{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    niri
    fuzzel
    wayland-utils
    wl-clipboard
    xwayland-satellite
  ];
}
