# qBittorrent on cold, with its inbox on a dedicated gigavault dataset.
#
# Two things about cold shape this whole file:
#
#   1. cold is normally POWERED OFF. It wakes for the nightly backup and powers
#      itself back down unless /tmp/stay exists, so torrents only make progress
#      while the machine happens to be up. qBittorrent's resume data is written
#      to the profile dir on every shutdown, so a session picks up exactly where
#      it left off — which is why nothing here tries to keep cold awake.
#
#   2. gigavault is zfs-ENCRYPTED. On a fresh boot its key is not loaded, so
#      /gigavault/torrents is just an empty directory sitting on the rootfs.
#      Starting qBittorrent at that moment would quietly write the profile and
#      any downloads into the rootfs, and the next `zfs mount` would shadow the
#      lot — the same class of bug lame's docker data-root hit. Hence the
#      mountpoint gate below.

{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;
  t = lab.torrents;

  # qBittorrent.conf, rendered here rather than through the module's
  # `serverConfig` so we own the ExecStartPre and can splice the web UI password
  # in from the secrets dir at runtime (see installConfig).
  #
  # Keys use qBittorrent's `Section\Sub\Key` backslash convention.
  configFile = pkgs.writeText "qBittorrent.conf" ''
    [LegalNotice]
    Accepted=true

    [BitTorrent]
    Session\DefaultSavePath=${t.complete}
    Session\TempPath=${t.incomplete}
    Session\TempPathEnabled=true
    Session\Port=${toString lab.ports.torrent}

    ; ── connectivity ──────────────────────────────────────────────────────
    ; The peer port is statically forwarded on the opnsense box, so UPnP/NAT-PMP
    ; is off: leaving it on just races the static rule and re-maps the port to
    ; something the forward does not point at.
    Session\UseUPnP=false
    Session\UseRandomPort=false

    ; Peer discovery. DHT and LSD find peers when a tracker is down or the
    ; torrent is trackerless; PeX trades peers with the swarm. All three are what
    ; make a poorly-seeded torrent actually connect.
    Session\DHTEnabled=true
    Session\PeXEnabled=true
    Session\LSDEnabled=true

    ; 0 = prefer encryption but accept plaintext. 1 would REQUIRE it and quietly
    ; cut off every peer that cannot, which costs more peers than it gains.
    Session\Encryption=0

    ; cold has a 1 Gb link and 12 threads; the stock 200/500 caps are the usual
    ; reason a big swarm never fills the pipe.
    Session\MaxConnections=1000
    Session\MaxConnectionsPerTorrent=200
    Session\MaxUploads=32
    Session\MaxUploadsPerTorrent=8

    ; Unthrottled. cold is on the LAN and only awake in bursts, so a rate limit
    ; here mostly just wastes the window.
    Session\GlobalDLSpeedLimit=0
    Session\GlobalUPSpeedLimit=0

    ; Anti-corruption: do not sparse-allocate onto ZFS, and re-check on resume so
    ; a hard power cut (cold gets those by design) cannot poison a torrent.
    Session\Preallocation=false
    Session\ValidateHTTPSTrackerCertificate=true

    [Preferences]
    General\Locale=en
    Downloads\SavePath=${t.complete}
    Downloads\TempPath=${t.incomplete}
    Downloads\TempPathEnabled=true
    Downloads\ScanDirsV2=@Variant(\0\0\0\x1c\0\0\0\0)

    WebUI\Enabled=true
    WebUI\Address=*
    WebUI\Port=${toString lab.ports.qbittorrent}
    WebUI\Username=headpats
    WebUI\Password_PBKDF2=@WEBUI_PASSWORD@

    ; The web UI is LAN/tailnet only (the peer port is the only thing forwarded),
    ; but still require auth — cold is reachable from every host in the lab.
    WebUI\LocalHostAuth=true
    WebUI\CSRFProtection=true
    WebUI\ClickjackingProtection=true
    WebUI\HostHeaderValidation=false
  '';

  # Installs the config, then substitutes the web UI password from the secrets
  # dir. Runs with a `+` prefix (see serviceConfig) so it executes as root
  # outside the unit's sandbox — the qbittorrent user cannot read /var/lib/secrets.
  installConfig = pkgs.writeShellScript "qbittorrent-install-config" ''
    set -eu
    dest="${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf"
    install -Dm600 -o ${config.services.qbittorrent.user} -g ${config.services.qbittorrent.group} \
      ${configFile} "$dest"

    if [ -r "${lab.secrets.qbittorrent}" ]; then
      # The stored value is `@ByteArray(<b64>:<b64>)` — base64 plus punctuation
      # that contains no `|` and no `&`, so it is safe as a sed replacement with
      # a `|` delimiter without further escaping.
      pw="$(cat "${lab.secrets.qbittorrent}")"
      ${pkgs.gnused}/bin/sed -i "s|@WEBUI_PASSWORD@|$pw|" "$dest"
    else
      # No secret provisioned yet: drop the placeholder line entirely so
      # qBittorrent falls back to generating a temporary password and logging it.
      echo "qbittorrent: ${lab.secrets.qbittorrent} missing — using a temporary" \
           "password, check 'journalctl -u qbittorrent' and run qbittorrent-set-password" >&2
      ${pkgs.gnused}/bin/sed -i '/@WEBUI_PASSWORD@/d' "$dest"
    fi
  '';

  # Generates qBittorrent's PBKDF2 value and drops it in the secrets dir.
  # Format is `@ByteArray(<b64 salt>:<b64 key>)`, PBKDF2-HMAC-SHA512, 100k
  # iterations, 64-byte key, 16-byte salt.
  qbittorrent-set-password = pkgs.writeShellScriptBin "qbittorrent-set-password" ''
    set -eu
    if [ "$(id -u)" != 0 ]; then echo "must run as root" >&2; exit 1; fi

    printf 'new qBittorrent web UI password for user "headpats": '
    stty -echo; read -r pw; stty echo; printf '\n'
    if [ -z "$pw" ]; then echo "empty password, aborting" >&2; exit 1; fi

    install -d -m 0700 ${lab.secrets.dir}
    PW="$pw" ${pkgs.python3}/bin/python3 -c '
import base64, hashlib, os, sys
pw = os.environ["PW"].encode()
salt = os.urandom(16)
key = hashlib.pbkdf2_hmac("sha512", pw, salt, 100000, 64)
sys.stdout.write("@ByteArray(%s:%s)" % (
    base64.b64encode(salt).decode(), base64.b64encode(key).decode()))
' > ${lab.secrets.qbittorrent}
    chmod 0400 ${lab.secrets.qbittorrent}
    echo "wrote ${lab.secrets.qbittorrent}"

    systemctl try-restart qbittorrent.service
    echo "done — web UI: http://${lab.lan.cold}:${toString lab.ports.qbittorrent}"
  '';

  # One-shot provisioning for the dataset. Not run automatically: creating a
  # dataset needs the pool unlocked, and a service that silently creates storage
  # is exactly how you end up with an inbox on the wrong filesystem.
  torrent-storage-init = pkgs.writeShellScriptBin "torrent-storage-init" ''
    set -eu
    if [ "$(id -u)" != 0 ]; then echo "must run as root" >&2; exit 1; fi

    if ! ${pkgs.zfs}/bin/zfs list -H -o name ${t.dataset} >/dev/null 2>&1; then
      echo "creating ${t.dataset}"
      # recordsize=1M: torrent payloads are big media files read back
      # sequentially while seeding. atime=off so seeding does not turn every
      # read into a write. compression stays on (lz4 aborts early on the
      # already-compressed media, so it costs ~nothing and wins on the rest).
      ${pkgs.zfs}/bin/zfs create \
        -o recordsize=1M \
        -o atime=off \
        -o compression=lz4 \
        -o xattr=sa \
        -o acltype=posixacl \
        ${t.dataset}
    else
      echo "${t.dataset} already exists"
    fi

    install -d -o ${config.services.qbittorrent.user} -g ${config.services.qbittorrent.group} -m 0775 \
      ${t.root} ${t.incomplete} ${t.complete} ${t.watch}
    echo "storage ready at ${t.root}"
    systemctl start qbittorrent.service || true
  '';
in
{
  services.qbittorrent = {
    enable = true;
    profileDir = "/var/lib/qBittorrent";
    webuiPort = lab.ports.qbittorrent;
    torrentingPort = lab.ports.torrent;

    # Opened explicitly below so every hole in cold's firewall is greppable in
    # one place; the module's openFirewall would also miss the UDP half.
    openFirewall = false;
  };

  systemd.services.qbittorrent = {
    after = [ "zfs.target" ];

    # The gate. If the dataset is not mounted the unit is SKIPPED (condition
    # failed, not failed) rather than starting and writing to the rootfs.
    unitConfig.ConditionPathIsMountPoint = t.root;

    serviceConfig = {
      # mkForce: replaces the nixpkgs module's own ExecStartPre, which installs
      # its `serverConfig` file. We render the config ourselves (see configFile)
      # so the password can be spliced in at runtime. `+` = run as root, outside
      # the sandbox, so it can read the secrets dir.
      ExecStartPre = lib.mkForce [ "+${installConfig}" ];
      ReadWritePaths = [ t.root ];
    };
  };

  # Starting qBittorrent once the pool comes up.
  #
  # A systemd .path unit would be the obvious tool, but it cannot see this: the
  # inotify watch lands on the *unmounted* /gigavault directory, and mounting a
  # filesystem over a directory generates no event for the watcher underneath.
  # gigavault's key is loaded by `cold-unlock` long after boot, so we poll. The
  # start is a no-op when the unit is already running, and the mountpoint check
  # keeps it silent until the pool is actually there.
  systemd.services.qbittorrent-mount-watch = {
    description = "Start qBittorrent once its ZFS dataset is mounted";
    serviceConfig.Type = "oneshot";
    script = ''
      if ${pkgs.util-linux}/bin/mountpoint -q ${t.root}; then
        systemctl start qbittorrent.service
      fi
    '';
  };

  systemd.timers.qbittorrent-mount-watch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "2min";
      Unit = "qbittorrent-mount-watch.service";
    };
  };

  # ── firewall ─────────────────────────────────────────────────────────────
  # Web UI: LAN + tailnet only, by virtue of nothing forwarding it at the router.
  # Peer port: TCP for peers, UDP for uTP and DHT, on the same number. This is
  # the pair that must be forwarded to lan.cold on the opnsense box — inbound
  # peers are the single biggest lever on swarm connectivity.
  networking.firewall.allowedTCPPorts = with lab.ports; [
    qbittorrent
    torrent
  ];
  networking.firewall.allowedUDPPorts = [ lab.ports-udp.torrent ];

  environment.systemPackages = [
    qbittorrent-set-password
    torrent-storage-init
  ];
}
