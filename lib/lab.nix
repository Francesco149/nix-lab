# anything that would otherwise be a magic number/string goes here. it's not as
# efficient as surgically scoping everything but much less cumbersome.

rec {
  tailnet.prefix = "100.64.0";

  # change these after deploying and bringing tailscale up on both machines.
  # check `tailscale ip` on each machine or `headscale nodes list` on the relay
  tailnet.mail = "${tailnet.prefix}.1";
  tailnet.relay = "${tailnet.prefix}.2";

  # public ip of your vps
  internet.relay = "198.46.149.19";

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

  mail.main.user = "loli";
  mail.main.addr = mail.main.user + "@" + domains.base;
  mail.master = mail.main.user; # this user is aliased to postmaster
  mail.users = [
    mail.main.user # remember to generate hashed password files, see README
  ];

  fzf.excluded = [
    ".git"
    ".nix-defexpr"
    ".direnv"
    "result*"
  ];

  ssh.authorized-keys = [
    # workstation
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF0Hj5jOmw03+LxHO7xOkcPSMknxRXflt+qznZ0SRCQG headpats@cutestation"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOggpEtx3bYTi/Qr59aaAi2RyAwvsBv04tyPVPGd/9j4 headpats@DESKTOP-2FRVAC7"
    # streaming pc
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNTISALC2cQaRAtgsLUK1V5Ko1s8eO8/1WHkdnH/ifiglrbftmfZ72HHSSht54lUsRR6CvGnDRQPJfySI1xCHhg= loli@HCUP"
    # laptop
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINJqIAtWyhxUgDI8G9oSyzxEtMggUkBcOcYBfonad6RI deeznuts@MOOPLASTORY"
    # proxmox
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEIRmdPK45tD5E9LWrQlU0Cvh/l/31ceXT6tlwBBLwG4 headpats@proxmox"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC3GITt7Z4V/IwnPKmFEpz7KVXXkcyiDaZvg59lbmcTlamMuHopMGXEdh7u1qKWqkr+agNxaqWpAConEsCwX5GFRaOe/LQFHVneOArXWS/p1xw+ywxlgA8NabsQUlg7GsKW5LbJyALZiS5CCTdEz2yCk/NauR9MMXUNW/ZJEN2QrYNZloYiRLY8XCNMNZPwhaPH4rd/K1Am1ZuTPlyjTfkTEyLRCF025KIMNe16ll2DT9HxHE8dFsenxpj2Jgt9e7wch5Pg5h6L4S83++fEYBxsdXrEPC2Yz7WYc6io7dLk31kUGH0QpCelLyELiWpltnQ8OBJKpHBVQpA5HlQtK5I4uujRG0gtVAMflwkqwh69ahK4fy0+8ESUhC4ACH4AqURFrEOqamXwPIqHgU+8zoS2+kmKD0LmU8O2RSE0CUw55b2f358QACA94QfQX3gPonvdP1gQjK9ODcFrApnDaqyK1kZ4Wno7W1NrOkJE7rbukRaivp0conSKgaOGNFs3tkkSF6HPjddKqHNGMRttZp3d5HoK78h+0EBbryAiQ5EFIEj27eO/qG2iEykXN7rig1ezVkW9kA9vcP3HJyePpTPQQteEdL7ztLZfuUDmr8KNzoPK/L+X1kS+oRS8EjHVOvSVaWkRWGeJn1/8yKKUWBQG96mlPLkeKX7PYlKaCZxeSQ== root@proxmox"
    # dockge + openvscode-server dev vm
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO51fsBkesFI7L3+AH2gcn+lEx9S0XzVRcYf6tFujvIr root@code"
  ];

  ssh.no-strict = [ "nixos" ]; # default fresh vm hostname, don't check ssh keys

  # probably never change these unless you know what you're doing.
  # for example, changing smtp-relay won't change the port on postfix.
  # these are purely for labeling at the moment

  ports.ssh = 22;
  ports.http = 80;
  ports.https = 443;

  ports.smtp-relay = 25;
  ports.smtps = 465;
  ports.smtp = 587;
  ports.imap = 993;
  ports.managesieve = 4190;

  ports.headscale = 8080;
  ports-udp.headscale = 41641;
  ports.beszel-agent = 45876;

  ports.openvscode-server = 3010;
  ports.beszel = 8090;
  ports.cache = 8765;

  # docker containers
  ports.kurrier = 3000;
  ports.kurrier-dav = 3001;
  ports.dockge = 5001;
  ports.rackpeek = 8080;
  ports.authentik = 9000;

  # lxc on proxmox
  ports.immich = 2283;

  tailnet.prefixes = [ "${tailnet.prefix}.0/10" ];

  # router ip (default gateway)
  lan.gateway = "10.0.10.1";

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
}
