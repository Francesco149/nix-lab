#!/usr/bin/env python3
"""vision-bench — compare cheap OpenRouter vision models on the same media.

Measures REAL cost: each provider tokenizes images/videos differently, so
price-per-M alone is misleading. Sends the same test set (images + a short
video) to every model, reads usage from the response, prints a table with
prompt/completion tokens, wall time, and cost per request.

Usage: vision-bench.py [--models a,b,c] [--images d1,d2] [--video v] [--prompt P]
       (run with OPENROUTER_API_KEY in the environment)
"""
import argparse, base64, json, mimetypes, os, sys, time
import urllib.request, urllib.error

MODELS = [
    ("qwen/qwen3.5-9b", 0.10, 0.15),                     # baseline (current default)
    ("qwen/qwen3.7-flash", 0.03, 0.13),
    ("qwen/qwen3.5-flash-02-23", 0.07, 0.26),
    ("google/gemini-2.5-flash-lite:batch", 0.05, 0.20),  # user's candidate
    ("google/gemini-2.5-flash-lite", 0.10, 0.40),        # non-batch twin
    ("bytedance-seed/seed-1.6-flash", 0.07, 0.30),
    ("google/gemini-3.1-flash-lite:batch", 0.12, 0.75),
]

PROMPT = ("You are looking at a screenshot of a Game Boy game. Describe the "
          "screen in detail: what is shown, any UI/HUD elements, any text "
          "(quote it verbatim).")

key = os.environ.get("OPENROUTER_API_KEY", "")
if not key:
    print("OPENROUTER_API_KEY not set", file=sys.stderr)
    sys.exit(1)


def data_url(path):
    mime = mimetypes.guess_type(path)[0] or "image/png"
    return f"data:{mime};base64," + base64.b64encode(open(path, "rb").read()).decode()


def call(model, content, max_tokens=300):
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "max_tokens": max_tokens, "temperature": 0.2, "stream": False,
        "reasoning": {"effort": "none"},
    }
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    )
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=180) as r:
        resp = json.loads(r.read())
    dt = time.time() - t0
    msg = resp["choices"][0]["message"]
    out = (msg.get("content") or "").strip()
    u = resp.get("usage", {})
    return dt, u.get("prompt_tokens", 0), u.get("completion_tokens", 0), out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="")
    ap.add_argument("--images", nargs="+", default=[
        "/opt/src/nix-lab/research/local-vision/assets/game/kirby-3.png",
        "/opt/src/nix-lab/research/local-vision/assets/text/dense.png",
        "/opt/src/nix-lab/research/local-vision/assets/text/code.png",
        "/opt/src/nix-lab/research/local-vision/assets/ui/webapp.png",
    ])
    ap.add_argument("--video", default="/opt/src/nix-lab/research/local-vision/assets/clips/kirby-pan.mp4")
    ap.add_argument("--prompt", default=PROMPT)
    ap.add_argument("--max-tokens", type=int, default=300)
    ap.add_argument("--show-outputs", action="store_true")
    args = ap.parse_args()

    models = [m for m in MODELS if not args.models or m[0] in args.models.split(",")]
    items = [(os.path.basename(p), data_url(p)) for p in args.images]
    if args.video and os.path.exists(args.video):
        items.append((os.path.basename(args.video), data_url(args.video)))

    rows = []
    for mid, pin, cout in models:
        for name, url in items:
            is_video = url.startswith("data:video")
            block = ({"type": "video_url", "video_url": {"url": url}}
                     if is_video else {"type": "image_url", "image_url": {"url": url}})
            try:
                dt, pt, ct, out = call(mid, [block, {"type": "text", "text": args.prompt}], args.max_tokens)
                cost = (pt * pin + ct * cout) / 1e6
                rows.append((mid, name, pt, ct, round(dt, 1), round(cost, 4), out[:120].replace("\n", " ")))
                print(f"{mid:45s} {name:24s} pp={pt:6d} tg={ct:4d} {dt:5.1f}s ${cost:.4f}")
            except urllib.error.HTTPError as e:
                rows.append((mid, name, -1, -1, 0, 0, f"HTTP {e.code}"))
                print(f"{mid:45s} {name:24s} FAILED HTTP {e.code}: {e.read()[:150]}")
            except Exception as e:  # noqa: BLE001
                rows.append((mid, name, -1, -1, 0, 0, str(e)))
                print(f"{mid:45s} {name:24s} FAILED {e}")

    print("\n--- cost per item ($) ---")
    mids = list(dict.fromkeys(r[0] for r in rows))
    itms = list(dict.fromkeys(r[1] for r in rows))
    for m in mids:
        line = f"{m:45s}"
        for it in itms:
            r = next((x for x in rows if x[0] == m and x[1] == it), None)
            line += f"  {r[5]:.4f}" if r and r[3] >= 0 else "    FAIL"
        print(line)

    if args.show_outputs:
        print("\n--- outputs (first 400 chars) ---")
        for mid, name, pt, ct, dt, cost, out in rows:
            if out and not out.startswith("HTTP"):
                print(f"\n### {mid} / {name}\n{out[:400]}")


if __name__ == "__main__":
    main()
