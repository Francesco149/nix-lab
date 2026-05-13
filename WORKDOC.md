# nix-lab Workdoc

Last updated: 2026-05-13

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
