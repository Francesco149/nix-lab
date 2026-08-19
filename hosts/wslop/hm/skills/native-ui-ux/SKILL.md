---
name: native-ui-ux
description: Master doctrine for native desktop UI/UX design in ImGui, C++, and Lua. Enforces smooth 60fps feel, direct viewport manipulation (Blender/Godot/Figma standard), cursor-centered navigation, named keycodes, non-destructive undo, autosave, cohesive theme aesthetics, and mandatory interactive smoke test gates.
---

# Native UI/UX Design & Interaction Doctrine

This skill establishes the engineering and interaction standards for building high-performance, beautiful, intuitive native desktop creation tools (ImGui / C++ / Lua).

---

## 1. The "Feel First" Law (Performance & Presentation)

A tool with clunky, sluggish interactions will never be used, no matter how many features it has. Responsiveness and smooth tactile feel are **Priority #1**.

1. **Target 60 FPS / Monitor Refresh Rate with Zero Jitter**:
   - **3D tools**: Raylib 6.0 (GLFW/Vulkan/OpenGL underneath — hardware depth buffer, models, textures, RLSL shaders, lighting) with **rlImGui** bridging Dear ImGui panels into the same context. Complex 3D (meshes, textures, shaders, picking) is Lua-callable via `lp.rl.*` — NO hand-rolled GL.
   - **2D tools**: Raylib `Camera2D` for pan/zoom viewports, textures/images for the canvas, ImGui via rlImGui.
   - **Input Timing**: Always pump OS events *immediately* before building the frame. Never place sleeps, locks, or busy-waits between input polling and frame rendering.
   - **Zero Drawing Latency**: When drawing or brushing, render the in-flight stroke immediately in the current frame. Never wait for stroke completion to show visual feedback.

2. **Camera & Canvas Navigation (The Golden Standard)**:
   - **Scroll = Zoom Centered on Cursor**: Always anchor zoom at the mouse pointer. When the user scrolls at point $(x, y)$, $(x, y)$ in world coordinates must remain stationary under the cursor.
     $$\text{world\_pos} = \frac{\text{mouse\_pos} - \text{pan}}{\text{zoom}}$$
     $$\text{pan}' = \text{mouse\_pos} - \text{world\_pos} \times \text{zoom}'$$
   - **2D scenes — middle-mouse is PAN** (tldraw/Figma/Photoshop language). Middle-drag pans, scroll zooms. No other button meanings.
   - **3D scenes — Godot 3D editor language**:
     - **Middle-drag = TILT / ORBIT** the camera (yaw/pitch around the view center).
     - **Right-drag hold = FPS FLY**: mouse looks (yaw/pitch), WASD moves along camera axes, Q/E (or Space/Ctrl) up/down. Release to stop.
     - **Shift+Middle-drag = 3D PAN**: translate the view center in the view plane.
     - Scroll wheel = dolly (move closer/farther).
   - **Disengage Fit Mode on Pan/Zoom**: Panning or scrolling MUST switch zoom state from `"fit"` to `"custom"` so that pan offsets $(\Delta x, \Delta y)$ are never reset on mouse release.
   - **Smooth Inertial Camera Smoothing**: Use critically damped springs or exponential lerp (`camera = lerp(camera, target_camera, 1.0 - exp(-dt * speed))`) for smooth panning, zooming, orbiting, and flying.

---

## 2. Direct Viewport Manipulation (The Anti-Button Law)

❌ **THE LLM TRAP**: Placing buttons in a sidebar (`[Extrude]`, `[Move]`, `[Scale]`) rather than implementing direct in-viewport manipulation. This results in a tedious, unnatural workflow.

✅ **THE PRO CREATOR STANDARD (Blender / Godot / Figma)**:
1. **Direct Viewport Selection**:
   - Hovering over a face/object/vertex highlights it subtly in the 3D viewport.
   - Left-clicking on a face/object selects it directly via screen-to-world raycasting (Möller–Trumbore intersection).
   - `1`: Vertex Selection Mode, `2`: Edge Selection Mode, `3`: Face Selection Mode.
2. **Modal Transform States (Hotkeys & Mouse Pulling)**:
   - **`G` (Grab / Move)**: Pressing `G` enters interactive move state. Moving the mouse moves the selected face/vertex in 3D in real-time. Left-Click/Enter commits with undo; Right-Click/Escape cancels.
   - **`E` (Extrude)**: Pressing `E` extrudes the face and immediately begins dragging along the face normal $\vec{N}$ following the mouse motion. Left-Click/Enter commits with undo; Right-Click/Escape cancels and deletes the in-flight extrusion.
   - **`S` (Scale)**: Pressing `S` scales the element relative to its centroid.
   - **`F` (Frame / Focus)**: Centers and frames camera on selection.
