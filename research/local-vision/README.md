# Local vision on lame — testbed, results, and integration

Reusable evaluation + serving setup for **local vision models** on the 7800XT,
plus the omp wiring that lets text-only coding agents "see" through a local
VLM. Built 2026-08-13 on top of the earlier
[`../video-understanding/`](../video-understanding/) findings (native video in
upstream llama.cpp, Qwen-VL-lineage temporal merge, VRAM-fitting quants).

## TL;DR

- **Stack**: llama.cpp `llama-server` (Vulkan, 7800XT) + `--mmproj`; OpenAI-compatible API.
  Video goes through llama.cpp's native `input_video` for Qwen-VL-lineage
  models; other families get ffmpeg-sampled frames (the eval handles both).
- **Models**: on-disk (Qwen3.5/3.6 HauhauCS quants + mmproj, Gemma-4 family) +
  newly downloaded Qwen3.5-9B, Qwen3-VL-8B, DeepSeek-OCR. Full manifest:
  `models.yaml`.
- **Wiring into omp**: `models.yml` provider pointing at lame + `modelRoles.vision`.
  Any text-only model then gets a working `inspect_image` via the local VLM
  (see `README.md` here for the exact diff; the general pattern is
  omp `local-models.md` / `adding-a-provider.md`).
- **GPU switcheroo**: `hosts/lame/gpu-switch/` — `gpu-switch run vision|code|embed|idle`
  swaps what each GPU runs; boot-restore unit in `hosts/lame/gpu-switch.nix`.

## Eval harness (reusable)

```
models.yaml      # model manifest: gguf + mmproj + family + video mode
testcases.yaml   # images + clips with per-case prompts
assets/          # game HUD shots (Kirby TnT via BizHawk), dense text, code,
                 # web UI, diagram, video clips
scripts/serve.sh # llama-server lifecycle for one model (port 8095)
scripts/eval.py  # loop: model × case → results/run-*/results.json + report.html
scripts/mkreport.py
```

Run (on lame, in `/opt/ai-lab/vision-eval` — rsync from this dir):

```sh
rsync -az --exclude results research/local-vision/ root@lame:/opt/ai-lab/vision-eval/
ssh root@lame 'cd /opt/ai-lab/vision-eval && nix-shell -p python3 python3Packages.pyyaml ffmpeg \
  --run "python3 scripts/eval.py [--models a,b] [--cases c,d] [--run NAME] [--smoke]"'
```

The report is a standalone HTML page (images embedded, videos referenced):
open `results/run-<NAME>/report.html`.

### Gotchas learned (2026-08-13)

- **Video payload shape** for this llama.cpp rev: `{"type":"input_video","input_video":{"data":"<base64>"}}`
  — NOT `video_url`. The buffer is probed via ffprobe over `pipe:0`, which
  needs `-movflags +faststart` MP4 (webm-over-pipe reports `duration=N/A` but
  still works for the helper; mp4 is safer).
- **ffmpeg/ffprobe must stay in the server's PATH** — `serve.sh` resolves the
  nix-store ffmpeg and prepends it (the mtmd helper shells out per request).
- **gemma-4** emits its thinking in `reasoning_content`; send
  `chat_template_kwargs: {enable_thinking: false}` for direct answers.
- **SIGPIPE**: run the server under `sigpipe-wrapper.py` (SIG_IGN) — the mtmd
  feeder thread dies on EPIPE mid-video otherwise.
- **VRAM ceiling ~15.5 GB** on the 16 GiB card (see haruness `docs/MODELS.md`);
  a quant that "fits" on paper can still corrupt generation when mmproj + KV
  push past the ceiling.

## Vision for text-only agents — the research (what other people do)

Text-only models (DSV4-flash etc.) get vision one of these ways:

1. **VLM-as-a-tool (the standard agentic pattern)** — the agent gets an
   `inspect_image`-style tool that calls a separate vision model. OpenAI/Anthropic
   agents do this natively; self-hosted setups point the tool at a local
   OpenAI-compatible VLM (llama.cpp / Ollama / vLLM). This is exactly what omp
   does with `modelRoles.vision` → our local qwen3.5-9b. omp's own
   `tools/inspect_image.md` documents the contract (image content block +
   question; model must advertise `input: [text, image]`).
2. **OCR pipelines** — for text-heavy screens (terminals, docs, game HUDs):
   tesseract/paddleocr or a specialist VLM (DeepSeek-OCR, Qwen2.5-VL-OCR).
   Cheaper than a full VLM per call; loses layout semantics. We eval DeepSeek-OCR
   alongside the generalists as the dense-text specialist.
3. **DOM/a11y extraction for web UIs** — screenshot → browser accessibility
   tree/HTML instead of pixels; loses rendering fidelity (canvas, weird CSS,
   games). Complements rather than replaces VLM.
4. **Frame sampling for video** — clip → N frames → image batch (our fallback
   path); Qwen-VL-lineage models additionally get native temporal video via
   llama.cpp (M-RoPE + timestamp interleave).
5. **Offline captioning services** — a persistent VLM endpoint (like our
   `gpu-switch run vision`) that any tool/repo can POST images to; the
   one-shot `vision` CLI wraps it for scripts and non-omp contexts.

## Results

See `results/` (each `run-*` has `results.json` + `report.html`).
