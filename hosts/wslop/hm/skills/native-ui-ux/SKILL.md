---
name: native-ui-ux
description: Master doctrine for native desktop UI/UX design in ImGui, C++, and Lua. Enforces smooth 60fps feel, direct manipulation, cursor-centered navigation, keyboard shortcuts, non-destructive undo, autosave, cohesive theme aesthetics, and professional tool ergonomics (Figma/tldraw/Godot standard).
---

# Native UI/UX Design & Interaction Doctrine

This skill establishes the engineering and interaction standards for building high-performance, beautiful, intuitive native desktop creation tools (ImGui / C++ / Lua).

---

## 1. The "Feel First" Law (Performance & Presentation)

A tool with clunky, sluggish interactions will never be used, no matter how many features it has. Responsiveness and smooth tactile feel are **Priority #1**.

1. **Target 60 FPS / Monitor Refresh Rate with Zero Jitter**:
   - **Windows (D3D11)**: Use `DXGI_SWAP_EFFECT_FLIP_DISCARD`, 3 swap buffers, DXGI frame latency waitable object (`SetMaximumFrameLatency(1)`), and `Present(1, 0)`.
   - **Input Timing**: Always pump OS events *immediately* before building the frame. Never place sleeps, locks, or busy-waits between input polling and frame rendering.
   - **Zero Drawing Latency**: When drawing or brushing, render the in-flight stroke immediately in the current frame's drawlist. Never wait for stroke completion to show visual feedback.

2. **Camera & Canvas Navigation (The Golden Standard)**:
   - **Scroll = Zoom Centered on Cursor**: Always anchor zoom at the mouse pointer. When the user scrolls at point $(x, y)$, $(x, y)$ in world coordinates must remain stationary under the cursor.
     $$\text{world\_pos} = \frac{\text{mouse\_pos} - \text{pan}}{\text{zoom}}$$
     $$\text{pan}' = \text{mouse\_pos} - \text{world\_pos} \times \text{zoom}'$$
   - **Pan Controls**:
     - **Middle-Mouse Drag**: Universal pan.
     - **Space + Left-Mouse Drag**: Universal pan.
     - **Right-Mouse Drag**: Pan (with a 4px deadzone to distinguish from a Right-Click context menu).
   - **Smooth Inertial Camera Smoothing**: Use critically damped springs or exponential lerp (`camera = lerp(camera, target_camera, 1.0 - exp(-dt * speed))`) for smooth panning and zooming.

---

## 2. Interaction Physics & Direct Manipulation

1. **Drag Deadzones**:
   - Never initiate a drag, marquee selection, or transform on the first mouse down.
   - Enforce a **3px to 4px drag deadzone** (`length(mouse_delta) >= 3.0`). If the user releases within the deadzone, treat it strictly as a click. This prevents accidental 1px moves during rapid clicking.

2. **Single-Key Tool Shortcuts (The Pro Creator Standard)**:
   Every creation tool must have standard single-key hotkeys without modifier clutter:
   - `V`: Pointer / Select / Move tool
   - `H` or `Space (hold)`: Hand / Pan tool
   - `B`: Brush / Paint tool
   - `E`: Eraser tool
   - `R`: Rectangle / Box tool
   - `C`: Circle / Cylinder tool
   - `G`: Grab / Translate (in 3D / canvas)
   - `S`: Scale
   - `R` (or `Alt+R`): Rotate
   - `Z`: Zoom tool (or `Ctrl+Z` undo)
   - `X`: Swap Primary / Secondary colors
   - `D`: Reset to default colors (Black/White or primary palette)
   - `F`: Focus / Frame selected object (smooth center & zoom to bounds)
   - `Escape`: Cancel active drag/tool, deselect all, or drill up one hierarchy level.

3. **Modifier Key Standards**:
   - `Shift + Drag`: Constrain axis (horizontal/vertical lock, 45°/15° angle snap) or lock aspect ratio.
   - `Alt + Drag`: Scale from center (instead of corner) or duplicate-drag.
   - `Ctrl / Cmd + Drag`: Snap to grid or precision step.

4. **Hierarchical Selection (Group Drill-Down)**:
   - Clicking an object inside a group selects the **Group**.
   - Clicking the selected group again drills down into the **Child Object**.
   - Pressing `Escape` or clicking empty space drills back up to the Parent Group.

5. **Context Menus at Cursor**:
   - Right-click anywhere opens a context-sensitive menu *at the mouse cursor position* (`ImGui::OpenPopupOnItemClick`).
   - Never force the user to travel across a 4K screen to reach a frequent action.

---

