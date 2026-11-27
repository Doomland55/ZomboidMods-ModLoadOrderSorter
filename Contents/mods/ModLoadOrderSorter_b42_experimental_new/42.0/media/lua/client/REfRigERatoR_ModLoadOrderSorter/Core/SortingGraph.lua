--- Directed sorting graph. Edge A -> B means A must load before B.
--- Builds explicit and heuristic edges and propagates effective categories.
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local Graph = {}
Graph.REQUIRE, Graph.LOAD, Graph.RULE, Graph.HOOK, Graph.SHADOW, Graph.SOFT = 100, 95, 90, 50, 10, 5

local function addEdge(edges, from, to, weight)
    if not from or not to then return end
    local list = edges[from]
    if not list then list = {}; edges[from] = list end
    for _, edge in ipairs(list) do
        if edge.to == to then
            if edge.weight < weight then edge.weight = weight end
            return
        end
    end
    list[#list + 1] = { to = to, weight = weight }
end

local function hasEdge(edges, from, to, minimum)
    for _, edge in ipairs(edges[from] or {}) do
        if edge.to == to and edge.weight >= (minimum or 0) then return true end
    end
    return false
end

local function addHint(edges, from, to, weight)
    if not hasEdge(edges, to, from) then addEdge(edges, from, to, weight) end
end

local function addExplicit(edges, records)
    for id, info in pairs(records) do
        for _, dep in ipairs(info.requirements) do
            if records[dep] then addEdge(edges, dep, id, Graph.REQUIRE) end
        end
        for _, dep in ipairs(info.infoLoadAfter) do
            if records[dep] then addEdge(edges, dep, id, Graph.LOAD) end
        end
        for _, dep in ipairs(info.infoLoadBefore) do
            if records[dep] then addEdge(edges, id, dep, Graph.LOAD) end
        end
        for _, dep in ipairs(info.loadAfter) do
            if records[dep] then addEdge(edges, dep, id, Graph.RULE) end
        end
        for _, dep in ipairs(info.loadBefore) do
            if records[dep] then addEdge(edges, id, dep, Graph.RULE) end
        end
    end
end

local function categoryIndices(records, edges)
    local categories, reverse, queue, queued = {}, {}, {}, {}
    for id, info in pairs(records) do
        categories[id] = core.categoryOrder[info.category] or core.categoryOrder.undefined or #core.rawCategoryOrder
        queue[#queue + 1] = id
        queued[id] = true
    end
    for from, list in pairs(edges) do
        for _, edge in ipairs(list) do
            if edge.weight >= Graph.RULE then
                local parents = reverse[edge.to]
                if not parents then parents = {}; reverse[edge.to] = parents end
                parents[#parents + 1] = from
            end
        end
    end
    -- Worklist propagates every promotion along explicit dependency chains.
    local head = 1
    while head <= #queue do
        local id = queue[head]
        head = head + 1
        queued[id] = nil
        for _, parent in ipairs(reverse[id] or {}) do
            if categories[parent] > categories[id] then
                categories[parent] = categories[id]
                if not queued[parent] then
                    queued[parent] = true
                    queue[#queue + 1] = parent
                end
            end
        end
    end
    return categories
end

local function addFileHints(edges, records, files, order)
    local owners = {}
    for id in pairs(records) do
        for _, filename in ipairs((files[id] or {}).files or {}) do
            local list = owners[filename]
            if not list then list = {}; owners[filename] = list end
            list[id] = true
        end
    end
    for _, byId in pairs(owners) do
        local ids = {}
        for id in pairs(byId) do ids[#ids + 1] = id end
        table.sort(ids, function(a, b) return order[a] < order[b] end)
        for i = 2, #ids do addHint(edges, ids[i - 1], ids[i], Graph.SHADOW) end
    end
end

local function indexTargets(records, files)
    local targets = {}
    for id in pairs(records) do
        local data = files[id]
        if data and data.complete ~= nil then
            for _, modification in ipairs(data.modifications or {}) do
                if modification.className and modification.methodName then
                    local key = modification.className .. "." .. modification.methodName
                    local owners = targets[key]
                    if not owners then owners = {}; targets[key] = owners end
                    if owners[id] == nil or modification.isHook ~= true then
                        owners[id] = modification.isHook == true
                    end
                end
            end
        end
    end
    return targets
end

local function addTargetWarnings(edges, target, overwrites, warnings)
    local conflicts = {}
    for i = 1, #overwrites do
        for j = i + 1, #overwrites do
            local a, b = overwrites[i], overwrites[j]
            if not hasEdge(edges, a, b, Graph.RULE) and not hasEdge(edges, b, a, Graph.RULE) then
                conflicts[#conflicts + 1] = a .. " <-> " .. b
            end
        end
    end
    if #conflicts > 0 then
        warnings[#warnings + 1] = { severity = "CRITICAL", layer = "ModsFiles",
            title = getText("UI_MLOS_Conflict_Overwrite_Title"),
            message = getText("UI_MLOS_Conflict_Overwrite_Msg", table.concat(conflicts, "; "), target) }
    end
end

local function addTargetHints(edges, records, files, order, warnings)
    local targets = indexTargets(records, files)
    local names = {}
    for target in pairs(targets) do names[#names + 1] = target end
    table.sort(names)
    for _, target in ipairs(names) do
        local owners = targets[target]
        local overwrites, hooks = {}, {}
        for id, isHook in pairs(owners) do
            local group = isHook and hooks or overwrites
            group[#group + 1] = id
        end
        local function byOrder(a, b) return order[a] < order[b] end
        table.sort(overwrites, byOrder)
        table.sort(hooks, byOrder)
        addTargetWarnings(edges, target, overwrites, warnings)
        for _, overwrite in ipairs(overwrites) do
            for _, hook in ipairs(hooks) do addEdge(edges, overwrite, hook, Graph.HOOK) end
        end
        for _, group in ipairs({ overwrites, hooks }) do
            for i = 2, #group do addHint(edges, group[i - 1], group[i], Graph.SOFT) end
        end
    end
end

function Graph.build(records, files, order, warnings)
    local edges = {}
    addExplicit(edges, records)
    local categories = categoryIndices(records, edges)
    addFileHints(edges, records, files, order)
    addTargetHints(edges, records, files, order, warnings)
    -- Preserve the fixed category order: weaker file heuristics cannot promote
    -- categories or force a mod from a later category ahead of an earlier one.
    for from, list in pairs(edges) do
        for i = #list, 1, -1 do
            local edge = list[i]
            if edge.weight < Graph.RULE and categories[from] > categories[edge.to] then
                table.remove(list, i)
            end
        end
    end
    return edges, categories
end

return Graph
