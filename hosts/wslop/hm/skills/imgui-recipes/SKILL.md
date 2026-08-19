---
name: imgui-recipes
description: Battle-tested C++ and Lua code recipes for complex ImGui UI patterns: 2D infinite canvas, 3D viewport, floating pill toolbars, resizable splitters, color swatches, layer stacks with drag-and-drop reorder, undo-coalescing sliders, and cursor context menus.
---

# ImGui Interaction & Widget Recipes (C++ & Lua)

Copy-pasteable, robust recipes designed for native creation tools.

---

## 0. Scoped ImGui API (Mandatory)

**ALWAYS** use the scoped wrappers for every Begin/End pair. They take a Lua callback as the last argument, call the matching `End` unconditionally (even when the body raises a Lua error), and are depth-tracked by the frame-end balance checker. Raw `ig.begin_*` / `ig.end_*` functions remain registered ONLY as an escape hatch.

### The Pattern

Instead of pairing a `Begin` with a manually-remembered `End`:

❌ **WRONG** — raw begin/end (easy to forget the `End`; an early `return` inside the body leaks an open scope):
```lua
if ig.begin_child("layer_list", 0, 0, true) then
    -- ... content ...
    -- must remember ig.end_child() on every path
end
ig.end_child()
```

✅ **RIGHT** — scoped wrapper (the wrapper always calls `End` for you, even on Lua errors inside the body):
```lua
ig.child("layer_list", 0, 0, function()
    -- ... content ...  -- no End needed; guaranteed by the wrapper
end)
```

### All Scoped Functions

| Wrapper | Signature (Lua) | Ends |
|---|---|---|
| `ig.window` | `ig.window(name, [flags], fn)` | `end_` |
| `ig.child` | `ig.child(name, [w], [h], [child_flags], [window_flags], fn)` | `end_child` |
| `ig.popup` | `ig.popup(name, fn)` | `end_popup` |
| `ig.popup_modal` | `ig.popup_modal(name, [flags], fn)` | `end_popup` |
| `ig.popup_context_window` | `ig.popup_context_window([id], [flags], fn)` | `end_popup` |
| `ig.popup_context_item` | `ig.popup_context_item([id], [flags], fn)` | `end_popup` |
| `ig.menu` | `ig.menu(name, [enabled], fn)` | `end_menu` |
| `ig.menu_bar` | `ig.menu_bar(fn)` | `end_menu_bar` |
| `ig.table_` | `ig.table_(name, columns, [flags], fn)` | `end_table` |
| `ig.tab_bar` | `ig.tab_bar(name, [flags], fn)` | `end_tab_bar` |
| `ig.tab_item` | `ig.tab_item(name, [flags], fn)` | `end_tab_item` |
| `ig.list_box` | `ig.list_box(name, [w], [h], fn)` | `end_list_box` |
| `ig.tree` | `ig.tree(name, [flags], fn)` | `tree_pop` |
| `ig.tooltip_` | `ig.tooltip_(fn)` | `end_tooltip` |
| `ig.group` | `ig.group(fn)` | `end_group` |
| `ig.disabled` | `ig.disabled(cond, fn)` | `end_disabled` |

Two end policies, both safe:
- **Always-End** (`window`, `child`, `tooltip_`, `group`, `disabled`): `End` is called regardless of the `Begin` result; the body only runs when content is visible.
- **Conditional-End** (`popup*`, `menu`, `menu_bar`, `table_`, `tab_bar`, `tab_item`, `list_box`, `tree`): body and `End` run only when the `Begin` returns true.

### Concrete Examples