3. **In-Flight Modal HUD**:
   - When an interactive action is active, display a floating status badge:
     `EXTRUDE: +0.85m  |  Left-Click: Confirm  ·  Right-Click / Esc: Cancel`
4. **Interactive Gizmo Dragging (MANDATORY)**:
   - Gizmo arrows MUST be draggable, not visual-only decoration. See `skill://imgui-recipes` Section 8 for the hit-test + constrained-drag recipe.
   - Every axis gizmo MUST: detect mouse proximity (12px threshold), highlight the hovered axis, drag-constrain movement to the projected screen direction, and commit on release.

**MANDATORY**: Every geometric transform operation (move, scale, rotate, extrude) MUST be implemented as a modal state machine activated by a single-key hotkey, with real-time mouse-following preview, commit on Left-Click/Enter, and cancel on Right-Click/Escape. Sidebar buttons MAY exist as secondary access but MUST NOT be the primary interaction path.

❌ **WRONG** (button-driven, the default LLM output — never do this):
```lua
if ig.button("Extrude") then mesh.extrude_face(doc.mesh, sel, 1.0) end
if ig.button("Move") then obj.pos[1] = obj.pos[1] + 1 end
```

❌ **WRONG** (visual-only gizmo arrows with no drag interaction):
```lua
-- Draws arrows but they do NOTHING when clicked/dragged
ig.dl_add_line(dl, cx, cy, ax, ay, 0.95, 0.2, 0.2, 1.0, 3.0)
ig.dl_add_circle_filled(dl, ax, ay, 4.0, 0.95, 0.2, 0.2, 1.0)
```

✅ **RIGHT** (direct manipulation with modal state + interactive gizmo):
```lua
if not doc.action and ig.is_key_pressed(ig.key.E) and doc.selected_face then
    doc.action = "extrude"
    doc.action_orig = doc.snapshot()  -- PRE-action state for undo
    mesh.extrude_face(doc.mesh, doc.selected_face, 0)
end
if doc.action == "extrude" then
    -- mouse delta → extrusion distance each frame, HUD badge, commit/cancel
end
-- Gizmo: see skill://imgui-recipes Section 8 for hit-test + drag recipe
```
---

## 3. ImGui 1.92+ Keycode Invariant

❌ **NEVER** pass legacy numeric integers (e.g. `46`, `44`, `9`) to `is_key_pressed()` or `is_key_down()`. In ImGui 1.92+, raw integers trigger `Assertion failed: IsNamedKey(key)`.

✅ **ALWAYS** use `ig.key.*` named key constants:
- `ig.key.Space`, `ig.key.Equal` (`+`), `ig.key.Minus` (`-`), `ig.key.F`, `ig.key.G`, `ig.key.E`, `ig.key.S`, `ig.key.Z`, `ig.key.Y`, `ig.key.Delete`, `ig.key.Escape`, `ig.key["0"]`, `ig.key["1"]`, `ig.key["2"]`, `ig.key["3"]`.


---

## 3a. Lua 5.4 Compatibility Invariants

❌ **NEVER** use APIs removed in Lua 5.4:
- `math.pow(base, exp)` → Use `base ^ exp` (the `^` operator). `math.pow` does not exist in Lua 5.4.
- `math.atan2(y, x)` → Use `math.atan(y, x)` (two-argument form).
- `math.ldexp(m, e)` → Use `m * 2.0 ^ e`.
- `math.frexp()` → removed; restructure the algorithm.
- `math.cosh/sinh/tanh` → removed; compute manually if needed.
- `math.log10(x)` → Use `math.log(x, 10)`.
- `unpack()` → Use `table.unpack()`.
- `loadstring()` → Use `load()`.
- `setfenv/getfenv` → removed (Lua 5.1 only).

✅ **ALWAYS** use the `^` operator for exponentiation:
```lua
local factor = 1.15 ^ io.mouse_wheel  -- CORRECT: Lua 5.4
local factor = math.pow(1.15, io.mouse_wheel)  -- WRONG: crashes in Lua 5.4
```

---

## 3b. 3D DrawList Rendering: Painter's Algorithm Required

