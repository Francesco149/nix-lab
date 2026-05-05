# hosts/lame/open-webui.nix
{ config, ... }:
let
  inherit (config) lab;
in
{
  virtualisation.oci-containers = {
    backend = "docker"; # or "podman"

    containers.open-webui = {
      image = "ghcr.io/open-webui/open-webui:main"; # or pin a version

      ports = [
        "0.0.0.0:${toString config.lab.ports.open-webui}:8080"
      ];

      environment = {
        OLLAMA_BASE_URL = "http://host.docker.internal:${toString config.lab.ports.ollama-proxy}";
        SCARF_NO_TELEMETRY = "1";
        DO_NOT_TRACK = "1";
      };

      volumes = [
        "/opt/ai-lab/open-webui-data:/app/backend/data"
      ];

      extraOptions = [
        "--add-host=host.docker.internal:host-gateway"
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [
    config.lab.ports.open-webui
  ];
}
