---
name: scaffold-native-app
description: Turnkey scaffolding blueprint and automation guide for bootstrapping native desktop creation tools (Raylib 6.0 + ImGui + Lua) with Nix flakes, Windows cross-compilation, runtime-loaded fonts, headless testing, and ORIENTATION.md.
---

# Scaffold Native App Blueprint

This skill guides the creation of a new, fully reproducible native desktop application repository adhering to the high-performance native tool standards.

There is ONE template — `templates/raylib/` — and it is **2D + 3D in a single
codebase**: the 3D block editor and a 2D texture-paint canvas share one Raylib
window and one Lua VM, and the painted 2D texture binds straight onto the 3D
model (`lp.tex.apply_to_model`). There is no separate 2D template and no
font-embedding tool. Every new scaffold is a copy of this template with the
project name substituted.

---

## 1. Project Directory Structure Standard

```
my-tool/
├── flake.nix              # Pinned Nix flake (raylib 6.0, MinGW-w64 cross, ImGui 1.92.4, Lua 5.4)
├── flake.lock
├── ORIENTATION.md         # Dense, single-source-of-truth front (for LLMs and humans)
├── README.md              # Project overview, key features, build instructions (scaffold adds)
├── LICENSE                # MIT License (scaffold adds)
├── .gitignore             # build/, *.exe, *.o
├── assets/
│   └── fonts/             # Runtime-loaded fonts — NOT embedded, no embed step
│                           #   InterVariable.ttf (Latin/Cyrillic primary) + ipag.ttf (CJK fallback)
│                           #   dev shell: FONT_LATIN / FONT_CJK env vars; packaged: assets/fonts/
└── editor/
    ├── Makefile           # linux, win, package, run, test, shot, shot-drive, shot-pan, shot-paint, win-run
    ├── src/               # C++ core — ONE window host + ONE bindings TU
    │   ├── main.cpp       # raylib window, rlImGui bridge, Lua VM, lp.rl/lp.ig/lp.tex/lp.cam2d/
    │   │                  #   lp.drive bindings, modern dark theme + Inter/CJK font stack,
    │   │                  #   CLI modes (--test/--shot/--frames/--drive), layout-aware root
    │   ├── ig.cpp         # ImGui setup, scoped Begin/End wrappers (ig.window, ig.child, …)
    │   │                  #   + frame-end balance tracker (ig_balance_check)
    │   ├── editor.h       # Shared bindings header
    │   └── vendor/rlImGui/  # Vendored rlImGui bridge (rlImGui.cpp, imgui_impl_raylib)
    ├── lua/               # ALL UI, interaction, cameras, document state (embedded Lua 5.4)
    │   ├── main.lua       # Frame orchestration, modes 1-5, GPU setup deferred to first frame
    │   ├── doc.lua        # Document state model, serialization, mutation tracking
    │   ├── geom.lua       # Geometry helpers
    │   ├── undo.lua       # Snapshot undo/redo journal
    │   └── drive.lua      # Headless input-tape library (D.tap/D.drag/D.at over lp.drive.*)
    └── tests/             # Headless Test Suite
        ├── testmain.lua   # Headless test runner (--test boot + binding checks)
        └── drive_*.lua    # Input tapes: drive_orbit, drive_pan, drive_paint3d, drive_gate5
```

> **ig.cpp scoped wrappers**: the `ig.cpp` binding layer ships a scoped Begin/End API (`ig.window`, `ig.child`, `ig.popup`, `ig.popup_modal`, `ig.popup_context_window`, `ig.popup_context_item`, `ig.menu`, `ig.menu_bar`, `ig.table_`, `ig.tab_bar`, `ig.tab_item`, `ig.list_box`, `ig.tree`, `ig.tooltip_`, `ig.group`, `ig.disabled`) — each takes a Lua callback as its last argument and guarantees the matching `End` is called even when the body errors. It also tracks every scoped pair in a depth counter (`g_bal`) and exposes `ig_balance_check()`, called at frame end from `main.cpp`, which force-closes any unbalanced pair with a warning instead of corrupting the frame stack. New projects MUST keep both in `ig.cpp`; all panel code uses the scoped wrappers, never raw `ig.begin_*`/`ig.end_*` (escape-hatch only).