ImGui DrawList is a **2D immediate-mode API with no Z-buffer**. When rendering 3D meshes via projected triangles (`dl_add_triangle_filled`), faces MUST be sorted back-to-front before drawing. Without this, back faces render on top of front faces.

❌ **WRONG** — drawing faces in array order:
```lua
for f_idx, f in ipairs(doc.mesh.faces) do
    -- project and draw → back faces occlude front faces
end
```

✅ **RIGHT** — painter's algorithm (sort by average Z, farthest first):
```lua
local sorted = {}
for f_idx, f in ipairs(doc.mesh.faces) do
    local pts, avg_z, ok = {}, 0, true
    for _, vi in ipairs(f.verts) do
        local sx, sy, sz = world_to_screen(v.pos[1], v.pos[2], v.pos[3])
        pts[#pts + 1] = { sx, sy, sz }
        avg_z = avg_z + sz
        if sz <= 0 then ok = false end
    end
    if ok and #pts >= 3 then
        sorted[#sorted + 1] = { f_idx = f_idx, f = f, pts = pts, avg_z = avg_z / #pts }
    end
end
table.sort(sorted, function(a, b) return a.avg_z > b.avg_z end) -- far first
for _, sf in ipairs(sorted) do
    -- draw sf.pts triangles, wireframe, gizmos
end

---

## 3c. 3D Line & Grid Rendering: Camera Near-Plane Clipping Required

In perspective projection, points behind the camera ($z_{cam} > 0$ or $w < 0$) invert their $X/Y$ coordinates when divided by $w$.

❌ **WRONG** — projecting raw endpoints and testing `sz > 0`:
```lua
local x1, y1, z1 = world_to_screen(i, 0, -16)
local x2, y2, z2 = world_to_screen(i, 0,  16)
if z1 > 0 and z2 > 0 then
    ig.dl_add_line(dl, x1, y1, x2, y2, ...)  -- Drops entire line when near ground!
end
```

✅ **RIGHT** — clip line segments against the camera near plane in camera space before projecting:
```lua
-- See skill://imgui-recipes Section 9 for the complete draw_line_3d implementation
draw_line_3d(dl, x1, y1, z1, x2, y2, z2, r, g, b, a, thick, cam_eye, cam_fwd, world_to_screen)
```

---

## 3d. Toolbar Layout: Relative Flow Required

❌ **NEVER** hardcode absolute horizontal pixel offsets (e.g. `ig.same_line(390)`) for sequential action buttons in toolbars or ribbons. Button label additions/translations will cause subsequent buttons to overlap.

✅ **ALWAYS** use relative flow with `ig.same_line()` and visual separators (`|`):
```lua
if ig.button("+ Box") then ... end
ig.same_line()
if ig.button("+ Cylinder") then ... end
ig.same_line()
if ig.button("+ Wedge") then ... end
ig.same_line()
if ig.button("+ Stairs") then ... end
ig.same_line()
ig.text_colored("|", 0.35, 0.35, 0.4, 1.0)
ig.same_line()
if ig.button("Undo") then undo.do_undo() end
ig.same_line()
if ig.button("Redo") then undo.do_redo() end
```
```

---

## 3e. Numeric Counters, FPS Readouts, & Monospace Isolation

❌ **NEVER** place fluctuating numeric readouts (FPS, frame times, dimensions) in variable-pitch proportional fonts right next to other dynamic widgets without fixed-width isolation. As the numbers change width each frame, surrounding elements jitter and vibrate visually.

✅ **ALWAYS** isolate numeric meters:
1. Use fixed-width / monospace font (`JetBrains Mono`).
2. Position in a dedicated fixed-width slot or right-aligned anchor.
3. Smooth high-frequency counters (e.g. FPS) with an exponential moving average:
```lua
local cur_fps = io.delta_time > 0 and (1.0 / io.delta_time) or 60.0
avg_fps = avg_fps + (cur_fps - avg_fps) * 0.05
local info = string.format("%d×%d · %2dfps · comp %4.1fms", w, h, math.floor(avg_fps + 0.5), comp_ms)
ig.set_cursor_pos(rect.w - 240, 9)
ig.push_font(1) -- JetBrains Mono
ig.text_colored(info, 0.45, 0.47, 0.52, 1)
ig.pop_font()
```

---

## 3f. 3D Raycast Face Picking & Front-Face Culling

❌ **NEVER** pick 3D faces using 2D screen-space point-in-triangle or arbitrary vertex depth (`v0.z`). On convex or overlapping meshes, back faces will frequently be picked over front faces.

