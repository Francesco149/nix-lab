-- editor/tests/testmain.lua — headless boot + binding checks (--test mode)
print("== test_bindings ==")
local ig, rl, drive = lp.ig, lp.rl, lp.drive
local fails = 0
local function ok(cond, msg)
    if cond then print("  ok   " .. msg) else print("  FAIL " .. msg); fails = fails + 1 end
end

-- Scoped ImGui wrappers (the "Missing EndChild" fix must be present)
ok(type(ig.window) == "function", "ig.window scoped wrapper")
ok(type(ig.child) == "function", "ig.child scoped wrapper")
ok(type(ig.popup) == "function", "ig.popup scoped wrapper")
ok(type(ig.tab_bar) == "function", "ig.tab_bar scoped wrapper")

-- Complex-3D raylib surface (the "complex 3D from Lua" hypothesis)
ok(type(rl.load_model_cube) == "function", "rl.load_model_cube")
ok(type(rl.load_texture_perlin) == "function", "rl.load_texture_perlin")
ok(type(rl.load_shader) == "function", "rl.load_shader")
ok(type(rl.set_material_texture) == "function", "rl.set_material_texture")
ok(type(rl.set_material_shader) == "function", "rl.set_material_shader")
ok(type(rl.set_shader_value_vec3) == "function", "rl.set_shader_value_vec3")
ok(type(rl.draw_model) == "function", "rl.draw_model")
ok(type(rl.load_model_cylinder) == "function", "rl.load_model_cylinder")
ok(type(rl.draw_triangle_3d) == "function", "rl.draw_triangle_3d")
ok(type(rl.draw_cylinder) == "function", "rl.draw_cylinder")
ok(type(rl.draw_cylinder_wires) == "function", "rl.draw_cylinder_wires")
ok(type(rl.world_to_screen) == "function", "rl.world_to_screen")

-- Headless drive surface
ok(type(drive.mouse) == "function", "drive.mouse")
ok(type(drive.button) == "function", "drive.button")
ok(type(drive.key) == "function", "drive.key")
ok(type(drive.frame) == "function", "drive.frame")

