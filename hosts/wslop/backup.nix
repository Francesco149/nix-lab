# hosts/wslop/backup.nix
#
# manual cold-storage backup of the WSL guest rootfs and the windows host
# drives. WSL2 NAT drops subnet-directed broadcasts, so the guest cannot send
# WoL packets itself: wake+unlock is relayed through `cold-unlock` on code.
# data is pushed with rsync as root@cold (the interactive ssh keys are already
# authorized everywhere), so cold needs no extra setup. see docs/OPERATIONS.md.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;

  backup-py = pkgs.writeText "wslop-backup.py" (builtins.readFile ./backup/wslop-backup.py);

  # serialise backup settings from lab.nix to JSON for the Python script
  configJson = pkgs.writeText "wslop-backup.json" (builtins.toJSON lab.backup.wslop);

  wslop-backup = pkgs.writeShellScriptBin "wslop-backup" ''
    if [ "$(id -u)" -ne 0 ]; then
      exec sudo "$0" "$@"
    fi
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          openssh
          rsync
          python3
        ]
      )
    }:$PATH"
    exec ${pkgs.python3}/bin/python3 ${backup-py} \
      --relay   root@${lab.lan.code} \
      --cold-ip ${lab.lan.cold} \
      --config  ${configJson} \
      "$@"
  '';
in
{
  environment.systemPackages = [ wslop-backup ];

  programs.ssh.knownHosts = {
    code = {
      hostNames = [
        lab.lan.code
        "code"
      ];
      publicKey = lab.ssh.host.code;
    };
    cold = {
      hostNames = [
        lab.lan.cold
        "cold"
      ];
      publicKey = lab.ssh.host.cold;
    };
  };

  # the nightly orchestrator on code sshes in as backup and runs the backup
  # opportunistically when wslop happens to be up during the backup window
  users.users.backup = {
    isSystemUser = true;
    group = "backup";
    shell = "${pkgs.bash}/bin/bash";
    home = "/var/lib/backup";
    createHome = true;
    openssh.authorizedKeys.keys = [ lab.ssh.pub.unlock ];
  };
  users.groups.backup = { };

  security.sudo.extraRules = [
    {
      users = [ "backup" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/wslop-backup --no-poweroff";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
