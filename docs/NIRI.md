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

The script launches weston (kiosk-shell, fullscreen) which execs niri inside
it. When niri exits, weston exits. WSLg must be running (`WAYLAND_DISPLAY`
set) — opening any GUI app first will trigger WSLg startup.

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

## Known Issues

- **WSLg resize crash**: The outer WSLg window cannot be resized while niri
  is running. The kiosk-shell fullscreen setup avoids this by launching at
  a fixed 1920×1080.
- **Wayland connection**: `niri-start` will fail if WSLg is not running.
  Run a GUI app (e.g. `glxgears`) first to trigger WSLg.
- **No clipboard sharing**: Currently no wayland-to-Windows clipboard bridge
  is configured. `wl-clipboard` is installed for in-session use.
