{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;
  model-dir = "/opt/ai-lab/models";
  radv-icd = "${pkgs.mesa.drivers}/share/vulkan/icd.d/radeon_icd.x86_64.json";

  mkLlamaService =
    {
      name,
      package,
      port,
      flags,
      environment ? { },
      after ? [ ],
    }:
    lib.nameValuePair "llama-${name}" {
      description = "llama.cpp ${name}";
      after = [
        "network.target"
        "zfs.target"
      ]
      ++ after;
      wantedBy = [ "multi-user.target" ];
      environment = environment;
      serviceConfig = {
        Type = "idle";
        KillSignal = "SIGINT";
        Restart = "on-failure";
        RestartSec = "300";
        PrivateDevices = false;
        ExecStart = "${package}/bin/llama-server ${lib.escapeShellArgs flags}";
      };
    };

  instances = {
    vulkan = {
      package = pkgs.llama-cpp-vulkan;
      port = lab.ports.llama-vulkan;
      environment = {
        VK_ICD_FILENAMES = radv-icd;
      };
      flags = [
        "--host"
        "0.0.0.0"
        "--port"
        (toString lab.ports.llama-vulkan)

        "-c"
        "120000"
        "-ngl"
        "99"
        "--n-cpu-moe"
        "0"
        "--kv-unified"
        "--jinja"

        "--temperature"
        "1.0"
        "--top-p"
        "0.95"
        "--top-k"
        "64"

        "--flash-attn"
        "on"
        "--cache-type-k"
        "q8_0"
        "--cache-type-v"
        "q8_0"

        "-m"
        "${model-dir}/mudler/gemma-4-26B-A4B-it-APEX-GGUF/gemma-4-26B-A4B-APEX-I-Mini.gguf"
        "--mmproj"
        "${model-dir}/unsloth/gemma-4-26B-A4B-it-GGUF/mmproj-F32.gguf"
        "--chat-template-file"
        "/opt/ai-lab/templates/new-chat-template-gemma.jinja"

        "--batch-size"
        "512"
        "-np"
        "4"
        "--cont-batching"
        "--ubatch-size"
        "1024"
      ];
    };

    embed = {
      package = pkgs.llama-cpp;
      port = lab.ports.llama-embed;
      flags = [
        "--host"
        "0.0.0.0"
        "--port"
        (toString lab.ports.llama-embed)
        "--embedding"
        "--batch-size"
        "8192"
        "-m"
        "${model-dir}/nomic-ai/nomic-embed-text-v1.5-GGUF/nomic-embed-text-v1.5.f16.gguf"
      ];
    };
  };

in
{
  systemd.services = lib.mapAttrs' (name: cfg: mkLlamaService ({ inherit name; } // cfg)) instances;
  networking.firewall.allowedTCPPorts = map (cfg: cfg.port) (lib.attrValues instances);
}
