-- Run from repository root with Lua 5.1.
local path = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/REfRigERatoR_ModLoadOrderSorter/Layers/ModsFilesParser.lua'
local parser = dofile(path)
local lines = {}
for i=1,400 do lines[#lines+1] = '-- filler ' .. i end
lines[#lines+1] = 'local Alias = Some.Class'
lines[#lines+1] = 'local old = Alias.method'
lines[#lines+1] = 'function Alias.method() end'
lines[#lines+1] = 'function Some.Class:other() end'
local source = table.concat(lines, '\n')
local yields = 0
local co = coroutine.create(function()
    return parser.parse(parser.stringReader(source), function() yields = yields + 1; coroutine.yield() end)
end)
local results
repeat
    local ok, value = coroutine.resume(co)
    assert(ok, value)
    results = value
until coroutine.status(co) == 'dead'
assert(yields >= 3, 'large files must yield periodically')
assert(#results == 2 and results[1].className == 'Some.Class' and results[1].methodName == 'method')
assert(results[1].isHook and results[2].separator == ':')
print('Incremental parser tests passed')