Fonts load at runtime via `FONT_LATIN`/`FONT_CJK` (dev shell) or
`assets/fonts/` (packaged) — there is no embedding step, no generated font
header, and no mono font in the stack. See §7 for the required
theme/font defaults.

---

## 2. Pinned Nix Flake (`flake.nix`) Specification

The `flake.nix` provides instant, hermetic development environments and cross-compilation toolchains:

```nix
{
  description = "cubeforge-raylib — 3D block editor with Raylib + ImGui + Lua";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        mingw = pkgs.pkgsCross.mingwW64.buildPackages;
        mingwPkgs = pkgs.pkgsCross.mingwW64;

        # Pin Dear ImGui >= 1.92 for dynamic font atlas
        imguiSrc = pkgs.fetchFromGitHub {
          owner = "ocornut";
          repo = "imgui";
          rev = "v1.92.4";
          hash = "sha256-DyQ2fh749S41UFdLto7TtxsnBsd7CBzAUFq36LeZZ5Y=";
        };

        # Lua 5.4 source for embedding (unpacked from the pinned nixpkgs src)
        luaSrc = pkgs.runCommand "lua-5.4-src" { } ''
          mkdir -p $out
          tar xzf ${pkgs.lua5_4.src} --strip-components=1 -C $out
        '';
      in {
        devShells.default = pkgs.mkShell {
          name = "cubeforge-raylib-dev";

          packages = with pkgs; [
            mingw.gcc
            mingw.binutils
            gnumake
            pkg-config
            python3
            lua5_4
            git
          ];

          buildInputs = with pkgs; [
            raylib
            libGL
            mesa
            xorg.libX11
            xorg.libXrandr
            xorg.libXinerama
            xorg.libXcursor
            xorg.libXi
            inter
            ipafont
          ];

          shellHook = ''
            export CF_ROOT=$PWD
            export IMGUI_DIR=${imguiSrc}
            export LUA_SRC=${luaSrc}
            export RAYLIB_INC=${pkgs.raylib}/include
            export RAYLIB_LIB=${pkgs.raylib}/lib
            export FONT_LATIN=${pkgs.inter}/share/fonts/truetype/InterVariable.ttf
            export FONT_CJK=${pkgs.ipafont}/share/fonts/truetype/ipag.ttf

            # Windows cross: raylib import lib + runtime DLL from pkgsCross
            export RAYLIB_CROSS_INC=${mingwPkgs.raylib}/include
            export RAYLIB_CROSS_LIB=${mingwPkgs.raylib}/lib
            export RAYLIB_CROSS_DLL=${mingwPkgs.raylib}/bin/libraylib.dll
            # nixpkgs mingw raylib links GLFW dynamically — ship its DLL too
            export GLFW_CROSS_DLL=${mingwPkgs.glfw}/bin/glfw3.dll

            export MCFG_LIBDIR=$(x86_64-w64-mingw32-g++ -### -x c++ /dev/null -o /dev/null 2>&1 \
              | tr ' ' '\n' | grep -m1 -oE '^-L/nix/store/[^ ]*mcfgthread[^ ]*/lib' | cut -c3-)
            export MCFG_DLL=$(dirname "$MCFG_LIBDIR")/bin/libmcfgthread-2.dll

            export MINGW_CC=x86_64-w64-mingw32-gcc
            export MINGW_CXX=x86_64-w64-mingw32-g++

            echo "cubeforge-raylib dev shell ready"
            echo "  raylib:   ${pkgs.raylib}"
            echo "  imgui:    ${imguiSrc}"
            echo "  build:    make -C editor        # windows cross"
            echo "            make -C editor linux  # native linux"
          '';
        };

        formatter = pkgs.nixfmt-rfc-style;
      });
}
```

