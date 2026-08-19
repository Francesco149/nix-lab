-- filebrowser.lua — in-app file browser (the reliable file picker).
-- Native dialogs (tinyfiledialogs) need zenity/kdialog on Linux — absent
-- under WSLg — and can silently fail; this modal is the template's guaranteed
-- path. Share it with any tool that needs "open a file".
local ig = lp.ig
local rl = lp.rl

local fb = {
    open_flag = false,
    dir = ".",
    on_pick = nil,
    sel = nil,
}

local IMAGE_EXTS = {
    png = true, jpg = true, jpeg = true, bmp = true,
    tga = true, gif = true, qoi = true, ico = true,
}

local function ext_of(name)
    local i = name:match("^.*%.([^%.]+)$")
    return i and i:lower() or ""
end

local function join(dir, name)
    if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then return dir .. name end
    return dir .. "/" .. name
end

function fb.open(start_dir, on_pick)
    fb.dir = start_dir or fb.dir or "."
    fb.on_pick = on_pick
    fb.sel = nil
    fb.open_flag = true
end

function fb.close()
    fb.open_flag = false
end

function fb.frame()
    if not fb.open_flag then return end
    local sw, sh = rl.get_screen_size()
    local w = math.min(500, math.max(260, sw - 32))
    local h = math.min(420, math.max(200, sh - 32))
    ig.set_next_window_pos(math.max(8, (sw - w) * 0.5), math.max(8, (sh - h) * 0.5))
    ig.set_next_window_size(w, h)
    ig.window("##filebrowser", 1 + 2, function()
        ig.text_colored("Open Texture — " .. fb.dir, 0.96, 0.65, 0.12, 1.0)
        ig.separator()

        ig.child("##fb_list", 0, h - 130, 1, function()
            -- Navigate up
            if fb.dir and fb.dir ~= "." then
                if ig.selectable("  [..]  (up)") then
                    local d = fb.dir:match("^(.*)[/\\][^/\\]*[/\\]?$") or "."
                    fb.dir = (d == "" and "/" or d)
                    fb.sel = nil
                end
            end
            local ok, dirs, files = pcall(rl.list_dir or lp.file.list_dir, fb.dir)
            if not ok then
                ig.text_colored("Cannot read directory", 0.8, 0.3, 0.3, 1.0)
                return
            end
            for _, d in ipairs(dirs or {}) do
                if ig.selectable("  [D]  " .. d) then
                    fb.dir = join(fb.dir, d)
                    fb.sel = nil
                end
            end
            for _, f in ipairs(files or {}) do
                local is_img = IMAGE_EXTS[ext_of(f)]
                if is_img then
                    if ig.selectable("  " .. f, fb.sel == f) then fb.sel = f end
                else
                    ig.begin_disabled(true)
                    ig.selectable("  [x] " .. f, false)
                    ig.end_disabled()
                end
            end
        end)

        ig.separator()
        if fb.sel then
            ig.text_colored("Selected: " .. fb.sel, 0.7, 0.75, 0.8, 1.0)
        end
        if ig.button("Open", 90, 28) and fb.sel then
            local full = join(fb.dir, fb.sel)
            local cb = fb.on_pick
            fb.close()
            if cb then cb(full) end
        end
        ig.same_line()
        if ig.button("Cancel", 90, 28) then
            fb.close()
        end
    end)
end

return fb
