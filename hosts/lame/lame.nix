{ config, pkgs, ... }:
{
  imports = [
    ./llama.nix
    ./open-webui.nix
    ./ollama-proxy.nix
    ./ingest.nix
  ];

  # ── ZFS, WoL, remote unlock ──────────────────────────────────────────────
  nut.zfs.pools = [ "lamedata" ];
  nut.initrd-unlock.iface = "enp42s0";
  services.zfs.autoSnapshot.enable = true;
  # remember to do:
  # zfs set com.sun:auto-snapshot=true lamedata
  # zfs allow -u backup hold,send,snapshot,mount

  # ── GPU ──────────────────────────────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = with pkgs; [
    # Vulkan for 7800XT
    vulkan-loader
    vulkan-tools
  ];

  # CUDA for 3080
  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };
  services.xserver.videoDrivers = [ "nvidia" ];

  # Let Docker containers use the 3080 (CUDA / OpenGL / NVENC) WITHOUT vfio
  # passthrough — the host nvidia driver + GL (/run/opengl-driver) is injected into
  # the container (CDI). Powers the interactive GPU sandbox: Godot/OpenGL rendered
  # on the 3080 at native speed, streamed out via Sunshine/Moonlight. Run a GPU
  # container with `docker run --device nvidia.com/gpu=all …` (or `--gpus all`).
  # NOTE: enabling this reconfigures the docker runtime, so `nixos-rebuild switch`
  # restarts dockerd — deploy only when no Docker workload (e.g. a haruness sweep)
  # is mid-run, or it will kill the running containers. The 3080 is freed for this
  # by disabling the llama-embed service (see hosts/lame/llama.nix).
  hardware.nvidia-container-toolkit.enable = true;

  # uinput: virtual mouse/keyboard for the interactive GPU sandbox (Sunshine injects
  # Moonlight input via /dev/uinput). Load it at boot so the sandbox survives reboots.
  boot.kernelModules = [ "uinput" ];

  # Sunshine/Moonlight streaming ports for the interactive GPU sandbox. The container
  # runs with --network host (required so the host udevd's input-hotplug uevents reach
  # its Xorg — how Moonlight mouse/kb works), so Docker no longer publishes ports and
  # the host firewall must allow them directly. See haruness docs/interactive-sandbox.md.
  networking.firewall.allowedTCPPorts = with config.lab.ports; [
    sunshine-https
    sunshine-http
    sunshine-web
    sunshine-rtsp
    haruness-dashboard # the harness dashboard (bun, port 8799) — standing service we poke the GPU sandbox from
  ];
  networking.firewall.allowedUDPPorts = with config.lab.ports-udp; [
    sunshine-video
    sunshine-control
    sunshine-audio
    sunshine-mic
    mdns
  ];

  # make both GPUs visible to the right tools
  environment.variables = {
    # hide 3080 from Vulkan (7800XT only), CUDA still sees it
    VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
  };

  # ── basic system ─────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    git
    nvtopPackages.full # monitor both GPUs
    smartmontools
  ];
}
