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

  # monitor ui for my funny ai chatbot's state
  services.lurk-monitor = {
    enable = true;
    port = config.lab.ports.lurk-monitor;
    host = "127.0.0.1";
    baseDir = "/var/lib/shigebot"; # UPDATE THIS

    # CRITICAL: SQLite WAL mode creates .wal and .shm files dynamically.
    # To ensure the monitor can read them, run the monitor as the same
    # NixOS user that executes your chat bot.
    user = "shigebot";
  };
}
