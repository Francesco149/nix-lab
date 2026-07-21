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
  imports = [
    ./backup.nix
    ./desktop.nix
    ./torrents.nix
    ./archive.nix
    ./downloads.nix
  ];

  # ── interactive user ─────────────────────────────────────────────────────
  # cold used to be deploy-only. It now has a Plasma session (desktop.nix) that
  # needs a real user to autologin as, and that same user is who you land on when
  # you ssh in to drive the torrent stack.
  users.users.headpats = {
    isNormalUser = true;
    description = "headpats";
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video" # kms/drm access for the session
      "render" # vaapi encode for sunshine
      "input" # read existing input devices
      # THE one that makes Moonlight's mouse/keyboard work. hardware.uinput
      # (enabled by services.sunshine) ships /dev/uinput as root:uinput 0660, so
      # without membership here Sunshine starts fine and streams fine but logs
      # "Unable to create virtual mouse: Permission denied" — you get a picture
      # you cannot click on. `input` is NOT a substitute; it is a different gid.
      "uinput"
      "audio"
      "qbittorrent" # read/write the torrent inbox without sudo
    ];
    openssh.authorizedKeys.keys = lab.ssh.authorized-keys;
  };

  # ── keep root on bash ────────────────────────────────────────────────────
  # modules/interactive.nix sets `users.defaultUserShell = pkgs.fish`, and root
  # inherits it (nixpkgs declares root's shell as mkDefault defaultUserShell).
  # On code and lame that is harmless. cold is different: it is the lab's backup
  # TARGET, and sshd runs every non-interactive remote command through the login
  # shell. root@cold is the receiving end of wslop's rsync push, and the `zfs`
  # calls that create and snapshot datasets around it — a data path, not an
  # operator convenience.
  #
  # Nothing in the repo would actually break today (every remote command is a
  # simple one-liner, and the `backup` user already pins bash in
  # modules/backup-target.nix), but the failure mode if something ever does is
  # silently corrupted backups rather than a visible error. Not worth trading for
  # a nicer root prompt: log in as headpats to get fish.
  users.users.root.shell = pkgs.bash;

  # /tmp/stay (cold-unlock --stay) suppresses the auto-shutdown after backups.
  # /tmp lives on the rootfs, so without this a stay file outlives the manual
  # session it was meant for and disables auto-shutdown forever (a stale one
  # from 2026-05-06 was doing exactly that).
  boot.tmp.cleanOnBoot = true;

  # ── ZFS, WoL, remote unlock ──────────────────────────────────────────────
  nut.initrd-unlock.iface = "enp4s0";
  nut.zfs.pools = [
    "gigavault"
    "gaijin"
  ];

  # ── SMART monitoring ─────────────────────────────────────────────────────
  services.smartd = {
    enable = true;
    autodetect = true;

    notifications.mail = {
      enable = true;
      recipient = config.lab.mail.main.addr;
      # sender defaults to "root", fine to leave
      # mailer defaults to sendmail wrapper, which you have via postfix
    };

    # notifications.mail handling is injected by the module automatically —
    # do NOT put -m or -M exec in the defaults string, the module does that

    defaults.monitored = lib.concatStringsSep " " [
      "-a" # monitor all SMART attributes
      "-o on" # enable automatic offline data collection
      "-S on" # enable attribute autosave
      "-n standby,24" # skip check if in standby (max 24 non-standby wakeups/day for checks)
      "-W 4,50,55" # temp diff>=4 logs, >=50 warns, >=55 critical
      "-s (S/../../6/02|L/../../1/03)" # short test Sat 2am, long Mon 3am
    ];
  };

  # ── HDD spin-down: be conservative with He8 helium drives ────────────────
  # Don't use hdparm -S aggressive standby — helium drives tolerate spin cycles
  # less well. Let the machine power off entirely between backup windows instead.
  # Only use standby if the machine idles for extended periods unexpectedly.
  powerManagement.enable = false; # no aggressive power management
  services.udev.extraRules = ''
    # disable APM on all SATA spinning rust (He8s)
    ACTION=="add", SUBSYSTEM=="block", KERNEL=="sd[a-j]", \
      RUN+="${pkgs.hdparm}/bin/hdparm -B 254 -S 0 /dev/%k"
  '';

  # backup user needs to write to ZFS datasets
  # set this after the pools are mounted:
  # zfs allow -u backup send,receive,mount,create,destroy gigavault
  # zfs allow -u backup send,receive,mount,create,destroy gaijin

  # ── backup service (post-boot, run by orchestrator) ──────────────────────
  security.sudo.extraRules = [
    {
      users = [ "backup" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/systemctl start cold-backup.service";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  environment.systemPackages = with pkgs; [
    zfs
    hdparm
    smartmontools

    # syncoid + compression dependencies
    sanoid
    lzop
    mbuffer
    pv
  ];
}
