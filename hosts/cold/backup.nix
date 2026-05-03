{ config, pkgs, ... }:
let
  inherit (config) lab;

  # XXX: transient dataset busy states will make syncoid hang indefinitely,
  # seemingly on the receiving side. not sure what is causing this, maybe it's
  # not waiting long enough for the dataset to settle.

  # the only way to work around this is to hard kill it and restart it until it
  # completes with no dataset busy errors

  cold-backup = pkgs.writeShellScriptBin "cold-backup" ''
    exec ${pkgs.python3}/bin/python3 ${pkgs.writeText "cold-backup.py" ''
      import subprocess, sys, time, os, datetime

      LOG = "/var/log/cold-backup.log"
      SYNCOID = "${pkgs.sanoid}/bin/syncoid"
      SMARTCTL = "${pkgs.smartmontools}/bin/smartctl"
      ZPOOL   = "/run/current-system/sw/bin/zpool"
      MAX_RESTARTS = 200

      def log(msg):
          line = f"[{datetime.datetime.now().astimezone().isoformat(timespec='seconds')}] {msg}"
          print(line, flush=True)
          with open(LOG, "a") as f:
              f.write(line + "\n")

      def run_syncoid():
          restarts = 0
          while restarts < MAX_RESTARTS:
              log(f"starting syncoid (attempt {restarts + 1})")
              proc = subprocess.Popen(
                  [
                      SYNCOID,
                      "--recursive",
                      "--no-privilege-elevation",
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
                  log(line)
                  if "dataset is busy" in line:
                      log("dataset busy detected — killing syncoid and restarting in 5s")
                      proc.kill()
                      proc.wait()
                      busy = True
                      break

              if not busy:
                  rc = proc.wait()
                  if rc == 0:
                      log("syncoid done")
                      return
                  else:
                      log(f"syncoid exited with code {rc}, restarting in 5s")

              restarts += 1
              time.sleep(5)

          log(f"ERROR: syncoid restarted {MAX_RESTARTS} times, giving up")
          sys.exit(1)

      def wait_smart():
          log("checking for in-progress SMART tests")
          import glob
          disks = sorted(glob.glob("/dev/sd?"))
          for disk in disks:
              while True:
                  r = subprocess.run(
                      [SMARTCTL, "-a", disk],
                      capture_output=True, text=True
                  )
                  if "Self-test routine in progress" not in r.stdout:
                      break
                  log(f"  {disk}: SMART test in progress, waiting 60s...")
                  time.sleep(60)
          log("SMART tests clear")

      def wait_scrub():
          while True:
              r = subprocess.run(
                  [ZPOOL, "status", "gigavault"],
                  capture_output=True, text=True
              )
              if "scan:  scrub in progress" not in r.stdout:
                  break
              log("scrub in progress, waiting 5min...")
              time.sleep(300)

      run_syncoid()
      wait_smart()
      wait_scrub()
      log("backup cycle complete")
    ''}
  '';

in
{
  environment.systemPackages = [ cold-backup ];

  # the full backup cycle service, triggered remotely by the orchestrator
  systemd.services.cold-backup = {
    description = "Cold storage backup cycle";
    after = [
      "zfs.target"
      "network.target"
    ];
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
  security.sudo.extraRules = [
    {
      users = [ "backup" ];
      commands = [
        {
          command = "${pkgs.systemd}/bin/systemctl start cold-backup.service";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  programs.ssh.knownHosts = {
    "proxmox".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIrny+0hMgPXGTcMNcZczDVYl+LaQONSrVPGRiogSR9q root@proxmox";
  };
}
