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

    plugins = [
      "persistent_login"
      "managesieve"
    ];

    dicts = with pkgs.aspellDicts; [
      # https://search.nixos.org/packages?query=aspellDicts
      en
      en-computers
      it
    ];

    # Account for ~30% size increase due to base64 encoding of attachments
    # https://github.com/roundcube/roundcubemail/issues/7979
    maxAttachmentSize = builtins.floor (lab.mail.messageSizeLimit / 1024 / 1024 / 1.37);

    extraConfig = ''
      $config['imap_host'] = "ssl://${lab.domains.fqdn}";
      $config['smtp_host'] = "ssl://${lab.domains.fqdn}";
      $config['smtp_user'] = "%u";
      $config['smtp_pass'] = "%p";

      $config['managesieve_host'] = "tls://${lab.domains.fqdn}";
      $config['managesieve_port'] = ${toString lab.ports.managesieve};
      $config['managesieve_usetls'] = true;
    '';
  };

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
