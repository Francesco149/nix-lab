-- editor/tests/drive_paint3d.lua — headless 2D→3D texture-paint demo tape.
-- Enters texture-paint mode (5), paints a stroke on the 512x512 canvas, exits
-- back to 3D and asserts the canvas pixels changed and the canvas texture is
-- bound to the cube's GPU model. The capture (shot_paint3d.png) must show the
-- painted marks on the cube — the 2D↔3D bridge in one codebase.
--
-- Run: build/cubeforge-raylib --shot build/shot_paint3d.png --frames 24 \
--        --drive editor/tests/drive_paint3d.lua
local D = require("drive")
local doc = require("doc")

-- 1. Enter 2D texture-paint mode (tap 5) — applies the canvas to the cube
D.tap(2, D.Key.Five)

-- 2. Paint a horizontal stroke across the canvas center with the left button.
--    Viewport: pan (256,256), zoom 1, offset (640,400) → world = screen-384.
--    Screen x 500..700 maps to world x 116..316 at world y 256.
D.drag(4, 500, 400, 700, 400, 10, 0)

-- 3. Exit back to 3D face mode (tap 3)
D.tap(18, D.Key.Three)

-- 4. Assertions on frame 24 (before the screenshot is taken)
D.at(24, function()
    local m = doc.meshes[1]
    if doc.mode ~= 3 then
        print(string.format("[paint3d] FAIL: expected mode 3 after exiting 2D, got %d", doc.mode))
        os.exit(1)
    end
    if not (doc.canvas.tex_id and m and m.model_id) then
        print("[paint3d] FAIL: canvas tex id or cube model missing")
        os.exit(1)
    end
    if doc.canvas.applied_mesh_idx ~= 1 then
        print("[paint3d] FAIL: canvas texture not applied to the cube model")
        os.exit(1)
    end
    -- The stroke crossed world x 116..316 at y 256; sample a painted pixel
    local px = lp.tex.get_pixel(doc.canvas.tex_id, 200, 256)
    print(string.format("[paint3d] canvas pixel (200,256) = 0x%08X", px))
    if px == 0xFFFFFFFF then
        print("[paint3d] FAIL: stroke did not paint the canvas")
        os.exit(1)
    end
    print("[paint3d] OK: stroke painted the canvas and is bound to the cube")
    print("[paint3d] ALL 2D→3D ASSERTIONS PASSED")
end)
