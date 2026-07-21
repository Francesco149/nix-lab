#!/usr/bin/env bash
# lab-check.sh — verbose post-deploy / anytime health check for the nix-lab.
#
# It SSHes to each host as root and runs a battery of checks. Design goals:
#   * VERBOSE: every remote command and its raw output is printed, so you can
#     eyeball a weird/silent failure that the scripted pass/fail logic misses.
#   * HONEST: ssh/command exit codes are checked explicitly; an unreachable host
#     or an errored command is a FAIL, never a silent pass.
#   * SUMMARY: a PASS/WARN/FAIL tally prints at the end. WARN/FAIL lines are
#     repeated there so they don't scroll away.
#
# It is a *sanity* check, not a guarantee — read the verbose output too.
#
# Requirements: run from a host with root ssh access to the lab (wslop, which is
# the deploy/build box, or your workstation) and with `nix` on PATH. Host
# addresses are read from lib/lab.nix so this never drifts from the inventory.
#
# Usage:
#   ./utils/lab-check.sh                 # all hosts
#   ./utils/lab-check.sh relay cold      # only the named hosts
#
# Exit status: number of FAILs (0 = all good), capped at 125.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SSH=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)

# Run a command on a host under bash via stdin (avoids quoting issues and the
# fish login shells on code/lame). Use sudo instead of an SSH hairpin when the
# runner is wslop itself. Returns the command's exit status.
rcmd() {
  if [ "$1" = local ]; then
    if [ "$EUID" -eq 0 ]; then
      bash -s <<<"$2"
    else
      sudo -n bash -s <<<"$2"
    fi
  else
    "${SSH[@]}" "root@$1" 'bash -s' <<<"$2"
  fi
}

# Resolve a value from lab.nix (single source of truth for addresses).
labval() { nix eval --raw --impure --expr "(import $REPO/lib/lab.nix).$1" 2>/dev/null; }

# Same, for numeric values. `--raw` refuses to coerce an integer, so a port read
# through labval silently comes back EMPTY and builds a nonsense URL — which is
# how this helper came to exist.
labnum() { nix eval --raw --impure --expr "toString (import $REPO/lib/lab.nix).$1" 2>/dev/null; }

# openssl for the runner (cert checks). Fall back to a throwaway nix shell.
if command -v openssl >/dev/null 2>&1; then OPENSSL=(openssl); else OPENSSL=(nix run nixpkgs#openssl --); fi

echo "resolving host addresses from lib/lab.nix ..."
if [ "$(hostname)" = wslop ]; then
  WSLOP_ENDPOINT=local
else
  WSLOP_ENDPOINT="$(labval tailnet.wslop)"
fi
declare -A ADDR=(
  [code]="$(labval lan.code)"
  [mail]="$(labval lan.mail)"
  [cold]="$(labval lan.cold)"
  [lame]="$(labval lan.lame)"
  [relay]="$(labval internet.relay)"
  [wslop]="$WSLOP_ENDPOINT"
)
for h in code mail cold lame relay wslop; do
  [ -n "${ADDR[$h]:-}" ] || { echo "FATAL: could not resolve $h address from lab.nix"; exit 125; }
  printf '  %-6s %s\n' "$h" "${ADDR[$h]}"
done

if [ "$#" -gt 0 ]; then HOSTS=("$@"); else HOSTS=(code mail cold lame relay wslop); fi

# ── result tracking ────────────────────────────────────────────────────────
declare -a SUMMARY=()
pass=0 warn=0 fail=0
record() { # <PASS|WARN|FAIL> <label> [detail]
  local lvl="$1" label="$2" detail="${3:-}"
  SUMMARY+=("$lvl|$label|$detail")
  case "$lvl" in
    PASS) pass=$((pass + 1)) ;;
    WARN) warn=$((warn + 1)) ;;
    FAIL) fail=$((fail + 1)) ;;
  esac
  printf '    => [%s] %s%s\n' "$lvl" "$label" "${detail:+ — $detail}"
}

