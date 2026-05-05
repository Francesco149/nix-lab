{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "lame";
  networking.hostId = "a73ec6f3"; # required for ZFS, generate with: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
  networking.networkmanager.enable = true;
  system.stateVersion = "25.11";
}
