-- editor/lua/doc.lua — Document model, selection, modal tools, and state for CubeForge
local geom = require("geom")
local undo = require("undo")

local doc = {
    meshes = {},
    selected_mesh_idx = 1,
    selected_face_idx = 3, -- Default to top face of initial cube
    selected_vert_idx = nil,
    selected_edge = nil,
    mode = 3, -- 1: Vertex, 2: Edge, 3: Face, 4: Paint
    brush = {
        radius = 1.2,
        color = { 240, 120, 50 }, -- RGB 0-255
        strength = 0.9,
        hardness = 0.6,           -- 0 = fully feathered, 1 = hard edge (shared 2D/3D)
        spacing = 0.20,           -- 0.05 = continuous line, 0.50 = sketchy/spaced stamps
    },
    lighting_enabled = false,     -- 3D lighting toggle (consistent across backends)
    action = nil, -- nil, "extrude", "move"
    action_orig = nil,
    action_data = nil,
    dirty = false,
    status_msg = "Ready",
    -- 2D texture canvas (lp.tex): the offscreen paint surface. Its brush
    -- shares the vertex-paint brush (radius/color/strength) below.
    canvas = {
        tex_id = nil,          -- lp.tex canvas id (created on first 3D frame)
        stroke_active = false, -- stroke tracking for undo coalescing
        last_stamp = nil,      -- previous world-space stamp (for interpolation)
        applied_mesh_idx = nil, -- mesh whose model shows this canvas
    },
}

-- ── Initialize Default Scene ────────────────────────────────────────────────
function doc.init_default()
    local box = geom.create_box(0, 1, 0, 2, 2, 2, { 170, 190, 215, 255 })
    box.kind = "box"
    box.dims = { w = 2, h = 2, d = 2 }
    box.origin = { x = 0, y = 1, z = 0 }
    box.name = "Box_1"
    doc.meshes = { box }
    doc.selected_mesh_idx = 1
    doc.selected_face_idx = 3 -- Top face
    doc.selected_vert_idx = nil
    doc.selected_edge = nil
    doc.mode = 3
    doc.action = nil
    doc.action_orig = nil
    doc.canvas.tex_id = nil
    doc.canvas.stroke_active = false
    doc.canvas.last_stamp = nil
    doc.canvas.applied_mesh_idx = nil
    doc.status_msg = "CubeForge Ready. E: Extrude, G: Move, 1-5: Modes"
    undo.clear()
end

-- ── Snapshot & Restore ──────────────────────────────────────────────────────
function doc.snapshot()
    local snap_meshes = {}
    for i, m in ipairs(doc.meshes) do
        snap_meshes[i] = geom.clone_mesh(m)
    end
    return {
        meshes = snap_meshes,
        selected_mesh_idx = doc.selected_mesh_idx,
        selected_face_idx = doc.selected_face_idx,
        selected_vert_idx = doc.selected_vert_idx,
        selected_edge = doc.selected_edge and { vi1 = doc.selected_edge.vi1, vi2 = doc.selected_edge.vi2, face_idx = doc.selected_edge.face_idx },
        lighting_enabled = doc.lighting_enabled,
        brush = {
            radius = doc.brush.radius,
            color = { doc.brush.color[1], doc.brush.color[2], doc.brush.color[3] },
            strength = doc.brush.strength,
            hardness = doc.brush.hardness,
            spacing = doc.brush.spacing or 0.20,
        },
    }
end

function doc.restore(snap)
    if not snap then return end
    local restored_meshes = {}
    for i, m in ipairs(snap.meshes) do
        restored_meshes[i] = geom.clone_mesh(m)
    end
    doc.meshes = restored_meshes
    doc.selected_mesh_idx = snap.selected_mesh_idx
    doc.selected_face_idx = snap.selected_face_idx
    doc.selected_vert_idx = snap.selected_vert_idx
    doc.selected_edge = snap.selected_edge
    doc.mode = snap.mode or doc.mode
    if snap.lighting_enabled ~= nil then
        doc.lighting_enabled = snap.lighting_enabled
        if lp.rl.set_lighting_enabled then lp.rl.set_lighting_enabled(doc.lighting_enabled) end
    end
    if snap.brush then
        doc.brush.radius = snap.brush.radius or doc.brush.radius
        doc.brush.color = {
            snap.brush.color[1] or doc.brush.color[1],
            snap.brush.color[2] or doc.brush.color[2],
            snap.brush.color[3] or doc.brush.color[3],
        }
        doc.brush.strength = snap.brush.strength or doc.brush.strength
        doc.brush.hardness = snap.brush.hardness or doc.brush.hardness
        doc.brush.spacing = snap.brush.spacing or doc.brush.spacing or 0.20
    end
    doc.dirty = true
    -- Undo/redo restores geometry; if GL is live, rebuild the GPU model so
    -- the texture binding (perlin/canvas) renders on the restored geometry.
    if _G.gl_ready then
        doc.rebuild_model(doc.selected_mesh_idx)
    end
