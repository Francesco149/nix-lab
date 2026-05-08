# Neovim

Interactive hosts import `modules/interactive.nix`, which imports
`modules/nvim.nix`. That module exposes a custom Neovim as the system-wide
binary `e`.

The regular `neovim` package is intentionally left alone. OpenVSCode can keep
using the clean system `nvim`, while humans use `e`.

## Isolation

The `e` launcher sets `NVIM_APPNAME=labvim`. Neovim therefore looks under
`labvim` config, data, state, and cache paths instead of the default `nvim`
paths. This keeps the custom editor from reading or writing normal Neovim
configuration.

## Defaults

- 2-space indents.
- Absolute and relative line numbers.
- Transparent editor background; explicit colors are pulled from
  `config.lab.colors`.
- Diagnostics are shown with signs and underline, but inline virtual text is
  disabled.
- Completion does not auto-show or auto-insert text. Use `<C-Space>` to open
  completion and `<Tab>` to accept the selected item.
- Inlay hints are disabled when an LSP attaches.

## Clipboard

When `SSH_TTY` or `SSH_CONNECTION` is present, `e` uses Neovim's built-in OSC52
clipboard provider. This supports copying from remote SSH sessions through a
terminal such as Alacritty.

In SSH sessions, normal yanks also send the yanked text to the client clipboard
through OSC52, but `clipboard=unnamedplus` is not set. That keeps Vim's unnamed
register local, so `yy` followed by `p` works normally even though remote
clipboard paste cannot be read back through OSC52.

Outside SSH, `clipboard=unnamedplus` is set so local clipboard integration can
work when workstation use moves to NixOS.

## Language Tooling

The wrapper adds the language servers and formatters to its own `PATH`, so they
are available to `e` without changing the host-wide `neovim` package.

Configured LSPs cover:

- bash
- C and C++
- C#
- fish
- GDScript
- Lua
- Nix
- Python
- Svelte
- TypeScript and JavaScript
- Zig

Treesitter parsers are packaged for the same core language set. Neovim 0.12's
built-in `vim.treesitter.start()` is enabled by filetype rather than using the
old `nvim-treesitter.configs` API.

## Search

Telescope is installed for fuzzy search:

- `<leader>ff`: files
- `<leader>fg`: live grep
- `<leader>fb`: buffers
- `<leader>fh`: help

## Formatting

Formatting is handled by `conform.nvim` and runs on save by default.

Manual commands:

- `:Format`: format the current buffer.
- `:FormatDisable`: disable auto-format globally.
- `:FormatDisable!`: disable auto-format for the current buffer.
- `:FormatEnable`: re-enable auto-format.

Formatters include `nixfmt`, `prettierd`, `ruff format`, `clang-format`,
`csharpier`, `shfmt`, `fish_indent`, `stylua`, and `zig fmt`.
