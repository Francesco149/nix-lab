{
  imports = [
    ./dockge.nix
    ./openvscode-server.nix
  ];

  # enable other machines in the tailnet to see my home lan
  services.tailscale.extraUpFlags = [
    "--advertise-routes=10.0.10.0/24"
  ];
}
