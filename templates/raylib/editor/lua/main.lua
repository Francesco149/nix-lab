-- editor/lua/main.lua — CubeForge (2D + 3D) (Raylib + ImGui + Lua)
--
-- Features:
-- 1. 3D Viewport with Tilt (MMB), 3D Pan (Shift+MMB), Fly (RMB+WASD/QE), Dolly (Wheel), Inertial damping (~22/s)
-- 2. Primitive spawning (+ Box, + Cylinder)
-- 3. Face selection via GetScreenToWorldRay + Möller–Trumbore (front-face culling)
-- 4. Modal Extrude (E): live mouse pulling along normal, LClick/Enter commit, RClick/Esc cancel, floating HUD
-- 5. Modal Move (G): live mouse pulling in view plane, commit/cancel, floating HUD
-- 6. Vertex Painting (Mode 4 / B): brush radius/color, stroke coalescing, 3D vertex display
-- 7. ImGui Side panel: mode pills (1..5), brush settings, hotkey reference, scoped wrappers
-- 8. Snapshot Undo/Redo (Ctrl+Z / Ctrl+Y)
-- 9. Wavefront OBJ Export (Button / Ctrl+E)
-- 10. 2D Texture Paint (Mode 5): the viewport becomes a 512x512 canvas view
--     (lp.cam2d; MMB pan, wheel cursor-anchored zoom, LMB stamps). The canvas
--     texture is bound to the active 3D mesh via lp.tex.apply_to_model, so
--     painting shows up on the cube — 2D and 3D in ONE codebase.

local ig = lp.ig
local rl = lp.rl
local geom = require("geom")
local undo = require("undo")
local doc = require("doc")

-- ── Camera State ────────────────────────────────────────────────────────────
local cam = {
    yaw = 45.0,
    pitch = 30.0,
    dist = 8.0,
    target = { 0, 1.0, 0 },
    -- Smooth targets for exponential damping
    target_yaw = 45.0,
    target_pitch = 30.0,
    target_dist = 8.0,
    target_pos = { 0, 1.0, 0 },
    eye = { 5, 5, 5 },
}

-- ── 2D Camera State ─────────────────────────────────────────────────────────
-- 2D doctrine: MMB pans, wheel zooms anchored at the cursor. The Lua table is
-- the single source of truth; lp.cam2d.set keeps the C++ Camera2D in sync so
-- lp.rl.screen_to_world / begin_mode2d use the exact same transform.
local cam2d = { pan = { 256, 256 }, zoom = 1.0 }

-- Right sidebar width (resizable via the left-edge drag strip).
local sidebar_w = 280
local show_perf_hud = false
local fps_smooth = 60.0
local frame_history = {}
local fps_limit_idx = 1
local FPS_LIMITS = {
    { label = "VSync", fps = 0 },
    { label = "240 FPS", fps = 240 },
    { label = "144 FPS", fps = 144 },
    { label = "120 FPS", fps = 120 },
    { label = "60 FPS", fps = 60 },
    { label = "Unlimited", fps = -1 },
}
local function sync_cam2d()
    lp.cam2d.set(cam2d.pan[1], cam2d.pan[2], cam2d.zoom)
end

local function deg2rad(d) return d * math.pi / 180.0 end
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Icon lookup helper with safe fallback
local function ic(name, fallback)
    if ig.icon and ig.icon[name] then
        return ig.icon[name] .. " "
    end
    return fallback and (fallback .. " ") or ""
end
-- ── Deferred Scene Setup (keeps --test GL-free) ─────────────────────────────
local scene_ready = false
local function setup_scene()
    if scene_ready then return end
    scene_ready = true
    _G.gl_ready = true  -- GL is live; model rebuilds are now safe (--test stays GL-free)
    -- Initialize default box if not present
    if #doc.meshes == 0 then
        doc.init_default()
    end
    -- GPU resources (GL is live here — first rendered frame):
    -- 1) the default box gets a GPU model + perlin texture (default look)
    local m1 = doc.meshes[1]
    if m1 and not m1.model_id then
        doc.perlin_tex_id = rl.load_texture_perlin(256, 256, 2.0)
        m1.tex_binding = { kind = "perlin" }  -- survives model rebuilds
        doc.rebuild_model(1)
    end
    -- 2) the offscreen 512x512 paint canvas (white)
    doc.canvas_init()
end

-- ── GPU mesh registry (textured render path) ────────────────────────────────
-- Meshes that are still pristine primitives get a raylib Model so the canvas
-- (or perlin) texture can be shown on them. Geometry edits drop the model
-- (flat-shaded fallback); restored snapshots clone without GPU ids.
local function ensure_mesh_model(mesh, m_idx)
    if mesh.model_id then return end
    doc.rebuild_model(m_idx)
end

-- Enter 2D texture-paint mode: the canvas becomes the active mesh's texture.
local function enter_texture_paint()
    setup_scene()
    doc.canvas_init()
    local m_idx = doc.selected_mesh_idx or 1
    local mesh = doc.meshes[m_idx]
    if mesh then
        ensure_mesh_model(mesh, m_idx)
        doc.canvas_apply_to(m_idx)
    end
    doc.mode = 5
    doc.status_msg = "Mode: Texture Paint (2D) — MMB Pan, Wheel Zoom"
end

local MODE_NAMES = { "Vertex", "Edge", "Face", "Vertex Paint", "Texture Paint (2D)" }
local function set_mode(m)
    if m == 5 then
        enter_texture_paint()
    else
        doc.mode = m
        doc.status_msg = "Mode: " .. (MODE_NAMES[m] or tostring(m))
    end
end

-- Resize handling doctrine:
--   CHEAP per-frame state (camera aspect, viewport rect, cam2d offset) MUST
--   read the live window size every frame — raylib's Camera3D does this
--   internally, and cam2d syncs per frame, so nothing stretches permanently.
--   HEAVY work on resize (texture re-upload, cache/geometry rebuilds) MUST be
--   debounced: run only after the size stops changing for ~120 ms.
local resize_debounce = { last_w = 0, last_h = 0, timer = 0 }
local function resize_settled(dt)
    local sw, sh = rl.get_screen_size()
    if sw ~= resize_debounce.last_w or sh ~= resize_debounce.last_h then
        resize_debounce.last_w, resize_debounce.last_h = sw, sh
        resize_debounce.timer = 0.12
        return false
    end
    if resize_debounce.timer > 0 then
        resize_debounce.timer = resize_debounce.timer - (dt or 0.016)
        if resize_debounce.timer <= 0 then return true end
    end
    return false
end