✅ **ALWAYS** use 3D unprojected raycasting with front-face normal validation:
1. Unproject mouse coordinate $(mx, my)$ into a 3D world ray $(origin, dir)$.
2. Cull backfaces: skip any face where $Normal \cdot RayDir \ge 0$.
3. Test front-facing triangles with Möller–Trumbore ray-triangle intersection.
4. Select the face with minimum positive ray distance ($t > 0$).
|---

## 3g. Scoped Begin/End API (Mandatory)

❌ **NEVER** hand-write raw `ig.begin_*` / `ig.end_*` pairs in Lua UI code.

✅ **ALWAYS** use the scoped wrappers (`ig.window`, `ig.child`, `ig.popup`, `ig.popup_modal`, `ig.popup_context_window`, `ig.popup_context_item`, `ig.menu`, `ig.menu_bar`, `ig.table_`, `ig.tab_bar`, `ig.tab_item`, `ig.list_box`, `ig.tree`, `ig.tooltip_`, `ig.group`, `ig.disabled` — see `skill://imgui-recipes` Section 0 for signatures). Each takes a callback as its last argument and guarantees the matching `End` is called on every path, including Lua errors raised inside the body.

❌ **WRONG** (raw begin/end — forget the `End`, or early-return inside the body, and the frame stack leaks):
```lua
if ig.begin_child("inspector", 260, 0, true) then
    ig.text("Selection")
    if doc.selected then
        ig.text(doc.selected.name)
        return  -- leaks open EndChild for the rest of the frame!
    end
end
ig.end_child()
```

✅ **RIGHT** (scoped wrapper — `EndChild` is guaranteed on every path):
```lua
ig.child("inspector", 260, 0, function()
    ig.text("Selection")
    if doc.selected then
        ig.text(doc.selected.name)
        return  -- safe: the wrapper still calls EndChild
    end
end)
```

**Auto-balance safety net**: every scoped call is depth-tracked per category, and `ig_balance_check()` force-closes any unbalanced Begin/End pair at frame end with a warning instead of crashing. It catches errors that slip through — but it is a backstop, never a reason to hand-write raw begin/end. Unbalanced scopes can still clip or misplace content mid-frame, so the review gate is: no raw `ig.begin_*` / `ig.end_*` in committed UI code.

## 3h. Widget Return Conventions (Avoid Silent Snaps)

The binding layer returns FLAT values, not tables, for widgets that mutate a
buffer in place:
- `ig.color_edit3/4`, `ig.color_picker3/4` → `(changed, r, g, b[, a])` —
  NUMBERS. Assigning the second return to a table (`new_c[1]`) is nil-indexed
  → the arithmetic errors, the pcall swallows it, and the picker appears to
  snap back to the default. `ig.slider_float/int`, `drag_float/int` → also
  `(changed, new_value)` flat.
- `ig.get_content_region_avail()` → `(w, h)` — capture BOTH. Keeping only one
  makes full-height hitboxes 6px tall.

## 3i. File Import Doctrine (Drop / Paste / Picker — ONE Pipeline)

Every tool that accepts assets MUST route drag&drop, Ctrl+V paste, and the
file-picker button through the SAME import function (load → validate →
apply), and MUST reject unsupported inputs gracefully (status message, no
state change, no crash):

- Drop: OS event → first path. Paste: clipboard FILE (Windows CF_HDROP via a
  Win32 helper file — never GLFW's clipboard-string path, it errors on
  files/empty) or text path (strip `file://`). Picker: the in-app browser is
  the reliable picker (native dialogs need zenity/kdialog on Linux and can
  silently fail); keep a "System…" button as a bonus.
- Rejection path MUST be tested headlessly: bad path → false, canvas
  unchanged; round-trip → identical pixels.

## 3j. Reference Grid vs Coplanar Geometry

Never place a reference grid coplanar with mesh faces (raylib `DrawGrid` at
y=0 vs a cube bottom at y=0 → edge flicker/z-fighting). Offset the grid
slightly below the geometry (e.g. `GRID_Y = -0.02`).

## 4. ImGui Visual Ergonomics & Theme Aesthetics

Default ImGui looks dated and dull (gray background, bright blue active widgets, sharp corners). Native tools must look premium, modern, and distinct.

### The Modern Dark Theme Specification

