# anything that would otherwise be a magic number/string goes here. it's not as
# efficient as surgically scoping everything but much less cumbersome.

rec {
  tailnet.prefix = "100.64.0";

  # change these after deploying and bringing tailscale up on both machines.
  # check `tailscale ip` on each machine or `headscale nodes list` on the relay
  tailnet.mail = "${tailnet.prefix}.1";
  tailnet.relay = "${tailnet.prefix}.2";

  # the windows host that runs the wslop WSL guest. tailscale runs on the
  # windows side; a netsh portproxy forwards :22 into the guest's sshd, so
  # this address doubles as wslop's ssh endpoint (also used by the fish
  # remote-deploy helpers as rd_host).
  tailnet.wslop = "${tailnet.prefix}.9";

  # public ip of your vps
  internet.relay = "198.46.149.19";

  lan.prefix = "10.0.10";
  lan.mask = "${lan.prefix}.0/24";
  lan.code = "${lan.prefix}.53";
  lan.cold = "${lan.prefix}.54";
  lan.mail = "${lan.prefix}.55";
  lan.lame = "${lan.prefix}.56";

  # .6X is reserved for early boot ssh
  lan.cold-unlock = "${lan.prefix}.60";
  lan.lame-unlock = "${lan.prefix}.61";

  # MACs for WoL
  mac.cold = "74:56:3c:fc:9b:30";
  mac.lame = "2c:f0:5d:db:7c:1c";

  # all of these point to internet.relay. see README.md for records setup
  domains.base = "headpats.uk";
  domains.mail = "mail.${domains.base}"; # PTR, spf1, mx records point to this
  domains.fqdn = "smtp.${domains.base}"; # must be different than the relay's
  domains.headscale = "hs.${domains.base}";

  # internal sub-domain for self hosted stuff. it's an actual domain to get
  # actual valid ssl certs, but it doesn't point to anything publicly, the dns
  # server on my router just overrides it.
  domains.internal = "box.${domains.base}";
  domains.nix-cache = "cache.${domains.internal}";
  domains.roundcube = "mail.${domains.internal}";

  mail.main.user = "loli";
  mail.main.addr = mail.main.user + "@" + domains.base;
  mail.master = mail.main.user; # this user is aliased to postmaster
  mail.users = [
    mail.main.user # remember to generate hashed password files, see README
  ];

  mail.aliases.loli = [ "cute" ];

  # ACME account identity is intentionally stable and separate from the primary
  # mailbox so changing mail users does not rotate Let's Encrypt accounts.
  acme.email = "francesco149@gmail.com";

  fzf.excluded = [
    ".git"
    ".nix-defexpr"
    ".direnv"
    "result*"
  ];

  ##################################################################################
  # colors and other visual settings

  colors = {
    base00 = "000000";
    base01 = "545454";
    base02 = "A8A8A8";
    base03 = "A8A8A8";
    base04 = "C0C7C8";
    base05 = "FFFFFF";
    base06 = "FFFFFF";
    base07 = "FFFFFF";

    base08 = "A80000"; # red
    base09 = "A85400"; # orange
    base0A = "A85400"; # yellow
    base0B = "00A800"; # green
    base0C = "00A8A8"; # cyan
    base0D = "0000A8"; # blue
    base0E = "A800A8"; # magenta
    base0F = "A80000";
  };

  ##################################################################################
  # automatic unlock/backup infrastructure

  # the key cold storage uses to ssh into backup targets
  ssh.pub.cold-backup = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOaxTk8yT7OFLBErrylHrdfnTAxGFMcALMXpjMq7aDiU syncoid@cold";

  # backup targets: cold -> syncoid ssh into target -> push to cold
  backup.targets = [
    "backup@proxmox:tank/data"
    "backup@proxmox:tank/proxmox"
    "backup@lame:lamedata"
  ];

  # known hosts for backup service so we can do strict key checking on each target
  ssh.cold-backup-known-hosts = {
    "proxmox".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIrny+0hMgPXGTcMNcZczDVYl+LaQONSrVPGRiogSR9q root@proxmox";
    "lame".publicKey = ssh.host.lame;
  };

  # age key pair used to decrypt the passphrases for ssh unlock
  secrets.age.unlock = "${secrets.dir}/cold-age-key";

  # ssh key pair used by code to ssh into the initrd stage and unlock the file systems
  secrets.ssh.unlock = "${secrets.dir}/cold-unlock-key";
  ssh.pub.unlock = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPwEiN9bssyDBj+Ldj8nbZs/sFoNRNJYrPX9rb+iHnCH unlock@code";

  # known hosts for backup/unlock orchestrator on code
  ssh.host.lame = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPiyiPPDqtIjkp6xeNsigSBkDivCAAgydcUHImaz34qN root@lame";
  ssh.host.cold = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAqjHsgUF2s+MRJqSvyB14w05NXVRoaimZjPyu/S3NYX root@nixos";
  ssh.host.cold-unlock = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOSXuJ592PTKU3Kxo8vcBT8VOnkEXBJVcEjk9vMx1VKx cold-initrd";
  ssh.host.lame-unlock = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMk71LondG3mBFE2pECMWN+iNht3di9Bcla+jkOZX6zy lame-initrd";

  # known hosts for the wslop backup (wslop -> code relay, wslop -> cold push)
  # and for the orchestrator on code to reach wslop
  ssh.host.code = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDS6Yrr49OImcExU3Mx07jEJ3avQkD7k0HqQXq5Zqj4+ root@code";
  ssh.host.wslop = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIACy/6kUkKqi9XZEmTmgYxKk5j4VvdyPx2v1M5SSjHnR root@wslop";

  # wslop cold backup. two kinds of source, pushed with rsync as root@cold
  # into `dataset`:
  #
  #   rootfs  — the WSL guest's own disk (`/`). this is native ext4 inside the
  #             VM, NOT the slow 9p/drvfs windows mount, so it reads at full
  #             speed; rsync only ships deltas, making it a cheap incremental
  #             of the whole rootfs after the first run. (the rootfs lives on
  #             the windows host as a ~400G ext4.vhdx under AppData, but that
  #             blob is locked while WSL runs and useless for file-level
  #             restore, so backing the live `/` up is the right way — not the
  #             vhdx.) "plenty of storage", so only pseudo-fs is excluded.
  #
  #   windows — work that only exists on the windows host. it can only be read
  #             through the slow 9p drvfs mount, so the list is deliberately
  #             narrow: actual work, never the whole C: drive (no Windows/,
  #             Program Files/, AppData/ or the ext4.vhdx). image/video files
  #             in the capture+trace dirs are throwaway and excluded, leaving
  #             the binary traces.
  #
  # WSL2 NAT drops subnet-directed broadcasts (verified empirically), so the
  # guest cannot send WoL packets: when cold is down, wake+unlock is relayed
  # through `cold-unlock --host cold` on code instead.
  backup.wslop =
    let
      # capture/trace dirs keep only the binary traces; rendered frames and
      # video are disposable and otherwise dominate the slow 9p transfer.
      image-junk = [
        "*.png"
        "*.bmp"
        "*.jpg"
        "*.jpeg"
        "*.gif"
        "*.webp"
        "*.mp4"
        "*.mov"
        "*.avi"
        "*.webm"
        "*.mkv"
      ];
    in
    {
      dataset = "gigavault/wslop-backup";
      keep-snapshots = 14;

      rootfs = {
        src = "/";
        excludes = [
          # pseudo filesystems and the windows mounts; rsync -x already keeps
          # these as empty dirs, the explicit excludes also cover bind mounts
          "/proc/*"
          "/sys/*"
          "/dev/*"
          "/run/*"
          "/tmp/*"
          "/var/tmp/*"
          "/mnt/*"
          "/usr/lib/wsl/*"
          "/lost+found"
        ];
      };

      windows = {
        # applied to every windows target on top of any per-target excludes
        common-excludes = [
          "desktop.ini"
          "Thumbs.db"
          "thumbs.db"
          "*.tmp"
        ];

        # backed up by default
        work = [
          { name = "documents"; src = "/mnt/c/Users/headpats/Documents"; } # blender + docs
          { name = "desktop"; src = "/mnt/c/Users/headpats/Desktop"; }
          { name = "pictures"; src = "/mnt/c/Users/headpats/Pictures"; }
          { name = "music"; src = "/mnt/c/Users/headpats/Music"; }
          { name = "password-store"; src = "/mnt/c/Users/headpats/.password-store"; }
          { name = "blender-config"; src = "/mnt/c/Users/headpats/AppData/Roaming/Blender Foundation"; }
          { name = "oss-osr"; src = "/mnt/c/oss-osr"; excludes = image-junk; }
          { name = "osscap"; src = "/mnt/c/osscap"; excludes = image-junk; }
          { name = "openrecet-traces"; src = "/mnt/c/Users/headpats/openrecet-traces"; excludes = image-junk; }
        ];

        # backed up only with `wslop-backup --all`; big and/or re-downloadable
        optional = [
          { name = "downloads"; src = "/mnt/c/Users/headpats/Downloads"; }
          { name = "videos"; src = "/mnt/c/Users/headpats/Videos"; }
          { name = "steam"; src = "/mnt/c/Program Files (x86)/Steam/steamapps"; }
          { name = "gog"; src = "/mnt/c/GOG Games"; }
        ];
      };
    };

  # data for remote unlock and backup scripts

  # edit secrets with:
  #   secret-edit /var/lib/secrets/cold-luks-passphrase.age
  # (custom command that runs age ... | vipe | age ... -o ...)

  unlockables = {
    # host = [ zfs-pool1 ... ]
    # automatically uses host-luks-passphase.age to unlock luks
    # automatically uses zfs-pool1-passphrase to unlock zfs
    cold = [
      "gigavault"
      "gaijin"
    ];

    # zfs pool is unencrypted, luks handles the encryption
    lame = [ ];
  };

  ##################################################################################

  ssh.authorized-keys = [
    # workstation
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF0Hj5jOmw03+LxHO7xOkcPSMknxRXflt+qznZ0SRCQG headpats@cutestation"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJa2cA6+V9KjkEzkgMhoyKBUTOGeJBQpaU5WA3lrRMaF headpats@cutestation"
    # streaming pc
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNTISALC2cQaRAtgsLUK1V5Ko1s8eO8/1WHkdnH/ifiglrbftmfZ72HHSSht54lUsRR6CvGnDRQPJfySI1xCHhg= loli@HCUP"
    # laptop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINJqIAtWyhxUgDI8G9oSyzxEtMggUkBcOcYBfonad6RI deeznuts@MOOPLASTORY"
    # proxmox
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEIRmdPK45tD5E9LWrQlU0Cvh/l/31ceXT6tlwBBLwG4 headpats@proxmox"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC3GITt7Z4V/IwnPKmFEpz7KVXXkcyiDaZvg59lbmcTlamMuHopMGXEdh7u1qKWqkr+agNxaqWpAConEsCwX5GFRaOe/LQFHVneOArXWS/p1xw+ywxlgA8NabsQUlg7GsKW5LbJyALZiS5CCTdEz2yCk/NauR9MMXUNW/ZJEN2QrYNZloYiRLY8XCNMNZPwhaPH4rd/K1Am1ZuTPlyjTfkTEyLRCF025KIMNe16ll2DT9HxHE8dFsenxpj2Jgt9e7wch5Pg5h6L4S83++fEYBxsdXrEPC2Yz7WYc6io7dLk31kUGH0QpCelLyELiWpltnQ8OBJKpHBVQpA5HlQtK5I4uujRG0gtVAMflwkqwh69ahK4fy0+8ESUhC4ACH4AqURFrEOqamXwPIqHgU+8zoS2+kmKD0LmU8O2RSE0CUw55b2f358QACA94QfQX3gPonvdP1gQjK9ODcFrApnDaqyK1kZ4Wno7W1NrOkJE7rbukRaivp0conSKgaOGNFs3tkkSF6HPjddKqHNGMRttZp3d5HoK78h+0EBbryAiQ5EFIEj27eO/qG2iEykXN7rig1ezVkW9kA9vcP3HJyePpTPQQteEdL7ztLZfuUDmr8KNzoPK/L+X1kS+oRS8EjHVOvSVaWkRWGeJn1/8yKKUWBQG96mlPLkeKX7PYlKaCZxeSQ== root@proxmox"
    # dockge + openvscode-server dev vm
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO51fsBkesFI7L3+AH2gcn+lEx9S0XzVRcYf6tFujvIr root@code"
    # inference server
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAyFHy49bkJO5y2k3aVo5Pu9yUnY7lEppQljdxv1GOzp root@lame"
    # cold storage
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK4sAQQHxZNbdyusIsZsh/l5o+N+Rq/r8uBX3hS+60dA root@cold"
  ];

  ssh.no-strict = [ "nixos" ]; # default fresh vm hostname, don't check ssh keys

  # probably never change these unless you know what you're doing.
  # for example, changing smtp-relay won't change the port on postfix.
  # these are purely for labeling at the moment

  ports.ssh = 22;
  ports.ssh-initrd = 2222;
  ports.http = 80;
  ports.https = 443;

  ports.smtp-relay = 25;
  ports.smtps = 465;
  ports.imap = 993;

  ports.headscale = 8080;
  ports-udp.headscale = 41641;
  ports.beszel-agent = 45876;

  ports.openvscode-server = 3010;
  ports.beszel = 8090;
  ports.cache = 8765;
  ports.dmarc-analyzer = 8741;
  ports.roundcube = 3100;
  ports.grammar-helper = 5060;

  # docker containers
  ports.dockge = 5001;
  ports.rackpeek = 8080;
  ports.authentik = 9000;

  # lxc on proxmox
  ports.immich = 2283;

  # inference server
  ports.open-webui = 3000;
  ports.ollama-proxy = 11434;
  ports.llama-vulkan = 8080;
  ports.llama-video = 7080;
  ports.llama-embed = 6080;
  ports.ingest = 8083;

  tailnet.prefixes = [ "${tailnet.prefix}.0/10" ];

  # router ip (default gateway)
  lan.gateway = "${lan.prefix}.1";

  # reverse dns zone designation. it works by reversing the ip address and
  # appending .in-addr.arpa .

  # for example, when you look up my vps's PTR record
  #
  #   $ host 198.46.149.19
  #   19.149.46.198.in-addr.arpa domain name pointer mail.headpats.uk.
  #

  # therefore, 10.in-addr.arpa -> every 10.x.x.x address

  lan.zone = "10.in-addr.arpa";

  secrets.dir = "/var/lib/secrets";
  headscale.db-path = "/var/lib/headscale/db.sqlite";
  headscale.noise.private-key-path = "/var/lib/headscale/noise_private.key";
  derp.urls = [ "https://controlplane.tailscale.com/derpmap/default" ];

  # where the oauth tokens for gmail accounts are stored. this might be used for
  # other tokens as well in the future
  fetchmail.secrets-dir = "${secrets.dir}/fetchmail";

  mail.mkHashedPasswordFileName = user: "${secrets.dir}/${user}-hashed-password";
  mail.messageSizeLimit = 20971520;
}
