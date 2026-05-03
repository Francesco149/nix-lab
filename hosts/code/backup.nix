# hosts/code/backup.nix
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;
  secrets = lab.secrets.dir;
  sshKey = "${secrets}/cold-unlock-key";
  ageKey = "${secrets}/cold-age-key";

  unlock-py = pkgs.writeText "cold-unlock.py" (builtins.readFile ./backup/cold-unlock.py);
  backup-py = pkgs.writeText "cold-backup.py" (builtins.readFile ./backup/cold-backup.py);

  # substitute nix store paths and lab values into the python scripts
  cold-unlock = pkgs.writeShellScriptBin "cold-unlock" ''
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          openssh
          age
          wakeonlan
          netcat-openbsd
          python3
        ]
      )
    }:$PATH"
    exec ${pkgs.python3}/bin/python3 ${unlock-py} \
      --ssh-key   ${sshKey} \
      --age-key   ${ageKey} \
      --secrets   ${secrets} \
      --cold-ip   ${lab.lan.cold} \
      --cold-mac  ${lab.mac.cold} \
      --initrd-ip ${lab.lan.cold-unlock} \
      --ssh-port  ${toString lab.ports.ssh} \
      --initrd-port ${toString lab.ports.ssh-initrd}
  '';

  cold-backup = pkgs.writeShellScriptBin "cold-backup" ''
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          openssh
          age
          wakeonlan
          netcat-openbsd
          python3
        ]
      )
    }:$PATH"
    exec ${pkgs.python3}/bin/python3 ${backup-py} \
      --ssh-key    ${sshKey} \
      --cold-ip    ${lab.lan.cold} \
      --unlock-bin ${cold-unlock}/bin/cold-unlock
  '';

in
{
  environment.systemPackages = [
    cold-unlock
    cold-backup
  ];

  programs.ssh.knownHosts = {
    "cold".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqjHsgUF2s+MRJqSvyB14w05NXVRoaimZjPyu/S3NYX root@nixos";
    "cold-unlock".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOSXuJ592PTKU3Kxo8vcBT8VOnkEXBJVcEjk9vMx1VKx cold-initrd";
  };

  systemd.services.cold-backup = {
    description = "Cold storage backup cycle";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${cold-backup}/bin/cold-backup";
      TimeoutStartSec = "20h";
      Restart = "no";
    };
  };

  systemd.timers.cold-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 01:30:00";
      Persistent = false;
      Unit = "cold-backup.service";
    };
  };
}
