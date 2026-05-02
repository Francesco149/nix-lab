{ config, pkgs, lib, ... }:
let
  inherit (config) lab;

  zpool = "/run/current-system/sw/bin/zpool";

  cold-backup = pkgs.writeShellScriptBin "cold-backup" ''
    #!/usr/bin/env bash
    set -euo pipefail
    
    LOG="/var/log/cold-backup.log"
    log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }
    
    # ── 1. syncoid ───────────────────────────────────────────────────────────────
    log "starting syncoid"

    # generate the ssh key with this command on first deployment
    # ssh-keygen -t ed25519 -f /root/.ssh/syncoid_id -C "syncoid@cold" -N ""

    ${pkgs.sanoid}/bin/syncoid \
      --recursive \
      --no-privilege-elevation \
      --sshkey /root/.ssh/syncoid_id \
      --exclude-datasets "tank/tmp" \
      backup@proxmox:tank gigavault/proxmox-backup \
      2>&1 | tee -a "$LOG"
    # note: if you prefer push from Proxmox side, invert this and trigger
    # the syncoid run on Proxmox instead, then poll for completion here
    log "syncoid done"
    
    # ── 2. wait for any SMART self-tests already in progress ────────────────────
    log "checking for in-progress SMART tests"
    for disk in /dev/sd{a..j}; do
      [ -b "$disk" ] || continue
      while ${pkgs.smartmontools}/bin/smartctl -a "$disk" | grep -q "Self-test routine in progress"; do
        log "  $disk: SMART test in progress, waiting 60s..."
        sleep 60
      done
    done
    log "SMART tests clear"
    
    while ${zpool} status gigavault | grep -q "scan:.*in progress"; do
      log "  scrub in progress, waiting 5min..."
      sleep 300
    done
    log "backup cycle complete"
  '';
in
{
  environment.systemPackages = [ cold-backup ];

  # the full backup cycle service, triggered remotely by the orchestrator
  systemd.services.cold-backup = {
    description = "Cold storage backup cycle";
    after = [ "zfs.target" "network.target" ];
    # do NOT add to any .target — only triggered remotely
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${cold-backup}/bin/cold-backup";
      TimeoutStartSec = "8h";
      # write a stamp file the orchestrator can poll
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
  
  # allow backup user to trigger it without a password
  security.sudo.extraRules = [{
    users = [ "backup" ];
    commands = [{
      command = "${pkgs.systemd}/bin/systemctl start cold-backup.service";
      options = [ "NOPASSWD" ];
    }];
  }];

  programs.ssh.knownHosts = {
    "proxmox".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIrny+0hMgPXGTcMNcZczDVYl+LaQONSrVPGRiogSR9q root@proxmox";
  };
}