-- ── 2D Canvas Input & Rendering (Mode 5) ────────────────────────────────────
-- 2D doctrine: MMB pans the view, wheel zooms anchored at the cursor, LMB
-- paints the canvas in world space (the same world the cube lives in — the
-- canvas is just another surface, and lp.tex.apply_to_model bridges it to 3D).
local function handle_canvas_input(mx, my, sw, sh, io)
    local panel_w = math.max(180, math.min(sidebar_w, math.max(180, sw - 120)))
    local vp_w = math.max(60, sw - panel_w)
    local tb_w = math.min(540, vp_w - 16)
    local tb_x = math.max(8, (vp_w - tb_w) * 0.5)
    local over_tb = (my <= 58 and mx >= tb_x and mx <= tb_x + tb_w)
    local over_ui = (mx >= sw - panel_w - 8) or over_tb
    if over_ui and io.want_capture_mouse then return end

    -- Wheel: cursor-anchored zoom (the world point under the cursor stays put).
    -- raylib wheel: positive = scroll up = zoom IN.
    local wheel = rl.get_mouse_wheel()
    if wheel ~= 0 then
        local wx, wy = rl.screen_to_world(mx, my)
        cam2d.zoom = clamp(cam2d.zoom * (1.15 ^ wheel), 0.1, 16.0)
        cam2d.pan[1] = wx - (mx - sw * 0.5) / cam2d.zoom
        cam2d.pan[2] = wy - (my - sh * 0.5) / cam2d.zoom
        sync_cam2d()
    end

    -- MMB: pan (content follows the drag, scaled by zoom)
    if rl.is_mouse_button_down(rl.MOUSE_MIDDLE) then
        local dx, dy = rl.get_mouse_delta()
        cam2d.pan[1] = cam2d.pan[1] - dx / cam2d.zoom
        cam2d.pan[2] = cam2d.pan[2] - dy / cam2d.zoom
        sync_cam2d()
    end

    -- LMB: paint a stroke on the canvas
    if not over_ui then
        if rl.is_mouse_button_down(rl.MOUSE_LEFT) then
            local wx, wy = rl.screen_to_world(mx, my)
            doc.canvas_stroke(wx, wy)
        elseif doc.canvas.stroke_active then
            doc.canvas_stroke_end()
        end
    end
end

local function draw_canvas_2d()
    local tid = doc.canvas.tex_id
    if not tid then return end
    sync_cam2d()
    -- Live stroke feedback: push the CPU Image to the GPU while painting
    if doc.canvas.stroke_active then
        lp.tex.upload(tid)
    end
    rl.begin_mode2d()
    -- Canvas frame (backdrop + border) in world space
    rl.draw_rect_2d(-5, -5, 522, 522, 30, 28, 34, 255)
    rl.draw_rect_2d(-2, -2, 516, 516, 96, 82, 58, 255)
    rl.draw_texture(tid, 0, 0, 512, 512)
    -- Brush cursor ring (world space)
    local mx, my = rl.get_mouse_pos()
    local wx, wy = rl.screen_to_world(mx, my)
    rl.draw_circle_lines_2d(wx, wy, doc.brush_px(), 1.5, 250, 210, 70, 220)
    rl.draw_text_2d("Texture Paint (2D) - MMB Pan · Wheel Zoom", 12, 518, 18, 0.9, 0.7, 0.2, 210)
    rl.end_mode2d()
end

-- ── Camera Update & Input ───────────────────────────────────────────────────
local function update_camera(dt)
    local f = 1.0 - math.exp(-dt * 22.0)
    cam.yaw = cam.yaw + (cam.target_yaw - cam.yaw) * f
    cam.pitch = cam.pitch + (cam.target_pitch - cam.pitch) * f
    cam.dist = cam.dist + (cam.target_dist - cam.dist) * f

    cam.target[1] = cam.target[1] + (cam.target_pos[1] - cam.target[1]) * f
    cam.target[2] = cam.target[2] + (cam.target_pos[2] - cam.target[2]) * f
    cam.target[3] = cam.target[3] + (cam.target_pos[3] - cam.target[3]) * f

    local ry = deg2rad(cam.yaw)
    local rp = deg2rad(cam.pitch)
    local cp = math.cos(rp)

    cam.eye[1] = cam.target[1] + cam.dist * cp * math.sin(ry)
    cam.eye[2] = cam.target[2] + cam.dist * math.sin(rp)
    cam.eye[3] = cam.target[3] + cam.dist * cp * math.cos(ry)

    rl.set_camera(cam.eye[1], cam.eye[2], cam.eye[3],
                  cam.target[1], cam.target[2], cam.target[3], 60)
end

-- ── Keyboard & Mouse Shortcuts ──────────────────────────────────────────────
local function handle_hotkeys()
    local io = ig.get_io()
    local ctrl_down = rl.is_key_down(rl.key.LeftCtrl) or rl.is_key_down(rl.key.RightCtrl) or io.key_ctrl
    local shift_down = rl.is_key_down(rl.key.LeftShift) or rl.is_key_down(rl.key.RightShift) or io.key_shift

    -- Undo: Ctrl+Z (and not shift) — canvas in 2D mode, mesh undo otherwise
    if ctrl_down and not shift_down and rl.is_key_pressed(rl.key.Z) then
        if doc.mode == 5 then doc.canvas_undo() else doc.perform_undo() end
        return
    end

    -- Redo: Ctrl+Y or Ctrl+Shift+Z
    if (ctrl_down and rl.is_key_pressed(rl.key.Y)) or
       (ctrl_down and shift_down and rl.is_key_pressed(rl.key.Z)) then
        if doc.mode == 5 then doc.canvas_redo() else doc.perform_redo() end
        return
    end

    -- OBJ Export: Ctrl+E
    if ctrl_down and rl.is_key_pressed(rl.key.E) then
        doc.export_obj("build/cubeforge_model.obj")
        return
    end

    -- Modal action confirms/cancels via keys
    if doc.action then
        if rl.is_key_pressed(rl.key.Enter) then
            doc.confirm_action()
            return
        end
        if rl.is_key_pressed(rl.key.Escape) then
            doc.cancel_action()
            return
        end
    end

    -- Mode switching: 1, 2, 3, 4, 5, B (only if not typing in text input)
    if not io.want_text_input then
        if rl.is_key_pressed(rl.key["1"]) then
            set_mode(1)
        elseif rl.is_key_pressed(rl.key["2"]) then
            set_mode(2)
        elseif rl.is_key_pressed(rl.key["3"]) then
            set_mode(3)
        elseif rl.is_key_pressed(rl.key["4"]) or rl.is_key_pressed(rl.key.B) then
            set_mode(4)
        elseif rl.is_key_pressed(rl.key["5"]) then
            set_mode(5)
        end

        -- Extrude: E (when not ctrl; 3D modes only)
        if not ctrl_down and doc.mode ~= 5 and rl.is_key_pressed(rl.key.E) then
            if not doc.action then
                local mx, my = rl.get_mouse_pos()
                doc.start_extrude(mx, my)
            end
        end

        -- Move / Grab: G (3D modes only)
        if not ctrl_down and doc.mode ~= 5 and rl.is_key_pressed(rl.key.G) then
            if not doc.action then
                local mx, my = rl.get_mouse_pos()
                doc.start_move(mx, my)
            end
        end
    end
end

-- ── Viewport Input (Camera & Tools) ─────────────────────────────────────────
local is_painting = false

