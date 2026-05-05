{ ... }:
{
  programs.git = {
    enable = true;
    settings = {
      user.name = "headpats";
      user.email = "cute@headpats.uk";
      init.defaultBranch = "master"; # more aura and makes you horny
      pull.rebase = true;
    };
    ignores = [
      "result"
      "result*"
      ".direnv"
      "*.swp"
    ];
  };
}
