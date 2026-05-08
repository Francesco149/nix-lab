# nix-lab Workdoc

Last updated: 2026-05-08

## Project

Personal NixOS flake for homelab hosts, built on the local `nut` flake library.
The repo should stay easy for humans and coding agents to resume without
re-learning project conventions each session.

## Current Goals

- Keep `flake.nix` as the host/module wiring source of truth.
- Keep shared constants in `lib/lab.nix`.
- Keep `README.md` short and accurate; put operational runbooks in `docs/`.
- Avoid documentation/spec drift by linking to canonical files instead of
  copying values and commands into multiple places.

## Scope Notes

- `/opt/src/nix-lab` is editable.
- `/opt/src/nut` is reference-only unless explicitly requested.
- `lib/lab.nix` contains an unused color palette intentionally reserved for
  future theming.

## Findings

- `nut.lib.mf` automatically imports `hosts/<host>/configuration.nix` and
  `hosts/<host>/<host>.nix`, then appends global and host-specific modules.
- `nut.lib.mf` also injects Home Manager when `home-manager` exists and
  `hmModules` are configured.
- The previous README listed stale paths and hosts, including missing
  `hosts/code/hm/home.nix` details and omitted current `cold`/`lame` coverage.
- The tracked top-level file `2` was an obsolete starship TOML fragment and was
  removed during cleanup.
- `flake.lock` now points at `nut` commit `c158b1e`, which includes Home
  Manager `extraSpecialArgs.inputs` threading.
- A targeted eval confirmed `inputs` is present in
  `nixosConfigurations.code.config.home-manager.extraSpecialArgs`.

## Decisions

- Root `AGENTS.md` is the durable agent orientation file.
- Root `WORKDOC.md` is the durable cross-session task and decision log.
- Operational docs live under `docs/` and should avoid copying values that
  already live in `lib/lab.nix`.
- `nut` remains read-only for this cleanup.

## Tasks

- [done] Add durable agent orientation.
- [done] Add cross-session workdoc.
- [done] Replace stale README structure docs with an accurate overview.
- [done] Move operational notes out of README.
- [done] Remove obsolete tracked `2` file.
- [done] Update the locked `nut` input so Home Manager modules receive
  `inputs` from `nut`.
- [done] Clean up flake check warnings: `system` rename, `mesa.drivers`
  deprecation, and renamed nixos-mailserver options.
- [todo] Consider generating docs from `lib/lab.nix` if the host inventory grows.
- [todo] Wire `lab.colors` into theming when ready.