-- 2D surface: offscreen canvas (lp.tex.*), 2D camera (lp.cam2d.*), world-space
-- 2D draw bindings (lp.rl.*). All CPU-side behavior — no GL is touched here.
local tex, cam2d = lp.tex, lp.cam2d
ok(type(tex) == "table", "lp.tex registry")
ok(type(tex.create) == "function", "tex.create")
ok(type(tex.stamp) == "function", "tex.stamp")
ok(type(tex.get_pixel) == "function", "tex.get_pixel")
ok(type(tex.set_pixel) == "function", "tex.set_pixel")
ok(type(tex.clear) == "function", "tex.clear")
ok(type(tex.upload) == "function", "tex.upload")
ok(type(tex.export_png) == "function", "tex.export_png")
ok(type(tex.push_undo) == "function", "tex.push_undo")
ok(type(tex.pop_undo) == "function", "tex.pop_undo")
ok(type(tex.push_redo) == "function", "tex.push_redo")
ok(type(tex.pop_redo) == "function", "tex.pop_redo")
ok(type(tex.can_undo) == "function", "tex.can_undo")
ok(type(tex.can_redo) == "function", "tex.can_redo")
ok(type(tex.apply_to_model) == "function", "tex.apply_to_model")
ok(type(tex.texture_id) == "function", "tex.texture_id")
ok(type(cam2d.set) == "function", "cam2d.set")
ok(type(cam2d.get) == "function", "cam2d.get")
ok(type(rl.screen_to_world) == "function", "rl.screen_to_world")
ok(type(rl.draw_texture) == "function", "rl.draw_texture")
ok(type(rl.draw_line_2d) == "function", "rl.draw_line_2d")
ok(type(rl.draw_circle_lines_2d) == "function", "rl.draw_circle_lines_2d")
ok(type(rl.draw_rect_2d) == "function", "rl.draw_rect_2d")
ok(type(rl.draw_text_2d) == "function", "rl.draw_text_2d")
ok(type(rl.begin_mode2d) == "function", "rl.begin_mode2d")
ok(type(rl.end_mode2d) == "function", "rl.end_mode2d")
ok(type(rl.draw_sphere_wires) == "function", "rl.draw_sphere_wires")
ok(type(rl.load_model_mesh) == "function", "rl.load_model_mesh")
ok(type(rl.set_mouse_cursor) == "function", "rl.set_mouse_cursor")
ok(rl.CURSOR_RESIZE_EW ~= nil, "rl.CURSOR_RESIZE_EW constant")
ok(rl.CURSOR_HAND ~= nil, "rl.CURSOR_HAND constant")
ok(type(rl.set_window_size) == "function", "rl.set_window_size")
ok(type(rl.get_monitor_size) == "function", "rl.get_monitor_size")
ok(type(rl.set_window_position) == "function", "rl.set_window_position")
ok(type(rl.get_window_position) == "function", "rl.get_window_position")
ok(type(rl.set_lighting_enabled) == "function", "rl.set_lighting_enabled")
ok(type(rl.is_lighting_enabled) == "function", "rl.is_lighting_enabled")
ok(type(rl.set_target_fps) == "function", "rl.set_target_fps")
ok(type(rl.get_target_fps) == "function", "rl.get_target_fps")
ok(type(rl.get_monitor_refresh_rate) == "function", "rl.get_monitor_refresh_rate")
ok(type(ig.plot_lines) == "function", "ig.plot_lines")
ok(type(ig.icon) == "table", "ig.icon table exists")
ok(type(ig.icon.CUBE) == "string", "ig.icon.CUBE is string")
ok(type(ig.icon.EXTRUDE) == "string", "ig.icon.EXTRUDE is string")
ok(type(ig.icon.UNDO) == "string", "ig.icon.UNDO is string")
ok(type(ig.icon.PAINT) == "string", "ig.icon.PAINT is string")
ok(type(ig.icon.GRIP) == "string", "ig.icon.GRIP is string")
ok(type(lp.app.get_app_name) == "function", "lp.app.get_app_name")
ok(type(lp.app.get_app_title) == "function", "lp.app.get_app_title")
ok(type(lp.app.set_app_name) == "function", "lp.app.set_app_name")
ok(lp.app.get_app_name() == "cubeforge", "default app name is cubeforge")
ok(lp.app.get_app_title() == "CubeForge", "default app title is CubeForge")
lp.app.set_app_name("testapp", "TestApp")
ok(lp.app.get_app_name() == "testapp", "get_app_name returns updated testapp")
ok(lp.app.get_app_title() == "TestApp", "get_app_title returns updated TestApp")
lp.app.set_app_name("cubeforge", "CubeForge") -- restore default
ok(type(lp.app.get_config_dir) == "function", "lp.app.get_config_dir")
ok(type(lp.app.get_data_dir) == "function", "lp.app.get_data_dir")
ok(type(lp.app.get_documents_dir) == "function", "lp.app.get_documents_dir")
ok(type(lp.app.get_projects_dir) == "function", "lp.app.get_projects_dir")
ok(type(lp.app.save_user_file) == "function", "lp.app.save_user_file")
ok(type(lp.app.load_user_file) == "function", "lp.app.load_user_file")
ok(type(lp.app.resolve_asset) == "function", "lp.app.resolve_asset")

