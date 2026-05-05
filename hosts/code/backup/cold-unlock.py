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
log = logging.getLogger("cold-unlock")

STAY_FILE = "/tmp/stay"


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--ssh-key",     required=True)
    p.add_argument("--age-key",     required=True)
    p.add_argument("--secrets",     required=True)
    p.add_argument("--unlockables", required=True, help="path to unlockables JSON")
    p.add_argument("--host-meta",   required=True, help="path to host meta JSON")
    p.add_argument("--ssh-port",    type=int, required=True)
    p.add_argument("--initrd-port", type=int, required=True)
    # optional: unlock a specific host, defaults to all
    p.add_argument("--host", default=None,
                   help="unlock a specific host (default: all unlockables)")
    # flag: manual wake, leave a stay file so backup won't shut down
    p.add_argument("--stay", action="store_true",
                   help="create /tmp/stay on cold after unlock (skip auto-shutdown)")
    return p.parse_args()


def port_open(host, port, timeout=2):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def ssh_cmd(args, host, cmd, *, host_alias, port=22, input=None, check=True):
    return subprocess.run(
        [
            "ssh",
            "-i", args.ssh_key,
            "-p", str(port),
            "-o", "StrictHostKeyChecking=yes",
            "-o", f"HostKeyAlias={host_alias}",
            "-o", "ConnectTimeout=10",
            "-o", "BatchMode=yes",
            f"backup@{host}",
            cmd,
        ],
        input=input,
        text=True,
        check=check,
        capture_output=False,
    )


def decrypt_age(args, filename):
    r = subprocess.run(
        ["age", "-d", "-i", args.age_key,
         os.path.join(args.secrets, filename)],
        capture_output=True, text=True, check=True,
    )
    return r.stdout.strip()


def is_mounted(args, host_ip):
    r = subprocess.run(
        [
            "ssh",
            "-i", args.ssh_key,
            "-o", "StrictHostKeyChecking=yes",
            "-o", f"HostKeyAlias={host_ip}",
            "-o", "ConnectTimeout=5",
            "-o", "BatchMode=yes",
            f"backup@{host_ip}",
            "zfs list -H -o mounted 2>/dev/null | grep -c yes || true",
        ],
        capture_output=True, text=True, check=False,
    )
    try:
        return int(r.stdout.strip()) >= 1
    except ValueError:
        return False


def wait_for_port(host, port, attempts=60, interval=5, label="SSH"):
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


def unlock_host(args, host, pools, meta):
    ip         = meta["ip"]
    initrd_ip  = meta["initrd-ip"]
    mac        = meta["mac"]

    log.info("=== unlocking %s ===", host)

    # ── 1. wake if needed ────────────────────────────────────────────────
    ssh_up    = port_open(ip, args.ssh_port)
    initrd_up = port_open(initrd_ip, args.initrd_port)

    if ssh_up:
        log.info("%s responding on port %d", host, args.ssh_port)
        if is_mounted(args, ip):
            log.info("%s pools already mounted", host)
            return
    elif not initrd_up:
        log.info("sending WoL to %s (%s)", host, mac)
        subprocess.run(["wakeonlan", mac], check=True)

    # ── 2. wait for initrd or full SSH ───────────────────────────────────
    log.info("waiting for %s to respond...", host)
    for i in range(1, 61):
        if port_open(initrd_ip, args.initrd_port):
            log.info("initrd SSH up on %s", host)
            break
        if port_open(ip, args.ssh_port):
            log.info("%s already fully booted", host)
            break
        if i == 60:
            log.error("timed out waiting for %s", host)
            sys.exit(1)
        time.sleep(5)

    # ── 3. LUKS unlock via initrd SSH if needed ──────────────────────────
    if port_open(initrd_ip, args.initrd_port):
        log.info("unlocking LUKS on %s via initrd SSH", host)
        luks_pw = decrypt_age(args, f"{host}-luks-passphrase.age")

        subprocess.run(
            [
                "ssh",
                "-p", str(args.initrd_port),
                "-i", args.ssh_key,
                "-o", "StrictHostKeyChecking=yes",
                "-o", f"HostKeyAlias={host}-unlock",
                "-o", "ConnectTimeout=10",
                "-o", "ServerAliveInterval=5",
                "-o", "ServerAliveCountMax=2",
                f"root@{initrd_ip}",
                "cryptsetup-askpass",
            ],
            input=luks_pw + "\n", text=True, check=False,
        )
        del luks_pw

        log.info("passphrase sent, waiting for full boot on %s...", host)
        time.sleep(10)
        if not wait_for_port(ip, args.ssh_port, label=f"{host} post-LUKS SSH"):
            log.error("%s did not finish booting", host)
            sys.exit(1)

    # ── 4. ZFS pool unlock ───────────────────────────────────────────────
    log.info("unlocking ZFS pools on %s: %s", host, pools)
    for pool in pools:
        pw = decrypt_age(args, f"{pool}-passphrase.age")
        subprocess.run(
            [
                "ssh",
                "-i", args.ssh_key,
                "-o", "StrictHostKeyChecking=yes",
                "-o", f"HostKeyAlias={host}",
                "-o", "BatchMode=yes",
                f"backup@{ip}",
                f"sudo zfs load-key {pool}",
            ],
            input=pw, text=True, check=False,  # non-zero if already loaded
        )
        del pw

    subprocess.run(
        [
            "ssh",
            "-i", args.ssh_key,
            "-o", "StrictHostKeyChecking=yes",
            "-o", f"HostKeyAlias={host}",
            "-o", "BatchMode=yes",
            f"backup@{ip}",
            "sudo zfs mount -a",
        ],
        check=True,
    )

    if not is_mounted(args, ip):
        log.error("mount check failed on %s after sending keys", host)
        sys.exit(1)

    log.info("%s is up and unlocked", host)

    # ── 5. create stay file if manual wake ──────────────────────────────
    if args.stay:
        subprocess.run(
            [
                "ssh",
                "-i", args.ssh_key,
                "-o", "StrictHostKeyChecking=yes",
                "-o", f"HostKeyAlias={host}",
                "-o", "BatchMode=yes",
                f"backup@{ip}",
                f"touch {STAY_FILE}",
            ],
            check=True,
        )
        log.info("created %s on %s — auto-shutdown disabled", STAY_FILE, host)


def main():
    args = parse_args()

    with open(args.unlockables) as f:
        unlockables = json.load(f)
    with open(args.host_meta) as f:
        host_meta = json.load(f)

    targets = (
        {args.host: unlockables[args.host]}
        if args.host
        else unlockables
    )

    for host, pools in targets.items():
        meta = host_meta[host]
        unlock_host(args, host, pools, meta)


if __name__ == "__main__":
    main()