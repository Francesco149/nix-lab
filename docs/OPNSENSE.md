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
| Public address | dynamic (WAN is PPPoE) |

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
  --data-binary '{}' https://10.0.10.1:8443/api/firewall/d_nat/apply
```

Every change is two steps: **mutate**, then **apply**. Nothing reaches the
packet filter until the apply call, and an un-applied change still shows in the
GUI as pending.

## Finding the right endpoint

The API controller name often does **not** match the menu label. Port forward is
"Destination NAT" in the GUI and `d_nat` in the API — not `destination_nat`,
`nat`, `portforward`, `dnat` or `rdr`, all of which return
`{"errorMessage":"Endpoint not found"}` and make it look like no API exists.

Do not guess. Ask the box:

```sh
curl -sk -u "$KEY:$SECRET" https://10.0.10.1:8443/api/core/menu/search \
  | tr ',' '\n' | grep -iE '"(Url|VisibleName)"' | grep -iB1 nat
```

The `Url` is the answer. `/ui/firewall/d_nat/` → the API is `firewall/d_nat`.
A `/…​.php` URL means a legacy page with no MVC API (Outbound NAT is one).

Current NAT model coverage:

| GUI page | URL | API |
|----------|-----|-----|
| Source NAT | `/ui/firewall/source_nat/` | `firewall/source_nat` |
| **Destination NAT** (port forward) | `/ui/firewall/d_nat/` | **`firewall/d_nat`** |
| One-to-One | `/ui/firewall/one_to_one/` | `firewall/one_to_one` |
| NPTv6 | `/ui/firewall/npt/` | `firewall/npt` |
| Outbound | `/firewall_nat_out.php` | none (legacy) |

Aliases are `firewall/alias`; automation filter rules are `firewall/filter`.

## ⚠️ Nested fields must be nested JSON

**This is the trap that matters.** `searchRule` *returns* nested fields in dotted
form (`destination.network`), but sending them that way in a POST is **silently
ignored** — no error, `{"result":"saved"}`, and the field is left empty.

An empty `destination` and `destination.port` on a port-forward rule does not
fail closed. It means *any destination, any port*, so the rule redirects *all*
inbound WAN traffic to the target host and, with `pass`, permits it. This was
created and applied on this box before being caught; it existed for about a
minute before deletion.

```jsonc
// WRONG — silently produces a match-everything rule
{"rule":{"destination.network":"wanip","destination.port":"pf_cold_torrent"}}

// RIGHT — nested objects
{"rule":{"destination":{"network":"wanip","port":"pf_cold_torrent"}}}
```

**Always create rules with `"disabled":"1"`, read them back, and only then
enable.** The verification step is not optional here, because the failure mode is
silent and fails *open*.

## Adding a port forward

Ports live in an alias so future changes never touch the rule. Convention:
`pf_<host>_<purpose>`, type `port`.

```sh
API=https://10.0.10.1:8443/api
post() { curl -sk -u "$KEY:$SECRET" -X POST -H 'Content-Type: application/json' \
           --data-binary "$2" "$API/$1"; }
get()  { curl -sk -u "$KEY:$SECRET" "$API/$1"; }

# 1. the port alias
post firewall/alias/addItem '{"alias":{"enabled":"1","name":"pf_cold_torrent",
  "type":"port","content":"51413","description":"cold: qBittorrent peer port"}}'
post firewall/alias/reconfigure '{}'

# 2. the rule — DISABLED, nested fields
post firewall/d_nat/addRule '{"rule":{
  "disabled":"1",
  "interface":"wan",
  "ipprotocol":"inet",
  "protocol":"tcp/udp",
  "source":{"network":"any"},
  "destination":{"network":"wanip","port":"pf_cold_torrent"},
  "target":"10.0.10.54",
  "local-port":"pf_cold_torrent",
  "pass":"pass",
  "descr":"cold: qBittorrent peer port"}}'

# 3. READ IT BACK before enabling — destination.* must not be empty
get firewall/d_nat/searchRule | jq '.rows[] | select(.uuid!="lockout_0")'

# 4. enable + apply  (toggleRule flips state; it ignores a trailing 0/1)
post "firewall/d_nat/toggleRule/$UUID" '{}'
post firewall/d_nat/apply '{}'
```

Field notes:

- `destination.network` = **`wanip`** — the *current* WAN address. WAN is PPPoE
  with a dynamic address, so a literal IP here breaks on reconnection.
- `protocol` = `tcp/udp` when a service needs both on one port (qBittorrent does:
  TCP for peers, UDP for µTP and DHT). It becomes two pf rules.
- `pass` = `"pass"` emits `rdr pass`, which redirects *and* permits in one rule —
  no separate filter rule to keep in sync. `""` is Manual (you write the filter
  rule yourself) and `"rule"` registers a separate one.
- `local-port` may be the same alias as `destination.port` for a 1:1 mapping.

### Verify it actually works

Config state is not proof. Check the live ruleset:

```sh
get diagnostics/firewall/pf_statistics/rules | grep -oE "rdr[^\"]*10\.0\.10\.54[^\"]*"
# @2 rdr pass on pppoe0 inet proto tcp from any to (pppoe0:1) port = 51413 -> 10.0.10.54
# @3 rdr pass on pppoe0 inet proto udp from any to (pppoe0:1) port = 51413 -> 10.0.10.54
```

Then prove it end-to-end from **outside** the LAN — the relay VPS is the lab's
handy vantage point, since testing from inside only exercises NAT reflection:

```sh
ssh root@relay 'timeout 8 bash -c "echo > /dev/tcp/<public-ip>/51413" \
  && echo OPEN || echo closed'
```

## Changing ports later (no GUI, no rule edit)

Because the rule points at an alias, this is the whole procedure:

```sh
UUID=$(get 'firewall/alias/searchItem?searchPhrase=pf_cold_torrent' | jq -r '.rows[0].uuid')

# content is a FULL REPLACEMENT, newline-separated — send the complete list
post "firewall/alias/setItem/$UUID" '{"alias":{"enabled":"1","name":"pf_cold_torrent",
  "type":"port","content":"51413\n6881","description":"cold: torrent ports"}}'
post firewall/alias/reconfigure '{}'
```

Removing a port is the same call with it left out.

## Removing a forward

```sh
post "firewall/d_nat/delRule/$UUID" '{}'
post firewall/d_nat/apply '{}'
# then the alias, if nothing else uses it
post "firewall/alias/delItem/$ALIAS_UUID" '{}'
post firewall/alias/reconfigure '{}'
```

## Current forwards

| Alias | Ports | Target | For |
|-------|-------|--------|-----|
| `pf_cold_torrent` | 51413 TCP+UDP | `10.0.10.54` (cold) | qBittorrent peer port — see `OPERATIONS.md` |

Before this the box had **no port forwards at all** — everything internet-facing
in the lab reaches the outside through the relay VPS instead. A forward here is
therefore a genuine change in exposure and worth a second look.

## Safety

- The API key is **root-equivalent**. Treat the key file as a credential.
- `core/backup/download/this` returns the whole `config.xml`, **including
  secrets** (certificates, passwords, keys). Do not leave copies around and never
  commit one.
- Rollback: **System → Configuration → History** for config, **System →
  Snapshots** for boot environments.
