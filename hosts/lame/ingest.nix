# hosts/lame/ingest.nix
{ config, pkgs, ... }:
let
  # llama-video PyPI package isn't in nixpkgs, build it ourselves
  llama-video-py = pkgs.python3Packages.buildPythonPackage rec {
    pname = "llama_video";
    version = "0.1.3";
    pyproject = true;

    src = pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-0s1QX7y2r5+YASj/RVGVFRH1vI+FF3dUdZOAZzUigx4=";
    };

    build-system = [ pkgs.python3Packages.hatchling ];

    dependencies = with pkgs.python3Packages; [
      fastapi
      httpx
      numpy
      pillow
      pydantic
      pydantic-settings
      uvicorn
    ];

    doCheck = false;
  };

  python-full = pkgs.python3.withPackages (
    ps:
    with ps;
    [
      fastapi
      uvicorn
      httpx
      youtube-transcript-api
      trafilatura
      opencv-python
    ]
    ++ [ llama-video-py ]
  );

  src = "/opt/ai-lab/ingest";
in
{
  systemd.services.ingest = {
    description = "AI content ingestion service";
    after = [
      "network.target"
      "zfs.target"
      "llama-vulkan.service"
      "llama-embed.service"
    ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      INGEST_CONFIG = "/opt/ai-lab/data/ingest-config.toml";
      WHISPER_BIN = "${pkgs.whisper-cpp}/bin/whisper-cpp";
      WHISPER_MODEL = "/opt/ai-lab/models/whisper/ggml-medium.bin";
    };

    serviceConfig = {
      Type = "simple";
      WorkingDirectory = src;
      ExecStart = "${python-full}/bin/python ${src}/run_api.py";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  networking.firewall.allowedTCPPorts = [ config.lab.ports.ingest ];
}
