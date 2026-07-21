{ config, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "headpats";
  wsl.useWindowsDriver = true;
  networking.hostName = "wslop";
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";
}
