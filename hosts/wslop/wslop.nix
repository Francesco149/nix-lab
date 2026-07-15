{ config, pkgs, lib, ... }:
{
  imports = [
    ../../modules/niri.nix
    ./backup.nix
  ];

  programs.dconf.enable = true;

  # beszel-agent is wired globally (modules/beszel.nix) for the lab's GPU/server
  # hosts and expects a secret at /var/lib/secrets/beszel-agent. wslop has no
  # such secret and no reason to report to beszel, so mask the unit here rather
  # than provision a credential it will never use. (Left failing since before
  # this host existed in beszel; see WORKDOC 2026-07-15.)
  services.beszel.agent.enable = lib.mkForce false;
  systemd.services.beszel-agent.enable = lib.mkForce false;

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

    # for the remote deploy trick to deploy faster
    git
    deploy-rs

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
