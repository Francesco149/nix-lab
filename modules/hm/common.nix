{ pkgs, osConfig, ... }:
let
  excludeFlagsList = map (d: "--exclude ${d}") osConfig.lab.fzf.excluded;
  excludeFlags = builtins.concatStringsSep " " excludeFlagsList;
in
{
  programs.git = {
    enable = true;
    settings = {
      user.name = "headpats";
      user.email = osConfig.lab.mail.main.addr;
      init.defaultBranch = "master"; # more aura and makes you horny
      pull.rebase = true;
    };
    ignores = osConfig.lab.fzf.excluded;
  };

  # software I would want to always have available.
  # - things I use all the time
  # - critical tools in case I have no internet to do nix-shell

  home.packages = with pkgs; [
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
  ];

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
      # we can tap into nix variables and consts from here if needed
      set -g rsync_exclude_flags ${builtins.replaceStrings [ "*" ] [ "\\*" ] excludeFlags}
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
  programs.bottom.enable = true; # 👉 👈

}
