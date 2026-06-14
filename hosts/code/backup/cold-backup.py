#!/usr/bin/env python3
import argparse
import json
import logging
import os
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

STAY_FILE = "/tmp/stay"


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--ssh-key",     required=True)
    p.add_argument("--cold-ip",     required=True)
    p.add_argument("--unlock-bin",  required=True)
    p.add_argument("--unlockables", required=True, help="path to unlockables JSON")
    p.add_argument("--host-meta",   required=True, help="path to host meta JSON")
    p.add_argument("--targets",     required=True, help="path to targets JSON")
    p.add_argument("--wslop-addr",  default=None,
                   help="ssh address of wslop; backed up opportunistically when up")
    return p.parse_args()


def port_open(host, port, timeout=5):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def ssh_run(args, cmd, *, check=True, capture=False, host="cold", ip=None):
    # `host` is the known-hosts alias (drives -o HostKeyAlias); `ip` is what we
    # actually connect to. both default to cold. callers targeting another
    # machine (the shutdown loop) MUST pass both, otherwise the strict host-key
    # check runs against cold's key and the connection silently fails — which is
    # exactly why lame was never shut down and cold's shutdown ignored its alias.
    return subprocess.run(
        [
            "ssh",
            "-i", args.ssh_key,
            "-o", "StrictHostKeyChecking=yes",
            "-o", f"HostKeyAlias={host}",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=120",
            f"backup@{ip or args.cold_ip}",
            cmd,
        ],
        check=check,
        capture_output=capture,
        text=True,
    )


def stay_exists(args, host="cold", ip=None):
    r = ssh_run(args,
        f"test -f {STAY_FILE} && echo yes || echo no",
        check=False, capture=True, host=host, ip=ip)
    # fail safe: if the host can't be reached to check, do NOT shut it down — a
    # transient ssh hiccup should never translate into powering a machine off
    if r.returncode != 0:
        log.warning("could not check %s on %s (ssh rc=%d) — leaving it running",
                    STAY_FILE, host, r.returncode)
        return True
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

    # ── 3.5 opportunistic wslop backup ────────────────────────────────────
    # wslop is a workstation: back it up when it happens to be up during the
    # backup window, skip it when it isn't. failures are non-fatal so a
    # mid-backup shutdown of wslop doesn't leave cold running all day.
    if args.wslop_addr:
        if port_open(args.wslop_addr, 22):
            log.info("wslop is up — backing it up")
            r = subprocess.run(
                [
                    "ssh",
                    "-i", args.ssh_key,
                    "-o", "StrictHostKeyChecking=yes",
                    "-o", "HostKeyAlias=wslop",
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=30",
                    "-o", "ServerAliveInterval=60",
                    "-o", "ServerAliveCountMax=10",
                    f"backup@{args.wslop_addr}",
                    "sudo /run/current-system/sw/bin/wslop-backup --no-poweroff",
                ],
                check=False,
            )
            if r.returncode != 0:
                log.error("wslop backup exited %d — continuing", r.returncode)
        else:
            log.info("wslop is down — skipping its backup")

    # ── 4. shut each woken host down unless its stay file exists ──────────
    # NB: target each host by its own ip + host-key alias. previously the
    # shutdown ssh passed no host, so it always landed on cold (ignoring cold's
    # own stay file when issued during another host's iteration) and lame was
    # never reached at all.
    for host in wakeup_targets:
        ip = host_meta[host]["ip"]
        if stay_exists(args, host=host, ip=ip):
            log.info("%s exists on %s — skipping shut down", STAY_FILE, host)
        else:
            log.info("shutting down %s", host)
            ssh_run(args, "sudo shutdown -h now", check=False, host=host, ip=ip)


if __name__ == "__main__":
    main()