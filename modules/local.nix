# anything that is common to all machines on my home lan goes here

{ config, ... }:
{
  # use local package cache instead of nixos
  nix.settings.substituters = [ "https://${config.lab.domains.nix-cache}" ];
}
