{ ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  networking.hostName = "code";
  networking.networkmanager.enable = true;

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 1024 * 8;
    }
  ];

  system.stateVersion = "25.11";

}
