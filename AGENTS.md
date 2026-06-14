# nix-lab Agent Guide

This repo is a personal NixOS flake. Keep changes small, explicit, and biased
toward reducing configuration/documentation drift.

## Scope

- You may edit this repo.
- Treat `/opt/src/nut` as read-only reference unless the user explicitly opens
  that scope.
- Do not move host behavior between machines without calling it out.
- Do not remove secrets placeholders or deployment notes just because they are
  not referenced by Nix.

## Source Of Truth

- `flake.nix`: host inventory and module wiring.
- `lib/lab.nix`: shared constants, addresses, domains, ports, secrets paths,
  SSH keys, backup targets, and other values that would otherwise become magic
  strings.
- `hosts/<name>/<name>.nix`: host-specific service composition.
- `hosts/<name>/configuration.nix`: hardware/boot/base host config loaded by
  `nut` automatically.
- `modules/`: reusable NixOS modules applied globally or per host.
- `modules/hm/`: shared Home Manager modules.
- `WORKDOC.md`: current goals, decisions, and follow-up tasks across sessions.

The color palette in `lib/lab.nix` is intentionally unused for now. Leave it in
place until it is wired into theming.

## Nut Integration

`nix-lab` uses `nut.lib.mf` from `/opt/src/nut`. Important conventions from
`nut/lib/mkFlake.nix`:

- Every host automatically imports:
  - `/opt/src/nut/modules/ssh.nix`
  - `hosts/<host>/configuration.nix`
  - `hosts/<host>/<host>.nix`
- Global `modules = [ ... ]` in `flake.nix` are appended to every host.
- Host-specific modules come from `hosts.<name>.modules` or a host list.
- If `home-manager` is an input and `hmModules` are present, nut injects
  Home Manager and imports `hosts/<host>/hm/home.nix` before the listed modules
  for each user.
- `nut.deploy.host` defaults to the host name unless overridden.

Do not duplicate those automatically injected paths in `flake.nix`.

## Editing Rules

- Prefer moving constants into `lib/lab.nix` over scattering literals.
- Prefer one obvious place for each piece of documentation. Link to it instead
  of repeating commands in multiple files.
- When changing docs, update `README.md` only for navigation/overview and put
  operational details in `docs/`.
- Keep `WORKDOC.md` current when a task creates follow-up work, introduces a
  convention, or leaves a known risk.
- Use `rg`/`git ls-files` for exploration and read focused file ranges.
- Preserve existing uncommitted changes unless the user asks otherwise.

## Commits

- When committing changes, include a co-author trailer on every commit with
  your model name so the provenance is clear:
  - Codex agents: `Co-authored-by: OpenAI Codex <codex@openai.com>`
  - Opencode agents: use your model name, e.g.
    `Co-authored-by: DeepSeek V4 Pro <noreply@opencode.ai>`
- Prefer split commits for unrelated work, with the co-author trailer on each
  commit.
- Commit in logical units AS YOU GO. Don't let unrelated changes pile up into
  one large mixed changeset and commit it all at the end — land each coherent
  change as its own commit while working. (A single file spanning concerns can
  still be one commit; the point is incremental, scoped history.)

## Checks

Use the lightest check that validates the change:

- Documentation-only: no Nix check required.
- Nix formatting: `nix fmt` if available for the touched Nix files.
- Nix evaluation: `nix flake check --no-build` when module wiring changes.
- Host build smoke test: `build-system <host>` for meaningful host changes.

## Operations & Updates

Operational docs (link to these; don't duplicate their contents):

- `docs/OPERATIONS.md` — deploy/recovery, backups, service notes.
- `docs/UPDATING.md` — step-by-step manual update + redeploy runbook.
- `utils/lab-check.sh` — verbose post-deploy health check with a PASS/WARN/FAIL
  summary; run after every deploy.

`docs/UPDATING.md` and `utils/lab-check.sh` encode how the lab is updated,
deployed, and verified. They drift silently and only bite during a bad deploy,
so update them IN THE SAME CHANGE whenever structure shifts: a host
added/removed/renamed or its address/role changes; the deploy/unlock flow,
`/tmp/stay`, or the nightly timer changes; a new critical service/cert/backup
invariant a healthy host must have (add a check); or a new class of update-time
"rot" to fix (note it in the runbook). If you change those without touching
these files, say why.

## Binary Caches

When running Nix builds/checks in this repo, use the homelab cache first. It is
a local domain: `cache.box.headpats.uk` resolves through the router at
`10.0.10.1` to `10.0.10.53`, so sandboxed DNS may fail. If a build needs the
local cache, rerun the Nix command with escalated network access.

Preferred flags:

```sh
--option substituters "https://cache.box.headpats.uk" \
--option extra-substituters "https://nix-community.cachix.org https://cache.nixos-cuda.org https://cache.numtide.com" \
--option trusted-public-keys "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" \
--option extra-trusted-public-keys "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M= cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
```
