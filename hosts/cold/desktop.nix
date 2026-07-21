# KDE Plasma desktop on cold, driven remotely over Moonlight.
#
# cold is a headless box in a rack: there is no keyboard on it and its HDMI port
# may or may not have a live display on the other end. So the session is built to
# come up on its own, with no human at the machine:
#
#   sddm (autologin) -> plasma 6 (wayland) -> graphical-session.target -> sunshine
#
# sunshine's systemd user unit is `partOf` graphical-session.target (see the
# nixpkgs module), which is exactly why the autologin matters — without a logged
# in graphical session there is nothing for Moonlight to attach to.

{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;
in
{
  # ── GPU ──────────────────────────────────────────────────────────────────
  # cold's CPU is a Ryzen 5 5600G: an APU, so there IS a Vega iGPU here even
  # though the box was built as a NAS. That gives us hardware GL for the Plasma
  # session and, more importantly, VAAPI video encode for Sunshine — a software
  # x264 stream would otherwise eat most of the 12 threads while backups run.
  # VAAPI on AMD comes from mesa's radeonsi, which hardware.graphics already
  # pulls in — no extraPackages needed here. (The libva-vdpau-driver /
  # libvdpau-va-gl pair that shows up in a lot of guides is a VDPAU->VAAPI shim
  # for legacy NVIDIA and is actively wrong on this box.) `vainfo` from
  # libva-utils is in systemPackages below to verify the encoder is really there.
  hardware.graphics.enable = true;

  services.xserver.videoDrivers = [ "amdgpu" ];

  # Load amdgpu in the initrd. Early KMS matters here because the forced-connector
  # kernel param below is applied when the driver binds: leaving it to late module
  # load means the console comes up on simpledrm first and the mode is applied to
  # the wrong device.
  boot.initrd.kernelModules = [ "amdgpu" ];

  # Synthesise a 1080p display on HDMI-A-1.
  #
  # Whatever is on cold's HDMI port reports `connected` but hands over NO EDID,
  # so the kernel falls back to a generic mode list that tops out at 1366x768 —
  # and that is what KWin, and therefore Moonlight, ends up streaming. A bare
  # `video=HDMI-A-1:1920x1080@60e` does NOT fix it: the forced mode never makes
  # it into the probed mode list (verified on the box — kscreen-doctor still
  # reported 1366x768 as the only preferred mode).
  #
  # Feeding the connector a generated EDID does fix it, because now there is a
  # real 1080p60 timing to prefer. `mode = "e"` additionally forces the connector
  # enabled, so the session survives the display being unplugged or powered off
  # — otherwise KWin loses its only output and the stream drops.
  #
  # The modeline is the standard CEA-861 1080p60 timing. Change HDMI-A-1 if the
  # cable ever moves; DP-1 and HDMI-A-2 are the other two connectors.
  hardware.display = {
    edid.modelines."1920x1080_60" = "148.50 1920 2008 2052 2200 1080 1084 1089 1125 +hsync +vsync";
    outputs."HDMI-A-1" = {
      edid = "1920x1080_60.bin";
      mode = "e";
    };
  };

  # ── session ──────────────────────────────────────────────────────────────
  services.displayManager = {
    sddm = {
      enable = true;
      wayland.enable = true;
    };
    autoLogin = {
      enable = true;
      user = "headpats";
    };
    defaultSession = "plasma";
  };

  services.desktopManager.plasma6.enable = true;

  # Disable the automatic screen lock. `headpats` autologins with no password
  # set, so a lock screen is a dead end: Moonlight would show a prompt that
  # cannot be satisfied, and recovering means SSHing in to kill kscreenlocker.
  # Nothing is lost security-wise — reaching the session at all requires pairing
  # with Sunshine first, and cold is not physically accessible.
  environment.etc."xdg/kscreenlockerrc".text = ''
    [Daemon]
    Autolock=false
    LockOnResume=false
  '';

  # ── audio ────────────────────────────────────────────────────────────────
  # Sunshine captures whatever the default sink is. On a box whose only real
  # sinks are HDMI (which disappears when the display sleeps) and unused onboard
  # analog, that default can vanish underneath the stream, so we pin a null sink
  # and make it the fallback. Audio then keeps working with nothing plugged in.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    extraConfig.pipewire."99-cold-null-sink" = {
      "context.objects" = [
        {
          factory = "adapter";
          args = {
            "factory.name" = "support.null-audio-sink";
            "node.name" = "moonlight-sink";
            "node.description" = "Moonlight (virtual)";
            "media.class" = "Audio/Sink";
            "audio.position" = [
              "FL"
              "FR"
            ];
            "priority.session" = 2000; # outrank HDMI so it stays the default
          };
        }
      ];
    };
  };

  # ── sunshine ─────────────────────────────────────────────────────────────
  services.sunshine = {
    enable = true;
    autoStart = true;

    # CAP_SYS_ADMIN is what lets Sunshine grab the screen through DRM/KMS, which
    # is the capture path on a Wayland session. Without it capture fails on
    # Plasma 6 even though the unit starts fine.
    capSysAdmin = true;

    # We open the ports ourselves from lab.ports below so every hole in this
    # host's firewall is greppable in one place, the same way lame does it.
    openFirewall = false;

    settings = {
      sunshine_name = "cold";

      # The default (`pc`) only accepts web UI requests originating from
      # localhost. cold has no local browser, so leaving this alone means the
      # pairing UI is unreachable and the host can never be paired. `lan` is the
      # narrowest value that still lets us reach it from the workstation.
      origin_web_ui_allowed = "lan";
    };
  };

  # NOTE: setting `settings` above makes sunshine.conf declarative, so the web UI
  # can no longer change these. Pairing and credentials are NOT part of that file
  # — they live in the user's state dir — so pairing from Moonlight still works
  # and survives redeploys.

  networking.firewall.allowedTCPPorts = with lab.ports; [
    sunshine-https
    sunshine-http
    sunshine-web
    sunshine-rtsp
  ];
  networking.firewall.allowedUDPPorts = with lab.ports-udp; [
    sunshine-video
    sunshine-control
    sunshine-audio
    sunshine-mic
    mdns
  ];

  # ── desktop apps ─────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    firefox
    kdePackages.filelight # what is eating the pool
    kdePackages.kate
    kdePackages.ark
    mpv
    vlc

    # `vainfo` — confirms the Vega iGPU is exposing VAAPI *encode* entrypoints
    # (look for VAEntrypointEncSlice on H264/HEVC). If Moonlight is soft and the
    # CPU is pinned, this is the first thing to check: Sunshine silently falls
    # back to software x264 when VAAPI init fails.
    libva-utils
  ];

  # Plasma ships its own terminal/file manager, so we deliberately do NOT pull in
  # modules/hm/{alacritty,fuzzel,niri-config,theme,default-apps}.nix here: those
  # are the niri/wayland-standalone stack and their Qt/GTK and *_BACKEND settings
  # actively fight a Plasma session.
}
