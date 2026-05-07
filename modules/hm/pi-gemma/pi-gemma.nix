{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.programs.pi-gemma;

  # ── JSON helpers ──────────────────────────────────────────────────────────────

  settingsJson = builtins.toJSON {
    defaultProvider = "ollama";
    defaultModel = cfg.modelId;
    defaultThinkingLevel = "off";
    hideThinkingBlock = false;

    compaction = {
      enabled = true;
      # Keep recent tokens small — Gemma's context shape matters more than size.
      # Aggressive compaction keeps old tool noise summarised away quickly.
      reserveTokens = cfg.compaction.reserveTokens;
      keepRecentTokens = cfg.compaction.keepRecentTokens;
    };

    branchSummary = {
      reserveTokens = cfg.compaction.reserveTokens;
      skipPrompt = false;
    };

    retry = {
      enabled = true;
      maxRetries = 2;
      baseDelayMs = 1000;
      provider = {
        timeoutMs = cfg.inference.timeoutMs;
        maxRetries = 0;
        maxRetryDelayMs = 10000;
      };
    };

    quietStartup = false;
    enableInstallTelemetry = false;
    doubleEscapeAction = "tree";
    # Hide tool calls in the session tree — reduces visual noise
    treeFilterMode = "no-tools";

    steeringMode = "one-at-a-time";
    followUpMode = "one-at-a-time";

    enableSkillCommands = true;
    sessionDir = "~/.pi/agent/sessions";
    enabledModels = [ "${cfg.modelId}*" ];

    warnings = {
      anthropicExtraUsage = false;
    };
  };

  modelsJson = builtins.toJSON {
    providers = {
      ollama = {
        baseUrl = cfg.inference.baseUrl + "/v1";
        api = "openai-completions";
        apiKey = "ollama";
        compat = {
          # Ollama / llama.cpp don't understand the OpenAI developer role
          # used for reasoning models — send as plain system instead.
          supportsDeveloperRole = false;
          supportsReasoningEffort = false;
        };
        models = [
          {
            id = cfg.modelId;
            name = cfg.modelName;
            reasoning = false;
            input = [ "text" ];
            contextWindow = cfg.inference.contextWindow;
            maxTokens = cfg.inference.maxTokens;
            cost = {
              input = 0;
              output = 0;
              cacheRead = 0;
              cacheWrite = 0;
            };
          }
        ];
      };
    };
  };

in
{

  # ── Option declarations ─────────────────────────────────────────────────────

  options.programs.pi-gemma = {

    enable = mkEnableOption "Pi coding agent configured for Gemma4 A4B local models";

    package = mkOption {
      type = types.package;
      description = ''
        The pi agent package. The recommended way to get it is through llm-agents:
        https://github.com/numtide/llm-agents.nix

        Example flake usage:
          inputs.llm-agents.url = "github:numtide/llm-agents.nix";

          programs.pi-gemma = {
            enable = true;
            package = inputs.llm-agents.packages.''${pkgs.stdenv.hostPlatform.system}.pi;
          };
      '';
    };

    modelId = mkOption {
      type = types.str;
      default = "gemma4";
      description = ''
        Ollama model ID to use. Must match the name you pulled with
        `ollama pull` or the model name served by llama.cpp.
        Examples: "gemma4", "gemma4:26b", "gemma4:e4b".
      '';
    };

    modelName = mkOption {
      type = types.str;
      default = "Gemma4 26B A4B (local)";
      description = "Human-readable model label shown in Pi's UI.";
    };

    inference = {
      baseUrl = mkOption {
        type = types.str;
        default = "http://localhost:11434";
        description = ''
          Base URL of the OpenAI-compatible inference server.
          Works with Ollama (default), llama.cpp server, LM Studio, or vLLM.
          Do NOT include the /v1 suffix — the module appends it.
        '';
      };

      contextWindow = mkOption {
        type = types.int;
        default = 32768;
        description = ''
          Token window Pi uses for compaction threshold calculation. Set this
          well below your llama.cpp -c value to trigger compaction with headroom.
          Example: if llama-server runs with -c 120000, setting 32768 here means
          Pi compacts at ~16k tokens, long before llama runs out of KV cache.

          IMPORTANT — also add --parallel 1 (or -np 1) to your llama-server
          command. Pi has one conversation at a time and gets no benefit from
          parallel slots. Without it, compaction causes llama to simultaneously
          save the old slot's KV state and allocate a new one, which can spike
          memory by 700–800 MiB and trigger the OOM killer on large contexts.
        '';
      };

      maxTokens = mkOption {
        type = types.int;
        default = 4096;
        description = "Maximum tokens per generation (max_tokens in API calls).";
      };

      timeoutMs = mkOption {
        type = types.int;
        default = 120000;
        description = ''
          Provider request timeout in milliseconds.
          Local inference can be slow — 120s is conservative.
          Increase if you have very large files or slow hardware.
        '';
      };
    };

    compaction = {
      keepRecentTokens = mkOption {
        type = types.int;
        default = 8000;
        description = ''
          Tokens of recent conversation to preserve verbatim during compaction.
          Lower = more aggressive summarisation of old turns. Essential for small
          models where context shape matters more than size.
          Recommended: 6000–10000 for Gemma A4B.
        '';
      };

      reserveTokens = mkOption {
        type = types.int;
        default = 4096;
        description = ''
          Tokens reserved for the model's next response during compaction.
          Must leave room for response generation after compaction summaries.
        '';
      };
    };

    guardian = {
      reminderInterval = mkOption {
        type = types.int;
        default = 8;
        description = ''
          Inject a WORKDOC.md update reminder every N agent turns.
          Lower values = more frequent reminders = less likely to lose context
          across compaction. Increase if reminders feel too noisy.
        '';
      };

      wrapUpTurn = mkOption {
        type = types.int;
        default = 17;
        description = ''
          Warn the model to wrap up cleanly at this turn count.
          Keep well below your eviction threshold. With keepRecentTokens=8000
          and a 32k context, compaction typically fires around turn 20–25.
        '';
      };

      stuckWindow = mkOption {
        type = types.int;
        default = 4;
        description = "Sliding window of tool calls inspected for stuck detection.";
      };

      stuckThreshold = mkOption {
        type = types.int;
        default = 2;
        description = ''
          Number of identical tool-call fingerprints in stuckWindow
          that triggers a stuck intervention.
        '';
      };

      subagentMaxTokens = mkOption {
        type = types.int;
        default = 1024;
        description = ''
          Max tokens for spawn_subagent responses. Keep low — sub-agents
          are meant to give concise answers, not full explanations.
        '';
      };
    };

    extraAgentsContext = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Additional content appended to AGENTS.md for every session.
        Use for project-specific conventions, paths, or tool constraints
        without modifying the module.
      '';
    };

  };

  # ── Config (only active when enable = true) ─────────────────────────────────

  config = mkIf cfg.enable {

    home.packages = [ cfg.package ];

    # ── Environment variables consumed by the guardian extension ──────────────

    home.sessionVariables = {
      GEMMA_OLLAMA_URL = cfg.inference.baseUrl;
      GEMMA_MODEL_ID = cfg.modelId;
      GEMMA_SUBAGENT_MAX_TOKENS = toString cfg.guardian.subagentMaxTokens;
      PI_SKIP_VERSION_CHECK = "1";
    };

    # ── ~/.pi/agent/ directory layout ─────────────────────────────────────────
    #
    # Pi discovery rules:
    #   ~/.pi/agent/settings.json      → global settings
    #   ~/.pi/agent/models.json        → custom provider / model definitions
    #   ~/.pi/agent/extensions/*.ts    → auto-discovered extensions (hot-reloadable)
    #   ~/.pi/agent/skills/<name>/     → auto-discovered skills
    #   ~/.pi/agent/sessions/          → session storage (managed by Pi at runtime)
    #   ~/.pi/agent/AGENTS.md          → fallback when no project-local AGENTS.md

    home.file = {

      ".pi/agent/settings.json" = {
        text = settingsJson;
      };

      ".pi/agent/models.json" = {
        text = modelsJson;
      };

      ".pi/agent/extensions/workdoc-guardian.ts" = {
        source = ./workdoc-guardian.ts;
      };

      ".pi/agent/skills/gemma-coding/SKILL.md" = {
        source = ./SKILL.md;
      };

      # Pi loads this from ~/.pi/agent/AGENTS.md when no project-local
      # AGENTS.md exists. extraAgentsContext is appended here.
      ".pi/agent/AGENTS.md" = {
        text =
          (builtins.readFile ./AGENTS.md)
          + (optionalString (cfg.extraAgentsContext != "") ("\n\n" + cfg.extraAgentsContext));
      };

    };

    # ── Shell aliases ──────────────────────────────────────────────────────────
    # `pg` overrides the model at launch, handy if you want to test a different
    # variant without touching settings.json.

    programs.bash.shellAliases = mkIf config.programs.bash.enable {
      pg = "pi --model ${cfg.modelId}";
    };

    programs.zsh.shellAliases = mkIf config.programs.zsh.enable {
      pg = "pi --model ${cfg.modelId}";
    };

    programs.fish.shellAliases = mkIf config.programs.fish.enable {
      pg = "pi --model ${cfg.modelId}";
    };

  };

}