```lua
-- Window with flags
ig.window("Inspector", ig.WindowFlags_NoCollapse, function()
    ig.text("Hello")
end)

-- Child with explicit size
ig.child("mesh_list", 240, 320, function()
    for i = 1, #items do
        ig.selectable(items[i], i == sel, 0, 0, 20)
    end
end)

-- Context popup + nested menu
ig.popup_context_window(nil, ig.PopupFlags_MouseButtonRight, function()
    ig.menu("Add", function()
        if ig.menu_item("Box") then add_box() end
        if ig.menu_item("Sphere") then add_sphere() end
    end)
    ig.separator()
    if ig.menu_item("Delete", nil, false, can_delete) then delete_sel() end
end)

-- Modal
ig.popup_modal("Confirm", function()
    ig.text("Delete selected layer?")
    if ig.button("Yes") then do_delete() end
    ig.same_line()
    if ig.button("No") then ig.close_current_popup() end
end)

-- Table
ig.table_("props", 2, ig.TableFlags_Borders, function()
    ig.table_setup_column("Name")
    ig.table_setup_column("Value")
    ig.table_headers_row()
    ig.table_next_row()
    ig.table_next_column(); ig.text("Scale")
    ig.table_next_column(); ig.text("1.0")
end)

-- Tooltip (BeginTooltip has no return value)
ig.button("Hover me")
ig.tooltip_(function()
    ig.text("Fancy multi-line tooltip")
end)

-- Disabled block
ig.disabled(not doc.has_selection, function()
    if ig.button("Extrude") then extrude() end
end)

-- Group (BeginGroup/EndGroup have no return value)
ig.group(function()
    ig.text("Grouped")
    ig.button("A")
    ig.same_line()
    ig.button("B")
end)
```

### Balance Tracker Safety Net

Every scoped call increments a per-category depth counter; `ig_balance_check()` at frame end force-closes any unbalanced pair with a `[ig] WARNING: force-closing unbalanced …` diagnostic instead of corrupting the frame stack. It catches errors that slip through — but it is a backstop, NOT a license to skip `End`, since an unbalanced scope can still clip or misplace content mid-frame.

### Escape Hatch Only

Raw `ig.begin` / `ig.end_`, `ig.begin_child` / `ig.end_child`, `ig.begin_popup` / `ig.end_popup`, and friends remain registered for the rare case a wrapper cannot express (e.g. a `Begin` whose body must span multiple Lua functions or frames). **AVOID them for ordinary UI** — the scoped wrapper is the default and the review standard.

---

## 1. Infinite 2D Canvas (Pan, Cursor Zoom & World Transform)

### Lua Implementation

