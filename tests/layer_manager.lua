-- Run from repository root with Lua 5.1.
local root = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/REfRigERatoR_ModLoadOrderSorter/'
local prefix = 'REfRigERatoR_ModLoadOrderSorter/'
local clock = 0
function getTimestampMs() clock = clock + 1; return clock end
Events = { OnFETick = { Add = function() end } }
function getText(key, a, b) return key .. ':' .. tostring(a) .. ':' .. tostring(b) end
local cm = dofile(root .. 'Core/CorutineManager.lua')
local core = { layers = {} }
package.loaded[prefix .. 'Core/Core'] = core
package.loaded[prefix .. 'Core/CorutineManager.lua'] = cm
local manager = dofile(root .. 'Layers/LayerManager.lua')
local unrelated = cm.run(function() cm.waitUntil(function() return false end) end, {name='unrelated'})
core.layers.SortingRules = { getData = function() error('rules failed') end }
core.layers.ModsInfo = { getData = function()
    return cm.run(function() error('metadata failed') end, {name='info'})
end }
core.layers.ModsFiles = { getData = function() return cm.run(function() end, {name='files'}) end,
    getWarnings = function() return {{layer='ModsFiles', message='incomplete'}} end }
local completed = 0
manager:initialise({}, {onComplete=function() completed=completed+1 end})
for _=1,50 do if manager:isCompleted() then break end; cm.update() end
assert(manager:isCompleted() and not manager:isSuccessful() and completed == 1)
assert(not unrelated:isDone(), 'unrelated task must not hold up the layer batch')
local warnings = manager:getWarnings()
assert(#warnings == 3 and warnings[1].layer == 'SortingRules' and warnings[2].layer == 'ModsInfo')
assert(warnings[1].message:find('rules failed', 1, true) and warnings[2].message:find('metadata failed', 1, true))
assert(warnings[3].message == 'incomplete')
-- New runs cancel just their predecessor's tasks and suppress stale callbacks.
local oldCalls, newCalls = 0, 0
core.layers.SortingRules = { getData = function() return {} end }
core.layers.ModsInfo = { getData = function()
    return cm.run(function() cm.waitUntil(function() return false end) end, {name='old-info'})
end }
core.layers.ModsFiles = { getData = function() return cm.run(function() end) end }
local oldRun = manager:initialise({}, {onComplete=function() oldCalls=oldCalls+1 end})
assert(not manager:isCompleted())
core.layers.ModsInfo = { getData = function() return cm.run(function() end) end }
manager:initialise({}, {onComplete=function() newCalls=newCalls+1 end})
for _=1,50 do if manager:isCompleted() then break end; cm.update() end
assert(manager:isSuccessful() and newCalls == 1 and oldCalls == 0)
assert(oldRun.tasks[1]:getStatus() == 'cancelled' and not unrelated:isDone())
-- A broken warning provider becomes a warning, rather than an exception.
core.layers.ModsFiles.getWarnings = function() error('warning failed') end
manager:initialise({}, {})
for _=1,50 do if manager:isCompleted() then break end; cm.update() end
warnings = manager:getWarnings()
assert(manager:isSuccessful() and #warnings == 1 and warnings[1].message:find('warning failed',1,true))
print('Layer manager task and error tests passed')
