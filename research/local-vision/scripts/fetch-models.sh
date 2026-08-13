#!/usr/bin/env bash
# Fetch the vision-eval GGUF set into /opt/ai-lab/models (run ON lame).
# Resumable via aria2 (.aria2 control files). Safe to re-run.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS=/opt/ai-lab/models

fetch() { # repo destfile... (dest = /opt/ai-lab/models/<repo>)
  local repo="$1"; shift
  local dest="$MODELS/$repo"
  mkdir -p "$dest"; cd "$dest"
  for f in "$@"; do
    [ -f "$f" ] && [ ! -f "$f.aria2" ] && { echo "skip  $f"; continue; }
    echo "=== $f ==="
    nix-shell -p aria2 --run "aria2c -x8 -s8 -c --retry-wait=5 --max-tries=5 --console-log-level=warn -o '$f' 'https://huggingface.co/$repo/resolve/main/$f'" \
      || echo "WARN: $f failed (will be retried on next run)"
  done
}

fetch unsloth/Qwen3.5-9B-GGUF Qwen3.5-9B-Q4_K_M.gguf mmproj-F16.gguf
fetch Qwen/Qwen3-VL-8B-Instruct-GGUF Qwen3VL-8B-Instruct-Q4_K_M.gguf mmproj-Qwen3VL-8B-Instruct-Q8_0.gguf
fetch ggml-org/DeepSeek-OCR-GGUF DeepSeek-OCR-Q8_0.gguf mmproj-DeepSeek-OCR-Q8_0.gguf
echo ALL-DOWNLOADS-DONE
