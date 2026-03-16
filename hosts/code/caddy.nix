{ pkgs, config, ... }:
let
  p = config.lab.ports;
in
{
  services.caddy = {
    enable = true;

    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.3" ];
      hash = "sha256-bL1cpMvDogD/pdVxGA8CAMEXazWpFDBiGBxG83SmXLA=";
    };

    globalConfig = ''
      acme_dns cloudflare {$CLOUDFLARE_API_TOKEN}
    '';

    extraConfig = ''
      (authentik) {
        forward_auth localhost:${toString p.authentik} {
          uri /outpost.goauthentik.io/auth/caddy
          copy_headers X-Authentik-Username X-Authentik-Groups
        }
      }
    '';

    virtualHosts."isp.box.headpats.uk".extraConfig = ''
      reverse_proxy isp.soy {
        header_up Host "192.168.1.1"
      }
    '';

    virtualHosts."sense.box.headpats.uk".extraConfig = ''
      reverse_proxy https://uwusense.soy:8443 {
        transport http {
          tls_insecure_skip_verify
          versions 1.1
        }
      }
    '';

    virtualHosts."gear.box.headpats.uk".extraConfig = ''
      reverse_proxy netgear.soy
    '';

    virtualHosts."fritz.box.headpats.uk".extraConfig = ''
      reverse_proxy fritzbox.soy
    '';

    virtualHosts."dock.box.headpats.uk".extraConfig = ''
      import authentik
      reverse_proxy localhost:${toString p.dockge}
    '';

    virtualHosts."auth.box.headpats.uk".extraConfig = ''
      reverse_proxy localhost:${toString p.authentik}
    '';

    virtualHosts."prox.box.headpats.uk".extraConfig = ''
      reverse_proxy https://proxmox.soy:8006 {
        transport http {
          tls_insecure_skip_verify
        }
      }
    '';

    virtualHosts."img.box.headpats.uk".extraConfig = ''
      reverse_proxy localhost:${toString p.immich}
    '';

    virtualHosts."hw.box.headpats.uk".extraConfig = ''
      reverse_proxy localhost:${toString p.beszel} {
        flush_interval -1
      }
    '';

    virtualHosts."mail.box.headpats.uk".extraConfig = ''
      @worker {
        path /webdav/*
      }
      reverse_proxy @worker localhost:${toString p.kurrier-dav}
      reverse_proxy localhost:${toString p.kurrier}
    '';

    virtualHosts."code.box.headpats.uk".extraConfig = ''
      import authentik
      reverse_proxy localhost:${toString p.openvscode-server} {
        transport http {
          read_buffer 0
        }
        flush_interval -1
      }
    '';

    virtualHosts."cache.box.headpats.uk".extraConfig = ''
      reverse_proxy localhost:${toString p.cache}
    '';

    virtualHosts."rack.box.headpats.uk".extraConfig = ''
      import authentik
      reverse_proxy localhost:${toString p.rackpeek}
    '';
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = [ "${config.lab.secrets.dir}/caddy" ];

  networking.firewall.allowedTCPPorts = [
    p.http
    p.https
  ];
}
