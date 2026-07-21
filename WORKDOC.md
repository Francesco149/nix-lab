# nix-lab Workdoc

Last updated: 2026-07-15

## Project

Personal NixOS flake for homelab hosts, built on the local `nut` flake library.
The repo should stay easy for humans and coding agents to resume without
re-learning project conventions each session.

## Current Goals

- Keep `flake.nix` as the host/module wiring source of truth.
- Keep shared constants in `lib/lab.nix`.
- Provide a system-wide custom Neovim launcher named `e` for interactive hosts
  without changing the clean `neovim` package used by OpenVSCode.
- Keep interactive tool colors tied to `lib/lab.nix` without overriding the
  terminal background.

## Scope Notes

- `/opt/src/nix-lab` is editable.
- `/opt/src/nut` is reference-only unless explicitly requested.
- `interactive.nix` is currently included by `code` and `lame`.
- OpenVSCode should keep using system `neovim`; the custom editor should remain
  isolated behind the `e` launcher.
- System tmux defaults live in `modules/tmux.nix` and are applied through
  `interactive.nix`.

## Findings

- `nut.lib.mf` automatically imports host files and appends global and
  host-specific modules.
- `lab.colors` is available from NixOS modules through `config.lab.colors`.

- Root `AGENTS.md` is the durable agent orientation file.
- Root `WORKDOC.md` is the durable cross-session task and decision log.

## Tasks

- [done] Build custom Neovim wrapper exposed as `e` from `interactive.nix`.
- [done] Keep custom editor config isolated from system-wide `nvim`.
- [done] Configure SSH clipboard through OSC52 while leaving local clipboard
  behavior available later.
- [done] Add conservative LSP, completion, formatting, and fuzzy-find defaults.
- [done] Add system tmux defaults for interactive hosts with mouse scrolling
  left to the terminal emulator.
- [todo] Consider generating docs from `lib/lab.nix` if the host inventory grows.

## Wslop Cold Backup

`wslop-backup` (hosts/wslop/backup.nix) backs up the WSL guest rootfs and a
curated list of windows work dirs to cold. Usage and design live in
docs/OPERATIONS.md.

Decisions:

- 2026-06-14 redesign: the windows side no longer mirrors whole `/mnt` drives
  (that pulled `Windows/`, `Program Files/`, the 414G WSL `ext4.vhdx` under
  AppData, and locked system files over slow 9p, and failed instantly on a
  missing `windows/<drive>` dest dir). It is now an explicit
  `backup.wslop.windows.{work,optional}` list of actual work dirs; capture/
  trace dirs drop image/video (`image-junk`), keeping only binary traces.
  rootfs is unchanged — it reads native ext4 `/` (not 9p) and is a cheap
  rsync incremental. Fixes shipped: `--mkpath` (the instant-failure bug),
  dataset `acltype=posixacl` (killed the `set_acl Operation not supported`
  spam on `/var/log/journal`), and skip wake/unlock when cold is already up.
- WSL2 NAT drops subnet-directed broadcasts (tested with a sniffer on code:
  unicast UDP arrives, broadcast never does), so wslop relays wake+unlock
  through `ssh root@code cold-unlock --host cold` instead of sending WoL.
- Push runs as root@cold: the interactive ssh keys are authorized everywhere
  already, cold ships rsync via NixOS defaultPackages, and root can create
  datasets/snapshots without `zfs allow` — so the manual command works without
  redeploying cold or code.
- Skipping the cold wake-up when nothing changed was considered and dropped:
  `code` is a VM on proxmox and always has new data, so the check would never
  skip anything.

Deploy state:

- [done] wslop side (command, known hosts, backup user + sudo rule) — only
  wslop may be redeployed at the moment. Deployed and smoke-tested 2026-06-10
  (wake, unlock, dataset auto-create, rsync, snapshot+prune, report, poweroff).
- [done] All of the above deployed 2026-06-15 (full lab update, see section
  below): code's opportunistic wslop step + the orchestrator shutdown fix,
  cold's `boot.tmp.cleanOnBoot`, and the cutestation/wslop-root key is now in
  every host's deployed config (the runtime appends on cold/mail/relay are
  redundant).
- [done] Backup redesign deployed + verified 2026-06-15: a full run was clean
  (rootfs 6.3M files / 0 ACL errors, all windows work dirs, `--mkpath` created
  the `windows/<name>/` dests, snapshot `wslop-20260615-000430`).
