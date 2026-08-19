local D = require("drive")
local doc = require("doc")
D.at(4, function()
    -- Build a known test image: paint the canvas solid RED, export it
    doc.canvas_init()
    lp.tex.clear(doc.canvas.tex_id, 0xFF0000FF)
    lp.tex.export_png(doc.canvas.tex_id, "build/import_test.png")
    -- Reject: nonexistent file
    local ok_bad = CF.import("build/does_not_exist.png")
    local px_after_bad = lp.tex.get_pixel(doc.canvas.tex_id, 10, 10)
    -- Import the exported PNG (round-trip)
    local ok_good = CF.import("build/import_test.png")
    local px = lp.tex.get_pixel(doc.canvas.tex_id, 10, 10)
    print(string.format("[import] reject=%s px_after_reject=%08X ok=%s px=%08X",
        tostring(ok_bad), px_after_bad, tostring(ok_good), px))
    if ok_bad then print("[import] FAIL: rejected file should return false"); os.exit(1) end
    if not ok_good then print("[import] FAIL: png import failed"); os.exit(1) end
    -- The imported image is 512x512 red → center pixel red
    local cr = (px >> 24) & 0xFF
    local cg = (px >> 16) & 0xFF
    local cb = (px >> 8) & 0xFF
    if cr < 200 or cg > 80 or cb > 80 then
        print(string.format("[import] FAIL: expected red, got %d,%d,%d", cr, cg, cb))
        os.exit(1)
    end
    print("[import] OK: reject + import round-trip")
end)
