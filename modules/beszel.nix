{ config, lib, ... }:
{
  services.beszel.agent = {
    enable = true;
    environmentFile = "${config.lab.secrets.dir}/beszel-agent";
    openFirewall = false; # we will use the tailnet ip
  };

  systemd.services.beszel-agent = {
    serviceConfig = {
      User = lib.mkForce "beszel";
      DynamicUser = lib.mkForce false;
      PrivateUsers = lib.mkForce false;
      DeviceAllow = [
        "/dev/nvidia0 rw"
        "/dev/nvidia-caps rw"
        "/dev/nvidiactl rw"
        "/dev/nvidia-modeset rw"
        "/dev/nvidia-uvm rw"
        "/dev/nvidia-uvm-tools rw"
      ];
      PrivateDevices = lib.mkForce false;
      DevicePolicy = "auto"; # or "closed" with proper allows
    };
  };

  users.users.beszel = {
    isSystemUser = true;
    group = "beszel";
    # needs access to GPU devices
    extraGroups = [
      "render"
      "video"
      "beszel-secrets"
    ];
  };
  users.groups.beszel = { };
  users.groups.beszel-secrets = { };
}