```lua
local canvas = {
    pan = { x = 0, y = 0 },
    zoom = 1.0,
    target_pan = { x = 0, y = 0 },
    target_zoom = 1.0,
    min_zoom = 0.05,
    max_zoom = 32.0,
    is_panning = false,
    pan_start = { x = 0, y = 0 },
}

function canvas.screen_to_world(sx, sy)
    return (sx - canvas.pan.x) / canvas.zoom, (sy - canvas.pan.y) / canvas.zoom
end

function canvas.world_to_screen(wx, wy)
    return wx * canvas.zoom + canvas.pan.x, wy * canvas.zoom + canvas.pan.y
end

function canvas.update(dt)
    -- Smooth exponential lerp toward target
    local lerp_factor = 1.0 - math.exp(-dt * 20.0)
    canvas.zoom = canvas.zoom + (canvas.target_zoom - canvas.zoom) * lerp_factor
    canvas.pan.x = canvas.pan.x + (canvas.target_pan.x - canvas.pan.x) * lerp_factor
    canvas.pan.y = canvas.pan.y + (canvas.target_pan.y - canvas.pan.y) * lerp_factor
end

function canvas.render_viewport(w, h, draw_callback)
    local avail_w, avail_h = ig.get_content_region_avail()
    local screen_p0 = ig.get_cursor_screen_pos()
    local mouse_x, mouse_y = ig.get_mouse_pos()
    local io = ig.get_io()
    
    -- Invisible button to capture mouse events on canvas
    ig.invisible_button("canvas_viewport", avail_w, avail_h)
    local is_hovered = ig.is_item_hovered()
    local is_active = ig.is_item_active()
    
    -- 1. Zoom centered on cursor
    if is_hovered and io.mouse_wheel ~= 0 then
        local zoom_factor = 1.15 ^ io.mouse_wheel
        local new_target_zoom = math.max(canvas.min_zoom, math.min(canvas.max_zoom, canvas.target_zoom * zoom_factor))
        
        -- Anchor mouse world position
        local wx, wy = canvas.screen_to_world(mouse_x, mouse_y)
        canvas.target_zoom = new_target_zoom
        canvas.target_pan.x = mouse_x - wx * new_target_zoom
        canvas.target_pan.y = mouse_y - wy * new_target_zoom
    end
    
    -- 2. Pan via Middle-Mouse or Space+Left-Mouse
    local space_down = ig.key and ig.is_key_down(ig.key.Space)
    if is_hovered and (ig.is_mouse_clicked(2) or (space_down and ig.is_mouse_clicked(0))) then
        canvas.is_panning = true
        canvas.pan_start.x = mouse_x - canvas.target_pan.x
        canvas.pan_start.y = mouse_y - canvas.target_pan.y
    end
    
    if canvas.is_panning then
        if ig.is_mouse_down(2) or (space_down and ig.is_mouse_down(0)) then
            canvas.target_pan.x = mouse_x - canvas.pan_start.x
            canvas.target_pan.y = mouse_y - canvas.pan_start.y
        else
            canvas.is_panning = false
        end
    end
    
    -- 3. Drawlist rendering with clipping
    local dl = ig.get_window_draw_list()
    ig.push_clip_rect(screen_p0.x, screen_p0.y, screen_p0.x + avail_w, screen_p0.y + avail_h, true)
    
    -- Background grid
    canvas.draw_grid(dl, screen_p0, avail_w, avail_h)
    
    -- Custom content callback
    if draw_callback then
        draw_callback(dl, screen_p0, avail_w, avail_h)
    end
    
    ig.pop_clip_rect()
end

function canvas.draw_grid(dl, p0, w, h)
    local grid_step = 64.0 * canvas.zoom
    while grid_step < 16.0 do grid_step = grid_step * 2.0 end
    while grid_step > 128.0 do grid_step = grid_step / 2.0 end
    
    local start_x = math.fmod(canvas.pan.x - p0.x, grid_step)
    local start_y = math.fmod(canvas.pan.y - p0.y, grid_step)
    
    for x = start_x, w, grid_step do
        dl:add_line(p0.x + x, p0.y, p0.x + x, p0.y + h, 0x15FFFFFF, 1.0)
    end
    for y = start_y, h, grid_step do
        dl:add_line(p0.x, p0.y + y, p0.x + w, p0.y + y, 0x15FFFFFF, 1.0)
    end
end
```

---

## 2. Floating Pill Toolbar (With Active State & Tooltips)

```lua
function ui.floating_toolbar(tools, active_tool_id, on_select)
    local padding = 6.0
    local btn_size = 32.0
    local count = #tools
    local toolbar_w = count * btn_size + (count - 1) * 4.0 + padding * 2.0
    local toolbar_h = btn_size + padding * 2.0
    
    local vp_pos = ig.get_window_pos()
    local vp_size = ig.get_window_size()
    
    -- Float at top-center of viewport
    local pill_x = vp_pos.x + (vp_size.x - toolbar_w) * 0.5
    local pill_y = vp_pos.y + 16.0
    
    ig.set_next_window_pos(pill_x, pill_y, ig.Cond_Always)
    ig.set_next_window_size(toolbar_w, toolbar_h, ig.Cond_Always)
    ig.set_next_window_bg_alpha(0.92)
    
    local flags = ig.WindowFlags_NoDecoration | ig.WindowFlags_NoMove | ig.WindowFlags_NoSavedSettings
    ig.window("##floating_toolbar", flags, function()
        for i, tool in ipairs(tools) do
            if i > 1 then ig.same_line(0, 4.0) end
            
            local is_active = (tool.id == active_tool_id)
            if is_active then
                ig.push_style_color(ig.Col_Button, 0.96, 0.62, 0.04, 1.0)
                ig.push_style_color(ig.Col_Text, 0.1, 0.1, 0.12, 1.0)
            end
            
            if ig.button(tool.icon_or_label .. "##" .. tool.id, btn_size, btn_size) then
                on_select(tool.id)
            end
            
            if is_active then
                ig.pop_style_color(2)
            end
            
            ui.tooltip(tool.name, tool.shortcut, tool.desc)
        end
    end)
end
```

