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

## Results (run full-20260813, 7800XT, llama.cpp 6e9007a, temp 0.2)

9 models × 10 cases (7 images, 2 clips, 1 long-video chunk test). Full matrix:
`results/run-full-20260813/results.json` (regenerate the HTML page with
`scripts/mkreport.py`; live copy served at http://10.0.10.56:8099/report.html).

**Winner: Qwen3.5-9B Q4_K_M** — the vision service model (`gpu-switch run vision`,
omp `modelRoles.vision`). Newest native-vision family, ~6 GB → huge VRAM headroom,
fast (8–20 s/case), the most accurate dense-text/code transcription, and clean
native temporal video. Runner-ups: Qwen3.6/3.5-35B-A3B IQ2_M (equal image
quality, faster per-token, but IQ2 quant caps their ceiling and they eat the
whole card); Qwen3-VL-8B (fine, occasionally weaker game/HUD reasoning).

| model | image | dense text / code | video | notes |
|---|---|---|---|---|
| **qwen3.5-9b** ✅ | excellent | excellent (verbatim) | native, good | winner |
| qwen3.6-35b-a3b iq2m | excellent | excellent | native, good | IQ2 ceiling |
| qwen3.5-35b-a3b iq2m | excellent | excellent | native, good | IQ2 ceiling |
| qwen3.6-27b iq2m | excellent | excellent | native, good | slowest (dense 27B) |
| qwen3vl-8b | good | good | native, good | mis-guessed game on 1 shot |
| gemma4-26b-a4b q3km | good | weak (garbled lines) | frames | >15.5 GB VRAM with F32 mmproj |
| gemma4-12b q4km | good | **hallucinates** code | frames | unreliable for text |
| gemma4-31b iq2m | good | garbled | frames (per-frame refusal) | weakest gemma |
| deepseek-ocr q8 | OCR-only | flaky on large images | none | specialist only; not a chat model |

Pipeline gotchas baked into the harness: llama.cpp `input_video` payload shape
(`input_video: {data}`), ffprobe must stay in the server PATH, gemma-4
`chat_template_kwargs.enable_thinking:false`, SIGPIPE wrapper, VRAM ceiling
~15.5 GB, gemma 26B/31B mmproj crashes on multi-image batches (frames sent
sequentially), xet-backed HF repos need `hf download` (aria2 double-write
corrupted a file silently — verify sha256).

Long-video path (ingest-style): `video-summarize.py` chunks → timestamped
per-chunk captions → one joined summary. Verified on a 122 s MinutePhysics
clip (5 chunks, 93 s total, accurate joined summary). Wrapped as
`vision --video <file>`.

## State protocol (wake / switch guard)

`utils/vision` gates every call: `VISION_STATE=ok|switch|down` (exit 0/3/4).
On `down` it auto-wakes lame via code (`cold-unlock --host lame --stay`,
bounded by `VISION_WAKE_TIMEOUT`); on `switch` (lame up, vision not running —
something else on the GPU or idle) it refuses to switch automatically and
instructs the caller to get human confirmation (`gpu-switch run vision`).
`vision --check` probes passively. The same protocol is documented in the
repo AGENTS.md for agent sessions and is what omp `inspect_image` failures
should fall back to.

## 2026-08-14 update — OpenRouter default

`utils/vision` now defaults to **OpenRouter `qwen/qwen3.5-9b`**
(`OPENROUTER_API_KEY` in `~/.omp/agent/.env`, outside the repo) and falls
back to the local lame model on any OR failure (verified: 401 bad key →
local; 400 bad model → local). omp `modelRoles.vision` → openrouter
provider; `lame-vision` provider stays as the manual fallback. lame itself
is powered off; the local fallback auto-wakes it via code per the state
protocol above.
