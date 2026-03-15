{ config, ... }:
{
  nut.deploy.host = "nix-mail";

  # relay only for outbound mail, so it comes from the vps ip. the relay's
  # domain needs to be different than the domain used by the mail server at
  # home. this is to avoid a loop. for example:
  #
  #   mail server at home: smtp.headpats.uk (also points to vps ip)
  #      relay on the vps: mail.headpats.uk (needs to match ptr)
  #

  services.postfix.settings.main = {
    relayhost = [
      "${config.lab.tailnet.relay}:${toString config.lab.ports.smtp-relay}"
    ];
    myhostname = config.lab.domains.fqdn;
  };

  # Enable ACME HTTP-01 challenge with nginx.
  # this auto generates and renews a cert for the domain
  services.nginx.virtualHosts.${config.mailserver.fqdn}.enableACME = true;

  mailserver = {
    enable = true;
    stateVersion = 3;
    fqdn = config.lab.domains.fqdn;
    domains = [ config.lab.domains.base ];

    # enables filters using sieve scripts
    enableManageSieve = true;

    # STARTTLS on port 587/tcp disabled by default since 25.11
    enableSubmission = true;
    enableSubmissionSsl = true;

    # since 26.05 we explicitly use nginx for the cert
    x509.useACMEHost = config.mailserver.fqdn;

    loginAccounts = builtins.listToAttrs (
      map (user: {
        name = "${user}@${config.lab.domains.base}";
        value = {
          hashedPasswordFile = "/var/lib/secrets/${user}-hashed-password";
        }
        // (
          if user == config.lab.mail.master then
            {
              aliases = [ "postmaster@${config.lab.domains.base}" ];
            }
          else
            { }
        );
      }) config.lab.mail.users
    );

  };

  # only for the home lan for mail clients to use. not exposed to the internet
  networking.firewall = {
    allowedTCPPorts = [
      config.lab.ports.imap
      config.lab.ports.smtp
      config.lab.ports.managesieve
    ];
  };

}
