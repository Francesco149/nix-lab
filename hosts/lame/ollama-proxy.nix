# hosts/lame/ollama-proxy.nix
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;

  python = pkgs.python3.withPackages (
    ps: with ps; [
      fastapi
      uvicorn
      httpx
      aiofiles
      # tomllib is stdlib in python 3.11+, no package needed
    ]
  );

  # the repo itself lives outside the nix store so config.toml and
  # sessions.json can be edited without a rebuild
  src = "/opt/ai-lab/ollama-proxy";

  # DISABLED for now (2026-06-16): ollama-proxy bridges to llama-vulkan, which is
  # disabled to keep the 7800XT free for haruness harness dev (see llama.nix +
  # ../../WORKDOC.md). Flip to true to restore it together with llama-vulkan.
  enable = false;
in
lib.mkIf enable {
  systemd.services.ollama-proxy = {
    description = "Ollama proxy (llama.cpp bridge + agentic loop)";
    after = [
      "network.target"
      "llama-vulkan.service"
    ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      # config_loader.py checks this env var first
      OLLAMA_PROXY_CONFIG = "/opt/ai-lab/data/ollama-proxy-config.toml";
    };

    serviceConfig = {
      Type = "simple";
      WorkingDirectory = src;
      ExecStart = "${python}/bin/python ${src}/proxy.py";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  networking.firewall.allowedTCPPorts = [
    lab.ports.ollama-proxy
  ];
}
