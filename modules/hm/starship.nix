{ osConfig, ... }:
let
  inherit (osConfig.lab) colors;
in
{
  programs.starship = {
    enable = true;
    enableFishIntegration = true;

    settings = fromTOML (
      builtins.readFile ./starship.toml
    );
  };
}
