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
  cold/                   cold storage, ZFS backup target, remote unlock
  lame/                   inference server, GPUs, local AI services
modules/
  *.nix                   reusable NixOS modules
  hm/                     shared Home Manager modules and shell config
utils/
  gmail-oauth.py          Gmail OAuth helper
docs/
  OPERATIONS.md           deployment, secrets, recovery notes
  STRUCTURE.md            this file
AGENTS.md                 agent-facing conventions and source-of-truth map
WORKDOC.md                cross-session goals, decisions, and task log
```

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
| `cold` | Cold storage and backup target | local LAN, tailnet LAN, initrd unlock, ZFS, backup target |
| `lame` | GPU inference host | disko, interactive shell, local LAN, tailnet LAN, initrd unlock, ZFS, backup target, root HM |

## Documentation Boundaries

- `README.md` is an entrypoint and should stay compact.
- `docs/STRUCTURE.md` documents repo layout and wiring.
- `docs/OPERATIONS.md` documents procedures.
- `AGENTS.md` documents conventions for coding agents.
- `WORKDOC.md` tracks active goals, decisions, and follow-up tasks.

When documentation needs a value from the system, prefer naming the canonical
`lab` attribute instead of copying the current literal value.
