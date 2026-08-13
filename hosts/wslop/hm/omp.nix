{
  pkgs,
  inputs,
  ...
}:
{
  home.packages = [
    # oh-my-pi (omp) — the coding-agent harness sentdex concluded is optimal for
    # DeepSeek-V4-Flash. omp-nix ships the prebuilt release binary wrapped for
    # NixOS (ld-linux interpreter + BUN_SELF_EXE), so nothing builds from source.
    # wslop-only for now; see WORKDOC if it should spread to other interactive hosts.
    inputs.omp-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # omp global agent config. The API key itself lives OUTSIDE nix in
  # ~/.omp/agent/.env (DEEPSEEK_API_KEY=...), which omp loads eagerly, so the
  # key never lands in the store. If the file is missing, run:
  #   echo 'DEEPSEEK_API_KEY=sk-...' > ~/.omp/agent/.env && chmod 600 ~/.omp/agent/.env
  home.file.".omp/agent/models.yml".text = ''
    # DeepSeek V4 Flash provider for omp. A custom entry is REQUIRED because
    # the built-in deepseek provider lacks the compat block below, which is what
    # prevents 400s when DeepSeek V4 uses tools in thinking mode.
    # Reference: https://api-docs.deepseek.com/quick_start/agent_integrations/oh_my_pi
    providers:
      deepseek:
        baseUrl: https://api.deepseek.com
        api: openai-completions
        apiKey: DEEPSEEK_API_KEY
        authHeader: true
        models:
          - id: deepseek-v4-flash
            name: DeepSeek V4 Flash
            reasoning: true
            thinking:
              minLevel: high
              maxLevel: xhigh
              mode: effort
            input: [text]
            contextWindow: 1000000
            maxTokens: 384000
            compat:
              supportsDeveloperRole: false
              supportsReasoningEffort: true
              maxTokensField: max_tokens
              reasoningEffortMap:
                high: high
                xhigh: max
              supportsToolChoice: false
              requiresReasoningContentForToolCalls: true
              requiresAssistantContentForToolCalls: true
              extraBody:
                thinking:
                  type: enabled
  '';

  home.file.".omp/agent/config.yml".text = ''
    # Single-model routing: only DeepSeek V4 Flash is wired up, so every text
    # role points at it. (tiny is deliberately unset — it is the local on-device
    # role for titles/memory; `omp tiny-models download` won't burn API credits.
    # defaultThinkingLevel: high is DeepSeek V4's minimum thinking tier (model
    # thinking.minLevel) and the level sentdex benched. Say "ultrathink" in a
    # turn to push it to xhigh (DeepSeek "max") on demand.
    modelRoles:
      default: deepseek/deepseek-v4-flash
      smol: deepseek/deepseek-v4-flash
      slow: deepseek/deepseek-v4-flash
      plan: deepseek/deepseek-v4-flash
      commit: deepseek/deepseek-v4-flash
      task: deepseek/deepseek-v4-flash
    defaultThinkingLevel: high
  '';
}