---

## 3. Layer Stack (With Drag-and-Drop Reorder & Eye Toggle)

```lua
function ui.layer_stack(layers, selected_idx, on_select, on_reorder, on_toggle_vis)
    ig.child("layer_list", 0, 0, function()
    
        for i = #layers, 1, -1 do -- Top layers displayed first
            local layer = layers[i]
            ig.push_id(layer.id or i)
            
            -- Visibility Eye Button
            local eye_icon = layer.visible and "👁" or " "
            if ig.button(eye_icon .. "##vis", 24, 24) then
                on_toggle_vis(i)
            end
            ui.tooltip("Toggle Visibility", nil, "Show or hide this layer")
            
            ig.same_line()
            
            -- Selectable layer row
            local is_selected = (i == selected_idx)
            if ig.selectable(layer.name .. "##row", is_selected, ig.SelectableFlags_AllowDoubleClick, 0, 24) then
                on_select(i)
            end
            
            -- Drag-and-Drop Source
            if ig.begin_drag_drop_source(ig.DragDropFlags_None) then
                ig.set_drag_drop_payload("LAYER_INDEX", tostring(i))
                ig.text("Move " .. layer.name)
                ig.end_drag_drop_source()
            end
            
            -- Drag-and-Drop Target
            if ig.begin_drag_drop_target() then
                local payload = ig.accept_drag_drop_payload("LAYER_INDEX")
                if payload then
                    local from_idx = tonumber(payload)
                    if from_idx and from_idx ~= i then
                        on_reorder(from_idx, i)
                    end
                end
                ig.end_drag_drop_target()
            end
            
            ig.pop_id()
        end
    
    end)
end
```

---

## 4. Undo-Coalescing Slider & Scrubbing Pattern

Continuous dragging must push only a single undo state when released:

```lua
local slider_active_before = false

function ui.undoable_slider_float(label, val, min_val, max_val, on_change, on_commit_undo)
    local changed, new_val = ig.slider_float(label, val, min_val, max_val)
    if changed then
        on_change(new_val)
    end
    
    -- Detect completion of continuous drag
    if ig.is_item_deactivated_after_edit() then
        on_commit_undo()
    end
    
    return changed, new_val
end
```

---

## 5. Context-Sensitive Right-Click Menu at Mouse Cursor

```lua
function ui.context_menu(menu_id, items)
    ig.popup_context_window(menu_id, ig.PopupFlags_MouseButtonRight | ig.PopupFlags_NoOpenOverExistingPopup, function()
        for _, item in ipairs(items) do
            if item.separator then
                ig.separator()
            else
                if ig.menu_item(item.label, item.shortcut, item.selected, item.enabled ~= false) then
                    item.action()
                end
            end
        end
    end)
end

---

## 6. Direct Manipulation Modal Transform State Machine (Blender/Figma Standard)

Eliminates clunky button-based manipulation by handling hotkey triggers, live mouse pulling, and commit/cancel states:

```lua
-- In preview.lua / tool state machine
local modal = {
    action = nil, -- nil, "extrude", "move", "scale"
    orig_state = nil,
    drag_start = nil,
}

