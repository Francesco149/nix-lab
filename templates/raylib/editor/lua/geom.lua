-- editor/lua/geom.lua — 3D geometry, mesh generation, raycasting, extrude, and OBJ export for CubeForge
local geom = {}

-- ── Vector Math ─────────────────────────────────────────────────────────────
function geom.vec3(x, y, z)
    return { x or 0, y or 0, z or 0 }
end

function geom.add(a, b)
    return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

function geom.sub(a, b)
    return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

function geom.scale(a, s)
    return { a[1] * s, a[2] * s, a[3] * s }
end

function geom.dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

function geom.cross(a, b)
    return {
        a[2] * b[3] - a[3] * b[2],
        a[3] * b[1] - a[1] * b[3],
        a[1] * b[2] - a[2] * b[1],
    }
end

function geom.length(a)
    return math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
end

function geom.normalize(a)
    local len = geom.length(a)
    if len < 1e-8 then return { 0, 1, 0 } end
    local inv = 1.0 / len
    return { a[1] * inv, a[2] * inv, a[3] * inv }
end

function geom.dist3(x1, y1, z1, x2, y2, z2)
    local dx = x1 - x2
    local dy = y1 - y2
    local dz = z1 - z2
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- ── Distance from 3D point to line segment ─────────────────────────────────
function geom.dist_point_to_segment(p, a, b)
    local ab_x = b.x - a.x
    local ab_y = b.y - a.y
    local ab_z = b.z - a.z
    local ap_x = p[1] - a.x
    local ap_y = p[2] - a.y
    local ap_z = p[3] - a.z
    local ab_len2 = ab_x * ab_x + ab_y * ab_y + ab_z * ab_z
    if ab_len2 < 1e-8 then
        return geom.dist3(p[1], p[2], p[3], a.x, a.y, a.z)
    end
    local t = math.max(0.0, math.min(1.0, (ap_x * ab_x + ap_y * ab_y + ap_z * ab_z) / ab_len2))
    local proj_x = a.x + t * ab_x
    local proj_y = a.y + t * ab_y
    local proj_z = a.z + t * ab_z
    return geom.dist3(p[1], p[2], p[3], proj_x, proj_y, proj_z)
end

-- ── Pick closest vertex to ray ──────────────────────────────────────────────
function geom.pick_vertex(mesh, ray_orig, ray_dir, max_dist)
    max_dist = max_dist or 0.35
    local best_dist = max_dist
    local best_idx = nil
    local best_depth = math.huge

    for v_idx, v in ipairs(mesh.verts) do
        local wx = v.x - ray_orig[1]
        local wy = v.y - ray_orig[2]
        local wz = v.z - ray_orig[3]
        local proj = wx * ray_dir[1] + wy * ray_dir[2] + wz * ray_dir[3]
        if proj > 0 then
            local w_len2 = wx * wx + wy * wy + wz * wz
            local perp2 = w_len2 - (proj * proj)
            if perp2 >= 0 then
                local perp = math.sqrt(perp2)
                if perp < best_dist or (perp < best_dist + 0.05 and proj < best_depth) then
                    best_dist = perp
                    best_depth = proj
                    best_idx = v_idx
                end
            end
        end
    end

    return best_idx, best_dist
end

-- ── Normal Calculation ──────────────────────────────────────────────────────
function geom.calc_face_normal(verts, face_vert_indices)
    if #face_vert_indices < 3 then return { 0, 1, 0 } end
    local v1 = verts[face_vert_indices[1]]
    local v2 = verts[face_vert_indices[2]]
    local v3 = verts[face_vert_indices[3]]
    if not (v1 and v2 and v3) then return { 0, 1, 0 } end

    local e1 = { v2.x - v1.x, v2.y - v1.y, v2.z - v1.z }
    local e2 = { v3.x - v1.x, v3.y - v1.y, v3.z - v1.z }
    local n = geom.cross(e1, e2)
    return geom.normalize(n)
end

