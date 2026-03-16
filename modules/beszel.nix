{
  services.beszel.agent = {
    enable = true;
    environmentFile = "/var/lib/secrets/beszel-agent";
    openFirewall = false; # we will use the tailnet ip
  };

  systemd.services.beszel-agent = {
    serviceConfig.SupplementaryGroups = [ "beszel-secrets" ];
  };
}