local function handle_viewport_input()
    local dt = rl.get_frame_time()
    local mx, my = rl.get_mouse_pos()
    local sw, sh = rl.get_screen_size()
    local io = ig.get_io()

    handle_hotkeys()

    -- 0. 2D texture-paint mode (mode 5): MMB pan, wheel zoom, LMB paint.
    --    The 3D camera stays inert while the 2D viewport owns the frame.
    if doc.mode == 5 then
        handle_canvas_input(mx, my, sw, sh, io)
        return
    end

    -- 1. In-flight modal interaction (Extrude / Move)
    if doc.action then
        -- Confirm on Left-Click
        if rl.is_mouse_button_pressed(rl.MOUSE_LEFT) then
            doc.confirm_action()
            return
        end
        -- Cancel on Right-Click
        if rl.is_mouse_button_pressed(rl.MOUSE_RIGHT) then
            doc.cancel_action()
            return
        end

        -- Update in-flight motion
        if doc.action == "extrude" then
            doc.update_extrude(mx, my)
        elseif doc.action == "move" then
            doc.update_move(mx, my, cam)
        end
        return
    end

    -- 2. Check if mouse is over UI area (Right sidebar & top toolbar)
    local panel_w = math.max(180, math.min(sidebar_w, math.max(180, sw - 120)))
    local vp_w = math.max(60, sw - panel_w)
    local tb_w = math.min(540, vp_w - 16)
    local tb_x = math.max(8, (vp_w - tb_w) * 0.5)
    local over_tb = (my <= 58 and mx >= tb_x and mx <= tb_x + tb_w)
    local over_ui = (mx >= sw - panel_w - 8) or over_tb
    if io.want_capture_mouse and over_ui then
        update_camera(dt)
        return
    end

    -- 3. Camera Dolly (Scroll Wheel)
    local wheel = rl.get_mouse_wheel()
    if wheel ~= 0 then
        cam.target_dist = clamp(cam.target_dist * (1.15 ^ (-wheel)), 1.0, 50.0)
    end

    -- 4. Camera (Godot 3D editor language):
    --    Middle-drag = tilt (orbit yaw/pitch)
    --    Shift+Middle-drag = 3D pan (translate view center)
    --    Right-drag hold = FPS fly (look + WASD/QE movement)
    local shift_down = rl.is_key_down(rl.key.LeftShift) or rl.is_key_down(rl.key.RightShift) or io.key_shift
    local mmb = rl.is_mouse_button_down(rl.MOUSE_MIDDLE)
    local rmb = rl.is_mouse_button_down(rl.MOUSE_RIGHT)

    -- Shift+Middle: 3D pan (translate target in the view plane)
    if shift_down and mmb then
        local dx, dy = rl.get_mouse_delta()
        local ry = deg2rad(cam.yaw)
        local right_x = math.cos(ry)
        local right_z = -math.sin(ry)
        local speed = cam.dist * 0.002
        cam.target_pos[1] = cam.target_pos[1] - right_x * dx * speed
        cam.target_pos[3] = cam.target_pos[3] - right_z * dx * speed
        cam.target_pos[2] = cam.target_pos[2] + dy * speed

    -- Middle: tilt (orbit yaw/pitch around the view center)
    elseif mmb then
        local dx, dy = rl.get_mouse_delta()
        cam.target_yaw = cam.target_yaw - dx * 0.4
        cam.target_pitch = clamp(cam.target_pitch + dy * 0.4, -89, 89)

    -- Right-drag hold: FPS fly (look + move)
    elseif rmb then
        local dx, dy = rl.get_mouse_delta()
        cam.target_yaw = cam.target_yaw - dx * 0.25
        cam.target_pitch = clamp(cam.target_pitch + dy * 0.25, -89, 89)
        -- WASD/QE movement along camera axes (Godot fly-mode language)
        local ry = deg2rad(cam.yaw)
        local rp = deg2rad(cam.pitch)
        local cp = math.cos(rp)
        local fwd = { -cp * math.sin(ry), -math.sin(rp), -cp * math.cos(ry) }
        local right = { math.cos(ry), 0, -math.sin(ry) }
        local speed = 4.0 * (cam.dist / 8.0) * dt   -- scale with zoom
        local move = { 0, 0, 0 }
        if rl.is_key_down(rl.key.W) then
            move[1] = move[1] + fwd[1]; move[2] = move[2] + fwd[2]; move[3] = move[3] + fwd[3]
        end
        if rl.is_key_down(rl.key.S) then
            move[1] = move[1] - fwd[1]; move[2] = move[2] - fwd[2]; move[3] = move[3] - fwd[3]
        end
        if rl.is_key_down(rl.key.D) then
            move[1] = move[1] + right[1]; move[2] = move[2] + right[2]; move[3] = move[3] + right[3]
        end
        if rl.is_key_down(rl.key.A) then
            move[1] = move[1] - right[1]; move[2] = move[2] - right[2]; move[3] = move[3] - right[3]
        end
        if rl.is_key_down(rl.key.Q) or rl.is_key_down(rl.key.E) then
            local up = (rl.is_key_down(rl.key.Q) and -1) or 1
            move[2] = move[2] + up
        end
        local len = math.sqrt(move[1]^2 + move[2]^2 + move[3]^2)
        if len > 0.001 then
            cam.target_pos[1] = cam.target_pos[1] + move[1] / len * speed
            cam.target_pos[2] = cam.target_pos[2] + move[2] / len * speed
            cam.target_pos[3] = cam.target_pos[3] + move[3] / len * speed
        end
    end

    -- 5. Left Click / Drag Actions (Selection & Vertex Paint)
    if not over_ui then
        if doc.mode == 4 then
            -- Vertex Paint Mode
            if rl.is_mouse_button_down(rl.MOUSE_LEFT) then
                is_painting = true
                doc.paint_stroke(mx, my)
            elseif is_painting and not rl.is_mouse_button_down(rl.MOUSE_LEFT) then
                is_painting = false
                doc.end_paint_stroke()
            end
        else
            -- Selection Modes (Vertex / Edge / Face)
            if rl.is_mouse_button_pressed(rl.MOUSE_LEFT) then
                doc.select_at(mx, my)
            end
        end
    end

    update_camera(dt)
end


-- ── 3D Scene Rendering ──────────────────────────────────────────────────────
local LIGHT_DIR = geom.normalize({ 0.45, 0.85, 0.35 })

local function offset_pt(v, norm, dist)
    return {
        x = v.x + norm[1] * dist,
        y = v.y + norm[2] * dist,
        z = v.z + norm[3] * dist,
    }
end

-- Base shaded triangle rendering for untextured / geometry-edited meshes
local function render_mesh_3d(mesh, is_active_mesh)
    local verts = mesh.verts
    local faces = mesh.faces

    for _, face in ipairs(faces) do
        local fv = face.verts
        local num_v = #fv

        local norm = face.normal or geom.calc_face_normal(verts, fv)
        local dot = geom.dot(norm, LIGHT_DIR)
        local lit = math.max(0.25, math.min(1.0, 0.35 + 0.65 * dot))
        local fc = face.color or { 170, 190, 215, 255 }

        if num_v >= 3 then
            local v0 = verts[fv[1]]
            for i = 2, num_v - 1 do
                local v1 = verts[fv[i]]
                local v2 = verts[fv[i + 1]]
                if v0 and v1 and v2 then
                    local avg_vr = ((v0.r or fc[1]) + (v1.r or fc[1]) + (v2.r or fc[1])) / 3.0
                    local avg_vg = ((v0.g or fc[2]) + (v1.g or fc[2]) + (v2.g or fc[2])) / 3.0
                    local avg_vb = ((v0.b or fc[3]) + (v1.b or fc[3]) + (v2.b or fc[3])) / 3.0

                    local r = math.floor(math.min(255, avg_vr * lit))
                    local g = math.floor(math.min(255, avg_vg * lit))
                    local b = math.floor(math.min(255, avg_vb * lit))

                    rl.draw_triangle_3d(
                        v0.x, v0.y, v0.z,
                        v1.x, v1.y, v1.z,
                        v2.x, v2.y, v2.z,
                        r, g, b, 255
                    )
                end
            end
        end
    end
