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

    services.zfs.autoScrub = {
      enable = true;
      interval = "monthly";
      inherit (cfg) pools;
    };
  };
}
