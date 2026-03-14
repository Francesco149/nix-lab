# system-wide config for machines that I actually use interactively. these don't
# need to be included on servers that I only ever remotely deploy to and almost
# never ssh into to use the shell interactively.

{ pkgs, ... }:
{
  programs.fish.enable = true;
  users.users.root.shell = pkgs.fish;
  security.sudo.wheelNeedsPassword = false;
}