end

-- ── Active Selection Helpers ────────────────────────────────────────────────
function doc.get_active_mesh()
    return doc.meshes[doc.selected_mesh_idx]
end

function doc.get_active_face()
    local m = doc.get_active_mesh()
    if m and doc.selected_face_idx then
        return m.faces[doc.selected_face_idx]
    end
    return nil
end

-- ── Primitive Spawning ──────────────────────────────────────────────────────
function doc.add_box()
    if doc.action then doc.cancel_action() end
    undo.push("Add Box", doc.snapshot())

    local y_offset = 1.0
    local new_box = geom.create_box(0, y_offset, 0, 2, 2, 2, { 170, 190, 215, 255 })
    new_box.name = "Box_" .. (#doc.meshes + 1)
    new_box.kind = "box"
    new_box.dims = { w = 2, h = 2, d = 2 }
    new_box.origin = { x = 0, y = y_offset, z = 0 }
    doc.meshes[#doc.meshes + 1] = new_box
    doc.selected_mesh_idx = #doc.meshes
    doc.selected_face_idx = 3 -- Top face
    doc.dirty = true
    doc.status_msg = "Added Box primitive"
end

function doc.add_cylinder()
    if doc.action then doc.cancel_action() end
    undo.push("Add Cylinder", doc.snapshot())

    local y_offset = 1.0
    local new_cyl = geom.create_cylinder(0, y_offset, 0, 1.0, 2.0, 16, { 180, 210, 180, 255 })
    new_cyl.name = "Cylinder_" .. (#doc.meshes + 1)
    new_cyl.kind = "cylinder"
    new_cyl.dims = { r = 1.0, h = 2.0 }
    new_cyl.origin = { x = 0, y = y_offset, z = 0 }
    doc.meshes[#doc.meshes + 1] = new_cyl
    doc.selected_mesh_idx = #doc.meshes
    doc.selected_face_idx = 1 -- Top face
    doc.dirty = true
    doc.status_msg = "Added Cylinder primitive"
end

-- ── Raycast Selection ───────────────────────────────────────────────────────
function doc.select_at(mx, my)
    if doc.action then return end
    local ox, oy, oz, dx, dy, dz = lp.rl.get_ray(mx, my)
    local ray_orig = { ox, oy, oz }
    local ray_dir = { dx, dy, dz }

    -- Mode 1: Vertex Selection
    if doc.mode == 1 then
        local best_mesh_idx = nil
        local best_vert_idx = nil
        local min_dist = math.huge

        for m_idx, mesh in ipairs(doc.meshes) do
            local vi, d = geom.pick_vertex(mesh, ray_orig, ray_dir, 0.5)
            if vi and d < min_dist then
                min_dist = d
                best_mesh_idx = m_idx
                best_vert_idx = vi
            end
        end

        if best_mesh_idx and best_vert_idx then
            doc.selected_mesh_idx = best_mesh_idx
            doc.selected_vert_idx = best_vert_idx
            doc.selected_face_idx = nil
            doc.selected_edge = nil
            doc.status_msg = string.format("Selected Vertex #%d on %s",
                best_vert_idx, doc.meshes[best_mesh_idx].name or "Mesh")
            return true
        else
            doc.selected_vert_idx = nil
            return false
        end
    end

    -- Mode 2: Edge Selection
    if doc.mode == 2 then
        local best_dist = math.huge
        local best_mesh_idx = nil
        local best_face_idx = nil
        local best_hit = nil

        for m_idx, mesh in ipairs(doc.meshes) do
            local hit = geom.raycast_mesh(mesh, ray_orig, ray_dir)
            if hit and hit.dist < best_dist then
                best_dist = hit.dist
                best_mesh_idx = m_idx
                best_face_idx = hit.face_idx
                best_hit = hit
            end
        end

        if best_mesh_idx and best_face_idx and best_hit then
            local mesh = doc.meshes[best_mesh_idx]
            local face = mesh.faces[best_face_idx]
            local fv = face.verts
            local num_v = #fv
            local min_edge_d = math.huge
            local best_e1, best_e2 = nil, nil

            for i = 1, num_v do
                local vi1 = fv[i]
                local vi2 = fv[(i % num_v) + 1]
                local va = mesh.verts[vi1]
                local vb = mesh.verts[vi2]
                if va and vb then
                    local d = geom.dist_point_to_segment(best_hit.hit_point, va, vb)
                    if d < min_edge_d then
                        min_edge_d = d
                        best_e1 = vi1
                        best_e2 = vi2
                    end
                end
            end

            doc.selected_mesh_idx = best_mesh_idx
            doc.selected_edge = { vi1 = best_e1, vi2 = best_e2, face_idx = best_face_idx }
            doc.selected_vert_idx = nil
            doc.selected_face_idx = nil
            doc.status_msg = string.format("Selected Edge (%d - %d) on %s",
                best_e1, best_e2, mesh.name or "Mesh")
            return true, best_hit
        else
            doc.selected_edge = nil
            return false, nil
        end
    end

    -- Mode 3 (or other): Face Selection
    local best_dist = math.huge
    local best_mesh_idx = nil
    local best_face_idx = nil
    local best_hit = nil

    for m_idx, mesh in ipairs(doc.meshes) do
        local hit = geom.raycast_mesh(mesh, ray_orig, ray_dir)
        if hit and hit.dist < best_dist then
            best_dist = hit.dist
            best_mesh_idx = m_idx
            best_face_idx = hit.face_idx
            best_hit = hit
        end
    end

    if best_mesh_idx and best_face_idx then
        doc.selected_mesh_idx = best_mesh_idx
        doc.selected_face_idx = best_face_idx
        doc.selected_vert_idx = nil
        doc.selected_edge = nil
        doc.status_msg = string.format("Selected Face #%d on %s",
            best_face_idx, doc.meshes[best_mesh_idx].name or "Mesh")
        return true, best_hit
    else
        doc.selected_face_idx = nil
        return false, nil
    end
end

-- ── GPU model invalidation ───────────────────────────────────────────────────
-- Geometry edits drop the mesh's GPU model so the textured render path never
-- shows stale geometry; the flat-shaded renderer takes over. GL is only ever
-- touched when a model actually exists (never in --test, where none do).
function doc.invalidate_model(mesh_idx)
    local m = doc.meshes[mesh_idx]
    if not m then return end
    if m.model_id and lp and lp.rl then
        lp.rl.unload_model(m.model_id)
    end
    m.model_id = nil
    -- NOTE: kind/dims/tex_binding are PRESERVED. The GPU model is dropped
    -- (flat-shaded fallback during live drags) but the texture binding
    -- survives so doc.rebuild_model() can restore textured rendering on
    -- commit/cancel — perlin/canvas no longer silently vanish after edits.
end

-- Re-create a GPU model from the CURRENT (possibly edited) geometry and
-- re-apply its texture binding. Live updates unload the old model and reload.
function doc.rebuild_model(mesh_idx)
    local m = doc.meshes[mesh_idx]
    if not m then return end
    if not (lp and lp.rl and lp.rl.load_model_mesh) then return end
    if not _G.gl_ready then return end  -- GL-free in --test
    if m.model_id and lp and lp.rl and lp.rl.unload_model then
        lp.rl.unload_model(m.model_id)
        m.model_id = nil
    end
    local vf, idx = geom.mesh_to_gl(m)
    if #vf == 0 or #idx == 0 then return end
    m.model_id = lp.rl.load_model_mesh(vf, idx)
    doc.apply_tex_binding(m)
end
-- Re-apply the mesh's recorded texture binding to its GPU model.
function doc.apply_tex_binding(m)
    if not m or not m.model_id then return end
    local b = m.tex_binding
    if not b then return end
    if b.kind == "perlin" and doc.perlin_tex_id then
        lp.rl.set_material_texture(m.model_id, lp.rl.MAP_ALBEDO, doc.perlin_tex_id)
    elseif b.kind == "canvas" and doc.canvas.tex_id then
        lp.tex.apply_to_model(doc.canvas.tex_id, m.model_id)
    end
end

-- ── Modal Tool: Extrude (E) ─────────────────────────────────────────────────
function doc.start_extrude(mx, my)
    if doc.action then return end
    local mesh = doc.get_active_mesh()
    local face = doc.get_active_face()
    if not (mesh and face and doc.selected_face_idx) then
        doc.status_msg = "Select a face to extrude"
        return
    end
    doc.action_orig = doc.snapshot()

    local normal = face.normal or geom.calc_face_normal(mesh.verts, face.verts)
    local orig_verts = face.verts
    local orig_positions = {}
    for i, vi in ipairs(orig_verts) do
        local v = mesh.verts[vi]
        orig_positions[i] = { x = v.x, y = v.y, z = v.z }
    end

    -- Perform initial zero-distance extrusion
    geom.extrude_face(mesh, doc.selected_face_idx, 0.0)

    -- Cap vertices are now in face.verts
    local cap_verts = {}
    for i, vi in ipairs(face.verts) do
        cap_verts[i] = vi
    end

    doc.action = "extrude"
    doc.action_data = {
        mesh_idx = doc.selected_mesh_idx,
        face_idx = doc.selected_face_idx,
        cap_verts = cap_verts,
        orig_positions = orig_positions,
        normal = { normal[1], normal[2], normal[3] },
        drag_start = { mx or 0, my or 0 },
        dist = 0.0,
    }
    doc.status_msg = "Extruding: drag mouse along normal"
end

function doc.update_extrude(mx, my)
    if doc.action ~= "extrude" or not doc.action_data then return end
    local data = doc.action_data
    local mesh = doc.meshes[data.mesh_idx]
    if not mesh then return end

    -- Distance pulled from vertical mouse movement
    local dy = (data.drag_start[2] - my) * 0.02
    data.dist = dy

    geom.set_extrude_offset(mesh, data.cap_verts, data.orig_positions, data.normal, dy)
    doc.rebuild_model(data.mesh_idx)
end

-- ── Modal Tool: Move (G) ────────────────────────────────────────────────────
function doc.start_move(mx, my)
    if doc.action then return end
    local mesh = doc.get_active_mesh()
    if not mesh then return end

    local vert_indices = {}
    local orig_positions = {}

    if doc.mode == 1 and doc.selected_vert_idx then
        local vi = doc.selected_vert_idx
        local v = mesh.verts[vi]
        if not v then return end
        vert_indices = { vi }
        orig_positions = { { x = v.x, y = v.y, z = v.z } }
    elseif doc.mode == 2 and doc.selected_edge then
        local e = doc.selected_edge
        local v1 = mesh.verts[e.vi1]
        local v2 = mesh.verts[e.vi2]
        if not (v1 and v2) then return end
        vert_indices = { e.vi1, e.vi2 }
        orig_positions = {
            { x = v1.x, y = v1.y, z = v1.z },
            { x = v2.x, y = v2.y, z = v2.z },
        }
    elseif doc.selected_face_idx and mesh.faces[doc.selected_face_idx] then
        local face = mesh.faces[doc.selected_face_idx]
        local touched = {}
        for _, vi in ipairs(face.verts) do
            if not touched[vi] then
                touched[vi] = true
                vert_indices[#vert_indices + 1] = vi
                local v = mesh.verts[vi]
                orig_positions[#orig_positions + 1] = { x = v.x, y = v.y, z = v.z }
            end
        end
    else
        doc.status_msg = "Select a vertex, edge, or face to move"
        return
    end

    doc.action_orig = doc.snapshot()

    doc.action = "move"
    doc.action_data = {
        mesh_idx = doc.selected_mesh_idx,
        face_idx = doc.selected_face_idx,
        vert_indices = vert_indices,
        orig_positions = orig_positions,
        drag_start = { mx or 0, my or 0 },
        delta = { 0, 0, 0 },
    }
    doc.status_msg = "Moving: drag mouse in view plane"
end

function doc.update_move(mx, my, cam)
    if doc.action ~= "move" or not doc.action_data then return end
    local data = doc.action_data
    local mesh = doc.meshes[data.mesh_idx]
    if not mesh then return end

    local dmx = mx - data.drag_start[1]
    local dmy = my - data.drag_start[2]

    -- Camera basis for view-plane movement
    local ry = (cam and cam.yaw or 45.0) * math.pi / 180.0
    local rp = (cam and cam.pitch or 30.0) * math.pi / 180.0
    local dist = (cam and cam.dist or 8.0)

    local right_x = math.cos(ry)
    local right_y = 0
    local right_z = -math.sin(ry)

    local up_x = -math.sin(rp) * math.sin(ry)
    local up_y = math.cos(rp)
    local up_z = -math.sin(rp) * math.cos(ry)

    local scale = dist * 0.002
    local delta_vec = {
        (dmx * right_x - dmy * up_x) * scale,
        (dmx * right_y - dmy * up_y) * scale,
        (dmx * right_z - dmy * up_z) * scale,
    }
    data.delta = delta_vec
    geom.set_move_positions(mesh, data.vert_indices, data.orig_positions, delta_vec)
    doc.rebuild_model(data.mesh_idx)
end
-- ── Modal Confirm / Cancel ──────────────────────────────────────────────────
function doc.confirm_action()
    if not doc.action then return end
    local label = (doc.action == "extrude") and "Extrude Face" or "Move Face"
    if doc.action_orig then
        undo.push(label, doc.action_orig)
    end
    doc.action = nil
    doc.action_orig = nil
    doc.action_data = nil
    doc.dirty = true
    -- Restore textured rendering on the edited mesh (canvas/perlin binding).
    doc.rebuild_model(doc.selected_mesh_idx)
    doc.status_msg = label .. " committed"
end

function doc.cancel_action()
    if not doc.action then return end
    if doc.action_orig then
        doc.restore(doc.action_orig)
    end
    local label = doc.action
    doc.action = nil
    doc.action_orig = nil
    doc.action_data = nil
    doc.rebuild_model(doc.selected_mesh_idx)
    doc.status_msg = label .. " cancelled"
end

-- ── Vertex Painting ─────────────────────────────────────────────────────────
function doc.paint_stroke(mx, my)
    if doc.action then return end
    local ox, oy, oz, dx, dy, dz = lp.rl.get_ray(mx, my)
    local ray_orig = { ox, oy, oz }
    local ray_dir = { dx, dy, dz }

    local best_dist = math.huge
    local best_mesh_idx = nil
    local best_mesh = nil
    local best_hit = nil

    for m_idx, mesh in ipairs(doc.meshes) do
        local hit = geom.raycast_mesh(mesh, ray_orig, ray_dir)
        if hit and hit.dist < best_dist then
            best_dist = hit.dist
            best_mesh_idx = m_idx
            best_mesh = mesh
            best_hit = hit
        end
    end

    if best_mesh and best_hit then
        undo.begin_coalesce("Vertex Paint", doc.snapshot())
        local mod = geom.paint_vertices(best_mesh, best_hit.hit_point,
            doc.brush.radius, doc.brush.color, doc.brush.strength, doc.brush.hardness)
        if mod then
            doc.rebuild_model(best_mesh_idx)
            doc.dirty = true
            doc.status_msg = "Painting vertex colors"
        end
        return true, best_hit.hit_point
    end

    return false, nil
end

function doc.end_paint_stroke()
    undo.commit_coalesce()
end

-- ── 2D Texture Canvas (mode 5) ──────────────────────────────────────────────
-- The offscreen canvas (lp.tex.*) is the 2D surface of the template. It
-- shares the vertex-paint brush (radius/color/strength), so one settings
-- block drives both surfaces. GL calls (upload) are deferred to render time;
-- these functions run only from the render path, never from --test.

function doc.canvas_init()
    if doc.canvas.tex_id then return doc.canvas.tex_id end
    local tid = lp.tex.create(512, 512)
    doc.canvas.tex_id = tid
    lp.tex.clear(tid, 0xFFFFFFFF) -- white canvas
    lp.tex.upload(tid)
    return tid
end

-- The 2D→3D bridge: bind the canvas texture to a mesh's GPU model material.
function doc.canvas_apply_to(mesh_idx)
    local mesh = doc.meshes[mesh_idx]
    if not mesh or not mesh.model_id or not doc.canvas.tex_id then return false end
    lp.tex.apply_to_model(doc.canvas.tex_id, mesh.model_id)
    doc.canvas.applied_mesh_idx = mesh_idx
    mesh.tex_binding = { kind = "canvas" }  -- survives model rebuilds
    doc.dirty = true
    doc.status_msg = "Canvas texture applied to " .. (mesh.name or "Mesh")
    return true
end

-- Brush radius in canvas texels (shared with the vertex-paint brush).
function doc.brush_px()
    return (doc.brush.radius or 1.2) * 32.0
end

function doc.canvas_stroke(wx, wy)
    local tid = doc.canvas.tex_id
    if not tid then return false end
    local px = doc.brush_px()
    local bc = doc.brush.color
    local strength = doc.brush.strength or 0.9
    local alpha = math.floor(255.0 * math.max(0.0, math.min(1.0, strength)))
    local hardness = doc.brush.hardness or 0.6
    local spacing = math.max(0.04, math.min(1.0, doc.brush.spacing or 0.20))
    local step_dist = math.max(0.5, px * spacing)

    if not doc.canvas.stroke_active then
        lp.tex.push_undo(tid)
        doc.canvas.stroke_active = true
        doc.canvas.last_stamp = { wx, wy }
        doc.canvas.rem_dist = 0
        lp.tex.stamp(tid, wx, wy, px, hardness, bc[1], bc[2], bc[3], alpha)
        doc.dirty = true
        doc.status_msg = "Painting canvas"
        return true
    end

    local lx, ly = doc.canvas.last_stamp[1], doc.canvas.last_stamp[2]
    local dist = math.sqrt((wx - lx) ^ 2 + (wy - ly) ^ 2)
    if dist < 1e-4 then return true end

    local total = dist + (doc.canvas.rem_dist or 0)
    local num_steps = math.floor(total / step_dist)
    doc.canvas.rem_dist = total - (num_steps * step_dist)

    if num_steps > 0 then
        for i = 1, num_steps do
            local cur_d = (i * step_dist) - (total - dist)
            local t = math.max(0.0, math.min(1.0, cur_d / dist))
            local sx = lx + (wx - lx) * t
            local sy = ly + (wy - ly) * t
            lp.tex.stamp(tid, sx, sy, px, hardness, bc[1], bc[2], bc[3], alpha)
        end
        doc.canvas.last_stamp = { wx, wy }
        doc.dirty = true
        doc.status_msg = "Painting canvas"
    end
    return true
end

function doc.canvas_stroke_end()
    if not doc.canvas.stroke_active then return end
    doc.canvas.stroke_active = false
    doc.canvas.last_stamp = nil
    local tid = doc.canvas.tex_id
    if tid then lp.tex.upload(tid) end
end

function doc.canvas_undo()
    local tid = doc.canvas.tex_id
    if not tid then return end
    if lp.tex.pop_undo(tid) then
        lp.tex.upload(tid)
        doc.status_msg = "Canvas Undo"
    else
        doc.status_msg = "Nothing to undo on canvas"
    end
end

function doc.canvas_redo()
    local tid = doc.canvas.tex_id
    if not tid then return end
    if lp.tex.pop_redo(tid) then
        lp.tex.upload(tid)
        doc.status_msg = "Canvas Redo"
    else
        doc.status_msg = "Nothing to redo on canvas"
    end
end

function doc.canvas_clear()
    local tid = doc.canvas.tex_id
    if not tid then return end
    lp.tex.push_undo(tid)
    lp.tex.clear(tid, 0xFFFFFFFF)
    lp.tex.upload(tid)
    doc.status_msg = "Canvas cleared"
end

-- ── Undo / Redo Dispatchers ─────────────────────────────────────────────────
function doc.perform_undo()
    if doc.action then
        doc.cancel_action()
        return
    end
    local prev_state, label = undo.do_undo(function() return doc.snapshot() end)
    if prev_state then
        doc.restore(prev_state)
        doc.status_msg = "Undo: " .. (label or "Action")
    else
        doc.status_msg = "Nothing to undo"
    end
end

function doc.perform_redo()
    if doc.action then
        doc.cancel_action()
        return
    end
    local next_state, label = undo.do_redo(function() return doc.snapshot() end)
    if next_state then
        doc.restore(next_state)
        doc.status_msg = "Redo: " .. (label or "Action")
    else
        doc.status_msg = "Nothing to redo"
    end
end

-- ── Export OBJ ──────────────────────────────────────────────────────────────
function doc.export_obj(filepath)
    filepath = filepath or "build/cubeforge_model.obj"
    -- Ensure the parent dir exists (works in dev and packaged layouts)
    local dir = filepath:match("^(.*)[/\\][^/\\]*$")
    if dir and dir ~= "" and lp and lp.file then
        lp.file.mkdirs(dir)
    end
    local ok, err = geom.export_obj(doc.meshes, filepath)
    if ok then
        doc.status_msg = "Exported OBJ to " .. filepath
        return true, filepath
    else
        doc.status_msg = "Export failed: " .. tostring(err)
        return false, err
    end
end

-- Initialize default document state on load
doc.init_default()

return doc
