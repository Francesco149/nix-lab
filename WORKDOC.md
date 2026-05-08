# nix-lab Workdoc

Last updated: 2026-05-08

## Project

Personal NixOS flake for homelab hosts, built on the local `nut` flake library.
The repo should stay easy for humans and coding agents to resume without
re-learning project conventions each session.

## Current Goals

- Keep `flake.nix` as the host/module wiring source of truth.
- Keep shared constants in `lib/lab.nix`.
- Provide a system-wide custom Neovim launcher named `e` for interactive hosts
  without changing the clean `neovim` package used by OpenVSCode.
- Keep editor colors tied to `lib/lab.nix` and avoid overriding the terminal
  background.

## Scope Notes

- `/opt/src/nix-lab` is editable.
- `/opt/src/nut` is reference-only unless explicitly requested.
- `interactive.nix` is currently included by `code` and `lame`.
- OpenVSCode should keep using system `neovim`; the custom editor should remain
  isolated behind the `e` launcher.

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
- [todo] Consider generating docs from `lib/lab.nix` if the host inventory grows.
