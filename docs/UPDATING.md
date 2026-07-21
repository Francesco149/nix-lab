# Updating The Lab (manual runbook)

Step-by-step for a periodic update + redeploy of the lab, with the critical
checks at each stage. This is what to do by hand when the automation isn't
driving it. Keep it current — see the reminder in `CLAUDE.md`.

Companion script: **`./utils/lab-check.sh`** runs the post-deploy health checks
for you (verbose, with a PASS/WARN/FAIL summary). Run it after every deploy.

## Model

- **Builds happen on `wslop`** — it is the `rd_host` (see `modules/hm/fish/dev.fish`).
  Run these steps from wslop (or a box that delegates to it). Heavy builds must
  not run on `code`.
- **Deploys are pushed from wslop** to each host over ssh as `root`. wslop's
  root key is the `headpats@cutestation` key in `lab.ssh.authorized-keys`; it is
  in every host's config. If a host rejects it (a stale generation), append it
  once via `code` (which can reach everyone) — see Gotchas.
- Hosts: `code` (proxmox VM), `mail` (LAN), `relay` (RackNerd VPS), `cold`
  (encrypted backup target, normally powered off), `lame` (encrypted, GPU box),
  and `wslop` (the local NixOS-WSL build/deploy box).

## 1. Update inputs

Update the upstream inputs only; leave the local `git+file:///opt/src/*` app
inputs (nut, shigebot, dmarc-analyzer, grammar-helper) pinned unless you mean to
ship app changes:

```sh
cd /opt/src/nix-lab
nix flake update nixpkgs nixos-mailserver disko llm-agents nixos-wsl deploy-rs home-manager
```

A plain `nix flake update` also re-locks the local app inputs to their current
HEAD — only do that if you intend to deploy those app changes.

## 2. Build every host + diff

Build each system and compare against what's deployed. Fix anything that fails
to build (see step 3) before deploying anything.

Run the health check before copying closures as well as after deployment:

```sh
./utils/lab-check.sh
```

Treat `root disk headroom` as a hard gate. It requires both 5 GiB free and less
than 90% usage on every host; `dry-activate` cannot predict a database or cache
hitting `ENOSPC` after the new closure is copied.

Before a host build, cache-gate the large packages from `llm-agents`. Do not
accept a local Codex build just because the full host build has already started:

```sh
miss=0
for p in codex claude-code opencode; do
  out=$(nix eval --raw --impure --expr \
    "(builtins.getFlake (toString ./.)).inputs.llm-agents.packages.x86_64-linux.$p.outPath")
  hash=${out#/nix/store/}; hash=${hash%%-*}
  curl -sfI "https://cache.numtide.com/$hash.narinfo" >/dev/null \
    && echo "HIT  $p $out" || { echo "MISS $p $out"; miss=1; }
done
test "$miss" -eq 0
```

If any gate misses — especially Codex — stop before the host build. Keep the
previous `llm-agents` revision, or let that input use the Nixpkgs revision its
cache was built against instead of forcing a mismatched root `nixpkgs`; then
re-evaluate and diff. A duplicate input is cheaper than compiling Codex locally.

```sh
for h in code mail relay cold lame wslop; do
  nix build ".#nixosConfigurations.$h.config.system.build.toplevel" --no-link --print-out-paths
done
```

Diff each host (the fish helper does build + fetch-current + `nvd diff`):

```sh
diff-system code     # repeat per host; or use nvd diff <current> <new> manually
```

Read every diff. Expect version bumps; be suspicious of **removed** services or
units you didn't intend. Common benign churn from a nixpkgs jump: openssl point
releases, `util-linux` output reshuffles, the scripted-networking unit rename
(`network-setup.service` → `networking-scripted.target`).

## 3. Fix rot

The update will surface breakage to fix before deploying:

- **Fixed-output hash mismatches** (e.g. `caddy.withPlugins`): copy the `got:`
  hash into the `hash = ` field (`hosts/code/caddy.nix`).
- **Eval/deprecation warnings**: fix in-repo; if it comes from an input flake,
  note it (or retire/​bump that input).
