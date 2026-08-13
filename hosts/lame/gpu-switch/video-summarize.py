#!/usr/bin/env python3
"""video-summarize — chunk a long video, caption each chunk via the vision
server, join chunk captions into one cohesive summary (ingest-style pipeline,
see github.com/Francesco149/ingest modules/tasks/describe_single_chunk +
summarize_video).

Usage:
  python3 video-summarize.py <video> [--chunk 30] [--fps 2] [--scale 540]
                             [--frames-scale 384] [--max-frames 60]
                             [--port 8080] [--prompt "..."]

Output: "#### MM:SS - MM:SS" blocks (one per chunk) then "===== JOINED ====="
and the joined summary. Stdlib only; ffmpeg from PATH (nix-shell).
"""
import argparse, base64, json, os, subprocess, sys, tempfile, time
import urllib.request, urllib.error

def run(cmd):
    subprocess.run(cmd, check=True, capture_output=True)

def probe_duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "csv=p=0", path], capture_output=True, text=True)
    return float(out.stdout.strip())

def chat(port, content, max_tokens=1500, temperature=0.2):
    payload = {
        "model": "vision",
        "messages": [{"role": "user", "content": content}],
        "max_tokens": max_tokens, "temperature": temperature, "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            resp = json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read()[:300]}")
    msg = resp["choices"][0]["message"]
    out = (msg.get("content") or "").strip()
    if not out and msg.get("reasoning_content"):
        out = msg["reasoning_content"].strip()
    return out

def chunk_desc(port, chunk_path, start, end, fps, frames_scale, max_frames, prompt):
    s, e = int(start), int(end)
    header = f"#### {s//60:02d}:{s%60:02d} - {e//60:02d}:{e%60:02d}"
    # try native video first; on failure fall back to sampled frames
    b64 = base64.b64encode(open(chunk_path, "rb").read()).decode()
    try:
        content = [{"type": "input_video", "input_video": {"data": b64}},
                   {"type": "text", "text": prompt}]
        text = chat(port, content)
        if text:
            return f"{header}\n\n{text}"
        print(f"  [chunk {header}] native returned empty; falling back to frames", file=sys.stderr)
    except Exception as e:
        print(f"  [chunk {header}] native failed ({e}); falling back to frames", file=sys.stderr)
    with tempfile.TemporaryDirectory() as td:
        pat = os.path.join(td, "fr-%03d.jpg")
        run(["ffmpeg", "-y", "-v", "error", "-i", chunk_path, "-vf",
             f"fps={fps},scale={frames_scale}:-1", pat])
        frames = sorted(os.listdir(td))[:max_frames]
        if not frames:
            raise RuntimeError(f"no frames extracted for {chunk_path}")
        content = [{"type": "image_url",
                    "image_url": {"url": "data:image/jpeg;base64," + base64.b64encode(
                        open(os.path.join(td, f), "rb").read()).decode()}}
                   for f in frames]
        content.append({"type": "text",
                        "text": prompt + "\n(These are frames sampled from this clip, in order.)"})
        text = chat(port, content)
        return f"{header}\n\n{text}"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--chunk", type=int, default=30)
    ap.add_argument("--fps", type=float, default=2.0)
    ap.add_argument("--scale", type=int, default=540)
    ap.add_argument("--frames-scale", type=int, default=384)
    ap.add_argument("--max-frames", type=int, default=60)
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--prompt", default=(
        "Describe what happens in this video clip in detail, in order: "
        "motion, scene changes, people/objects, and any visible text. "
        "Be concrete and factual."))
    args = ap.parse_args()

    duration = probe_duration(args.video)
    print(f"# video: {args.video} ({duration:.0f}s), chunk={args.chunk}s", file=sys.stderr)
    blocks = []
    t0 = time.time()
    with tempfile.TemporaryDirectory() as td:
        start = 0
        while start < duration:
            end = min(start + args.chunk, duration)
            chunk_path = os.path.join(td, f"chunk-{start}.mp4")
            run(["ffmpeg", "-y", "-v", "error", "-ss", str(start), "-t", str(end - start),
                 "-i", args.video, "-vf", f"scale=-1:{args.scale}",
                 "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
                 "-movflags", "+faststart", "-an", chunk_path])
            print(f"[{time.strftime('%H:%M:%S')}] chunk {start}-{end}s ...", file=sys.stderr)
            blocks.append(chunk_desc(args.port, chunk_path, start, end, args.fps,
                                     args.frames_scale, args.max_frames, args.prompt))
            start = end

    print("\n\n".join(blocks))
    print("\n===== JOINED =====")
    join_prompt = (
        "Below are timestamped visual descriptions of consecutive chunks of one video.\n\n"
        + "\n\n".join(blocks) +
        "\n\nWrite ONE cohesive summary of the whole video based on these chunk "
        "descriptions: what it is, what happens over time, notable details. "
        "Preserve useful specifics (names, numbers, text).")
    joined = chat(args.port, [{"type": "text", "text": join_prompt}], max_tokens=2000, temperature=0.3)
    print(joined)
    print(f"# done in {time.time()-t0:.0f}s", file=sys.stderr)

if __name__ == "__main__":
    main()
