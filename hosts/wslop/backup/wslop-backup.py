#!/usr/bin/env python3
# manual cold-storage backup for the wslop WSL guest and its windows host.
#
# wake+unlock of cold is relayed through `cold-unlock --host cold` on code
# because WSL2 NAT cannot send WoL broadcasts. data is pushed with rsync as
# root@cold so no zfs delegation or backup user setup is needed on cold.
import argparse
import json
import logging
import os
import re
import subprocess
import sys
import tempfile
import time

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger("wslop-backup")

STAY_FILE = "/tmp/stay"
LOG_DIR = "/var/log/wslop-backup"
MAX_INLINE_ERRORS = 30


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--relay",   required=True, help="user@host that runs cold-unlock (code)")
    p.add_argument("--cold-ip", required=True)
    p.add_argument("--config",  required=True, help="path to backup config JSON")
    p.add_argument("--only", action="append", default=None, metavar="TARGET",
                   help="limit to the given target(s), e.g. rootfs or windows/documents")
    p.add_argument("--all", action="store_true",
                   help="also back up the optional windows targets (games, downloads, ...)")
    p.add_argument("--no-poweroff", action="store_true",
                   help="leave cold running (used by the orchestrator on code)")
    return p.parse_args()


def ssh_cold(args, cmd, *, check=True, capture=False):
    return subprocess.run(
        [
            "ssh",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "HostKeyAlias=cold",
            "-o", "ConnectTimeout=30",
            f"root@{args.cold_ip}",
            cmd,
        ],
        check=check,
        capture_output=capture,
        text=True,
    )


# ── unlock ────────────────────────────────────────────────────────────────


def unlock_cold(args):
    log.info("waking/unlocking cold via %s", args.relay)
    subprocess.run(
        [
            "ssh",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "HostKeyAlias=code",
            "-o", "ConnectTimeout=30",
            args.relay,
            "cold-unlock --host cold",
        ],
        check=True,
    )


def check_cold_access(args):
    r = ssh_cold(args, "true", check=False)
    if r.returncode != 0:
        log.error(
            "cannot ssh root@%s — wslop's root key must be authorized on cold "
            "(see the wslop notes in docs/OPERATIONS.md)", args.cold_ip)
        sys.exit(1)


# ── dataset ───────────────────────────────────────────────────────────────


def ensure_dataset(args, dataset):
    r = ssh_cold(args, f"zfs list -H -o name {dataset}", check=False, capture=True)
    if r.returncode != 0:
        log.info("creating dataset %s", dataset)
        # acltype=posixacl + xattr=sa so the rootfs's `-aHAX` ACLs/xattrs land
        # without the noisy "Operation not supported" spam on every file
        ssh_cold(args, f"zfs create -p -o xattr=sa -o acltype=posixacl {dataset}")
    else:
        # repair datasets created before acltype was set (rsync -A would
        # otherwise fail on every ACL-bearing file, e.g. /var/log/journal)
        acltype = ssh_cold(args, f"zfs get -H -o value acltype {dataset}",
                           capture=True).stdout.strip()
        if acltype not in ("posixacl", "posix"):
            log.info("enabling acltype=posixacl on %s", dataset)
            ssh_cold(args, f"zfs set acltype=posixacl {dataset}", check=False)

    mounted = ssh_cold(args, f"zfs get -H -o value mounted {dataset}",
                       capture=True).stdout.strip()
    mountpoint = ssh_cold(args, f"zfs get -H -o value mountpoint {dataset}",
                          capture=True).stdout.strip()
    if mounted != "yes" or not mountpoint.startswith("/"):
        log.error("dataset %s is not mounted (mounted=%s mountpoint=%s)",
                  dataset, mounted, mountpoint)
        sys.exit(1)
    return mountpoint


# ── rsync targets ─────────────────────────────────────────────────────────


