-- Run from the repository root with Lua 5.1, or through lupa.lua51.
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/'
package.path = base .. '?.lua;' .. package.path
package.preload.luautils = function() return {trim=function(s) return (s:gsub('^%s*(.-)%s*$', '%1')) end} end
luautils = require('luautils')
getGameVersion=function() return '42.21' end
getFileSeparator=function() return '/' end
local saved = nil
cacheFileExists=function() return saved ~= nil end
getFileWriter=function() local parts = {}; return {
    write=function(_, s) parts[#parts+1]=s end,
    close=function() saved=table.concat(parts) end,
} end
getFileReader=function()
    if not saved then return nil end
    local pos=1
    return {readLine=function()
        if pos > #saved then return nil end
        local e=saved:find('\n',pos,true)
        local line=e and saved:sub(pos,e-1) or saved:sub(pos)
        pos=e and e+1 or #saved+1
        return (line:gsub('\r$', ''))
    end,close=function() end}
end
local tick={}
Events={OnFETick={Add=function(f) tick[#tick+1]=f end, Remove=function(f)
    for i=#tick,1,-1 do if tick[i]==f then table.remove(tick,i) end end
end}}
local function drain()
    local n=0
    while #tick>0 do n=n+1; assert(n<500, 'analysis stuck'); tick[1]() end
end
local function jlist(t) return {size=function() return #t end,get=function(_,i) return t[i+1] end} end
local listed={'media/lua/client/test.lua'}
listFilesInModDirectory=function() return jlist(listed) end
local loaded={}
getLoadedLuaCount=function() return #loaded end
getLoadedLua=function(i) return loaded[i+1] end
local original='local P = ISInventoryPane\r\n-- comment\r\nfunction P:prerender() end\r\n'
getModFileReader=function(_, path)
    local input = path=='mod.info' and 'version=1\n' or original
    local p=1
    return {readLine=function()
        if p>#input then return nil end
        local e=input:find('\n',p,true)
        local line=e and input:sub(p,e-1) or input:sub(p)
        p=e and e+1 or #input+1
        return (line:gsub('\r$', ''))
    end, close=function() end}
end
local root='REfRigERatoR_ModLoadOrderSorter/'
local files=require(root..'Layers/ModsFiles')
local info={getDir=function() return '/mods/test' end,getVersionDir=function() return '/mods/test/42.0' end,
    getCommonDir=function() return '/mods/test/common' end,getWorkshopID=function() return nil end}
local mods={{item={modId='test',modInfo=info}}}
local paths={'media/lua/client/test.lua'}
local sources={original}
local fingerprint='sha-a'
local pending=1
local fail=false
local releases=0
MLOS_BuddyBegin=function(id) assert(id=='test'); return 'job' end
MLOS_BuddyState=function() if fail then return 'error' end; if pending>0 then pending=pending-1; return 'pending' end; return 'ready' end
MLOS_BuddyCount=function() return #paths end
MLOS_BuddyPath=function(_, i) return paths[i+1] end
MLOS_BuddySource=function(_, i) return sources[i+1] end
MLOS_BuddyFingerprint=function() return fingerprint end
MLOS_BuddyRelease=function() releases=releases+1 end
local function run(opts)
    local completed=false
    opts=opts or {}
    opts.onComplete=function() completed=true end
    files:queryAndGetData(mods, opts)
    drain()
    assert(completed)
end
-- A newly enabled, not loaded mod is analysed; cache is written in the existing format.
run()
assert(files.data.test.complete and not files:hasNotLoadedMods())
assert(files.data.test.modifications[1].fullTarget=='ISInventoryPane:prerender')
assert(files.data.test.modifications[1].line==3 and files.data.test.modifications[1].alias=='P')
assert(saved:find('fssignature=sha%-a') and saved:find('mod=media/lua/client/test.lua|ISInventoryPane:prerender|3|false|P',1,true))
assert(releases==1)
-- A Java cache is readable without the bridge, including after a file reload.
local bridge={MLOS_BuddyBegin,MLOS_BuddyState,MLOS_BuddyCount,MLOS_BuddyPath,MLOS_BuddySource,MLOS_BuddyFingerprint,MLOS_BuddyRelease}
MLOS_BuddyBegin=nil
run({reread=true})
assert(files.data.test.complete and files.data.test.fsSignature=='sha-a')
assert(files:hasNotLoadedMods()) -- legacy warning remains unchanged
assert(files.data.test.modifications[1].fullTarget=='ISInventoryPane:prerender')
-- Re-enable bridge, reload the same cache, and avoid parsing an unchanged snapshot.
MLOS_BuddyBegin=bridge[1]
run({reread=true})
assert(#files.staleMods==0 and not files:hasNotLoadedMods())
-- Same paths/count and workshop timestamp, but changed contents: reparse.
fingerprint='sha-b'; sources={'function ISInventoryPane:render() end\n'}
run({reread=true})
assert(#files.staleMods==1 and files.data.test.modifications[1].fullTarget=='ISInventoryPane:render')
-- A cache written by the legacy reader is accepted by the Java path too.
MLOS_BuddyBegin=nil; saved=nil; files.cache=nil; loaded={'/mods/test/42.0/media/lua/client/test.lua'}
run()
assert(files.data.test.complete and not saved:find('fssignature=',1,true))
MLOS_BuddyBegin=bridge[1]; fingerprint='sha-c'; sources={original}
run({reread=true})
assert(#files.staleMods==0 and files.data.test.modifications[1].fullTarget=='ISInventoryPane:prerender')
assert(files.data.test.fsSignature=='sha-c')
-- A failed bridge falls back and cannot mark an apparently empty mod complete.
fail=true; loaded={}; listed={}; files.cache={}; saved=nil
run()
assert(not files.data.test.complete and files:hasNotLoadedMods())
assert(saved:find('complete=false',1,true))
-- A failed mod does not prevent the remaining mods from being analysed.
local otherInfo={getDir=function() return '/mods/other' end,getVersionDir=function() return '/mods/other/42.0' end,
    getCommonDir=function() return '/mods/other/common' end,getWorkshopID=function() return nil end}
mods={{item={modId='test',modInfo=info}},{item={modId='other',modInfo=otherInfo}}}
MLOS_BuddyBegin=function(id) return id end
MLOS_BuddyState=function(id) return id=='test' and 'error' or 'ready' end
fingerprint='sha-other'; sources={'local A = ISPanel\rfunction A:render() end\r'}
files.cache={}; saved=nil
run()
assert(not files.data.test.complete and files.data.other.complete)
assert(#files.notLoaded==1 and files.notLoaded[1]=='test')
assert(files.data.other.modifications[1].fullTarget=='ISPanel:render' and files.data.other.modifications[1].line==2)
mods={{item={modId='test',modInfo=info}}}
MLOS_BuddyBegin=bridge[1]; MLOS_BuddyState=bridge[2]
-- Cancelling an in-flight request releases its worker and ignores the old completion.
fail=false; pending=100; listed={'media/lua/client/test.lua'}
local first=false
files:queryAndGetData(mods,{onComplete=function() first=true end})
tick[1]()
local before=releases
pending=0
run()
assert(releases>=before+2 and not first and files.data.test.complete)
print('ZombieBuddy integration tests passed')
