local Enemy = Enemy
local tsort = table.sort
local pcall = pcall
local error = error

local sortContexts = {}
local sortDepth = 0


local function NewSortContext ()
    local context = {}
    context.compare = function (a, b)
        return context.callback (a, b, context.first, context.second, context.third)
    end
    return context
end


-- table.sort has no context arguments. Reuse one adapter per active sort depth,
-- so a comparator may start another sort without replacing its caller's data.
function Enemy.SortWithContext (items, callback, first, second, third)
    local depth = sortDepth + 1
    local context = sortContexts[depth]
    if (not context)
    then
        context = NewSortContext ()
        sortContexts[depth] = context
    end

    sortDepth = depth
    context.callback = callback
    context.first, context.second, context.third = first, second, third
    local ok, err = pcall (tsort, items, context.compare)
    context.callback = nil
    context.first, context.second, context.third = nil, nil, nil
    sortDepth = depth - 1

    -- Release references and restore depth even if a custom comparator fails.
    if (not ok) then error (err, 0) end
end
