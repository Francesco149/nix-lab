{ osConfig, ... }:
let
  inherit (osConfig.lab) colors;
  palette = {
    base03 = "#${colors.base00}";
    base02 = "#${colors.base01}";
    base01 = "#${colors.base02}";
    base00 = "#${colors.base03}";
    base0 = "#${colors.base04}";
    base1 = "#${colors.base05}";
    base2 = "#${colors.base06}";
    base3 = "#${colors.base07}";
    yellow = "#${colors.base0A}";
    orange = "#${colors.base09}";
    red = "#${colors.base08}";
    magenta = "#${colors.base0E}";
    violet = "#${colors.base0D}";
    blue = "#${colors.base0D}";
    cyan = "#${colors.base0C}";
    green = "#${colors.base0B}";
  };
in
{
  programs.starship = {
    enable = true;
    enableFishIntegration = true;

    settings = (fromTOML (builtins.readFile ./starship.toml)) // {
      palettes.chicago95 = palette;
    };
  };
}
