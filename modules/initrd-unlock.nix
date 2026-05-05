# modules/initrd-unlock.nix
#
# usage in host config:
#
#   imports = [ ../../modules/initrd-unlock.nix ];
#   nut.initrd-unlock = {
#     ip     = "10.0.10.60";
#     iface  = "enp4s0";
#     nicMod = "r8169";
#   };
#

{ config, lib, ... }:
let
  inherit (config) lab;
  cfg = config.nut.initrd-unlock;
in
{
  options.nut.initrd-unlock = {
    ip = lib.mkOption {
      type = lib.types.str;
      description = "Static IP assigned during initrd (pre-udev rename)";
      default = lab.lan."${config.networking.hostName}-unlock";
    };
    iface = lib.mkOption {
      type = lib.types.str;
      description = "NIC interface name after udev rename (used for ip= param)";
    };
    nicMod = lib.mkOption {
      type = lib.types.str;
      description = "Kernel module for the NIC, loaded early so it's available before udev";
      default = "r8169";
    };
    gateway = lib.mkOption {
      type = lib.types.str;
      default = lab.lan.gateway;
    };
    netmask = lib.mkOption {
      type = lib.types.str;
      default = "255.255.255.0";
    };
    port = lib.mkOption {
      type = lib.types.int;
      default = lab.ports.ssh-initrd;
    };
    hostKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "${lab.secrets.dir}/initrd/ssh_host_ed25519_key" ];
    };
    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ lab.ssh.pub.unlock ];
      description = "SSH public keys allowed to connect to the initrd SSH server";
    };
  };

  config = {
    boot.initrd.kernelModules = [ cfg.nicMod ];

    boot.initrd.network = {
      enable = true;
      ssh = {
        enable = true;
        port = cfg.port;
        hostKeys = cfg.hostKeys;
        authorizedKeys = cfg.authorizedKeys;
      };
    };

    # ip=<client>::<gw>:<mask>:<hostname>:<iface>:off
    # hostname gets a -unlock suffix to distinguish initrd from full-boot host key
    boot.kernelParams = [
      "ip=${cfg.ip}::${cfg.gateway}:${cfg.netmask}:${config.networking.hostName}-unlock:${cfg.iface}:off"
    ];

    networking.interfaces.${cfg.iface}.wakeOnLan.enable = true;
    boot.zfs.requestEncryptionCredentials = false; # we handle this ourselves
  };
}
