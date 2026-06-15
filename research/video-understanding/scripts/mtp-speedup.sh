#!/usr/bin/env bash
# Measure the MTP (multi-token-prediction) speculative-decoding speedup of an MTP
# GGUF: same prompt, greedy (deterministic) -> baseline and --spec-type draft-mtp
# produce IDENTICAL output, so the only difference is speed. Speculative decoding
# is exact. Relevant to agentic coding: predictable/code text accepts more drafts.
#
# Needs llama-cli, which links server-context -> build it with build-llama.sh
# (that configures LLAMA_BUILD_SERVER=ON but only builds the cli, no web UI).
# The new cli prints timing as `[ Prompt: N t/s | Generation: N t/s ]`; it needs
# `-st` (single-turn) to run non-interactively and exit.
#
#   Usage: mtp-speedup.sh <mtp-model.gguf> [vulkan|cuda] [n_predict=256]
#   Env:   PROMPTFILE (defaults to a coding prompt)
set -euo pipefail
MODEL="${1:?mtp-model.gguf}"; BACKEND="${2:-vulkan}"; N="${3:-256}"
BIN="/tmp/llama.cpp/build-$BACKEND/bin"
PF="${PROMPTFILE:-/tmp/mtp-prompt.txt}"
[ -f "$PF" ] || printf '%s\n' "Write a complete, well-documented Python implementation of a binary search tree (insert, delete, search, in-order traversal) with docstrings and a usage example." > "$PF"

INNER="$(mktemp)"
{
  echo 'set -uo pipefail'
  echo "export LD_LIBRARY_PATH=$BIN:\${LD_LIBRARY_PATH:-}"
  [ "$BACKEND" = vulkan ] && echo "export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json"
  [ "$BACKEND" = cuda ]   && echo "export LD_LIBRARY_PATH=/run/opengl-driver/lib:\$LD_LIBRARY_PATH"
  echo "echo '=== baseline (no spec, greedy) ==='"
  echo "$BIN/llama-cli -m $MODEL -ngl 99 -c 4096 -n $N -st --simple-io --temp 0 -f $PF 2>&1 | grep -aiE 'Prompt:|Generation:'"
  echo "echo '=== --spec-type draft-mtp (greedy) ==='"
  echo "$BIN/llama-cli -m $MODEL -ngl 99 -c 4096 -n $N -st --simple-io --temp 0 --spec-type draft-mtp -f $PF 2>&1 | grep -aiE 'Prompt:|Generation:|accept|draft'"
} > "$INNER"
nix-shell -p vulkan-loader mesa --run "bash $INNER"
rm -f "$INNER"
echo MTP_SPEEDUP_DONE
