# Local video understanding on llama.cpp — findings & testbed

Reusable setup + findings for running **video understanding** on local vision
LLMs via upstream **llama.cpp native video**, on the `lame` inference host. Built
2026-06-15. Extends into agentic-coding evaluation later (see `../README.md`).

## TL;DR

- **Upstream llama.cpp has native video** (temporal-merge + M-RoPE + ffmpeg frame
  extraction + interleaved timestamps) as of commit **`8f83d6c` (2026-06-08)**.
  It **matches/beats** the old third-party `Cobdog/llama-video` patch and needs
  **no patch**. Verified end-to-end on the 7800XT with our existing
  `Qwen3.6-35B-A3B` + mmproj — high-quality, temporally-ordered descriptions.
- **Native temporal video is Qwen-VL-lineage only** (projector types
  `QWEN2VL`/`QWEN25VL`/`QWEN3VL` → `n_temporal_merge=2`). Gemma/GLM/InternVL/etc.
  can only see video as independent stills + timestamps. So a good video model on
  llama.cpp must be Qwen-VL family. Our Qwen3.6 models qualify.
- **nixpkgs `llama-cpp` (b9503, 2026-06-04) predates video by 4 days** → we build
  from source for now. Once nixpkgs crosses ~b9510 the deployment is just
  `pkgs.llama-cpp` + `ffmpeg` in PATH.
- **Perf headline:** fitting fully in VRAM dominates. A MoE that fits 16 GB runs
  ~120 t/s; the same family at `Q4_K_P` (21.8 G, needs offload) does 14–25 t/s.
  See `results/`.

## Hardware (host: lame, 10.0.10.56)

| GPU | VRAM | llama.cpp backend | Role |
|---|---|---|---|
| AMD RX 7800 XT | 16 GB | Vulkan / RADV | "main" instance (more VRAM) |
| NVIDIA RTX 3080 | 10 GB | CUDA | secondary (embed/video today) |

12 cores, 62 GB RAM (so MoE `--n-cpu-moe` offload is cheap). Both GPUs are in one
box; `VK_ICD_FILENAMES=<radv icd>` hides the NVIDIA card from Vulkan so the
7800 XT is used. Models live in `/opt/ai-lab/models`.

## How native video works (what to know)

- `llama-mtmd-cli --video FILE` or the server's OAI `input_video` content type.
- The mtmd **video helper** shells out to **ffmpeg/ffprobe** (must be in PATH),
  samples frames at a target fps (default 4.0), and interleaves human-readable
  **timestamp text chunks** (`[10m50.5s]`) for temporal grounding.
- For Qwen-VL it pairs consecutive frames into a **temporal super-frame**
  (`build_inp_with_temporal_merge`, two patch-embed kernels = the model's native
  Conv3D temporal dim) and assigns **M-RoPE** positions. This is exactly what the
  Cobdog patch hand-rolled, now upstream.
- Video exists only at the *helper* level — the core lib treats frames as images.

## Build + run (run ON lame)

```sh
# build llama-mtmd-cli + llama-bench (skips the web UI; not needed, breaks in sandbox)
scripts/build-llama.sh vulkan      # -> /tmp/llama.cpp/build-vulkan/bin
scripts/build-llama.sh cuda        # -> /tmp/llama.cpp/build-cuda/bin   (3080 = sm_86)

# describe a video (native temporal path)
scripts/video-describe.sh \
  /opt/ai-lab/models/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-Q4_K_P.gguf \
  /opt/ai-lab/models/HauhauCS/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive/mmproj-Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive-f16.gguf \
  /opt/ai-lab/downloads/video-282a46a4.webm vulkan

# text throughput sweep
scripts/bench.sh vulkan <model.gguf> -ngl 99 -ncmoe 33,26,20,14
```

## Gotchas (both matter for deployment)

1. **SIGPIPE crash (exit 141 mid-video).** The helper's ffmpeg *feeder thread*
   does a bare `fwrite()` with no `SIG_IGN`; when ffmpeg exits after the model has
   the frames it needs, the feeder hits SIGPIPE and the default disposition kills
   the process. Workaround: run under `scripts/sigpipe-wrapper.py` (SIG_IGN
   survives execv). Proper fix is one line upstream — worth a PR.
