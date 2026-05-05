{ ... }:
{
  disko.devices = {
    disk.nvme0n1 = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            size = "100G";
            content = {
              type = "luks";
              name = "lame-root";
              settings.allowDiscards = true;
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
          data = {
            size = "100%";
            content = {
              type = "luks";
              name = "lame-data";
              # zfs pool created separately after partitioning
              # disko just creates the LUKS container
              content = {
                type = "zfs";
                pool = "lamedata";
              };
            };
          };
        };
      };
    };

    zpool.lamedata = {
      type = "zpool";
      rootFsOptions = {
        compression = "zstd";
        encryption = "off"; # LUKS handles encryption at block level
        "com.sun:auto-snapshot" = "false";
      };
      datasets = {
        "openwebui" = {
          type = "zfs_fs";
          mountpoint = "/opt/ai-lab/open-webui-data";
        };
        "knowledge" = {
          type = "zfs_fs";
          mountpoint = "/opt/ai-lab/knowledge";
        };
        "downloads" = {
          type = "zfs_fs";
          mountpoint = "/opt/ai-lab/downloads";
        };
        "models" = {
          type = "zfs_fs";
          mountpoint = "/opt/ai-lab/models";
        };
        "appstate" = {
          type = "zfs_fs";
          mountpoint = "/opt/ai-lab/data";
        };
      };
    };
  };
}
