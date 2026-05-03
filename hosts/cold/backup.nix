{ pkgs, lib, ... }:
let
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
    exec ${pkgs.python3}/bin/python3 ${backup-py}
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
  programs.ssh.knownHosts = {
    "proxmox".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIrny+0hMgPXGTcMNcZczDVYl+LaQONSrVPGRiogSR9q root@proxmox";
  };
}
