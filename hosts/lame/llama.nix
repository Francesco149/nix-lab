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

  llama-cpp-cuda = pkgs.llama-cpp.override ({ cudaSupport = true; });
  llama-cpp-cuda-video = llama-cpp-cuda.overrideAttrs (old: rec {
    pname = "llama-video";

    # must be a valid integer literal in c++
    version = "0x" + (builtins.substring 0 8 src.rev);

    src = pkgs.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      rev = "0adede866ddb2e31992b3792eaea31d18ed89acf";
      hash = "sha256-Z+n7ksjwcbJ1ROmVVtHkEvzIjWfigfWfn+fv5XpjRQ8=";
    };

    npmDepsHash = "sha256-RAFtsbBGBjteCt5yXhrmHL39rIDJMCFBETgzId2eRRk=";

    preConfigure = ''
      prependToVar cmakeFlags "-DLLAMA_BUILD_COMMIT:STRING=${src.rev}"
      pushd ${old.npmRoot}
      npm run build
      popd
    '';

    patches = [
      (pkgs.fetchpatch {
        url = "https://raw.githubusercontent.com/Cobdog/llama-video/27358360bebf4efa30d94513d1d9e4f2e55341cd/patches/video-support-20260424.patch";
        hash = "sha256-C8QZR1SHQp95D3jQHfo2WS66PloYSirrUNeZGZhn4BI=";
      })
    ];
    # drop any existing nixpkgs patches — they may not apply to this commit
    # if the build fails with patch errors, uncomment:
    # patches = [ ... ] (just the llama-video patch, no old.patches)
  });

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
      environment = environment // {
        # hide 3080 from vulkan
        VK_ICD_FILENAMES = radv-icd;
      };
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
      package = llama-cpp-cuda;
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

    video = {
      package = llama-cpp-cuda-video;
      port = lab.ports.llama-video;
      flags = [
        "--host"
        "0.0.0.0"
        "--port"
        (toString lab.ports.llama-video)
        "-c"
        "64000"
        "-ngl"
        "99"
        "--n-cpu-moe"
        #"30" # if using Qwen3.5 35B A3B Q4_K_M
        "33"
        "--jinja"
        "--no-mmap"
        "--kv-unified"
        "--flash-attn"
        "on"
        "--cache-type-k"
        "q4_0"
        "--cache-type-v"
        "q4_0"
        "--temperature"
        "1.0"
        "--top-p"
        "0.95"
        "--top-k"
        "20"
        "--cache-reuse"
        "0"
        "--reasoning"
        "off"
        "-m"
        "${model-dir}/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf"
        #"${model-dir}/HauhauCS/Qwen3.5-35B-A3B-Uncensored-HauhauCS-Aggressive/Qwen3.5-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_M.gguf"
        "--mmproj"
        "${model-dir}/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/mmproj-Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-f16.gguf"
        #"${model-dir}/HauhauCS/Qwen3.5-35B-A3B-Uncensored-HauhauCS-Aggressive/mmproj-Qwen3.5-35B-A3B-Uncensored-HauhauCS-Aggressive-f16.gguf"
      ];
    };
  };

in
{
  systemd.services = lib.mapAttrs' (name: cfg: mkLlamaService ({ inherit name; } // cfg)) instances;
  networking.firewall.allowedTCPPorts = map (cfg: cfg.port) (lib.attrValues instances);
}
