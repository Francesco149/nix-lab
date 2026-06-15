#!/usr/bin/env bash
# Describe a video with a vision LLM via llama.cpp's native video path
# (llama-mtmd-cli --video). Run ON the inference host. Forces the AMD Vulkan ICD
# (7800XT) for the vulkan backend and wraps the binary in the SIGPIPE shim;
# ffmpeg/ffprobe come from nix-shell.
#
#   Usage: video-describe.sh <model.gguf> <mmproj.gguf> <video> [vulkan|cuda]
#   Env knobs: PROMPT, NPREDICT(300), CTX(24576), IMAGE_MAX_TOKENS(256),
#              NGL(99), NCMOE(unset -> no MoE offload)
#
# IMAGE_MAX_TOKENS caps tokens per frame: at full res a clip costs ~1.3k
# tokens/sec-of-video, so long videos need this (and/or a lower fps) to fit ctx.
set -euo pipefail
MODEL="${1:?model.gguf}"; MMPROJ="${2:?mmproj.gguf}"; VIDEO="${3:?video}"; BACKEND="${4:-vulkan}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="/tmp/llama.cpp/build-$BACKEND/bin"
PROMPT="${PROMPT:-Describe this video in detail. What is shown, and what happens over time from beginning to end?}"

INNER="$(mktemp)"
{
  echo 'set -uo pipefail'
  echo "export LD_LIBRARY_PATH=$BIN:\${LD_LIBRARY_PATH:-}"
  [ "$BACKEND" = vulkan ] && echo "export VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json"
  echo "python3 $HERE/sigpipe-wrapper.py $BIN/llama-mtmd-cli \\"
  echo "  -m $MODEL --mmproj $MMPROJ --video $VIDEO \\"
  echo "  --image-max-tokens ${IMAGE_MAX_TOKENS:-256} -c ${CTX:-24576} -n ${NPREDICT:-300} \\"
  echo "  -ngl ${NGL:-99} ${NCMOE:+--n-cpu-moe $NCMOE} --temp 0.7 --top-p 0.95 -p \"\$PROMPT\""
} > "$INNER"
PROMPT="$PROMPT" nix-shell -p ffmpeg vulkan-loader mesa python3 --run "PROMPT=\"$PROMPT\" bash $INNER"
rm -f "$INNER"
