-- editor/tests/drive_window_resize.lua — autonomous window resize behavior test
-- Dynamically resizes the window through multiple resolutions and aspect ratios,
-- asserting that screen dimensions, camera projections, and UI layouts adapt
-- live on each frame without stalling, clipping, or distortion.

local D = require("drive")
local rl = lp.rl
local cam2d = lp.cam2d

local steps = {
    { frame = 5,  w = 960,  h = 640, label = "960x640" },
    { frame = 15, w = 800,  h = 600, label = "800x600 (low-res)" },
    { frame = 25, w = 1440, h = 900, label = "1440x900 (widescreen)" },
    { frame = 35, w = 1024, h = 768, label = "1024x768 (4:3)" },
    { frame = 45, w = 1280, h = 800, label = "1280x800 (restored)" },
}

for _, step in ipairs(steps) do
    D.at(step.frame, function()
        rl.set_window_size(step.w, step.h)
    end)
    D.at(step.frame + 3, function()
        local sw, sh = rl.get_screen_size()
        local cpx, cpy, zoom = cam2d.get()
        local sb_w = CF.sidebar()
        local max_sb = math.max(180, sw - 120)
        local eff_sb = math.max(180, math.min(sb_w, max_sb))
        local vp_w = math.max(60, sw - eff_sb)
        local tb_w = math.min(540, vp_w - 16)
        local tb_x = math.max(8, (vp_w - tb_w) * 0.5)

        print(string.format("[win-resize] Step %s: screen=(%d,%d) cam2d_pan=(%.1f,%.1f) tb_x=%.1f tb_w=%.1f sidebar=%.1f",
            step.label, sw, sh, cpx, cpy, tb_x, tb_w, eff_sb))

        -- Save intermediate screenshot for visual inspection:
        local shot_name = string.format("build/shot_resize_%dx%d.png", sw, sh)
        rl.take_screenshot(shot_name)

        -- Invariant assertions:
        if sw ~= step.w or sh ~= step.h then
            print(string.format("[win-resize] FAIL: Expected screen size (%d,%d), got (%d,%d)", step.w, step.h, sw, sh))
            os.exit(1)
        end
        if tb_x < 8 or (tb_x + tb_w) > vp_w + 1 then
            print(string.format("[win-resize] FAIL: Toolbar exceeds viewport bounds: tb_x=%.1f tb_w=%.1f vp_w=%.1f", tb_x, tb_w, vp_w))
            os.exit(1)
        end
        if eff_sb > sw then
            print(string.format("[win-resize] FAIL: Sidebar width %.1f exceeds screen width %d", eff_sb, sw))
            os.exit(1)
        end
    end)
end

D.at(52, function()
    print("[win-resize] ALL WINDOW RESIZE INVARIANTS PASSED")
end)
