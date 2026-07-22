# Read-only network views of cold's operator-facing gigavault datasets.
#
# "Read-only" is deliberately a Samba policy, not a ZFS or Unix-permission
# change: aria2, qBittorrent and an interactive session on cold must keep writing
# to these paths normally. SMB clients may browse/copy, but cannot create,
# rename, edit or delete anything.

{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config) lab;

  # Reuse the interface already declared for cold's initrd unlock rather than
  # growing a second copy of this host-specific constant.
  lanInterface = config.nut.initrd-unlock.iface;

  shareMounts = [
    lab.archive.root
    lab.staging.root
    lab.torrents.root
  ];

  mkReadOnlyShare = path: comment: {
    inherit path comment;
    "browseable" = "yes";
    "guest ok" = "no";
    "read only" = "yes";
    "valid users" = [ "headpats" ];
  };

  samba-set-password = pkgs.writeShellScriptBin "samba-set-password" ''
    set -eu
    if [ "$(id -u)" != 0 ]; then echo "must run as root" >&2; exit 1; fi

    echo 'Set the SMB-only password for user "headpats".'
    echo "It is stored hashed in Samba's persistent passdb, never in the Nix store."
    ${config.services.samba.package}/bin/smbpasswd -a headpats
  '';
in
{
  services.samba = {
    enable = true;

    # The broad module switch opens legacy NetBIOS ports on every interface.
    # This host uses direct SMB over TCP plus interface-scoped rules below.
    openFirewall = false;
    nmbd.enable = false;
    winbindd.enable = false;

    settings = {
      global = {
        security = "user";
        workgroup = "WORKGROUP";
        "netbios name" = "COLD";
        "server string" = "cold storage (read only)";
        "invalid users" = [ "root" ];

        # Authenticated access works with current Windows defaults, including
        # clients that reject guest sessions and require SMB signing. Keep SMB1
        # and the old NetBIOS transport out; Windows Vista+ and current Linux
        # clients negotiate SMB2/3 directly on TCP 445.
        "map to guest" = "Never";
        "server min protocol" = "SMB2_02";
        "server smb transports" = "tcp";
        "disable netbios" = "yes";

        # Do not serve these datasets over tailscale or any future interface
        # just because it appears on cold. Loopback is retained so local Samba
        # administration tools keep working.
        interfaces = [
          "lo"
          lanInterface
        ];
        "bind interfaces only" = "yes";

        # Make this look like a file server to Windows, not a print server.
        "load printers" = "no";
        "disable spoolss" = "yes";
        "printcap name" = "/dev/null";

        # Samba registers _smb._tcp with the Avahi daemon already used by
        # Sunshine. This makes smb://cold.local useful to Linux GUI clients.
        "mdns name" = "mdns";

        # These are large-file, read-mostly datasets; zero-copy reads avoid an
        # unnecessary userspace copy when the negotiated connection permits it.
        "use sendfile" = "yes";
      };

      archive = mkReadOnlyShare lab.archive.root "Long-term archive (read only)";
      staging = mkReadOnlyShare lab.staging.root "Download staging (read only)";
      torrents = mkReadOnlyShare lab.torrents.root "Torrent inbox (read only)";
    };
  };

  # Modern Windows Explorer no longer uses the SMB1 browser service. WSD is the
  # mechanism that makes COLD appear under Network without weakening SMB.
  services.samba-wsdd = {
    enable = true;
    openFirewall = false;
    interface = lanInterface;
    hostname = "cold";
    workgroup = "WORKGROUP";
  };

  # Sunshine already enables Avahi today, but Samba discovery should not depend
  # on an unrelated desktop service remaining enabled forever.
  services.avahi = {
    enable = true;
    publish.enable = true;
  };

  # SMB direct hosting plus WSD, on the physical LAN only. No router forward is
  # needed or wanted.
  networking.firewall.interfaces.${lanInterface} = {
    allowedTCPPorts = [
      445
      5357
    ];
    allowedUDPPorts = [ 3702 ];
  };

  # gigavault is encrypted and mounts after boot-time units have already run.
  # Refuse to serve the empty rootfs mountpoints, then start both SMB and its
  # Windows discovery companion once every declared share is genuinely mounted.
  systemd.services.samba-smbd = {
    after = [ "zfs.target" ];
    unitConfig.ConditionPathIsMountPoint = shareMounts;
  };

  systemd.services.samba-wsdd = {
    after = [
      "network-online.target"
      "zfs.target"
    ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathIsMountPoint = shareMounts;
  };

  systemd.services.samba-mount-watch = {
    description = "Start Samba once all read-only shares are mounted";
    serviceConfig.Type = "oneshot";
    script = ''
      for path in ${lib.escapeShellArgs shareMounts}; do
        if ! ${pkgs.util-linux}/bin/mountpoint -q "$path"; then
          exit 0
        fi
      done

      ${pkgs.systemd}/bin/systemctl start samba-smbd.service samba-wsdd.service
    '';
  };

  systemd.timers.samba-mount-watch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "2min";
      Unit = "samba-mount-watch.service";
    };
  };

  environment.systemPackages = [ samba-set-password ];
}
