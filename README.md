# nix-lab

My personal NixOS configuration. Not intended to be used directly, but feel free
to poke around for reference or inspiration.

Built with [nut](https://github.com/Francesco149/nut), my own flake
library that cuts out the boilerplate of wiring up deploy-rs, home-manager, and
flake-parts. If you are building something similar, that is probably a better
starting point than this repo.

---

## machines

| host     | description                                                                               |
| -------- | ----------------------------------------------------------------------------------------- |
| `code`   | Proxmox VM (home) — openvscode-server, dockge, caddy (reverse proxy), beszel hub          |
| `mail`   | Proxmox VM (home) — nixos-mailserver (dovecot + postfix), Gmail IMAP sync, DMARC analyzer |
| `relay`  | VPS (198.46.149.19) — headscale, postfix relay, nginx stream proxy                        |
| `immich` | Proxmox LXC (home, not NixOS) — Immich photo server, iGPU HW transcoding + OpenVINO       |

---

## hardware

### home server (Proxmox host)

Mini-PC running [Proxmox VE](https://www.proxmox.com/):

- **CPU**: Intel N300
- **RAM**: 16 GB
- **Storage**: 2 TB M.2 NVMe SSD + 2 TB SATA SSD, in ZFS RAIDZ1

Both `code`, `mail`, and `immich` run on this box.

> **Thermal note**: the SATA SSD physically blocks the fan, so it runs warm. The
> fans kick in around 80 °C and consistently pull temps back down to ~60 °C. It's
> been stable, just not cool.

### router

Same mini-PC form factor running OPNsense, stock 512 GB SSD. No thermal issues
since there's no SATA drive blocking the fan.

### VPS (`relay`)

[RackNerd](https://racknerd.com/) — cheapest plan from a New Year's deal:

- **vCPU**: 1
- **RAM**: 1 GB (~30% used)
- **Disk**: 24 GB (~30% used)
- **Bandwidth**: 2 TB/month (barely touched)

CPU sits essentially idle.

---

## structure

```text
hosts/
  code/
    configuration.nix         # hardware/boot config
    code.nix                  # machine-specific NixOS config
    caddy.nix                 # caddy reverse proxy with cloudflare DNS plugin
    cache.nix                 # nginx-based nix binary cache proxy
    dockge.nix                # dockge docker stack manager (NixOS OCI container)
    openvscode-server.nix     # openvscode-server NixOS service
    hm/
      home.nix                # per-machine home-manager config
  mail/
    configuration.nix         # hardware/boot config
    mail.nix                  # mailserver, postfix outbound relay, nginx ACME
    mail-fetch.nix            # systemd service+timer to pull Gmail via IMAP OAuth2
    dmarc.nix                 # dmarc-analyzer service + LAN firewall rules
    mail-fetch/
      fetch.py                # Python script: OAuth2 token refresh + IMAP fetch
                              #   into Maildir
  relay/
    configuration.nix         # hardware/boot config
    relay.nix                 # headscale, postfix relay, nginx stream proxy
modules/
  beszel.nix                  # beszel agent — applied globally to all hosts
  tailscale-home-lan.nix      # shared tailscale config for home machines
  hm/                         # shared home-manager modules
    fish/
      init.fish               # prompt, base aliases, fzf config
      dev.fish                # deploy helpers, nix dev workflow functions
lib/
  lab.nix                     # all magic numbers: IPs, domains, ports, paths
utils/
  gmail-oauth.py              # one-time OAuth2 token generation for Gmail accounts
```

---

## architecture overview

```text
internet → relay (198.46.149.19)
             ├── port 25   → stream proxy → mail:25   (inbound SMTP relay)
             ├── port 80   → stream proxy → mail:80   (ACME HTTP-01)
             ├── port 443  → nginx (headscale at hs.headpats.uk)
             └── headscale → tailnet (100.64.0.0/10)
                               ├── relay  (100.64.0.2)
                               ├── mail   (100.64.0.1)
                               └── code   (100.64.0.5)

mail (home, Proxmox VM)
  ├── nixos-mailserver (dovecot IMAP + postfix)
  │     fqdn: smtp.headpats.uk
  │     domain: headpats.uk
  │     ACME: HTTP-01 via nginx (port 80 tunneled through relay)
  ├── postfix outbound → relayhost: 100.64.0.2:25
  ├── mail-fetch timer (every 5 min)
  │     fetch.py /var/lib/secrets/fetchmail /var/vmail/headpats.uk/loli/mail/
  ├── dmarc-analyzer (port 8741, LAN-only, firewall allows code only)
  └── beszel-agent → hub on code (over tailnet)

code (home, Proxmox VM)
  ├── caddy (NixOS service, ports 80/443, cloudflare DNS-01 for ACME)
  │     reverse proxies: dockge, authentik, openvscode-server, beszel hub,
  │                      immich, nix cache, rackpeek, mail relay UIs, LAN devices
  ├── beszel hub (hw.box.headpats.uk)
  │     agents connect directly over tailnet (no SSH tunnel)
  │       ├── code  — tailnet-ip:beszel-agent-port
  │       ├── mail  — tailnet-ip:beszel-agent-port
  │       └── relay — tailnet-ip:beszel-agent-port
  └── beszel-agent (self-monitoring, same as all other hosts)

immich (home, Proxmox LXC — not NixOS, provisioned via Proxmox VE Community Scripts)
  ├── Immich server (port 2283, proxied through code's caddy at img.box.headpats.uk)
  ├── hardware video transcoding via passed-through iGPU
  └── OpenVINO ML acceleration (smart search, face recognition)

relay (VPS)
  └── beszel-agent → hub on code (over tailnet)
```

Outbound mail leaves from the relay's public IP (`198.46.149.19 / mail.headpats.uk`)
so SPF and PTR both resolve correctly. The mail server's own hostname is
`smtp.headpats.uk` to avoid a relay loop (relay is `mail.headpats.uk`).

The beszel agent module (`modules/beszel.nix`) is applied globally to all hosts
via `flake.nix`. Each agent communicates with the hub on `code` directly over
the tailnet (`openFirewall = false`). There is no SSH tunnel needed.

---

## opnsense (`uwusense.soy`)

The home network edge is managed by OPNsense running on a dedicated mini-PC.

### PPPoE optimizations (critical)

Because FreeBSD defaults to single-core processing for PPPoE, these tunables are
applied to distribute the load across all available cores, preventing
bottlenecks during high packet volumes:

- `net.isr.dispatch = deferred`
- `net.isr.maxthreads = -1`

### interfaces & networks

| interface   | physical          | network          | description                                                    |
| :---------- | :---------------- | :--------------- | :------------------------------------------------------------- |
| **WAN**     | `pppoe0`          | DHCP / PPPoE     | Primary internet connection.                                   |
| **LAN**     | `igc1`            | `10.0.10.1/24`   | Main trusted network (`.soy` domain).                          |
| **Homelab** | `vlan01` (tag 20) | `10.0.30.1/24`   | Isolated lab network. Unused as I don't have a managed switch. |
| **Modem**   | `igc0`            | `192.168.1.2/24` | Direct connection to the ISP modem for management.             |

### DNS & DHCP

DNS is split between **Unbound** and **Dnsmasq**:

- **Unbound (Port 53):** Primary resolver with DNSBL (adblocking).
- **Dnsmasq (Port 53053):** Handles DHCP leases and local `.soy` resolution.
- **Host Overrides:** Wildcard records route `*.box.headpats.uk` to `10.0.10.53`
  (Caddy).

### traffic shaping (bufferbloat)

Traffic shaping using `fq_codel` is configured to mitigate bufferbloat:

- **Download:** 100 Mbit/s
- **Upload:** 18 Mbit/s

### auth

- **Authentik LDAP:** Management access is authenticated via the central
  Authentik instance (`code.soy:389`). Completely optional as you can still log
  in as root when it's down, this was purely an experiment and did not achieve
  what I wanted, which is being able to use the authentik session to bypass
  credentials entry like I do with services that support SSO.

---

## dockge containers (code)

Dockge is used as a low-friction way to spin up and experiment with containers.
Stacks here are considered temporary — once something proves useful it gets
migrated into the NixOS config properly.

| stack          | description                                                                                                                                                |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `immich-stack` | Small utility that automatically stacks the RAW and compressed versions of photos in Immich. Immich itself runs as a Proxmox LXC — see the machines table. |
| `authentik`    | Identity provider / SSO. Protects internal services via Caddy's `forward_auth` — see the `(authentik)` snippet in `caddy.nix`.                             |

---

## dmarc-analyzer

[dmarc-analyzer](https://github.com/Francesco149/dmarc-analyzer) is a local
flake input. It runs on `mail` and is reverse-proxied through `code`'s caddy at
`dmarc.box.headpats.uk`, behind authentik.

Two moving parts:

- **`dmarc-scanner`** — oneshot systemd service on a timer. Runs as
  `vmailUser` (needs read access to the `700`-mode Maildir). Extracts DMARC
  aggregate report XMLs from the postmaster inbox and writes `reports.json` to
  `/var/lib/dmarc-analyzer/data/`.
- **`dmarc-server`** — minimal Python HTTP server serving the self-contained
  frontend and `reports.json`. Bound to `mail`'s LAN IP.

In my case, I have sieve rules set up to automatically move the DMARC reports to
a separate folder and point the analyzer to that, but the script is designed to
be able to scan a mixed, even huge inbox quickly and efficiently.

Firewall rules in `hosts/mail/dmarc.nix` allow only `code`'s LAN IP to reach
port 8741 on `mail`. Caddy proxies through to `mail.soy` (local DNS alias) and
wraps it with authentik auth.

The flake input is wired in `flake.nix`:

```nix
inputs.dmarc-analyzer.url = "git+file:///opt/src/dmarc-analyzer";
# ...
hosts.mail = [
  inputs.dmarc-analyzer.nixosModules.dmarc-analyzer
  # ...
];
```

Config in `hosts/mail/dmarc.nix`:

```nix
services.dmarc-analyzer = {
  enable = true;
  mailDir = "/var/vmail/${lab.domains.base}/${lab.mail.master}/mail";
  scanUser = config.mailserver.vmailUserName;
  port = lab.ports.dmarc-analyzer;
  listenHost = lab.lan.mail;
};
```

---

## fish commands

Custom fish functions live in `modules/hm/fish/dev.fish` and are loaded on
machines with the `interactive` module. They assume you're in the `nix-lab` repo
directory.

### `deploy [args]`

Wraps `deploy-rs`. Detects whether the current machine is the designated
workstation (`rd_host = 100.64.0.6`). If it is, runs `deploy` directly. If not
(e.g. on a laptop), delegates to `remote-deploy` so builds run on the faster
machine.

```sh
deploy            # deploy all nodes
deploy .#mail     # deploy one node
```

### `remote-deploy [args]`

Deploys from a non-workstation machine by:

1. `rsync-shallow`ing the repo and local flake inputs (`nut`, `dmarc-analyzer`)
   to the workstation under `/tmp/`
2. SSHing in, initialising shallow git repos from those copies, overriding the
   flake inputs to point at them, then running `deploy`

Unstaged changes deploy cleanly without polluting git history, and heavy Nix
eval/builds happen on the faster workstation.

### `rsync-shallow`

`rsync -a` with the fzf exclude flags (`.git`, `.direnv`, `result*`, etc.).
Used internally by `remote-deploy`.

### `diff-system <host> [ssh-key]`

Builds the new system closure, fetches the current one from the target, and runs
`nvd diff` between them. Useful before deploying.

```sh
diff-system mail
diff-system relay ~/.ssh/id_relay
```

### `build-system <host>`

Builds the system closure locally (via `nom`) without deploying. Good for
catching build errors early.

```sh
build-system code
```

### `check-inputs`

Scans `flake.lock` for duplicate versions of the same input (e.g. two different
`nixpkgs` revisions pulled in by different deps) and prints a full input list
with nar hashes.

### `refresh-nix-tokens [host]`

Pushes a fresh GitHub token (from `gh auth token`) into
`~/.config/nix/nix.conf` on a remote host. Useful when private flake inputs
fail to fetch on a fresh VM.

```sh
refresh-nix-tokens              # targets root@nixos (default fresh VM hostname)
refresh-nix-tokens root@mail
```

### `ns [pkg ...] [flake#pkg ...]`

Shorthand for `nix shell`. Bare names get `nixpkgs#` prepended automatically;
full flake refs pass through unchanged.

```sh
ns git ripgrep                 # → nix shell nixpkgs#git nixpkgs#ripgrep
ns github:some/flake#tool      # → nix shell github:some/flake#tool
```

---

## roundcube gotchas

The NixOS `services.roundcube` module has a few rough edges when running behind
Caddy with a non-default PostgreSQL port.

### nginx SSL conflict

The module defaults to `forceSSL = true`, which makes nginx try to bind 443 and
an HTTP→HTTPS redirect on port 8000. Both conflict with existing services. Since
Caddy handles TLS termination, force both off and pin the listen address to
localhost:

```nix
services.nginx.virtualHosts.${host} = {
  forceSSL = lib.mkForce false;
  enableACME = lib.mkForce false;
  listen = lib.mkForce [
    { addr = "127.0.0.1"; port = lab.ports.roundcube; }
  ];
};
```

### PostgreSQL port

If anything occupies the default PostgreSQL port (5432), the NixOS postgres
needs to run on a custom port. This breaks roundcube in two places:

1. The module's generated DSN hardcodes `unix(/run/postgresql)` with no port, but
   the socket file is named after the port and has moved. Override `db_dsnw` in
   `extraConfig` using the `unix(path:port)` PHP DSN syntax:

```nix
   $config['db_dsnw'] = 'pgsql://roundcube@unix(/run/postgresql:5433)/roundcube';
```

1. The `roundcube-setup` service (which initialises the DB schema) invokes `psql`
   without a port. Fix by injecting `PGPORT` into its environment:

```nix
   systemd.services.roundcube-setup.environment.PGPORT = toString lab.ports.postgresql;
```

Right now, I'm not using these workarounds anymore, but I'll leave them here for
future reference.

### maxAttachmentSize type error

The `maxAttachmentSize` option expects a signed integer but dividing by `1.37`
produces a float. Wrap in `builtins.floor`:

```nix
maxAttachmentSize = builtins.floor (lab.mail.messageSizeLimit / 1024 / 1024 / 1.37);
```

---

## DNS records

All A records point to `198.46.149.19`.

| type | name                         | value                                                       | notes                         |
| ---- | ---------------------------- | ----------------------------------------------------------- | ----------------------------- |
| A    | `headpats.uk`                | `198.46.149.19`                                             |                               |
| A    | `mail.headpats.uk`           | `198.46.149.19`                                             | PTR must match this (see VPS) |
| A    | `smtp.headpats.uk`           | `198.46.149.19`                                             | mailserver fqdn               |
| A    | `hs.headpats.uk`             | `198.46.149.19`                                             | headscale                     |
| MX   | `headpats.uk`                | `mail.headpats.uk` (priority 10)                            |                               |
| TXT  | `headpats.uk`                | `v=spf1 mx ~all`                                            | SPF                           |
| TXT  | `_dmarc.headpats.uk`         | `v=DMARC1; p=none; rua=mailto:loli@headpats.uk`             | DMARC reporting               |
| TXT  | `mail._domainkey...`         | _(DKIM public key — generated by mailserver on first boot)_ |                               |
| PTR  | `19.149.46.198.in-addr.arpa` | `mail.headpats.uk`                                          | set in VPS control panel      |

**DKIM key**: after first deploy of `mail`, grab the public key with:

```sh
cat /var/lib/rspamd/dkim/*.pub  # or wherever nixos-mailserver puts it
```

Then create the TXT record `mail._domainkey.headpats.uk` with that value.

---

## mail server notes

The `mail` machine runs
[nixos-mailserver](https://gitlab.com/simple-nixos-mailserver/nixos-mailserver),
which brings up kresd (Knot Resolver) as a local DNSSEC-validating resolver in
place of systemd-resolved. This means local domains that only exist on the
router (e.g. `box.headpats.uk`) won't resolve unless explicitly forwarded — see
the `services.kresd.extraConfig` forward-zone policy in `hosts/mail/mail.nix`.

### kresd DNS cache stale after policy changes

kresd caches results in lmdb on disk, so stale NXDOMAIN entries survive service
restarts and silently ignore updated policy rules until the cache is cleared:

```sh
systemctl stop kresd@1
rm -rf /var/cache/knot-resolver/*
systemctl start kresd@1
```

---

## secrets

All secrets live outside the Nix store. They must be created manually before or
just after the first deploy.

Make sure to create the secrets dir as root and make it non-traversable, with
the exception of `mail` where virtualMail needs to see the gmail secrets.

```sh
mkdir -p /var/lib/secrets
chmod 700 /var/lib/secrets

# only on mail
chmod 711 /var/lib/secrets
```

### mail server password files

Hashed password files are expected at `/var/lib/secrets/<user>-hashed-password`
on the `mail` machine. Generate them with:

```sh
nix-shell -p mkpasswd --run 'mkpasswd -sm bcrypt' > /var/lib/secrets/loli-hashed-password
chmod 600 /var/lib/secrets/loli-hashed-password
```

### caddy

Caddy uses DNS-01 validation via the Cloudflare plugin and reads its token from
an `EnvironmentFile`. Create it on `code`:

```sh
cat > /var/lib/secrets/caddy <<EOF
CLOUDFLARE_API_TOKEN=<your-cloudflare-api-token>
EOF
chmod 600 /var/lib/secrets/caddy
```

### beszel agent key

The beszel agent module (`modules/beszel.nix`) is applied to every host. Each
one needs its own credentials file. The values come from the beszel hub when you
add the system — open the hub at `hw.box.headpats.uk`, click **Add system**,
use the host's tailnet IP and the agent port from `lab.ports.beszel-agent`, and
it will show you the key and token.

Create the file on each host with:

```sh
cat > /var/lib/secrets/beszel-agent <<EOF
KEY=<public-key-from-beszel-hub>
TOKEN=<token-from-beszel-hub>
EOF
```

Then lock it down. The service runs with `beszel-secrets` as a supplementary
group (declared in `modules/beszel.nix`), so:

```sh
mkdir -p /var/lib/secrets
chmod 700 /var/lib/secrets # 711 if on mail, explained later
groupadd -f beszel-secrets
chown root:beszel-secrets /var/lib/secrets/beszel-agent
chmod 640 /var/lib/secrets/beszel-agent
```

Restart the agent to pick it up:

```sh
systemctl restart beszel-agent
```

Or better yet, just have it set up before you deploy the agent.

### Gmail OAuth2 tokens

Tokens live at `config.lab.fetchmail.secrets-dir` = `/var/lib/secrets/fetchmail/`.
Each Gmail account has one file named `gmail-<email>.json`:

```json
{
  "client_id": "...",
  "client_secret": "...",
  "refresh_token": "..."
}
```

**Generating a token for a new Gmail account:**

1. Go to [Google Cloud Console](https://console.cloud.google.com/) → create a
   project → enable the Gmail API → create OAuth credentials (Desktop app) →
   download `credentials.json`.

2. Run the helper script (on any machine with Python 3, not necessarily the server):

   ```sh
   python3 utils/gmail-oauth.py credentials.json user@gmail.com
   ```

   It will open a browser, ask you to authorize, then save `gmail-user@gmail.com.json`.

3. Copy the resulting file to the mail server:

   ```sh
   # on mail
   mkdir -p /var/lib/secrets/fetchmail

   # on the machine you ran the script on
   scp gmail-user@gmail.com.json mail:/var/lib/secrets/fetchmail/
   ```

   The `mail-fetch` service runs as `mailserver.vmailUserName` so make sure the
   directory and file are readable by that user:

   ```sh
   # dir is readable by virtualMail but dont allow messing with dir structure
   chown root:virtualMail /var/lib/secrets/fetchmail

   # files only readable by virtualMail
   chown virtualMail:virtualMail /var/lib/secrets/fetchmail/*.json
   chmod 600 /var/lib/secrets/fetchmail/*.json

   # make sure dir is readable
   chmod 750 /var/lib/secrets/fetchmail

   # make sure parent dir is traversable
   chmod 711 /var/lib/secrets
   ```

4. Trigger a manual fetch to verify it works:

   ```sh
   systemctl start mail-fetch.service
   journalctl -u mail-fetch -f
   ```

The timer runs on boot (after 2 min) and then every 5 minutes thereafter.

---

## deploying

Note: if you're not me, change the nut input away from a local path in `flake.nix`.

With [deploy-rs](https://github.com/serokell/deploy-rs):

```sh
deploy            # all machines
deploy .#code     # code only
deploy .#mail     # mail server only
deploy .#relay    # relay only
```

Or directly on the machine:

```sh
nixos-rebuild switch --flake .#code
nixos-rebuild switch --flake .#mail
nixos-rebuild switch --flake .#relay
```

---

## first time setup

Things that can't be done declaratively and must be run after the first deploy.

### relay

1. **Create the headscale user** (only needed once, before registering any nodes):

   ```sh
   headscale users create default
   ```

2. **Bring up tailscale** — it will print a URL and then wait:

   ```sh
   tailscale up --advertise-exit-node --accept-routes \
     --login-server=https://hs.headpats.uk
   ```

   Open the URL in a browser. It will redirect to your headscale instance and show
   a `headscale nodes register` command, something like:

   ```sh
   headscale nodes register --key nodekey:xxxxxxxxxxxxxxxx --user default
   ```

   Run that on the relay. Tailscale will then complete the handshake.

3. **Verify headscale is reachable** at `https://hs.headpats.uk`.

4. **Set up the beszel agent** — see [beszel agent key](#beszel-agent-key) above.

### mail

1. **Create secrets** — see [secrets](#secrets) section above.

2. **Bring up tailscale** — it will print a URL and then wait:

   ```sh
   tailscale up --accept-dns=false \
     --login-server=https://hs.headpats.uk
   ```

   Open the URL in a browser, copy the `headscale nodes register` command it gives
   you, and run it on the relay:

   ```sh
   headscale nodes register --key nodekey:xxxxxxxxxxxxxxxx --user default
   ```

3. **Verify ACME cert** is issued (requires port 80 tunnel through relay to be working):

   ```sh
   journalctl -u acme-smtp.headpats.uk -f
   ```

4. **Add DKIM DNS record** — see [DNS records](#dns-records) above.

5. **Copy Gmail OAuth tokens** — see [secrets](#secrets) above.

6. **Test mail flow**:
   - inbound: send to `loli@headpats.uk` from an external address
   - outbound: send from `loli@headpats.uk` using a mail client via
     `smtp.headpats.uk:587`

   ```sh
   # gmail sync:
   systemctl start mail-fetch && journalctl -u mail-fetch -f
   ```

### code

Bring up tailscale and advertise the home lan:

```sh
tailscale up --advertise-routes=10.0.10.0/24 \
  --login-server=https://hs.headpats.uk
```

Open the URL it prints, copy the `headscale nodes register` command, and run it
on the relay:

```sh
headscale nodes register --key nodekey:xxxxxxxxxxxxxxxx --user default
```

Then approve the advertised route on the relay:

```sh
headscale nodes list  # find the node id
headscale routes list --identifier <node-id>
headscale routes enable --route <route-id>
```

**Create caddy secret** — see [caddy](#caddy) above. Caddy won't start without
`/var/lib/secrets/caddy`.

**Set up the beszel hub** — the hub runs on `code` at `hw.box.headpats.uk`. On
first boot it will be empty. Once tailscale is up and the other hosts have their
agent keys configured, add each system in the hub UI using its tailnet IP and
`lab.ports.beszel-agent`.

**Set up the beszel agent on code itself** — see [beszel agent key](#beszel-agent-key)
above. The hub monitors `code` too.

---

## migration / redeploy checklist

### migrating the relay to a new VPS

The relay is mostly stateless — headscale state is the only thing worth preserving.

1. **Update DNS** — point all A records to the new IP, update PTR in the new VPS
   control panel to `mail.headpats.uk`.

2. **Update `lib/lab.nix`**:

   ```nix
   internet.relay = "<new-ip>";
   ```

3. **Back up headscale state** from the old relay:

   ```sh
   # headscale db
   scp relay:/var/lib/headscale/db.sqlite ./headscale-backup.sqlite
   # headscale noise key
   scp relay:/var/lib/headscale/noise_private.key ./noise_private.key.bak
   ```

4. **Deploy to the new relay**:

   ```sh
   deploy .#relay
   ```

5. **Restore headscale state**:

   ```sh
   scp ./headscale-backup.sqlite new-relay:/var/lib/headscale/db.sqlite
   scp ./noise_private.key.bak new-relay:/var/lib/headscale/noise_private.key
   systemctl restart headscale
   ```

6. **Re-join all tailscale nodes** (the noise key stays the same so they should
   reconnect automatically, but if not, re-run `tailscale up` on each node — it
   will print a URL and a `headscale nodes register` command to run on the
   relay).

7. **Test**: ping across tailnet, send a test email inbound and outbound.

### migrating the mail server to new hardware

Mail state is in two places: the Maildir and `/var/lib/secrets` (which now
covers mail passwords, Gmail tokens, and the beszel agent credentials).

1. **Back up Maildir**:

   ```sh
   rsync -avz mail:/var/vmail/ ./vmail-backup/
   ```

2. **Back up secrets**:

   ```sh
   rsync -avz mail:/var/lib/secrets/ ./secrets-backup/
   ```

3. **Deploy to new hardware**:

   ```sh
   deploy .#mail
   ```

4. **Restore Maildir and secrets**:

   ```sh
   rsync -avz ./vmail-backup/ new-mail:/var/vmail/
   rsync -avz ./secrets-backup/ new-mail:/var/lib/secrets/

   # fix ownership
   ssh new-mail
   chown -R virtualMail:virtualMail /var/vmail

   chown root:root /var/lib/secrets
   chown root:virtualMail /var/lib/secrets/fetchmail

   chmod 711 /var/lib/secrets
   chmod 750 /var/lib/secrets/fetchmail

   chown root:root /var/lib/secrets/*-hashed-password
   chmod 600 /var/lib/secrets/*-hashed-password
   chmod 600 /var/lib/secrets/fetchmail/*.json
   groupadd -f beszel-secrets
   chown root:beszel-secrets /var/lib/secrets/beszel-agent
   chmod 640 /var/lib/secrets/beszel-agent
   ```

   Also check that the files inside `/var/vmail` are not world readable. if you
   messed up the permissions on the backup you could fix with `chmod -R go=` but
   some files might need different permissions.

5. **Re-run tailscale first-time steps** (see above).

6. **Verify ACME** renews correctly — may need to wait a few minutes or poke
   `systemctl start acme-smtp.headpats.uk`.

---

## if a machine fails to deploy

Usually it's because it needs to reboot rather than switching in-place. Note the
`/nix/store` path deploy was trying to use, then:

```sh
ssh root@machine
nix-env --profile /nix/var/nix/profiles/system --set /nix/store/path-to-system
/nix/store/path-to-system/bin/switch-to-configuration boot
reboot
```

If it says `failed to acquire lock`, do a force shutdown and reboot to clear it,
then try those commands again.

---

## bypassing the local cache

This is useful when restarting caddy or fixing a broken configuration. Anything
that would bring down the caching reverse proxy. I guess this would be an
argument in favor of using the port number so that we're not dependent on caddy
for the cache to work.

```sh
nixos-rebuild switch --flake .#code --option substituters "https://cache.nixos.org https://nix-community.cachix.org"
deploy .#code -- --option substituters "https://cache.nixos.org https://nix-community.cachix.org"
```

---

## useful diagnostics

```sh
# check mail fetch is running and healthy
systemctl status mail-fetch.timer
journalctl -u mail-fetch -n 50

# check dmarc scanner
systemctl status dmarc-scanner.timer
journalctl -u dmarc-scanner -n 50

# check postfix queue on mail server
mailq

# check postfix on the relay
ssh relay mailq

# test SMTP submission
swaks --to loli@headpats.uk --from loli@headpats.uk \
  --server smtp.headpats.uk --port 587 --auth LOGIN \
  --auth-user loli@headpats.uk

# verify tailnet connectivity
tailscale ping 100.64.0.2   # relay from mail
tailscale ping 100.64.0.1   # mail from relay

# check headscale node list from relay
headscale nodes list

# check TLS cert status
openssl s_client -connect smtp.headpats.uk:993 -quiet 2>&1 | head -5

# check caddy is up and reload config without restart
systemctl status caddy
systemctl reload caddy

# check beszel agent on any host
systemctl status beszel-agent
journalctl -u beszel-agent -n 50
```

---

## acknowledgements

This setup wouldn't exist without a handful of projects doing the hard work:

- **[nixpkgs](https://github.com/NixOS/nixpkgs)** — the foundation everything
  runs on. The module system approach is exactly right.

- **[deploy-rs](https://github.com/serokell/deploy-rs)** for remote NixOS
  deployment that just works.

- **[home-manager](https://github.com/nix-community/home-manager)** for
  declarative user environment management. You don't know you need it until
  you have it.

- **[nixos-mailserver](https://gitlab.com/simple-nixos-mailserver/nixos-mailserver)**
  for making self-hosted mail not a complete nightmare.

- **[nix](https://github.com/NixOS/nix)** itself, a genuinely novel idea that
  keeps proving its worth.

- **[OPNsense](https://opnsense.org/)** — for providing a rock-solid, BSD-based
  routing platform that can actually handle high-performance PPPoE with the
  right tuning.

If any of these projects have made your life better, please consider supporting
them. Most are maintained by small teams or individuals giving their time freely:

- [NixOS Foundation](https://nixos.org/donate/) supports nixpkgs and NixOS
- [Serokell](https://serokell.io/) maintains deploy-rs
- [home-manager
  contributors](https://github.com/nix-community/home-manager/graphs/contributors).
  Consider sponsoring active maintainers directly on GitHub
- [flake-parts](https://github.com/hercules-ci/flake-parts) by Hercules CI
- [Deciso](https://www.deciso.com/) sponsors the OPNsense project
