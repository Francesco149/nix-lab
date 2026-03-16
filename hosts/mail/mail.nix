{ config, ... }:
{
  imports = [
    ./mail-fetch.nix
  ];

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

    # help improve email security across the internet by sending feedback on
    # authentication failures, spoofing attempts, and TLS encryption issues.
    dmarcReporting.enable = true;
    tlsrpt.enable = true;
    systemContact = config.lab.mail.main.addr;

    # since 26.05 we explicitly use nginx for the cert
    x509.useACMEHost = config.mailserver.fqdn;

    loginAccounts = builtins.listToAttrs (
      map (user: {
        name = "${user}@${config.lab.domains.base}";
        value = {
          hashedPasswordFile = config.lab.mail.mkHashedPasswordFileName user;
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
      config.lab.ports.smtps
      config.lab.ports.managesieve
      config.lab.ports.beszel-agent
    ];
  };

  # tunnel beszel agent port to the remote relay through headscale. at the
  # moment, this is needed because my beszel container can't see the tailnet,
  # but I'm planning to fix it

  services.nginx = {
    enable = true;
    streamConfig = ''
      upstream beszel_agent {
        server ${config.lab.tailnet.relay}:${toString config.lab.ports.beszel-agent};
      }

      server {
        listen ${toString config.lab.ports.beszel-agent};
        proxy_pass beszel_agent;
      }
    '';
  };

}
