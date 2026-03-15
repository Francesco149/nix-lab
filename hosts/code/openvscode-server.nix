{ pkgs, config, ... }:
{
  services.openvscode-server = {
    enable = true;
    # required for docker to be able to see us through
    # the dockerhost interface.
    host = "0.0.0.0";
    port = config.lab.ports.openvscode-server-internal;
    withoutConnectionToken = true; # auth handled by authentik
    user = "root";
    group = "root";
    extraPackages = with pkgs; [
      git
      nil # nix language server
      nixd # also a nix lang server
      nixfmt
      statix # linter
      caddy # for caddyfile formatting
      docker # container management extensions
      direnv
      nix-direnv
      fish-lsp
      prettier # formatter for js, json, ts and others
      python3
      python3Packages.pip
      ruff # py linter
      ty # py lang server. should ship with the ext but just in case
      neovim
    ];
  };
}
