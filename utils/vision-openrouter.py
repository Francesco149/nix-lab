#!/usr/bin/env python3
"""vision-openrouter — send one image/video to OpenRouter's qwen3.5-9b.

Used by the `vision` wrapper (wslop side). stdin = base64 of the media file,
ext in /tmp/vision-ext, prompt in argv or /tmp/vision-prompt.
API key: OPENROUTER_API_KEY env (the wrapper sources ~/.omp/agent/.env).

Exit 0 = answer printed. Non-zero = OpenRouter failed (bad key, credit,
timeout, 4xx/5xx) — caller falls back to the local lame model.
"""
import base64, json, os, sys, urllib.request, urllib.error

MODEL = os.environ.get("VISION_OR_MODEL", "qwen/qwen3.7-flash")
URL = "https://openrouter.ai/api/v1/chat/completions"
TIMEOUT = 180

key = os.environ.get("OPENROUTER_API_KEY", "").strip()
if not key:
    print("vision-openrouter: OPENROUTER_API_KEY not set", file=sys.stderr)
    sys.exit(1)

b64 = sys.stdin.read().strip()
if not b64:
    print("vision-openrouter: empty media on stdin", file=sys.stderr)
    sys.exit(1)
try:
    with open("/tmp/vision-ext") as f:
        ext = f.read().strip()
except OSError:
    ext = "png"

mime = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "webp": "image/webp", "gif": "image/gif",
        "mp4": "video/mp4", "webm": "video/webm"}.get(ext, "image/png")

if mime.startswith("video"):
    # OpenAI-style video block; OpenRouter qwen3.5 accepts video data URLs.
    media_block = {"type": "video_url", "video_url": {"url": f"data:{mime};base64,{b64}"}}
else:
    media_block = {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}}

try:
    with open("/tmp/vision-prompt") as f:
        prompt = f.read().strip()
except OSError:
    prompt = "Describe this image in detail."

payload = {
    "model": MODEL,
    "messages": [{"role": "user", "content": [media_block, {"type": "text", "text": prompt}]}],
    "max_tokens": 1200,
    "temperature": 0.2,
    "reasoning": {"effort": "none"},  # direct answers for tool-style use
    "stream": False,
}

req = urllib.request.Request(
    URL,
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json",
             "Authorization": f"Bearer {key}",
             "HTTP-Referer": "https://github.com/Francesco149/nix-lab",
             "X-Title": "nix-lab vision"},
)
try:
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        resp = json.loads(r.read())
except urllib.error.HTTPError as e:
    body = e.read()[:400].decode("utf-8", "replace")
    print(f"vision-openrouter: HTTP {e.code}: {body}", file=sys.stderr)
    sys.exit(2)
except Exception as e:  # noqa: BLE001 — timeout/network = fallback trigger
    print(f"vision-openrouter: {e}", file=sys.stderr)
    sys.exit(2)

msg = resp["choices"][0]["message"]
out = (msg.get("content") or "").strip()
if not out and msg.get("reasoning_content"):
    out = msg["reasoning_content"].strip()
if not out:
    print("vision-openrouter: empty response", file=sys.stderr)
    sys.exit(2)
print(out)
