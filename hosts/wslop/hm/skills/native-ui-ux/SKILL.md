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
   - **Backend**: Use `SDL3` + `SDL_Renderer` (`imgui_impl_sdlrenderer3.h`), which automatically uses **Direct3D 11 (`d3d11`)** on Windows (Windows 7 SP1+ compatible) and **Vulkan / OpenGL** on Linux.
   - **Input Timing**: Always pump OS events *immediately* before building the frame. Never place sleeps, locks, or busy-waits between input polling and frame rendering.
   - **Zero Drawing Latency**: When drawing or brushing, render the in-flight stroke immediately in the current frame's drawlist. Never wait for stroke completion to show visual feedback.

2. **Camera & Canvas Navigation (The Golden Standard)**:
   - **Scroll = Zoom Centered on Cursor**: Always anchor zoom at the mouse pointer. When the user scrolls at point $(x, y)$, $(x, y)$ in world coordinates must remain stationary under the cursor.
     $$\text{world\_pos} = \frac{\text{mouse\_pos} - \text{pan}}{\text{zoom}}$$
     $$\text{pan}' = \text{mouse\_pos} - \text{world\_pos} \times \text{zoom}'$$
   - **Disengage Fit Mode on Pan/Zoom**: Panning or scrolling MUST switch zoom state from `"fit"` to `"custom"` so that pan offsets $(\Delta x, \Delta y)$ are never reset on mouse release.
   - **Standard Pan Controls**:
     - **Middle-Mouse Drag**: Universal pan.
     - **Space + Left-Mouse Drag**: Universal pan.
     - **Right-Mouse Drag**: Pan (with a 4px deadzone to distinguish from a Right-Click context menu).
   - **Smooth Inertial Camera Smoothing**: Use critically damped springs or exponential lerp (`camera = lerp(camera, target_camera, 1.0 - exp(-dt * speed))`) for smooth panning and zooming.

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

---

## 3. ImGui 1.92+ Keycode Invariant

❌ **NEVER** pass legacy numeric integers (e.g. `46`, `44`, `9`) to `is_key_pressed()` or `is_key_down()`. In ImGui 1.92+, raw integers trigger `Assertion failed: IsNamedKey(key)`.

✅ **ALWAYS** use `ig.key.*` named key constants:
- `ig.key.Space`, `ig.key.Equal` (`+`), `ig.key.Minus` (`-`), `ig.key.F`, `ig.key.G`, `ig.key.E`, `ig.key.S`, `ig.key.Z`, `ig.key.Y`, `ig.key.Delete`, `ig.key.Escape`, `ig.key["0"]`, `ig.key["1"]`, `ig.key["2"]`, `ig.key["3"]`.

---

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
