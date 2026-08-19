# Image attachments on text-only models (auto-described)

When the active model has no vision support, omp automatically replaces an
attached/pasted image with a vision-model description in this form:

    <image path="local://image-<hash>.png">
    <description of the image, produced by a vision model>
    </image>

Rules:

1. The description inside the block IS the image content. Do NOT call
   inspect_image (or read the local:// path) just because the block exists —
   the image was already described by a vision model; re-inspecting wastes a
   round trip and adds nothing.
2. Only inspect the saved file when you need a specific detail the block does
   not cover (exact wording, small text, coordinates, precise layout) and the
   user asks for it.
3. If the block has an empty description, treat the image as unavailable and
   tell the user the description failed, or use `vision <path>` to retry.

# Vision vs. text-only models & xd:// devices

1. **Vision-capable models (e.g. Gemini, Claude)**:
   - Have native image support (`input: [text, image]`).
   - Receive image attachments and `read` tool outputs directly as native image payloads.
   - `inspect_image` is automatically deactivated (not mounted under `xd://`) because native vision handles images directly without routing through external vision endpoints.

2. **Text-only models (e.g. DeepSeek)**:
   - Lack native image input (`input: [text]`).
   - Pasted/attached images are auto-described into `<image path="local://...">` blocks using the configured `vision` model role (OpenRouter qwen3.7-flash, local lame fallback).
   - `inspect_image` is automatically mounted under `xd://inspect_image` to delegate ad-hoc image inspection to the `vision` model role:
     `write(path="xd://inspect_image", content={"path": "/tmp/shot.png", "question": "…"})`

3. **Other discoverable xd:// devices (browser, ast_edit, lsp, debug)**:
   - Available across sessions and invoked by writing JSON args to `xd://<tool>`.

# Native Desktop UI/UX & Creation Tool Principles

When creating or working on native desktop apps (Raylib / C++, Lua, Dear ImGui):
1. **Default Template**: Always start from or default to the turnkey Raylib + ImGui + Lua creation tool template in `templates/raylib` (or `skill://scaffold-native-app`).
2. Consult `skill://native-ui-ux`, `skill://scaffold-native-app`, and `skill://imgui-recipes` for interaction standards, blueprints, and UI recipes.
3. **Feel is Priority #1**: 60 FPS / refresh rate locked, input pumped immediately before frame build, zero drawing latency on brush/draw strokes.
4. **3D & 2D Creation Standards**:
   - Unified normal-offset overlays ($\vec{N} \times 0.003$ fill, $\vec{N} \times 0.005$ outline) so face, vertex, and edge selections render crisply over textures with zero Z-fighting.
   - Live GPU mesh rebuilding (`geom.mesh_to_gl`) during modal move (`G`), extrude (`E`), and vertex paint so textures and vertex color gradients remain visible in real time.
   - Mode 1: Vertex selection & move, Mode 2: Edge selection & move, Mode 3: Face selection & extrude/move, Mode 4: 3D Vertex Paint (per-vertex RGB modulation), Mode 5: 2D Texture Paint (offscreen canvas).
   - Native Win32 file picker (`GetOpenFileNameW` with `CoInitializeEx` and `OFN_EXPLORER`).
5. **Navigation & Physics**: Cursor-anchored zoom (mouse world coordinate invariant across zoom), pan via Middle-drag or Space+Left-drag, smooth inertial lerp on camera motion, 3-4px drag deadzones.
6. **Tool Ergonomics**: Single-key shortcuts (V=Select, H=Pan, B=Brush, E=Eraser, R=Rect, C=Circle, G=Grab, S=Scale, Z=Zoom, X=Swap, D=Default, F=Focus), right-click context menus at mouse cursor, informative tooltips with hotkey badges on EVERY button/tool.
7. **Visual Styling**: Modern sleek dark theme (custom palette, rounded corners `WindowRounding=6.0, FrameRounding=4.0, PopupRounding=6.0`, soft borders, amber/azure vivid accents), embedded vector & icon fonts (Inter, JetBrains Mono, icon glyphs) — NEVER default gray ImGui or single-letter text buttons.
8. **State & Safety**: Non-destructive document tree, infinite multi-session undo (`undo.jsonl`) with continuous drag coalescing (`IsItemDeactivatedAfterEdit()`), debounced 300ms autosave + backup rotation.
9. **Headless Verification**: Every project must support `--shot <out.png> [--frames N]` offscreen screenshot capture, `--drive <script.lua>` input injection, and `--test` headless state verification from Day 1.