- wslop stays out of the auto-unlock flow: bitlocker passphrase without TPM,
  and the machine is not guaranteed to be up during the backup window.

## 2026-06-15 Lab Update + Robustness

Full update of all hosts (nixpkgs a799d3e → 9ae611a; deployed gens were the
stale 26.05.20260430 — ~6 weeks behind; home-manager/mailserver/disko/
llm-agents/nixos-wsl bumped, deploy-rs already current). Built + `nvd diff`'d
every host on wslop (the rd_host build box), then deployed from wslop with
`nix copy [-s] --to` → `nix-env --set` → `switch-to-configuration boot` →
reboot (avoiding deploy-rs hangs). Runbook now in `docs/UPDATING.md`; health
check in `utils/lab-check.sh` (run after every deploy). All hosts `running` on
9ae611a; final `lab-check.sh` = PASS=35/WARN=0/FAIL=0.

- code/mail/lame/relay rebooted; **cold** used a live `switch` (encrypted +
  must stay up; new kernel lands on its next power-cycle). lame's reboot needed
  `cold-unlock --host lame` (LUKS initrd).
- Rot fixed: `caddy.withPlugins` hash (`hosts/code/caddy.nix`); **lurk-monitor
  retired** (input + code module + caddy vhost + lab port) — also removed the
  only `pkgs.system` deprecation (it came from lurk-monitor's flake).
- Orchestrator fix (`hosts/code/backup/cold-backup.py`): shutdown loop now
  targets each woken host by its own ip + HostKeyAlias (it always hit cold with
  no host=, bypassing cold's `/tmp/stay` during lame's iteration and never
  reaching lame). Fail-safe added: unreachable host → don't shut down.
- lame: llama re-enabled (vulkan + embed active, GPU OK). The **`video`
  instance is disabled** in `hosts/lame/llama.nix` — new nixpkgs llama-cpp moved
  its web UI to `tools/ui`, incompatible with the pinned April commit the Cobdog
  video patch needs. **[update 2026-06-15] Resolved differently:** upstream
  llama.cpp now has *native* video (no Cobdog patch needed) — re-enable by
  dropping the patch + April pin. See "Video Understanding" section below.
- Deploy access: deploys push from wslop (rd_host). mail/relay had rejected
  wslop's root key (stale gens predating it); bootstrapped via code, now in
  their deployed config.
- relay headscale cert was **expired since 2026-05-27** (pre-existing, not this
  update): HTTP-01 can't run on relay (:80 is the mail stream-proxy). Switched
  `hs.headpats.uk` to **DNS-01 (cloudflare)** — reused code's CF token at
  `/var/lib/secrets/acme-cloudflare` (`CLOUDFLARE_DNS_API_TOKEN`); cert reissued
  (valid to Sep 2026), tailnet control plane recovered.
- cold + lame pinned with `/tmp/stay` (helium drives — avoid power cycling).
  Nightly timer re-armed; the fixed orchestrator respects the stays. `/tmp/stay`
  is tmpfs — recreate after any reboot.

## Video Understanding / Local VLM Eval (2026-06-15)

Investigated replacing the broken `llama-video` (Cobdog patch) setup. **Upstream
llama.cpp has native video since `8f83d6c` (2026-06-08)** — temporal-merge +
M-RoPE + ffmpeg frame extraction + interleaved timestamps — matching/beating the
patch, no patch needed. Proven on lame (7800XT/Vulkan) with the existing
`Qwen3.6-35B-A3B` + mmproj: high-quality, temporally-ordered descriptions
(user-confirmed ≥ llama-video). Full findings + reusable testbed live in
`research/video-understanding/` (build/run scripts, perf matrix, model rec).

Key results:
- Native temporal video is **Qwen-VL-lineage only** (our Qwen3.6 models qualify).
  nixpkgs `llama-cpp` b9503 predates video by 4 days → build from source for now
  (`research/.../scripts/build-llama.sh`), or wait for nixpkgs ≥ ~b9510.
- Perf (7800XT 16 G, fully on GPU): MoE quants that fit VRAM ≈ **120 t/s**;
  dense-27B ≈ 31 t/s, **+MTP ≈ 54 t/s (1.74×)**; the offloaded `Q4_K_P` (current
  prod config) only **14–25 t/s**. The 3080 (10 G) is VRAM-bound for 27–35 B →
  the **7800XT is the better card** here.
- Two real gotchas (documented): the helper's **ffmpeg-feeder SIGPIPE bug**
  (needs SIG_IGN; one-line upstream fix worth a PR) and the **video token budget**
  (~1.3k tok/sec-of-video at full res → cap `--image-max-tokens`/fps for long clips).
- **MTP + `--mmproj` works for video** (tested); mmproj is shareable across
  Qwen3.6 finetunes of the same base.

Follow-ups:
- [todo] Re-enable the `video` instance in `hosts/lame/llama.nix` **natively**:
  drop the Cobdog patch + April `src.rev` pin, put `pkgs.ffmpeg` in the service
  PATH, carry the SIGPIPE fix until upstreamed. Pick the model/quant per the
  `research/video-understanding/README.md` recommendation (A: APEX-MTP Mini
  ~120 t/s, or B: dense-27B + MTP ~54 t/s) — both beat the offloaded `Q4_K_P`.
- [todo] The `ingest` service can be rewritten to the new interface (OAI
  `input_video`, or the C++ video helper) — user confirmed breaking it is fine.
- [planned] Agentic-coding eval harness (`research/agentic-coding/`) to settle
  the model choice on coding quality; fold MTP on/off in (free dense speedup).
- **Runtime state for next session:** `llama-vulkan` + `ollama-proxy` are
  **stopped** to free the 7800XT for harness dev; `llama-embed` stays up on the
  3080. `hosts/lame/llama.nix` is unchanged, so a lame reboot/redeploy restarts
  them — re-stop (or comment out + deploy) if the 7800XT must stay free.
- A from-source video-enabled llama.cpp (mtmd-cli, bench, cli) is built under
  `lame:/tmp/llama.cpp/build-{vulkan,cuda}` and the APEX-MTP + dense-MTP GGUFs are
  downloaded in `/opt/ai-lab/models` — reusable next session (rebuild via the
  research scripts if `/tmp` was cleared).

## 2026-06-16 Interactive GPU Sandbox — Moonlight input + firewall

The haruness interactive GPU sandbox (lame 3080 → Sunshine/Moonlight) now has
working mouse/keyboard. Root cause + fix live in haruness
`docs/interactive-sandbox.md` (short version: run the container with
`--network host` + the host's udev DB so Xorg hotplugs Sunshine's uinput devices
— NOT the systemd/logind rewrite previously planned).

nix-lab side (this repo):
- `--network host` means Docker no longer publishes Sunshine's ports, so the host
  firewall must allow them. Added to `hosts/lame/lame.nix`
  (`networking.firewall.allowed{TCP,UDP}Ports`) referencing new
  `lab.ports.sunshine-*` / `lab.ports-udp.*` labels in `lib/lab.nix`. Ports: TCP
  47984/47989/47990/48010, UDP 47998-48000/48002, + mDNS 5353.
- Validated by host eval (`nix eval
  .#nixosConfigurations.lame.config.networking.firewall.*`). Full `nix flake
  check` still fails only on the known missing-local-inputs deploy-schema check
  (pre-existing — see Niri "Known issues").

Deploy state:
- [done] Committed (cc67b95 firewall ports; 645c976 disables llama+ollama-proxy)
  AND deployed to lame via a live `switch` on 2026-06-16 (now survives reboots).
  To stop the redeploy from restarting the manually-stopped `llama-vulkan`/
  `ollama-proxy` (which would re-grab the 7800XT needed for harness dev), they
  were first DISABLED in config (llama.nix removeAttrs += "vulkan"; ollama-proxy
  wrapped in `lib.mkIf enable`, enable=false). The closure diff confirmed no
  docker/nvidia/kernel change, so the switch only stopped those two units +
  reloaded the firewall — **dockerd untouched, the gpu-sandbox container +
  Moonlight session survived, no reboot.** `lab-check lame` = PASS 7/0/0.
- Re-enable the lab's llama endpoint by dropping "vulkan" from llama.nix's
  removeAttrs / flipping ollama-proxy's `enable` to true, then redeploy.
- `utils/lab-check.sh` + `docs/UPDATING.md` updated: lame no longer asserts llama
  active; it checks the sandbox prereqs (uinput + nvidia-container-toolkit CDI).

## 2026-06-17 Docker data-root → ZFS pool (lame root disk pressure)

lame's 98G LUKS **root filled to 100%** during a haruness sweep (the harness builds
+ runs on lame). Breakdown was `/nix/store` 64G, docker 14G in `/var`, plus the
non-haruness `llmtoy-zig` (12G) and the `open-webui` image (6.7G). Fixed:

