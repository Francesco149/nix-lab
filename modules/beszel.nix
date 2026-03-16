{ config, ... }:
{
  services.beszel.agent = {
    enable = true;
    environmentFile = "${config.lab.secrets.dir}/beszel-agent";
    openFirewall = false; # we will use the tailnet ip
  };

  systemd.services.beszel-agent = {
    serviceConfig.SupplementaryGroups = [ "beszel-secrets" ];
  };
}
