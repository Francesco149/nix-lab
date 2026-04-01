{ pkgs, config, ... }:

let
  fetchScript = ./mail-fetch/fetch.py;
  secretsDir = config.lab.fetchmail.secrets-dir;
  vmailUser = config.mailserver.vmailUserName;
  targetEmail = config.lab.mail.main.addr;
in
{
  systemd.services.mail-fetch = {
    description = "Fetch Gmail accounts via IMAP OAuth2";
    after = [
      "network-online.target"
      "dovecot2.service"
    ];
    wants = [ "network-online.target" ];

    # Pass the Nix-controlled paths as environment variables
    environment = {
      DOVECOT_LDA = "${pkgs.dovecot}/libexec/dovecot/dovecot-lda";
      DOVECOT_CONF = "${config.services.dovecot2.configFile}";
      TARGET_EMAIL = "${targetEmail}";
    };

    serviceConfig = {
      Type = "oneshot";
      User = vmailUser;
      ExecStart = "${pkgs.python3}/bin/python3 ${fetchScript} ${secretsDir}";
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