function modal.handle_triggers(doc, is_hovered, mx, my)
    if not is_hovered or modal.action or not doc.selected_face then return end
    local io = ig.get_io()
    if io.want_text_input then return end

    -- 'E' -> Extrude Face
    if ig.key and ig.is_key_pressed(ig.key.E) and not io.key_ctrl then
        modal.action = "extrude"
        modal.orig_state = doc.snapshot() -- Capture PRE-ACTION state
        modal.drag_start = { mx, my }
        mesh.extrude_face(doc.mesh, doc.selected_face, 0.0) -- Start extrusion at 0
    end

    -- 'G' -> Grab / Move Selection
    if ig.key and ig.is_key_pressed(ig.key.G) then
        modal.action = "move"
        modal.orig_state = doc.snapshot()
        modal.drag_start = { mx, my }
    end
end

function modal.update_and_render_hud(doc, undo, mx, my, avail_w, avail_h, x0, y0)
    if not modal.action then return end
    local io = ig.get_io()
    local dl = ig.get_window_draw_list()

    -- Apply real-time transformation from mouse motion
    local start_m = modal.drag_start or { mx, my }
    local dy = (start_m[2] - my) * 0.02
    if modal.action == "extrude" and doc.mesh and doc.selected_face then
        -- Pull face along normal in real-time
        mesh.set_extrude_distance(doc.mesh, doc.selected_face, modal.orig_state, dy)
    end

    -- Confirm on Left-Click / Enter
    if ig.is_mouse_clicked(0) or (ig.key and ig.is_key_pressed(ig.key.Enter)) then
        undo.push_state(modal.action:upper() .. " Face", modal.orig_state)
        modal.action = nil
        modal.orig_state = nil
        doc.mark_dirty()
    end

    -- Cancel on Right-Click / Escape
    if ig.is_mouse_clicked(1) or (ig.key and ig.is_key_pressed(ig.key.Escape)) then
        doc.restore(modal.orig_state)
        modal.action = nil
        modal.orig_state = nil
    end

    -- Render In-Flight Floating HUD Status Badge
    if modal.action then
        local hud_text = string.format("%s: %+.2fm  |  LClick/Enter: Confirm  ·  RClick/Esc: Cancel",
            modal.action:upper(), dy)
        local tw = ig.calc_text_size(hud_text)
        local hx = x0 + (avail_w - tw) * 0.5
        local hy = y0 + 16.0
        ig.dl_add_rect_filled(dl, hx - 12, hy - 4, hx + tw + 12, hy + 24, 0.12, 0.13, 0.16, 0.95)
        ig.dl_add_text(dl, hx, hy, 0.96, 0.62, 0.04, 1.0, hud_text)
    end
