# GPU switcheroo for lame: restores the last-used GPU preset at boot and opens
# the llama ports. The switcher itself lives OUTSIDE nix (like haruness) at
# /opt/ai-lab/gpu-switch (deployed by rsync from this repo's hosts/lame/gpu-switch/)
# so presets can be edited without a rebuild. Nix only provides the boot hook
# and firewall.
#
#   ssh root@lame gpu-switch list
#   ssh root@lame gpu-switch run vision|code-qwen36|gemma26|embed|idle
#
# Ports (see lib/lab.nix): 8080 = 7800XT main slot, 6080 = 3080 embed slot.
{ config, lib, ... }:
let
  inherit (config) lab;
in
{
  systemd.services.gpu-switch-restore = {
    description = "Restore the last GPU preset (gpu-switch)";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ -f /opt/ai-lab/gpu-switch/gpu-switch ] && [ -f /opt/ai-lab/gpu-switch/current ]; then
        /opt/ai-lab/gpu-switch/gpu-switch daemon-run
      fi
    '';
  };

  networking.firewall.allowedTCPPorts = [
    lab.ports.llama-vulkan # 7800XT main slot
    lab.ports.llama-embed  # 3080 slot
    lab.ports.llama-video
  ];
}
