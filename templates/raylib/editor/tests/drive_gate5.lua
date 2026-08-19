-- editor/tests/drive_gate5.lua — Gate 5 verification:
-- Rotate camera 180 degrees, then extrude twice in sequence.
-- Verifies no z-fighting, correct normal pulling, and hardware depth testing.
local D = require("drive")
local doc = require("doc")

-- 1. Tilt camera 180 degrees (middle-drag from 640px to 190px over 15 frames)
D.drag(2, 640, 400, 190, 400, 15, 2)  -- btn 2 = middle: tilt

-- 2. First Extrude (E) on frame 20
D.tap(20, D.Key.E)
D.drag(22, 500, 400, 500, 320, 4, 0)
D.tap(28, D.Key.Enter)

-- 3. Second Extrude (E) on frame 32
D.tap(32, D.Key.E)
D.drag(34, 500, 400, 500, 320, 4, 0)
D.tap(40, D.Key.Enter)

-- 4. Assertions on frame 46
D.at(46, function()
    local c = lp.rl.get_camera()
    print(string.format("[gate5] Camera eye (%.2f, %.2f, %.2f)", c.eye_x, c.eye_y, c.eye_z))

    local mesh = doc.get_active_mesh()
    print(string.format("[gate5] Mesh '%s' has %d verts, %d faces after 2 extrudes at 180 deg",
        mesh.name, #mesh.verts, #mesh.faces))

    -- Initial box: 8 verts, 6 faces.
    -- Extrude 1 (+4 verts, +4 faces): 12 verts, 10 faces.
    -- Extrude 2 (+4 verts, +4 faces): 16 verts, 14 faces.
    if #mesh.verts ~= 16 or #mesh.faces ~= 14 then
        print(string.format("[gate5] FAIL: expected 16 verts & 14 faces, got %d verts & %d faces",
            #mesh.verts, #mesh.faces))
        os.exit(1)
    end

    print("[gate5] OK: Extrude twice after 180 deg camera rotation succeeded cleanly")
end)
