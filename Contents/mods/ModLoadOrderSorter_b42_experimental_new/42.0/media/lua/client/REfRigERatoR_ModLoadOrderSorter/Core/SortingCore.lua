--- Deterministic Kahn topological sorter for the load-order UI.
--- Public API: buildGraph, sort, validate, getIncompatibleWarnings, applyOrder.
--- Uses merged layer data, explicit category promotion and a binary min-heap.
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local Heap = require('REfRigERatoR_ModLoadOrderSorter/Core/BinaryHeap')
local Data = require('REfRigERatoR_ModLoadOrderSorter/Core/SortingData')
local Graph = require('REfRigERatoR_ModLoadOrderSorter/Core/SortingGraph')
local Sorter = { warnings = {} }
local BACKUP_FILE = "loadOrderBackup.txt"

local function positionRank(record, category)
    if record.loadFirst == "on" then return 0, 0, 0 end
    if record.loadLast == "on" then return 2, 0, 0 end
    local first = record.loadFirst == "category" or record.loadFirst == "inCategory"
    local last = record.loadLast == "category" or record.loadLast == "inCategory"
    return 1, category, first and -1 or (last and 1 or 0)
end

local function priorityLess(records, categories)
    return function(a, b)
        local ag, ac, ap = positionRank(records[a], categories[a])
        local bg, bc, bp = positionRank(records[b], categories[b])
        if ag ~= bg then return ag < bg end
        if ac ~= bc then return ac < bc end
        if ap ~= bp then return ap < bp end
        local an, bn = records[a].name:lower(), records[b].name:lower()
        if an ~= bn then return an < bn end
        return a < b
    end
end

local function prepare(self, modsList, activeRules)
    local records, order, counts, files = Data.collect(modsList, activeRules)
    self.warnings = {}
    local edges, categories = Graph.build(records, files, order, self.warnings)
    local modInfo = core.layers and core.layers.ModsInfo and core.layers.ModsInfo.data or {}
    for id, category in pairs(categories) do
        if modInfo[id] then modInfo[id].effectiveCategory = core.rawCategoryOrder[category] end
    end
    return records, order, counts, edges, categories
end

-- Read-only category projection for the editor. File conflict hints do not
-- promote categories, so avoid scanning/copying file inventories here.
function Sorter:calculateCategories(modsList, activeRules)
    local records = Data.collect(modsList, activeRules, true)
    local categories = Graph.effectiveCategories(records)
    local effective, base = {}, {}
    for id, index in pairs(categories) do
        effective[id] = core.rawCategoryOrder[index] or "undefined"
        local category = records[id].category
        base[id] = core.categoryOrder[category] and category or "undefined"
    end
    return effective, base
end

function Sorter:buildGraph(modsList, activeRules)
    local records, order, _, edges, categories = prepare(self, modsList, activeRules)
    local enabled = {}
    for id in pairs(records) do enabled[id] = true end
    return edges, enabled, order, categories
end

