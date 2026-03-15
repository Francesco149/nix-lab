{ pkgs, config, ... }:

let
  fetchScript = ./mail-fetch/fetch.py;
  secretsDir = config.lab.fetchmail.secrets-dir;
  vmailUser = config.mailserver.vmailUserName;
  domain = config.lab.domains.base;
  mainUser = config.lab.mail.main.user;
  maildir = "/var/vmail/${domain}/${mainUser}/mail/";
in
{
  systemd.services.mail-fetch = {
    description = "Fetch Gmail accounts via IMAP OAuth2";
    after = [
      "network-online.target"
      "dovecot2.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = vmailUser;
      ExecStart = "${pkgs.python3}/bin/python3 ${fetchScript} ${secretsDir} ${maildir}";
    };
  };

  systemd.timers.mail-fetch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      Unit = "mail-fetch.service";
    };
  };
}
