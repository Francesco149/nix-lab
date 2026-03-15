{ config, ... }:
{
  time.timeZone = "Europe/Rome";
  i18n.defaultLocale = "en_US.UTF-8";
  nut.ssh.authorizedKeys = config.lab.ssh.authorized-keys;

  # always skip key verification for new VMs
  programs.ssh.extraConfig = builtins.concatStringsSep "\n" (
    map (host: ''
      Host ${host}
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
    '') config.lab.ssh.no-strict
  );

  security.acme = {
    acceptTerms = true;
    defaults.email = config.lab.mail.main.addr;
  };
}
