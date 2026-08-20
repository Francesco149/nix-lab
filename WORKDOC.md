# nix-lab Workdoc

Personal NixOS flake for homelab hosts, built on the local `nut` flake library.
This document serves as the single high-level overview of how the lab works, its
current operational state, and active goals.

---

## Current Goals

* **None at the moment.** The lab infrastructure, backup pipelines, desktop/media
  stacks, and coding agent environments are fully deployed, healthy, and operational.

---

## Source Of Truth & Layout

* `flake.nix`: Host inventory, global module composition, and per-system outputs.
* `lib/lab.nix`: Shared constants, addresses, domains, ports, secret paths, SSH keys,
  backup targets, and lab-wide values.
* `hosts/<name>/`: Host-specific service definitions (`<name>.nix`) and base configurations
  (`configuration.nix`).
* `modules/`: Reusable NixOS and Home Manager modules applied across hosts.
* `docs/`: In-depth operational runbooks and subsystem documentation.

---

## Host Inventory & Operational Roles

| Host | IP / Address | Role & Service Composition |
| --- | --- | --- |
| **`code`** | `10.0.10.53` (`code.box.headpats.uk`) | Core interactive VM on Proxmox. Runs Caddy reverse proxy (`*.box.headpats.uk`), local binary cache (`cache.box.headpats.uk`), Beszel hub, Dockge, app services (shigebot, grammar-helper, gcal-emu), and backup orchestration (`cold-backup.py`). |
| **`mail`** | `10.0.10.52` (`mail.box.headpats.uk`) | Dedicated mail host. Runs `nixos-mailserver`, Gmail IMAP XOAUTH2 fetcher, and DMARC analyzer. |
| **`relay`** | Public VPS | Public ingress and headscale control plane (`hs.headpats.uk` via Cloudflare DNS-01 ACME), inbound stream proxying, and authenticated outbound mail relay. |
| **`cold`** | `10.0.10.54` (`cold.box.headpats.uk`) | Encrypted storage host (`gigavault` ZFS pool). Nightly pull backup target (read-only datasets), remote initrd unlock (`cold-unlock`), KDE Plasma desktop over Moonlight, qBittorrent stack, and read-only authenticated SMB shares (`archive`, `staging`, `torrents`). |
| **`lame`** | `10.0.10.56` (`lame.box.headpats.uk`) | GPU inference server (Radeon 7800XT + RTX 3080). Local VLM vision endpoint (port 8080 via `gpu-switch vision`), Docker runtime on ZFS, and detached testbed runner for `haruness`. |
| **`wslop`** | Workstation (WSL2) | Local NixOS-WSL build & deploy host (`rd_host`), primary Oh My Pi (`omp`) coding environment, and nested Niri desktop under WSLg. |
| **`timemachine`** | Foreign Target | Retro gaming rig whose NVMe NixOS courier images cold Windows system disks to `cold`. |

---

## Core Invariants & Architecture Rules

1. **Secrets Out of Store**: Secrets live in `/var/lib/secrets` (or `~/.omp/agent/.env`
   for agent keys) with strict permissions (`700`/`600`), never in the Nix store.
2. **Read-Only Backup Datasets**: Backup target datasets on `gigavault` are set to
   `readonly=on` to prevent accidental operator mutation or corruption.
3. **Drive Preservation (`/tmp/stay`)**: Helium drives on `cold` and `lame` use
   `/tmp/stay` to prevent the nightly backup orchestrator from power-cycling them
   when they are meant to stay up.
4. **Workstation Build & Deploy (`wslop`)**: Heavy Nix evaluations and package builds
   execute on `wslop` (`rd_host`), pushing closures over SSH to target hosts.
5. **No Magic Literals**: Addresses, ports, and common paths must be sourced from
   `lib/lab.nix` rather than hardcoded in modules or docs.

---

## Documentation Map

For operational procedures and subsystem details, consult the dedicated guides in `docs/`:

* **[docs/OMP.md](docs/OMP.md)** — **Oh My Pi, AI Models, & Agents**: Provider logins
  (Google Antigravity / Gemini Pro, Z.AI GLM Coding Plan, DeepSeek, Claude),
  multi-account refresh token management (`omp-token`), vision routing, and `haruness`.
* **[docs/OPERATIONS.md](docs/OPERATIONS.md)** — **Deployment & Day-to-Day Ops**: Host
  deploy commands, initial node boot, secret creation, Gmail OAuth, backups, dataset
  management, and recovery.
* **[docs/UPDATING.md](docs/UPDATING.md)** — **Update & Redeploy Runbook**: Step-by-step
  routine maintenance, input bumps, cache verification, and post-deploy health checks
  (`utils/lab-check.sh`).
* **[docs/OPNSENSE.md](docs/OPNSENSE.md)** — **Router & Firewall**: OPNsense API access,
  port forwarding rules, aliases, and DNS overrides.
* **[docs/STRUCTURE.md](docs/STRUCTURE.md)** — **Flake Layout & Wiring**: Host-to-module
  mapping and `nut` framework conventions.
* **[docs/NIRI.md](docs/NIRI.md)** — **Desktop Compositor**: Niri under WSLg, keybindings,
  and styling on `wslop`.
* **[docs/NVIM.md](docs/NVIM.md)** — **Custom Editor**: The `e` Neovim wrapper, treesitter,
  LSP, and OSC52 clipboard forwarding.
* **[docs/TMUX.md](docs/TMUX.md)** — **Terminal Multiplexer**: System tmux defaults, keybindings,
  and color palette integration.