- **Docker moved off root onto the `lamedata` ZFS pool** (hundreds of GB free).
  `hosts/lame/disko.nix` declares a `lamedata/docker` dataset (mountpoint
  `/lamedata/docker`); `hosts/lame/lame.nix` sets
  `virtualisation.docker.daemon.settings.data-root = "/lamedata/docker"` and orders
  `docker.service` **after + requires `zfs.target`** so it never writes to the path
  before the dataset mounts (which would be shadowed on the next boot). overlay2-on-
  ZFS is supported here (OpenZFS 2.4 / kernel 6.18, verified).
- **Migration (live, no reboot):** stopped docker → `zfs create lamedata/docker` →
  `rsync -aHAX --numeric-ids /var/lib/docker/ /lamedata/docker/` (preserves the
  hardlinks/xattrs the containerd-snapshotter store needs) → `switch-to-configuration
  switch` → verified `docker info` data-root + all 5 images + open-webui **healthy**
  → removed the old `/var/lib/docker`. Also ran `nix-collect-garbage -d` (**41 GiB**).
- **Result:** root **0 free (100%) → 57G free (40% used)**; `lamedata/docker` 4.9G /
  ~197G free. `utils/lab-check.sh` gained "docker on zfs" + "root disk free" checks;
  `docs/UPDATING.md` notes the data-root + the post-reboot verify.
