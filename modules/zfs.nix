# modules/zfs.nix
#
# usage in host config:
#
#   imports = [ ../../modules/zfs.nix ];
#   nut.zfs.pools = [ "tank" ];
#

{ config, lib, ... }:
let
  cfg = config.nut.zfs;
in
{
  options.nut.zfs = {
    pools = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  config = {
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;
    boot.zfs.extraPools = cfg.pools;
    boot.kernelParams = [ "zfs.zfs_arc_max=1288490188" ];

    services.zfs.autoScrub = {
      enable = true;
      interval = "monthly";
      inherit (cfg) pools;
    };
  };
}
