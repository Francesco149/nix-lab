{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;

  # serialise backup targets list to JSON
  targetsJson = pkgs.writeText "targets.json" (builtins.toJSON lab.backup.targets);

  backup-py = pkgs.writeText "cold-backup.py" (builtins.readFile ./backup/cold-backup.py);

  cold-backup = pkgs.writeShellScriptBin "cold-backup" ''
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          sanoid
          smartmontools
          zfs
          python3
        ]
      )
    }:$PATH"
    exec ${pkgs.python3}/bin/python3 ${backup-py} --targets ${targetsJson}
  '';
in
{
  environment.systemPackages = with pkgs; [
    cold-backup
    sanoid
    lzop
    mbuffer
    pv
    smartmontools
    zfs
    hdparm
  ];

  systemd.services.cold-backup = {
    description = "Cold storage backup cycle";
    after = [
      "zfs.target"
      "network.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${cold-backup}/bin/cold-backup";
      TimeoutStartSec = "20h";
    };
  };
  # the time machine courier restic-pushes its Win7/XP images into
  # gigavault/timemachine-restic over sftp as this backup user
  users.users.backup.openssh.authorizedKeys.keys = [ lab.ssh.pub.timemachine-restic ];

  programs.ssh.knownHosts = lab.ssh.cold-backup-known-hosts;
}
