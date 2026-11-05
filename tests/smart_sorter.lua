-- Run from the repository root with a Lua 5.1 interpreter: lua tests/smart_sorter.lua
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/'
package.path = base .. '?.lua;' .. package.path
package.preload.luautils = function() return {trim=function(s) return (s:gsub('^%s*(.-)%s*$', '%1')) end} end
luautils = require('luautils')
getGameVersion = function() return '42.21' end
cacheFileExists = function() return false end
getFileWriter = function() return {write=function() end, close=function() end} end
getText = function(k, ...) return k end
getFileSeparator = function() return '/' end
local root = 'REfRigERatoR_ModLoadOrderSorter/'
local core = require(root .. 'Core/Core')
local utils = require(root .. 'Core/1_Utils')
local sorter = require(root .. 'Core/2_SortingCore')
local rules = require(root .. 'Layers/3_SortingRules')
core.layers = { modInfo={data={}}, modFiles={data={}}, sortingRules=rules }
local function items(...)
    local result = {}
    for _, id in ipairs({...}) do result[#result+1] = {item={modId=id,name=id}} end
    return result
end
local function eq(a,b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
local data = core.layers.modInfo.data
-- Recursive category promotion and alphabetical order within the promoted category.
data.A={name='A',category='vehicle',requirements={'B'}}
data.B={name='B',category='code',requirements={'C'}}
data.C={name='C',category='translation'}
local sorted=sorter:sort(items('A','B','C'), {})
eq(table.concat(sorted, ','), 'C,B,A'); eq(data.C.effectiveCategory, 'vehicle')
-- Working overrides must not mutate or consult saved rules.
rules.data={A={loadAfter={'B'}}}
local override={A={loadBefore={'B'}}}
data.A.requirements={}; data.B.requirements={}; data.A.category='code'; data.B.category='code'
sorted=sorter:sort(items('B','A'), override)
eq(table.concat(sorted, ','), 'A,B'); eq(rules.data.A.loadAfter[1], 'B')
-- Category and global positions are independent; validation priority is purple > red > yellow.
local statuses=sorter:validate(items('A','B','C'), {A={loadLast='on',incompatibleMods={'B'}}})
eq(statuses.A,'purple'); eq(statuses.B,'purple')
data.A.requirements={'missing'}; statuses=sorter:validate(items('A','B'), {})
eq(statuses.A,'red')
data.A.requirements={}; statuses=sorter:validate(items('A','B'), {A={loadAfter={'B'}}})
eq(statuses.A,'yellow')
-- Only edges in a cycle may be broken, not unrelated downstream edges.
data.A.requirements={'B'}; data.B.requirements={'A'}; data.C.requirements={}
core.layers.modFiles.data={A={files={'shared'},modifications={}},C={files={'shared'},modifications={}}}
sorted=sorter:sort(items('A','C','B'), {})
eq(#sorted,3); eq(#sorter.brokenEdges,1); assert(sorter.brokenEdges[1].weight==100)
-- Saved/working nested lists are independent; first/last are exclusive.
rules.data={A={loadAfter={'B'},loadFirst='on'}}; rules.loaded=true
local working=rules:beginEdit(); working.A.loadAfter[1]='C'; eq(rules.data.A.loadAfter[1],'B')
rules:setPosition('A','loadLast','category'); eq(working.A.loadFirst,'off')
rules:discardEdit(); eq(rules.working.A.loadAfter[1],'B'); eq(rules.data.A.loadFirst,'on')
local cyc={}; cyc.self=cyc; local copy=utils:deepCopy(cyc); assert(copy ~= cyc and copy.self == copy)
print('smart sorter tests passed')
-- Fake PZ front-end and Steam APIs exercise callback, parsing, cache and fallback.
local handlers = {}
Events = {OnFETick={Add=function(f) handlers[#handlers+1]=f end, Remove=function(f)
    for i=#handlers,1,-1 do if handlers[i]==f then table.remove(handlers,i) end end
end}}
local loaded = {'/mods/test/42.0/media/lua/client/test.lua'}
getLoadedLuaCount=function() return #loaded end
getLoadedLua=function(i) return loaded[i+1] end
local function javaList(t) return {size=function() return #t end, get=function(_, i) return t[i+1] end} end
listFilesInModDirectory=function() return javaList({'media/lua/client/test.lua'}) end
local lines={'local InvPane = ISInventoryPane', '--[[', 'function Ignored:one() end', ']]', 'function InvPane:prerender() end', '-- function Ignored:two() end'}
getModFileReader=function(id, name)
    local content = name=='mod.info' and {'version=1'} or lines
    local i=0
    return {readLine=function() i=i+1; return content[i] end,close=function() end}
end
getSteamWorkshopItemIDs=function() return javaList({'123'}) end
local steamCallback
querySteamWorkshopItemDetails=function(ids, callback, self) steamCallback=function(status, info) callback(self,status,info) end end
local modInfo={getDir=function() return '/mods/test' end,getVersionDir=function() return '/mods/test/42.0' end,
    getCommonDir=function() return '/mods/test/common' end,getWorkshopID=function() return '123' end}
local files=require(root .. 'Layers/1_ModsFiles')
local complete=false
files:queryAndGetData({{item={modId='test',modInfo=modInfo}}},{onComplete=function() complete=true end})
assert(steamCallback and not complete)
steamCallback('Completed', javaList({{getIDString=function() return '123' end,getTimeUpdated=function() return 50 end}}))
while #handlers > 0 do handlers[1]() end
assert(complete); assert(files.data.test.complete); eq(#files.data.test.modifications, 1)
eq(files.data.test.modifications[1].fullTarget,'ISInventoryPane:prerender')
assert(files.data.test.signature:match('|50$'))
-- Failed Steam query must preserve an existing cache rather than force a rescan.
complete=false
files:queryAndGetData({{item={modId='test',modInfo=modInfo}}},{onComplete=function() complete=true end})
steamCallback('NotCompleted')
assert(complete); eq(#handlers, 0); assert(files.data.test.complete)
print('file analysis tests passed')
eq(files.data.test.files['media/lua/client/test.lua'][1], 'ISInventoryPane:prerender')
-- Only a newer workshop timestamp causes another scan.
complete=false
files:queryAndGetData({{item={modId='test',modInfo=modInfo}}},{onComplete=function() complete=true end})
steamCallback('Completed', javaList({{getIDString=function() return '123' end,getTimeUpdated=function() return 51 end}}))
assert(not complete); assert(#handlers > 0)
while #handlers > 0 do handlers[1]() end
assert(complete); assert(files.data.test.signature:match('|51$'))
print('cache invalidation tests passed')
-- Requirements from mod.info are merged with ChooseGameInfo, including reverse links.
isSystemLinux=function() return true end
Translator={getLanguage=function() return {name=function() return 'EN' end} end}
getMapFoldersForMod=function() return javaList({}) end
local infoFiles={A={'require=B','incompatible=C'},B={},C={}}
getModFileReader=function(id, name)
    local content=infoFiles[id] or {}; local i=0
    return {readLine=function() i=i+1; return content[i] end,close=function() end}
end
local function pzInfo(id)
    return {getName=function() return id end,getId=function() return id end,getCategory=function() return 'code' end,
        getRequire=function() return javaList({}) end,getLoadAfter=function() return javaList({}) end,
        getLoadBefore=function() return javaList({}) end,getIncompatible=function() return javaList({}) end}
end
local infos=require(root .. 'Layers/2_ModsInfo')
local ilist={}
for _, id in ipairs({'A','B','C'}) do ilist[#ilist+1]={item={modId=id,modInfo=pzInfo(id)}} end
infos:getData(ilist, {}, true)
eq(infos.data.A.requirements[1],'B'); eq(infos.data.B.requiredBy[1],'A'); eq(infos.data.A.incompatibleMods[1],'C')
infos:getData({ilist[2],ilist[3]}, {}, false); eq(#infos.data.B.requiredBy,0)
print('metadata tests passed')
-- A committed edit writes the working snapshot; discarding never writes it.
local written=''
getFileWriter=function() return {write=function(_, text) written=written..text end,close=function() end} end
rules.data={A={loadAfter={'B'}}}; rules.loaded=true
local edit=rules:beginEdit(); edit.A.loadAfter[1]='C'
rules:discardEdit(); eq(written,''); eq(rules.data.A.loadAfter[1],'B')
edit=rules:beginEdit(); edit.A.loadAfter[1]='C'; assert(rules:commitEdit())
assert(written:find('loadAfter=C',1,true)); eq(rules.data.A.loadAfter[1],'C')
print('rules persistence tests passed')
