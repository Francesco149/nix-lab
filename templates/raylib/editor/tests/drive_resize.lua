-- editor/tests/drive_resize.lua — panel-resize via the in-window splitter.
-- Drags the 6px handle (left edge of the sidebar window) left by 50px and
-- asserts the sidebar width grew — proves the splitter latches (cursor may
-- leave the thin handle during the drag) and adjusts live.
local D = require("drive")
D.at(4, function()
    local sw, sh = lp.rl.get_screen_size()
    local w0 = CF.sidebar()
    local hx = sw - 280 + 11   -- window left edge + padding + mid-handle
    D.drag(6, hx, 300, hx - 50, 300, 4, 0)
    D.at(14, function()
        local w1 = CF.sidebar()
        print(string.format("[resize] w0=%d w1=%.0f %s", w0, w1, w1 > w0 and "RESIZE_OK" or "FAIL"))
        if w1 <= w0 then os.exit(1) end
    end)
end)
