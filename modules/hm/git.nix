{ ... }:
{
  programs.git = {
    enable = true;
    settings = {
      user.name = "headpats";
      user.email = "cute@headpats.uk";
      init.defaultBranch = "master";
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
