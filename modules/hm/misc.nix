{ pkgs, ... }:
{
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
  ];

  # shell
  programs.fish = {
    enable = true;
    interactiveShellInit = (builtins.readFile ./fish/init.fish) + (builtins.readFile ./fish/dev.fish);
  };

  # automatically enter dev shells
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    silent = true;
  };

  # fuzzy file finder
  programs.fzf = {
    enable = true;
    defaultCommand =
      let
        excluded = [
          ".git"
          ".nix-defexpr"
          ".direnv"
          "result"
        ];
        excludeFlags = map (d: "--exclude ${d}") excluded;
      in
      "fd --type f --hidden --follow ${builtins.concatStringsSep " " excludeFlags}";
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
