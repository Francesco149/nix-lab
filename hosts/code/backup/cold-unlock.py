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
log = logging.getLogger("cold-unlock")


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--ssh-key",     required=True)
    p.add_argument("--age-key",     required=True)
    p.add_argument("--secrets",     required=True)
    p.add_argument("--cold-ip",     required=True)
    p.add_argument("--cold-mac",    required=True)
    p.add_argument("--initrd-ip",   required=True)
    p.add_argument("--ssh-port",    type=int, required=True)
    p.add_argument("--initrd-port", type=int, required=True)
    return p.parse_args()


def port_open(host, port, timeout=2):
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def ssh(args, host, cmd, *, port=22, host_alias=None, check=True, input=None):
    alias = host_alias or host
    return subprocess.run(
        [
            "ssh",
            "-i", args.ssh_key,
            "-p", str(port),
            "-o", "StrictHostKeyChecking=yes",
            "-o", f"HostKeyAlias={alias}",
            "-o", "ConnectTimeout=10",
            "-o", "BatchMode=yes",
            f"backup@{host}",
            cmd,
        ],
        check=check,
        input=input,
        text=True,
        capture_output=False,
    )


def decrypt_age(args, filename):
    r = subprocess.run(
        ["age", "-d", "-i", args.age_key, f"{args.secrets}/{filename}"],
        capture_output=True,
        text=True,
        check=True,
    )
    return r.stdout.strip()


def is_mounted(args):
    r = subprocess.run(
        [
            "ssh",
            "-i", args.ssh_key,
            "-o", "StrictHostKeyChecking=yes",
            "-o", "HostKeyAlias=cold",
            "-o", "ConnectTimeout=5",
            "-o", "BatchMode=yes",
            f"backup@{args.cold_ip}",
            "zfs list -H -o name,mounted gigavault 2>/dev/null | grep -c yes || true",
        ],
        capture_output=True,
        text=True,
        check=False,
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


def main():
    args = parse_args()

    # ── 1. wake if needed ────────────────────────────────────────────────
    ssh_up     = port_open(args.cold_ip,   args.ssh_port)
    initrd_up  = port_open(args.initrd_ip, args.initrd_port)

    if ssh_up:
        log.info("cold responding on port %d, checking pools", args.ssh_port)
        if is_mounted(args):
            log.info("pools already mounted, nothing to do")
            return
    elif not initrd_up:
        log.info("cold unreachable, sending WoL to %s", args.cold_mac)
        subprocess.run(["wakeonlan", args.cold_mac], check=True)

    # ── 2. wait for initrd SSH or full SSH ───────────────────────────────
    log.info("waiting for cold to respond...")
    for i in range(1, 61):
        if port_open(args.initrd_ip, args.initrd_port):
            log.info("initrd SSH up")
            break
        if port_open(args.cold_ip, args.ssh_port):
            log.info("cold already fully booted")
            break
        if i == 60:
            log.error("timed out waiting for cold")
            sys.exit(1)
        time.sleep(5)

    # ── 3. LUKS unlock via initrd SSH if needed ──────────────────────────
    if port_open(args.initrd_ip, args.initrd_port):
        log.info("unlocking LUKS via initrd SSH")

        luks_pw = decrypt_age(args, "cold-luks-passphrase.age")

        # pipe passphrase directly into cryptsetup-askpass
        # connection will die abruptly when initrd pivots — that's expected
        subprocess.run(
            [
                "ssh",
                "-p", str(args.initrd_port),
                "-i", args.ssh_key,
                "-o", "StrictHostKeyChecking=yes",
                "-o", "HostKeyAlias=cold-unlock",
                "-o", "ConnectTimeout=10",
                "-o", "ServerAliveInterval=5",
                "-o", "ServerAliveCountMax=2",
                f"root@{args.initrd_ip}",
                "cryptsetup-askpass",
            ],
            input=luks_pw,
            text=True,
            check=False,  # connection dies abruptly, non-zero exit is expected
        )
        del luks_pw

        log.info("passphrase sent, waiting for full boot...")
        time.sleep(10)

        if not wait_for_port(args.cold_ip, args.ssh_port, label="post-LUKS SSH"):
            log.error("cold did not finish booting after LUKS unlock")
            sys.exit(1)
        log.info("cold fully booted")

    # ── 4. ZFS pool unlock ───────────────────────────────────────────────
    log.info("sending ZFS keys...")

    for pool in ("gigavault", "gaijin"):
        pw = decrypt_age(args, f"{pool}-passphrase.age")
        subprocess.run(
            [
                "ssh",
                "-i", args.ssh_key,
                "-o", "StrictHostKeyChecking=yes",
                "-o", "HostKeyAlias=cold",
                "-o", "BatchMode=yes",
                f"backup@{args.cold_ip}",
                f"sudo zfs load-key {pool}",
            ],
            input=pw,
            text=True,
            check=False,  # exits non-zero if key already loaded — fine
        )
        del pw

    subprocess.run(
        [
            "ssh",
            "-i", args.ssh_key,
            "-o", "StrictHostKeyChecking=yes",
            "-o", "HostKeyAlias=cold",
            "-o", "BatchMode=yes",
            f"backup@{args.cold_ip}",
            "sudo zfs mount -a",
        ],
        check=True,
    )

    if not is_mounted(args):
        log.error("mount check failed after sending keys, investigate")
        sys.exit(1)

    log.info("cold is up and unlocked")


if __name__ == "__main__":
    main()