def list_targets(cfg):
    # rootfs: native ext4 read, full restore fidelity. -x stays on the rootfs;
    # -H/-A/-X/--numeric-ids preserve hardlinks/ACLs/xattrs/ids.
    targets = [{
        "name": "rootfs",
        "src": cfg["rootfs"]["src"],
        "excludes": cfg["rootfs"]["excludes"],
        "flags": ["-aHAXxS", "--numeric-ids"],
        "optional": False,
    }]

    win = cfg["windows"]
    common = win.get("common-excludes", [])
    missing = []
    for tier, optional in (("work", False), ("optional", True)):
        for w in win.get(tier, []):
            src = w["src"]
            if not os.path.isdir(src):
                # a configured dir that isn't there (renamed/removed on the
                # windows side) — skip it rather than fail the whole run
                missing.append(w["name"])
                continue
            targets.append({
                "name": f"windows/{w['name']}",
                # trailing slash: copy the dir's *contents* into the dest
                "src": src.rstrip("/") + "/",
                "excludes": common + w.get("excludes", []),
                # drvfs ownership/modes are synthetic, keep only structure+times
                "flags": ["-rltS"],
                "optional": optional,
            })
    if missing:
        log.warning("skipping missing windows source(s): %s", ", ".join(missing))
    return targets


def run_rsync(target, dest, log_path):
    cmd = [
        "rsync",
        *target["flags"],
        # create the full dest path: windows/<name>/ is two levels below the
        # dataset root and rsync won't make intermediate dirs without this
        "--mkpath",
        "--delete",
        "--delete-excluded",
        "--info=stats2,progress2",
        *[f"--exclude={e}" for e in target["excludes"]],
        "-e", "ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o HostKeyAlias=cold",
        target["src"],
        dest,
    ]
    log.info("rsync %s -> %s", target["src"], dest)

    started = time.monotonic()
    with open(log_path, "w") as errlog:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=errlog)
        # pass progress through to the terminal, keep a tail for the stats block
        tail = bytearray()
        while True:
            chunk = proc.stdout.read(8192)
            if not chunk:
                break
            sys.stdout.buffer.write(chunk)
            sys.stdout.buffer.flush()
            tail += chunk
            if len(tail) > 131072:
                del tail[:-65536]
        rc = proc.wait()
    print(flush=True)  # progress2 ends without a newline

    with open(log_path) as f:
        err_lines = [l.rstrip() for l in f if l.strip()]
    for line in err_lines[:MAX_INLINE_ERRORS]:
        log.warning("%s", line)
    if len(err_lines) > MAX_INLINE_ERRORS:
        log.warning("(%d more lines in %s)", len(err_lines) - MAX_INLINE_ERRORS, log_path)

    stats = {}
    text = tail.decode(errors="replace")
    for key, pattern in {
        "files": r"Number of files: ([\d,]+)",
        "created": r"Number of created files: ([\d,]+)",
        "deleted": r"Number of deleted files: ([\d,]+)",
        "size": r"Total file size: ([\d,]+) bytes",
        "sent": r"Total bytes sent: ([\d,]+)",
    }.items():
        m = re.search(pattern, text)
        stats[key] = int(m.group(1).replace(",", "")) if m else None

    # 23 = partial transfer (locked/unreadable files), 24 = files vanished
    status = "ok" if rc == 0 else "partial" if rc in (23, 24) else f"FAILED rc={rc}"
    return {
        "name": target["name"],
        "rc": rc,
        "status": status,
        "errors": len(err_lines),
        "seconds": time.monotonic() - started,
        **stats,
    }


# ── snapshots ─────────────────────────────────────────────────────────────


def snapshot_and_prune(args, dataset, keep):
    snap = f"{dataset}@wslop-{time.strftime('%Y%m%d-%H%M%S')}"
    r = ssh_cold(args, f"zfs snapshot '{snap}'", check=False)
    if r.returncode != 0:
        log.error("snapshot %s failed", snap)
        return None, 0, 0

    r = ssh_cold(args, f"zfs list -H -t snapshot -o name -s creation -d 1 {dataset}",
                 check=False, capture=True)
    snaps = [s for s in r.stdout.splitlines() if s.startswith(f"{dataset}@wslop-")]
    pruned = 0
    for old in snaps[:-keep] if keep > 0 else []:
        d = ssh_cold(args, f"zfs destroy '{old}'", check=False)
        if d.returncode == 0:
            pruned += 1
        else:
            log.warning("could not prune %s", old)
    return snap, len(snaps) - pruned, pruned


# ── report ────────────────────────────────────────────────────────────────


def human(n):
    if n is None:
        return "?"
    for unit in ["B", "KiB", "MiB", "GiB", "TiB"]:
        if n < 1024 or unit == "TiB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{n} B"
        n /= 1024


def duration(seconds):
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    return f"{h}h {m:02d}m {s:02d}s" if h else f"{m}m {s:02d}s"


