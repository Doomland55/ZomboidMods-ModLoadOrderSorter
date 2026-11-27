-- Run from repository root with Lua 5.1.
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/REfRigERatoR_ModLoadOrderSorter/'
local prefix = 'REfRigERatoR_ModLoadOrderSorter/'
local utils = {}
function utils:contains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
function utils:tableIsEmpty(t) return not t or next(t) == nil end
function utils:deepCopy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}; if seen[value] then return seen[value] end
    local copy = {}; seen[value] = copy
    for k, v in pairs(value) do copy[self:deepCopy(k, seen)] = self:deepCopy(v, seen) end
    return copy
end
local core = { rawCategoryOrder = {'code', 'undefined'} }
local cm, yieldCheckpoints = {}, false
function cm.checkpoint() if yieldCheckpoints then coroutine.yield() end end
function cm.run(fn, options)
    return coroutine.create(function() return fn(unpack(options.args)) end)
end
package.loaded[prefix .. 'Core/1_Utils'] = utils
package.loaded[prefix .. 'Core/Core'] = core
package.loaded[prefix .. 'Core/CorutineManager.lua'] = cm
function isSystemLinux() return false end
Translator = { getLanguage = function() return { name = function() return 'EN' end } end }
function getText(key, arg) return key .. (arg or '') end
local layer = dofile(base .. 'Layers/ModsInfo.lua')
local facts = { A = {'B'}, B = {}, C = {'A'} }
local reads = {}
function layer:getExtraModInfo(row)
    local id = row.item.modId
    reads[id] = (reads[id] or 0) + 1
    if id == 'bad' then error('metadata read failed') end
    return { name = id, category = 'code', requirements = utils:deepCopy(facts[id] or {}),
        object = row, warnings = {}, flags = {'example'} }
end
local function row(id) return {item = { modId = id }} end
local a, b, c = row('A'), row('B'), row('C')
layer:load({a,b,c})
assert(#layer.data.B.requiredBy == 1 and layer.data.B.requiredBy[1] == 'A')
assert(#layer.data.A.requiredBy == 1 and layer.data.A.requiredBy[1] == 'C')
assert(#layer.data.A.warnings.missing == 0)
assert(not layer.cache.A.object and not layer.cache.A.warnings and not layer.cache.A.requiredBy)
-- Disabled entries remain cached but cannot satisfy active dependencies.
layer:load({a,c})
assert(layer.data.B == nil and layer.cache.B and layer.data.A.warnings.missing[1] == 'B')
assert(#layer:getWarnings() == 1 and reads.A == 1 and reads.B == 1)
assert(#layer.data.A.requiredBy == 1 and layer.data.A.requiredBy[1] == 'C')
-- A later selection reuses metadata and refreshes the reference to its row.
local b2 = row('B')
layer:load({a,b2})
assert(layer.data.B.object == b2 and reads.B == 1 and #layer.data.A.warnings.missing == 0)
assert(#layer.data.B.requiredBy == 1 and layer.data.B.requiredBy[1] == 'A')
-- Changes in a current snapshot cannot mutate cached facts.
layer.data.A.requirements[1] = 'mutated'
layer.data.A.effectiveCategory = 'mutated'
assert(layer.cache.A.requirements[1] == 'B' and not layer.cache.A.effectiveCategory)
layer:load({})
assert(next(layer.data) == nil and layer.cache.A and layer.cache.B)
layer:load({a,a,b2})
assert(#layer.data.B.requiredBy == 1 and reads.A == 1)
-- reread applies to current mods only and doesn't destroy disabled cache entries.
facts.A = {'C'}
layer:load({a}, true)
assert(reads.A == 2 and reads.B == 1 and layer.cache.B and layer.data.A.warnings.missing[1] == 'C')
-- An exception before publication must leave previous data and cache intact.
local previousData, previousCache = layer.data, layer.cache.A
local ok = pcall(layer.load, layer, {a,row('bad')}, true)
assert(not ok and layer.data == previousData and layer.cache.A == previousCache)
-- Snapshot list at scheduling time, and reject publication from older tasks.
local selection = {a}
local first = layer:getData(selection, true)
selection[1] = b
local second = layer:getData({b}, false)
yieldCheckpoints = true
assert(coroutine.resume(first))
while coroutine.status(second) ~= 'dead' do assert(coroutine.resume(second)) end
while coroutine.status(first) ~= 'dead' do assert(coroutine.resume(first)) end
yieldCheckpoints = false
assert(layer.data.B and not layer.data.A, 'outdated task overwrote the new selection')
assert(layer.cache.A == previousCache, 'outdated task overwrote cached metadata')
print('ModsInfo snapshot and cache tests passed')
