{ config, lib, ... }:
{
  services.beszel.agent = lib.mkIf config.nut.monitoring {
    enable = true;
    environmentFile = "/etc/secrets/beszel-agent";
    openFirewall = false; # we will use the tailnet ip
  };

  systemd.services.beszel-agent = lib.mkIf config.nut.monitoring {
    serviceConfig.SupplementaryGroups = [ "beszel-secrets" ];
  };
}
