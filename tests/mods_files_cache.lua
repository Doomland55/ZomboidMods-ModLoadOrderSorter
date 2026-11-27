-- Run from repository root with Lua 5.1 (or another Lua runtime):
-- lua tests/mods_files_cache.lua
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/REfRigERatoR_ModLoadOrderSorter/'
local prefix = 'REfRigERatoR_ModLoadOrderSorter/'
local files, now, steam, scanCount = {}, 1000000, {}, 0
local activeQueries = {}
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
function getLoadedLuaCount() return 2 end
function getLoadedLua(i) return ({'/mods/A/media/lua/client/a.lua', '/mods/B/media/lua/client/b.lua'})[i+1] end
function getModFileReader() return { close = function() end } end
function getSteamWorkshopItemIDs() return array({'unrelated'}) end
function querySteamWorkshopItemDetails(ids, callback, arg)
    assert(arg == nil)
    activeQueries = ids.values
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
    local info = {}
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
assert(layer.cache.A.complete == false and #layer.notLoaded == 2)
layer:load({a,b}); assert(scanCount == 2, 'fresh cache must not be scanned')
steam['123'] = 101
layer:load({a}); assert(scanCount == 3 and layer.cache.A.updatedTime == 101)
assert(layer.cache.B ~= nil, 'inactive cache entry lost')
-- Force a cache reload, proving all entries and timestamps were serialized.
layer.cacheLoaded = false; layer.cache = {}; layer:load({a})
assert(scanCount == 3 and layer.cache.B.lastAnalyzedTime == now)
steam = false; now = now + 86400
layer:load({a,b}); assert(scanCount == 3, 'exactly one day is not older than one day')
now = now + 1; layer:load({a,b}); assert(scanCount == 5)
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
