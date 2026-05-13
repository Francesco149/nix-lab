{ config, pkgs, ... }:
{
  imports = [
    ../../modules/niri.nix
  ];

  environment.systemPackages = with pkgs; [
    weston

    (writeShellScriptBin "niri-start" ''
      # nested weston under WSLg using kiosk-shell.
      # kiosk-shell runs the program from `--` args fullscreen, zero chrome.
      # --fullscreen asks WSLg to make the outer window borderless.
      set -eu

      if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
        echo "niri-start: WAYLAND_DISPLAY is not set. Is WSLg running?" >&2
        exit 1
      fi
      if [ -z "''${XDG_RUNTIME_DIR:-}" ]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      fi

      SOCKET="niri-weston-$$"

      # launch weston with kiosk-shell: fullscreen, no chrome.
      # the `--` program is the kiosk app — weston execs it with
      # the wayland display set to our socket.
      # when niri exits, weston exits.
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
