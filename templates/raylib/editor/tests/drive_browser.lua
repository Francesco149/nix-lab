-- drive_browser.lua — headless test: file-picker button renders (no-op in
-- headless since the native dialog can't open without user interaction).
local D = require("drive")
-- Verify the import pipeline is callable (no crash).
D.at(5, function()
    CF.import("")  -- graceful rejection of empty path
end)
