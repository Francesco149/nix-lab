{ config, pkgs, ... }:
let
  inherit (config.lab) colors;
in
{
  environment.systemPackages = [
    pkgs.tmux
  ];

  environment.etc."tmux.conf".text = ''
    set -g default-terminal "tmux-256color"
    set -as terminal-features ",alacritty*:RGB,xterm-256color:RGB,tmux-256color:RGB"

    set -g mouse off
    set -g history-limit 100000
    set -g renumber-windows on
    set -g base-index 1
    set -g pane-base-index 1
    set -g escape-time 10
    set -g focus-events on
    set -g set-clipboard on
    set -g detach-on-destroy off

    set -g prefix C-a
    set -g prefix2 C-b
    bind C-a send-prefix

    bind c new-window -c "#{pane_current_path}"
    bind '"' split-window -v -c "#{pane_current_path}"
    bind % split-window -h -c "#{pane_current_path}"
    bind r source-file /etc/tmux.conf \; display-message "tmux config reloaded"

    bind h select-pane -L
    bind j select-pane -D
    bind k select-pane -U
    bind l select-pane -R

    set -g status on
    set -g status-interval 5
    set -g status-position bottom
    set -g status-justify left
    set -g status-left-length 40
    set -g status-right-length 80
    set -g status-left "#[fg=#${colors.base0C},bold]#S #[fg=#${colors.base01}]| "
    set -g status-right "#[fg=#${colors.base01}]%Y-%m-%d #[fg=#${colors.base0A}]%H:%M"
    set -g status-style "fg=#${colors.base05},bg=default"
    set -g window-status-format "#[fg=#${colors.base02}] #I:#W "
    set -g window-status-current-format "#[fg=#${colors.base00},bg=#${colors.base0C},bold] #I:#W "
    set -g window-status-separator ""

    set -g pane-border-style "fg=#${colors.base01}"
    set -g pane-active-border-style "fg=#${colors.base0A}"
    set -g message-style "fg=#${colors.base05},bg=#${colors.base01}"
    set -g mode-style "fg=#${colors.base00},bg=#${colors.base0A}"
    set -g window-style "fg=default,bg=default"
    set -g window-active-style "fg=default,bg=default"
  '';
}
