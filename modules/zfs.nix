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

    arcMaxBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1288490188;
      description = "Maximum ZFS ARC size in bytes.";
    };
  };

  config = {
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;
    boot.zfs.extraPools = cfg.pools;
    boot.kernelParams = [ "zfs.zfs_arc_max=${toString cfg.arcMaxBytes}" ];

    services.zfs.autoScrub = {
      enable = true;
      interval = "monthly";
      inherit (cfg) pools;
    };
  };
}