- **Risk/follow-up:** boot ordering is by construction (matches the host's other
  zfs-dependent services) but not yet reboot-tested — a future lame reboot will
  confirm docker comes up on `/lamedata/docker`. Non-haruness root hogs remain
  (`llmtoy-zig` 12G, `open-webui` image 6.7G) if more root space is wanted later.

## 2026-06-20 Time Machine (Win7/XP) Weekly Image Backup

New foreign backup target `timemachine`: a Win7/XP retro gaming box whose NixOS
"courier" (NVMe) images the *cold* Windows system disks to cold. Config is split —
the **courier** side lives in the `retro-hardware` repo (`builds/nixos-utility/`),
the **orchestration** here.

Design:

- Courier boots NixOS by default; the Windows SSDs are cold block devices, so the
  NTFS images are crash-consistent. `tm-backup` (on the courier) resolves the XP
  (Crucial MX300) + Win7 (Netac) disks BY MODEL via `/dev/disk/by-id` (sdX is
  unstable — RETRO-KIT SD + USB readers reshuffle letters), images each NTFS
  partition with `ntfsclone` (used-clusters-only; *refuses* an inconsistent FS) +
  the first MiB (MBR/parttable) via dd, and restic-pushes to
  `sftp:backup@cold:/gigavault/timemachine-restic`. Rollback = `restic dump … |
  ntfsclone --restore-image`.
- `code` runs it weekly (`tm-backup.timer`, Sun 04:00): cold-unlock cold → WoL the
  courier (`mac.timemachine`) → wait for ssh → `ssh backup@timemachine sudo
  tm-backup` → power both down. Orchestrator `hosts/code/backup/tm-backup.py` is a
  SIBLING of cold-backup (not folded in — different cadence/dep/failure domain).
  Fail-safe: never power a host off when its state is uncertain.
- restic over syncoid/zfs-send: the source is foreign Windows block devices (no ZFS
  dataset to send); restic gives dedup/incremental + tagged snapshots + one-command
  restore, repo still on a scrubbed ZFS dataset. Mirrors the wslop PUSH precedent.

Decisions / facts:

