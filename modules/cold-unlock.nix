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

  unlock-cold = pkgs.writeShellScriptBin "unlock-cold" ''
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

    # ── 1. wake the machine if it isn't responding ──────────────────────
    if ! nc -z -w3 cold ${toString lab.ports.ssh} 2>/dev/null; then
      log "cold unreachable, sending WoL to ${lab.mac.cold}"
      wakeonlan cold
    else
      log "cold already responding on port ${toString lab.ports.ssh}, checking if pools are mounted"
      MOUNTED=$(ssh -i ${sshKey} -o StrictHostKeyChecking=yes \
        -o ConnectTimeout=5 backup@cold \
        'zfs list -H -o name,mounted gigavault 2>/dev/null | grep -c yes || true')
      if [ "$MOUNTED" -ge "1" ]; then
        log "pools already unlocked, nothing to do"
        exit 0
      fi
    fi

    # ── 2. wait for SSH ────────────────────────────────────────────────
    log "waiting for SSH..."
    for i in $(seq 1 60); do
      sleep 5
      nc -z -w2 cold ${toString lab.ports.ssh} 2>/dev/null && break
      if [ $i -eq 60 ]; then
        log "ERROR: timed out waiting for SSH"
        exit 1
      fi
      log "attempt $i/60..."
    done
    log "SSH is up"

    # ── 3. decrypt passphrases from age-encrypted files ─────────────────
    PW_GIGAVAULT=$(age -d -i ${ageKey} ${secrets}/gigavault-passphrase.age)
    PW_GAIJIN=$(age -d -i ${ageKey} ${secrets}/gaijin-passphrase.age)

    # ── 4. SSH into cold and unlock ─────────────────────────────────────
    log "sending keys to cold..."
    ssh -i ${sshKey} \
      -o StrictHostKeyChecking=yes \
      -o HostKeyAlias=cold \
      root@cold << EOF
    printf '%s' "$PW_GIGAVAULT" | zfs load-key gigavault
    printf '%s' "$PW_GAIJIN"    | zfs load-key gaijin
    zfs mount -a
    EOF

    unset PW_GIGAVAULT PW_GAIJIN
    log "keys sent, cold is up and unlocked"
  '';

in
{
  environment.systemPackages = [ unlock-cold ];

  programs.ssh.knownHosts = {
    "cold".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvwCDi8S5aJYYPsYlnqBVo6ItZKtLgmiFJzN+b/hs2k";
  };
}