New scaffolds MUST keep this exact shape: `raylib` + X11 libs (`libX11`,
`libXrandr`, `libXinerama`, `libXcursor`, `libXi`) + `libGL`/`mesa` as
`buildInputs`, `inter` + `ipafont` for the font stack, and the full
`shellHook` export set — `RAYLIB_INC`/`RAYLIB_LIB`,
`RAYLIB_CROSS_INC`/`RAYLIB_CROSS_LIB`/`RAYLIB_CROSS_DLL`, `GLFW_CROSS_DLL`,
`MCFG_DLL`, `FONT_LATIN`, `FONT_CJK`, `MINGW_CC`/`MINGW_CXX` (plus
`CF_ROOT`, `IMGUI_DIR`, `LUA_SRC`). The Makefile consumes these names
verbatim. Keep the ImGui `fetchFromGitHub` pin (>= 1.92 for the dynamic font
atlas) and the Lua 5.4 source pattern (`pkgs.lua5_4.src` unpacked via
`runCommand`).

---

## 3. Top-Level `ORIENTATION.md` Standard

Every repository must start with a dense `ORIENTATION.md` serving as the single source of truth:

```markdown
# <project-name> — orientation

<One-sentence elevator pitch: what it is, core workflow, target user aesthetic>.
C++ is a slim core (raylib window, rlImGui bridge, Lua VM, lp.rl/lp.ig/lp.tex/lp.cam2d
bindings); ALL UI, interaction logic, cameras, and document state are embedded Lua 5.4.
2D texture paint is a first-class subset of the same project as the 3D editor.

## Environment & Build Rules
- Everything builds and runs via `nix develop`; make targets run from the repo root.
- `make -C editor linux` -> Compiles native Linux binary (raylib 6.0, GL).
- `make -C editor win` -> Cross-compiles standalone Windows 64-bit PE via MinGW
  (raylib mingw, GLFW/OpenGL).
- `make -C editor package` -> Assembles standalone folder: exe + libraylib.dll +
  glfw3.dll + libmcfgthread-2.dll + lua/ + tests/ + assets/fonts/.
- `make -C editor test` -> Headless boot + binding checks (no window, no GL).
- `make -C editor shot` -> Headless screenshot to build/shot.png (hidden window).
- `make -C editor shot-drive` -> 3D orbit input tape -> build/shot_orbit.png.
- `make -C editor shot-pan` -> 2D MMB-pan input tape -> build/shot_pan.png.
- `make -C editor shot-paint` -> 2D->3D paint tape -> build/shot_paint3d.png.
- `make -C editor run` -> Interactive window.

## Architecture & Code Map
- `editor/src/main.cpp` -> Single host: raylib window, rlImGui bridge, Lua VM,
  all lp.* bindings, theme + fonts.
- `editor/src/ig.cpp` -> ImGui setup, scoped Begin/End wrappers + balance tracker.
- `editor/lua/` -> Product implementation (panels, cameras, canvas, undo, tools).
- `assets/fonts/` -> Runtime-loaded Inter + CJK fonts (no embedding step).

## Interaction & Feel Invariants
- 60 FPS locked, zero-latency input polling.
- 3D camera is Godot language: MMB tilt, Shift+MMB pan, RMB fly (WASD/QE), wheel dolly.
- 2D camera: MMB pan (content follows the drag, scaled by zoom), wheel zoom
  cursor-anchored (the world point under the cursor stays put).
- Ctrl+Z / Ctrl+Y undo/redo with stroke coalescing (one undo per stroke).
- All actions have keyboard shortcuts and clear tooltips.
- All UI Begin/End pairs use the scoped wrappers from `ig.cpp` (`ig.window`/`ig.child`/…);
  raw `ig.begin_*`/`ig.end_*` is escape-hatch only. `ig_balance_check()` closes any
  unbalanced pair at frame end with a warning.
- Headless verification uses the `lp.drive.*` virtual-input override: frame-accurate
  input tapes with no window focus, no xdotool, no synthetic OS events.
```

---

## 4. Headless Automation & Verification Harness

`main.cpp` MUST parse the standard CLI modes (all headless-capable):

```
build/cubeforge-raylib                            # interactive
build/cubeforge-raylib --test                     # boot VM + run tests/testmain.lua
build/cubeforge-raylib --shot out.png --frames N  # hidden-window capture, N frames
build/cubeforge-raylib --shot out.png --frames N --drive editor/tests/drive_pan.lua
```

- `--test` — headless boot check: initialize the Lua VM (no window, no GL
  context) and run `tests/testmain.lua` if present; exit 0/1. GPU resource
  creation MUST be deferred to the first frame (`setup_scene()` in `main.lua`),
  NOT module load, so `--test` stays GL-free (`lp.tex.create` allocates only a
  CPU `Image` until the first `upload()`).
