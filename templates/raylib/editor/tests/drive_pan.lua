-- editor/tests/drive_pan.lua — headless 2D pan verification (shot-pan target).
-- Proves the 2D surface's camera doctrine: in texture-paint mode (mode 5) a
-- middle-button drag pans the 2D viewport (lp.cam2d), not the 3D camera.
--
-- Run: build/cubeforge-raylib --shot build/shot_pan.png --frames 30 \
--        --drive editor/tests/drive_pan.lua
local D = require("drive")
local doc = require("doc")

-- 1. Enter 2D texture-paint mode (tap 5)
D.tap(2, D.Key.Five)

-- 1b. Record the settled 3D camera BEFORE the pan (mode 5 entered, damping done)
local ref_eye = nil
D.at(3, function()
    local c = lp.rl.get_camera()
    ref_eye = { c.eye_x, c.eye_y, c.eye_z }
end)

-- 2. Middle-drag 100px right inside the 2D canvas area (viewport, not sidebar)
D.drag(4, 400, 400, 500, 400, 8, 2)

-- 3. Assertions on frame 20: mode is 5 and the 2D pan moved with the drag
D.at(20, function()
    if doc.mode ~= 5 then
        print(string.format("[pan] FAIL: expected mode 5 (2D), got mode %d", doc.mode))
        os.exit(1)
    end
    local pan = CF.cam2d.pan
    print(string.format("[pan] 2D pan now (%.2f, %.2f) at zoom %.2f (started 256, 256)",
        pan[1], pan[2], CF.cam2d.zoom))
    -- Dragging the content right by ~100px moves the camera target left.
    if math.abs(pan[1] - 256) < 30 then
        print("[pan] FAIL: 2D pan did not move with the middle-drag")
        os.exit(1)
    end
    -- The 3D camera must stay untouched by 2D navigation
    local c = lp.rl.get_camera()
    if ref_eye and (math.abs(c.eye_x - ref_eye[1]) > 1e-3 or
                    math.abs(c.eye_y - ref_eye[2]) > 1e-3 or
                    math.abs(c.eye_z - ref_eye[3]) > 1e-3) then
        print("[pan] FAIL: 3D camera eye moved during 2D pan")
        os.exit(1)
    end
    print("[pan] OK: 2D middle-drag panned the canvas viewport")
    print("[pan] ALL 2D PAN ASSERTIONS PASSED")
end)
