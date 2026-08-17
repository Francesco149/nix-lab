---
name: imgui-recipes
description: Battle-tested C++ and Lua code recipes for complex ImGui UI patterns: 2D infinite canvas, 3D viewport, floating pill toolbars, resizable splitters, color swatches, layer stacks with drag-and-drop reorder, undo-coalescing sliders, and cursor context menus.
---

# ImGui Interaction & Widget Recipes (C++ & Lua)

Copy-pasteable, robust recipes designed for native creation tools.

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
        local zoom_factor = math.pow(1.15, io.mouse_wheel)
        local new_target_zoom = math.max(canvas.min_zoom, math.min(canvas.max_zoom, canvas.target_zoom * zoom_factor))
        
        -- Anchor mouse world position
        local wx, wy = canvas.screen_to_world(mouse_x, mouse_y)
        canvas.target_zoom = new_target_zoom
        canvas.target_pan.x = mouse_x - wx * new_target_zoom
        canvas.target_pan.y = mouse_y - wy * new_target_zoom
    end
    
    -- 2. Pan via Middle-Mouse or Space+Left-Mouse
    local space_down = ig.is_key_down(ig.Key_Space)
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
    if ig.begin_window("##floating_toolbar", true, flags) then
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
    end
    ig.end_window()
end
```

---

## 3. Layer Stack (With Drag-and-Drop Reorder & Eye Toggle)

```lua
function ui.layer_stack(layers, selected_idx, on_select, on_reorder, on_toggle_vis)
    ig.begin_child("layer_list", 0, 0, true)
    
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
    
    ig.end_child()
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
    if ig.begin_popup_context_window(menu_id, ig.PopupFlags_MouseButtonRight | ig.PopupFlags_NoOpenOverExistingPopup) then
        for _, item in ipairs(items) do
            if item.separator then
                ig.separator()
            else
                if ig.menu_item(item.label, item.shortcut, item.selected, item.enabled ~= false) then
                    item.action()
                end
            end
        end
        ig.end_popup()
    end
end
```
