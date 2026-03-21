{ config, ... }:
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

  services.postfix = {
    enable = true;
    settings.main = {
      myhostname = config.lab.domains.mail;
      inet_interfaces = config.lab.tailnet.relay;
      inet_protocols = "ipv4";
      mynetworks = config.lab.tailnet.prefixes;
      relay_domains = null;
      smtp_bind_address = config.lab.internet.relay;
    };
  };

  # if tailscale gos down, stop postfix. only start after tailscale goes up

  systemd.services.postfix = {
    after = [
      "tailscaled.service"
      "sys-subsystem-net-devices-tailscale0.device"
    ];
    wants = [ "tailscaled.service" ];
    requires = [ "sys-subsystem-net-devices-tailscale0.device" ];
  };

  # postfix-setup runs postalias which validates inet_interfaces — needs tailscale0 too
  systemd.services.postfix-setup = {
    after = [ "sys-subsystem-net-devices-tailscale0.device" ];
    requires = [ "sys-subsystem-net-devices-tailscale0.device" ];
  };

  # nginx is acting as a reverse proxy which routes all connections to their
  # destination. the stream proxy is great for tunneling ports over tailnet

  services.nginx = {
    enable = true;

    # port 80 is occupied by the stream proxy, so don't let the headscale vhost
    # also try to grab it, and ACME will sort itself out on 443.

    # this way the mail server at home is also able to do cert generation, but
    # on port 80 which we tunnel over.

    virtualHosts.${config.lab.domains.headscale} = {
      onlySSL = true;
      enableACME = true;

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
