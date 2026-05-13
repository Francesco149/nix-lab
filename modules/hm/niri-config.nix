{ osConfig, pkgs, ... }:
let
  inherit (osConfig.lab) colors;
  c = colors;
  activeColor = "#${c.base0D}";
  inactiveColor = "#${c.base01}";
in
{
  xdg.configFile."niri/config.kdl".text = ''
    // niri configuration — colors from lab.nix

    input {
      keyboard {
        xkb {
          layout "us"
          options "caps:escape"
        }
      }
    }

    layout {
      gaps 8

      focus-ring {
        on
        active-color "${activeColor}"
        inactive-color "${inactiveColor}"
        width 2
      }

      border {
        on
        active-color "${activeColor}"
        inactive-color "${inactiveColor}"
        width 2
      }

      preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
      }
    }

    binds {
      Mod+Return  { spawn "${pkgs.alacritty}/bin/alacritty"; }
      Mod+D       { spawn "${pkgs.fuzzel}/bin/fuzzel"; }
      Mod+Q       { close-window; }

      Mod+H { focus-column-left; }
      Mod+J { focus-window-down; }
      Mod+K { focus-window-up; }
      Mod+L { focus-column-right; }

      Mod+Ctrl+H { focus-monitor-left; }
      Mod+Ctrl+L { focus-monitor-right; }

      Mod+Shift+H { move-column-left; }
      Mod+Shift+J { move-window-down; }
      Mod+Shift+K { move-window-up; }
      Mod+Shift+L { move-column-right; }

      Mod+Home      { focus-column-first; }
      Mod+End       { focus-column-last; }
      Mod+Shift+Home { move-column-to-first; }
      Mod+Shift+End  { move-column-to-last; }

      Mod+Shift+F { maximize-column; }
      Mod+F       { fullscreen-window; }

      Mod+R       { switch-preset-column-width; }
      Mod+Shift+R { reset-window-height; }

      Mod+1 { focus-workspace 1; }
      Mod+2 { focus-workspace 2; }
      Mod+3 { focus-workspace 3; }
      Mod+4 { focus-workspace 4; }
      Mod+5 { focus-workspace 5; }
      Mod+6 { focus-workspace 6; }
      Mod+7 { focus-workspace 7; }
      Mod+8 { focus-workspace 8; }
      Mod+9 { focus-workspace 9; }

      Mod+Shift+1 { move-column-to-workspace 1; }
      Mod+Shift+2 { move-column-to-workspace 2; }
      Mod+Shift+3 { move-column-to-workspace 3; }
      Mod+Shift+4 { move-column-to-workspace 4; }
      Mod+Shift+5 { move-column-to-workspace 5; }
      Mod+Shift+6 { move-column-to-workspace 6; }
      Mod+Shift+7 { move-column-to-workspace 7; }
      Mod+Shift+8 { move-column-to-workspace 8; }
      Mod+Shift+9 { move-column-to-workspace 9; }
    }

    // run as a nested session under WSLg/Wayland
    prefer-no-csd

    spawn-at-startup "${pkgs.alacritty}/bin/alacritty"
  '';
}