function geom.recalc_normals(mesh)
    for _, face in ipairs(mesh.faces) do
        face.normal = geom.calc_face_normal(mesh.verts, face.verts)
    end
end

-- ── Centroid Calculation ────────────────────────────────────────────────────
function geom.calc_face_centroid(verts, face_vert_indices)
    local n = #face_vert_indices
    if n == 0 then return { 0, 0, 0 } end
    local cx, cy, cz = 0, 0, 0
    for _, vi in ipairs(face_vert_indices) do
        local v = verts[vi]
        if v then
            cx = cx + v.x
            cy = cy + v.y
            cz = cz + v.z
        end
    end
    return { cx / n, cy / n, cz / n }
end

-- ── Deep Copy ───────────────────────────────────────────────────────────────
function geom.clone_mesh(mesh)
    local new_verts = {}
    for i, v in ipairs(mesh.verts) do
        new_verts[i] = {
            x = v.x, y = v.y, z = v.z,
            r = v.r or 200, g = v.g or 200, b = v.b or 200, a = v.a or 255,
        }
    end

    local new_faces = {}
    for i, f in ipairs(mesh.faces) do
        local f_verts = {}
        for j, vi in ipairs(f.verts) do f_verts[j] = vi end
        local fn = f.normal and { f.normal[1], f.normal[2], f.normal[3] } or { 0, 1, 0 }
        local fc = f.color and { f.color[1], f.color[2], f.color[3], f.color[4] } or { 180, 180, 180, 255 }
        new_faces[i] = {
            verts = f_verts,
            normal = fn,
            color = fc,
        }
    end

    return {
        id = mesh.id,
        name = mesh.name,
        verts = new_verts,
        faces = new_faces,
        -- Preserve primitive identity + texture binding so undo/restore keeps
        -- the mesh renderable with its texture (perlin/canvas) after edits.
        kind = mesh.kind,
        dims = mesh.dims and { w = mesh.dims.w, h = mesh.dims.h, d = mesh.dims.d, r = mesh.dims.r },
        tex_binding = mesh.tex_binding and { kind = mesh.tex_binding.kind },
    }
end

-- ── Primitive: Box ──────────────────────────────────────────────────────────
function geom.create_box(cx, cy, cz, sx, sy, sz, color)
    cx = cx or 0
    cy = cy or 1
    cz = cz or 0
    sx = (sx or 2.0) * 0.5
    sy = (sy or 2.0) * 0.5
    sz = (sz or 2.0) * 0.5
    local c = color or { 170, 190, 215, 255 }

    local verts = {
        { x = cx - sx, y = cy - sy, z = cz - sz, r = c[1], g = c[2], b = c[3], a = c[4] }, -- 1
        { x = cx + sx, y = cy - sy, z = cz - sz, r = c[1], g = c[2], b = c[3], a = c[4] }, -- 2
        { x = cx + sx, y = cy + sy, z = cz - sz, r = c[1], g = c[2], b = c[3], a = c[4] }, -- 3
        { x = cx - sx, y = cy + sy, z = cz - sz, r = c[1], g = c[2], b = c[3], a = c[4] }, -- 4
        { x = cx - sx, y = cy - sy, z = cz + sz, r = c[1], g = c[2], b = c[3], a = c[4] }, -- 5
        { x = cx + sx, y = cy - sy, z = cz + sz, r = c[1], g = c[2], b = c[3], a = c[4] }, -- 6
        { x = cx + sx, y = cy + sy, z = cz + sz, r = c[1], g = c[2], b = c[3], a = c[4] }, -- 7
        { x = cx - sx, y = cy + sy, z = cz + sz, r = c[1], g = c[2], b = c[3], a = c[4] }, -- 8
    }

    -- 6 Quad faces with outward counter-clockwise winding
    local face_defs = {
        { verts = { 5, 6, 7, 8 }, normal = { 0, 0, 1 } },  -- Front (+Z)
        { verts = { 2, 1, 4, 3 }, normal = { 0, 0, -1 } }, -- Back (-Z)
        { verts = { 8, 7, 3, 4 }, normal = { 0, 1, 0 } },  -- Top (+Y)
        { verts = { 1, 2, 6, 5 }, normal = { 0, -1, 0 } }, -- Bottom (-Y)
        { verts = { 6, 2, 3, 7 }, normal = { 1, 0, 0 } },  -- Right (+X)
        { verts = { 1, 5, 8, 4 }, normal = { -1, 0, 0 } }, -- Left (-X)
    }

    local faces = {}
    for i, fd in ipairs(face_defs) do
        faces[i] = {
            verts = fd.verts,
            normal = fd.normal,
            color = { c[1], c[2], c[3], c[4] },
        }
    end

    return {
        name = "Box",
        verts = verts,
        faces = faces,
    }
