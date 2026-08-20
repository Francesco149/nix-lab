# Structure

## Layout

```text
flake.nix                 host inventory, global modules, per-system outputs
lib/
  lab.nix                 shared constants and lab-wide data
  devShell.nix            development shell package list
hosts/
  code/                   interactive VM, reverse proxy, cache, app services
  mail/                   mailserver, Gmail fetch, DMARC analyzer
  relay/                  VPS, headscale, public mail relay, stream proxy
  cold/                   cold storage, ZFS backup target, remote unlock,
                          plasma/moonlight desktop, torrent stack, read-only SMB
  lame/                   inference server, GPUs, local AI services
modules/
  *.nix                   reusable NixOS modules
  hm/                     shared Home Manager modules and shell config
utils/
  gmail-oauth.py          Gmail OAuth helper
docs/
  OPERATIONS.md           deployment, secrets, recovery notes
  UPDATING.md             step-by-step update and redeploy runbook
  OMP.md                  Oh My Pi, model logins, token rotation, vision protocol
  OPNSENSE.md             router firewall API, port forwards, and DNS overrides
  STRUCTURE.md            this file
  NIRI.md                 Niri desktop setup under WSLg
  NVIM.md                 custom Neovim launcher and editor behavior
  TMUX.md                 system tmux defaults and keybindings
AGENTS.md                 agent-facing conventions and source-of-truth map
WORKDOC.md                high-level system state, invariants, and active goals

## Host Wiring

This flake calls `nut.lib.mf` in `flake.nix`. `nut` supplies the default host
imports, deploy-rs wiring, and Home Manager injection. Because of that, a host
entry in `flake.nix` should list only extra modules or host-specific Home
Manager modules.

Current host entries:

| Host | Role | Extra wiring in `flake.nix` |
| --- | --- | --- |
| `code` | Interactive VM, Caddy, cache, service UIs, backup orchestrator | Docker, interactive shell, local LAN, tailnet LAN route, grammar/lurk/shigebot modules, root HM |
| `mail` | Mailserver and DMARC analyzer | nixos-mailserver, DMARC analyzer, local LAN, tailnet LAN |
| `relay` | Public VPS relay and headscale | no extra modules; host file owns specifics |
| `cold` | Cold storage, backup target, remote desktop, torrents, read-only SMB | local LAN, tailnet LAN, initrd unlock, ZFS, backup target, interactive, plasma + sunshine, qbittorrent, Samba + WSD |
| `lame` | GPU inference host | disko, interactive shell, local LAN, tailnet LAN, initrd unlock, ZFS, backup target, root HM |

## Documentation Boundaries

- `README.md` is an entrypoint and should stay compact.
- `docs/STRUCTURE.md` documents repo layout and wiring.
- `docs/OPERATIONS.md` documents deployment, backup, and service procedures.
- `docs/UPDATING.md` documents the step-by-step lab update runbook.
- `docs/OMP.md` documents Oh My Pi harness configuration, model authentication, token rotation, and vision routing.
- `docs/OPNSENSE.md` documents router API automation, port forwards, and DNS.
- `docs/NIRI.md` documents the desktop compositor on `wslop`.
- `docs/NVIM.md` documents the custom `e` editor setup.
- `docs/TMUX.md` documents the system tmux setup.
- `AGENTS.md` / `CLAUDE.md` documents conventions for coding agents.
- `WORKDOC.md` tracks high-level system state, core invariants, and active goals.
When documentation needs a value from the system, prefer naming the canonical
`lab` attribute instead of copying the current literal value.
