#!/usr/bin/env python3
"""vision-cli — send one image/video to the lame vision server and print the answer.

Used by the `vision` wrapper on wslop (stdin = base64 of the media file).
Server: http://127.0.0.1:8080 (gpu-switch vision preset).
"""
import base64, json, sys, urllib.request

PORT = 8080
b64 = sys.stdin.read().strip()
prompt = sys.argv[1] if len(sys.argv) > 1 else "Describe this image in detail."

try:
    with open("/tmp/vision-ext", "r") as f:
        ext = f.read().strip()
except OSError:
    ext = "png"

mime = {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "webp": "image/webp", "gif": "image/gif",
        "mp4": "video/mp4", "webm": "video/webm"}.get(ext, "image/png")

kind = "input_video" if mime.startswith("video") else "image_url"
if kind == "input_video":
    media_block = {"type": "input_video", "input_video": {"data": b64}}
else:
    media_block = {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}}

payload = {
    "model": "vision",
    "messages": [{"role": "user", "content": [
        media_block,
        {"type": "text", "text": prompt},
    ]}],
    "max_tokens": 1200,
    "temperature": 0.2,
    "stream": False,
    "chat_template_kwargs": {"enable_thinking": False},
}

req = urllib.request.Request(
    f"http://127.0.0.1:{PORT}/v1/chat/completions",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=600) as r:
        resp = json.loads(r.read())
except urllib.error.HTTPError as e:
    print(f"vision-cli: HTTP {e.code}: {e.read()[:300]}", file=sys.stderr)
    sys.exit(1)
msg = resp["choices"][0]["message"]
out = (msg.get("content") or "").strip()
if not out and msg.get("reasoning_content"):
    out = msg["reasoning_content"].strip()
print(out)
