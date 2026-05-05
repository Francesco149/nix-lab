{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) lab;

  # RADV (Mesa) is better than amdvlk for compute — use it for the 7800XT
  # Reference the store path directly so the service environment is hermetic
  radv-icd = "${pkgs.mesa.drivers}/share/vulkan/icd.d/radeon_icd.x86_64.json";

  llama-vulkan = pkgs.llama-cpp-vulkan;
  model-dir = "/opt/ai-lab/models";
  model-path = "${model-dir}/mudler/gemma-4-26B-A4B-it-APEX-GGUF/gemma-4-26B-A4B-APEX-I-Mini.gguf";
  mmproj-path = "${model-dir}/unsloth/gemma-4-26B-A4B-it-GGUF/mmproj-F32.gguf";
  template-path = "/opt/ai-lab/templates/new-chat-template-gemma.jinja";

in
{
  systemd.services.llama-vulkan = {
    description = "llama.cpp Vulkan inference server (7800XT)";
    after = [
      "network.target"
      "zfs.target"
    ];
    wantedBy = [ "multi-user.target" ];

    # don't start until the model file is actually there
    unitConfig.ConditionPathExists = model-path;

    environment = {
      # restrict Vulkan to the 7800XT only — hides the 3080
      VK_ICD_FILENAMES = radv-icd;
    };

    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "5s";
      User = "root";

      ExecStart = lib.concatStringsSep " " [
        "${llama-vulkan}/bin/llama-server"
        "--host 0.0.0.0"
        "--port ${toString lab.ports.llama-vulkan}"
        "-c 120000"
        "-m ${model-path}"
        "-ngl 99"
        "--n-cpu-moe 0"
        "--kv-unified"
        "--batch-size 512"
        "-np 4"
        "--cont-batching"
        "--jinja"
        "--ubatch-size 1024"
        "--temperature 1.0"
        "--top-p 0.95"
        "--top-k 64"
        "--flash-attn on"
        "--cache-type-k q8_0"
        "--cache-type-v q8_0"
        "--mmproj ${mmproj-path}"
        "--chat-template-file ${template-path}"
      ];
    };
  };

  # make llama-server available on PATH for manual use
  environment.systemPackages = [ llama-vulkan ];

  networking.firewall.allowedTCPPorts = [ lab.ports.llama-vulkan ];
}