# check <host> <label> <remote-cmd> <expected-substring>
# Prints the raw output; PASS if rc==0 and output contains the substring,
# FAIL if the command/ssh errored, WARN if it ran but output was unexpected.
check() {
  local host="$1" label="$2" cmd="$3" want="$4" out rc
  echo "+ ${host}: ${label}"
  echo "  \$ ${cmd}"
  out="$(rcmd "${ADDR[$host]}" "$cmd" 2>&1)"
  rc=$?
  printf '%s\n' "$out" | sed 's/^/  | /'
  if [ $rc -ne 0 ]; then
    record FAIL "${host}/${label}" "exit ${rc} (unreachable or command errored)"
  elif [ -z "$want" ] || printf '%s' "$out" | grep -qiF -- "$want"; then
    record PASS "${host}/${label}"
  else
    record WARN "${host}/${label}" "output did not contain '${want}'"
  fi
}

section() { printf '\n============================================================\n%s\n============================================================\n' "$1"; }

# ── common checks (every host) ──────────────────────────────────────────────
common_checks() {
  local h="$1"
  check "$h" "reachable"          'echo ok'                                              'ok'
  check "$h" "system running"     'systemctl is-system-running || true'                  'running'
  check "$h" "no failed units"    'systemctl --failed --no-legend --plain | sed "s/.*/FAILED: &/"; systemctl --failed --quiet --no-legend --plain | grep -q . && echo HAS_FAILED || echo none' 'none'
  check "$h" "generation"         'readlink /run/current-system'                         '/nix/store/'
  check "$h" "root disk headroom" 'read -r avail used <<<"$(df -B1 --output=avail,pcent / | tail -1)"; used=${used%\%}; if [ "${avail:-0}" -ge 5368709120 ] && [ "${used:-100}" -lt 90 ]; then echo "ok ${avail}B-free ${used}%used"; else echo "LOW ${avail:-0}B-free ${used:-100}%used"; exit 1; fi' 'ok'
}