end
```

---

## 7. 3D DrawList Rendering with Painter's Algorithm (Depth Sorting)

ImGui DrawList has **no Z-buffer**. Rendering 3D meshes via projected triangles requires sorting faces back-to-front (painter's algorithm) before drawing. Without this, back faces render on top of front faces.

```lua
function render_mesh_sorted(dl, doc, world_to_screen, mesh)
    -- Phase 1: Project all faces, compute average depth
    local sorted_faces = {}
    for f_idx, f in ipairs(doc.mesh.faces) do
        local pts = {}
        local all_front = true
        local avg_z = 0
        for _, vi in ipairs(f.verts) do
            local v = doc.mesh.vertices[vi]
            if v and v.pos then
                local sx, sy, sz = world_to_screen(v.pos[1], v.pos[2], v.pos[3])
                pts[#pts + 1] = { sx, sy, sz }
                avg_z = avg_z + sz
                if sz <= 0 then all_front = false end
            end
        end
        if all_front and #pts >= 3 then
            avg_z = avg_z / #pts
            sorted_faces[#sorted_faces + 1] = {
                f_idx = f_idx, f = f, pts = pts, avg_z = avg_z
            }
        end
    end

    -- Phase 2: Sort farthest-first (larger Z = farther from camera)
    table.sort(sorted_faces, function(a, b) return a.avg_z > b.avg_z end)

    -- Phase 3: Draw in sorted order
    for _, sf in ipairs(sorted_faces) do
        local f_idx, f, pts = sf.f_idx, sf.f, sf.pts
        local is_selected = (f_idx == doc.selected_face)

        -- Compute face normal for lighting
        local norm = f.normal or mesh.calculate_face_normal(doc.mesh, f)
        local light_dot = math.max(0.15, norm[1] * 0.5 + norm[2] * 0.7 + norm[3] * 0.5)

        local r = is_selected and 0.86 or (0.45 * light_dot)
        local g = is_selected and 0.56 or (0.50 * light_dot)
        local b = is_selected and 0.04 or (0.60 * light_dot)

        -- Filled triangles (fan from first vertex for quads)
        ig.dl_add_triangle_filled(dl,
            pts[1][1], pts[1][2], pts[2][1], pts[2][2], pts[3][1], pts[3][2],
            r, g, b, 0.95)
        if #pts == 4 then
            ig.dl_add_triangle_filled(dl,
                pts[1][1], pts[1][2], pts[3][1], pts[3][2], pts[4][1], pts[4][2],
                r, g, b, 0.95)
        end

        -- Wireframe edges
        for i = 1, #pts do
            local ni = (i % #pts) + 1
            ig.dl_add_line(dl, pts[i][1], pts[i][2], pts[ni][1], pts[ni][2],
                0.28, 0.32, 0.40, 0.85, is_selected and 2.5 or 1.0)
        end
    end
end
```

---

## 8. Interactive 3D Axis Gizmo with Mouse Drag (Move/Scale)

Visual-only gizmo arrows are insufficient. Gizmo axes MUST be draggable to move/scale objects directly in the viewport. This recipe implements hit-testing on projected axis lines and constrained dragging.

```lua
local gizmo = {
    active_axis = nil,  -- "x", "y", "z", or nil
    drag_origin = nil,  -- world position at drag start
    drag_start_mouse = nil,
}

function gizmo.draw_and_interact(dl, obj, world_to_screen, screen_to_ray, mx, my, is_hovered)
    local bx, by, bz = obj.pos[1], obj.pos[2], obj.pos[3]
    local g_len = 1.5

    -- Project axis endpoints
    local gc_x, gc_y, gc_z = world_to_screen(bx, by, bz)
    local gx_x, gx_y, gx_z = world_to_screen(bx + g_len, by, bz)
    local gy_x, gy_y, gy_z = world_to_screen(bx, by + g_len, bz)
    local gz_x, gz_y, gz_z = world_to_screen(bx, by, bz + g_len)

    if gc_z <= 0 then return end

    -- Axis definitions: {endpoint_screen, color, name}
    local axes = {
        { gx_x, gx_y, 0.95, 0.2, 0.2, "x" },
        { gy_x, gy_y, 0.2, 0.95, 0.2, "y" },
        { gz_x, gz_y, 0.2, 0.5, 0.95, "z" },
    }

    -- Hit test: distance from mouse to axis line segment
    local function point_to_seg_dist(px, py, ax, ay, bx2, by2)
        local dx, dy = bx2 - ax, by2 - ay
        local len_sq = dx * dx + dy * dy
        if len_sq < 1e-6 then return math.huge end
        local t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len_sq))
        local cx2, cy2 = ax + t * dx, ay + t * dy
        return math.sqrt((px - cx2) ^ 2 + (py - cy2) ^ 2)
    end

    -- Start drag on click near axis
    if is_hovered and ig.is_mouse_clicked(0) and not gizmo.active_axis then
        local best_dist, best_axis = 12.0, nil -- 12px hit threshold
        for _, a in ipairs(axes) do
            local d = point_to_seg_dist(mx, my, gc_x, gc_y, a[1], a[2])
            if d < best_dist then best_dist = d; best_axis = a[6] end
        end
        if best_axis then
            gizmo.active_axis = best_axis
            gizmo.drag_origin = { bx, by, bz }
            gizmo.drag_start_mouse = { mx, my }
        end
    end

    -- Apply constrained drag
    if gizmo.active_axis and ig.is_mouse_down(0) then
        local dmx = mx - gizmo.drag_start_mouse[1]
        local dmy = my - gizmo.drag_start_mouse[2]
        -- Project mouse delta onto axis screen direction
        local ax_info = axes[gizmo.active_axis == "x" and 1 or (gizmo.active_axis == "y" and 2 or 3)]
        local ax_dx = ax_info[1] - gc_x
        local ax_dy = ax_info[2] - gc_y
        local ax_len = math.sqrt(ax_dx * ax_dx + ax_dy * ax_dy)
        if ax_len > 1e-3 then
            local proj = (dmx * ax_dx + dmy * ax_dy) / ax_len
            local world_scale = g_len / ax_len -- screen px to world units
            local delta = proj * world_scale
            local idx = gizmo.active_axis == "x" and 1 or (gizmo.active_axis == "y" and 2 or 3)
            obj.pos[idx] = gizmo.drag_origin[idx] + delta
        end
    else
        if gizmo.active_axis then
            gizmo.active_axis = nil -- commit on release
        end
    end

    -- Draw axes (highlight active)
    for _, a in ipairs(axes) do
        local is_active = (gizmo.active_axis == a[6])
        local thick = is_active and 4.0 or 3.0
        local alpha = is_active and 1.0 or 0.85
        ig.dl_add_line(dl, gc_x, gc_y, a[1], a[2], a[3], a[4], a[5], alpha, thick)
        ig.dl_add_circle_filled(dl, a[1], a[2], is_active and 6.0 or 4.0, a[3], a[4], a[5], alpha)
    end
