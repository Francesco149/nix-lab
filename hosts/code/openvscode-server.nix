{ pkgs, ... }:
{
  services.openvscode-server = {
    enable = true;
    host = "0.0.0.0";
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