- `--shot out.png --frames N` — hidden-window capture; runs N frames, saves the
  PNG, exits. The default is 20 frames.
- `--drive script.lua` — loads an input tape before the loop, enabling
  `--shot` to be input-driven.

**Headless input drive (`lp.drive.*`)** — the C++ `lp.drive.*` layer is a
virtual-input override: when active, ALL `lp.rl.*` input getters return injected
state instead of real input. Frame-accurate tests need no window focus, no
xdotool, no synthetic OS events — the app runs hidden and a Lua tape drives it.

`lp.drive` API:
- `lp.drive.active(bool)` — enable/disable the override
- `lp.drive.mouse(x, y)` — set cursor pos
- `lp.drive.button(btn, down)` — 0=left 1=right 2=middle (pressed edge tracked)
- `lp.drive.wheel(dy)` — accumulate wheel for this frame
- `lp.drive.key(code, down)` — raylib keycodes; `lp.rl.key.*` constants
- `lp.drive.frame()` — frame boundary (advance prev-pos, clear wheel/pressed)

The C++ loop calls the global `drive_step()` before each frame's render
(injects this frame's input) and `drive_frame()` after `EndDrawing` (the frame
boundary advances the prev-pos baseline so delta math is correct). `drive.lua`
implements both and layers composites on top: `D.tap(f, key)`,
`D.drag(f, x0,y0,x1,y1, steps, btn)`, `D.click(f, x, y, btn)`, `D.chord(f, mod,
key)`, `D.at(f, fn)`.

Drive script pattern (`editor/tests/drive_pan.lua`):
```lua
local D = require("drive")
D.tap(2, D.Key.Five)                        -- enter 2D texture-paint mode
D.drag(4, 400, 400, 500, 400, 8, 2)         -- middle-drag = 2D pan
D.at(20, function() ... assert CF.cam2d.pan moved ... end)
```

**Layout-aware paths**: the exe must resolve roots for both layouts —
`editor/lua/` in the dev tree, `lua/` directly next to the exe in the packaged
folder. The drive-script path resolution does the same (`editor/tests/` in
dev; `tests/` packaged; a path containing `/` is used verbatim). Exports that
write into `build/` need the cross-platform `lp.file.mkdirs` binding so
`build/` exists in packaged mode too.

---

## 5. Standalone Windows Packaging

The Makefile `package` rule gathers the executable, its DLLs, `lua/`, `tests/`,
and the fonts into a standalone folder:

```makefile
package: win
	mkdir -p $(BUILD)/cubeforge-raylib-win64
	cp $(WIN_OUT) $(BUILD)/cubeforge-raylib-win64/
	cp $(RAYLIB_CROSS_DLL) $(BUILD)/cubeforge-raylib-win64/   # libraylib.dll
	cp $(GLFW_CROSS_DLL) $(BUILD)/cubeforge-raylib-win64/     # glfw3.dll
	cp $(MCFG_DLL) $(BUILD)/cubeforge-raylib-win64/           # libmcfgthread-2.dll
	cp -r ../editor/lua $(BUILD)/cubeforge-raylib-win64/lua
	cp -r ../editor/tests $(BUILD)/cubeforge-raylib-win64/tests
	mkdir -p $(BUILD)/cubeforge-raylib-win64/assets/fonts
	cp $(FONT_LATIN) $(BUILD)/cubeforge-raylib-win64/assets/fonts/InterVariable.ttf
	cp $(FONT_CJK) $(BUILD)/cubeforge-raylib-win64/assets/fonts/ipag.ttf
	@echo "packaged $(BUILD)/cubeforge-raylib-win64/"
```

New scaffolds MUST ship `lua/` + `tests/` + `assets/fonts/` next to the exe —
the packaged exe is layout-aware and needs all three (see §4).

## 5b. Raylib Windows Cross

Cross-compile against `pkgsCross.mingwW64.raylib` 6.0. The nixpkgs mingw raylib
build links **GLFW dynamically**, so the package ships `libraylib.dll` +
`glfw3.dll` + `libmcfgthread-2.dll` + the exe + `lua/` + `tests/` +
`assets/fonts/`. The flake shellHook exports the env names the Makefile
consumes (see §2):

