# nix-lab Workdoc

Last updated: 2026-06-10

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
