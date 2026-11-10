-- Integration of the real layers and manager with simulated PZ front-end APIs.
local root='REfRigERatoR_ModLoadOrderSorter/'
package.path='Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/?.lua;'..package.path
package.preload.luautils=function() return {trim=function(s) return (s:gsub('^%s*(.-)%s*$','%1')) end} end
luautils=require('luautils')
getGameVersion=function() return '42.21' end
cacheFileExists=function() return false end
getFileWriter=function() return {write=function() end,close=function() end} end
getText=function(k) return k end
getFileSeparator=function() return '/' end
local handlers={}
Events={OnFETick={Add=function(f) handlers[#handlers+1]=f end,Remove=function(f)
    for i=#handlers,1,-1 do if handlers[i]==f then table.remove(handlers,i) end end
end}}
local function tick()
    local copy={}; for i,f in ipairs(handlers) do copy[i]=f end
    for _,f in ipairs(copy) do local live=false; for _,v in ipairs(handlers) do if v==f then live=true end end; if live then f() end end
end
local function drain()
    local n=0; while #handlers>0 do n=n+1; assert(n<100,'unfinished layer'); tick() end
end
local function javaList(a) return {size=function() return #a end,get=function(_,i) return a[i+1] end} end
getLoadedLuaCount=function() return 0 end
getLoadedLua=function() return nil end
listFilesInModDirectory=function() return javaList({}) end
getModFileReader=function() local used=false; return {readLine=function() if used then return nil end; used=true; return 'version=1' end,close=function() end} end
isSystemLinux=function() return true end
Translator={getLanguage=function() return {name=function() return 'EN' end} end}
local core=require(root..'Core/Core')
local rules=require(root..'Layers/SortingRules')
local info=require(root..'Layers/ModsInfo')
local files=require(root..'Layers/ModsFiles')
local reads,scans=0,0
function rules:readSortingRules()
    reads=reads+1
    coroutine.yield() -- dependent layer must wait for loaded state
    return {A={category=reads==1 and 'map' or 'vehicle'}}
end
function info:getExtraModInfo(row)
    local id=row.item.modId
    return {id=id,name=id,category='code',requirements={},loadAfter={},loadBefore={},incompatibleMods={}}
end
local original=files.queryAndGetData
files.queryAndGetData=function(self,...) scans=scans+1; return original(self,...) end
local function row(id)
    return {item={modId=id,modInfo={getDir=function() return '/mods/'..id end,
        getVersionDir=function() return '/mods/'..id..'/42.0' end,
        getCommonDir=function() return '/mods/'..id..'/common' end,
        getWorkshopID=function() return nil end}}}
end
require(root..'Layers/LayerManager')
local manager=core.layersManager
local completed=0
local status
manager:initialise({row('A')},{onProgress=function(s) status=s end,onComplete=function(s) assert(s.success); completed=completed+1 end})
assert(not manager:isCompleted()); tick()
assert(info.status=='waiting' and not info.loaded and not rules.loaded and files.loaded)
tick(); drain()
assert(manager:isSuccessful() and completed==1 and status.finished==3 and scans==1 and reads==1)
assert(info.data.A.sortingRules.category=='map')
-- Ordinary reopen does not reread rules, but recomputes active mod info and reverse links.
manager:initialise({row('A'),row('B')},{onComplete=function(s) assert(s.success); completed=completed+1 end})
drain()
assert(completed==2 and scans==2 and reads==1 and info.data.B and info.data.A.sortingRules.category=='map')
-- Explicit reread reaches rules, and removed mods disappear from the info layer.
manager:initialise({row('A')},{reread=true,onComplete=function(s) assert(s.success); completed=completed+1 end})
drain()
assert(completed==3 and scans==3 and reads==2 and not info.data.B)
assert(info.data.A.sortingRules.category=='vehicle')
-- A missing Steam callback times out and a late callback cannot restart analysis.
local steamCallback
getSteamWorkshopItemIDs=function() return javaList({'123'}) end
querySteamWorkshopItemDetails=function(_, callback, self) steamCallback=function(status, details) callback(self,status,details) end end
local last
manager:initialise({row('A')},{onComplete=function(s) last=s end})
for i=1,1805 do if #handlers==0 then break end; tick() end
drain()
assert(last and last.success and files.steamUnavailable and manager:isCompleted())
local countAfterTimeout=scans
steamCallback('Completed', javaList({}))
assert(scans==countAfterTimeout and #handlers==0)
-- Reinitialisation cancels the previous Steam query; its callback is ignored.
local callbacks={}
querySteamWorkshopItemDetails=function(_, callback, self)
    callbacks[#callbacks+1]=function(status,details) callback(self,status,details) end
end
local firstDone, secondDone=false,false
manager:initialise({row('A')},{onComplete=function() firstDone=true end})
tick()
manager:initialise({row('B')},{onComplete=function(s) secondDone=s.success end})
tick()
callbacks[1]('Completed',javaList({}))
assert(not firstDone and not secondDone and not manager:isCompleted())
callbacks[2]('Completed',javaList({}))
drain()
assert(secondDone and not firstDone and info.data.B and not info.data.A)
-- Malformed asynchronous results fail the layer and the manager settles visibly.
local failedCallback
querySteamWorkshopItemDetails=function(_, callback, self) failedCallback=function() callback(self,'Completed',{}) end end
local failedStatus
manager:initialise({row('A')},{onComplete=function(status) failedStatus=status end})
tick(); failedCallback(); drain()
assert(failedStatus and not failedStatus.success and files.status=='failed' and not files.loaded)
assert(#manager:getWarnings()>0)
-- The same lifecycle waits for the real optional bridge path.
querySteamWorkshopItemDetails=nil; getSteamWorkshopItemIDs=nil
local ready=false
MLOS_BuddyBegin=function() return 'bridge' end
MLOS_BuddyState=function() if not ready then ready=true; return 'pending' end; return 'ready' end
MLOS_BuddyCount=function() return 1 end
MLOS_BuddyPath=function() return 'media/lua/client/test.lua' end
MLOS_BuddySource=function() return 'function ISPanel:render() end\n' end
MLOS_BuddyFingerprint=function() return 'hash' end
MLOS_BuddyRelease=function() end
local bridgeDone=false
manager:initialise({row('Z')},{onComplete=function(s) bridgeDone=s.success end})
drain()
assert(bridgeDone and files.loaded and files.data.Z.complete and not files:hasNotLoadedMods())
assert(files.data.Z.modifications[1].fullTarget=='ISPanel:render')
MLOS_BuddyBegin=nil
-- Metadata yields every eight mods, and its actual progress reaches the manager.
local batch={}; for i=1,20 do batch[i]=row('M'..i) end
local seen8,seen16=false,false
manager:initialise(batch,{onProgress=function(state)
    for _,item in ipairs(state.layers) do
        if item.name=='modInfo' and item.progress then
            if item.progress.current==8 then seen8=true end
            if item.progress.current==16 then seen16=true end
        end
    end
end})
drain()
assert(manager:isSuccessful() and seen8 and seen16)
print('real layer integration tests passed')