end

-- Unified 3D selection, wireframe, vertex/edge handles, and gizmo overlays.
-- Runs identically on top of both textured meshes (rl.draw_model) and
-- flat-shaded meshes (render_mesh_3d), using normal offsets to guarantee
-- zero Z-fighting and high-contrast visibility through any texture.
local function draw_mesh_overlays(mesh, is_active_mesh)
    local verts = mesh.verts
    local faces = mesh.faces
    local is_face_mode = (doc.mode == 3 or doc.mode == nil)
    local is_edge_mode = (doc.mode == 2)
    local is_vert_mode = (doc.mode == 1)
    local is_paint_mode = (doc.mode == 4)

    -- 1. Wireframe edges (offset slightly along face normal so they never Z-fight)
    for f_idx, face in ipairs(faces) do
        local fv = face.verts
        local num_v = #fv
        local is_sel_face = (is_active_mesh and is_face_mode and f_idx == doc.selected_face_idx)
        local norm = face.normal or geom.calc_face_normal(verts, fv)

        local wire_r = is_sel_face and 255 or (is_edge_mode and 70 or 45)
        local wire_g = is_sel_face and 220 or (is_edge_mode and 95 or 55)
        local wire_b = is_sel_face and 60 or (is_edge_mode and 135 or 75)
        local wire_a = is_sel_face and 255 or (is_active_mesh and 170 or 100)
        local offset_dist = is_sel_face and 0.004 or 0.002

        for i = 1, num_v do
            local vi1 = fv[i]
            local vi2 = fv[(i % num_v) + 1]
            local va = verts[vi1]
            local vb = verts[vi2]
            if va and vb then
                local p1 = offset_pt(va, norm, offset_dist)
                local p2 = offset_pt(vb, norm, offset_dist)
                rl.draw_line_3d(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, wire_r, wire_g, wire_b, wire_a)
            end
        end
    end

    -- 2. Mode 3 (Face Mode): Selected Face Highlight (Warm golden amber fill + bright boundary + normal gizmo)
    if is_active_mesh and is_face_mode and doc.selected_face_idx and faces[doc.selected_face_idx] then
        local face = faces[doc.selected_face_idx]
        local fv = face.verts
        local num_v = #fv
        local norm = face.normal or geom.calc_face_normal(verts, fv)

        -- Face highlight fill (golden amber wash, offset by normal to prevent Z-fighting)
        if num_v >= 3 then
            local v0 = offset_pt(verts[fv[1]], norm, 0.003)
            for i = 2, num_v - 1 do
                local v1 = offset_pt(verts[fv[i]], norm, 0.003)
                local v2 = offset_pt(verts[fv[i + 1]], norm, 0.003)
                rl.draw_triangle_3d(
                    v0.x, v0.y, v0.z,
                    v1.x, v1.y, v1.z,
                    v2.x, v2.y, v2.z,
                    245, 185, 40, 180
                )
            end
        end

        -- Bright golden-yellow boundary outline (double thickness via offset)
        for i = 1, num_v do
            local vi1 = fv[i]
            local vi2 = fv[(i % num_v) + 1]
            local va = verts[vi1]
            local vb = verts[vi2]
            if va and vb then
                local p1 = offset_pt(va, norm, 0.005)
                local p2 = offset_pt(vb, norm, 0.005)
                rl.draw_line_3d(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, 255, 230, 65, 255)
            end
        end

        -- Centroid normal pip & axis gizmo
        local centroid = geom.calc_face_centroid(verts, fv)
        local cb_x = centroid[1] + norm[1] * 0.01
        local cb_y = centroid[2] + norm[2] * 0.01
        local cb_z = centroid[3] + norm[3] * 0.01
        local ct_x = centroid[1] + norm[1] * 0.42
        local ct_y = centroid[2] + norm[2] * 0.42
        local ct_z = centroid[3] + norm[3] * 0.42
        rl.draw_line_3d(cb_x, cb_y, cb_z, ct_x, ct_y, ct_z, 255, 215, 50, 255)
        rl.draw_sphere(ct_x, ct_y, ct_z, 0.038, 255, 230, 70, 255)
    end

    -- 3. Mode 2 (Edge Mode): Highlight selected edge with electric cyan + handle pip
    if is_active_mesh and is_edge_mode and doc.selected_edge then
        local e = doc.selected_edge
        local va = verts[e.vi1]
        local vb = verts[e.vi2]
        if va and vb then
            local fn = { 0, 1, 0 }
            if e.face_idx and faces[e.face_idx] then
                fn = faces[e.face_idx].normal or geom.calc_face_normal(verts, faces[e.face_idx].verts)
            end
            local p1 = offset_pt(va, fn, 0.006)
            local p2 = offset_pt(vb, fn, 0.006)
            rl.draw_line_3d(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, 50, 225, 255, 255)
            local mx = (p1.x + p2.x) * 0.5
            local my = (p1.y + p2.y) * 0.5
            local mz = (p1.z + p2.z) * 0.5
            rl.draw_sphere(mx, my, mz, 0.045, 50, 235, 255, 255)
        end
    end

    -- 4. Mode 1 (Vertex Mode): Draw 3D vertex handles with selected vertex highlighted
    if is_active_mesh and is_vert_mode then
        for v_idx, v in ipairs(verts) do
            if doc.selected_vert_idx == v_idx then
                -- Selected vertex: glowing bright gold sphere
                rl.draw_sphere(v.x, v.y, v.z, 0.065, 255, 235, 75, 255)
            else
                -- Unselected vertex: amber dot
                rl.draw_sphere(v.x, v.y, v.z, 0.040, 225, 160, 35, 255)
            end
        end
    end

    -- 5. Vertex Paint Mode (Mode 4): Draw vertex spheres with painted RGB color
    if is_active_mesh and is_paint_mode then
        for _, v in ipairs(verts) do
            rl.draw_sphere(v.x, v.y, v.z, 0.048, v.r or 200, v.g or 200, v.b or 200, 255)
        end
    end

    -- 6. In-Flight Modal Transform Gizmos (Extrude / Move)
    if is_active_mesh and doc.action == "extrude" and doc.action_data then
        local data = doc.action_data
        if data.orig_positions and data.cap_verts then
            for _, vi in ipairs(data.cap_verts) do
                local orig = data.orig_positions[vi]
                local cur = verts[vi]
                if orig and cur then
                    rl.draw_line_3d(orig.x, orig.y, orig.z, cur.x, cur.y, cur.z, 80, 255, 140, 255)
                end
            end
        end
    end

    -- 7. Hover Highlight (subtle translucent highlight on element under mouse cursor)
    if is_active_mesh and not doc.action and doc.mode == 3 then
        local mx, my = rl.get_mouse_pos()
        local ox, oy, oz, dx, dy, dz = lp.rl.get_ray(mx, my)
        local hit = geom.raycast_mesh(mesh, { ox, oy, oz }, { dx, dy, dz })
        if hit and hit.face_idx and hit.face_idx ~= doc.selected_face_idx then
            local face = faces[hit.face_idx]
            if face then
                local fv = face.verts
                local num_v = #fv
                local norm = face.normal or geom.calc_face_normal(verts, fv)
                if num_v >= 3 then
                    local v0 = offset_pt(verts[fv[1]], norm, 0.002)
                    for i = 2, num_v - 1 do
                        local v1 = offset_pt(verts[fv[i]], norm, 0.002)
                        local v2 = offset_pt(verts[fv[i + 1]], norm, 0.002)
                        rl.draw_triangle_3d(v0.x, v0.y, v0.z, v1.x, v1.y, v1.z, v2.x, v2.y, v2.z, 200, 230, 255, 95)
                    end
                end
                for i = 1, num_v do
                    local vi1 = fv[i]
                    local vi2 = fv[(i % num_v) + 1]
                    local va = verts[vi1]
                    local vb = verts[vi2]
                    if va and vb then
                        local p1 = offset_pt(va, norm, 0.003)
                        local p2 = offset_pt(vb, norm, 0.003)
                        rl.draw_line_3d(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, 160, 220, 255, 200)
                    end
                end
            end
        end
    end