- timemachine is DHCP + normally OFF; addressed by `lan.timemachine = "timemachine.soy"`
  (router DNS) for ssh and `mac.timemachine` for WoL. NOT in `backup.targets` (that's
  the syncoid pull list) nor the lab-check default host loop (it's off).
- WoL verified to survive a NixOS shutdown (Test A: ~107s wake incl. POST). Win7/XP
  shutdown persistence still under test.
- The courier's RTC is localtime (`time.hardwareClockInLocalTime`) so it doesn't
  fight Win7/XP over the hardware clock on boot-switches.

Deploy state:

- [done] Built + validated: code/cold/courier toplevels build; `tm-backup --check`
  ran on hardware (Win7 images clean; XP was UNHEALTHY → user running `chkdsk /f`).
- [TODO before enabling the timer] (1) generate the courier restic key on
  timemachine and replace the `ssh.pub.timemachine-restic` PLACEHOLDER in lib/lab.nix;
  (2) on cold: `zfs create gigavault/timemachine-restic`, chown backup, `restic init`;
  (3) place `/etc/tm-restic-password` + cold's host key in root's known_hosts on the
  courier; (4) deploy code (switch) + cold (LIVE switch only — no reboot, not mid-
  backup) + courier; (5) run `tm-backup-cycle` by hand and confirm a Win7 snapshot
  lands BEFORE trusting the timer.
- Risk: foreign-repo coupling is invisible to nix checks — the pubkey strings in
  lab.nix and the authorizedKeys on the courier must match by hand.

## 2026-06-21 gcal-emu test-board on code (らき☆マス launcher)

- Added `hosts/code/gcal-emu.nix` — a localhost Python systemd service
  (`lab.ports.gcal-emu` = 8091, calendar-only / `--no-pop`) + a plain-HTTP
  `http://www.google.com` Caddy vhost (in `caddy.nix`) reverse-proxying to it. Lets
  the **XP Time Machine** reach a fake Google during a probe run: the Time Machine's
  own NixOS courier is offline while XP is booted (one OS at a time, shared NIC), so
  the emulator must live on a separate always-on box — `code` via its existing Caddy.
  The `http://` site stays plain :80, no HTTPS upgrade (validated with `caddy validate`).
- Flip the speech bubble live: `ssh code 'echo calendar=none > /var/lib/gcal-emu/scenario.conf'`
  (`calendar=schedule|none|error`); read the captured request log at
  `/var/lib/gcal-emu/gcal-emu.log`.
- `gcal-emu/gcal_emu.py` is a **vendored mirror** of
  `/opt/src/LuckyMasterEN/tools/gcal-emu/gcal_emu.py` — re-sync if that changes.
  This is **testing scaffolding**; the end goal is a native XP-local build (no Python
  on XP), at which point this module + the vhost can be removed.
- Risk/follow-up: POP3 mail can't be Caddy-fronted (not HTTP) → deferred. Needs
  `deploy .#code` to go live; eval + Caddyfile-validated, not yet deployed.

## 2026-06-30 claude-code bump (wslop) — surgical update, pi disabled

Goal was a newer `claude-code` from `llm-agents`. A full `nix flake update`
broke the wslop build, and a bump of `llm-agents` alone wanted to build `pi`
from source. Resolved by deploying a **surgical** update instead.

- **claude-code 2.1.197 deployed to wslop** via `nix flake update llm-agents`
  only (+ its private `bun2nix`); `nixpkgs` held at the known-good `9ae611a`.
  `nixos-rebuild switch` clean; `claude --version` = 2.1.197 live.
- **pi-gemma disabled** — commented out (import + config block) in
  `modules/hm/common.nix`, preserved for a later revamp. Reason: `pi 0.80.2`
  isn't on `cache.numtide.com` (404), so enabling it forces a from-source
  bun2nix build. Verified this is **not** the `nixpkgs.follows` — pi resolves to
  the *identical* path with or without the follows, and both 404. [todo] re-enable
  the import + block when revamping pi.
- **Known risk — full flake update is currently blocked**: the fresh `nixpkgs`
  (`b5aa0fb`) ships `cantarell-fonts 0.311` broken to build (an `afdko`
  `otfautohint` regression) **and** uncached on every substituter, so it fails
  from source and cascades to fail the whole host. Stay on the surgical update
  until a `nixpkgs` rev where cantarell builds/caches. Documented as a rot class
  in `docs/UPDATING.md` (step 3).
  - **[resolved 2026-07-15]** The full update landed — `nixpkgs 0bb7ec5`
    (26.11.20260708) builds/caches cantarell again, so the surgical-only
    constraint is lifted. See the 2026-07-15 entry.

## 2026-07-15 full flake update deployed (wslop) — cantarell unblocked

Full `nix flake update` (superseding the 2026-06-30 surgical-only hold) built,
diffed, and deployed to wslop locally. Delivered the original goal — the latest
`claude-code` + `codex` from `llm-agents` — plus a month of `nixpkgs`.

- **Versions live on wslop**: `claude-code 2.1.197 → 2.1.206`,
  `codex 0.142.4 → 0.144.1`; `nixpkgs 9ae611a → 0bb7ec5`
  (26.11.20260610 → 26.11.20260708).
- **The "builds from source" scare was one lagging package, not a cache
  misconfig.** Under the *unchanged* substituter set, `codex`/`opencode` fetched
  from `cache.numtide.com` (HTTP 200) and the `nixpkgs` closure came from cache;
  only `claude-code 2.1.206` 404'd on numtide (their CI had not published that
  fresh version yet) and built once locally. No substituter setting conjures an
  unpublished path. The `llm-agents.inputs.nixpkgs.follows = "nixpkgs"` is *not*
  the cause — numtide cache hits under the follows prove it (matches the
  2026-06-30 `pi` finding). It re-caches once numtide catches up.
