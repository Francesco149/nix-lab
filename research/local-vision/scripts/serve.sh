#!/usr/bin/env bash
# Manage a llama-server instance for one eval model (run ON lame).
# Uses the prebuilt Vulkan llama.cpp (native video, MTP build 6e9007a).
#
#   serve.sh start <model-id> [port]   # starts (idempotent; reuse running)
#   serve.sh stop  [port]
#   serve.sh status [port]
#
# Model config comes from models.yaml next to this script (python parse).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${3:-8095}"
BIN=/opt/ai-lab/scratch/llama-mtp-bin
ICD=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json
PIDFILE="/tmp/vision-eval-$PORT.pid"
LOGFILE="/opt/ai-lab/scratch/vision-eval-$PORT.log"

case "${1:-}" in
  stop)
    if [ -f "$PIDFILE" ]; then
      kill "$(cat "$PIDFILE")" 2>/dev/null || true
      # wait for the port to free
      for _ in $(seq 1 20); do
        ! kill -0 "$(cat "$PIDFILE")" 2>/dev/null && break
        sleep 0.5
      done
      rm -f "$PIDFILE"
    fi
    echo "stopped $PORT"; exit 0 ;;
  status)
    curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && echo "up" || echo "down"; exit 0 ;;
  start) ;;
  *) echo "usage: serve.sh <start|stop|status> <model-id> [port]"; exit 2 ;;
esac

MODEL_ID="${2:?model-id}"
# running already?
if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  ALIAS="$(curl -sf "http://127.0.0.1:$PORT/v1/models" | tr -d '\n' | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
  if [ "$ALIAS" = "$MODEL_ID" ]; then
    echo "already running $MODEL_ID on $PORT"; exit 0
  fi
  "$0" stop "$MODEL_ID" "$PORT"
fi

# resolve model config
CFG="$("$HERE"/../scripts/model-cfg.py "$MODEL_ID")"
eval "$CFG"   # sets GGUF, MMPROJ, FAMILY, LABEL

VRAM_CEIL=$((15 * 1024 * 1024 * 1024))
# wait for the 7800XT to drain (a crashed server leaves VRAM allocated)
for _ in $(seq 1 90); do
  used=$(cat /sys/class/drm/card0/device/mem_info_vram_used 2>/dev/null || echo 0)
  [ "$used" -lt $((2 * 1024 * 1024 * 1024)) ] && break
  sleep 1
done
if [ "$used" -gt "$VRAM_CEIL" ]; then
  echo "ERROR: 7800XT busy (${used} bytes used); free it first" >&2; exit 3
fi

export LD_LIBRARY_PATH="$BIN:${LD_LIBRARY_PATH:-}"
export VK_ICD_FILENAMES="$ICD"
# llama.cpp video helper shells out to ffmpeg/ffprobe — keep them on PATH
# even when the launching nix-shell has exited.
FFBIN="$(dirname "$(ls /nix/store/*-ffmpeg-8.1*/bin/ffprobe 2>/dev/null | head -1)")"
[ -n "$FFBIN" ] && export PATH="$FFBIN:$PATH"
command -v ffprobe >/dev/null || echo "WARN: ffprobe not found; video will fail"

python3 "$HERE/sigpipe-wrapper.py" \
  "$BIN/llama-server" \
  --host 127.0.0.1 --port "$PORT" \
  -c 32768 -ngl 99 --n-cpu-moe 0 \
  --kv-unified --flash-attn on \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --parallel 1 --jinja \
  --temp 0.2 --top-p 0.9 --top-k 40 \
  --alias "$MODEL_ID" \
  -m "$GGUF" --mmproj "$MMPROJ" \
  > "$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"

# wait for health
for _ in $(seq 1 240); do
  curl -sf "http://127.0.0.1:$PORT/health" >/dev/null 2>&1 && { echo "up: $MODEL_ID on $PORT"; exit 0; }
  kill -0 "$(cat "$PIDFILE")" 2>/dev/null || { echo "SERVER DIED:"; tail -30 "$LOGFILE"; exit 1; }
  sleep 1
done
echo "timeout waiting for $MODEL_ID"; tail -30 "$LOGFILE"; exit 1
