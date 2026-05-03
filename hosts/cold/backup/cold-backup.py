import glob
import logging
import subprocess
import sys
import time

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


def run_syncoid():
    restarts = 0
    while restarts < MAX_RESTARTS:
        log.info("starting syncoid (attempt %d)", restarts + 1)
        proc = subprocess.Popen(
            [
                SYNCOID,
                "--recursive",
                "--no-privilege-elevation",
                "--no-sync-snap",
                "--sshkey", "/root/.ssh/syncoid_id",
                "--exclude-datasets", "tank/tmp",
                "backup@proxmox:tank", "gigavault/proxmox-backup",
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
                log.warning("dataset busy — killing syncoid and restarting in 5s")
                proc.kill()
                proc.wait()
                busy = True
                break

        if not busy:
            rc = proc.wait()
            if rc == 0:
                log.info("syncoid done")
                return
            log.warning("syncoid exited with code %d, restarting in 5s", rc)

        restarts += 1
        time.sleep(5)

    log.error("syncoid restarted %d times, giving up", MAX_RESTARTS)
    sys.exit(1)


def wait_smart():
    log.info("checking for in-progress SMART tests")
    for disk in sorted(glob.glob("/dev/sd?")):
        while True:
            r = subprocess.run(
                [SMARTCTL, "-a", disk],
                capture_output=True, text=True,
            )
            if "Self-test routine in progress" not in r.stdout:
                break
            log.info("%s: SMART test in progress, waiting 60s...", disk)
            time.sleep(60)
    log.info("SMART tests clear")


def wait_scrub():
    while True:
        r = subprocess.run(
            [ZPOOL, "status", "gigavault"],
            capture_output=True, text=True,
        )
        if "scan:  scrub in progress" not in r.stdout:
            break
        log.info("scrub in progress, waiting 5min...")
        time.sleep(300)


run_syncoid()
wait_smart()
wait_scrub()
log.info("backup cycle complete")