end
-- ── 3D Viewport Drawing (Called inside BeginMode3D) ─────────────────────────
function lp_draw3d()
    setup_scene()
    handle_viewport_input()

    -- Mode 5: the 3D scene is hidden; the 2D canvas view draws in lp_draw2d
    if doc.mode == 5 then
        return
    end

    -- Ground reference grid
    local GRID_Y = -0.02
    for i = -10, 10 do
        local alpha = (i % 5 == 0) and 90 or 30
        rl.draw_line_3d(i, GRID_Y, -10, i, GRID_Y, 10, 200, 200, 200, alpha)
        rl.draw_line_3d(-10, GRID_Y, i, 10, GRID_Y, i, 200, 200, 200, alpha)
    end

    -- Render all document meshes (textured GPU model with Gouraud vertex color gradient)
    for m_idx, mesh in ipairs(doc.meshes) do
        local is_active = (m_idx == doc.selected_mesh_idx)
        if mesh.model_id then
            ensure_mesh_model(mesh, m_idx)
            rl.draw_model(mesh.model_id, 0, 0, 0, 1.0, 255, 255, 255, 255)
        else
            render_mesh_3d(mesh, is_active)
        end
        draw_mesh_overlays(mesh, is_active)
    end
    -- Paint Mode: draw 3D brush indicator at ray hit point
    if doc.mode == 4 and not doc.action then
        local mx, my = rl.get_mouse_pos()
        local ox, oy, oz, dx, dy, dz = lp.rl.get_ray(mx, my)
        local best_dist = math.huge
        local best_hit = nil
        for _, mesh in ipairs(doc.meshes) do
            local hit = geom.raycast_mesh(mesh, { ox, oy, oz }, { dx, dy, dz })
            if hit and hit.dist < best_dist then
                best_dist = hit.dist
                best_hit = hit
            end
        end
        if best_hit then
            local hp = best_hit.hit_point
            local bc = doc.brush.color
            rl.draw_sphere_wires(hp[1], hp[2], hp[3], doc.brush.radius, 12, 12, bc[1], bc[2], bc[3], 255)
        end
    end
end

-- ── 2D Viewport Drawing (Called after EndMode3D, inside BeginDrawing) ───────
-- raylib 6.0 quirk: BeginMode2D no longer installs an ortho projection, so 2D
-- content must be drawn outside BeginMode3D. Mode 5 owns this pass.
function lp_draw2d()
    if doc.mode == 5 then
        draw_canvas_2d()
    end
end

-- ── ImGui UI Panels (Called inside rlImGuiBegin/End) ────────────────────────
-- Shared image-import pipeline: drag&drop, Ctrl+V paste (clipboard file path),
-- and the file-picker button all route here. Loads the image into the canvas
-- (resized to 512x512), uploads it, and applies it to the active mesh so it
-- becomes the cube's texture. Graceful rejection: unsupported/unreadable
-- inputs only set a status message — the existing canvas is untouched.
local function import_image(path)
    if not path or path == "" then
        doc.status_msg = "Import: no file"
        return false
    end
    path = path:gsub("^%s+", ""):gsub("%s+$", "")
    -- Linux clipboard uri-list arrives as file:///abs/path — normalize
    if path:sub(1, 7) == "file://" then
        path = path:sub(8)
        if path:sub(1, 1) == "/" and path:sub(2, 2) == "/" then
            path = path:sub(2)  -- file://host/path → /path (local host)
        end
        path = path:gsub("%%20", " ")
    end
    if path == "" then
        doc.status_msg = "Import: empty path"
        return false
    end
    if not _G.gl_ready then
        doc.status_msg = "Import: not ready"
        return false
    end
    doc.canvas_init()
    local ok = lp.tex.load_image_from_file(doc.canvas.tex_id, path)
    if not ok then
        doc.status_msg = "Import rejected: unsupported or unreadable: " .. path
        return false
    end
    lp.tex.upload(doc.canvas.tex_id)
    local m_idx = doc.selected_mesh_idx or 1
    local mesh = doc.meshes[m_idx]
    if mesh then
        ensure_mesh_model(mesh, m_idx)
        doc.canvas_apply_to(m_idx)
    end
    doc.status_msg = "Imported texture: " .. path
    return true
end

