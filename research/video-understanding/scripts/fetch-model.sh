#!/usr/bin/env bash
# Download GGUF(s) from a Hugging Face repo with aria2 (resumable, multi-conn).
# Run ON the inference host (writes into the model store). Note: aria2
# preallocates each file to its full size up front, so on-disk size is NOT a
# completion signal — completion is the .aria2 control file disappearing.
#
#   Usage: fetch-model.sh <hf-repo> <dest-dir> <file> [file...]
#   e.g.   fetch-model.sh mudler/Qwen3.6-35B-A3B-APEX-MTP-GGUF \
#            /opt/ai-lab/models/mudler/Qwen3.6-35B-A3B-APEX-MTP-GGUF \
#            Qwen3.6-35B-A3B-APEX-MTP-I-Nano.gguf Qwen3.6-35B-A3B-APEX-MTP-I-Mini.gguf
set -euo pipefail
REPO="${1:?hf-repo}"; DEST="${2:?dest-dir}"; shift 2
mkdir -p "$DEST"; cd "$DEST"
for f in "$@"; do
  echo "=== $f ==="
  nix-shell -p aria2 --run "aria2c -x8 -s8 -c --console-log-level=warn -o '$f' 'https://huggingface.co/$REPO/resolve/main/$f'"
done
