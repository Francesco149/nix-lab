{ pkgs, ... }:
{
  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    docker-compose
  ];

  # accept all connections on the docker interfaces.
  # this is equivalent to the default docker behaviour on other distros.
  # without this, containers wouldn't be able to see lan ip's.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s 172.16.0.0/12 -j nixos-fw-accept
  '';

  virtualisation.oci-containers.backend = "docker";
}
