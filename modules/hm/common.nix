{
  pkgs,
  osConfig,
  inputs,
  ...
}:
let
  inherit (osConfig) lab;
  excludeFlagsList = map (d: "--exclude ${d}") lab.fzf.excluded;
  excludeFlags = builtins.concatStringsSep " " excludeFlagsList;
in
{
  imports = [
    ./starship.nix
    # ./pi-gemma/pi-gemma.nix  # disabled — outdated, pending revamp (see block below)
  ];

  programs.git = {
    enable = true;
    settings = {
      user.name = "headpats";
      user.email = lab.mail.main.addr;
      init.defaultBranch = "master";
      pull.rebase = true;
    };
    ignores = lab.fzf.excluded;
  };

  # software I would want to always have available.
  # - things I use all the time
  # - critical tools in case I have no internet to do nix-shell

  home.packages =
    with pkgs;
    [
      age
      wget
      curl
      pv # pipe things with a progress and speed monitor
      htop
      iftop
      jq # cli to parse and query json
      fd # used by fzf to filter files
      tmux
      zellij # modern tmux alternative
      diskus
      dust # tree view of disk usage, better du
      gh # to get github token
      glab # gitlab token
      moreutils # ts to timestamp lines of output plus other nice utils
    ]
    ++ (with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
      codex
      claude-code
      opencode
    ]);

  services.gpg-agent = {
    enable = true;
    enableZshIntegration = true;
    pinentry.package = pkgs.pinentry-curses;
  };

  programs.gpg.enable = true;

  # shell
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set -g fish_greeting

      # we can tap into nix variables and consts from here if needed
      set -g rsync_exclude_flags ${builtins.replaceStrings [ "*" ] [ "\\*" ] excludeFlags}
      set -g age_keyfile ${lab.secrets.age.unlock}
    ''
    + (builtins.readFile ./fish/init.fish)
    + (builtins.readFile ./fish/dev.fish);
  };

  # automatically enter dev shells
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    silent = true;
  };

  # fuzzy file finder
  programs.fzf = rec {
    enable = true;

    # find command for running `fzf` directly and CTRL+T respectively
    defaultCommand = "fd --type f --hidden --follow " + excludeFlags;
    fileWidgetCommand = defaultCommand;

    # ALT-C
    changeDirWidgetCommand = "fd --type d --hidden --follow " + excludeFlags;

    # install shell hooks
    enableFishIntegration = true;
  };

  # shell tab completions/suggestions
  programs.carapace = {
    enable = true;
    enableFishIntegration = true;
  };

  # cat replacement
  programs.bat = {
    enable = true;
    extraPackages = with pkgs.bat-extras; [
      batdiff
      batgrep
      batman
    ];
  };

  # grep replacement
  programs.ripgrep = {
    enable = true;
    arguments = [
      "--smart-case"
      "--hidden"
    ];
  };

  # system monitor
  programs.bottom.enable = true;

  # pi-gemma is disabled pending a revamp. It pins pi from llm-agents, and pi
  # (0.80.2) is not on the numtide binary cache, so enabling it forces a
  # build-from-source. Re-enable the import above when revamping.
  /*
    programs.pi-gemma = {
      enable = true;
      package = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.pi;

      modelId = "gemma4"; # ollama model ID
      modelName = "Gemma4 26B A4B"; # display name in Pi

      inference = {
        baseUrl = "http://lame:${toString lab.ports.llama-vulkan}"; # no /v1 suffix

        # I keep this lower than my actual context limit for more aggressive
        # eviction. For small models the actually useful context is much less.
        contextWindow = 32767;

        maxTokens = 4096; # per-generation cap
        timeoutMs = 120000; # 2 min — increase for slow hardware
      };

      compaction = {
        keepRecentTokens = 8000; # recent turns preserved verbatim
        reserveTokens = 4096; # reserved for model response
      };

      guardian = {
        reminderInterval = 8; # workdoc reminder every N turns
        wrapUpTurn = 17; # warn to wrap up at this turn
        stuckWindow = 4; # fingerprint window size
        stuckThreshold = 2; # repeat count to trigger intervention
        subagentMaxTokens = 1024; # spawn_subagent response budget
      };
    };
  */

}