function lp_frame()
    local sw, sh = rl.get_screen_size()
    -- Debounced resize hook: put heavy rebuilds behind this guard.
    if resize_settled(rl.get_frame_time()) then
        -- e.g. re-upload canvases, rebuild caches — nothing heavy today.
    end

    -- File drag & drop (raylib 6.0: LoadDroppedFiles takes the first path)
    if rl.is_file_dropped() then
        local dropped = rl.take_dropped_file()
        if dropped then
            import_image(dropped)
        end
    end
    -- Paste (Ctrl+V): clipboard holds a file (CF_HDROP on Windows) or a path
    -- → import; else reject politely. Uses clipboard_file_path so copying a
    -- file in Explorer pastes it WITHOUT GLFW's clipboard-string error.
    local ctrl = rl.is_key_down(rl.key.LeftCtrl) or rl.is_key_down(rl.key.RightCtrl) or ig.get_io().key_ctrl
    if ctrl and (rl.is_key_pressed(rl.key.V) or ig.is_key_pressed(ig.key.V)) then
        local txt = rl.clipboard_file_path()
        if txt and #txt > 0 then
            import_image(txt)
        else
            doc.status_msg = "Paste: clipboard has no file or image path"
        end
    end
    -- F3 Performance HUD toggle
    if (rl.key.F3 and rl.is_key_pressed(rl.key.F3)) or (ig.key.F3 and ig.is_key_pressed(ig.key.F3)) then
        show_perf_hud = not show_perf_hud
    end


    -- 1. Top Floating Pill Toolbar (Centered over 3D viewport area)
    local max_sidebar = math.max(180, sw - 120)
    local panel_w = math.max(180, math.min(sidebar_w, max_sidebar))
    local vp_w = math.max(60, sw - panel_w)
    local is_compact = (vp_w < 780)
    local tb_w = is_compact and math.min(500, vp_w - 16) or math.min(760, vp_w - 16)
    local tb_h = 42
    local tb_x = math.max(8, (vp_w - tb_w) * 0.5)
    ig.set_next_window_pos(tb_x, 12)
    ig.set_next_window_size(tb_w, tb_h)
    ig.set_next_window_bg_alpha(0.92)
    local tb_flags = 1 + 2 + 32 -- NoTitleBar | NoResize | NoSavedSettings
    ig.window("##top_toolbar", tb_flags, function()
        -- Primitives
        if ig.button(ic("CUBE", "+") .. "Box") then
            doc.add_box()
        end
        ig.same_line()
        local cyl_label = is_compact and (ic("CYLINDER", "+") .. "Cyl") or (ic("CYLINDER", "+") .. "Cylinder")
        if ig.button(cyl_label) then
            doc.add_cylinder()
        end

        ig.same_line()
        ig.text_colored("|", 0.4, 0.4, 0.45, 1.0)
        ig.same_line()

        -- Modal Tools
        local can_extrude = (doc.selected_face_idx ~= nil)
        local can_move = (doc.mode == 1 and doc.selected_vert_idx ~= nil)
            or (doc.mode == 2 and doc.selected_edge ~= nil)
            or (doc.selected_face_idx ~= nil)

        if not can_extrude then ig.begin_disabled(true) end
        local ext_label = is_compact and (ic("EXTRUDE", "") .. "Ext") or (ic("EXTRUDE", "") .. "Extrude (E)")
        if ig.button(ext_label) then
            local mx, my = rl.get_mouse_pos()
            doc.start_extrude(mx, my)
        end
        if not can_extrude then ig.end_disabled() end

        ig.same_line()
        if not can_move then ig.begin_disabled(true) end
        local move_label = is_compact and (ic("MOVE", "") .. "Move") or (ic("MOVE", "") .. "Move (G)")
        if ig.button(move_label) then
            local mx, my = rl.get_mouse_pos()
            doc.start_move(mx, my)
        end
        if not can_move then ig.end_disabled() end
        ig.same_line()
        ig.text_colored("|", 0.4, 0.4, 0.45, 1.0)
        ig.same_line()

        -- Undo / Redo (canvas stack in 2D mode, mesh stack otherwise)
        local canvas_mode = (doc.mode == 5)
        local can_u = canvas_mode
            and (doc.canvas.tex_id ~= nil and lp.tex.can_undo(doc.canvas.tex_id))
            or undo.can_undo()
        if not can_u then ig.begin_disabled(true) end
        if ig.button(ic("UNDO", "") .. "Undo") then
            if canvas_mode then doc.canvas_undo() else doc.perform_undo() end
        end
        if not can_u then ig.end_disabled() end

        ig.same_line()
        local can_r = canvas_mode
            and (doc.canvas.tex_id ~= nil and lp.tex.can_redo(doc.canvas.tex_id))
            or undo.can_redo()
        if not can_r then ig.begin_disabled(true) end
        if ig.button(ic("REDO", "") .. "Redo") then
            if canvas_mode then doc.canvas_redo() else doc.perform_redo() end
        end
        if not can_r then ig.end_disabled() end

        ig.same_line()
        ig.text_colored("|", 0.4, 0.4, 0.45, 1.0)
        ig.same_line()

        -- Export OBJ
        local exp_label = is_compact and (ic("EXPORT", "") .. "OBJ") or (ic("EXPORT", "") .. "Export OBJ")
        if ig.button(exp_label) then
            doc.export_obj("build/cubeforge_model.obj")
        end
    end)

    -- 2. In-Flight Modal Floating HUD Badge
    if doc.action then
        local hud_text
        if doc.action == "extrude" then
            local dist = (doc.action_data and doc.action_data.dist) or 0.0
            hud_text = string.format("EXTRUDE: %+.2fm  |  L-Click / Enter: Confirm  ·  R-Click / Esc: Cancel", dist)
        elseif doc.action == "move" then
            hud_text = "MOVE (View Plane)  |  L-Click / Enter: Confirm  ·  R-Click / Esc: Cancel"
        end

        if hud_text then
            local badge_w = 540
            ig.set_next_window_pos((vp_w - badge_w) * 0.5, 62)
            ig.set_next_window_size(badge_w, 36)
            ig.set_next_window_bg_alpha(0.95)
            ig.window("##modal_hud", tb_flags, function()
                ig.text_colored(hud_text, 0.96, 0.65, 0.12, 1.0)
            end)
        end
    end

    -- 3. Right Properties & Tools Side Panel
    -- Resizable via an ImGui splitter INSIDE the window's left edge
    -- (Godot-inspector style). Being a real widget, the handle gets proper
    -- hover/click capture: no click-through, no highlight bleed, and the
    -- cursor resets when the pointer leaves.
    local max_sidebar = math.max(180, sw - 120)
    local panel_w = math.max(180, math.min(sidebar_w, max_sidebar))
    ig.set_next_window_pos(sw - panel_w, 0)
    ig.set_next_window_size(panel_w, sh)
    ig.set_next_window_bg_alpha(0.96)

    ig.window("##sidebar", 1 + 2 + 32, function()
        -- Splitter handle: 6px column at the window's left edge
        ig.child("##splitter", 6, 0, 0, function()
            local sx, sy = ig.get_cursor_screen_pos()
            local dl = ig.get_window_draw_list()
            local aw, ah = ig.get_content_region_avail()  -- (w, h)
            ig.invisible_button("##resize_handle", 6, math.max(ah, 1))
            local on = ig.is_item_hovered()
            CF.sp_hover = (CF.sp_hover or 0) + (on and 1 or 0)
            if on and ig.is_mouse_clicked(0) then CF.resize_active = true end
            if not ig.is_mouse_down(0) then CF.resize_active = false end
            CF.sp_active = (CF.sp_active or 0) + (CF.resize_active and 1 or 0)
            if CF.resize_active then
                local dx = rl.get_mouse_delta()
                sidebar_w = clamp(sidebar_w - dx, 180, math.max(180, sw - 120))
            end
            if on or CF.resize_active then
                rl.set_mouse_cursor(rl.CURSOR_RESIZE_EW)
                ig.dl_add_rect_filled(dl, sx, sy, sx + 6, sy + ah, 0.96, 0.65, 0.12, 0.85)
            else
                rl.set_mouse_cursor(rl.CURSOR_DEFAULT)
            end
        end)
        ig.same_line()
        -- Content column (scrolls by default; never set NoScrollbar here)
        ig.child("##sidebar_content", 0, 0, 0, function()
        ig.text_colored("CubeForge 2D+3D", 0.96, 0.65, 0.12, 1.0)
        ig.same_line()
        ig.text_colored("v1.0", 0.5, 0.5, 0.55, 1.0)
        ig.same_line(panel_w - 118)
        ig.text_colored(ic("GRIP", "|") .. "drag edge", 0.45, 0.47, 0.52, 1.0)
        ig.separator()

        -- Selection Mode Pills (1..4 = 3D, 5 = 2D texture paint)
        ig.text("Selection Mode:")
        local mode_names = {
            ic("VERTEX", "") .. "1: Vertex",
            ic("EDGE", "") .. "2: Edge",
            ic("FACE", "") .. "3: Face",
            ic("PAINT", "") .. "4: Vert Paint",
            ic("PALETTE", "") .. "5: Tex Paint"
        }
        for m = 1, 5 do
            if m == 2 or m == 4 then ig.same_line() end  -- 2 per row
            local is_active = (doc.mode == m)
            if is_active then
                ig.push_style_color(ig.col.Button, 0.85, 0.55, 0.12, 1.0)
                ig.push_style_color(ig.col.Text, 0.1, 0.1, 0.12, 1.0)
            end
            if ig.button(mode_names[m]) then
                set_mode(m)
            end
            if is_active then
                ig.pop_style_color(2)
            end
        end

        ig.separator()

        -- Geometry Actions
        ig.text("Actions:")
        local can_extrude = (doc.selected_face_idx ~= nil)
        local can_move = (doc.mode == 1 and doc.selected_vert_idx ~= nil)
            or (doc.mode == 2 and doc.selected_edge ~= nil)
            or (doc.selected_face_idx ~= nil)

        if not can_extrude then ig.begin_disabled(true) end
        if ig.button(ic("EXTRUDE", "") .. "Extrude (E)", 126, 28) then
            local mx, my = rl.get_mouse_pos()
            doc.start_extrude(mx, my)
        end
        if not can_extrude then ig.end_disabled() end

        ig.same_line()
        if not can_move then ig.begin_disabled(true) end
        if ig.button(ic("MOVE", "") .. "Move (G)", 126, 28) then
            local mx, my = rl.get_mouse_pos()
            doc.start_move(mx, my)
        end
        if not can_move then ig.end_disabled() end
        ig.separator()

        -- Vertex Painting Settings (Mode 4)
        ig.text("Mode 4: Vertex Paint (3D Surface Tint):")
        ig.text_colored("Paints vertex RGB colors (blends with texture)", 0.55, 0.6, 0.65, 1.0)
        local r_chg, new_rad = ig.slider_float("Radius##brush", doc.brush.radius, 0.2, 4.0)
        if r_chg then doc.brush.radius = new_rad end

        local s_chg, new_str = ig.slider_float("Strength##brush", doc.brush.strength, 0.1, 1.0)
        if s_chg then doc.brush.strength = new_str end

        local h_chg, new_hard = ig.slider_float("Hardness##brush", doc.brush.hardness, 0.0, 1.0)
        if h_chg then doc.brush.hardness = new_hard end

        local sp_chg, new_sp = ig.slider_float("Spacing##brush", doc.brush.spacing or 0.20, 0.05, 0.60)
        if sp_chg then doc.brush.spacing = new_sp end
        local bc = doc.brush.color
        local col_norm = { (bc[1] or 240) / 255.0, (bc[2] or 120) / 255.0, (bc[3] or 50) / 255.0 }
        -- color_edit3 returns (changed, r, g, b) — three numbers, NOT a table
        local c_chg, cr, cg, cb = ig.color_edit3("Color##brush", col_norm[1], col_norm[2], col_norm[3])
        if c_chg then
            doc.brush.color = {
                math.floor(cr * 255 + 0.5),
                math.floor(cg * 255 + 0.5),
                math.floor(cb * 255 + 0.5),
            }
        end

        ig.separator()

        -- 2D Texture Canvas (mode 5): live preview + stroke controls.
        -- The preview draws the GPU texture via the window draw list.
        ig.text("Mode 5: 2D Texture Paint (UV Canvas):")
        ig.text_colored("Paints 2D bitmap -> UV mapped onto 3D mesh", 0.55, 0.6, 0.65, 1.0)
        if doc.canvas.tex_id then
            local tid = doc.canvas.tex_id
            local gl_id = lp.tex.texture_id(tid)
            local pw = panel_w - 16
            ig.child("##canvas_preview", pw, 122, 0, function()
                local wx, wy = ig.get_window_pos()
                local cx, cy = ig.get_cursor_pos()
                local dl = ig.get_window_draw_list()
                local size = 108
                local px = wx + cx + (pw - size) * 0.5
                local py = wy + cy + 4
                ig.dl_add_image(dl, gl_id, px, py, px + size, py + size, 0, 0, 1, 1)
                ig.dl_add_rect(dl, px - 1, py - 1, px + size + 1, py + size + 1,
                    0.85, 0.65, 0.2, 1.0, 0.0, 1.5)
            end)
            ig.text_colored("Texture → Cube (2D↔3D)", 0.95, 0.7, 0.2, 1.0)
            ig.text_colored("Drop · Ctrl+V · Open — import an image", 0.6, 0.65, 0.7, 1.0)
            if ig.button(ic("FOLDER_OPEN", "") .. "Load Texture…") then
                local path = lp.app.open_file_dialog()
                if path then
                    import_image(path)
                else
                    doc.status_msg = "No file selected"
                end
            end
            ig.same_line()
            if ig.button(ic("TRASH", "") .. "Clear Canvas") then doc.canvas_clear() end
            if ig.button(ic("UNDO", "") .. "Canvas Undo") then doc.canvas_undo() end
            ig.same_line()
            if ig.button(ic("REDO", "") .. "Canvas Redo") then doc.canvas_redo() end
        else
            ig.text_colored("Canvas created on first 3D frame", 0.5, 0.5, 0.55, 1.0)
        end

        ig.separator()

        -- Viewport Display Controls (3D Lighting toggle)
        ig.text("Viewport Display:")
        local l_chg, new_l = ig.checkbox("3D Lighting (Sun Key Light)", doc.lighting_enabled or false)
        if l_chg then
            doc.lighting_enabled = new_l
            if lp.rl.set_lighting_enabled then lp.rl.set_lighting_enabled(doc.lighting_enabled) end
        end

        ig.text("Frame Rate Limit:")
        for idx, opt in ipairs(FPS_LIMITS) do
            if idx == 2 or idx == 4 or idx == 6 then ig.same_line() end
            local active = (fps_limit_idx == idx)
            if active then
                ig.push_style_color(ig.col.Button, 0.96, 0.65, 0.12, 0.9)
                ig.push_style_color(ig.col.Text, 0.1, 0.1, 0.1, 1.0)
            end
            if ig.button(opt.label .. "##fps", 124, 24) then
                fps_limit_idx = idx
                if rl.set_target_fps then rl.set_target_fps(opt.fps) end
            end
            if active then
                ig.pop_style_color(2)
            end
        end
        ig.separator()

        -- Scene Hierarchy & Stats
        ig.text("Scene Summary:")
        local total_verts = 0
        local total_faces = 0
        for _, m in ipairs(doc.meshes) do
            total_verts = total_verts + #m.verts
            total_faces = total_faces + #m.faces
        end
        ig.text(string.format("  Objects: %d", #doc.meshes))
        ig.text(string.format("  Vertices: %d", total_verts))
        ig.text(string.format("  Faces: %d", total_faces))

        local active_m = doc.get_active_mesh()
        if active_m then
            ig.text(string.format("  Active: %s", active_m.name or "Mesh"))
            if doc.mode == 1 then
                if doc.selected_vert_idx then
                    ig.text_colored(string.format("  Selected Vertex: #%d", doc.selected_vert_idx), 0.95, 0.7, 0.2, 1.0)
                else
                    ig.text_colored("  No vertex selected", 0.55, 0.55, 0.6, 1.0)
                end
            elseif doc.mode == 2 then
                if doc.selected_edge then
                    ig.text_colored(string.format("  Selected Edge: (%d - %d)", doc.selected_edge.vi1, doc.selected_edge.vi2), 0.2, 0.85, 1.0, 1.0)
                else
                    ig.text_colored("  No edge selected", 0.55, 0.55, 0.6, 1.0)
                end
            else
                if doc.selected_face_idx then
                    ig.text_colored(string.format("  Selected Face: #%d", doc.selected_face_idx), 0.95, 0.7, 0.2, 1.0)
                else
                    ig.text_colored("  No face selected", 0.55, 0.55, 0.6, 1.0)
                end
            end
        end

        ig.separator()

        -- Hotkey Reference Card
        ig.text("Hotkey Reference:")
        ig.text_colored("  E", 0.95, 0.7, 0.2, 1.0); ig.same_line(70); ig.text("Extrude face")
        ig.text_colored("  G", 0.95, 0.7, 0.2, 1.0); ig.same_line(70); ig.text("Move in view plane")
        ig.text_colored("  1/2/3", 0.95, 0.7, 0.2, 1.0); ig.same_line(70); ig.text("Vert / Edge / Face")
        ig.text_colored("  4 / B", 0.95, 0.7, 0.2, 1.0); ig.same_line(70); ig.text("Paint mode")
        ig.text_colored("  5", 0.95, 0.7, 0.2, 1.0); ig.same_line(70); ig.text("Texture Paint (2D)")
        ig.text_colored("  Ctrl+Z", 0.95, 0.7, 0.2, 1.0); ig.same_line(84); ig.text("Undo")
        ig.text_colored("  Ctrl+Y", 0.95, 0.7, 0.2, 1.0); ig.same_line(84); ig.text("Redo")
        ig.text_colored("  Ctrl+E", 0.95, 0.7, 0.2, 1.0); ig.same_line(84); ig.text("Export OBJ")
        ig.text_colored("  MMB", 0.95, 0.7, 0.2, 1.0); ig.same_line(84); ig.text("Tilt / Orbit")
        ig.text_colored("  Shift+MMB", 0.95, 0.7, 0.2, 1.0); ig.same_line(84); ig.text("3D Pan")
        ig.text_colored("  RMB", 0.95, 0.7, 0.2, 1.0); ig.same_line(84); ig.text("Fly (WASD/QE)")
        ig.text_colored("  Wheel", 0.95, 0.7, 0.2, 1.0); ig.same_line(84); ig.text("Zoom / Dolly")
        ig.text_colored("  F3", 0.95, 0.7, 0.2, 1.0); ig.same_line(84); ig.text("Toggle Perf HUD")
        ig.separator()
        ig.text_colored(doc.status_msg or "", 0.7, 0.75, 0.8, 1.0)
        end)  -- sidebar_content child
    end)  -- sidebar window

    -- 4. Performance Profiling Overlay (F3 toggle — Bottom-Left)
    if show_perf_hud then
        local dt = rl.get_frame_time()
        local instant_fps = dt > 0.0001 and (1.0 / dt) or 60.0
        fps_smooth = fps_smooth + (instant_fps - fps_smooth) * math.min(1.0, math.max(0.01, dt * 10.0))
        local frame_ms = dt * 1000.0

        -- Push into rolling 120-sample buffer
        frame_history[#frame_history + 1] = frame_ms
        if #frame_history > 120 then
            table.remove(frame_history, 1)
        end

        local min_ms, max_ms, avg_ms = 999.0, 0.0, 0.0
        for _, v in ipairs(frame_history) do
            if v < min_ms then min_ms = v end
            if v > max_ms then max_ms = v end
            avg_ms = avg_ms + v
        end
        avg_ms = #frame_history > 0 and (avg_ms / #frame_history) or frame_ms

        local b_name = "OpenGL / D3D"
        if lp.app then
            if type(lp.app.backend_name) == "string" then
                b_name = lp.app.backend_name
            elseif type(lp.app.backend_name) == "function" then
                b_name = lp.app.backend_name()
            elseif type(lp.app.get_backend_name) == "function" then
                b_name = lp.app.get_backend_name()
            end
        end
        local m_count = #doc.meshes
        local total_verts, total_faces = 0, 0
        for _, m in ipairs(doc.meshes) do
            total_verts = total_verts + #(m.verts or {})
            total_faces = total_faces + #(m.faces or {})
        end

        ig.set_next_window_pos(12, sh - 172)
        ig.set_next_window_size(320, 160)
        ig.set_next_window_bg_alpha(0.88)
        local hud_flags = 1 + 2 + 32 + 64 -- NoTitleBar | NoResize | NoSavedSettings | NoFocusOnAppearing
        ig.window("##perf_hud", hud_flags, function()
            ig.text_colored("PERF HUD [F3]", 0.96, 0.65, 0.12, 1.0)
            ig.same_line()
            local fps_col = (fps_smooth >= 55.0) and { 0.2, 0.9, 0.4 } or { 0.95, 0.4, 0.2 }
            ig.text_colored(string.format("%.1f FPS (%.2f ms)", fps_smooth, frame_ms), fps_col[1], fps_col[2], fps_col[3], 1.0)
            ig.separator()

            -- Frame time rolling sparkline graph
            if #frame_history >= 2 and ig.plot_lines then
                ig.plot_lines("##ft_graph", frame_history, #frame_history, 0.0, 20.0, 304, 38,
                    string.format("min: %.1f | avg: %.1f | max: %.1f ms", min_ms, avg_ms, max_ms))
            end

            ig.text_colored("Backend:", 0.55, 0.6, 0.65, 1.0)
            ig.same_line()
            ig.text_colored(b_name, 0.4, 0.8, 1.0, 1.0)

            local cur_limit = FPS_LIMITS[fps_limit_idx] and FPS_LIMITS[fps_limit_idx].label or "Native"
            ig.text_colored(string.format("Res: %dx%d | Limit: %s", sw, sh, cur_limit), 0.75, 0.78, 0.82, 1.0)

            local light_str = doc.lighting_enabled and "3D Sun Light" or "Unlit Diffuse"
            ig.text_colored(string.format("Light: %s | Spacing: %.2f", light_str, doc.brush.spacing or 0.20), 0.65, 0.68, 0.72, 1.0)
        end)
    end
end

-- Global handle for drive assertions (CF.cam2d / CF.doc)
CF = { cam = cam, cam2d = cam2d, doc = doc, sidebar = function() return sidebar_w end, import = import_image }
