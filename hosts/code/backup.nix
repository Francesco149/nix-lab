# hosts/code/backup.nix
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;
  sshKey = lab.secrets.ssh.unlock;
  ageKey = lab.secrets.age.unlock;
  secrets = lab.secrets.dir;

  unlock-py = pkgs.writeText "cold-unlock.py" (builtins.readFile ./backup/cold-unlock.py);
  backup-py = pkgs.writeText "cold-backup.py" (builtins.readFile ./backup/cold-backup.py);

  # serialise the unlockables attrset to JSON for the Python script
  unlockablesJson = pkgs.writeText "unlockables.json" (builtins.toJSON lab.unlockables);

  # serialise backup targets list to JSON
  targetsJson = pkgs.writeText "targets.json" (builtins.toJSON lab.backup.targets);

  # per-host IPs and MACs from lab.nix
  hostMetaJson = pkgs.writeText "host-meta.json" (
    builtins.toJSON (
      lib.mapAttrs (host: _: {
        ip = lab.lan.${host};
        initrd-ip = lab.lan."${host}-unlock";
        mac = lab.mac.${host};
      }) lab.unlockables
    )
  );

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
      --ssh-key      ${sshKey} \
      --age-key      ${ageKey} \
      --secrets      ${secrets} \
      --unlockables  ${unlockablesJson} \
      --host-meta    ${hostMetaJson} \
      --ssh-port     ${toString lab.ports.ssh} \
      --initrd-port  ${toString lab.ports.ssh-initrd} \
      "$@"
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
      --ssh-key     ${sshKey} \
      --cold-ip     ${lab.lan.cold} \
      --unlock-bin  ${cold-unlock}/bin/cold-unlock \
      --unlockables ${unlockablesJson} \
      --host-meta   ${hostMetaJson} \
      --targets     ${targetsJson} \
      --wslop-addr  ${lab.tailnet.wslop}
  '';

  tm-orch-py = pkgs.writeText "tm-backup.py" (builtins.readFile ./backup/tm-backup.py);

  # weekly: wake cold + the time machine courier, run the courier's image backup,
  # then power both back down.
  tm-backup-cycle = pkgs.writeShellScriptBin "tm-backup-cycle" ''
    export PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          openssh
          wakeonlan
          netcat-openbsd
          python3
        ]
      )
    }:$PATH"
    exec ${pkgs.python3}/bin/python3 ${tm-orch-py} \
      --ssh-key    ${sshKey} \
      --unlock-bin ${cold-unlock}/bin/cold-unlock \
      --tm-addr    ${lab.lan.timemachine} \
      --tm-mac     ${lab.mac.timemachine} \
      --cold-addr  ${lab.lan.cold} \
      "$@"
  '';

in
{
  environment.systemPackages = [
    cold-unlock
    cold-backup
    tm-backup-cycle
  ];

  # cold pub key (backup) + all initrd pub keys (unlocks)
  programs.ssh.knownHosts =
    lib.mapAttrs' (
      host: _:
      lib.nameValuePair host {
        hostNames = [
          lab.lan.${host}
          host
        ];
        publicKey = lab.ssh.host.${host};
      }
    ) lab.unlockables
    // lib.mapAttrs' (
      host: _:
      lib.nameValuePair "${host}-unlock" {
        hostNames = [
          "[${lab.lan."${host}-unlock"}]:${toString lab.ports.ssh-initrd}"
          "${host}-unlock"
        ];
        publicKey = lab.ssh.host."${host}-unlock";
      }
    ) lab.unlockables
    // {
      # wslop is pushed-to over the tailnet, not an unlockable
      wslop = {
        hostNames = [
          lab.tailnet.wslop
          "wslop"
        ];
        publicKey = lab.ssh.host.wslop;
      };
      # the time machine courier: woken weekly, ssh'd into to run tm-backup
      timemachine = {
        hostNames = [
          "timemachine"
          lab.lan.timemachine
        ];
        publicKey = lab.ssh.host.timemachine;
      };
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

  # weekly image backup of the Win7/XP time machine to cold (Sunday, clear of the
  # nightly syncoid window; tm-backup-cycle re-unlocks cold idempotently anyway).
  systemd.services.tm-backup = {
    description = "Time Machine (Win7/XP) weekly image backup";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${tm-backup-cycle}/bin/tm-backup-cycle";
      TimeoutStartSec = "12h";
      Restart = "no";
    };
  };

  systemd.timers.tm-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 04:00:00";
      Persistent = false;
      Unit = "tm-backup.service";
    };
  };
}
