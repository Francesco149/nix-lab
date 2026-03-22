{ config, ... }:
{
  imports = [
    ./mail-fetch.nix
    ./dmarc.nix
  ];

  # because of the mail server, dns resolutuon goes through kresd which uses
  # cloudflare. this allows it to see our local domains by redirecting
  # resolution for back to my router so we can see the package cache.
  services.kresd.extraConfig = ''
    modules = { 'policy' }
    policy.add(policy.suffix(policy.FORWARD('${config.lab.lan.gateway}'), {
      todname('${config.lab.domains.internal}')
    }))
  '';

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
  services.nginx.enable = true;
  services.nginx.virtualHosts.${config.mailserver.fqdn}.enableACME = true;

  mailserver = {
    enable = true;
    stateVersion = 3;
    fqdn = config.lab.domains.fqdn;
    domains = [ config.lab.domains.base ];

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
        value =
          let
            baseAliases =
              if user == config.lab.mail.master then
                [
                  "postmaster@${config.lab.domains.base}"
                ]
              else
                [ ];

            extraAliases =
              map (alias: "${alias}@${config.lab.domains.base}")
                (config.lab.mail.aliases or { }).${user} or [ ];

            allAliases = baseAliases ++ extraAliases;
          in
          {
            hashedPasswordFile = config.lab.mail.mkHashedPasswordFileName user;
          }
          // (if allAliases != [ ] then { aliases = allAliases; } else { });
      }) config.lab.mail.users
    );

  };

  # managesieve based editors are too clunky. it's just easier to write the
  # sieve script manually and copy it over, without dealing with ui limitations
  # with nested conditions and such. I can also version control this which can
  # be nice.

  # I'm not going to commit the script to my public repo for privacy reaons, but
  # if you do have it your flake you can use sieve.scripts.before instead of
  # extraConfig to manage it declaratively.

  services.dovecot2.extraConfig = ''
    plugin {
      sieve_before = /etc/dovecot/sieve/headpats-before.sieve
    }
  '';

  # only for the home lan for mail clients to use. not exposed to the internet
  networking.firewall = {
    allowedTCPPorts = [
      config.lab.ports.imap
      config.lab.ports.smtps
      config.lab.ports.beszel-agent
    ];
  };

}
