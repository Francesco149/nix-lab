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

{
  config,
  lib,
  pkgs,
  ...
}:
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

    # at some point the kernel params stoped working, likely because NixOS
    # switched to systemd initrd. let's pin it enabled in case it ever changes
    # again. now we have to initialize networking using systemd
    boot.initrd.systemd.enable = true;

    boot.initrd.systemd.network = {
      enable = true;

      networks."10-${cfg.iface}" = {
        matchConfig.Name = cfg.iface;
        address = [ "${cfg.ip}/24" ];
        gateway = [ cfg.gateway ];
        dhcpV4Config = {
          UseDNS = false;
        };
      };
    };

    boot.initrd.network = {
      enable = true;

      # after fully booting, we use dhcpcd and assign leases from the router.
      # only unlock has a hardcoded network config
      flushBeforeStage2 = true;

      ssh = {
        enable = true;
        port = cfg.port;
        hostKeys = cfg.hostKeys;
        authorizedKeys = cfg.authorizedKeys;
      };
    };

    networking.interfaces.${cfg.iface}.wakeOnLan.enable = true;
    boot.zfs.requestEncryptionCredentials = false; # we handle this ourselves

    # with systemd initrd cryptsetup-askpass is gone so we have to roll our own
    # tool to desliver the password.

    # we need grep to extract the socket from the ask file and the systemd tool
    # to actually write the password into the socket which is already in
    # /usr/sbin

    boot.initrd.systemd.extraBin = {
      grep = "${pkgs.gnugrep}/bin/grep";
      busybox = "${pkgs.busybox}/bin/busybox"; # nice to have for debugging
      systemd-reply-password = "${config.boot.initrd.systemd.package}/lib/systemd/systemd-reply-password";
    };

    boot.initrd.systemd.contents."/etc/unlock-stdin".source = pkgs.writeShellScript "unlock-stdin" ''
      #!/bin/sh
      for i in $(seq 1 30); do
        ASK=$(ls /run/systemd/ask-password/ask.* 2>/dev/null | head -1)
        [ -n "$ASK" ] && break
        sleep 0.5
      done

      [ -z "$ASK" ] && { echo "unlock-stdin: no ask file appeared" >&2; exit 1; }

      SOCK=$(grep '^Socket=' "$ASK" | cut -d= -f2)
      [ -z "$SOCK" ] && { echo "unlock-stdin: no socket in ask file" >&2; exit 1; }

      systemd-reply-password 1 "$SOCK"
    '';

    # Because we set up pre-boot networking, we have to properly take ownership
    # of the interface post full boot or the initrd configuration will stick.
    networking.useNetworkd = true;
    services.resolved.enable = true; # should already be on by default

    systemd.network.networks."10-${cfg.iface}" = {
      matchConfig.Name = cfg.iface;
      networkConfig.DHCP = "yes";
      dhcpV4Config = {
        UseDNS = true;
        UseDomains = true; # pick up the .soy search domain from router
        RouteMetric = 10;
      };
    };
  };
}