def print_report(results, dataset, usage, snap_info, total_seconds):
    rows = [["target", "files", "data", "sent", "err", "time", "status"]]
    for r in results:
        rows.append([
            r["name"],
            f"{r['files']:,}" if r["files"] is not None else "?",
            human(r["size"]),
            human(r["sent"]),
            str(r["errors"]),
            duration(r["seconds"]),
            r["status"],
        ])
    widths = [max(len(row[i]) for row in rows) for i in range(len(rows[0]))]

    print()
    print("═" * (sum(widths) + 2 * (len(widths) - 1)))
    print("wslop backup report")
    print("═" * (sum(widths) + 2 * (len(widths) - 1)))
    for row in rows:
        print("  ".join(cell.ljust(w) for cell, w in zip(row, widths)).rstrip())
    print("─" * (sum(widths) + 2 * (len(widths) - 1)))

    used, refer, avail = usage
    print(f"dataset   {dataset}  refer {human(refer)}  used {human(used)}  avail {human(avail)}")
    snap, kept, pruned = snap_info
    if snap:
        print(f"snapshot  {snap.split('@')[1]}  ({kept} kept, {pruned} pruned)")
    else:
        print("snapshot  FAILED — backup data is on the live dataset only")
    print(f"duration  {duration(total_seconds)}")
    print(f"logs      {LOG_DIR}/")
    print(flush=True)


# ── poweroff ──────────────────────────────────────────────────────────────


def poweroff_cold(args, dataset):
    pool = dataset.split("/")[0]
    while True:
        r = ssh_cold(args, f"zpool status {pool}", check=False, capture=True)
        if "scrub in progress" not in r.stdout:
            break
        log.info("scrub in progress on %s — waiting 5min before poweroff...", pool)
        time.sleep(300)

    r = ssh_cold(args, f"test -f {STAY_FILE}", check=False)
    if r.returncode == 0:
        log.info("%s exists on cold — leaving it running", STAY_FILE)
        return
    log.info("powering off cold")
    ssh_cold(args, "shutdown -h now", check=False)


# ── main ──────────────────────────────────────────────────────────────────


def main():
    args = parse_args()
    with open(args.config) as f:
        cfg = json.load(f)
    dataset = cfg["dataset"]

    started = time.monotonic()
    os.makedirs(LOG_DIR, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")

    targets = list_targets(cfg)
    if args.only:
        unknown = set(args.only) - {t["name"] for t in targets}
        if unknown:
            log.error("unknown target(s): %s (have: %s)",
                      ", ".join(sorted(unknown)),
                      ", ".join(t["name"] for t in targets))
            sys.exit(1)
        targets = [t for t in targets if t["name"] in args.only]
    elif not args.all:
        # default run: rootfs + the work windows targets, skip the optional ones
        targets = [t for t in targets if not t["optional"]]

    # cold may already be up (left running, or the nightly cycle has it). only
    # pay the wake+unlock relay through code when cold is actually unreachable.
    if ssh_cold(args, "true", check=False).returncode == 0:
        log.info("cold already reachable — skipping wake/unlock relay")
    else:
        unlock_cold(args)
        check_cold_access(args)
    mountpoint = ensure_dataset(args, dataset)

    results = []
    for target in targets:
        log_path = f"{LOG_DIR}/{stamp}-{target['name'].replace('/', '-')}.log"
        dest = f"root@{args.cold_ip}:{mountpoint}/{target['name']}/"
        results.append(run_rsync(target, dest, log_path))

    failed = [r for r in results if r["rc"] not in (0, 23, 24)]

    # snapshot even on partial runs: locked windows files are expected
    snap_info = (None, 0, 0)
    if not failed:
        snap_info = snapshot_and_prune(args, dataset, cfg["keep-snapshots"])

    r = ssh_cold(args, f"zfs list -H -p -o used,refer,avail {dataset}",
                 check=False, capture=True)
    try:
        usage = tuple(int(x) for x in r.stdout.split())
    except ValueError:
        usage = (None, None, None)

    print_report(results, dataset, usage, snap_info, time.monotonic() - started)

    if failed:
        log.error("target(s) failed: %s — leaving cold up for investigation",
                  ", ".join(f["name"] for f in failed))
        sys.exit(1)

    if args.no_poweroff:
        log.info("--no-poweroff: leaving cold to the orchestrator")
    else:
        poweroff_cold(args, dataset)


if __name__ == "__main__":
    main()