end
```


---

## 9. 3D Line & Grid Drawing with Near-Plane Clipping

In perspective projection, points behind the camera ($z_{cam} > 0$ or $w < 0$) invert their $X/Y$ coordinates when divided by $w$. If a 3D line segment has one endpoint in front of the camera and one endpoint behind the camera:
1. Checking `sz > 0` on both endpoints drops the entire line as soon as one end goes behind the camera near plane (causing grid lines to vanish near the ground or during camera rotation).
2. Projecting unclipped endpoints connects the valid point to an inverted point on the opposite side of the screen, creating stray lines that shoot across the viewport to a fake horizon vanishing point.

### Recipe: Camera-Space Near-Plane Line Clipping
```lua
-- Clips 3D line segment against camera near plane before projection
local function draw_line_3d(dl, x1, y1, z1, x2, y2, z2, r, g, b, a, thickness, eye, fwd, world_to_screen, near_plane)
    near_plane = near_plane or 0.15
    local d1 = (x1 - eye[1]) * fwd[1] + (y1 - eye[2]) * fwd[2] + (z1 - eye[3]) * fwd[3]
    local d2 = (x2 - eye[1]) * fwd[1] + (y2 - eye[2]) * fwd[2] + (z2 - eye[3]) * fwd[3]

    if d1 < near_plane and d2 < near_plane then
        return -- both endpoints behind near plane: cull completely
    end

    local px1, py1, pz1 = x1, y1, z1
    local px2, py2, pz2 = x2, y2, z2

    if d1 < near_plane then
        local t = (near_plane - d1) / (d2 - d1)
        px1 = x1 + t * (x2 - x1)
        py1 = y1 + t * (y2 - y1)
        pz1 = z1 + t * (z2 - z1)
    elseif d2 < near_plane then
        local t = (near_plane - d1) / (d2 - d1)
        px2 = x1 + t * (x2 - x1)
        py2 = y1 + t * (y2 - y1)
        pz2 = z1 + t * (z2 - z1)
    end

    local s1x, s1y, s1z = world_to_screen(px1, py1, pz1)
    local s2x, s2y, s2z = world_to_screen(px2, py2, pz2)

    if s1z > 0 and s2z > 0 then
        ig.dl_add_line(dl, s1x, s1y, s2x, s2y, r, g, b, a, thickness or 1.0)
    end
