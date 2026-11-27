-- Run from repository root with Lua 5.1.
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/REfRigERatoR_ModLoadOrderSorter/'
local tick = 0
function getTimestampMs() tick = tick + 1; return tick end
Events = { OnFETick = { Add = function() end } }
local cm = dofile(base .. 'Core/CorutineManager.lua')
local calls = 0
local task = cm.run(function() end, { onCancel = function(t) calls = calls + 1; assert(t.status == 'cancelled') end })
cm.cancel(task)
cm.cancel(task)
assert(calls == 1 and task:getStatus() == 'cancelled')
print('Coroutine cancellation callback test passed')
