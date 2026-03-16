{ pkgs, config, ... }:
{
  virtualisation.oci-containers.containers."dockge" = {
    image = "louislam/dockge:1";
    autoStart = true;

    ports =
      let
        p = toString config.lab.ports.dockge;
      in
      [ "127.0.0.1:${p}:${p}" ];

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

  # to replicate the previous setup I had on dockge, I create the dockge_default
  # net which dockge sits on. this is an external network shared with a few
  # containers such as caddy <-> dockge so I can isolate their network. overkill
  # for a purely lan homelab setup but I like to isolate them when I can.

  # This has become even more overkill as I've been migrating containers to
  # NixOS, however it's always nice to have at my disposal when I happen to need
  # 2 containers to see eachother without opening ports.

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
