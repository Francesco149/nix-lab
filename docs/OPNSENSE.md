# OPNsense

The lab's router/firewall. Not managed by this flake — it is a separate
appliance — but the lab depends on it for port forwards and DNS overrides, so
the procedures live here.

| | |
|---|---|
| Host | `uwusense.soy` — resolves to several addresses, one per interface |
| Web UI / API | `https://10.0.10.1:8443` (NOT 443 — nothing listens there) |
| Also reachable as | `https://sense.box.headpats.uk` |
| Version | OPNsense 26.1.11 (core ABI 26.1) |
| SSH | **disabled** — the API and the GUI are the only ways in |

## Interfaces

Rules refer to the logical name (left column), never the device.

| Logical | Device | Description |
|---------|--------|-------------|
| `wan` | `pppoe0` | WAN — **PPPoE**, so the public address is dynamic |
| `lan` | `igc1` | LAN — `10.0.10.0/24`, where the lab hosts live |
| `opt1` | `igc0` | ISP_Modem |
| `opt2` | `vlan01` | Homelab |

## API access

The root API key/secret lives in a downloaded key file, currently
`C:\Users\headpats\Downloads\uwusense.soy_root_apikey.txt` (from wslop:
`/mnt/c/Users/headpats/Downloads/...`). Keep it out of this repo.

Calls are HTTP basic auth, `key` as username and `secret` as password:

```sh
KEY=$(grep '^key='    "$KEYFILE" | cut -d= -f2- | tr -d '\r\n')
SECRET=$(grep '^secret=' "$KEYFILE" | cut -d= -f2- | tr -d '\r\n')

# GET: do NOT send a Content-Type. OPNsense answers
#   {"status":400,"message":"Invalid JSON syntax"}
# to a GET that declares application/json with an empty body.
curl -sk -u "$KEY:$SECRET" https://10.0.10.1:8443/api/core/firmware/status

# POST: body required, even if empty ({})
curl -sk -u "$KEY:$SECRET" -X POST -H 'Content-Type: application/json' \
  --data-binary '{}' https://10.0.10.1:8443/api/firewall/alias/reconfigure
```

Every change is two steps: **mutate**, then **apply**. Nothing takes effect
until the apply/reconfigure call, and an un-applied change is invisible to
traffic while still showing in the GUI as pending.

## What the API can and cannot do

This is the important part, and it is not obvious.

**Port forwards are NOT in the API.** OPNsense's MVC API covers the newer
"Firewall: Automation" models only:

| Endpoint | Covers |
|----------|--------|
| `firewall/filter` | Automation filter rules (pass/block) |
| `firewall/source_nat` | Outbound NAT (SNAT) |
| `firewall/one_to_one` | 1:1 NAT |
| `firewall/npt` | NPTv6 |
| `firewall/alias` | Aliases — **fully usable** |

Classic **Firewall → NAT → Port Forward** (rdr) is still a legacy page backed
directly by `config.xml`, and has no controller. Verified on 26.1.11: every one
of `firewall/nat`, `firewall/nat_port_forward`, `firewall/forward`,
`firewall/portforward`, `firewall/dnat`, `firewall/rdr` returns
`{"errorMessage":"Endpoint not found"}`, while `firewall/npt/searchRule` on the
same box returns a normal empty result — so the naming pattern is right and the
absence is real.

Consequences:

- **Creating a port forward is a one-time GUI action.** There is no supported
  API path. (Rewriting `config.xml` through `core/backup` would work but
  replaces the entire configuration and generally wants a reboot of the router —
  not worth it to add one rule.)
- **Changing which ports an existing forward covers IS scriptable**, if the rule
  is built against an alias. That is the pattern below.

## The pattern: one rule per host, ports in an alias

Point the rule's destination *and* redirect port at a per-host **port alias**.
The rule then never needs touching again — adding or removing a port is an API
call against the alias.

Naming convention: `pf_<host>_<purpose>`, type `Port(s)`.

### Adding ports to an existing forward (API — no GUI)

```sh
# inspect
curl -sk -u "$KEY:$SECRET" \
  'https://10.0.10.1:8443/api/firewall/alias/get' | jq '.alias.aliases.alias'

# find the uuid by name
UUID=$(curl -sk -u "$KEY:$SECRET" \
  'https://10.0.10.1:8443/api/firewall/alias/searchItem?searchPhrase=pf_cold_torrent' \
  | jq -r '.rows[0].uuid')

# replace the content (newline-separated for multiple entries)
curl -sk -u "$KEY:$SECRET" -X POST -H 'Content-Type: application/json' \
  --data-binary '{"alias":{"enabled":"1","name":"pf_cold_torrent","type":"port","content":"51413\n6881","description":"cold: torrent ports"}}' \
  "https://10.0.10.1:8443/api/firewall/alias/setItem/$UUID"

# apply — nothing is live until this runs
curl -sk -u "$KEY:$SECRET" -X POST -H 'Content-Type: application/json' \
  --data-binary '{}' 'https://10.0.10.1:8443/api/firewall/alias/reconfigure'
```

`content` is a full replacement, not an append — send the complete list.
Removing a port is the same call with that port left out.

### Adding a forward for a NEW host (one-time, GUI)

1. Create the port alias first, via the API above
   (`firewall/alias/addItem`, `type: "port"`), or **Firewall → Aliases**.
2. **Firewall → NAT → Port Forward → +**, and set:

   | Field | Value |
   |-------|-------|
   | Interface | `WAN` |
   | TCP/IP version | IPv4 |
   | Protocol | `TCP/UDP` if the service needs both, else pick one |
   | Destination | `WAN address` |
   | Destination port range | the alias, e.g. `pf_cold_torrent` (from/to both) |
   | Redirect target IP | the LAN address, e.g. `10.0.10.54` |
   | Redirect target port | the same alias |
   | Description | what and why |
   | NAT reflection | leave default unless reaching it from inside the LAN |
   | Filter rule association | **Add associated filter rule** |

3. Save, then **Apply changes**.

"Add associated filter rule" is what creates the matching WAN pass rule and
keeps it in sync with the NAT rule. Without it the translation happens and the
packet is then dropped by the default deny — a forward that looks correct and
does nothing.

Because WAN is **PPPoE with a dynamic address**, always use `WAN address` as the
destination rather than a literal IP — a hardcoded address breaks on
reconnection.

### Removing a forward

**Firewall → NAT → Port Forward**, delete the rule, **Apply changes**. If it was
created with an associated filter rule, that rule goes with it. Then delete the
alias if nothing else uses it (`firewall/alias/delItem/$UUID` + `reconfigure`).

## Current forwards

| Alias | Ports | Target | For |
|-------|-------|--------|-----|
| `pf_cold_torrent` | 51413 TCP+UDP | `10.0.10.54` (cold) | qBittorrent peer port — see `docs/OPERATIONS.md` |

Before this, the box had **no port forwards at all** — `<nat>` contained only
outbound rules. Anything internet-facing in the lab reaches the outside through
the relay VPS instead, so a new forward here is a genuine change in exposure and
worth a second look.

## Safety

- The API key is **root-equivalent**. Treat the key file as a credential.
- `core/backup/download/this` returns the whole `config.xml`, **including
  secrets** (certificates, passwords, keys). Do not leave copies lying around
  and never commit one.
- Config history is under **System → Configuration → History**, and boot
  environments under **System → Snapshots**, if a change needs rolling back.