- **cantarell no longer blocks**: the `afdko`/`otfautohint` regression that broke
  `cantarell-fonts 0.311` at `b5aa0fb` is gone at `0bb7ec5`; the full toplevel
  evaluates clean (only per-config wrapper derivations build, as always).
- Deployed by activating the built closure (`nix-env --set` +
  `switch-to-configuration switch`), not a rebuild-from-flake, so the live
  generation is exactly the diffed one. Old generation retained for rollback.

## 2026-07-15 beszel-agent masked on wslop

`beszel-agent.service` had been failing on wslop since the host was created —
`Result: resources`, never activated, no logs — because the globally-wired
`modules/beszel.nix` (built for the GPU/server hosts; note the `/dev/nvidia*`
device rules) expects a secret at `/var/lib/secrets/beszel-agent` that was never
provisioned here. The 2026-07-15 redeploy surfaced it (restarted the unit); it
did not cause it (present identically in generation-49).

- Fix: masked the unit on wslop in `hosts/wslop/wslop.nix`
  (`services.beszel.agent.enable` and `systemd.services.beszel-agent.enable`
  both `lib.mkForce false`). Activation is now clean (exit 0); unit is `masked`.
- Not lab-check-visible: `utils/lab-check.sh` only checks
  `code mail cold lame relay`, and its beszel assertion is `code`-specific — no
  check change needed.
- If wslop should ever report to beszel, provision the secret instead of masking.

## 2026-07-21 lab-wide update — scoped inline-snapshot workaround

The periodic update advances Nixpkgs to `241313f` (2026-07-19), plus Home
Manager, llm-agents, nixos-mailserver, and NixOS-WSL.

- The current graph exposed an uncached `inline-snapshot 0.32.5`: three
  documentation snapshots expect Black 25 formatting under Black 26.5.1, while
  1,428 functional tests pass. `modules/nix.nix` therefore skips only
  `tests/test_docs.py` through `pythonPackagesExtensions`; the rest of the test
  suite remains enabled. Shigebot's package set does not inherit host overlays,
  so `hosts/code/code.nix` replaces its yt-dlp dependency with the host package
  to carry that same narrow workaround across the actual dependency boundary.
- An archived `d407951` graph was evaluated and built while diagnosing this,
  but rejected before any deployment: it would have downgraded 141 packages on
  the already-newer wslop, including systemd, Python, Nix, OpenSSL, and Firefox.
  It also changed all three llm-agents store paths away from Numtide's published
  outputs and caused Codex to compile locally once. Do not repeat that pin.
- Compatibility fixes from the updated inputs: use
  `nixos-mailserver.nixosModules.default`, set wslop's `nixpkgs.hostPlatform`
  explicitly, adopt Home Manager's nested fzf widget options, and rename Qt's
  platform theme from `gtk` to `gtk3`.
- The runbook now hard-gates Codex, claude-code, and opencode against Numtide
  before building. The exact final outputs (Codex 0.144.6, claude-code 2.1.216,
  opencode 1.18.4) all returned HTTP 200; no agent package was rebuilt in the
  final graph.
- `nix flake check --no-build` and all six final toplevel builds pass. Predeploy
  diffs show forward updates on every host; the only removed unit trees are the
  intentional lame ZFS auto-snapshot timers and mail's TLS-policy service,
  replaced upstream by socket activation.
- Code's live activation exposed a separate storage failure: 285 rooted system
  generations plus a 3.9 GiB journal had left no writable ext4 headroom.
  PostgreSQL hit `ENOSPC` during its recovery checkpoint and mandb failed while
  copying its cache. Archived journals were vacuumed to 1 GiB; generations
  older than 30 days were unrooted (four rollback points remain), then the Nix
  store was garbage-collected, freeing 76.6 GiB and leaving code at 52% used
  with 91 GiB available. PostgreSQL recovered and accepted connections without
  data repair. `lab-check.sh` now hard-fails every host below 5 GiB free or at
  90% usage, and the runbook makes that a pre-copy gate.
