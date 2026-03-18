{ config, ... }:
{
  imports = [
    ./dockge.nix
    ./openvscode-server.nix
    ./cache.nix
    ./caddy.nix
    ./roundcube.nix
  ];

  # enable other machines in the tailnet to see my home lan
  services.tailscale.extraUpFlags = [
    "--advertise-routes=${config.lab.lan.mask}"
  ];

  # simple, beautiful agent based system monitor
  services.beszel.hub = {
    enable = true;
    port = config.lab.ports.beszel;
    host = "127.0.0.1";
  };
}