-- Iterative Kosaraju: identify cycle edges in linear time per removal,
-- without overflowing the Lua stack on long dependency chains.
local function weakestCycleEdge(edges, placed, records)
    local reverse, visited, finish = {}, {}, {}
    for from, list in pairs(edges) do
        if not placed[from] then
            for _, edge in ipairs(list) do
                if not placed[edge.to] then
                    local incoming = reverse[edge.to] or {}
                    reverse[edge.to] = incoming
                    incoming[#incoming + 1] = from
                end
            end
        end
    end
    for start in pairs(records) do
        if not placed[start] and not visited[start] then
            visited[start] = true
            local stack = { { id = start, next = 1 } }
            while #stack > 0 do
                local frame = stack[#stack]
                local edge = (edges[frame.id] or {})[frame.next]
                if edge then
                    frame.next = frame.next + 1
                    if not placed[edge.to] and not visited[edge.to] then
                        visited[edge.to] = true
                        stack[#stack + 1] = { id = edge.to, next = 1 }
                    end
                else
                    finish[#finish + 1] = frame.id
                    stack[#stack] = nil
                end
            end
        end
    end
    local component, sizes, number = {}, {}, 0
    for i = #finish, 1, -1 do
        local start = finish[i]
        if not component[start] then
            number = number + 1
            local stack = { start }
            component[start] = number
            sizes[number] = 0
            while #stack > 0 do
                local id = table.remove(stack)
                sizes[number] = sizes[number] + 1
                for _, other in ipairs(reverse[id] or {}) do
                    if not component[other] then
                        component[other] = number
                        stack[#stack + 1] = other
                    end
                end
            end
        end
    end
    local best
    for from, list in pairs(edges) do
        if not placed[from] then
            for i, edge in ipairs(list) do
                if not placed[edge.to] and component[from] == component[edge.to]
                    and (from == edge.to or sizes[component[from]] > 1) then
                    if not best or edge.weight < best.weight or
                        (edge.weight == best.weight and (from .. "\0" .. edge.to) < (best.from .. "\0" .. best.to)) then
                        best = { from = from, to = edge.to, weight = edge.weight, list = list, index = i }
                    end
                end
            end
        end
    end
    return best
end

local function cycleWarning(broken)
    if #broken == 0 then return nil end
    local ids, seen, details, hard = {}, {}, {}, false
    for _, edge in ipairs(broken) do
        for _, id in ipairs({ edge.from, edge.to }) do
            if not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        end
        if edge.weight >= Graph.RULE then hard = true end
        details[#details + 1] = edge.from .. " -> " .. edge.to .. " (" .. edge.weight .. ")"
    end
    table.sort(ids)
    return { severity = hard and "CRITICAL" or "WARNING", layer = "SortingRules",
        title = getText("UI_MLOS_Cycle_Title"),
        message = (hard and getText("UI_MLOS_Cycle_Msg", table.concat(ids, ", "))
            or getText("UI_MLOS_OrderHintBroken_Msg", table.concat(ids, ", ")))
            .. " | " .. table.concat(details, "; ") }
end

local function addIncompatibleWarnings(warnings, records, modsList)
    local seen = {}
    for _, row in ipairs(modsList or {}) do
        local id = row and row.item and row.item.modId
        local record = records[id]
        if record then
            for _, other in ipairs(record.incompatibleMods) do
                if records[other] and id ~= other then
                    local first, second = id < other and id or other, id < other and other or id
                    local key = first .. "\0" .. second
                    if not seen[key] then
                        seen[key] = true
                        warnings[#warnings + 1] = { severity = "CRITICAL", layer = "ModsInfo",
                            title = getText("UI_MLOS_Incompatible_Title"),
                            message = getText("UI_MLOS_Incompatible_Msg", records[first].name, records[second].name) }
                    end
                end
            end
        end
    end
end

function Sorter:getIncompatibleWarnings(modsList, activeRules)
    local records = Data.collect(modsList, activeRules)
    local warnings = {}
    addIncompatibleWarnings(warnings, records, modsList)
    return warnings
end

function Sorter:sort(modsList, activeRules)
    local records, _, counts, edges, categories = prepare(self, modsList, activeRules)
    self.lastEdges, self.brokenEdges = edges, {}
    local indegree, total = {}, 0
    for id in pairs(records) do indegree[id] = 0; total = total + 1 end
    for _, list in pairs(edges) do
        for _, edge in ipairs(list) do indegree[edge.to] = indegree[edge.to] + 1 end
    end
    local ready = Heap.new(priorityLess(records, categories))
    for id, degree in pairs(indegree) do if degree == 0 then ready:push(id) end end
    local placed, sorted, placedCount = {}, {}, 0
    while placedCount < total do
        if ready:isEmpty() then
            local edge = weakestCycleEdge(edges, placed, records)
            if not edge then
                -- Defensive fallback: return every remaining node even if an
                -- unexpected invalid graph prevented normal cycle resolution.
                for id in pairs(records) do if not placed[id] then ready:push(id) end end
                self.warnings[#self.warnings + 1] = { severity = "CRITICAL", layer = "SortingRules",
                    title = getText("UI_MLOS_Cycle_Title"), message = "[MLOS] Invalid dependency graph; remaining mods retained." }
            else
                table.remove(edge.list, edge.index)
                indegree[edge.to] = indegree[edge.to] - 1
                self.brokenEdges[#self.brokenEdges + 1] = { from = edge.from, to = edge.to, weight = edge.weight }
                if indegree[edge.to] == 0 then ready:push(edge.to) end
            end
        end
        if not ready:isEmpty() then
            local id = ready:pop()
            if not placed[id] then
                placed[id] = true
                placedCount = placedCount + 1
                for _ = 1, counts[id] do sorted[#sorted + 1] = id end
                for _, edge in ipairs(edges[id] or {}) do
                    indegree[edge.to] = indegree[edge.to] - 1
                    if indegree[edge.to] == 0 and not placed[edge.to] then ready:push(edge.to) end
                end
            end
        end
    end
    local warning = cycleWarning(self.brokenEdges)
    if warning then self.warnings[#self.warnings + 1] = warning end
    addIncompatibleWarnings(self.warnings, records, modsList)
    return sorted
end

local function mark(status, id, color)
    local severity = { yellow = 1, red = 2, purple = 3 }
    if not status[id] or severity[color] > severity[status[id]] then status[id] = color end
end

function Sorter:validate(modsList, activeRules)
    local records, index, _, edges, cats = prepare(self, modsList, activeRules)
    local status = {}
    for id, record in pairs(records) do
        for _, dep in ipairs(record.requirements) do
            if not records[dep] or index[dep] > index[id] then mark(status, id, "red") end
        end
        for _, other in ipairs(record.incompatibleMods) do
            if records[other] then mark(status, id, "purple"); mark(status, other, "purple") end
        end
        for _, other in ipairs(record.loadAfter) do
            if records[other] and index[other] > index[id] then mark(status, id, "yellow") end
        end
        for _, other in ipairs(record.loadBefore) do
            if records[other] and index[other] < index[id] then mark(status, id, "yellow") end
        end
    end
    for i = 1, #modsList do
        local a = modsList[i].item.modId
        if records[a] then
            local ag, ac, ap = positionRank(records[a], cats[a])
            for j = i + 1, #modsList do
                local b = modsList[j].item.modId
                if records[b] then
                    local bg, bc, bp = positionRank(records[b], cats[b])
                    if ag > bg or (ag == bg and (ac > bc or (ac == bc and ap > bp))) then
                        mark(status, a, "yellow"); mark(status, b, "yellow")
                    end
                end
            end
        end
    end
    return status
end

function Sorter:applyOrder(scrollObject, sortedIds)
    if not scrollObject or not scrollObject.items then return end
    local current, buckets = {}, {}
    for _, row in ipairs(scrollObject.items) do
        local id = row.item and row.item.modId
        current[#current + 1] = tostring(id or "")
        if id then
            local bucket = buckets[id] or { rows = {}, next = 1 }
            buckets[id] = bucket
            bucket.rows[#bucket.rows + 1] = row
        end
    end
    local ok, err = pcall(function()
        local file = getFileWriter(utils:joinpath(core.MLOS_ROOT, BACKUP_FILE), true, false)
        if not file then error("cannot open backup file") end
        file:write(table.concat(current, ";")); file:close()
    end)
    if not ok then print("[MLOS] Failed to save load order backup: " .. tostring(err)) end
    local newItems, used = {}, {}
    for _, id in ipairs(sortedIds or {}) do
        local bucket = buckets[id]
        if bucket and bucket.rows[bucket.next] then
            local row = bucket.rows[bucket.next]
            bucket.next = bucket.next + 1
            newItems[#newItems + 1] = row; used[row] = true
        end
    end
    for _, row in ipairs(scrollObject.items) do
        if not used[row] then newItems[#newItems + 1] = row end
    end
    scrollObject.items = newItems
    for i, row in ipairs(newItems) do row.itemindex = i end
    scrollObject.selected = #newItems > 0 and 1 or 0
end

return Sorter
