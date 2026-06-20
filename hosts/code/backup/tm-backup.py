#!/usr/bin/env python3
# tm-backup.py (runs on `code`) — weekly orchestrator for the Time Machine courier.
#
# The courier (timemachine) is a FOREIGN NixOS box (config lives in another repo)
# that images the Win7/XP system disks into a restic repo on cold. It is normally
# powered OFF. This orchestrator:
#   1. ensures cold is up + ZFS-unlocked (cold-unlock --host cold, idempotent) so
#      the restic repo on gigavault is mounted,
#   2. wakes the courier via Wake-on-LAN,
#   3. waits for its SSH, runs `tm-backup` on it (the courier restic-pushes to cold),
#   4. powers the courier back off (unless it failed / --no-poweroff / /tmp/stay),
#   5. powers cold back off if nothing else needs it (no /tmp/stay, no running nightly).
#
# Mirrors the wslop opportunistic-push design plus WoL + power management. Fail-safe:
# never power a host off when its state is uncertain (an SSH failure => leave it up).
import argparse
import logging
import socket
import subprocess
import sys
import time

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s",
                    handlers=[logging.StreamHandler(sys.stdout)])
log = logging.getLogger("tm-backup")
STAY_FILE = "/tmp/stay"


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--ssh-key", required=True)
    p.add_argument("--unlock-bin", required=True, help="cold-unlock binary on code")
    p.add_argument("--tm-addr", required=True, help="courier ssh address (host/ip)")
    p.add_argument("--tm-mac", required=True)
    p.add_argument("--cold-addr", required=True)
    p.add_argument("--tm-user", default="backup")
    p.add_argument("--cold-user", default="backup")
    p.add_argument("--ssh-port", type=int, default=22)
    p.add_argument("--no-poweroff", action="store_true")
    return p.parse_args()


def port_open(host, port, timeout=5):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def wait_for_port(host, port, attempts=72, interval=5, label="courier SSH"):
    log.info("waiting for %s on %s:%d...", label, host, port)
    for i in range(1, attempts + 1):
        if port_open(host, port):
            log.info("%s is up", label)
            return True
        if i % 6 == 0:
            log.info("  attempt %d/%d...", i, attempts)
        time.sleep(interval)
    log.error("timed out waiting for %s on %s:%d", label, host, port)
    return False


def ssh(args, alias, user, host, cmd, *, check=True, capture=False):
    # `alias` drives StrictHostKeyChecking via HostKeyAlias; `host` is the connect
    # target. Both must be right or strict checking runs against the wrong key.
    return subprocess.run(
        [
            "ssh", "-i", args.ssh_key,
            "-o", "StrictHostKeyChecking=yes",
            "-o", f"HostKeyAlias={alias}",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=30",
            "-o", "ServerAliveInterval=60",
            "-o", "ServerAliveCountMax=20",
            f"{user}@{host}", cmd,
        ],
        check=check, capture_output=capture, text=True,
    )


def poweroff(args, alias, user, host, what):
    # fail-safe: test -f returns 0=present, 1=absent; ssh returns 255 on conn fail.
    r = ssh(args, alias, user, host, f"test -f {STAY_FILE}", check=False, capture=True)
    if r.returncode == 0:
        log.info("%s present on %s — leaving it up", STAY_FILE, what)
        return
    if r.returncode != 1:
        log.warning("can't reach %s (rc=%d) — NOT powering it off", what, r.returncode)
        return
    log.info("powering off %s", what)
    ssh(args, alias, user, host, "sudo shutdown -h now", check=False)


def poweroff_cold(args):
    r = ssh(args, "cold", args.cold_user, args.cold_addr,
            "systemctl is-active cold-backup.service", check=False, capture=True)
    if r.stdout.strip() == "active":
        log.info("cold-backup is running — leaving cold up")
        return
    poweroff(args, "cold", args.cold_user, args.cold_addr, "cold")


def main():
    args = parse_args()

    log.info("ensuring cold is up + unlocked")
    subprocess.run([args.unlock_bin, "--host", "cold"], check=True)

    log.info("waking courier %s (%s)", args.tm_addr, args.tm_mac)
    subprocess.run(["wakeonlan", args.tm_mac], check=True)

    if not wait_for_port(args.tm_addr, args.ssh_port):
        log.error("courier never came up — aborting (cold left to the nightly)")
        sys.exit(1)

    log.info("running tm-backup on the courier")
    r = ssh(args, "timemachine", args.tm_user, args.tm_addr, "sudo tm-backup", check=False)
    ok = r.returncode == 0
    if not ok:
        log.error("tm-backup exited %d — leaving courier up for investigation", r.returncode)

    if ok and not args.no_poweroff:
        poweroff(args, "timemachine", args.tm_user, args.tm_addr, "courier")
    poweroff_cold(args)

    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
