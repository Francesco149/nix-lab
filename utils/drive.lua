-- utils/drive.lua — Standardized Headless UI Interaction & Tape Driver
-- Enables frame-accurate automated testing, input simulation, and visual verification.
--
-- Usage:
--   local D = require("drive")
--   D.click(10, 400, 300)                -- Click at (400, 300) on frame 10
--   D.drag(15, 100, 100, 300, 200, 5)   -- Drag from (100,100) to (300,200) over 5 frames
--   D.tap(25, D.Key.V)                   -- Press 'V' key on frame 25
--   D.chord(30, D.Key.Ctrl, D.Key.Z)     -- Press Ctrl+Z on frame 30
--   D.at(35, function()                  -- Custom assertion on frame 35
--       assert(doc.get_layer_count() == 2, "Expected 2 layers")
--   end)

local D = {
    plan = {},
    f = 0,
    log = {},
    Key = {
        Ctrl = 224,
        Shift = 225,
        Alt = 226,
        Space = 44,
        Enter = 40,
        Escape = 41,
        V = 25,
        H = 11,
        B = 5,
        E = 8,
        R = 21,
        C = 6,
        G = 10,
        S = 22,
        Z = 29,
        Y = 28,
        F = 9,
    }
}

function D.at(f, fn)
    local list = D.plan[f] or {}
    list[#list + 1] = fn
    D.plan[f] = list
end

function D.step(events)
    D.f = D.f + 1
    local fns = D.plan[D.f]
    if fns then
        for _, fn in ipairs(fns) do
            local ok, out = pcall(fn)
            if not ok then
                print(string.format("[drive] ERROR on frame %d: %s", D.f, tostring(out)))
            elseif type(out) == "table" and events then
                for _, ev in ipairs(out) do
                    events[#events + 1] = ev
                end
            end
        end
    end
end

-- Synthetic event builders
function D.mouse_move(x, y)
    return { type = "motion", x = x, y = y, ui_x = x, ui_y = y }
end

function D.mouse_button(x, y, down, btn)
    return { type = "button", x = x, y = y, down = down, button = btn or 1 }
end

function D.key_event(scancode, down)
    return { type = "key", scancode = scancode, down = down }
end

-- Composite actions scheduled across frames
function D.click(f, x, y, btn)
    D.at(f,     function() return { D.mouse_move(x, y) } end)
    D.at(f + 1, function() return { D.mouse_button(x, y, true, btn) } end)
    D.at(f + 2, function() return { D.mouse_button(x, y, false, btn) } end)
end

function D.rclick(f, x, y)
    D.click(f, x, y, 3)
end

function D.drag(f, x0, y0, x1, y1, steps, btn)
    steps = steps or 4
    D.at(f,     function() return { D.mouse_move(x0, y0) } end)
    D.at(f + 1, function() return { D.mouse_button(x0, y0, true, btn) } end)
    for s = 1, steps do
        local t = s / steps
        local cur_x = x0 + (x1 - x0) * t
        local cur_y = y0 + (y1 - y0) * t
        D.at(f + 1 + s, function() return { D.mouse_move(cur_x, cur_y) } end)
    end
    D.at(f + 2 + steps, function() return { D.mouse_button(x1, y1, false, btn) } end)
end

function D.tap(f, scancode)
    D.at(f,     function() return { D.key_event(scancode, true) } end)
    D.at(f + 1, function() return { D.key_event(scancode, false) } end)
end

function D.chord(f, mod_scancode, scancode)
    D.at(f,     function() return { D.key_event(mod_scancode, true) } end)
    D.at(f + 1, function() return { D.key_event(scancode, true) } end)
    D.at(f + 2, function() return { D.key_event(scancode, false) } end)
    D.at(f + 3, function() return { D.key_event(mod_scancode, false) } end)
end

return D
