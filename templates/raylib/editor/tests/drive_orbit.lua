-- editor/tests/drive_orbit.lua — headless interactive drive tape.
-- Exercises:
-- 1. Middle-drag camera tilt -> asserts camera eye moved
-- 2. Spawning cylinder primitive via toolbar click -> asserts mesh count
-- 3. Extruding face via 'E' key + mouse drag + Enter confirm -> asserts vertex/face count
--
-- Run: build/cubeforge-raylib --shot build/shot_orbit.png --frames 40 \
--        --drive editor/tests/drive_orbit.lua
local D = require("drive")
local doc = require("doc")

-- 1. Right-drag orbit from screen center to the left by 160px over 12 frames.
D.drag(2, 640, 400, 480, 400, 12, 2)   -- btn 2 = middle: tilt camera

-- 2. Click "+ Cylinder" button on the top toolbar at (240, 24) on frame 18
D.click(18, 240, 24, 0)

-- 3. Start Extrude (E) on frame 24
D.tap(24, D.Key.E)

-- 4. Drag mouse up by 100px to pull extrusion distance along face normal
D.drag(26, 500, 400, 500, 300, 6, 0)

-- 5. Confirm Extrude via Enter on frame 34
D.tap(34, D.Key.Enter)

-- 6. Assertions on frame 38
D.at(38, function()
    local c = lp.rl.get_camera()
    print(string.format("[drive] Camera: eye (%.2f, %.2f, %.2f) target (%.2f, %.2f, %.2f)",
        c.eye_x, c.eye_y, c.eye_z, c.target_x, c.target_y, c.target_z))

    -- Assert Camera orbited
    if c.eye_x < 5.4 then
        print("[drive] FAIL: camera did not orbit (eye_x=" .. string.format("%.2f", c.eye_x) .. ")")
        os.exit(1)
    end
    print("[drive] OK: Camera orbited successfully")

    -- Assert Cylinder spawned (mesh count >= 2)
    if #doc.meshes < 2 then
        print(string.format("[drive] FAIL: expected at least 2 meshes, got %d", #doc.meshes))
        os.exit(1)
    end
    print(string.format("[drive] OK: Primitives spawned (#meshes=%d)", #doc.meshes))

    -- Assert Extrusion committed (new cylinder top face extruded -> more faces)
    local active_m = doc.get_active_mesh()
    print(string.format("[drive] Active mesh '%s': %d verts, %d faces",
        active_m.name, #active_m.verts, #active_m.faces))
    if #active_m.faces < 18 then
        print(string.format("[drive] FAIL: expected extruded cylinder with >= 18 faces, got %d", #active_m.faces))
        os.exit(1)
    end
    print("[drive] OK: Extrusion committed successfully")

    print("[drive] ALL INTERACTION ASSERTIONS PASSED")
end)