- Code, mail, relay, cold, and wslop are live on the `241313f` generation. Mail
  and relay rebooted successfully; relay needed no VPS-console intervention and
  its GRUB install, Headscale health endpoint, services, and certificate all
  passed. Cold was live-switched without a reboot, both pools remain ONLINE,
  and `/tmp/stay` remains present. Lame's new system profile is staged for boot
  but intentionally not live: its NVIDIA driver changes from 595.80 to 595.84,
  so it needs an authorized reboot/unlock rather than a mismatched live switch.
  The six-host aggregate health check finished at PASS=51, WARN=0, FAIL=0; lame
  remains healthy on the matching old kernel/userspace until that reboot.
- Proxmox was updated afterward from PVE 9.1.7 to `proxmox-ve 9.2.0` /
  `pve-manager 9.2.4` (213 upgrades, five new packages, zero removals or holds).
  APT/dpkg are clean with no pending upgrades; PVE services, all storage and
  `tank`, VMs 104/105, and CT 102 remained healthy throughout. Kernel
  `7.0.14-5-pve` is installed with ZFS 2.4.3 and is GRUB's explicit default,
  while the host intentionally remains on `6.17.13-2-pve` for the operator's
  pending reboot.
- The Proxmox upgrade found and fixed two boot risks before that reboot. The
  machine had actually booted through a stale removable fallback loader; GRUB's
  prescribed `force_efi_extra_removable` remediation now keeps it current and
  it matches the signed Proxmox shim. The custom `/usr/local/sbin/sync-esp` also
  lacked a trailing slash, producing an unbootable `EFI/EFI` tree on the backup
  ESP, and emitted rsync progress into `grub.cfg` through its GRUB hook. The
  script now mirrors silently into the correct root, both ESPs compare clean,
  `grub-script-check` passes, and the original script is retained remotely as
  `sync-esp.pre-update-20260721`.
- Follow-up: decide whether code should get a scheduled Nix GC policy. This
  update does not introduce automatic deletion behavior without an explicit
  retention decision.

## 2026-07-21 cold: Plasma/Moonlight desktop + torrent stack

`cold` stops being deploy-only. It gains a KDE Plasma desktop driven remotely
over Moonlight, the standard interactive shell stack, and a qBittorrent stack
with its inbox on a dedicated `gigavault` dataset. New files:
`hosts/cold/desktop.nix`, `hosts/cold/torrents.nix`, `hosts/cold/hm/home.nix`.

Hardware findings (probed on the box, they contradict what the config implies):

- cold's CPU is a **Ryzen 5 5600G — an APU**, so there is a Vega iGPU with
  `/dev/dri/renderD128` despite the host being built as a NAS. That means
  **VAAPI hardware encode** for Sunshine rather than software x264, which
  matters on a 12-thread box that also runs backups. `hardware-configuration.nix`
  lists no video driver only because nixos-generate-config had no reason to.
- `card1-HDMI-A-1` currently reads `connected`; DP-1 and HDMI-A-2 do not.

Decisions:

- **Session**: sddm (wayland) autologin as `headpats` → plasma6 →
  `graphical-session.target` → sunshine's user unit (it is `partOf` that target,
  so without an autologin session there is nothing to stream). Needs the new
  `headpats` user on cold; the desktop is the only reason it exists.
- **`video=HDMI-A-1:1920x1080@60e` kernel param.** Forces the connector on
  regardless of detection. Without it, a display that is absent or merely powered
  off leaves KWin with zero outputs and nothing to render into — which presents
  as "Moonlight connects, then instantly drops". **Requires a reboot**; a live
  `switch` does not apply it. `docs/UPDATING.md` now carries this as an explicit
  exception to cold's usual switch-don't-reboot rule.
- **Null audio sink** pinned at `priority.session=2000` so Sunshine always has a
  capture target; the real sinks are HDMI (vanishes when the display sleeps) and
  unused onboard analog.
- **Deliberately NOT reusing wslop's hm set**: `theme.nix` sets
  `qt.platformTheme = "gtk3"` and `default-apps.nix` forces wayland backends —
  both fight a Plasma session. cold gets `common` + `fonts` + `alacritty` only.
