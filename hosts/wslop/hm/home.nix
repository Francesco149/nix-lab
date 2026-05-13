{ ... }:
{
  imports = [
    ../../../modules/hm/fonts.nix
    ../../../modules/hm/alacritty.nix
    ../../../modules/hm/fuzzel.nix
    ../../../modules/hm/niri-config.nix
  ];

  home.stateVersion = "25.11";
}