2. **Video token budget.** At full res a clip costs ~**1.3k tokens / sec of
   video** (≈646 tokens/super-frame × 2 fps-pairs). A 23 s clip overflowed a
   16k context. Cap per-frame tokens with `--image-max-tokens 256` (also how
   Qwen-VL is *meant* to do video) and/or lower fps. Long videos in the
   (rewritable) ingest path will need this tuning.
3. **CUDA build runtime:** the build links the *stub* `libcuda.so.1`; at runtime
   put `/run/opengl-driver/lib` first in `LD_LIBRARY_PATH` so the real driver
   wins, else llama.cpp silently falls back to CPU. (`scripts/bench.sh` handles
   this; `build-llama.sh` does not need it.)
4. **MTP GGUFs:** `--mmproj` may not co-exist with the MTP head in current
   llama.cpp. For vision/video use the non-MTP GGUF unless a test proves
   otherwise (see results / the MTP note below).

## Results

- `results/7800xt-vulkan.md` — RX 7800 XT (Vulkan) throughput matrix
- `results/3080-cuda.md` — RTX 3080 (CUDA) + card comparison
- `results/video-quality.md` — sample video descriptions per model
- `results/mtp-speedup.md` — MTP speculative-decode speedup (text gen)

## Model landscape (mid-2026) & recommendation

Qwen-VL lineage spans Qwen3-VL → Qwen3.5 → **Qwen3.6** (newest, Apr 2026; the
`Qwen3.6-*` files here). All share the vision encoder, so all get the temporal
video path. Qwen3.6 adds strong agentic coding (SWE-bench 73–77) that plain
Qwen3-VL lacked — so a single Qwen3.6 model can plausibly do **assistant +
agentic coding + video**.

Speed/quality on the **7800XT (16 GB), fully on GPU** (the deciding instance —
the 3080's 10 GB can't hold these at usable quants):

| Option | Model / quant | gen t/s | Notes |
|---|---|---:|---|
| **A — max speed** | MoE 35B-A3B **APEX-MTP Mini** (Q3, 13.3 G) | **~120** | great video, decent coding, fastest |
| **B — best quality** | **Dense 27B** Q3_K_XL **+ MTP** | **~54** | strongest coder, best video grounding, MTP 1.74× |
| (avoid) | MoE 35B-A3B `Q4_K_P` (offloaded) | 14–25 | best MoE weights but VRAM-bound → slow |

- **All three Qwen3.6 variants produce excellent, temporally-ordered video** — so
  video quality does **not** force the choice; speed vs coding does.
- **Recommendation:** run **one unified model on the 7800XT**. Pick **A
  (APEX-MTP Mini)** if raw speed/throughput matters most; pick **B (dense-27B +
  MTP)** for the best agentic-coding + most precise video, now fast enough (~54
  t/s) thanks to MTP. Both fit fully in 16 GB and both beat the offloaded
  `Q4_K_P` the lab runs today. (The forthcoming agentic-coding harness will
  settle A-vs-B on actual coding quality.)
- **mmproj is shareable** across Qwen3.6 finetunes of the same base, and
  MTP GGUFs work with `--mmproj` for video — so the fast MTP quants are viable
  for the unified instance.
- Keep the **3080** for embeddings / smaller models; it's VRAM-bound for 27–35B.

## Deployment path (hosts/lame/llama.nix)

The disabled `video` instance should be re-enabled **natively**:
- Drop the `Cobdog/llama-video` patch and the April `src.rev` pin.
- Use a recent llama.cpp (rev with native video) — or wait for nixpkgs
  `llama-cpp` ≥ ~b9510, then just `pkgs.llama-cpp`.
- Put `pkgs.ffmpeg` in the service PATH (runtime dep for video).
- Carry the SIGPIPE fix until upstreamed.
- Pick the model/quant from the perf matrix (a VRAM-fitting quant is ~5–8×
  faster than the offloaded `Q4_K_P`).

See `../../WORKDOC.md` and `../../hosts/lame/llama.nix`.