- **root stays on bash** (`users.users.root.shell = pkgs.bash`) even though
  `interactive.nix` sets `defaultUserShell = fish`. An audit of every path that
  SSHes into cold found nothing that breaks under fish today (the `backup` user
  already pins bash; `utils/lab-check.sh` funnels through `bash -s`; deploy-rs
  emits one flat command). But cold is the backup *target* — `root@cold` is the
  receiving end of wslop's rsync push — and the failure mode there is silently
  corrupted backups rather than a visible error. `headpats` gets fish.
- **Torrent inbox gating.** `gigavault` is zfs-encrypted, so on a fresh boot
  `/gigavault/torrents` is an empty dir on the rootfs. Starting qBittorrent then
  would write the profile and downloads there and have them shadowed on mount —
  the same bug class as lame's docker data-root. Guarded by
  `ConditionPathIsMountPoint`.
- A systemd **`.path` unit does not work** for this and was rejected: the inotify
  watch lands on the unmounted `/gigavault`, and mounting over a directory
  generates no event for the watcher underneath. Replaced with a 2-minute
  `qbittorrent-mount-watch` timer that starts the unit once the mount appears
  (a no-op while it is already running).
- **qBittorrent config is rendered here, not via the module's `serverConfig`**,
  because we need to own `ExecStartPre` to splice the web UI password in from
  `lab.secrets.qbittorrent` at runtime (`+` prefix = runs as root outside the
  sandbox, since the qbittorrent user cannot read the secrets dir). Note the
  module's ExecStartPre **overwrites the config on every start**, so anything
  changed in the web UI is lost on restart — settings belong in the nix file.
- **Connectivity**: static forward instead of UPnP (UPnP would race the opnsense
  rule and re-map to a port the forward does not target). DHT + PeX + LSD on,
  encryption "prefer" not "require" (requiring it silently drops peers).

Lifecycle (user's call, 2026-07-21): **unchanged.** cold stays a normally-off
box; the operator touches `/tmp/stay` when they want it to keep downloading, and
the existing orchestrator check honours it. The orchestrator was deliberately NOT
modified. Consequence to remember: `/tmp/stay` is tmpfs + `cleanOnBoot`, so it
must be re-created after every boot or the next nightly cycle powers cold off
mid-download. qBittorrent resume data survives, so this stalls rather than loses.

Deploy state:

- [todo] Provision on the box (both need the pool unlocked, neither is automatic):
  `torrent-storage-init` then `qbittorrent-set-password`.
- [todo] Forward `lab.ports.torrent` (51413) **TCP+UDP** on opnsense to
  `lab.lan.cold`. Nothing else is forwarded; web UI + Sunshine stay LAN-side.
- [todo] Pair Moonlight against `https://cold:47990`.
- Risk: the Plasma-on-Wayland + Sunshine KMS capture path is unproven on THIS
  box — the lab's only prior Sunshine experience is lame's containerised Xorg
  sandbox, which shares only the uinput/firewall skeleton. If capture fails,
  the fallbacks are an X11 session or `xf86-video-dummy`.

## Niri Desktop (wslop)

Niri is wired as a nested compositor under WSLg on the `wslop` host. The
non-WSL parts are reusable modules.

### Modules added

| Module | Type | What it does |
|--------|------|-------------|
| `modules/niri.nix` | NixOS | Installs niri, wayland-utils, wl-clipboard |
| `modules/hm/niri-config.nix` | HM | Generates `~/.config/niri/config.kdl` with lab.nix colors |
| `modules/hm/alacritty.nix` | HM | Installs/configures alacritty with lab.nix colors + PxPlus IBM VGA8 font |
| `modules/hm/fonts.nix` | HM | Fetches and installs PxPlus_IBM_VGA8.ttf |

### Architecture notes

- HM modules access NixOS options via `osConfig`, same pattern as `starship.nix`.
- Niri colors apply to focus-ring and border (active=blue base0D, inactive=dark
  gray base01). Alacritty gets the full terminal palette.
- WSL launch script (`niri-start`) runs `niri` directly — WSLg provides
  `WAYLAND_DISPLAY` so niri auto-detects nested mode.

### Known issues

- Resizing the WSLg window while niri is running causes a crash (likely a
  WSLg/niri interaction). Workaround: press Win+Shift+Enter to fullscreen
  the WSLg window before launching niri, or avoid resizing.
- `grammar-helper` and other local inputs are missing in this environment,
  so `nix flake check` fails on deploy-rs checks. Host-specific builds
  (`.#nixosConfigurations.wslop`) work fine.
