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
  ...
modules/
  hm/                   # shared home-manager modules
  ...
  # shared modules
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

---

## first time setup

There's a few things that still can't be done fully declaratively so we will
have to run some commands after the first deploy.

### code

Bring up tailscale and advertise the home lan:

```sh
tailscale up --advertise-routes=10.0.10.0/24 --login-server=https://hs.headpats.uk
```

SSH into the relay and approve the route

```sh
headscale nodes list  # get node id
headscale nodes approve-routes --identifier <node-id> --routes 10.0.10.0/24
```

### relay

Bring up tailscale and verify that it sees the home ip's

```sh
tailscale up --accept-routes --login-server=https://hs.headpats.uk
ping 10.0.10.1
```

The split DNS config in headscale only routes queries for `*.box.headpats.uk`
and reverse lookups for `10.x.x.x` to my OPNsense, everything else uses the
node's normal DNS. The `10.in-addr.arpa` entry handles reverse DNS for the LAN
IPs.
