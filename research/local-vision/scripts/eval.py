#!/usr/bin/env python3
"""Vision-model eval loop for local llama.cpp servers (run ON lame).

Usage:
  python3 eval.py [--models id1,id2] [--cases a,b] [--run NAME] [--smoke]

For each model: start llama-server (serve.sh), then run every test case
(image or video) via the OpenAI-compatible API. Videos go through llama.cpp's
native `input_video` path for Qwen-VL-lineage models; other families get
ffmpeg-extracted frames as image batches.

Writes results/run-<NAME>/results.json + report.html. Stdlib + pyyaml only.
"""
import argparse, base64, json, mimetypes, os, shutil, subprocess, sys, time
import urllib.request, urllib.error
import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PORT = 8095
BASE = f"http://127.0.0.1:{PORT}/v1"

NATIVE_VIDEO_FAMILIES = {"qwen25vl", "qwen3vl", "qwen35", "qwen36"}
FRAME_FPS = 1.5
MAX_FRAMES = 12


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def load_manifest():
    cfg = yaml.safe_load(open(os.path.join(ROOT, "models.yaml")))
    cases = yaml.safe_load(open(os.path.join(ROOT, "testcases.yaml")))
    return cfg["models"], cases["cases"]


def http_json(url, payload, timeout=900):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def data_url(path):
    mime = mimetypes.guess_type(path)[0] or "image/png"
    with open(path, "rb") as f:
        return f"data:{mime};base64," + base64.b64encode(f.read()).decode()


def extract_frames(video, workdir):
    """ffmpeg → jpg frames; returns list of paths."""
    os.makedirs(workdir, exist_ok=True)
    pat = os.path.join(workdir, "fr-%02d.jpg")
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-i", video, "-vf",
         f"fps={FRAME_FPS},scale=512:-1", pat],
        check=True,
    )
    frames = sorted(f for f in os.listdir(workdir) if f.endswith(".jpg"))
    return [os.path.join(workdir, f) for f in frames[:MAX_FRAMES]]


def build_content(case, model, workdir):
    path = os.path.join(ROOT, case["path"])
    if case["kind"] == "image":
        return [{"type": "image_url", "image_url": {"url": data_url(path)}},
                {"type": "text", "text": case["prompt"]}]
    # video
    if model["video"] == "native":
        b64 = base64.b64encode(open(path, "rb").read()).decode()
        return [{"type": "input_video", "input_video": {"data": b64}},
                {"type": "text", "text": case["prompt"]}]
    frames = extract_frames(path, workdir)
    if not frames:
        raise RuntimeError(f"no frames extracted from {path}")
    content = [{"type": "image_url", "image_url": {"url": data_url(f)}} for f in frames]
    content.append({"type": "text", "text": case["prompt"] + "\n(These are frames sampled from a video, in order.)"})
    return content


def run_case(model, case, workdir):
    content = build_content(case, model, workdir)
    payload = {
        "model": model["id"],
        "messages": [{"role": "user", "content": content}],
        "max_tokens": 900,
        "temperature": 0.2,
        "top_p": 0.9,
        "stream": False,
    }
    # Direct answers for eval: disable thinking channels where the template
    # supports it (gemma-4, qwen3.5/3.6, qwen3-vl). OCR ignores kwargs.
    if model.get("family") != "ocr":
        payload["chat_template_kwargs"] = {"enable_thinking": False}
    t0 = time.time()
    resp = http_json(f"{BASE}/chat/completions", payload)
    dt = time.time() - t0
    msg = resp["choices"][0]["message"]
    text = msg.get("content") or ""
    usage = resp.get("usage", {})
    return {
        "model": model["id"],
        "case": case["id"],
        "kind": case["kind"],
        "output": text,
        "elapsed_s": round(dt, 1),
        "prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": usage.get("completion_tokens"),
        "error": None,
    }


def vram_used():
    try:
        return int(open("/sys/class/drm/card0/device/mem_info_vram_used").read())
    except OSError:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="")
    ap.add_argument("--cases", default="")
    ap.add_argument("--run", default=time.strftime("%Y%m%d-%H%M%S"))
    ap.add_argument("--smoke", action="store_true", help="1 model × 1 image + 1 video")
    args = ap.parse_args()

    models, cases = load_manifest()
    if args.smoke:
        models = [m for m in models if m["id"] == "gemma4-12b-q4km"]
        cases = [c for c in cases if c["id"] in ("game-maze", "video-game")]
    if args.models:
        want = set(args.models.split(","))
        models = [m for m in models if m["id"] in want]
    if args.cases:
        want = set(args.cases.split(","))
        cases = [c for c in cases if c["id"] in want]

    outdir = os.path.join(ROOT, "results", f"run-{args.run}")
    os.makedirs(outdir, exist_ok=True)
    results = []

    ready = []
    for m in models:
        if not os.path.exists(m["gguf"]) or not os.path.exists(m["mmproj"]):
            log(f"SKIP {m['id']}: files missing (downloading?)")
            continue
        ready.append(m)
    models = ready

    for mi, model in enumerate(models):
        log(f"=== [{mi+1}/{len(models)}] {model['id']} ({model['label']})")
        subprocess.run([os.path.join(HERE, "serve.sh"), "start", model["id"], str(PORT)], check=True)
        vram = vram_used()
        log(f"vram used: {vram/1e9:.2f} GB")
        for case in cases:
            workdir = os.path.join(outdir, "frames", f"{model['id']}-{case['id']}")
            rec = {"model": model["id"], "case": case["id"], "kind": case["kind"],
                   "label": model["label"], "prompt": case["prompt"],
                   "vram_bytes": vram, "output": None, "error": None,
                   "elapsed_s": None, "prompt_tokens": None, "completion_tokens": None}
            t0 = time.time()
            try:
                rec.update(run_case(model, case, workdir))
                log(f"  {case['id']}: {rec['elapsed_s']}s, {rec['completion_tokens']} tok out")
            except Exception as e:  # noqa: BLE001
                rec["error"] = f"{type(e).__name__}: {e}"
                log(f"  {case['id']}: ERROR {rec['error']}")
            results.append(rec)
            with open(os.path.join(outdir, "results.json"), "w") as f:
                json.dump(results, f, indent=1)
        subprocess.run([os.path.join(HERE, "serve.sh"), "stop", model["id"], str(PORT)], check=True)

    log("eval done → " + os.path.join(outdir, "results.json"))
    subprocess.run([sys.executable, os.path.join(HERE, "mkreport.py"), outdir], check=True)


if __name__ == "__main__":
    main()
