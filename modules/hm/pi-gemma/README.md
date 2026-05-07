# pi-gemma — Pi coding agent for Gemma4 A4B

A Nix Home Manager module that configures [Pi](https://pi.dev) as a small-model-optimised
coding harness for `gemma4 26B A4B` (or any other local Ollama / llama.cpp model).

Adapted from the `ollama-proxy` architecture. The same principles apply — they just
map onto Pi's native extension system instead of a custom proxy.

---

## Design: why this works on small models

Cloud-optimised harnesses like opencode and vanilla Pi send the model everything and
let it figure out what matters. A 4B-active-parameter model collapses under that load —
it starts looping because the context is noisy, not because it can't code.

This configuration applies five fixes:

| Problem | Fix |
|---------|-----|
| Model reads whole files → context floods | `AGENTS.md` law: never `cat`, always `git grep` + `sed -n` with 80-line cap |
| Long sessions → model forgets plan | `WORKDOC.md` working document, periodically forced by guardian extension |
| Thinking loops → repeated tool calls | Stuck detector: fingerprints last 4 calls, steers on 2 repeats |
| Context floods before compaction | 65% context warning, mandatory WORKDOC flush before Pi compacts |
| Sub-analysis bloats orchestrator context | `spawn_subagent` tool: fresh Ollama call, file content never enters main window |

Pi's aggressive compaction (`keepRecentTokens: 8000`) handles the "20 turn eviction"
from `ollama-proxy`. The working document is the bridge across compaction boundaries —
the guardian extension makes sure the model keeps it current.

---

## Files

```
pi-gemma.nix                        ← Home Manager module (install this)
AGENTS.md                           ← Always-loaded project context (laws + workflow)
skills/gemma-coding/SKILL.md        ← On-demand full coding protocol (/skill:gemma-coding)
extensions/workdoc-guardian.ts      ← Guardian extension (reminders, stuck, subagent)
settings.json                       ← Pi global settings (compaction, retry, UI)
models.json                         ← Ollama provider + gemma4 model definition
```

All files are referenced directly from the module via `source = ./file` — no
content is duplicated as inline Nix strings.

---

## Quick start (with Nix + Home Manager)

### 1. Add llm-agents to your flake inputs

Pi is packaged by [numtide/llm-agents.nix](https://github.com/numtide/llm-agents.nix).
Add it alongside your other inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

### 2. Thread inputs through to Home Manager modules

```nix
outputs = { nixpkgs, home-manager, llm-agents, ... } @ inputs: {
  nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
    modules = [
      home-manager.nixosModules.home-manager
      {
        # thread through inputs to HM modules
        home-manager.extraSpecialArgs = { inherit inputs; };
      }
      ./configuration.nix
    ];
  };
};
```

### 3. Import the module and enable it

In your Home Manager config (receives `inputs` via `extraSpecialArgs`):

```nix
{ config, pkgs, inputs, ... }:
{
  imports = [ ./pi-gemma.nix ];

  programs.pi-gemma = {
    enable = true;
    package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;

    # All other options are optional — defaults work for gemma4 via Ollama.
    # modelId = "gemma4:26b";
    # inference.baseUrl = "http://localhost:11434";
    # inference.contextWindow = 32768;
  };
}
```

### 4. Start Ollama

```bash
ollama pull gemma4          # or: gemma4:26b / gemma4:e4b
ollama serve                # must be running before you launch pi
```

### 5. Apply and launch

```bash
home-manager switch
cd ~/your-project
pi                          # or: pg (alias for pi --model gemma4)
```

---

## Quick start (without Nix)

```bash
# 1. Install Pi
npm install -g @mariozechner/pi-coding-agent

# 2. Create Pi directories
mkdir -p ~/.pi/agent/extensions ~/.pi/agent/skills/gemma-coding

# 3. Place files
cp settings.json  ~/.pi/agent/settings.json
cp models.json    ~/.pi/agent/models.json
cp AGENTS.md      ~/.pi/agent/AGENTS.md
cp extensions/workdoc-guardian.ts ~/.pi/agent/extensions/
cp skills/gemma-coding/SKILL.md   ~/.pi/agent/skills/gemma-coding/

# 4. Set env vars (add to your .bashrc / .zshrc)
export GEMMA_OLLAMA_URL=http://localhost:11434
export GEMMA_MODEL_ID=gemma4
export GEMMA_SUBAGENT_MAX_TOKENS=1024
export PI_SKIP_VERSION_CHECK=1

# 5. Start Ollama + Pi
ollama serve &
cd ~/your-project && pi
```

---

## Workflow

### Starting a coding session

```
/workdoc init           ← creates WORKDOC.md in current directory
/skill:gemma-coding     ← loads the full protocol into context

Let's fix the polling loop in task_manager.py — tasks added at runtime
are never picked up until restart.
```

The model will immediately invoke `git ls-files`, fill in WORKDOC.md, then
ask what you want to work on. From there it uses `git grep` + `sed -n` to
explore surgically and `edit` for all changes.

### Resuming after a break

```
/workdoc load           ← injects WORKDOC.md so the model restores state
```

Or just open Pi in the project directory — if WORKDOC.md exists, the guardian
extension injects the restore prompt automatically on session start.

### Key commands

| Command | What it does |
|---------|-------------|
| `/workdoc init` | Create empty WORKDOC.md |
| `/workdoc` | Preview WORKDOC.md in the TUI |
| `/workdoc load` | Inject WORKDOC content as a user message |
| `/skill:gemma-coding` | Load the full coding protocol |
| `/reload` | Hot-reload the guardian extension after edits |
| `/tree` | Browse session history (tool calls hidden by default) |

### The guardian extension

Runs silently and fires:

- **On session start**: if WORKDOC.md exists, injects a restore prompt
- **Every 8 turns**: reminds model to update WORKDOC.md
- **At turn 17**: warns to wrap up cleanly
- **At 65% context usage**: urgent WORKDOC flush reminder before compaction
- **On repeated tool calls**: steers the model away from loops
- **`spawn_subagent` tool**: focused file analysis via a fresh Ollama call

---

## Configuration options

All options have sensible defaults for Gemma4 A4B. Override in your Home Manager config:

```nix
programs.pi-gemma = {
  enable = true;
  package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;

  modelId   = "gemma4";             # ollama model ID
  modelName = "Gemma4 26B A4B";    # display name in Pi

  inference = {
    baseUrl       = "http://localhost:11434";  # no /v1 suffix
    contextWindow = 32768;   # tokens — match your server config
    maxTokens     = 4096;    # per-generation cap
    timeoutMs     = 120000;  # 2 min — increase for slow hardware
  };

  compaction = {
    keepRecentTokens = 8000;  # recent turns preserved verbatim
    reserveTokens    = 4096;  # reserved for model response
  };

  guardian = {
    reminderInterval    = 8;     # workdoc reminder every N turns
    wrapUpTurn          = 17;    # warn to wrap up at this turn
    stuckWindow         = 4;     # fingerprint window size
    stuckThreshold      = 2;     # repeat count to trigger intervention
    subagentMaxTokens   = 1024;  # spawn_subagent response budget
  };

  # Append project-specific rules to every session's AGENTS.md:
  extraAgentsContext = ''
    ## Project conventions
    - Use `ruff` for Python linting: `ruff check . --fix`
    - Migrations go in `db/migrations/` as `NNNN_description.sql`
  '';
};
```

---

## Tuning for different hardware

| GPU VRAM | Recommended model | `contextWindow` | `keepRecentTokens` |
|----------|-------------------|----------------|-------------------|
| 8 GB     | gemma4:e4b (edge) | 16384 | 5000 |
| 12 GB    | gemma4:26b A4B    | 24576 | 7000 |
| 16 GB    | gemma4:26b A4B    | 32768 | 8000 |
| 24 GB+   | gemma4:26b A4B    | 65536 | 12000 |

The edge (E4B) variant exhausts useful context faster — drop `reminderInterval`
to 6 and `wrapUpTurn` to 14 to compensate.

---

## Design decisions

**Why Home Manager (not NixOS module)?**
Pi is a per-user tool. Its config lives in `~/.pi/` and the binary goes in the
user's PATH. A system module would create multi-user complications for no benefit.

**Why llm-agents.nix for the Pi package?**
numtide maintains proper Nix packaging for Pi and other LLM tools, tracked against
upstream releases. The module accepts any package via the `package` option so you
can substitute a locally-built version or a different flake if needed.

**Why `source = ./file` instead of inlined strings?**
Everything lives in the same directory, so there's no realistic drift risk between
the module and the files it references. Inlining as Nix strings would mean
maintaining two copies of every file, which is worse.

**Why not use Pi's built-in compaction model override?**
Pi's compaction summary model defaults to the same model as the primary — on a
local setup there's only one model available. The guardian extension's 65% warning
+ mandatory WORKDOC flush achieves the same result without an extra API call.

**Why `edit` and not `write` for existing files?**
`write` generates the entire file in one pass and overwrites silently. For a small
model on a large file, this risks dropping content outside the target function.
`edit` is surgical: it sees the full file and applies a targeted replacement.