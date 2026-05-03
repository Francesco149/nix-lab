# modules/cold-unlock.nix
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

  cold-unlock = pkgs.writeShellScriptBin "cold-unlock" ''
    set -euo pipefail
    PATH="${
      lib.makeBinPath (
        with pkgs;
        [
          openssh
          age
          wakeonlan
          netcat-openbsd
        ]
      )
    }:$PATH"

    log() { echo "[$(date -Iseconds)] $*"; }

    is_mounted() {
      MOUNTED=$(ssh -i ${sshKey} -o StrictHostKeyChecking=yes \
        -o ConnectTimeout=5 backup@cold \
        'zfs list -H -o name,mounted gigavault 2>/dev/null | grep -c yes || true')
      if [ "$MOUNTED" -ge "1" ]; then
        return 0
      fi
      return 1
    }

    # ── 1. wake the machine if it isn't responding ──────────────────────
    if nc -z -w3 cold ${toString lab.ports.ssh} 2>/dev/null; then
      log "cold already responding on port ${toString lab.ports.ssh}, checking if pools are mounted"
      is_mounted && log "already mounted, nothing to do" && exit 0
    elif ! nc -z -w3 ${lab.lan.cold-unlock} ${toString lab.ports.ssh-initrd} 2>/dev/null; then
      log "cold unreachable, sending WoL to ${lab.mac.cold}"
      wakeonlan ${lab.mac.cold}
    fi

    # ── 2. wait for SSH ────────────────────────────────────────────────
    log "waiting for SSH..."
    for i in $(seq 1 60); do
      nc -z -w2 ${lab.lan.cold-unlock} ${toString lab.ports.ssh-initrd} 2>/dev/null &&
      	{ log "initrd SSH up"; break; }
      nc -z -w2 cold ${toString lab.ports.ssh} 2>/dev/null &&
      	{ log "already fully booted"; break; }
      sleep 5
      if [ $i -eq 60 ]; then
        log "ERROR: timed out waiting for SSH"
        exit 1
      fi
      log "attempt $i/60..."
    done
    
    # ── 3. LUKS unlock via initrd SSH if needed ────────────────────────────
    if nc -z -w2 ${lab.lan.cold-unlock} ${toString lab.ports.ssh-initrd} 2>/dev/null; then
      log "unlocking LUKS via initrd SSH"

      # send passphrase to the initrd password agent
      # systemd-tty-ask-password-agent reads from stdin when piped
      age -d -i ${ageKey} ${secrets}/cold-luks-passphrase.age | ssh \
        -p ${toString lab.ports.ssh-initrd} \
        -i ${sshKey} \
        -o StrictHostKeyChecking=yes \
        -o HostKeyAlias=cold-unlock \
	-o ConnectTimeout=10 \
        -o ServerAliveInterval=5 \
        -o ServerAliveCountMax=2 \
        root@${lab.lan.cold-unlock} \
        "cryptsetup-askpass" || true

      # since the connection ends abruptly, ssh will not exit cleanly

      log "LUKS passphrase sent, waiting for full boot..."

      # wait for initrd SSH to drop and full SSH to come up
      sleep 10
      for i in $(seq 1 60); do
        nc -z -w2 cold ${toString lab.ports.ssh} >/dev/null && break
        sleep 5
        [ $i -eq 60 ] && { log "ERROR: cold did not finish booting after LUKS unlock"; exit 1; }
      done
      log "cold fully booted"
    fi

    # ── 4. SSH into cold and unlock ─────────────────────────────────────
    log "sending keys to cold..."

    for k in gigavault gaijin; do
      age -d -i ${ageKey} ${secrets}/$k-passphrase.age |
      ssh -i ${sshKey} \
        -o StrictHostKeyChecking=yes \
        -o HostKeyAlias=cold \
	backup@cold \
        "sudo zfs load-key $k" || true # in case key is already loaded
    done

    ssh -i ${sshKey} \
      -o StrictHostKeyChecking=yes \
      -o HostKeyAlias=cold \
      backup@cold \
      "sudo zfs mount -a"

    log "checking mount..."
    if ! is_mounted; then
      log "looks like the mount failed, investigate"
      exit 1
    fi

    log "keys sent, cold is up and unlocked"
  '';

  cold-backup = pkgs.writeShellScriptBin "cold-backup" ''
    set -euo pipefail
    PATH="${lib.makeBinPath (with pkgs; [ openssh age wakeonlan netcat-openbsd coreutils gnugrep ])}:$PATH"

    log() { echo "[$(date -Iseconds)] $*"; }

    ${cold-unlock}/bin/cold-unlock

    # ── 3. trigger backup cycle and wait for it ──────────────────────────
    log "starting backup cycle on cold"
    ssh -i ${sshKey} -o StrictHostKeyChecking=yes \
      backup@cold \
      'sudo systemctl start cold-backup.service'

    log "waiting for backup cycle to complete..."
    while ssh -i ${sshKey} -o StrictHostKeyChecking=yes \
      backup@cold \
      'systemctl is-active cold-backup.service' 2>/dev/null \
      | grep -q "^active"; do
      sleep 30
    done

    # check it didn't fail
    STATUS=$(ssh -i ${sshKey} -o StrictHostKeyChecking=yes \
      backup@cold \
      'systemctl is-active cold-backup.service')
    if [ "$STATUS" = "failed" ]; then
      log "ERROR: backup cycle failed — not shutting down, investigate manually"
      exit 1
    fi

    log "backup cycle complete"

    # ── 4. shutdown cold ────────────────────────────────────────────
    log "shutting down cold"
    ssh -i ${sshKey} -o StrictHostKeyChecking=yes \
      backup@cold \
      'sudo shutdown -h now' || true
    # ssh will exit non-zero as the connection drops, so || true is correct

    log "done"
  '';

in
{
  environment.systemPackages = [ cold-unlock cold-backup ];

  programs.ssh.knownHosts = {
    "cold".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqjHsgUF2s+MRJqSvyB14w05NXVRoaimZjPyu/S3NYX root@nixos";
    "cold-unlock".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOSXuJ592PTKU3Kxo8vcBT8VOnkEXBJVcEjk9vMx1VKx cold-initrd";
  };

  systemd.services.cold-backup = {
    description = "Cold storage backup cycle";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${cold-backup}/bin/cold-backup";
      TimeoutStartSec = "20h";
      # if this fails, don't retry automatically — alert instead
      Restart = "no";
    };
  };

  systemd.timers.cold-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 01:30:00";
      Persistent = false; # explicitly false — if we miss a night, don't catch up
      Unit = "cold-backup.service";
    };
  };
}
