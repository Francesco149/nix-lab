{ pkgs, ... }:
{
  inherit pkgs;
  packages = with pkgs; [
    nix-output-monitor
    nvd
    nil
    nixd
  ];
}
