-- editor/lua/drive.lua — Headless input tape driver for raylib templates.
-- Schedules frame-accurate input injections via the C++ lp.drive.* override.
-- No window focus, no xdotool, no synthetic OS events — the app's lp.rl.*
-- input getters return injected state instead of real input.
--
-- Usage (from a --drive script):
--   local D = require("drive")
--   D.click(10, 400, 300)                -- click at (400,300) on frame 10
--   D.drag(15, 100, 100, 300, 200, 5)   -- drag over 5 frames
--   D.tap(25, D.Key.G)                   -- press G on frame 25
--   D.chord(30, D.Key.LeftCtrl, D.Key.Z) -- Ctrl+Z on frame 30
--   D.wheel(40, 3)                       -- scroll up 3 notches on frame 40
--   D.at(45, function() ... end)         -- custom assertion on frame 45
--
-- The C++ main loop calls drive_begin() once (enables the override) and
-- drive_step() every frame (executes this frame's plan + frame boundary).

local D = {
    plan = {},
    f = 0,
    Key = {
        G = 71, E = 69, S = 83, F = 70, B = 66,
        Z = 90, Y = 89, U = 85, Delete = 259, Escape = 256,
        Space = 32, Enter = 257, Tab = 258,
        One = 49, Two = 50, Three = 51, Four = 52, Five = 53,
        LeftCtrl = 341, LeftShift = 340, LeftAlt = 342,
    },
}

function D.at(f, fn)
    local list = D.plan[f] or {}
    list[#list + 1] = fn
    D.plan[f] = list
end

-- Executed by the C++ loop every frame, BEFORE the frame renders.
-- Only plan execution here; the per-frame boundary (prev-pos advance, wheel
-- and pressed-key clears) runs AFTER render via drive_frame() so the render
-- sees this frame's injected state with last frame's baseline for deltas.
function drive_step()
    D.f = D.f + 1
    local fns = D.plan[D.f]
    if fns then
        for _, fn in ipairs(fns) do
            local ok, err = pcall(fn)
            if not ok then
                print(string.format("[drive] ERROR on frame %d: %s", D.f, tostring(err)))
            end
        end
    end
end

-- Executed by the C++ loop AFTER EndDrawing each frame.
function drive_frame()
    lp.drive.frame()
end

-- Executed once by the C++ loop before the first frame.
function drive_begin()
    lp.drive.active(true)
end

-- Raw injections (frame-timed composites below)
function D.mouse(x, y)      lp.drive.mouse(x, y) end
function D.button(btn, d)   lp.drive.button(btn, d) end
function D.wheel(dy)        lp.drive.wheel(dy) end
function D.key(code, d)     lp.drive.key(code, d) end

-- Composite actions
function D.click(f, x, y, btn)
    btn = btn or 0
    D.at(f,     function() D.mouse(x, y) end)
    D.at(f + 1, function() D.button(btn, true) end)
    D.at(f + 2, function() D.button(btn, false) end)
end

function D.rclick(f, x, y)
    D.click(f, x, y, 1)
end

function D.drag(f, x0, y0, x1, y1, steps, btn)
    steps = steps or 4
    btn = btn or 0
    D.at(f,     function() D.mouse(x0, y0) end)
    D.at(f + 1, function() D.button(btn, true) end)
    for i = 1, steps do
        local t = i / (steps + 1)
        local x = x0 + (x1 - x0) * t
        local y = y0 + (y1 - y0) * t
        D.at(f + 1 + i, function() D.mouse(x, y) end)
    end
    D.at(f + 2 + steps, function() D.button(btn, false) end)
end

function D.tap(f, code)
    D.at(f,     function() D.key(code, true) end)
    D.at(f + 1, function() D.key(code, false) end)
end

function D.chord(f, mod_code, code)
    D.at(f,     function() D.key(mod_code, true) end)
    D.at(f + 1, function() D.key(code, true) end)
    D.at(f + 2, function() D.key(code, false) end)
    D.at(f + 3, function() D.key(mod_code, false) end)
end

return D