-- User settings & path persistence test
local cfg_dir = lp.app.get_config_dir()
ok(cfg_dir ~= nil and #cfg_dir > 0, "get_config_dir returns valid path (" .. tostring(cfg_dir) .. ")")
local proj_dir = lp.app.get_projects_dir()
ok(proj_dir ~= nil and #proj_dir > 0, "get_projects_dir returns valid path (" .. tostring(proj_dir) .. ")")

local save_ok, save_path = lp.app.save_user_file("cubeforge_test_settings.json", '{"theme":"dark","version":1}')
ok(save_ok == true, "save_user_file writes successfully")
local loaded_str = lp.app.load_user_file("cubeforge_test_settings.json")
ok(loaded_str ~= nil and loaded_str:find('"theme":"dark"') ~= nil, "load_user_file reads saved content")

local resolved_font = lp.app.resolve_asset("fonts/InterVariable.ttf")
ok(resolved_font ~= nil and #resolved_font > 0, "resolve_asset returns resolved font path")

-- Behavior: canvas create → white; stamp paints; undo restores; export writes.
local tid = tex.create(64, 64)
ok(tid ~= nil, "tex.create returns an id")
ok(tex.get_pixel(tid, 10, 10) == 0xFFFFFFFF, "canvas starts white (0xFFFFFFFF)")

tex.set_pixel(tid, 10, 10, 0xFF0000FF)
ok(tex.get_pixel(tid, 10, 10) == 0xFF0000FF, "set_pixel round-trip (0xRRGGBBAA)")

tex.stamp(tid, 32, 32, 8, 1.0, 255, 0, 0, 255)
ok(tex.get_pixel(tid, 32, 32) == 0xFF0000FF, "stamp center painted red")
ok(tex.get_pixel(tid, 0, 0) == 0xFFFFFFFF, "stamp did not paint outside radius")
ok(tex.get_pixel(tid, 40, 32) == 0xFFFFFFFF, "stamp edge at exact radius unchanged")

-- Undo: snapshot, break the pixel, restore
tex.push_undo(tid)
tex.stamp(tid, 40, 40, 6, 1.0, 0, 0, 255, 255)
ok(tex.get_pixel(tid, 40, 40) == 0x0000FFFF, "second stamp painted blue")
ok(tex.pop_undo(tid) == true, "pop_undo returns true when a state exists")
ok(tex.get_pixel(tid, 40, 40) == 0xFFFFFFFF, "undo restored pre-stamp pixel")
ok(tex.get_pixel(tid, 32, 32) == 0xFF0000FF, "undo kept the earlier red stamp")
ok(tex.can_redo(tid) == true, "can_redo true after undo")

-- Redo: restore the blue stamp
ok(tex.pop_redo(tid) == true, "pop_redo returns true when a state exists")
ok(tex.get_pixel(tid, 40, 40) == 0x0000FFFF, "redo restored the blue stamp")
ok(tex.can_undo(tid) == true, "can_undo true after redo")

-- New action (push_undo) invalidates redo
tex.push_undo(tid)
ok(tex.can_redo(tid) == false, "push_undo clears the redo stack")

-- Empty-stack pops report false, not errors (fresh canvas, untouched stacks)
local tid2 = tex.create(8, 8)
ok(tex.pop_undo(tid2) == false, "pop_undo on empty stack returns false")
ok(tex.pop_redo(tid2) == false, "pop_redo on empty stack returns false")

-- clear fills the whole canvas
tex.clear(tid, 0x000000FF)
ok(tex.get_pixel(tid, 5, 5) == 0x000000FF, "clear fills with the given color")
tex.clear(tid, 0xFFFFFFFF)

-- export_png writes a real file (mkdirs the parent)
local okp = tex.export_png(tid, "build/canvas_test.png")
ok(okp == true, "export_png returns true")
local pf = io.open("build/canvas_test.png", "rb")
ok(pf ~= nil, "exported PNG exists on disk")
if pf then pf:close() end

-- apply_to_model validates ids (no GL in --test, so valid-id path is exercised
-- by the drive tapes: drive_paint3d.lua binds the canvas to the cube model)
ok(pcall(tex.apply_to_model, tid, 0) == false, "apply_to_model errors on missing model")
ok(pcall(tex.apply_to_model, 99999, 0) == false, "apply_to_model errors on bad canvas id")

-- cam2d set/get round-trip
cam2d.set(123.0, -45.0, 2.5)
local cx, cy, cz = cam2d.get()
ok(math.abs(cx - 123.0) < 1e-4 and math.abs(cy - (-45.0)) < 1e-4 and math.abs(cz - 2.5) < 1e-4,
    "cam2d set/get round-trip")

-- 2D screen<->world round-trip (both directions use the same camera transform)
cam2d.set(10, 20, 2.0)
local wx, wy = rl.screen_to_world(640, 400)
local sx, sy = rl.world_to_screen(wx, wy)
ok(math.abs(sx - 640) < 1e-3 and math.abs(sy - 400) < 1e-3, "2D screen/world round-trip")
local w2x, w2y = rl.screen_to_world(sx, sy)
ok(math.abs(w2x - wx) < 1e-3 and math.abs(w2y - wy) < 1e-3, "2D world/screen round-trip")
-- world_to_screen with 3 args still resolves against the 3D camera (dispatch)
local p3x, p3y = rl.world_to_screen(0, 0, 0)
ok(p3x ~= nil and p3y ~= nil, "world_to_screen 3-arg (3D) dispatch intact")

-- Constants
ok(ig.key.G ~= nil, "ig.key.G")
ok(rl.MAP_ALBEDO ~= nil, "rl.MAP_ALBEDO")
ok(rl.UNIFORM_VEC3 ~= nil, "rl.UNIFORM_VEC3")
ok(rl.key.E ~= nil, "rl.key.E")
ok(rl.key.LeftCtrl ~= nil, "rl.key.LeftCtrl")
ok(rl.key.LeftShift ~= nil, "rl.key.LeftShift")

-- ── CubeForge Logic & Invariant Tests ────────────────────────────────────────
print("== test_cubeforge_logic ==")
local geom = require("geom")
local undo = require("undo")
local doc = require("doc")

-- 1. Primitive Generation
local box = geom.create_box(0, 1, 0, 2, 2, 2)
ok(#box.verts == 8, "create_box 8 vertices")
ok(#box.faces == 6, "create_box 6 quad faces")
ok(box.faces[3].normal[2] > 0.99, "create_box top face normal is +Y")

local cyl = geom.create_cylinder(0, 1, 0, 1.0, 2.0, 16)
ok(#cyl.verts == 32, "create_cylinder 32 vertices (16 top + 16 bot)")
ok(#cyl.faces == 18, "create_cylinder 18 faces (2 caps + 16 sides)")
ok(cyl.faces[1].normal[2] > 0.99, "create_cylinder top cap normal is +Y")
ok(cyl.faces[2].normal[2] < -0.99, "create_cylinder bottom cap normal is -Y")

-- 2. Möller–Trumbore Raycasting
local ray_orig = { 0, 5, 0 }
local ray_dir = { 0, -1, 0 }
local hit = geom.raycast_mesh(box, ray_orig, ray_dir)
ok(hit ~= nil, "raycast hits box from above")
ok(hit and hit.face_idx == 3, "raycast hits top face #3")
ok(hit and math.abs(hit.dist - 3.0) < 1e-4, "raycast distance is 3.0 (from y=5 to y=2)")
ok(hit and math.abs(hit.hit_point[2] - 2.0) < 1e-4, "hit point y is 2.0")

-- Ray from behind should NOT hit top face (front-face culling)
local hit_back = geom.raycast_mesh(box, { 0, -1, 0 }, { 0, -1, 0 })
ok(hit_back == nil, "raycast from behind culled by front-face normal")

-- 3. Extrusion
local initial_verts = #box.verts
local initial_faces = #box.faces
geom.extrude_face(box, 3, 1.5) -- Extrude top face by 1.5 units along +Y
ok(#box.verts == initial_verts + 4, "extrude adds 4 new cap vertices")
ok(#box.faces == initial_faces + 4, "extrude adds 4 new side quad faces")
-- Verify cap vertices moved to y = 2.0 + 1.5 = 3.5
local cap_face = box.faces[3]
for _, vi in ipairs(cap_face.verts) do
    ok(math.abs(box.verts[vi].y - 3.5) < 1e-4, "extruded cap vertex moved to y=3.5")
end

-- Double Extrude
geom.extrude_face(box, 3, 1.0) -- Extrude top face again by 1.0 units
ok(#box.verts == initial_verts + 8, "double extrude adds 8 total vertices")
ok(#box.faces == initial_faces + 8, "double extrude adds 8 total side faces")
for _, vi in ipairs(box.faces[3].verts) do
    ok(math.abs(box.verts[vi].y - 4.5) < 1e-4, "second extruded cap vertex moved to y=4.5")
end

-- 4. Move Face
geom.move_face(box, 3, { 0.5, 0, 0 })
for _, vi in ipairs(box.faces[3].verts) do
    ok(math.abs(box.verts[vi].y - 4.5) < 1e-4, "move preserves y=4.5")
end

-- 5. Vertex Painting
local v_paint_mesh = geom.create_box(0, 0, 0, 2, 2, 2, { 100, 100, 100, 255 })
local hit_pt = { -1, -1, -1 } -- Position of vertex 1
local painted = geom.paint_vertices(v_paint_mesh, hit_pt, 1.0, { 255, 0, 0 }, 1.0)
ok(painted == true, "paint_vertices modified vertex")
ok(v_paint_mesh.verts[1].r > 200, "vertex 1 painted red (r > 200)")
ok(v_paint_mesh.verts[7].r == 100, "distant vertex 7 unchanged")

-- 6. Undo / Redo System
doc.init_default()
ok(#doc.meshes == 1, "doc initialized with 1 box")
doc.add_cylinder()
ok(#doc.meshes == 2, "doc now has 2 meshes (box + cylinder)")
doc.perform_undo()
ok(#doc.meshes == 1, "undo restores 1 mesh")
doc.perform_redo()
ok(#doc.meshes == 2, "redo restores 2 meshes")

-- 7. Rapid Undo/Redo during active modal action (Gate 7)
doc.start_extrude(100, 100)
ok(doc.action == "extrude", "modal extrude started")
doc.perform_undo() -- rapid undo during modal
ok(doc.action == nil, "rapid undo cancels modal cleanly with zero corruption")
ok(#doc.meshes == 2, "mesh state remains intact")

-- 8. 10 Boxes Spawned Performance (Gate 6)
doc.init_default()
local t0 = os.clock()
for i = 2, 10 do
    doc.add_box()
end
local elapsed = os.clock() - t0
ok(#doc.meshes == 10, "10 boxes spawned successfully")
ok(elapsed < 0.1, string.format("10 boxes spawned in %.4fs (no slowdown)", elapsed))

-- 9. Wavefront OBJ Export (Gate 9)
local ok_export, exp_path = doc.export_obj("build/test_export.obj")
ok(ok_export == true, "OBJ exported successfully")
local exp_f = io.open("build/test_export.obj", "r")
ok(exp_f ~= nil, "exported OBJ file exists and readable")
if exp_f then
    local content = exp_f:read("*a")
    exp_f:close()
    ok(content:find("v ") ~= nil, "OBJ contains vertex data (v ...)")
    ok(content:find("f ") ~= nil, "OBJ contains face data (f ...)")
    ok(content:find("vn ") ~= nil, "OBJ contains normal data (vn ...)")
end

-- mesh_to_gl: flat face-corner expansion, 12 floats/vertex + triangles.
local geom = require("geom")
local docm = require("doc")
local m0 = docm.meshes[1]
if m0 then
    local vf, idx = geom.mesh_to_gl(m0)
    ok(type(vf) == "table" and #vf % 12 == 0 and #vf > 0, "mesh_to_gl emits 12 floats/vertex")
    ok(type(idx) == "table" and #idx % 3 == 0 and #idx > 0, "mesh_to_gl emits triangles")
else
    ok(false, "doc has a default mesh for mesh_to_gl")
end

-- 10. Image import pipeline (shared by drag&drop / paste / file picker).
-- CPU-side only (export_png + load_image_from_file + get_pixel work in --test).
ok(type(rl.is_file_dropped) == "function", "rl.is_file_dropped")
ok(type(rl.take_dropped_file) == "function", "rl.take_dropped_file")
ok(type(rl.get_clipboard_text) == "function", "rl.get_clipboard_text")
ok(type(tex.load_image_from_file) == "function", "tex.load_image_from_file")
ok(type(lp.app.open_file_dialog) == "function", "app.open_file_dialog")
ok(type(lp.file.list_dir) == "function", "file.list_dir")
ok(type(lp.file.exists) == "function", "file.exists")

-- In-app file browser: lists the repo's own files (headless-safe)
local fdirs, ffiles = lp.file.list_dir(".")
ok(type(fdirs) == "table" and type(ffiles) == "table", "list_dir returns dirs + files tables")
ok(lp.file.exists("editor/lua/main.lua") == true or lp.file.exists("lua/main.lua") == true, "file.exists finds main.lua")
ok(lp.file.exists("definitely_missing_xyz") == false, "file.exists false for missing")

-- Rejection: nonexistent / unsupported paths return false, canvas untouched
local imp_tid = tex.create(32, 32)
ok(imp_tid ~= nil, "import test canvas created")
local px_before = tex.get_pixel(imp_tid, 5, 5)
local ok_bad = tex.load_image_from_file(imp_tid, "build/does_not_exist.png")
ok(ok_bad == false, "load_image_from_file rejects missing file")
ok(tex.get_pixel(imp_tid, 5, 5) == px_before, "rejected import leaves canvas untouched")

-- Round-trip: export red → import → pixels identical
tex.clear(imp_tid, 0xFF0000FF)
ok(tex.export_png(imp_tid, "build/import_roundtrip.png") == true, "export_png for round-trip")
local ok_good = tex.load_image_from_file(imp_tid, "build/import_roundtrip.png")
ok(ok_good == true, "load_image_from_file loads exported png")
ok(tex.get_pixel(imp_tid, 5, 5) == 0xFF0000FF, "round-trip preserves pixel data")


-- 11. Selection Modes (Mode 1: Vertex, Mode 2: Edge, Mode 3: Face)
local test_box = geom.create_box(0, 1, 0, 2, 2, 2)
local ray_orig = { 0, 5, 0 }
local ray_dir = { 0, -1, 0 }

-- Mode 1: pick_vertex finds top vertex
local vi, vd = geom.pick_vertex(test_box, { 1, 5, 1 }, { 0, -1, 0 }, 0.5)
ok(vi ~= nil and vd < 0.1, "geom.pick_vertex finds close vertex")

-- Mode 2: dist_point_to_segment
local p_seg = geom.dist_point_to_segment({ 0, 2, 1 }, { x = -1, y = 2, z = 1 }, { x = 1, y = 2, z = 1 })
ok(p_seg < 1e-5, "dist_point_to_segment zero for point on segment")

-- Centroid calculation
local c_top = geom.calc_face_centroid(test_box.verts, test_box.faces[3].verts)
ok(math.abs(c_top[1]) < 1e-5 and math.abs(c_top[2] - 2.0) < 1e-5 and math.abs(c_top[3]) < 1e-5, "calc_face_centroid returns top face center (0, 2, 0)")

-- 12. Low-resolution responsive layout calculations (800x600, 640x480)
local function test_responsive_layout(sw, sh)
    local max_sidebar = math.max(180, sw - 120)
    local panel_w = math.max(180, math.min(280, max_sidebar))
    local vp_w = math.max(60, sw - panel_w)
    local tb_w = math.min(540, vp_w - 16)
    local tb_x = math.max(8, (vp_w - tb_w) * 0.5)
    return (tb_x >= 8) and (tb_x + tb_w <= vp_w) and (panel_w <= sw) and (vp_w > 0)
end
ok(test_responsive_layout(1280, 800) == true, "responsive layout at 1280x800")
ok(test_responsive_layout(800, 600) == true, "responsive layout at 800x600")
ok(test_responsive_layout(640, 480) == true, "responsive layout at 640x480")
if fails > 0 then
    print(string.format("FAIL: %d checks failed", fails))
    os.exit(1)
end
print("All binding and logic checks passed")
os.exit(0)