## 3. ImGui Visual Ergonomics & Theme Aesthetics

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
    s.WindowPadding     = ImVec2(10.0f, 10.0f);
    s.FramePadding      = ImVec2(6.0f, 4.0f);
    s.ItemSpacing       = ImVec2(6.0f, 6.0f);
    s.ItemInnerSpacing  = ImVec2(4.0f, 4.0f);
    s.IndentSpacing     = 14.0f;
    s.ScrollbarSize     = 10.0f;
    s.GrabMinSize       = 8.0f;
    
    // Color Palette: Deep Slate / Neutral Dark with Vivid Accent
    ImVec4* c = s.Colors;
    c[ImGuiCol_WindowBg]             = ImVec4(0.10f, 0.10f, 0.12f, 1.00f); // #1a1a1f
    c[ImGuiCol_ChildBg]              = ImVec4(0.12f, 0.12f, 0.14f, 1.00f); // #1f1f24
    c[ImGuiCol_PopupBg]              = ImVec4(0.13f, 0.13f, 0.16f, 0.98f); // #212129
    c[ImGuiCol_Border]               = ImVec4(0.20f, 0.20f, 0.24f, 1.00f); // #33333d
    c[ImGuiCol_BorderShadow]         = ImVec4(0.00f, 0.00f, 0.00f, 0.00f);
    c[ImGuiCol_FrameBg]              = ImVec4(0.16f, 0.16f, 0.19f, 1.00f); // #292930
    c[ImGuiCol_FrameBgHovered]       = ImVec4(0.22f, 0.22f, 0.27f, 1.00f); // #383845
    c[ImGuiCol_FrameBgActive]        = ImVec4(0.26f, 0.26f, 0.32f, 1.00f); // #424252
    c[ImGuiCol_TitleBg]              = ImVec4(0.09f, 0.09f, 0.11f, 1.00f);
    c[ImGuiCol_TitleBgActive]        = ImVec4(0.12f, 0.12f, 0.15f, 1.00f);
    c[ImGuiCol_TitleBgCollapsed]     = ImVec4(0.08f, 0.08f, 0.10f, 1.00f);
    c[ImGuiCol_MenuBarBg]            = ImVec4(0.11f, 0.11f, 0.13f, 1.00f);
    c[ImGuiCol_ScrollbarBg]          = ImVec4(0.09f, 0.09f, 0.11f, 0.50f);
    c[ImGuiCol_ScrollbarGrab]        = ImVec4(0.24f, 0.24f, 0.30f, 1.00f);
    c[ImGuiCol_ScrollbarGrabHovered] = ImVec4(0.32f, 0.32f, 0.40f, 1.00f);
    c[ImGuiCol_ScrollbarGrabActive]  = ImVec4(0.40f, 0.40f, 0.50f, 1.00f);
    
    // Primary Accent: Vibrant Amber (#f59e0b) or Royal Azure (#3b82f6)
    ImVec4 accent        = ImVec4(0.96f, 0.62f, 0.04f, 1.00f); // Amber Accent
    ImVec4 accentHover   = ImVec4(1.00f, 0.70f, 0.15f, 1.00f);
    ImVec4 accentActive  = ImVec4(0.85f, 0.52f, 0.02f, 1.00f);
    
    c[ImGuiCol_CheckMark]            = accent;
    c[ImGuiCol_SliderGrab]           = accent;
    c[ImGuiCol_SliderGrabActive]     = accentActive;
    c[ImGuiCol_Button]               = ImVec4(0.18f, 0.18f, 0.22f, 1.00f);
    c[ImGuiCol_ButtonHovered]        = ImVec4(0.25f, 0.25f, 0.31f, 1.00f);
    c[ImGuiCol_ButtonActive]         = accentActive;
    c[ImGuiCol_Header]               = ImVec4(0.18f, 0.18f, 0.23f, 1.00f);
    c[ImGuiCol_HeaderHovered]        = ImVec4(0.24f, 0.24f, 0.30f, 1.00f);
    c[ImGuiCol_HeaderActive]         = accentActive;
    c[ImGuiCol_Separator]            = ImVec4(0.20f, 0.20f, 0.24f, 1.00f);
    c[ImGuiCol_SeparatorHovered]     = accentHover;
    c[ImGuiCol_SeparatorActive]      = accentActive;
    c[ImGuiCol_ResizeGrip]           = ImVec4(0.20f, 0.20f, 0.24f, 0.00f);
    c[ImGuiCol_ResizeGripHovered]    = accentHover;
    c[ImGuiCol_ResizeGripActive]     = accentActive;
    c[ImGuiCol_Tab]                  = ImVec4(0.13f, 0.13f, 0.16f, 1.00f);
    c[ImGuiCol_TabHovered]           = ImVec4(0.22f, 0.22f, 0.28f, 1.00f);
    c[ImGuiCol_TabActive]            = ImVec4(0.18f, 0.18f, 0.23f, 1.00f);
    c[ImGuiCol_TabUnfocused]         = ImVec4(0.11f, 0.11f, 0.13f, 1.00f);
    c[ImGuiCol_TabUnfocusedActive]   = ImVec4(0.14f, 0.14f, 0.17f, 1.00f);
    c[ImGuiCol_Text]                 = ImVec4(0.92f, 0.92f, 0.95f, 1.00f); // #ebebf2
    c[ImGuiCol_TextDisabled]         = ImVec4(0.50f, 0.50f, 0.56f, 1.00f); // #80808f
    c[ImGuiCol_TextSelectedBg]       = ImVec4(0.96f, 0.62f, 0.04f, 0.35f);
}
```

### Typography & Fonts
- **Variable Body Font**: Inter (`InterVariable.ttf`) or Shantell Sans for hand-drawn look.
- **Monospace Font**: JetBrains Mono (`JetBrainsMono-Regular.ttf`) for coordinates, dimensions, numeric inputs, code, and debug stats.
- **Icon Glyphs**: Always embed an icon font (Lucide / FontAwesome / Material Icons / custom SVG atlas) or custom vector drawing helper. Never display `[B]` or `[X]` single-letter buttons.

### Informative Tooltips with Keyboard Badges
Every button and tool must show a clear tooltip on hover:
```lua
function ui.tooltip(title, shortcut, description)
    if ig.is_item_hovered() then
        ig.begin_tooltip()
        ig.text_colored(title, 1.0, 1.0, 1.0, 1.0)
        if shortcut then
            ig.same_line()
            ig.text_colored(" (" .. shortcut .. ")", 0.96, 0.62, 0.04, 1.0)
        end
        if description then
            ig.text_colored(description, 0.7, 0.7, 0.75, 1.0)
        end
        ig.end_tooltip()
    end
