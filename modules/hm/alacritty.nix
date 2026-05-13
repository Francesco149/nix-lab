{ osConfig, ... }:
let
  inherit (osConfig.lab) colors;
  c = colors;
in
{
  programs.alacritty = {
    enable = true;
    settings = {
      window = {
        dynamic_padding = true;
        decorations = "None";
        opacity = 0.95;
        padding = { x = 5; y = 5; };
      };
      font = {
        normal = {
          family = "PxPlus IBM VGA8";
          style = "Regular";
        };
        bold = {
          family = "PxPlus IBM VGA8";
          style = "Regular";
        };
        size = 12;
      };
      colors = {
        primary = {
          background = "#${c.base00}";
          foreground = "#${c.base05}";
        };
        normal = {
          black = "#${c.base00}";
          red = "#${c.base08}";
          green = "#${c.base0B}";
          yellow = "#${c.base0A}";
          blue = "#${c.base04}";
          magenta = "#${c.base0E}";
          cyan = "#${c.base0C}";
          white = "#${c.base05}";
        };
        bright = {
          black = "#${c.base01}";
          red = "#${c.base08}";
          green = "#${c.base0B}";
          yellow = "#${c.base0A}";
          blue = "#${c.base04}";
          magenta = "#${c.base0E}";
          cyan = "#${c.base0C}";
          white = "#${c.base07}";
        };
      };
      cursor = {
        style.shape = "Beam";
      };
      selection.save_to_clipboard = true;
    };
  };
}
