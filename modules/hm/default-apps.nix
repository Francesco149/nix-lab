{ pkgs, ... }:
{
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = [ "org.gnome.Nautilus.desktop" ];
      "text/plain" = [ "dev.zed.Zed.desktop" ];
      "text/x-python" = [ "dev.zed.Zed.desktop" ];
      "text/x-nix" = [ "dev.zed.Zed.desktop" ];
      "image/png" = [ "org.gnome.eog.desktop" ];
      "image/jpeg" = [ "org.gnome.eog.desktop" ];
      "image/gif" = [ "org.gnome.eog.desktop" ];
      "image/svg+xml" = [ "org.gnome.eog.desktop" ];
      "image/webp" = [ "org.gnome.eog.desktop" ];
      "video/mp4" = [ "mpv.desktop" ];
      "video/webm" = [ "mpv.desktop" ];
      "video/x-matroska" = [ "mpv.desktop" ];
    };
  };

  home.sessionVariables = {
    EDITOR = "e";
    VISUAL = "e";
    MOZ_ENABLE_WAYLAND = "1";
    EGL_PLATFORM = "wayland";
    QT_QPA_PLATFORM = "wayland";
    GDK_BACKEND = "wayland";
    SDL_VIDEODRIVER = "wayland";
    ELECTRON_OZONE_PLATFORM_HINT = "wayland";
  };

  home.packages = with pkgs; [
    firefox
  ];
}
