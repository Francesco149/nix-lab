# nix-lab

My personal NixOS configuration. Not intended to be used directly, but feel free
to poke around for reference or inspiration.

Built with [nix-utils](https://github.com/Francesco149/nix-utils), my own flake
library that cuts out the boilerplate of wiring up deploy-rs, home-manager, and
flake-parts. If you are building something similar, that is probably a better
starting point than this repo.

---

## machines

| host   | description                                               |
| ------ | --------------------------------------------------------- |
| `code` | home server running docker, openvscode-server, and dockge |

---

## structure

```text
hosts/
  code/
    configuration.nix   # hardware/boot config
    code.nix            # machine-specific NixOS config
    hm/
      home.nix          # per-machine home-manager config
modules/
  hm/                   # shared home-manager modules
  docker.nix
  nix.nix
  system.nix
  tailscale.nix
  ssh.nix
lib/
  nixvim.nix            # shared nixvim config
  nixvim-ssh.nix        # ssh-specific nixvim overrides (OSC52 clipboard etc)
```

---

## deploying

With [deploy-rs](https://github.com/serokell/deploy-rs):

```sh
deploy          # all machines
deploy .#code   # one machine
```

Or directly:

```sh
nixos-rebuild switch --flake .#code
```
