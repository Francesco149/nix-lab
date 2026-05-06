#!/usr/bin/env python3
import argparse
import json
import logging
import os
import subprocess
import sys
import time

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger("cold-backup")

STAY_FILE = "/tmp/stay"


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--ssh-key",     required=True)
    p.add_argument("--cold-ip",     required=True)
    p.add_argument("--unlock-bin",  required=True)
    p.add_argument("--unlockables", required=True, help="path to unlockables JSON")
    p.add_argument("--host-meta",   required=True, help="path to host meta JSON")
    p.add_argument("--targets",     required=True, help="path to targets JSON")
    return p.parse_args()


def ssh_run(args, cmd, *, check=True, capture=False, host=None):
    return subprocess.run(
        [
            "ssh",
            "-i", args.ssh_key,
            "-o", "StrictHostKeyChecking=yes",
            "-o", "HostKeyAlias=cold",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=120",
            f"backup@{host or args.cold_ip}",
            cmd,
        ],
        check=check,
        capture_output=capture,
        text=True,
    )


def stay_exists(args, host=None):
    r = ssh_run(args,
        f"test -f {STAY_FILE} && echo yes || echo no",
        check=False, capture=True, host=host)
    return r.stdout.strip() == "yes"


def main():
    args = parse_args()

    with open(args.targets) as f:
        targets = json.load(f)

    with open(args.unlockables) as f:
        unlockables = json.load(f)
        
    with open(args.host_meta) as f:
        host_meta = json.load(f)

    # ── 1. unlock cold (not stay — this is the backup service) ───────────
    log.info("running unlock")
    wakeup_targets = set({"cold"})

    for source in targets:
        # derive dest from source: "backup@proxmox:tank" -> "gigavault/proxmox-backup"
        host_name = source.split("@")[-1].split(":")[0]  # "proxmox"
        if host_name in unlockables:
            log.info(f"source {host_name} found in unlockables")
            wakeup_targets.add(host_name)
        else:
            log.info(f"source {host_name} is not an unlockable")
    
    failed_targets = set()
    for host_name in wakeup_targets:
        try:
            subprocess.run([args.unlock_bin, "--host", host_name], check=True)
        except Exception as e:
            log.error("couldn't wake up %s, backup for this machine will fail", host_name)
            if host_name == "cold":
                raise e
            failed_targets.add(host_name)

    wakeup_targets -= failed_targets

    # ── 2. trigger backup cycle on cold ──────────────────────────────────
    log.info("starting backup cycle on cold")
    ssh_run(args, "sudo systemctl start cold-backup.service")

    # ── 3. poll until service is no longer active ─────────────────────────
    log.info("waiting for backup cycle to complete...")
    while True:
        r = ssh_run(args, "systemctl is-active cold-backup.service",
                    check=False, capture=True)
        status = r.stdout.strip()
        if status not in ("active", "activating", "deactivating"):
            break
        time.sleep(30)

    if status != "inactive":
        log.error("backup cycle ended with status %r — not shutting down, investigate", status)
        sys.exit(1)

    log.info("backup cycle complete")

    # ── 4. shutdown cold unless stay file exists ──────────────────────────
    for host in wakeup_targets:
        if stay_exists(args, host=host):
            log.info("%s exists on %s — skipping shut down", STAY_FILE, host)
        else:
            log.info("shutting down %s", host)
            ssh_run(args, "sudo shutdown -h now", check=False)


if __name__ == "__main__":
    main()