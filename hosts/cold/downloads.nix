# Download manager on cold, for archive.org and other direct-HTTP sources —
# the cases where a torrent is dead or was never offered.
#
# Two tools, because they solve different halves:
#
#   aria2 + AriaNg   the general fetcher and its web UI. Multi-connection,
#                    resumable, retrying. archive.org in particular serves large
#                    files slowly and drops connections, so resume is not a
#                    nicety here — a single-stream wget of a 40G item will fail
#                    and start over. aria2 also speaks BitTorrent/magnet, so a
#                    half-working torrent can still be tried from the same UI.
#
#   ia (internetarchive)  the official archive.org CLI. Works in item
#                    identifiers rather than URLs, so `ia download <id>` fetches
#                    a whole item with its metadata and verifies checksums, and
#                    can filter by glob to skip the derivative formats archive.org
#                    generates. Use this when you know the item; use aria2 for a
#                    bare URL.
#
# Everything lands in lab.staging (its own dataset — see lib/lab.nix) for manual
# sorting into gigavault/archive afterwards.

{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;
  s = lab.staging;

  # Same shape as torrent-storage-init/archive-init: creating storage is a
  # deliberate act, and it needs the pool unlocked anyway.
  staging-init = pkgs.writeShellScriptBin "staging-init" ''
    set -eu
    if [ "$(id -u)" != 0 ]; then echo "must run as root" >&2; exit 1; fi

    if ${pkgs.zfs}/bin/zfs list -H -o name ${s.dataset} >/dev/null 2>&1; then
      echo "${s.dataset} already exists"
    else
      echo "creating ${s.dataset}"
      # Same large-file tuning as the archive, but NOT snapshotted: this is a
      # scratch area and snapshotting abandoned downloads would pin space for
      # months. compression=lz4 rather than zstd — data here is transient, so
      # spend as little CPU as possible; it gets recompressed with zstd if and
      # when it is promoted into the archive.
      ${pkgs.zfs}/bin/zfs create \
        -o recordsize=1M \
        -o compression=lz4 \
        -o atime=off \
        -o xattr=sa \
        -o acltype=posixacl \
        ${s.dataset}
    fi

    # aria2 writes as its own user; headpats needs to sort afterwards.
    install -d -o aria2 -g users -m 0775 ${s.root}
    echo "staging ready at ${s.root}"
  '';

  aria2-set-secret = pkgs.writeShellScriptBin "aria2-set-secret" ''
    set -eu
    if [ "$(id -u)" != 0 ]; then echo "must run as root" >&2; exit 1; fi
    install -d -m 0700 ${lab.secrets.dir}
    ${pkgs.openssl}/bin/openssl rand -hex 32 > ${lab.secrets.aria2}
    chmod 0400 ${lab.secrets.aria2}
    echo "wrote ${lab.secrets.aria2}"
    systemctl try-restart aria2.service
    echo
    echo "AriaNg needs this secret once, under its aria2 settings:"
    cat ${lab.secrets.aria2}
  '';

  # Convenience wrapper: fetch an archive.org item straight into staging.
  # `ia` defaults to the current directory, which on a box you ssh into is
  # /root — the wrong filesystem entirely.
  ia-fetch = pkgs.writeShellScriptBin "ia-fetch" ''
    set -eu
    if [ $# -lt 1 ]; then
      echo "usage: ia-fetch <archive.org-identifier> [extra ia download args...]" >&2
      echo "  e.g. ia-fetch some-item --glob='*.iso'" >&2
      exit 1
    fi
    id="$1"; shift
    dest=${s.root}
    echo "fetching '$id' into $dest"
    # --checksum verifies against archive.org's manifest and skips files already
    # present, which makes re-running after an interruption cheap and safe.
    exec ${pkgs.internetarchive}/bin/ia download --destdir "$dest" --checksum "$id" "$@"
  '';
in
{
  environment.systemPackages = [
    staging-init
    aria2-set-secret
    ia-fetch
    pkgs.internetarchive # the `ia` CLI itself, for metadata/search/upload
    pkgs.aria2 # aria2c for one-off command-line fetches
  ];

  # ── aria2 daemon ─────────────────────────────────────────────────────────
  services.aria2 = {
    enable = true;
    rpcSecretFile = lab.secrets.aria2;

    # aria2 is HTTP-out only here; the BitTorrent side is qBittorrent's job
    # (hosts/cold/torrents.nix), which already owns the forwarded peer port. So
    # nothing needs opening inbound.
    openPorts = false;

    settings = {
      dir = s.root;
      rpc-listen-port = lab.ports.aria2-rpc;

      # Bind RPC to the LAN, not just localhost, so AriaNg in a browser on
      # another machine can reach it.
      rpc-listen-all = true;
      rpc-allow-origin-all = true;

      # Resume, hard. This is the whole reason aria2 is here rather than wget:
      # archive.org stalls and drops large transfers routinely.
      continue = true;
      max-tries = 0; # retry forever rather than abandoning a 40G item
      retry-wait = 30;
      max-concurrent-downloads = 3;

      # archive.org rate-limits aggressively per connection. A handful of
      # connections helps; more than ~5 gets throttled or refused, and being
      # greedy against a free archive is rude besides.
      split = 4;
      max-connection-per-server = 4;
      min-split-size = "16M";

      # Survive restarts: keep the queue on disk and reload it on start.
      save-session = "/var/lib/aria2/aria2.session";
      input-file = "/var/lib/aria2/aria2.session";
      save-session-interval = 60;
      auto-save-interval = 60;

      # Sane files rather than aria2's default of appending to whatever exists.
      auto-file-renaming = true;
      allow-overwrite = false;

      file-allocation = "none"; # ZFS is copy-on-write; preallocating is wasted IO
    };
  };

  # Same gate as qBittorrent: gigavault is encrypted, so before cold-unlock the
  # staging dir is an empty mountpoint on the rootfs. Without this aria2 would
  # happily download into the rootfs and have it shadowed on the next mount.
  systemd.services.aria2 = {
    after = [ "zfs.target" ];
    unitConfig.ConditionPathIsMountPoint = s.root;
  };

  # And the same 2-minute poll that starts qBittorrent once the pool appears —
  # a .path unit cannot see a mount landing over a directory.
  systemd.services.aria2-mount-watch = {
    description = "Start aria2 once the staging dataset is mounted";
    serviceConfig.Type = "oneshot";
    script = ''
      if ${pkgs.util-linux}/bin/mountpoint -q ${s.root}; then
        systemctl start aria2.service
      fi
    '';
  };

  systemd.timers.aria2-mount-watch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "2min";
      Unit = "aria2-mount-watch.service";
    };
  };

  # ── AriaNg web UI ────────────────────────────────────────────────────────
  # A static single-page app that talks to the RPC port from the browser, so it
  # needs nothing but a file server.
  services.caddy = {
    enable = true;
    virtualHosts.":${toString lab.ports.aria2-web}".extraConfig = ''
      root * ${pkgs.ariang}/share/ariang
      file_server
    '';
  };

  networking.firewall.allowedTCPPorts = with lab.ports; [
    aria2-rpc
    aria2-web
  ];
}
