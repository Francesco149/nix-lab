function fish_prompt
  if set -q IN_NIX_SHELL; or set -q DIRENV_DIR
    set_color purple --bold
    set label (fish_is_root_user; and echo "owo"; or echo "uwu")
  else
    set_color red --bold
    set label (fish_is_root_user; and echo "OwO"; or echo "UwU")
  end

  echo -n "[$label] "
  set_color green
  echo -n (prompt_pwd)
  set_color normal
  echo -n " λ "
end

fzf --fish | source
carapace _carapace fish | source

alias cat bat
alias grep rg
alias du dust
