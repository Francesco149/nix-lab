{ pkgs, ... }:
{
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "en_US.UTF-8";
  programs.fish.enable = true;
  users.users.root.shell = pkgs.fish;
  security.sudo.wheelNeedsPassword = false;
}
