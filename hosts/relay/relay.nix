{
  config,
  lib,
  pkgs,
  ...
}:
{
  nut.deploy.host = config.lab.internet.relay;
  nut.dbus.implementation = "dbus";

  # on the relay only, tailscale needs to accept dns so we can see the home net
  # through the split dns configuration below. dns requests for home net things
  # are redirected to my home router.

  # we also advertise an exit node so if needed we can use the relay as a vpn.

  services.tailscale = {
    enable = true;
    extraUpFlags = [
      "--advertise-exit-node"
      "--login-server=https://${config.lab.domains.headscale}"
      "--accept-routes"
    ];
  };

  # this is what links everything together: headscale is a self-hosted tailscale
  # server. it estabilishes a private network between the mail server, the relay
  # and whichever of my machines I decide to run a tailscale client on and point
  # it at this server.

  # clients are assigned a special tailnet ip and can see eachother, as if on
  # the same lan, without having to open any inbound ports to the internet.

  services.headscale = {
    enable = true;
    port = config.lab.ports.headscale;
    settings = {
      database = {
        type = "sqlite3";
        sqlite.path = config.lab.headscale.db-path;
      };
      server_url = "https://${config.lab.domains.headscale}";
      listen_addr = "127.0.0.1:${toString config.lab.ports.headscale}";
      ip_prefixes = config.lab.tailnet.prefixes;
      noise.private_key_path = config.lab.headscale.noise.private-key-path;
      dns = {
        magic_dns = false;
        override_local_dns = false;
        nameservers = {
          split = {
            # use the home net router as a dns server for ips and domains
            # matching these rules. this will only query the vps for matching
            # domains. it will not send all dns through the vps this allows me
            # to see my home net as if I was there
            ${config.lab.domains.internal} = [ config.lab.lan.gateway ];
            ${config.lab.lan.zone} = [ config.lab.lan.gateway ];
          };
        };
      };
      # if there's serious routing/connectivity issues, the connection will go
      # through tailscale's DERP servers as a fallback.
      derp = {
        inherit (config.lab.derp) urls;
        auto_update_enabled = true;
        update_frequency = "24h";
      };
    };
  };

  # we send all mail through this relay so it comes from the trusted vps ip. it
  # is only accessible through tailscale.

  # we need to make sure it only listens on the tailnet ip so it doesn't
  # interfere with the public facing port for the actual mail server. we also
  # need to make sure it binds to the public ip for the outbound side

  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
  };

  services.postfix = {
    enable = true;
    settings.main = {
      myhostname = config.lab.domains.mail;
      # Keep setup commands such as postalias from failing when tailscaled
      # briefly removes the tailnet address during a deploy. The actual SMTP
      # listener is still bound to the tailnet address in master.cf below.
      inet_interfaces = "all";
      inet_protocols = "ipv4";
      mynetworks = config.lab.tailnet.prefixes;
      relay_domains = null;
      smtp_bind_address = config.lab.internet.relay;
    };
    settings.master.smtp_inet.name = lib.mkForce "${config.lab.tailnet.relay}:smtp";
  };

  # hs.headpats.uk's cert is issued via DNS-01 (cloudflare): relay's :80 is the
  # mail stream-proxy (and forwards the mail server's own HTTP-01 challenge), so
  # HTTP-01 can't be served here — which is why this cert silently stopped
  # renewing and expired 2026-05-27. Reuses the same cloudflare API token Caddy
  # uses on code; the env file holds CLOUDFLARE_DNS_API_TOKEN. Provision it with
  # the value from code's /var/lib/secrets/caddy (CLOUDFLARE_API_TOKEN).
  security.acme.certs.${config.lab.domains.headscale} = {
    dnsProvider = "cloudflare";
    environmentFile = "${config.lab.secrets.dir}/acme-cloudflare";
    group = config.services.nginx.group; # nginx (useACMEHost) must read the cert
  };

  # nginx is acting as a reverse proxy which routes all connections to their
  # destination. the stream proxy is great for tunneling ports over tailnet

  services.nginx = {
    enable = true;

    # this way the mail server at home is also able to do cert generation, but
    # on port 80 which we tunnel over.

    virtualHosts.${config.lab.domains.headscale} = {
      onlySSL = true;
      useACMEHost = config.lab.domains.headscale;

      # headscale wants to be the root location so we can't do something like
      # /headscale/ but we can do hs.domain.example
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.lab.ports.headscale}";

        # headscale uses websockets for the control protocol. we also have to
        # disable buffering for the websockets to work properly. set longer
        # timeouts so the tailscale connection doesn't die if it lags.

        proxyWebsockets = true;
        extraConfig = ''
          proxy_buffering off;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
          keepalive_timeout 3600s;
        '';
      };
    };

    # we don't need to open submission and imaps ports to the internet. we'll
    # access those at home only or through headscale.

    streamConfig = ''
      upstream mail_smtp {
        server ${config.lab.tailnet.mail}:${toString config.lab.ports.smtp-relay};
      }

      upstream mail_http {
        server ${config.lab.tailnet.mail}:${toString config.lab.ports.http};
      }

      server {
        listen ${config.lab.internet.relay}:${toString config.lab.ports.smtp-relay};
        proxy_pass mail_smtp;
        proxy_buffer_size 16k;
      }

      server {
        listen ${config.lab.internet.relay}:${toString config.lab.ports.http};
        proxy_pass mail_http;
      }
    '';
  };

  networking.firewall = {
    allowedTCPPorts = [
      config.lab.ports.smtp-relay
      config.lab.ports.http
      config.lab.ports.https
    ];
    allowedUDPPorts = [
      config.lab.ports-udp.headscale
    ];
  };

}
