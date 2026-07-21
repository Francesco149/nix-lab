{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  shigebotPackage =
    inputs.shigebot.packages.${pkgs.stdenv.hostPlatform.system}.default.overridePythonAttrs
      (old: {
        # The input instantiates nixpkgs without the host overlays. Replace its
        # yt-dlp dependency so the temporary inline-snapshot workaround applies.
        dependencies =
          builtins.filter (dependency: lib.getName dependency != "yt-dlp") old.dependencies
          ++ [ pkgs.python312Packages.yt-dlp ];
      });
in
{
  imports = [
    ./dockge.nix
    ./openvscode-server.nix
    ./cache.nix
    ./caddy.nix
    ./roundcube.nix
    ./backup.nix
    ./gcal-emu.nix
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

  services.grammar-helper = {
    enable = true;
    host = "127.0.0.1";
    port = config.lab.ports.grammar-helper;
    envFile = "/var/lib/secrets/shigebot-env";
  };

  services.shigebot = {
    enable = true;
    package = shigebotPackage;
    configFile = ./shigebot.toml;
    environmentFile = "/var/lib/secrets/shigebot-env";
  };
}
