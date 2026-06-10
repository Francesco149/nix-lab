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
  ];

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