end
```

---

## 10. Toolbar Sequential Layout & Relative Spacing

❌ **NEVER** use hardcoded absolute horizontal coordinates (e.g. `ig.same_line(390)`) for sequential toolbar buttons. Adding or changing button labels causes subsequent buttons to overlap and clobber each other.

✅ **ALWAYS** use relative flow with `ig.same_line()` and separators:
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
Right-aligned items (such as Export or Settings) should compute offsets relative to the right edge (`dw - 180`):
```lua
ig.same_line(dw - 180)
if ig.button("Export (.tscn)") then ... end
```
**CRITICAL**: Gizmo arrows that only draw lines without drag interaction are useless decoration. Every gizmo MUST support mouse drag with axis-constrained movement. The recipe above provides: hit-testing → constrained drag → visual feedback → commit on release.

---

## 11. Resizable Side Panel (Godot-Inspector Splitter)

❌ **NEVER** implement a resize strip as a screen-space manual hit-test outside
the ImGui window — ImGui windows overlap it, clicks pass through, the hover
highlight bleeds under/over the window, and the cursor gets stuck.

✅ **ALWAYS** make the handle a REAL ImGui widget INSIDE the window: a 6px
`invisible_button` in a child column, with the content in a sibling child via
`ig.same_line()`. ImGui then owns hover/click capture (no click-through), the
highlight is clipped to the handle child, and the cursor resets on leave.

```lua
-- sidebar_w is module state (clamp 200..640)
ig.window("##sidebar", 1 + 2 + 32, function()
    ig.child("##splitter", 6, 0, 0, function()          -- 6px handle column
        local sx, sy = ig.get_cursor_screen_pos()
        local dl = ig.get_window_draw_list()
        local aw, ah = ig.get_content_region_avail()    -- RETURNS TWO VALUES
        ig.invisible_button("##resize_handle", 6, math.max(ah, 1))
        local on = ig.is_item_hovered()
        if on and ig.is_mouse_clicked(0) then resize_active = true end
        if not ig.is_mouse_down(0) then resize_active = false end
        if resize_active then
            local dx = rl.get_mouse_delta()             -- or ig.get_mouse_delta
            sidebar_w = clamp(sidebar_w - dx, 200, 640)
        end
        if on or resize_active then
            rl.set_mouse_cursor(rl.CURSOR_RESIZE_EW)
            ig.dl_add_rect_filled(dl, sx, sy, sx + 6, sy + ah, 0.96, 0.65, 0.12, 0.85)
        else
            rl.set_mouse_cursor(rl.CURSOR_DEFAULT)     -- never leave it stuck
        end
    end)
    ig.same_line()
    ig.child("##content", 0, 0, 0, function()          -- scrolls by default
        -- ... panel body ...
    end)
end)
```
The drag LATCHES (`resize_active`) so the cursor may leave the 6px handle
mid-drag. `get_content_region_avail()` returns `(w, h)` — capturing only one
makes the handle 6px TALL (invisible). Same trap: `color_edit3/4` return
`(changed, r, g, b[, a])` — numbers, NOT a table.

---

## 12. Reference Grid vs Coplanar Geometry (Z-Fighting)

Never draw a reference grid coplanar with mesh geometry (raylib's `DrawGrid`
sits at y=0 — a cube's bottom face is y=0 → the edges flicker). Draw the grid
slightly below with manual lines:
```lua
local GRID_Y = -0.02
for i = -10, 10 do
    local alpha = (i % 5 == 0) and 90 or 30
    rl.draw_line_3d(i, GRID_Y, -10, i, GRID_Y, 10, 200, 200, 200, alpha)
    rl.draw_line_3d(-10, GRID_Y, i, 10, GRID_Y, i, 200, 200, 200, alpha)
end
```
