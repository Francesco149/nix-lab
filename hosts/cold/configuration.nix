{ ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "cold";
  networking.hostId = "44463c12";
  networking.networkmanager.enable = true;

  system.stateVersion = "25.11";
}
