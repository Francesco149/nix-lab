{ config, ... }:
{
  imports = [
    ./dockge.nix
    ./openvscode-server.nix
    ./cache.nix
  ];

  # enable other machines in the tailnet to see my home lan
  services.tailscale.extraUpFlags = [
    "--advertise-routes=10.0.10.0/24"
  ];

  # simple, beautiful agent based system monitor
  services.beszel.hub = {
    enable = true;
    port = config.lab.ports.beszel;
    host = "0.0.0.0";
  };
}
