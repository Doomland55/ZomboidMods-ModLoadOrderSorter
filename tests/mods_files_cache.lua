-- Run from repository root with Lua 5.1 (or another Lua runtime):
-- lua tests/mods_files_cache.lua
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/REfRigERatoR_ModLoadOrderSorter/'
local prefix = 'REfRigERatoR_ModLoadOrderSorter/'
local files, now, steam, scanCount, saveCount = {}, 1000000, {}, 0, 0
local activeQueries = {}
local queryCount = 0
local pendingCallback = nil
local function array(values)
    local a = { values = values or {} }
    function a:size() return #self.values end
    function a:get(i) return self.values[i + 1] end
    function a:clear() self.values = {} end
    function a:add(v) self.values[#self.values + 1] = v end
    return a
end
local utils = {}
function utils:getWorkshopId(info) return info:getWorkshopID() end
function utils:tableIsEmpty(t) return not t or next(t) == nil end
function utils:splitStringBySeparator(text)
    local out = {}; for part in text:gmatch('[^,]+') do out[#out+1] = part end; return out
end
function utils:joinpath(a, b) return a .. '/' .. b end
local core = { MLOS_LAYERS_ROOT = 'test', layers = {} }
function core:saveTxtFile(path, data, encode)
    saveCount = saveCount + 1
    local out = {}; for id, entry in pairs(data) do out[#out+1] = encode(id, entry) end
    files[path] = table.concat(out, '\n'); return true
end
function core:readTxtFile(path, decode)
    local out, entry = {}, nil
    for line in (files[path] or ''):gmatch('[^\r\n]+') do
        local section = line:match('^%[(.-)%]$')
        if section then entry = {}; out[section] = entry elseif entry then decode(entry, line) end
    end
    return out
end
local cm = {}
function cm.setProgress() end
function cm.checkpoint() end
function cm.sleep() end
function cm.waitUntil(predicate)
    if pendingCallback then
        assert(not predicate(), 'intermediate Steam status must not finish the wait')
        pendingCallback(); pendingCallback = nil
    end
    return not not predicate()
end
local parser = {}
function parser.parse(reader) scanCount = scanCount + 1; reader:close(); return {} end
function parser.stringReader() return { close = function() end } end
package.loaded[prefix .. 'Core/1_Utils'] = utils
package.loaded[prefix .. 'Core/Core'] = core
package.loaded[prefix .. 'Core/CorutineManager.lua'] = cm
package.loaded[prefix .. 'Layers/ModsFilesParser'] = parser
function cacheFileExists(path) return files[path] ~= nil end
function getTimestamp() return now end
local loadedMods = { A = true, B = true }
function isModActive(info) return loadedMods[info.id] == true end
function getLoadedLuaCount() return 2 end
function getLoadedLua(i) return ({'/mods/A/media/lua/client/a.lua', '/mods/B/media/lua/client/b.lua'})[i+1] end
function getModFileReader() return { close = function() end } end
function getSteamWorkshopItemIDs() return array({'unrelated'}) end
function querySteamWorkshopItemDetails(ids, callback, arg)
    assert(arg == nil)
    activeQueries = ids.values
    queryCount = queryCount + 1
    if steam == false then callback('NotCompleted'); return end
    local details = {}
    for _, id in ipairs(ids.values) do
        if steam[id] then
            local time = steam[id]
            details[#details+1] = { getIDString = function() return id end, getTimeUpdated = function() return time end }
        end
    end
    if steam.intermediate then
        callback('Pending')
        pendingCallback = function() callback('Completed', array(details)) end
    else
        callback('Completed', array(details))
    end
end
local function row(id, workshop)
    local info = { id = id }
    function info:getWorkshopID() return workshop end
    function info:getDir() return '/mods/' .. id end
    function info:getVersionDir() return '/mods/' .. id end
    function info:getCommonDir() return '/mods/' .. id end
    return { item = { modId = id, modInfo = info } }
end
local a, b = row('A', '123'), row('B', nil)
local layer = dofile(base .. 'Layers/ModsFiles.lua')
steam['123'] = 100
steam.intermediate = true
layer:load({a,b})
assert(scanCount == 2 and #activeQueries == 1 and activeQueries[1] == '123')
assert(layer.cache.A.updatedTime == 100 and layer.cache.B.lastAnalyzedTime == now)
assert(layer.cache.A.complete == false and #layer.notLoaded == 0,
    'loaded mods should not warn just because their snapshot is partial')
local previousSaves = saveCount
layer:load({a,b}); assert(scanCount == 2 and queryCount == 1, 'fresh cache must not be scanned or requeried')
assert(saveCount == previousSaves, 'unchanged cache must not be rewritten')
steam['123'] = 101
layer:load({a}); assert(scanCount == 2 and queryCount == 1 and layer.cache.A.updatedTime == 100,
    'Steam updates are checked once per session')
-- A new Lua session sees the changed Steam timestamp.
layer.workshopTimes, layer.checkedWorkshopIds = {}, {}
layer:load({a}); assert(scanCount == 3 and layer.cache.A.updatedTime == 101 and queryCount == 2)
assert(layer.cache.B ~= nil, 'inactive cache entry lost')
-- Force a cache reload, proving all entries and timestamps were serialized.
layer.cacheLoaded = false; layer.cache = {}; layer:load({a})
assert(scanCount == 3 and layer.cache.B.lastAnalyzedTime == now)
-- Simulate a new session without Steam: the failed query is not repeated.
layer.workshopTimes, layer.checkedWorkshopIds = {}, {}
steam = false; now = now + 86400
layer:load({a,b}); assert(scanCount == 3, 'exactly one day is not older than one day')
local failedQueryCount = queryCount
now = now + 1; layer:load({a,b}); assert(scanCount == 5 and queryCount == failedQueryCount)
assert(layer.cache.A.updatedTime == 101, 'offline scan must retain Steam time')
-- A failed scan cannot destroy an existing snapshot or mark it fresh.
now = now + 86401
function getModFileReader() return nil end
local old = layer.cache.A.lastAnalyzedTime
layer:load({a}); assert(layer.cache.A.lastAnalyzedTime == old and #layer.notLoaded == 1)
print('ModsFiles cache tests passed')
-- Bridge returns paths relative to the mod root, not reader paths. Version and
-- common duplicates collapse because the game reader gives version priority.
local c = row('C', nil)
function c.item.modInfo:getVersionDir() return '/mods/C/42.0' end
function c.item.modInfo:getCommonDir() return '/mods/C/common' end
local readPaths = {}
function getModFileReader(id, path)
    readPaths[#readPaths + 1] = path
    return { close = function() end }
end
function MLOS_listModFiles(id)
    assert(id == 'C')
    return array({'common/media/lua/client/shared.lua', '42.0/media/lua/client/shared.lua',
        '42.0/media/lua/client/deep/other.lua', '41.0/media/lua/ignored.lua', 'common/media/textures/x.png'})
end
layer:load({c})
assert(layer.data.C.complete and #layer.data.C.files == 2 and #readPaths == 2)
assert(layer.data.C.files[1] == 'media/lua/client/deep/other.lua')
assert(layer.data.C.files[2] == 'media/lua/client/shared.lua')
assert(#layer.notLoaded == 0)
-- Cache remains fresh; enumerating the bridge again would fail this assertion.
function MLOS_listModFiles() error('fresh cache was rescanned') end
layer:load({c}); assert(layer.data.C.complete)
print('ZombieBuddy bridge Lua tests passed')
-- Successful empty list is a complete snapshot, not an error.
local d = row('D', nil)
function d.item.modInfo:getVersionDir() return '/mods/D/42.0' end
function d.item.modInfo:getCommonDir() return '/mods/D/common' end
function MLOS_listModFiles() return array({}) end
layer:load({d}); assert(layer.data.D.complete and #layer.data.D.files == 0)
-- A bridge failure must not overwrite a previously complete snapshot.
now = now + 86401
function MLOS_listModFiles() return nil end
layer:load({c}); assert(layer.cache.C.complete and #layer.cache.C.files == 2 and #layer.notLoaded == 1)
print('Bridge empty/failure tests passed')

-- The selected mod is not necessarily loaded in the running Lua session.
MLOS_listModFiles = nil
local e = row('E', nil)
layer:load({e})
assert(#layer.notLoaded == 1 and layer.notLoaded[1] == 'E' and not layer.cache.E)
-- A previously cached partial snapshot still warns when the mod is not loaded.
loadedMods.B = false
layer.cache.B.lastAnalyzedTime = now -- fresh cache: no retry is necessary
layer:load({b})
assert(#layer.notLoaded == 1 and layer.notLoaded[1] == 'B')
-- A loaded mod without executed Lua paths (e.g. assets only) is not a failure.
local f = row('F', nil)
loadedMods.F = true
layer:load({f})
assert(#layer.notLoaded == 0 and layer.cache.F and #layer.cache.F.files == 0)
-- Fresh old partial cache entries stop generating false warnings after restart.
loadedMods.B = true
layer:load({b})
assert(#layer.notLoaded == 0 and layer.cache.B.complete == false)
print('Loaded mod warning tests passed')

-- New IDs are queried once without discarding earlier timestamps.
local x, y = row('X', '555'), row('Y', '666')
loadedMods.X, loadedMods.Y = true, true
steam = { ['555'] = 10, ['666'] = 20 }
layer.workshopTimes, layer.checkedWorkshopIds = {}, {}
local startQueries = queryCount
layer:load({x}); assert(queryCount == startQueries + 1 and layer.workshopTimes['555'] == 10)
layer:load({x,y}); assert(queryCount == startQueries + 2 and #activeQueries == 1 and activeQueries[1] == '666')
assert(layer.workshopTimes['555'] == 10 and layer.workshopTimes['666'] == 20)
layer:load({y,x}); assert(queryCount == startQueries + 2)
-- Obsolete signature fields are ignored on read and removed on the next save.
local cachePath = 'test/modsFilesCache.txt'
files[cachePath] = files[cachePath]:gsub('%[X%]', '[X]\nsignature=legacy-value')
layer.cacheLoaded = false
layer:load({x,y})
assert(not files[cachePath]:find('signature=legacy%-value'))
assert(not files[cachePath]:find('\nsignature='))
assert(layer.cache.X and layer.cache.Y)
print('Session Workshop cache and signature migration tests passed')

-- Both method syntaxes and aliases must survive cache serialization.
layer.cache.X.modifications = {
    { file = 'media/lua/x.lua', fullTarget = 'MyClass.method', line = 1, isHook = true },
    { file = 'media/lua/x.lua', fullTarget = 'MyClass:other', line = 2 },
    { file = 'media/lua/x.lua', fullTarget = 'require:Some.Path.method', line = 3 },
}
layer.cacheDirty = true
layer:load({x,y})
layer.cacheLoaded = false
layer:load({x,y})
local entries = layer.cache.X.modifications
assert(entries[1].className == 'MyClass' and entries[1].methodName == 'method' and entries[1].isHook)
assert(entries[2].className == 'MyClass' and entries[2].methodName == 'other')
assert(entries[3].className == 'require:Some.Path' and entries[3].methodName == 'method')

-- A failed bridge scan is remembered, survives cache reload and retries after
-- one day; a complete older snapshot is preserved until a successful scan.
local attempts = 0
function MLOS_listModFiles() attempts = attempts + 1; return nil end
now = now + 86401
layer:load({c}); assert(attempts == 1 and layer.cache.C.complete and layer.cache.C.buddyFailedAt == now)
layer:load({c}); assert(attempts == 1 and #layer.notLoaded == 1)
layer.cacheLoaded = false
layer:load({c}); assert(attempts == 1 and layer.cache.C.buddyFailedAt == now)
now = now + 86401
function MLOS_listModFiles() attempts = attempts + 1; return array({}) end
layer:load({c}); assert(attempts == 2 and layer.cache.C.complete and not layer.cache.C.buddyFailedAt)
print('Cache method roundtrip and bridge retry tests passed')
-- Exercise nested parser yields inside an outer Lua 5.1 task: yielding from
-- inside pcall would raise an error, while this coroutine boundary must work.
MLOS_listModFiles = nil
local realParser = dofile(base .. 'Layers/ModsFilesParser.lua')
package.loaded[prefix .. 'Layers/ModsFilesParser'] = realParser
local incrementalLayer = dofile(base .. 'Layers/ModsFiles.lua')
local bigSource = string.rep('-- filler\n', 500) .. 'function External.method() end\n'
loadedMods.G = true
local g = row('G', nil)
function getLoadedLuaCount() return 1 end
function getLoadedLua() return '/mods/G/media/lua/client/big.lua' end
function getModFileReader() return realParser.stringReader(bigSource) end
local checkpointCount = 0
function cm.checkpoint() checkpointCount = checkpointCount + 1; coroutine.yield() end
local task = coroutine.create(function() incrementalLayer:load({g}) end)
while coroutine.status(task) ~= 'dead' do
    local ok, err = coroutine.resume(task)
    assert(ok, err)
end
assert(checkpointCount >= 4, 'large parser must yield to the outer task')
assert(incrementalLayer.data.G.modifications[1].fullTarget == 'External.method')
print('Nested coroutine integration tests passed')
-- Cleanup closes an in-progress reader and releases only the task's Steam lock.
local closeCount = 0
function cm.run(_, opts) return opts end
local options = incrementalLayer:getData({g})
local cancelled = { mlosReader = { close = function() closeCount = closeCount + 1 end } }
incrementalLayer.fetchInProgress, incrementalLayer.fetchOwner = true, cancelled
options.onCancel(cancelled)
assert(closeCount == 1 and not cancelled.mlosReader and not incrementalLayer.fetchInProgress)
incrementalLayer.fetchInProgress, incrementalLayer.fetchOwner = true, {}
options.onCancel({})
assert(incrementalLayer.fetchInProgress, 'another task must retain its Steam lock')
print('ModsFiles cancellation cleanup tests passed')
