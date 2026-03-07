{ pkgs, ... }:
{
  virtualisation.oci-containers.containers."dockge" = {
    image = "louislam/dockge:1";
    autoStart = true;
    # I have dockge behind authentik so the ports should be closed
    # ports = [ "5001:5001" ];
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
      "/opt/dockge/data:/app/data"
      "/opt/stacks:/opt/stacks"
    ];
    extraOptions = [
      "--network=dockge_default"
    ];
    environment = {
      DOCKGE_STACKS_DIR = "/opt/stacks";
    };
  };

  # to replicate the previous setup I had on dockge, I create the dockge_default net
  # which dockge sits on. this is an external network shared with a few containers
  # such as caddy <-> dockge so I can isolate their network.
  # overkill for a purely lan homelab setup but I like to isolate them when I can.

  systemd.services.create-docker-networks = {
    description = "Create Docker networks";
    after = [
      "network.target"
      "docker.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.docker}/bin/docker network create dockge_default || true'";
      RemainAfterExit = true;
    };
  };

  systemd.services."docker-dockge".after = [ "create-docker-networks.service" ];
}
