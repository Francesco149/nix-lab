-- editor/lua/undo.lua — Snapshot-based Undo / Redo manager with coalescing for CubeForge
local undo = {
    history = {},
    redo_stack = {},
    max_entries = 100,
    coalesce_active = false,
    coalesce_label = nil,
    coalesce_snapshot = nil,
}

function undo.can_undo()
    return #undo.history > 0
end

function undo.can_redo()
    return #undo.redo_stack > 0
end

function undo.push(label, snapshot)
    if not snapshot then return end
    undo.history[#undo.history + 1] = {
        label = label or "Action",
        state = snapshot,
    }
    if #undo.history > undo.max_entries then
        table.remove(undo.history, 1)
    end
    -- Clear redo stack on new action
    undo.redo_stack = {}
end

function undo.do_undo(current_state_fn)
    if #undo.history == 0 then return nil end
    local entry = table.remove(undo.history)
    if current_state_fn then
        local current = current_state_fn()
        undo.redo_stack[#undo.redo_stack + 1] = {
            label = entry.label,
            state = current,
        }
    end
    return entry.state, entry.label
end

function undo.do_redo(current_state_fn)
    if #undo.redo_stack == 0 then return nil end
    local entry = table.remove(undo.redo_stack)
    if current_state_fn then
        local current = current_state_fn()
        undo.history[#undo.history + 1] = {
            label = entry.label,
            state = current,
        }
    end
    return entry.state, entry.label
end

-- Coalescing: capture snapshot at start of gesture, push only once on completion
function undo.begin_coalesce(label, snapshot)
    if not undo.coalesce_active then
        undo.coalesce_active = true
        undo.coalesce_label = label or "Drag"
        undo.coalesce_snapshot = snapshot
    end
end

function undo.commit_coalesce()
    if undo.coalesce_active and undo.coalesce_snapshot then
        undo.push(undo.coalesce_label, undo.coalesce_snapshot)
    end
    undo.coalesce_active = false
    undo.coalesce_label = nil
    undo.coalesce_snapshot = nil
end

function undo.cancel_coalesce()
    undo.coalesce_active = false
    undo.coalesce_label = nil
    undo.coalesce_snapshot = nil
end

function undo.clear()
    undo.history = {}
    undo.redo_stack = {}
    undo.cancel_coalesce()
end

return undo
