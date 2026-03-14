{ config, ... }:
{
  nut.ssh.authorizedKeys = config.lab.ssh.authorized-keys;

  # always skip key verification for new VMs
  programs.ssh.extraConfig = builtins.concatStringsSep "\n" (
    map (host: ''
      Host ${host}
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
    '') config.lab.ssh.no-strict
  );
}
