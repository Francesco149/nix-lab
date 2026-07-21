# nix-lab

Personal NixOS configuration for my homelab. It is not meant to be consumed as
a reusable distribution, but it can be useful as a reference.

This repo is built with [`nut`](https://github.com/Francesco149/nut), my local
flake library for the boilerplate around NixOS hosts, deploy-rs, Home Manager,
and flake-parts. In this checkout, `nut` is referenced as `/opt/src/nut`.

## Hosts

| Host | Role |
| --- | --- |
| `code` | Interactive VM for reverse proxying, cache, service UIs, Dockge, Beszel hub, and backup orchestration. |
| `mail` | Mailserver, Gmail fetch, and DMARC analyzer. |
| `relay` | Public VPS for headscale, inbound SMTP/ACME stream proxying, and outbound mail relay. |
| `cold` | Cold storage and ZFS backup target with remote unlock support. Also runs a Plasma desktop driven over Moonlight, and the torrent stack. |
| `lame` | GPU inference host for local AI services. |

`immich` also exists in the lab, but it is a Proxmox LXC managed outside this
flake and reverse-proxied by `code`.

## Source Of Truth

- `flake.nix` defines the flake inputs, host inventory, global modules, and
  per-system outputs.
- `lib/lab.nix` defines shared constants: addresses, domains, ports, secret
  paths, SSH keys, backup targets, and similar lab-wide values.
- `hosts/<host>/` contains host-local NixOS modules and scripts.
- `modules/` contains reusable NixOS and Home Manager modules.
- `AGENTS.md` and `WORKDOC.md` keep coding-agent conventions, goals, and task
  state durable across sessions.

The palette in `lib/lab.nix` is used by small interactive tools such as the
custom editor and tmux chrome while leaving terminal backgrounds alone.

## Nut Conventions

`nut.lib.mf` automatically imports these modules for each host:

- `hosts/<host>/configuration.nix`
- `hosts/<host>/<host>.nix`
- `/opt/src/nut/modules/ssh.nix`

It also injects Home Manager for configured users when this flake provides
`hmModules`. Because of that, `flake.nix` lists only global modules and
host-specific extras.

See [docs/STRUCTURE.md](docs/STRUCTURE.md) for the current layout and host
wiring details.

## Operations

Operational procedures live in [docs/OPERATIONS.md](docs/OPERATIONS.md). The
short version:

```sh
deploy
deploy .#code
build-system code
diff-system mail
check-inputs
```

Those helpers are fish functions from `modules/hm/fish/dev.fish`.

Update/redeploy runbook: [docs/UPDATING.md](docs/UPDATING.md). Router port
forwards and DNS overrides (the OPNsense box is not managed by this flake):
[docs/OPNSENSE.md](docs/OPNSENSE.md).

## Development

Enter the dev shell with direnv or:

```sh
nix develop
```

Useful checks:

```sh
nix flake check --no-build
nix fmt
statix check
```

Choose the lightest check that validates the change. For documentation-only
edits, no Nix evaluation is usually needed.
