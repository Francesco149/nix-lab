# research/

Evaluation + findings for **local AI models** on the lab's inference host
(`lame`). Reusable testbeds, not deployment config — deployment lives in
`hosts/lame/`. Each subdir is a self-contained workstream with its own README,
scripts, and results.

| Workstream | Status | What |
|---|---|---|
| [`video-understanding/`](video-understanding/) | active (2026-06-15) | native video on llama.cpp: build/run recipe, perf matrix (7800XT vs 3080), model selection |
| `agentic-coding/` | planned | custom harness to iteratively tune local models and score them on coding tasks |

## Conventions

- **Scripts run ON the inference host** (`ssh root@lame`), against
  `/opt/ai-lab/models`. They build llama.cpp under `/tmp/llama.cpp` and use
  `nix-shell` for toolchains/runtime libs — nothing is added to the host's
  system config.
- Findings + numbers are committed so they survive across sessions and machines
  (these reflect the state on the date noted; re-verify before relying on them).
- Keep model/quant file paths and `--n-cpu-moe`/`-ngl` knobs explicit in results
  so a run is reproducible.

The agentic-coding harness will reuse the same build/run plumbing
(`video-understanding/scripts/build-llama.sh`, `bench.sh`) plus a task corpus +
scoring; see that workstream's README when it lands.