```sh
export RAYLIB_CROSS_INC=${mingwPkgs.raylib}/include
export RAYLIB_CROSS_LIB=${mingwPkgs.raylib}/lib
export RAYLIB_CROSS_DLL=${mingwPkgs.raylib}/bin/libraylib.dll
export GLFW_CROSS_DLL=${mingwPkgs.glfw}/bin/glfw3.dll   # raylib links it dynamically
export MCFG_DLL=$(dirname "$MCFG_LIBDIR")/bin/libmcfgthread-2.dll
export MINGW_CC=x86_64-w64-mingw32-gcc
export MINGW_CXX=x86_64-w64-mingw32-g++
```

```makefile
# Makefile win target
WIN_CXX := $(MINGW_CXX)
WIN_CC   := $(MINGW_CC)
WIN_CXXFLAGS := $(CXXFLAGS) -DWINVER=0x0601 -D_WIN32_WINNT=0x0601 -DUNICODE -D_UNICODE \
  -I $(RAYLIB_CROSS_INC)
WIN_LDFLAGS := -static-libgcc -static-libstdc++
WIN_LIBS := -L$(RAYLIB_CROSS_LIB) -lraylib \
  -lopengl32 -lgdi32 -lwinmm -luser32 -lshell32 -lcomdlg32 \
  -Wl,-Bstatic -lmcfgthread -Wl,-Bdynamic \
  -ldwmapi -lole32 -lsetupapi
```

**Packaged layout is layout-aware**: the exe sits next to `lua/` and `tests/`
(directly, not under `editor/`). `main.cpp` must resolve roots for both
layouts (`editor/lua/` in dev, `lua/` packaged) — see the template's
`lua_init`/`--test`/root-resolution code. Exports that write into `build/`
need a cross-platform `lp.file.mkdirs` binding so `build/` exists in packaged
mode too.

**Windows smoke-test recipe** (host is the same machine via WSLInterop):
1. `make -C editor package`, copy `build/cubeforge-raylib-win64/*` to
   `C:\<app>` (never launch from a UNC cwd — cmd inherits it and pops a modal
   on the host screen).
2. Run `--test` via a `.bat` (stdout redirect, `echo EXITCODE=%ERRORLEVEL%`).
   `0xC0000135` (STATUS_DLL_NOT_FOUND) means a DLL is missing from the package —
   check `x86_64-w64-mingw32-objdump -p exe | grep 'DLL Name'` and the same for
   every shipped DLL (raylib pulls glfw3.dll transitively).
3. Verify interactively: PowerShell `Start-Process -PassThru`, assert
   `MainWindowHandle != 0`, `CopyFromScreen` capture, vision-check the PNG.

---

## 6. Single Template: 2D + 3D

New scaffolds MUST be ONE raylib-only template in which **2D is a first-class
subset of the 3D project** — there is no separate 2D template. One Raylib
window, one Lua VM: a 2D texture-paint canvas (`lp.tex.*` / `lp.cam2d.*` /
world-space `lp.rl` 2D draw bindings) sits alongside the 3D block editor, and
the painted texture is applied straight onto the 3D model. This proves
seamless 2D+3D integration in one codebase.

