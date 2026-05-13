# Niri Desktop (wslop)

Niri runs as a nested compositor on the `wslop` host. The outer layer is
weston under WSLg in kiosk mode (fullscreen, borderless container). Niri
runs inside weston with no chrome, giving a clean 1920×1080 workspace.

Three reusable modules power the desktop:
`modules/niri.nix` (system packages), `modules/hm/niri-config.nix` (niri
config), and `modules/hm/alacritty.nix` (terminal). Colors come from
`lib/lab.nix` via `osConfig.lab.colors`.

## Launch

```
niri-start
```

The script must be run as the `headpats` user (the default WSL user).
It launches weston (kiosk-shell, fullscreen) which execs niri inside it.
When niri exits, weston exits.

## Keybindings

| Key | Action |
|-----|--------|
| `Mod+Return` | Open alacritty terminal |
| `Mod+D` | Application launcher (fuzzel) |
| `Mod+Q` | Close focused window |
| `Mod+H/J/K/L` | Focus left/down/up/right |
| `Mod+Shift+H/J/K/L` | Move window left/down/up/right |
| `Mod+Ctrl+H/L` | Focus monitor left/right |
| `Mod+F` | Fullscreen window |
| `Mod+Shift+F` | Maximize column |
| `Mod+R` | Cycle column width (1/3, 1/2, 2/3) |
| `Mod+1-9` | Focus workspace 1-9 |
| `Mod+Shift+1-9` | Move column to workspace 1-9 |
| `Mod+Home/End` | First/last column |
| `Mod+Shift+Home/End` | Move column to first/last |
| `Mod+WheelDown/Up` | Focus column right/left |
| `Mod+Shift+WheelDown/Up` | Next/previous workspace |
| `Mod+Tab` | Toggle overview |

`Mod` is `Super` (Windows key) when niri runs directly, `Alt` when nested.
Under weston/WSLg, `Mod` resolves to `Alt` since niri detects the nested
environment. Use `Alt` for all bindings.

## Workspace Model

Niri uses dynamic workspaces arranged vertically. Each workspace holds
columns of windows that scroll horizontally. Empty workspaces disappear when
you switch away. One empty workspace always sits at the bottom.

- `focus-workspace-down/up` — move between workspaces (not bound by default;
  bind if needed)
- Workspaces move between monitors automatically on disconnect
- Named workspaces can be configured for persistence (see niri wiki)

## Font

PxPlus IBM VGA8 at 12px with bold disabled for pixel-perfect rendering.
Installed via `modules/hm/fonts.nix`, configured in alacritty with the full
lab.nix terminal palette.

## Theming

GTK and Qt apps use the Flat-Remix-Violet-Darkest theme with
Flat-Remix-Violet-Dark icons. Configured in `modules/hm/theme.nix`.
Firefox runs in dark mode via the GTK theme preference and
`MOZ_ENABLE_WAYLAND=1`.

## Default Applications

| Role | Application |
|------|------------|
| Terminal | alacritty |
| Launcher | fuzzel |
| File manager | nautilus |
| Text editor | gedit |
| Terminal editor | e (custom nvim wrapper) |
| Image viewer | eog |
| Video player | mpv |
| Browser | firefox |

Set in `modules/hm/default-apps.nix` via `xdg.mimeApps` and
`home.sessionVariables`.

## Known Issues

- **Resize behavior**: Running niri directly under WSLg (without weston)
  crashes on resize. When nested under weston in kiosk mode, both niri and
  weston windows can be resized without crashing, but weston does not change
  its internal resolution — it crops the view instead. Use the fullscreen
  setup at 1920×1080 for the best experience.
- **Wayland connection**: If `niri-start` complains about a missing Wayland
  display, WSLg may not have started yet. Try running a GUI app (e.g.
  `glxgears`) first to trigger WSLg, then launch niri again.
- **Clipboard**: Wayland clipboard changes are mirrored to the Windows
  clipboard via `wl-paste --watch clip.exe` at startup.
