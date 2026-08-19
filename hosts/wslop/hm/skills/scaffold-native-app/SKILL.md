---
name: scaffold-native-app
description: Turnkey scaffolding blueprint and automation guide for bootstrapping native desktop creation tools (ImGui + C++ / Lua) with Nix flakes, cross-compilation, embedded fonts, headless testing, and ORIENTATION.md.
---

# Scaffold Native App Blueprint

This skill guides the creation of a new, fully reproducible native desktop application repository adhering to the high-performance native tool standards.

The primary turnkey template is located at `templates/raylib` (Raylib + Dear ImGui + Lua 5.4 + MinGW Windows cross + Linux native).

---

## 1. Project Directory Structure Standard (Raylib Template)

```
my-tool/
├── flake.nix              # Pinned Nix flake (Raylib 6.0, MinGW-w64 cross, ImGui 1.92.4, Lua 5.4)
├── flake.lock
├── ORIENTATION.md         # Dense, single-source-of-truth front (for LLMs and humans)
├── README.md              # Project overview, key features, build instructions
├── .gitignore             # build/, *.exe, *.o, etc.
├── editor/
│   ├── Makefile           # Core build rules (win, linux, package, test, shot-*)
│   ├── src/               # C++ Core
│   │   ├── main.cpp       # Entry point, CLI args (--shot, --test, --drive), window loop
│   │   ├── winclip.c      # Win32 clipboard & native file dialog (GetOpenFileNameW)
│   │   ├── ig.cpp         # ImGui setup, theme, font atlas, Lua bindings (tw.ig.*)
│   │   ├── editor.h       # Core headers & bindings
│   │   └── vendor/        # rlImGui, tinyfiledialogs (Linux)
│   ├── lua/               # Pure Product Logic (Modular Lua)
│   │   ├── main.lua       # Frame orchestration, 3D viewport, 2D canvas, shortcuts, overlays
│   │   ├── doc.lua        # Document state model, selection modes (1..3), paint (4..5), undo
│   │   ├── geom.lua       # Vector math, raycast picking, normals, mesh_to_gl
│   │   └── undo.lua       # Snapshot undo/redo journal
│   └── tests/             # Headless Test Suite & Drive Tapes
│       ├── testmain.lua   # Headless test runner (binding & logic checks)
│       ├── drive.lua      # Headless input driver (injects mouse/keys per frame)
│       ├── drive_orbit.lua
│       ├── drive_pan.lua
│       ├── drive_paint3d.lua
│       └── drive_import.lua
```

---

## 2. Pinned Nix Flake (`flake.nix`) Specification

The `flake.nix` provides instant, hermetic development environments and cross-compilation toolchains:

```nix
{
  description = "my-tool — high-performance native desktop creation tool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        mingw = pkgs.pkgsCross.mingwW64.buildPackages;

        # Pin Dear ImGui >= 1.92 for dynamic font atlas
        imguiSrc = pkgs.fetchFromGitHub {
          owner = "ocornut";
          repo = "imgui";
          rev = "v1.92.4";
          hash = "sha256-DyQ2fh749S41UFdLto7TtxsnBsd7CBzAUFq36LeZZ5Y=";
        };

        # Lua 5.4 source for embedding
        luaSrc = pkgs.fetchurl {
          url = "https://www.lua.org/ftp/lua-5.4.7.tar.gz";
          hash = "sha256-d44XvIu1KxVdG3V/y+T48Zt02QJ2015rL0L47N8a7pI=";
        };
      in {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.pkg-config
            pkgs.gnumake
            pkgs.python3
            mingw.gcc
            mingw.binutils
          ];

          buildInputs = [
            pkgs.sdl3
            pkgs.lua5_4
            pkgs.mesa
            pkgs.libGL
          ];

          shellHook = ''
            export IMGUI_DIR="${imguiSrc}"
            export MINGW_PREFIX="x86_64-w64-mingw32"
          '';
        };

        formatter = pkgs.nixfmt-rfc-style;
      });
}
```

---

## 3. Top-Level `ORIENTATION.md` Standard

Every repository must start with a dense `ORIENTATION.md` serving as the single source of truth:

```markdown
# <project-name> — orientation

<One-sentence elevator pitch: what it is, core workflow, target user aesthetic>.
C++ is a slim core (window, imgui, Lua VM, GPU/math kernels); ALL UI, interaction logic,
and document state are embedded Lua 5.4.

## Environment & Build Rules
- Everything builds and runs via `nix develop`.
- `make win` -> Cross-compiles standalone Windows 64-bit PE (D3D11) via MinGW.
- `make linux` -> Compiles native Linux binary (SDL3).
- `make test` -> Runs headless test suite (assertions on state & kernels).
- `make shot` -> Captures offscreen UI screenshot to `build/shot.png`.
- `make package` -> Assembles standalone release folder with all dependencies.

## Architecture & Code Map
- `editor/src/` -> C++ backend (window, GPU textures, Lua bindings, heavy computation).
- `editor/lua/` -> Product implementation (UI panels, canvas, undo, autosave, tools).
- `assets/fonts/` -> Embedded vector & icon fonts.

## Interaction & Feel Invariants
- 60 FPS locked, zero-latency input polling.
- Cursor-anchored pan/zoom with smooth inertial lerp.
- Infinite multi-session undo (`undo.jsonl`), debounced 300ms autosave.
- All actions have keyboard shortcuts and clear tooltips.
```

---

## 4. Headless Automation & Verification Harness

Ensure `main.cpp` parses the standard CLI flags:
```cpp
if (cmd_has_flag("--shot")) {
    const char* out_path = cmd_get_str("--shot", "shot.png");
    int frames = cmd_get_int("--frames", 10);
    app_run_headless_screenshot(out_path, frames);
    return 0;
}

if (cmd_has_flag("--test")) {
    return app_run_headless_tests();
}

if (cmd_has_flag("--lua")) {
    const char* script_path = cmd_get_str("--lua", nullptr);
    return app_run_headless_script(script_path);
}
```

---

## 5. Standalone Windows Packaging

Ensure the Makefile contains a clean `package` rule that gathers the executable and all needed DLLs into a standalone folder:
```makefile
package: win
	mkdir -p dist/windows
	cp build/$(TARGET).exe dist/windows/
	cp -r editor/lua dist/windows/
	cp -r assets dist/windows/
	# Copy MinGW runtime DLLs
	cp $$(x86_64-w64-mingw32-gcc -print-file-name=libmcfgthread-2.dll) dist/windows/ 2>/dev/null || true
	@echo "Package ready at dist/windows/"
```
