{ config, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "headpats";
  wsl.useWindowsDriver = true;
  networking.hostName = "wslop";
  system.stateVersion = "25.11";
}