```cpp
void ApplyModernDarkTheme() {
    ImGuiStyle& s = ImGui::GetStyle();
    
    // Geometry & Rounding
    s.WindowRounding    = 6.0f;
    s.ChildRounding     = 4.0f;
    s.FrameRounding     = 4.0f;
    s.PopupRounding     = 6.0f;
    s.ScrollbarRounding = 4.0f;
    s.GrabRounding      = 3.0f;
    s.TabRounding       = 4.0f;
    
    // Spacing & Padding
    s.WindowPadding     = ImVec2(8.0f, 8.0f);
    s.FramePadding      = ImVec2(6.0f, 4.0f);
    s.ItemSpacing       = ImVec2(6.0f, 5.0f);
    s.ItemInnerSpacing  = ImVec2(4.0f, 4.0f);
    s.IndentSpacing     = 14.0f;
    s.ScrollbarSize     = 10.0f;
    s.GrabMinSize       = 8.0f;
    
    // Deep Slate Neutral Surfaces with Vivid Accent
    ImVec4* c = s.Colors;
    c[ImGuiCol_WindowBg]             = ImVec4(0.09f, 0.09f, 0.11f, 1.00f);
    c[ImGuiCol_ChildBg]              = ImVec4(0.12f, 0.13f, 0.16f, 1.00f);
    c[ImGuiCol_PopupBg]              = ImVec4(0.11f, 0.11f, 0.14f, 1.00f);
    c[ImGuiCol_Border]               = ImVec4(0.16f, 0.17f, 0.20f, 1.00f);
    c[ImGuiCol_FrameBg]              = ImVec4(0.15f, 0.16f, 0.19f, 1.00f);
    c[ImGuiCol_FrameBgHovered]       = ImVec4(0.21f, 0.23f, 0.27f, 1.00f);
    c[ImGuiCol_FrameBgActive]        = ImVec4(0.26f, 0.28f, 0.33f, 1.00f);
    c[ImGuiCol_CheckMark]            = ImVec4(0.96f, 0.62f, 0.04f, 1.00f);
    c[ImGuiCol_SliderGrab]           = ImVec4(0.96f, 0.62f, 0.04f, 1.00f);
    c[ImGuiCol_SliderGrabActive]     = ImVec4(1.00f, 0.78f, 0.55f, 1.00f);
    c[ImGuiCol_Button]               = ImVec4(0.16f, 0.18f, 0.22f, 1.00f);
    c[ImGuiCol_Header]               = ImVec4(0.20f, 0.23f, 0.28f, 1.00f);
    c[ImGuiCol_HeaderHovered]        = ImVec4(0.25f, 0.29f, 0.35f, 1.00f);
    c[ImGuiCol_HeaderActive]         = ImVec4(0.28f, 0.32f, 0.40f, 1.00f);
    c[ImGuiCol_Separator]            = ImVec4(0.18f, 0.19f, 0.22f, 1.00f);
    c[ImGuiCol_Text]                 = ImVec4(0.90f, 0.90f, 0.93f, 1.00f);
    c[ImGuiCol_TextDisabled]         = ImVec4(0.50f, 0.52f, 0.58f, 1.00f);
}
```

---

## 5. State Safety: Infinite Undo, Autosave & Zero Data Loss

1. **The Undo Coalescing Rule**:
   - Continuous operations (dragging sliders, scrubbing gizmos, painting brush strokes) must **NOT** push an undo state per frame or mouse movement.
   - **Rule**: Capture state on `IsItemActivated()` or start of gesture; push the single undo snapshot to the undo stack only on `IsItemDeactivatedAfterEdit()` or on mouse release.

2. **Cross-Session Undo (`undo.jsonl`)**:
   - Maintain an in-memory ring buffer (e.g. 100 snapshots).
   - Concurrently append snapshot deltas or full state to `<project>/undo.jsonl`.
   - When reopening a project, undo history is preserved across restarts.

3. **Debounced 300ms Autosave**:
   - On every document mutation, mark `doc.dirty = true` and `doc.dirty_time = current_time()`.
   - In the main loop tick: flush to disk atomically when `now - doc.dirty_time >= 0.300`.

---

## 6. Mandatory Interactive UI Smoke Test Gate

Every project repository MUST include a dedicated `test_ui_smoke.lua` that executes inside `make test`:
1. Simulates interactive mouse hovering, dragging, and wheel zooming over the UI.
2. Exercises `ig.key.*` named constants, ensuring no raw integer assertions occur.
3. Tests `reset_mouse_drag_delta`, modal state transitions (extrude/cancel/commit), and drawlist methods.
4. **Any crash, nil call, or ImGui assertion during smoke testing MUST immediately fail `make test`.**