end
```

---

## 4. State Safety: Infinite Undo, Autosave & Zero Data Loss

1. **The Undo Coalescing Rule**:
   - Continuous operations (dragging a slider, scrubbing a value, dragging an object, painting a brush stroke) must **NOT** push an undo state per frame or mouse movement.
   - Pushing per-mouse-move makes undo unusable (pressing Ctrl+Z steps backward through 60 fractional positions of the same drag).
   - **Rule**: Capture state on `IsItemActivated()` or start of stroke; push the single undo snapshot to the undo stack only on `IsItemDeactivatedAfterEdit()` or on mouse release.

2. **Cross-Session Undo (`undo.jsonl`)**:
   - Maintain an in-memory ring buffer (e.g. 100 snapshots).
   - Concurrently append snapshot deltas or full state to `<project>/undo.jsonl`.
   - When reopening a project, undo history is preserved across restarts.

3. **Debounced 300ms Autosave**:
   - On every document mutation, mark `doc.dirty = true` and `doc.dirty_time = current_time()`.
   - In the main loop tick:
     ```lua
     if doc.dirty and (now - doc.dirty_time) >= 0.300 then
         doc.save()
         doc.dirty = false
     end
     ```
   - Automatic project backups: On save, rotate `<project>/backup.1.json`, `backup.2.json` so power cuts or hard crashes never destroy user work.

4. **Crash Resilience**:
   - In Lua: wrap all panel rendering and tools in `pcall`. If a panel has a bug, log the error to the console / debug overlay and keep the rest of the application running.
   - In C++: attach top-level SEH/VEH (Windows) and signal handlers (Linux) that write a minidump/stack log and flush emergency save state.

---

## 5. Headless Verification & Automation Infrastructure

From **Day 1**, every native app must be testable and visually verifiable headlessly without requiring a human to click around:

1. **`--shot <output.png> [--frames N]`**:
   - Renders $N$ frames to an offscreen buffer, reads back pixels, and writes a PNG.
   - Used for instant visual verification via vision models:
     `read build/shot.png` or inspect via vision tools.

2. **`--eval "..."` or `--lua <script.lua>` or `--tape <tape.lua>`**:
   - Executes arbitrary automation scripts inside the engine context.
   - Simulates synthetic input events (mouse move, click, drag, key tap, shortcut chords).
   - Allows asserting internal document state and UI invariants.

3. **Golden Visual Regression Tests (`make test-golden`)**:
   - Compares rendered output against committed golden baseline images pixel-by-pixel (or perceptual threshold).

---

## 6. Prohibited Anti-Patterns (The LLM Pitfall Checklist)

❌ **NEVER** use default ImGui gray theme without rounded corners and modern color palette.
❌ **NEVER** use single-letter text buttons (`"B"`, `"E"`, `"S"`, `"D"`) — use clean icons with descriptive tooltips and hotkeys.
❌ **NEVER** place raw unconstrained `DragFloat` widgets without step formatting, min/max limits, or visual scrub labels.
❌ **NEVER** zoom into the screen center — zoom must anchor to the cursor.
❌ **NEVER** push undo states on every frame of a drag or slider scrub — coalesce on deactivation.
❌ **NEVER** create modal blocking dialogs for common actions — use inline drawers, floating toolbars, or context popups.
❌ **NEVER** perform heavy IO or synchronous blocking ops in the main frame loop.
❌ **NEVER** omit headless `--shot` and `--test` capabilities.
