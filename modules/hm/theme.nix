{ pkgs, config, ... }:
let
  gtkTheme = {
    name = "Flat-Remix-GTK-Violet-Darkest";
    package = pkgs.flat-remix-gtk;
  };
  iconTheme = {
    name = "Flat-Remix-Violet-Dark";
    package = pkgs.flat-remix-icon-theme;
  };
in
{
  gtk = {
    enable = true;
    theme = gtkTheme;
    iconTheme = iconTheme;
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    gtk4.theme = gtkTheme;
  };

  qt = {
    enable = true;
    platformTheme.name = "gtk";
  };

  home.packages = with pkgs; [
    flat-remix-gtk
    flat-remix-icon-theme
  ];
}
