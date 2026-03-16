{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;
in
{
  services.roundcube = {
    enable = true;
    hostName = lab.domains.roundcube;

    package = pkgs.roundcube.withPlugins (
      plugins: with plugins; [
        # https://search.nixos.org/packages?query=roundcubePlugins
        persistent_login
      ]
    );

    dicts = with pkgs.aspellDicts; [
      # https://search.nixos.org/packages?query=aspellDicts
      en
      en-computers
      it
    ];

    # Account for ~30% size increase due to base64 encoding of attachments
    # https://github.com/roundcube/roundcubemail/issues/7979
    maxAttachmentSize = builtins.floor (lab.mail.messageSizeLimit / 1024 / 1024 / 1.37);

    # The postgres socket file is named after the port, so when I changed it the
    # socket moved to /run/postgresql/.s.PGSQL.XXXX but roundcube is still trying
    # the default .s.PGSQL.5432.
    extraConfig = ''
      $config['imap_host'] = "ssl://${lab.domains.fqdn}";
      $config['smtp_host'] = "ssl://${lab.domains.fqdn}";
      $config['smtp_user'] = "%u";
      $config['smtp_pass'] = "%p";

      # he generated DSN uses unix(/run/postgresql) without a port, and the psql
      # call in the setup script also has no port, so both fail against my
      # custom port
      $config['db_dsnw'] = 'pgsql://roundcube@unix(/run/postgresql:${toString lab.ports.postgresql})/roundcube';
    '';
  };

  # this is the service that initializes the database. we need to tell it to use
  # the custom postgresql port, too.
  systemd.services.roundcube-setup.environment.PGPORT = toString lab.ports.postgresql;

  # by default, roundcube wants to set up its own nginx. we try to preserve as
  # much as possible but change it to localhost on a custom port so we can put
  # it behind caddy like all other services.
  services.nginx.virtualHosts.${lab.domains.roundcube} = {
    forceSSL = lib.mkForce false;
    enableACME = lib.mkForce false;
    listen = lib.mkForce [
      {
        addr = "127.0.0.1";
        port = lab.ports.roundcube;
      }
    ];
  };

  services.caddy.virtualHosts."${lab.domains.roundcube}".extraConfig = ''
    reverse_proxy localhost:${toString lab.ports.roundcube}
  '';
}