- **Uncached package forces a from-source build (which may then fail).** A fresh
  `nixpkgs` can ship a leaf package Hydra hasn't cached *and* that is broken to
  build — e.g. `cantarell-fonts 0.311` (an `afdko` regression broke its
  variable-font step): it 404s on every substituter, the source build fails, and
  it cascades to fail the whole host. An input's own cache can also lag (e.g.
  `pi` from `llm-agents` not yet on `cache.numtide.com`). Confirm with
  `curl -sI https://<cache>/<storehash>.narinfo` (404 = not cached). Fixes: hold
  or advance `nixpkgs` to a rev where the package is cached + builds, or — if you
  only need one input (e.g. a newer `claude-code` from `llm-agents`) — do a
  **surgical** `nix flake update llm-agents` and leave `nixpkgs` pinned.
- **A toolchain bump can break another package's checks.** Read the first failing
  derivation rather than only the cascade. For example, `inline-snapshot 0.32.5`
  fails three documentation snapshot checks when built with Black 26.5.1 while
  its functional suite still passes. Prefer a narrow, documented
  `disabledTestPaths` override for stale generated snapshots; do not disable the
  whole check phase. Input flakes can instantiate their own package sets without
  the host overlays, so the full six-host build must prove the workaround reaches
  every real dependency. If no narrow safe fix exists, compare archived channel
  releases — and diff every host before accepting a pin, because an older pin can
  be a large downgrade for an already-newer machine such as wslop.
- **Too many rooted generations can fill a host during the closure copy.** Check
  headroom before deployment. If it is low, first review
  `nix-env -p /nix/var/nix/profiles/system --list-generations`; then retain a
  useful rollback window and collect only the unrooted paths, for example:
  `nix-env -p /nix/var/nix/profiles/system --delete-generations 30d` followed by
  `nix-store --gc`. Do not remove the current/booted rollback roots merely to
  make a deploy fit. Large archived journals are a secondary place to inspect
  with `journalctl --disk-usage`.
- Re-build the affected host until it succeeds.

## 4. Deploy

`deploy` (deploy-rs) can hang for ages on benign failures, so for a
reboot-everything cycle prefer the explicit push + activate + reboot below. Do
the low-risk hosts first, the VPS last.

For each host: push the closure, set it as the system profile, stage it for
boot, then reboot.

```sh
NEW=/nix/store/...-nixos-system-<host>-...        # from step 2
nix copy --no-check-sigs --to ssh-ng://root@<addr> "$NEW"
ssh root@<addr> "nix-env -p /nix/var/nix/profiles/system --set '$NEW' \
  && '$NEW'/bin/switch-to-configuration boot"
ssh root@<addr> systemctl reboot
```

Use `switch-to-configuration switch` instead of `boot` (no reboot) when you want
the change live without rebooting (see `cold` below).

Per-host nuances (order: code → mail → lame → relay, then cold and wslop):

- **code** — VM. Reboot is safe; recover from the proxmox console if it doesn't
  return. Deploying it also activates the `cold-backup` orchestrator changes and
  the weekly `tm-backup` timer (Win7/XP image backup — see OPERATIONS.md).
- **mail** — LAN. Reboot. Verify postfix + dovecot come up (dovecot is the
  `dovecot.service` unit, renamed from `dovecot2` in newer nixpkgs).
- **lame** — root is LUKS-encrypted, so a **reboot drops it to initrd**. After
  `systemctl reboot`, unlock it: `ssh root@code cold-unlock --host lame`, then
  wait for full boot. Reboot is needed here so the new kernel matches the nvidia
  module. Verify `nvidia-smi` and the `llama-*` services after. **Docker's
  data-root lives on the `lamedata/docker` ZFS dataset** (not the 98G LUKS root,
  which a haruness sweep once filled to 100%); `docker.service` is ordered after
  `zfs.target` so it waits for that mount. After a reboot confirm `docker info`
  shows `Docker Root Dir: /lamedata/docker` and the images/containers survived
  (`lab-check.sh` checks both — "docker on zfs" + "root disk free").
- **relay** — RackNerd VPS, no encryption (GRUB on `/dev/vda`). It has bitten us
  on reboot before ("install corrupt"), recoverable only from the **RackNerd web
  console (VNC + power controls)** — have it open before you reboot. Push with
  `nix copy -s ...` so relay substitutes stock paths from cache.nixos.org
  instead of a slow full push over the internet. After staging, confirm
  `switch-to-configuration boot` printed `installing the GRUB 2 boot loader ...
  No error reported` before rebooting. Poll ssh after reboot; if it doesn't
  return in a few minutes, hard-reboot from RackNerd.
