#!/usr/bin/env python3
import argparse
import logging
import socket
import subprocess
import sys
import time

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger("cold-backup")


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--ssh-key",    required=True)
    p.add_argument("--cold-ip",    required=True)
    p.add_argument("--unlock-bin", required=True)
    return p.parse_args()


def ssh_run(args, cmd, *, check=True, capture=False):
    return subprocess.run(
        [
            "ssh",
            "-i", args.ssh_key,
            "-o", "StrictHostKeyChecking=yes",
            "-o", "HostKeyAlias=cold",
            "-o", "BatchMode=yes",
            f"backup@{args.cold_ip}",
            cmd,
        ],
        check=check,
        capture_output=capture,
        text=True,
    )


def main():
    args = parse_args()

    # ── 1. unlock ────────────────────────────────────────────────────────
    log.info("running unlock")
    subprocess.run([args.unlock_bin], check=True)

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

    # ── 4. shutdown cold ──────────────────────────────────────────────────
    log.info("shutting down cold")
    ssh_run(args, "sudo shutdown -h now", check=False)
    # ssh exits non-zero when the connection drops mid-shutdown — expected

    log.info("done")


if __name__ == "__main__":
    main()