**Frame structure** (the app's main loop — copy verbatim):
`BeginDrawing` → `BeginMode3D` → `lp_draw3d()` → `EndMode3D` →
`lp_draw2d()` (mode 5 only) → `rlImGuiBegin` → `lp_frame()` → `rlImGuiEnd` →
`EndDrawing`.

> **WARNING — BeginMode2D placement**: raylib 6.0's `BeginMode2D` no longer
> installs an ortho projection — it only loads the camera transform into the
> current modelview. Called inside `BeginMode3D`, the perspective projection
> clips every 2D quad at z=0 (silently renders nothing). The 2D pass MUST run
> AFTER `EndMode3D` via the `lp_draw2d()` hook; never nest `BeginMode2D` inside
> `BeginMode3D`.

**The 2D surface** (all in Lua, zero C++ for new 2D features):
- `lp.tex.*` — offscreen canvas (CPU `Image` + GPU `Texture2D`): `create(w,h)`,
  `stamp(id,x,y,radius,hardness,r,g,b,a)`, `get_pixel`/`set_pixel`, `clear`,
  `upload`, `export_png`, `push_undo`/`pop_undo`/`can_undo` (+ redo), and
  `texture_id(id)` for ImGui previews. `create` is GL-free until `upload()` so
  the canvas works under `--test`.
- `lp.cam2d.*` — 2D viewport camera: `set(pan_x, pan_y, zoom)` / `get()`.
- `lp.rl.*` 2D draw (world-space, inside `begin_mode2d`/`end_mode2d`):
  `draw_texture`, `draw_line_2d`, `draw_circle_lines_2d`, `draw_rect_2d`,
  `draw_text_2d`, and `screen_to_world(mx,my)` / `world_to_screen(wx,wy)`
  (3-arg `world_to_screen` dispatches to the 3D `GetWorldToScreen`).
- **Mode 5 texture paint**: the viewport becomes a 2D canvas view of the
  512×512 paint texture; left-drag stamps paint, and the canvas is applied to
  the active 3D mesh.
- **2D→3D bridge**: `lp.tex.apply_to_model(tex_id, model_id)` binds the canvas
  texture to a model's albedo map — painting in 2D shows up on the cube in 3D.
- **2D controls doctrine**: MMB pan (content follows the drag, scaled by zoom),
  wheel zoom cursor-anchored, LMB paint (brush radius/color shared with the
  vertex-paint brush), Ctrl+Z/Ctrl+Y canvas undo (stroke coalescing: one undo
  per stroke).

**3D stays raylib-native**: hardware depth buffer, models, textures, RLSL
shaders, lighting. No painter's algorithm, no Lua-side Z-sorting — Lua calls
high-level draw primitives (`lp.rl.draw_cube`, `draw_grid`, `draw_line_3d`,
`draw_sphere`, `set_camera`, `get_ray`, `load_model_cube`, `load_shader`,
`set_material_*`, …), and complex 3D (models, textures, custom shaders) is
configured from Lua (`lp.rl.load_model_cube`, `load_texture_perlin`,
`load_shader`, `set_shader_value_*`) — new 3D features require ZERO C++
changes.

---

## 7. Theme & Font Defaults

Every new project MUST apply the modern dark theme and the Inter + CJK font
stack from the template's `setup_imgui_fonts_and_theme()` in `main.cpp`:

- **Modern dark theme (deep slate + amber)**: deep-slate surfaces
  (`WindowBg` ≈ (0.09, 0.09, 0.11), `ChildBg` ≈ (0.12, 0.13, 0.16),
  `FrameBg` ≈ (0.15, 0.16, 0.19), `Border` ≈ (0.16, 0.17, 0.20)) with an amber
  accent (`CheckMark`/`SliderGrab` ≈ (0.96, 0.62, 0.04), hovered
  (1.00, 0.78, 0.55)) and near-white `Text` (0.90, 0.90, 0.93).
- **Font stack**: `io.FontDefault` = InterVariable (primary), loaded with the
  Latin + Cyrillic + Greek + punctuation + arrows + box-drawing ranges
  (0x0020–0x00FF, Latin Ext-A/B, Vietnamese, Cyrillic, Greek, General
  Punctuation, Arrows, Box Drawing). A **merged CJK fallback** (IPA Gothic)
  is added with `MergeMode = true` covering Han + Kana + fullwidth forms
  (0x3000–0x30FF, 0x31F0–0x31FF, 0x3400–0x4DBF, 0x4E00–0x9FFF,
  0xF900–0xFAFF, 0xFF00–0xFFEF) so every script renders from one atlas.
- **Runtime loading, no embed**: fonts load from `FONT_LATIN`/`FONT_CJK`
  (dev shell) or `assets/fonts/` next to the exe (packaged). There is no
  embedding step — if a font fails to load, the app falls back to the
  ImGui default font; it never embeds.

> **stb_truetype limitation**: ImGui's default rasterizer (stb_truetype)
> parses TrueType outlines only. The CJK font MUST be a TrueType-outlined
> `.ttf` — IPA Gothic (`ipag.ttf`) works, but Noto CJK (OTF/CFF or TTC
> collection) does NOT parse. Do not substitute Noto CJK for the fallback;
> keep `ipafont` in the flake.
