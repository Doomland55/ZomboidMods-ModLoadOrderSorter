--- Transactional rule editor model. No UI or writes until commit.
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local Model = {}
Model.__index = Model
local fields = { 'loadAfter', 'loadBefore', 'incompatibleMods' }

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function Model.new(data)
    return setmetatable({ original = utils:deepCopy(data or {}), draft = utils:deepCopy(data or {}) }, Model)
end

function Model:dirty(id)
    if id then return not same(self.original[id] or {}, self.draft[id] or {}) end
    return not same(self.original, self.draft)
end

function Model:set(id, key, value)
    local rule = self.draft[id] or {}
    self.draft[id] = rule
    rule[key] = value
    self:clean(id)
end

function Model:clean(id)
    local rule = self.draft[id]
    if not rule then return end
    for _, field in ipairs(fields) do
        if type(rule[field]) == 'table' and #rule[field] == 0 then rule[field] = nil end
    end
    if utils:tableIsEmpty(rule) then self.draft[id] = nil end
end

function Model:add(id, key, target)
    if not id or not target or id == target then return false end
    local rule = self.draft[id] or {}
    self.draft[id] = rule
    local list = rule[key] or {}
    rule[key] = list
    for _, value in ipairs(list) do if value == target then return false end end
    list[#list + 1] = target
    return true
end

function Model:remove(id, key, target)
    local list = self.draft[id] and self.draft[id][key]
    if type(list) ~= 'table' then return false end
    local removed = false
    for i = #list, 1, -1 do
        if list[i] == target then table.remove(list, i); removed = true end
    end
    self:clean(id)
    return removed
end

-- Each displayed relationship keeps both sources so removing the user rule
-- cannot hide a surviving mod.info relationship.
function Model:groups(id, info)
    info = info or {}
    local rule = self.draft[id] or {}
    local result = {}
    for _, key in ipairs(fields) do
        local group, byId = {}, {}
        local function collect(list, source)
            for _, other in ipairs(type(list) == 'table' and list or {}) do
                if type(other) == 'string' then
                    local entry = byId[other]
                    if not entry then entry = { id = other }; byId[other] = entry; group[#group + 1] = entry end
                    entry[source] = true
                end
            end
        end
        collect(info[key], 'metadata')
        collect(rule[key], 'user')
        result[key] = group
    end
    for _, key in ipairs({ 'requirements', 'requiredBy' }) do
        result[key] = {}
        for _, other in ipairs(info[key] or {}) do
            if type(other) == 'string' then result[key][#result[key] + 1] = { id = other, metadata = true } end
        end
    end
    return result
end

function Model:commit()
    local snapshot = utils:deepCopy(self.draft)
    local ok, result = pcall(function() return core.layers.SortingRules:commitEdit(snapshot) end)
    if not ok or result ~= true then return false, ok and 'save failed' or tostring(result) end
    self.original = utils:deepCopy(snapshot)
    return true
end
return Model
