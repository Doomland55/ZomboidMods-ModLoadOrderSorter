--- Merge sortable facts from ModsInfo, ModsFiles, then SortingRules.
--- Lists are unioned without duplicates; scalars are overridden in layer order.
--- requirements are exclusively from ModsInfo, never overridden by rules.
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local Data = {}
-- Merge arrays by value and maps recursively; never mutate layer snapshots.
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function merge(dst, source)
    local seen = {}
    for _, value in ipairs(dst) do
        if type(value) ~= "table" then seen[value] = true end
    end
    for _, value in ipairs(source) do
        -- Structured entries are retained; scalar lists are unioned efficiently.
        if type(value) == "table" or not seen[value] then
            dst[#dst + 1] = copy(value)
            if type(value) ~= "table" then seen[value] = true end
        end
    end
    for k, value in pairs(source) do
        if type(k) ~= "number" then
            if type(value) == "table" then
                if type(dst[k]) ~= "table" then dst[k] = {} end
                merge(dst[k], value)
            else
                dst[k] = value
            end
        end
    end
end

local categoryFields = { category=true, requirements=true, loadAfter=true, loadBefore=true }
local function mergeLayer(result, source, allowRequirements, categoryOnly)
    if type(source) ~= "table" then return end
    for key, value in pairs(source) do
        if (key ~= "requirements" or allowRequirements) and (not categoryOnly or categoryFields[key]) then
            if type(value) == "table" then
                if type(result[key]) ~= "table" then result[key] = {} end
                merge(result[key], value)
            else result[key] = value end
        end
    end
end

function Data.collect(modsList, activeRules, categoryOnly)
    local layers = core.layers or {}
    local info = layers.ModsInfo and layers.ModsInfo.data or {}
    local files = layers.ModsFiles and layers.ModsFiles.data or {}
    local rules = activeRules or (layers.SortingRules and layers.SortingRules.data) or {}
    local records, order, counts = {}, {}, {}
    for i, row in ipairs(modsList or {}) do
        local item = row and row.item
        local id = item and item.modId
        if type(id) == "string" and id:match("%S") then
            counts[id] = (counts[id] or 0) + 1
            if not records[id] then
                local result = { id = id, name = item.name or id, requirements = {},
                    loadAfter = {}, loadBefore = {}, incompatibleMods = {} }
                mergeLayer(result, info[id], true, categoryOnly)
                -- Preserve provenance for conflict resolution, even if a rule
                -- repeats an edge already specified in mod.info.
                result.infoLoadAfter = copy((info[id] or {}).loadAfter or {})
                result.infoLoadBefore = copy((info[id] or {}).loadBefore or {})
                mergeLayer(result, files[id], false, categoryOnly)
                mergeLayer(result, rules[id], false, categoryOnly)
                result.name = type(result.name) == "string" and result.name or id
                records[id], order[id] = result, i
            end
        end
    end
    return records, order, counts, files
end

return Data
