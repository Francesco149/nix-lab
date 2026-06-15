#!/usr/bin/env bash
# Text throughput (pp512 prompt / tg128 generation) via llama-bench, sweeping
# MoE CPU-offload (-ncmoe) or GPU layers (-ngl). Run ON the inference host.
# Forces the AMD Vulkan ICD (7800XT) for the vulkan backend; cuda uses the 3080.
#
#   Usage: bench.sh <vulkan|cuda> <model.gguf> [extra llama-bench args...]
#   e.g.   bench.sh vulkan model.gguf -ngl 99 -ncmoe 33,26,20,14
#          bench.sh cuda  model.gguf -ngl 99 -ncmoe 33      # 3080 has 10G
#
# Tip: order -ncmoe from most-offload to least so the configs that fit run
# before any OOM (on a tight card a load OOM can abort the rest of the sweep).
set -euo pipefail
BACKEND="${1:?vulkan|cuda}"; MODEL="${2:?model.gguf}"; shift 2
BIN="/tmp/llama.cpp/build-$BACKEND/bin"
INNER="$(mktemp)"
{
  echo 'set -uo pipefail'
  echo "export LD_LIBRARY_PATH=$BIN:\${LD_LIBRARY_PATH:-}"
  [ "$BACKEND" = vulkan ] && echo "export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json"
  echo "$BIN/llama-bench -m $MODEL -p 512 -n 128 -r 2 -o md $*"
} > "$INNER"
nix-shell -p vulkan-loader mesa --run "bash $INNER"
rm -f "$INNER"