for h in "${HOSTS[@]}"; do
  case " code mail cold lame relay wslop " in *" $h "*) : ;; *) echo "unknown host: $h" >&2; continue ;; esac
  section "HOST: $h (${ADDR[$h]})"
  common_checks "$h"

  case "$h" in
    code)
      check code "core services" 'systemctl is-active caddy docker beszel-agent sshd | paste -sd," "'        'active'
      check code "nightly timer" 'systemctl is-active cold-backup.timer'                                     'active'
      check code "tm-backup timer" 'systemctl is-active tm-backup.timer'                                     'active'
      check code "app services"  'systemctl is-active shigebot grammar-helper | paste -sd," "'               'active'
      ;;
    mail)
      check mail "mail services" 'systemctl is-active postfix dovecot rspamd sshd | paste -sd," "'           'active'
      check mail "mail certs"    'ls /var/lib/acme/ | grep -E "headpats" | paste -sd," "'                    'headpats'
      ;;
    relay)
      check relay "relay services" 'systemctl is-active headscale nginx tailscaled sshd | paste -sd," "'     'active'
      check relay "headscale http" 'curl -fsS -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/health'  '200'
      # cert expiry is checked from HERE (relay lacks the openssl cli)
      echo "+ relay: hs cert expiry (checked from runner)"
      cert_end="$(echo | "${OPENSSL[@]}" s_client -connect "${ADDR[relay]}:443" -servername "$(labval domains.headscale)" 2>/dev/null | "${OPENSSL[@]}" x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
      echo "  | notAfter=${cert_end:-<none>}"
      if [ -z "$cert_end" ]; then
        record FAIL "relay/hs cert" "could not read served cert"
      elif end_epoch=$(date -d "$cert_end" +%s 2>/dev/null) && [ "$end_epoch" -gt "$(( $(date +%s) + 7*86400 ))" ]; then
        record PASS "relay/hs cert" "valid until $cert_end"
      else
        record FAIL "relay/hs cert" "expires/expired $cert_end (<7d or unparseable)"
      fi
      ;;
    cold)
      check cold "zfs pools online" 'zpool list -H -o name,health | sed "s/\t/ /" ; zpool list -H -o health | grep -qv ONLINE && echo NOT_ALL_ONLINE || echo all-online' 'all-online'
      check cold "backup dataset"   'zfs list -H -o name gigavault/wslop-backup'                              'wslop-backup'
      check cold "recent snapshot"  'zfs list -H -t snapshot -o name -s creation gigavault/wslop-backup | tail -1' '@wslop-'
      check cold "tm restic repo"   'zfs list -H -o name gigavault/timemachine-restic'                        'timemachine-restic'
      check cold "stay (kept up)"   'test -f /tmp/stay && echo present || echo absent'                        'present'

      # Desktop + torrent stack (hosts/cold/{desktop,torrents}.nix).
      #
      # Order matters here. The inbox lives on gigavault, which is zfs-encrypted,
      # so until cold-unlock loads the key the dataset is unmounted and
      # qbittorrent is CORRECTLY inactive — its ConditionPathIsMountPoint skips
      # it rather than letting it write the profile onto the rootfs. Checking the
      # mount first means an inactive client reads as "pool still locked" instead
      # of "service broken".
      QBT_PORT="$(labnum ports.qbittorrent)"
      check cold "torrent dataset"  'zfs list -H -o name gigavault/torrents'                                  'torrents'
      check cold "torrent inbox mounted" 'mountpoint -q /gigavault/torrents && echo mounted || echo UNMOUNTED' 'mounted'
      check cold "qbittorrent"      'systemctl is-active qbittorrent'                                         'active'
      check cold "qbittorrent web"  "curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:$QBT_PORT/ || echo FAILED" '200'
      # The Plasma session is what Sunshine attaches to: sunshine's user unit is
      # partOf graphical-session.target, so no autologin session => no stream,
      # even though the host is otherwise perfectly healthy.
      check cold "plasma session"   'systemctl is-active display-manager'                                     'active'
      check cold "sunshine"         'pgrep -x sunshine >/dev/null && echo running || echo NOT_RUNNING'        'running'
      ;;
    lame)
      check lame "gpu (nvidia)"     'nvidia-smi --query-gpu=name,driver_version --format=csv,noheader'        'NVIDIA'
      # llama-vulkan/llama-embed are intentionally DISABLED on lame (7800XT freed for
      # haruness harness dev — see hosts/lame/llama.nix + WORKDOC.md). Check the durable
      # interactive-GPU-sandbox prereqs instead: the uinput module + the nvidia-container-
      # toolkit CDI spec (host GPU shared into containers for Sunshine/Moonlight).
      check lame "sandbox prereqs"  'lsmod | grep -q uinput && test -e /run/cdi/nvidia-container-toolkit.json && echo ok || echo MISSING'  'ok'
      # Docker's data-root lives on the lamedata ZFS pool, NOT the 98G LUKS root — a
      # haruness sweep once filled root to 100% (hosts/lame/lame.nix + disko.nix). If this
      # ever reads /var/lib/docker again the move regressed and root will refill.
      check lame "docker on zfs"    'docker info -f "{{.DockerRootDir}}" 2>/dev/null'                          '/lamedata/docker'
      check lame "stay (kept up)"   'test -f /tmp/stay && echo present || echo absent'                        'present'
      ;;
    wslop)
      check wslop "wsl guest"       'systemd-detect-virt'                                                    'wsl'
      check wslop "sshd"            'systemctl is-active sshd'                                              'active'
      check wslop "beszel masked"   'systemctl is-enabled beszel-agent 2>&1 || true'                         'masked'
      ;;
  esac
done

# ── summary ─────────────────────────────────────────────────────────────────
section "SUMMARY"
for r in "${SUMMARY[@]}"; do
  IFS='|' read -r lvl label detail <<<"$r"
  [ "$lvl" = PASS ] && continue
  printf '  [%s] %s%s\n' "$lvl" "$label" "${detail:+ — $detail}"
done
[ $((warn + fail)) -eq 0 ] && echo "  (no warnings or failures)"
printf '\n  PASS=%d  WARN=%d  FAIL=%d\n' "$pass" "$warn" "$fail"
echo
echo "  NOTE: this is a sanity check, not proof. Scroll the verbose output above"
echo "  for anything odd — a check can pass while something next to it failed."
[ $fail -eq 0 ] && echo "  VERDICT: OK" || echo "  VERDICT: FAILURES PRESENT — investigate the FAIL lines."

exit $(( fail > 125 ? 125 : fail ))
