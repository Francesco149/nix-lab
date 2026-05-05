{ config, pkgs, ... }:
{
  # ── ZFS, WoL, remote unlock ──────────────────────────────────────────────
  nut.zfs.pools = [ "lamedata" ];
  nut.initrd-unlock.iface = "enp42s0";

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