end

-- ── Primitive: Cylinder ─────────────────────────────────────────────────────
function geom.create_cylinder(cx, cy, cz, radius, height, slices, color)
    cx = cx or 0
    cy = cy or 1
    cz = cz or 0
    radius = radius or 1.0
    height = height or 2.0
    slices = slices or 16
    local c = color or { 180, 210, 180, 255 }

    local half_h = height * 0.5
    local y_top = cy + half_h
    local y_bot = cy - half_h

    local verts = {}
    -- Top circle vertices (1 .. slices)
    for i = 1, slices do
        local theta = (i - 1) * (2.0 * math.pi / slices)
        local vx = cx + radius * math.cos(theta)
        local vz = cz + radius * math.sin(theta)
        verts[#verts + 1] = { x = vx, y = y_top, z = vz, r = c[1], g = c[2], b = c[3], a = c[4] }
    end

    -- Bottom circle vertices (slices+1 .. 2*slices)
    for i = 1, slices do
        local theta = (i - 1) * (2.0 * math.pi / slices)
        local vx = cx + radius * math.cos(theta)
        local vz = cz + radius * math.sin(theta)
        verts[#verts + 1] = { x = vx, y = y_bot, z = vz, r = c[1], g = c[2], b = c[3], a = c[4] }
    end

    local faces = {}

    -- Top face (fan order: 1, 2, ..., slices) -> normal (0, 1, 0)
    local top_v = {}
    for i = 1, slices do top_v[i] = i end
    faces[#faces + 1] = {
        verts = top_v,
        normal = { 0, 1, 0 },
        color = { c[1], c[2], c[3], c[4] },
    }

    -- Bottom face (reverse fan order) -> normal (0, -1, 0)
    local bot_v = {}
    for i = 1, slices do
        bot_v[i] = slices + (slices - i + 1)
    end
    faces[#faces + 1] = {
        verts = bot_v,
        normal = { 0, -1, 0 },
        color = { c[1], c[2], c[3], c[4] },
    }

    -- Side quad faces
    for i = 1, slices do
        local next_i = (i % slices) + 1
        local t1 = i
        local t2 = next_i
        local b1 = slices + i
        local b2 = slices + next_i

        -- CCW outward winding: b1 -> b2 -> t2 -> t1
        local side_verts = { b1, b2, t2, t1 }
        local norm = geom.calc_face_normal(verts, side_verts)
        faces[#faces + 1] = {
            verts = side_verts,
            normal = norm,
            color = { c[1], c[2], c[3], c[4] },
        }
    end

    return {
        name = "Cylinder",
        verts = verts,
        faces = faces,
    }
end

-- ── Möller–Trumbore Ray-Triangle Intersection ──────────────────────────────
function geom.intersect_triangle(orig, dir, v0, v1, v2)
    local e1 = { v1.x - v0.x, v1.y - v0.y, v1.z - v0.z }
    local e2 = { v2.x - v0.x, v2.y - v0.y, v2.z - v0.z }
    local p = geom.cross(dir, e2)
    local det = geom.dot(e1, p)

    -- Front-face culling: require det > 1e-7
    if det <= 1e-7 then return nil end

    local inv_det = 1.0 / det
    local t_vec = { orig[1] - v0.x, orig[2] - v0.y, orig[3] - v0.z }
    local u = geom.dot(t_vec, p) * inv_det
    if u < 0.0 or u > 1.0 then return nil end

    local q = geom.cross(t_vec, e1)
    local v = geom.dot(dir, q) * inv_det
    if v < 0.0 or (u + v) > 1.0 then return nil end

    local t = geom.dot(e2, q) * inv_det
    if t > 1e-5 then
        local hit = {
            orig[1] + t * dir[1],
            orig[2] + t * dir[2],
            orig[3] + t * dir[3],
        }
        return t, hit
    end

    return nil
end

-- ── Raycast Mesh Faces ──────────────────────────────────────────────────────
function geom.raycast_mesh(mesh, ray_orig, ray_dir)
    local best_t = math.huge
    local best_hit = nil
    local best_face_idx = nil

    local verts = mesh.verts
    for f_idx, face in ipairs(mesh.faces) do
        -- Front-face culling via face normal
        local norm = face.normal or geom.calc_face_normal(verts, face.verts)
        if geom.dot(norm, ray_dir) < 0 then
            local fv = face.verts
            local num_v = #fv
            if num_v >= 3 then
                local v0 = verts[fv[1]]
                -- Fan triangulation
                for i = 2, num_v - 1 do
                    local v1 = verts[fv[i]]
                    local v2 = verts[fv[i + 1]]
                    if v0 and v1 and v2 then
                        local t, hit = geom.intersect_triangle(ray_orig, ray_dir, v0, v1, v2)
                        if t and t < best_t then
                            best_t = t
                            best_hit = hit
                            best_face_idx = f_idx
                        end
                    end
                end
            end
        end
    end

    if best_face_idx then
        return {
            face_idx = best_face_idx,
            dist = best_t,
            hit_point = best_hit,
            normal = mesh.faces[best_face_idx].normal,
        }
    end

    return nil
end

-- ── Extrude Face Operation ──────────────────────────────────────────────────
-- Extrudes the face at face_idx along its normal by distance.
-- Returns new_face_idx (the index of the cap face).
function geom.extrude_face(mesh, face_idx, distance)
    local face = mesh.faces[face_idx]
    if not face then return nil end

    local norm = face.normal or geom.calc_face_normal(mesh.verts, face.verts)
    local orig_verts = face.verts
    local num_v = #orig_verts

    -- 1. Create duplicate vertices for the extruded cap
    local new_vert_indices = {}
    for i, vi in ipairs(orig_verts) do
        local v = mesh.verts[vi]
        local new_v = {
            x = v.x + distance * norm[1],
            y = v.y + distance * norm[2],
            z = v.z + distance * norm[3],
            r = v.r or 200,
            g = v.g or 200,
            b = v.b or 200,
            a = v.a or 255,
        }
        mesh.verts[#mesh.verts + 1] = new_v
        new_vert_indices[i] = #mesh.verts
    end

    -- 2. Create side quad faces connecting original vertices to new cap vertices
    for i = 1, num_v do
        local next_i = (i % num_v) + 1
        local v_orig_a = orig_verts[i]
        local v_orig_b = orig_verts[next_i]
        local v_new_b = new_vert_indices[next_i]
        local v_new_a = new_vert_indices[i]

        -- CCW quad winding: v_orig_a -> v_orig_b -> v_new_b -> v_new_a
        local side_verts = { v_orig_a, v_orig_b, v_new_b, v_new_a }
        local side_norm = geom.calc_face_normal(mesh.verts, side_verts)
        mesh.faces[#mesh.faces + 1] = {
            verts = side_verts,
            normal = side_norm,
            color = { face.color[1], face.color[2], face.color[3], face.color[4] },
        }
    end

    -- 3. Update the original face to use the new cap vertices
    face.verts = new_vert_indices
    face.normal = geom.calc_face_normal(mesh.verts, new_vert_indices)

    return face_idx
end

-- Update in-flight extrusion offset
function geom.set_extrude_offset(mesh, cap_vert_indices, orig_positions, normal, dist)
    for i, vi in ipairs(cap_vert_indices) do
        local op = orig_positions[i]
        if op and mesh.verts[vi] then
            mesh.verts[vi].x = op.x + dist * normal[1]
            mesh.verts[vi].y = op.y + dist * normal[2]
            mesh.verts[vi].z = op.z + dist * normal[3]
        end
    end
    geom.recalc_normals(mesh)
end

-- ── Move Face / Vertices ────────────────────────────────────────────────────
function geom.move_face(mesh, face_idx, delta_vec)
    local face = mesh.faces[face_idx]
    if not face then return end

    local touched = {}
    for _, vi in ipairs(face.verts) do
        if not touched[vi] then
            touched[vi] = true
            local v = mesh.verts[vi]
            if v then
                v.x = v.x + delta_vec[1]
                v.y = v.y + delta_vec[2]
                v.z = v.z + delta_vec[3]
            end
        end
    end
    geom.recalc_normals(mesh)
end

function geom.set_move_positions(mesh, vert_indices, orig_positions, delta_vec)
    for i, vi in ipairs(vert_indices) do
        local op = orig_positions[i]
        local v = mesh.verts[vi]
        if op and v then
            v.x = op.x + delta_vec[1]
            v.y = op.y + delta_vec[2]
            v.z = op.z + delta_vec[3]
        end
    end
    geom.recalc_normals(mesh)
end

-- ── Vertex Painting ─────────────────────────────────────────────────────────
function geom.paint_vertices(mesh, hit_point, radius, target_color, strength, hardness)
    strength = strength or 1.0
    hardness = hardness or 0.6   -- 0 = fully feathered, 1 = hard edge
    local modified = false
    local tr = target_color[1]
    local tg = target_color[2]
    local tb = target_color[3]
    local inner = radius * hardness  -- full-strength core
    local band = radius - inner      -- feathered rim

    for _, v in ipairs(mesh.verts) do
        local d = geom.dist3(v.x, v.y, v.z, hit_point[1], hit_point[2], hit_point[3])
        if d <= radius then
            local falloff
            if d <= inner then
                falloff = 1.0
            else
                local s = (d - inner) / band      -- 0..1 across the rim
                falloff = (1.0 - s) * (1.0 - s)   -- smooth quadratic drop
            end
            falloff = falloff * strength
            falloff = math.max(0.0, math.min(1.0, falloff))
            v.r = math.floor((1.0 - falloff) * (v.r or 200) + falloff * tr + 0.5)
            v.g = math.floor((1.0 - falloff) * (v.g or 200) + falloff * tg + 0.5)
            v.b = math.floor((1.0 - falloff) * (v.b or 200) + falloff * tb + 0.5)
            modified = true
        end
    end

    return modified
end

-- ── OBJ Exporter ────────────────────────────────────────────────────────────
-- ── GPU mesh expansion (flat-shaded, textured-ready) ────────────────────────
-- Converts the Lua doc mesh (shared verts + quads with face normals) into
-- interleaved GL vertex data with ONE vertex per face-corner (classic flat
-- shading), plus planar-projected UVs so a canvas/perlin texture maps onto
-- each face. Format: 12 floats/vertex = pos(3)+color(4)+normal(3)+uv(2),
-- matching lp.rl.load_model_mesh. Used to rebuild GPU models after geometry
-- edits so texture bindings survive.
function geom.mesh_to_gl(mesh)
    local vf, idx = {}, {}
    local vi = 0
    local function emit(x, y, z, r, g, b, a, nx, ny, nz, u, v)
        vf[#vf + 1] = x; vf[#vf + 1] = y; vf[#vf + 1] = z
        vf[#vf + 1] = r; vf[#vf + 1] = g; vf[#vf + 1] = b; vf[#vf + 1] = a
        vf[#vf + 1] = nx; vf[#vf + 1] = ny; vf[#vf + 1] = nz
        vf[#vf + 1] = u; vf[#vf + 1] = v
        vi = vi + 1
    end
    for _, f in ipairs(mesh.faces or {}) do
        local n = f.normal or { 0, 1, 0 }
        local nx, ny, nz = n[1], n[2], n[3]
        -- Collect this face's corners (projected axes per dominant normal)
        local ax, ay = math.abs(nx), math.abs(ny)
        local proj_a, proj_b  -- projection functions → u, v
        if ax >= ay and ax >= math.abs(nz) then
            proj_a, proj_b = function(p) return p.z end, function(p) return p.y end  -- ±X
        elseif ay >= math.abs(nz) then
            proj_a, proj_b = function(p) return p.x end, function(p) return p.z end  -- ±Y
        else
            proj_a, proj_b = function(p) return p.x end, function(p) return p.y end  -- ±Z
        end
        -- First pass: collect corners, compute projected bounds (normalize UV
        -- per face so integer-aligned geometry maps the FULL texture)
        local corners = {}
        local min_a, max_a, min_b, max_b = math.huge, -math.huge, math.huge, -math.huge
        for _, vidx in ipairs(f.verts) do
            local v = mesh.verts[vidx]
            if v then
                local a, b = proj_a(v), proj_b(v)
                if a < min_a then min_a = a end
                if a > max_a then max_a = a end
                if b < min_b then min_b = b end
                if b > max_b then max_b = b end
                corners[#corners + 1] = v
            end
        end
        local span_a = max_a - min_a
        local span_b = max_b - min_b
        local base = vi
        local ncorners = 0
        for _, v in ipairs(corners) do
            local a, b = proj_a(v), proj_b(v)
            local u = span_a > 1e-9 and (a - min_a) / span_a or 0.0
            local uv = span_b > 1e-9 and (b - min_b) / span_b or 0.0
            emit(v.x, v.y, v.z,
                 v.r or 200, v.g or 200, v.b or 200, v.a or 255,
                 nx, ny, nz, u, uv)
            ncorners = ncorners + 1
        end
        -- Triangle fan for the n-gon (raylib indices are triangles)
        for j = 1, ncorners - 2 do
            idx[#idx + 1] = base
            idx[#idx + 1] = base + j
            idx[#idx + 1] = base + j + 1
        end
    end
    return vf, idx
end

function geom.export_obj(meshes, filepath)
    local f, err = io.open(filepath, "w")
    if not f then return false, err end
    f:write("# CubeForge Wavefront OBJ Export\n")
    f:write("# Generated by CubeForge (Raylib + ImGui + Lua)\n\n")

    local vert_offset = 0

    for m_idx, mesh in ipairs(meshes) do
        f:write(string.format("o %s_%d\n", mesh.name or "Mesh", m_idx))

        -- 1. Vertices (with optional per-vertex colors)
        for _, v in ipairs(mesh.verts) do
            local r = (v.r or 200) / 255.0
            local g = (v.g or 200) / 255.0
            local b = (v.b or 200) / 255.0
            f:write(string.format("v %.6f %.6f %.6f %.4f %.4f %.4f\n", v.x, v.y, v.z, r, g, b))
        end

        -- 2. Normals
        for _, face in ipairs(mesh.faces) do
            local n = face.normal or { 0, 1, 0 }
            f:write(string.format("vn %.6f %.6f %.6f\n", n[1], n[2], n[3]))
        end

        -- 3. Faces
        for f_idx, face in ipairs(mesh.faces) do
            f:write("f")
            for _, vi in ipairs(face.verts) do
                local global_vi = vi + vert_offset
                local normal_idx = f_idx + vert_offset
                f:write(string.format(" %d//%d", global_vi, normal_idx))
            end
            f:write("\n")
        end

        f:write("\n")
        vert_offset = vert_offset + #mesh.verts
    end

    f:close()
    return true, filepath
end

return geom
