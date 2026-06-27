#!/usr/bin/env python3
import argparse, glob, json, logging, subprocess, sys, time

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)],
)
log = logging.getLogger("cold-backup")

SYNCOID  = "syncoid"
SMARTCTL = "smartctl"
ZPOOL    = "zpool"
MAX_RESTARTS = 200


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--targets", required=True, help="path to targets JSON")
    return p.parse_args()


def run_syncoid(source, dest):
    restarts = 0
    while restarts < MAX_RESTARTS:
        log.info("syncoid %s -> %s (attempt %d)", source, dest, restarts + 1)
        proc = subprocess.Popen(
            [
                SYNCOID,
                "--recursive",
                "--no-privilege-elevation",
                # lame must NOT retain local snapshots (big, re-downloadable, frequently
                # deleted model data filled its pool): create a transient sync snapshot and
                # leave a zero-space BOOKMARK, so cold keeps the snapshot history while lame
                # keeps nothing. Other targets (proxmox) snapshot themselves, so we just
                # replicate their existing snaps with --no-sync-snap.
                *(["--use-bookmarks"] if "@lame:" in source else ["--no-sync-snap"]),
                "--sshkey", "/root/.ssh/syncoid_id",
                source, dest,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        busy = False
        for line in proc.stdout:
            line = line.rstrip()
            print(line, flush=True)
            if "dataset is busy" in line:
                log.warning("dataset busy — killing syncoid, restarting in 5s")
                proc.kill()
                proc.wait()
                busy = True
                break

        if not busy:
            rc = proc.wait()
            if rc == 0:
                log.info("syncoid done: %s -> %s", source, dest)
                return
            log.warning("syncoid exited %d, restarting in 5s", rc)

        restarts += 1
        time.sleep(5)

    log.error("syncoid restarted %d times, giving up", MAX_RESTARTS)
    sys.exit(1)


def wait_smart():
    log.info("checking for in-progress SMART tests")
    for disk in sorted(glob.glob("/dev/sd?")):
        while True:
            r = subprocess.run([SMARTCTL, "-a", disk],
                               capture_output=True, text=True)
            if "Self-test routine in progress" not in r.stdout:
                break
            log.info("%s: SMART test in progress, waiting 60s...", disk)
            time.sleep(60)
    log.info("SMART tests clear")


def wait_scrub():
    while True:
        r = subprocess.run([ZPOOL, "status", "gigavault"],
                           capture_output=True, text=True)
        if "scan:  scrub in progress" not in r.stdout:
            break
        log.info("scrub in progress, waiting 5min...")
        time.sleep(300)


def main():
    args = parse_args()

    with open(args.targets) as f:
        targets = json.load(f)

    # targets is a list of source strings like "backup@proxmox:tank"
    # destination is always gigavault/<hostname>-backup/<pool-name>
    for source in targets:
        # derive dest from source: "backup@proxmox:tank" -> "gigavault/proxmox-backup"
        host_pool = source.split(":")[-1]          # "tank"
        host_name = source.split("@")[-1].split(":")[0]  # "proxmox"
        destpath = "/".join(host_pool.split("/")[1:])
        dest = f"gigavault/{host_name}-backup/{destpath}".rstrip("/")
        run_syncoid(source, dest)

    wait_smart()
    wait_scrub()
    log.info("backup cycle complete")


if __name__ == "__main__":
    main()