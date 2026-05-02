{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;
  iface = "enp4s0";
in
{
  imports = [
    ./backup.nix
  ];

  # ── ZFS ─────────────────────────────────────────────────────────────────
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  # import both pools at boot but do NOT auto-mount encrypted datasets
  # the unlock service does that after receiving the passphrase
  boot.zfs.extraPools = [
    "gigavault"
    "gaijin"
  ];
  boot.zfs.requestEncryptionCredentials = false; # we handle this ourselves

  services.zfs.autoScrub = {
    enable = true;
    interval = "monthly";
    pools = [ "gigavault" ];
  };

  # ── WoL persistence ──────────────────────────────────────────────────────
  # WoL is enabled in UEFI but the kernel resets it after boot; keep it on
  networking.interfaces.${iface}.wakeOnLan.enable = true;
  # alternatively if the above NixOS option doesn't work on your NIC:
  # systemd.services.wol-enable = {
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig.ExecStart = "${pkgs.ethtool}/bin/ethtool -s ${iface} wol g";
  # };

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
      "-a"                          # monitor all SMART attributes
      "-o on"                       # enable automatic offline data collection
      "-S on"                       # enable attribute autosave
      "-n standby,24"               # skip check if in standby (max 24 non-standby wakeups/day for checks)
      "-W 4,50,55"                  # temp diff>=4 logs, >=50 warns, >=55 critical
      "-s (S/../../6/02|L/../../1/03)"  # short test Sat 2am, long Mon 3am
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

  # ── SFTP access for syncoid and rclone ───────────────────────────────────
  users.users.backup = {
    isSystemUser = true;
    group = "backup";
    shell = "${pkgs.bash}/bin/bash";
    home = "/var/lib/backup";
    createHome = true;
    openssh.authorizedKeys.keys = lab.ssh.unlock-authorized-keys;
  };
  users.groups.backup = { };

  # backup user needs to write to ZFS datasets
  # set this after the pools are mounted:
  # zfs allow -u backup send,receive,mount,create,destroy gigavault
  # zfs allow -u backup send,receive,mount,create,destroy gaijin

  # ── unlock service (post-boot, run by orchestrator) ──────────────────────
  security.sudo.extraRules = [{
    users = [ "backup" ];
    commands = [
      { command = "/run/current-system/sw/bin/systemctl start cold-backup.service";
        options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/shutdown -h now";
        options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/zfs load-key gigavault";
        options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/zfs load-key gaijin";
        options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/zfs mount -a";
        options = [ "NOPASSWD" ]; }
    ];
  }];

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
