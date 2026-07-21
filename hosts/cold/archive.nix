# Long-term archive dataset on gigavault.
#
# Purpose: park large files that are written once and thereafter mostly read or
# copied elsewhere. Snapshots exist purely as an undo buffer — the failure this
# guards against is deleting something to free space and only later realising it
# mattered.
#
# The cost model is worth being explicit about, because it is the one surprising
# thing here: snapshots of data that never changes are almost free. They only
# begin pinning space the moment you DELETE, and then they pin it for the whole
# retention window (lab.archive.retention). So a delete does not hand space back
# straight away. `archive-reclaim` below is the deliberate escape hatch.

{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;
  a = lab.archive;

  # Creates the dataset with archive-appropriate properties. Not automatic: the
  # pool is encrypted, so this can only run after cold-unlock, and a service that
  # silently conjures storage is how you end up with an archive on the wrong
  # filesystem.
  archive-init = pkgs.writeShellScriptBin "archive-init" ''
    set -eu
    if [ "$(id -u)" != 0 ]; then echo "must run as root" >&2; exit 1; fi

    if ${pkgs.zfs}/bin/zfs list -H -o name ${a.dataset} >/dev/null 2>&1; then
      echo "${a.dataset} already exists"
    else
      echo "creating ${a.dataset}"
      # recordsize=1M   — large files read back sequentially; fewer, bigger
      #                   records means less metadata and better throughput.
      # compression=zstd — writes are rare so the extra CPU over lz4 is paid
      #                   once and the ratio is kept forever. zstd early-aborts
      #                   on incompressible data, so already-compressed media
      #                   costs nothing.
      # atime=off       — files get copied OUT of here constantly; without this
      #                   every read becomes a metadata write, which also dirties
      #                   snapshots.
      ${pkgs.zfs}/bin/zfs create \
        -o recordsize=1M \
        -o compression=zstd \
        -o atime=off \
        -o xattr=sa \
        -o acltype=posixacl \
        ${a.dataset}
    fi

    install -d -o headpats -g users -m 0775 ${a.root}
    echo "archive ready at ${a.root}"
    ${pkgs.zfs}/bin/zfs get -o property,value \
      recordsize,compression,atime,readonly ${a.dataset}
  '';

  # The disk-space escape hatch. Deleting from the archive frees nothing while a
  # snapshot still references the blocks; this reports exactly how much each
  # snapshot is pinning and can destroy them.
  archive-reclaim = pkgs.writeShellScriptBin "archive-reclaim" ''
    set -eu
    if [ "$(id -u)" != 0 ]; then echo "must run as root" >&2; exit 1; fi

    ZFS=${pkgs.zfs}/bin/zfs
    DS=${a.dataset}

    usage() {
      cat <<'USAGE'
    archive-reclaim — report or reclaim space pinned by archive snapshots

      archive-reclaim                 report only (default, safe)
      archive-reclaim --older-than N  destroy archive snapshots older than N days
      archive-reclaim --all           destroy ALL archive snapshots

    Destroying snapshots is irreversible and removes your ability to undo any
    deletion they covered. Report first, then decide.
    USAGE
    }

    mode=report; days=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --older-than) mode=older; days="''${2:-}"; shift 2 ;;
        --all)        mode=all; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
      esac
    done

    if ! $ZFS list -H -o name "$DS" >/dev/null 2>&1; then
      echo "FAIL: $DS does not exist (pool locked, or archive-init never run)" >&2
      exit 1
    fi

    echo "=== space accounting for $DS ==="
    $ZFS list -o name,used,usedbydataset,usedbysnapshots,avail "$DS"
    held=$($ZFS get -H -p -o value usedbysnapshots "$DS")
    echo
    echo "space pinned by snapshots: $($ZFS get -H -o value usedbysnapshots "$DS")"

    echo
    echo "=== snapshots (oldest first; USED = space freed if destroyed) ==="
    $ZFS list -t snapshot -o name,creation,used -s creation -r "$DS" 2>/dev/null \
      || echo "  (none)"

    count=$($ZFS list -H -t snapshot -o name -r "$DS" 2>/dev/null | wc -l)

    if [ "$mode" = report ]; then
      echo
      echo "SUMMARY: $count snapshot(s), $($ZFS get -H -o value usedbysnapshots "$DS") reclaimable"
      if [ "$held" -eq 0 ] 2>/dev/null; then
        echo "PASS: snapshots are pinning no space — deleting them would free nothing."
      else
        echo "WARN: destroying every snapshot would free $($ZFS get -H -o value usedbysnapshots "$DS")."
        echo "      Re-run with --all (or --older-than N) to actually do it."
      fi
      exit 0
    fi

    # Build the kill list.
    if [ "$mode" = all ]; then
      victims=$($ZFS list -H -t snapshot -o name -s creation -r "$DS" 2>/dev/null)
    else
      case "$days" in
        ""|*[!0-9]*) echo "FAIL: --older-than needs a number of days" >&2; exit 1 ;;
      esac
      cutoff=$(( $(date +%s) - days * 86400 ))
      victims=$($ZFS list -H -p -t snapshot -o name,creation -s creation -r "$DS" 2>/dev/null \
        | ${pkgs.gawk}/bin/awk -v c="$cutoff" '$2 < c { print $1 }')
    fi

    if [ -z "$victims" ]; then echo "nothing matched — nothing to do"; exit 0; fi

    echo
    echo "=== about to DESTROY these snapshots (irreversible) ==="
    echo "$victims" | sed 's/^/  /'
    printf 'type YES to confirm: '
    read -r ans
    [ "$ans" = YES ] || { echo "aborted"; exit 1; }

    echo "$victims" | while read -r s; do
      [ -n "$s" ] || continue
      echo "  destroying $s"
      $ZFS destroy "$s"
    done

    echo
    echo "=== after ==="
    $ZFS list -o name,used,usedbysnapshots,avail "$DS"
    echo "PASS: reclaim complete"
  '';
in
{
  environment.systemPackages = [
    archive-init
    archive-reclaim
  ];

  # ── snapshots ────────────────────────────────────────────────────────────
  services.sanoid = {
    enable = true;

    # Hourly is not about taking hourly snapshots (the template sets hourly=0);
    # it is about OPPORTUNITY. cold is powered off most of the day, so a
    # once-a-day timer could easily never coincide with the machine being awake.
    # Running hourly means whenever cold happens to be up, a due daily/weekly/
    # monthly snapshot gets taken.
    interval = "hourly";

    datasets.${a.dataset} = {
      useTemplate = [ "archive" ];
      recursive = true;
    };

    templates.archive = {
      autosnap = true;
      autoprune = true;
    }
    // a.retention;
  };

  # Same reasoning as `interval` above, from the other direction: if cold was
  # asleep when the timer was due, fire once on boot rather than waiting for the
  # next slot.
  systemd.timers.sanoid.timerConfig.Persistent = true;

  # gigavault is zfs-encrypted, so before cold-unlock runs the archive is not
  # mounted and sanoid would just log failures every hour. Skip cleanly instead.
  systemd.services.sanoid.unitConfig.ConditionPathIsMountPoint = a.root;
}
