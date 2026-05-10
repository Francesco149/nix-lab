# tmux

Interactive hosts import `modules/interactive.nix`, which imports
`modules/tmux.nix`. That module installs `tmux` system-wide and writes the
shared configuration to `/etc/tmux.conf`.

## Terminal Behavior

Mouse mode is explicitly disabled. The terminal emulator keeps ownership of
wheel scrolling, so the scroll wheel moves through the Alacritty scrollback
instead of entering tmux copy mode or stepping through shell history.

tmux uses `tmux-256color` and enables RGB color support for Alacritty-style
terminals. Pane contents keep default foreground and background colors, so
programs inside tmux should look the same as they do outside tmux when the
terminal uses the same palette.

Only tmux chrome uses `config.lab.colors`: the status line, active pane border,
copy-mode selection, and command messages.

## Sessions

- `tmux`: start a new session.
- `tmux new -s <name>`: start a named session.
- `tmux ls`: list sessions.
- `tmux attach -t <name>`: attach to an existing session.
- `<prefix>d`: detach from the current session.

The primary prefix is `Ctrl-a`. The default `Ctrl-b` prefix also works.

## Windows And Panes

- `<prefix>c`: create a window in the current directory.
- `<prefix>,`: rename the current window.
- `<prefix>n` / `<prefix>p`: next or previous window.
- `<prefix><number>`: jump to a numbered window.
- `<prefix>"`: split below in the current directory.
- `<prefix>%`: split right in the current directory.
- `<prefix>x`: close the current pane.
- `<prefix>z`: zoom or unzoom the current pane.
- `<prefix>h/j/k/l`: select the pane left, down, up, or right.
- `<prefix><arrow>`: select panes with arrow keys.

Windows and panes are numbered from 1, and window numbers are renumbered after
closing a window.

## Copy Mode

- `<prefix>[`: enter copy mode.
- Arrow keys, Page Up, and Page Down move through the tmux history.
- `q`: leave copy mode.

Copy mode is intentionally explicit because normal mouse scrolling belongs to
the terminal scrollback.

## Config

- `<prefix>r`: reload `/etc/tmux.conf`.

The scrollback history limit is `100000` lines. Clipboard forwarding is enabled
with tmux's `set-clipboard` support, subject to terminal and SSH support.
