{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config) lab;
  zfs-mount-all = pkgs.writeShellScriptBin "zfs-mount-all" ''
    # A read-only parent cannot create mountpoint directories for child
    # datasets. Briefly make locally read-only, mounted parents writable so
    # ZFS can create those directories, then restore them immediately.
    status=0
    ${pkgs.zfs}/bin/zfs mount -a || status=$?

    while IFS=$'\t' read -r dataset mounted readonly; do
      [ "$mounted" = yes ] || continue
      [ "$readonly" = on ] || continue
      source=$(${pkgs.zfs}/bin/zfs get -H -o source readonly "$dataset")
      [ "$source" = local ] || continue

      ${pkgs.zfs}/bin/zfs set readonly=off "$dataset" || exit 1
      restore_readonly() {
        ${pkgs.zfs}/bin/zfs set readonly=on "$dataset"
      }
      trap restore_readonly EXIT INT TERM
      ${pkgs.zfs}/bin/zfs mount -a
      mount_status=$?
      restore_readonly || exit 1
      trap - EXIT INT TERM
      [ "$mount_status" -eq 0 ] && status=0 || status=$mount_status
    done < <(${pkgs.zfs}/bin/zfs list -H -t filesystem -o name,mounted,readonly)

    status=0
    ${pkgs.zfs}/bin/zfs mount -a || status=$?
    exit "$status"
  '';
in
{
  users.users.backup = {
    isSystemUser = true;
    group = "backup";
    shell = "${pkgs.bash}/bin/bash";
    home = "/var/lib/backup";
    createHome = true;
    openssh.authorizedKeys.keys = [
      lab.ssh.pub.unlock # allow unlock service to ssh in after full boot
      lab.ssh.pub.cold-backup # allow backup service to copy stuff over ssh
    ];
  };
  users.groups.backup = { };

  # deps for optimal syncoid performance
  environment.systemPackages =
    with pkgs;
    [
      sanoid # optional but nice to have if I ever need to push the other way
      lzop
      mbuffer
      pv
    ]
    ++ [ zfs-mount-all ];

  # zfs-mount is a vendor unit, so the empty entry resets its ExecStart before
  # installing our replacement.
  systemd.services.zfs-mount.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${zfs-mount-all}/bin/zfs-mount-all"
  ];

  # allow orchestrator to unlock pools and shutdown
  security.sudo.extraRules = [
    {
      users = [ "backup" ];
      commands = [
        {
          command = "/run/current-system/sw/bin/shutdown -h now";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/current-system/sw/bin/zfs-mount-all";
          options = [ "NOPASSWD" ];
        }
        # Compatibility for callers deployed before zfs-mount-all.
        {
          command = "/run/current-system/sw/bin/zfs mount -a";
          options = [ "NOPASSWD" ];
        }
      ]
      ++ map (pool: {
        command = "/run/current-system/sw/bin/zfs load-key ${pool}";
        options = [ "NOPASSWD" ];
      }) config.nut.zfs.pools;

      # NOTE: this will need to be optional if I ever have a host that does
      # backup/unlock without ZFS (unlikely)
    }
  ];
}
