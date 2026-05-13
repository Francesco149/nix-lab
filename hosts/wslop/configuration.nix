{ config, ... }:

{
  wsl.enable = true;
  networking.hostName = "wslop";
  system.stateVersion = "25.11";
}
