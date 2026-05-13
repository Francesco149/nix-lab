{ ... }:
{
  imports = [
    ../../../modules/hm/fonts.nix
    ../../../modules/hm/alacritty.nix
    ../../../modules/hm/fuzzel.nix
    ../../../modules/hm/niri-config.nix
    ../../../modules/hm/theme.nix
    ../../../modules/hm/default-apps.nix
  ];

  home.stateVersion = "25.11";
}
