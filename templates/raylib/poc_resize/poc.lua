-- poc.lua — Lua script for poc_lua.exe. Runs per-frame; exercises coroutines,
-- string ops, and table churn to surface any threading/re-entrancy snags when
-- frames are also driven from the Win32 subclass during modal resize.

local M = {}

M.frames = 0
M.resizes_seen = 0
M.last_w, M.last_h = 0, 0
M.spin_co = nil

local function spin_coroutine()
  local sum = 0
  while true do
    for i = 1, 100 do sum = (sum + i * 7) % 1000003 end
    coroutine.yield(sum)
  end
end

function M.frame(w, h, in_sizemove)
  M.frames = M.frames + 1
  if w ~= M.last_w or h ~= M.last_h then
    M.resizes_seen = M.resizes_seen + 1
    M.last_w, M.last_h = w, h
  end
  if not M.spin_co then M.spin_co = coroutine.create(spin_coroutine) end
  local ok, val = coroutine.resume(M.spin_co)
  M.spin_val = ok and val or -1
  M.in_sizemove = in_sizemove
  return M.frames
end

return M
