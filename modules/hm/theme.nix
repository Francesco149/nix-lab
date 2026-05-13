{ osConfig, pkgs, config, ... }:
let
  gtkTheme = {
    name = "Flat-Remix-GTK-Cyan-Darkest";
    package = pkgs.flat-remix-gtk;
  };
  iconTheme = {
    name = "Flat-Remix-Cyan-Dark";
    package = pkgs.flat-remix-icon-theme;
  };
in
{
  gtk = {
    enable = true;
    theme = gtkTheme;
    iconTheme = iconTheme;
    gtk4.theme = gtkTheme;
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
  };

  dconf = {
    enable = true;
    settings."org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      monospace-font-name = "JetBrainsMono Nerd Font Semi-Bold 12";
    };
  };

  home.packages = with pkgs; [
    cantarell-fonts
    flat-remix-gtk
    flat-remix-icon-theme
  ];
}
