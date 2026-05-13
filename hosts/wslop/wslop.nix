{ config, pkgs, ... }:
{
  imports = [
    ../../modules/niri.nix
  ];

  programs.dconf.enable = true;

  environment.variables = {
    GALLIUM_DRIVER = "d3d12";
    LD_LIBRARY_PATH = "/run/opengl-driver/lib";
  };

  environment.systemPackages = with pkgs; [
    weston
    nautilus
    zed-editor
    eog
    mpv

    (writeShellScriptBin "niri-start" ''
      # nested weston under WSLg using kiosk-shell.
      # kiosk-shell runs the program from -- args fullscreen, zero chrome.
      # --fullscreen asks WSLg to make the outer window borderless.
      set -eu

      if [ -z "''${XDG_RUNTIME_DIR:-}" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      fi

      if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
        if [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
          export WAYLAND_DISPLAY=wayland-0
        elif [ -S /mnt/wslg/runtime-dir/wayland-0 ]; then
          export WAYLAND_DISPLAY=/mnt/wslg/runtime-dir/wayland-0
        else
          echo "niri-start: cannot find Wayland display" >&2
          exit 1
        fi
      fi

      SOCKET="niri-weston-$$"

      exec weston \
        --socket="$SOCKET" \
        --width=1920 --height=1080 \
        --fullscreen \
        --shell=kiosk \
        -- \
        ${dbus}/bin/dbus-run-session ${niri}/bin/niri
    '')
  ];
}
