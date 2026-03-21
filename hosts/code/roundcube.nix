{
  config,
  pkgs,
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

    plugins = [
      "persistent_login"
      "archive" # one click archive
    ];

    dicts = with pkgs.aspellDicts; [
      # https://search.nixos.org/packages?query=aspellDicts
      en
      en-computers
      it
    ];

    maxAttachmentSize = lab.mail.messageSizeLimit / 1024 / 1024;

    extraConfig = ''
      $config['imap_host'] = "ssl://${lab.domains.fqdn}";
      $config['smtp_host'] = "ssl://${lab.domains.fqdn}";
      $config['smtp_user'] = "%u";
      $config['smtp_pass'] = "%p";

      $config['archive_mbox'] = 'Archive'; # one click archive folder
    '';
  };

  # by default, roundcube wants to set up its own nginx. we try to preserve as
  # much as possible but change it to localhost on a custom port so we can put
  # it behind caddy like all other services.
  services.nginx.virtualHosts.${lab.domains.roundcube} = {
    forceSSL = false;
    enableACME = false;
    listen = [
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