- **cold** — encrypted + meant to stay up (helium drives dislike power cycling).
  Prefer a live **`switch`** (no reboot): the new kernel lands on cold's next
  natural power-cycle. A reboot would need `ssh root@code cold-unlock --host cold`
  from initrd. Never deploy/reboot cold while a backup is running. (A cold switch
  also lands the `timemachine-restic` push key on its `backup` user; the
  `gigavault/timemachine-restic` dataset + `restic init` are manual one-time steps.)
- **wslop** — activate locally and last, after it has finished building and
  pushing the other closures: `sudo nix-env -p /nix/var/nix/profiles/system
  --set "$NEW" && sudo "$NEW/bin/switch-to-configuration" switch`. Do not reboot;
  NixOS-WSL uses the Windows-provided kernel, and a full WSL shutdown must be
  initiated from Windows if it is ever needed.

## 5. Keep cold / lame up; manage the nightly

- The nightly `cold-backup.timer` on `code` fires at 01:30. To avoid it colliding
  with a manual run, stop it for the night: `ssh root@code systemctl stop
  cold-backup.timer` (re-arm with `systemctl start`).
- The weekly `tm-backup.timer` on `code` fires Sun 04:00 — it wakes the (normally
  off) `timemachine` courier via WoL, runs its image backup to cold, and powers
  both down. Run on demand with `ssh root@code tm-backup-cycle`. See OPERATIONS.md.
- To keep `cold`/`lame` powered on, create `/tmp/stay` on them
  (`touch /tmp/stay`, or `cold-unlock --stay`). The fixed orchestrator
  (`hosts/code/backup/cold-backup.py`) skips shutdown for any host with the
  stay file. **Caveat:** `/tmp/stay` lives in tmpfs-cleaned `/tmp`, so it only
  survives until that host reboots — recreate it after a reboot.

## 6. Verify

```sh
./utils/lab-check.sh           # all hosts, verbose + summary
```

Critical checks (also what the script asserts):

- Every host: `systemctl is-system-running` = `running`, **no failed units**,
  `/run/current-system` points at the new generation.
- code: caddy, docker, beszel-agent, `cold-backup.timer`, `tm-backup.timer`, app services active.
- mail: postfix, dovecot, rspamd active.
- relay: headscale, nginx, tailscaled active; `http://127.0.0.1:8080/health` =
  200; the **hs.headpats.uk cert is not expired** (it renews via DNS-01 — see
  Gotchas). Sanity-check the tailnet: `ssh root@relay headscale nodes list`.
- cold: both zpools `ONLINE`, `gigavault/wslop-backup` present with a recent
  `@wslop-*` snapshot, `gigavault/timemachine-restic` present, `/tmp/stay` present
  if it should stay up.
- lame: `nvidia-smi` works; interactive-GPU-sandbox prereqs present (uinput module +
  `/run/cdi/nvidia-container-toolkit.json`). NOTE: `llama-vulkan`/`llama-embed` are
  intentionally **disabled** (7800XT freed for haruness harness dev — see WORKDOC.md);
  re-enable in `hosts/lame/llama.nix` to restore the shared llama endpoint.
- wslop: virtualization reports `wsl`, sshd is active, and the intentionally
  unprovisioned `beszel-agent` remains masked.

Read the verbose output too — a scripted check can pass while something next to
it quietly failed.

## Gotchas

- **Remote login shells are fish on `code` and `lame`.** `bash` loops/`$()` in a
  one-shot ssh command break there. Pipe scripts via `ssh root@host 'bash -s'`
  (what `lab-check.sh` does), or keep remote commands to single statements.
- **Host rejects wslop's deploy key** (stale generation predating the key):
  append it once via code, then deploy to make it permanent —
  `ssh root@code 'ssh root@<host> "cat >> /root/.ssh/authorized_keys"' < <(ssh root@code cat /var/lib/secrets/... )`
  (the cutestation pubkey). After the deploy the key is in config and this is
  no longer needed.
- **relay's hs.headpats.uk cert uses DNS-01 (cloudflare), not HTTP-01** — relay's
  :80 is the mail stream-proxy, so HTTP-01 can't be served there (this is why
  the cert silently expired once). The token lives at
  `/var/lib/secrets/acme-cloudflare` (`CLOUDFLARE_DNS_API_TOKEN`, same token
  Caddy uses on code). If you rebuild relay fresh, provision that file or the
  cert won't issue.
- **lame's llama `video` instance is disabled** (`hosts/lame/llama.nix`) — its
  pinned llama.cpp commit is incompatible with newer nixpkgs (web UI moved to
  `tools/ui`). Re-enable after bumping the pinned `src.rev` + the video patch.
