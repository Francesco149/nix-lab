{ config, pkgs, ... }:
let
  inherit (config) lab;
in
{
  users.users.backup = {
    isSystemUser = true;
    group = "backup";
    shell = "${pkgs.bash}/bin/bash";
    home = "/var/lib/backup";
    createHome = true;
    openssh.authorizedKeys.keys = [
      lab.ssh.pub.unlock
    ];
  };
  users.groups.backup = { };

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
