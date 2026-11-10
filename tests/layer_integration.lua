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
local clock=0
getTimestampMs=function() return clock end
_G.next=nil -- match PZ, where the global next iterator is unavailable
local function tick()
    assert(#handlers<=1, 'the whole analysis should use one game event handler')
    clock=clock+100
    local copy={}; for i,f in ipairs(handlers) do copy[i]=f end
    for _,f in ipairs(copy) do f() end
end
local function drain(limit)
    local n=0; while #handlers>0 do n=n+1; assert(n<(limit or 100),'unfinished layer'); tick() end
    return n
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
local sorter=require(root..'Core/2_SortingCore')
local reads,infoReads=0,0
function rules:readSortingRules()
    reads=reads+1
    return {A={category=reads==1 and 'map' or 'vehicle',incompatibleMods={'B'}}}
end
local requirements={A={'B','Missing'}}
function info:getExtraModInfo(row)
    local id=row.item.modId
    infoReads=infoReads+1
    clock=clock+1   -- reading one mod.info costs 1 ms
    return {id=id,name='Name '..id,category='code',requirements=requirements[id] or {},loadAfter={},loadBefore={},incompatibleMods={}}
end
local function row(id)
    return {item={modId=id,modInfo={getDir=function() return '/mods/'..id end,
        getVersionDir=function() return '/mods/'..id..'/42.0' end,
        getCommonDir=function() return '/mods/'..id..'/common' end,
        getWorkshopID=function() return nil end}}}
end
local manager=require(root..'Layers/LayerManager')
assert(manager==core.layersManager)
local completed=0
local status
-- Without Steam and the bridge everything fits into the first frame.
local list={row('A'),row('B')}
manager:initialise(list,{onProgress=function(s) status=s end,onComplete=function(s) assert(s.success); completed=completed+1 end})
assert(not manager:isCompleted() and reads==0); tick()
assert(manager:isSuccessful() and completed==1 and status.finished==3 and reads==1 and #handlers==0)
assert(rules.data.A.category=='map' and files.steamUnavailable and files.data.A.complete)
-- ModsInfo holds facts of the enabled mods only: reverse links and missing requirements.
assert(info.data.B.requiredBy[1]=='A' and #info.data.A.requiredBy==0)
assert(#info.data.A.warnings.missing==1 and info.data.A.warnings.missing[1]=='Missing')
assert(info.data.A.sortingRules==nil and info.data.A.priority==nil)
local warnings=manager:getWarnings()
assert(#warnings==1 and warnings[1].title:find('UI_MLOS_MissingDep_Title',1,true))
-- Rule-based combinations belong to the sorting core and need no layer rerun.
local incompatible=sorter:getIncompatibleWarnings(list)
assert(#incompatible==1 and incompatible[1].severity=='CRITICAL')
assert(#sorter:getIncompatibleWarnings(list,{})==0 and #sorter:getIncompatibleWarnings({row('A')})==0)
-- Ordinary reopen reuses cached rules and mod info, and forgets mods that are no longer enabled.
manager:initialise({row('B'),row('C')},{onComplete=function(s) assert(s.success); completed=completed+1 end})
drain()
assert(completed==2 and reads==1 and infoReads==3 and info.data.C and not info.data.A and not files.data.A)
assert(#info.data.B.requiredBy==0)
-- Explicit reread reaches every layer.
manager:initialise({row('A')},{reread=true,onComplete=function(s) assert(s.success); completed=completed+1 end})
drain()
assert(completed==3 and reads==2 and infoReads==4 and rules.data.A.category=='vehicle' and not info.data.B)
-- Steam answers asynchronously: the files layer waits without blocking and uses the timestamps.
local steamCallback
getSteamWorkshopItemIDs=function() return javaList({'123'}) end
querySteamWorkshopItemDetails=function(_, callback, arg) steamCallback=function(state, details) callback(arg,state,details) end end
local last
manager:initialise({row('A')},{onProgress=function(s) status=s end,onComplete=function(s) last=s end})
tick(); tick()
assert(not last and status.layers[3].name=='modFiles' and status.layers[3].status=='running' and status.finished==2)
steamCallback('Completed', javaList({{getIDString=function() return '123' end,getTimeUpdated=function() return 77 end}}))
drain()
assert(last and last.success and not files.steamUnavailable and files.workshopTimes['123']=='77')
-- A missing Steam callback times out and a late callback changes nothing.
last=nil
manager:initialise({row('A')},{onComplete=function(s) last=s end})
local ticks=drain(400)
assert(ticks>=300 and last and last.success and files.steamUnavailable)
steamCallback('Completed', javaList({}))
assert(#handlers==0 and files.steamUnavailable)
-- Reinitialisation drops the previous Steam query; its callback is ignored.
local callbacks={}
querySteamWorkshopItemDetails=function(_, callback, arg)
    callbacks[#callbacks+1]=function(state,details) callback(arg,state,details) end
end
local firstDone, secondDone=false,false
manager:initialise({row('A')},{onComplete=function() firstDone=true end})
tick()
manager:initialise({row('B')},{onComplete=function(s) secondDone=s.success end})
tick()
callbacks[1]('Completed',javaList({}))
tick()
assert(not firstDone and not secondDone and not manager:isCompleted())
callbacks[2]('Completed',javaList({}))
drain()
assert(secondDone and not firstDone and info.data.B and not info.data.A and files.data.B and not files.data.A)
-- A malformed asynchronous result fails the layer and the manager settles visibly.
local failedCallback
querySteamWorkshopItemDetails=function(_, callback, arg) failedCallback=function() callback(arg,'Completed',{}) end end
local failedStatus
manager:initialise({row('A')},{onComplete=function(s) failedStatus=s end})
tick(); failedCallback(); drain()
assert(failedStatus and not failedStatus.success and failedStatus.layers[3].status=='failed')
assert(failedStatus.layers[1].status=='loaded' and failedStatus.layers[2].status=='loaded')
warnings=manager:getWarnings()
assert(warnings[#warnings].layer=='modFiles' and warnings[#warnings].severity=='CRITICAL')
-- A synchronous "NotCompleted" answer (no query handle) is handled like a missing answer.
querySteamWorkshopItemDetails=function(_, callback, arg) callback(arg,'NotCompleted') end
manager:initialise({row('A')}); tick()
assert(manager:isSuccessful() and files.steamUnavailable)
-- The same lifecycle waits for the optional bridge.
querySteamWorkshopItemDetails=nil; getSteamWorkshopItemIDs=nil
local pending=3
MLOS_BuddyBegin=function() return 'bridge' end
MLOS_BuddyState=function() if pending>0 then pending=pending-1; return 'pending' end; return 'ready' end
MLOS_BuddyCount=function() return 1 end
MLOS_BuddyPath=function() return 'media/lua/client/test.lua' end
MLOS_BuddySource=function() return 'function ISPanel:render() end\n' end
MLOS_BuddyFingerprint=function() return 'hash' end
MLOS_BuddyRelease=function() end
local bridgeDone=false
manager:initialise({row('Z')},{onComplete=function(s) bridgeDone=s.success end})
assert(drain()==4)
assert(bridgeDone and files.data.Z.complete and not files:hasNotLoadedMods())
assert(files.data.Z.modifications[1].fullTarget=='ISPanel:render')
MLOS_BuddyBegin=nil
-- Long work is sliced by the frame budget (8 ms), and its progress reaches the UI callback.
local batch={}; for i=1,20 do batch[i]=row('M'..i) end
local seen={}
manager:initialise(batch,{reread=true,onProgress=function(state)
    local item=state.layers[2]
    assert(item.name=='modInfo')
    if item.status=='running' then seen[#seen+1]=item.progress.current..'/'..item.progress.total end
end})
drain()
assert(manager:isSuccessful() and table.concat(seen,',')=='8/20,16/20')
print('real layer integration tests passed')
