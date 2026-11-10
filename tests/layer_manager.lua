-- Layer lifecycle with stub layers. Run from repository root using Lua 5.1 (or lupa.lua51).
local root='REfRigERatoR_ModLoadOrderSorter/'
package.path='Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/?.lua;'..package.path
local handlers={}
Events={OnFETick={Add=function(f) handlers[#handlers+1]=f end,Remove=function(f)
    for i=#handlers,1,-1 do if handlers[i]==f then table.remove(handlers,i) end end
end}}
local clock=0
getTimestampMs=function() return clock end
_G.next=nil -- match PZ, where the global next iterator is unavailable
local function tick()
    clock=clock+100
    local copy={}; for i,f in ipairs(handlers) do copy[i]=f end
    for _,f in ipairs(copy) do f() end
end
local function drain()
    local n=0; while #handlers>0 do n=n+1; assert(n<100,'lifecycle did not finish'); tick() end
end
getText=function(k) return k end
local core={layers={}}
package.loaded[root..'Core/Core']=core

local log={}
local mode='ok'
local rules={data={}}
function rules:load(ctx)
    log[#log+1]='rules'
    self.seenReread=ctx.reread
    if mode=='failedRule' then error('bad rule data') end
    self.data={value=ctx.mods[1]}
end
local info={data={}}
function info:load(ctx)
    log[#log+1]='info'
    -- Layers registered earlier are already loaded when this one starts.
    assert(mode~='ok' or core.layers.sortingRules.data.value==ctx.mods[1])
    local seen={}
    for i,mod in ipairs(ctx.mods) do
        seen[i]=mod
        clock=clock+3            -- each unit of work costs 3 ms of the 8 ms frame budget
        ctx:step(i,#ctx.mods)
    end
    self.data={value=ctx.mods[1],seen=seen}
end
local files={data={},cancelled=0}
local external
function files:load(ctx)
    log[#log+1]='files'
    local result
    external=function(value) result=value end   -- e.g. a Steam callback
    while result==nil do ctx:wait() end
    if result=='error' then error('external failure') end
    self.data={value=result}
end
function files:cancel() self.cancelled=self.cancelled+1 end
function files:getWarnings() return {{title='file warning'}} end
package.loaded[root..'Layers/SortingRules']=rules
package.loaded[root..'Layers/ModsInfo']=info
package.loaded[root..'Layers/ModsFiles']=files
local manager=require(root..'Layers/LayerManager')
assert(manager==core.layersManager and core.layers.modFiles==files)

-- Nothing runs inside initialise; layers run one by one in registration order.
local mods={'m1','m2','m3','m4','m5','m6','m7'}
local calls,latest=0
manager:initialise(mods,{reread=true,onProgress=function(s) latest=s end,onComplete=function(s) assert(s.success); calls=calls+1 end})
mods[1]='changed after start'   -- the run works on its own snapshot of the list
assert(#log==0 and #handlers==1 and not manager:isCompleted())
assert(latest.total==3 and latest.finished==0 and latest.layers[1].status=='pending')
-- Frame budget: rules finish, info handles three mods (9 ms >= 8 ms) and yields.
tick()
assert(table.concat(log,',')=='rules,info' and rules.seenReread==true)
assert(latest.layers[1].status=='loaded' and latest.layers[2].status=='running' and latest.layers[3].status=='pending')
assert(latest.layers[2].progress.current==3 and latest.layers[2].progress.total==7 and latest.finished==1)
assert(math.abs(latest.progress-(1+3/7))<1e-9)
tick(); assert(latest.layers[2].progress.current==6 and #log==2)
-- The third tick finishes info and, with budget left, starts the next layer in the same frame.
tick(); assert(latest.layers[2].status=='loaded' and info.data.seen[1]=='m1' and #info.data.seen==7)
assert(log[3]=='files' and latest.layers[3].status=='running')
-- A layer waiting for an external result stays "running" without blocking frames.
tick(); tick()
assert(#log==3 and latest.layers[3].status=='running' and calls==0 and #manager:getWarnings()==0)
external('done'); tick()
assert(calls==1 and #handlers==0 and manager:isCompleted() and manager:isSuccessful())
assert(files.data.value=='done' and latest.completed and latest.finished==3 and latest.progress==3)
assert(#manager:getWarnings()==1 and files.cancelled==0)

-- A failed layer does not stop the following ones, but the run is not successful.
mode='failedRule'; calls=0
manager:initialise({'second'},{onComplete=function(s) assert(not s.success and s.failed==1); calls=calls+1 end})
tick(); tick(); external('ok'); drain()
assert(calls==1 and manager:isCompleted() and not manager:isSuccessful())
local status=manager:getStatus()
assert(status.layers[1].status=='failed' and status.layers[1].error:find('bad rule data',1,true))
assert(status.layers[2].status=='loaded' and status.layers[3].status=='loaded')
local warnings=manager:getWarnings()
assert(#warnings==2 and warnings[1].severity=='CRITICAL' and warnings[1].layer=='sortingRules')
-- A layer that fails after waiting releases its resources through cancel().
mode='ok'
manager:initialise({'third'}); tick(); tick(); external('error'); drain()
assert(files.cancelled==1 and manager:getStatus().layers[3].error:find('external failure',1,true))

-- Reinitialisation drops the old run: its coroutine never resumes and its callbacks stay silent.
local firstDone,secondDone=false,false
manager:initialise({'old'},{onComplete=function() firstDone=true end})
tick(); tick(); tick()
local oldExternal=external
assert(manager:getStatus().layers[3].status=='running')
manager:initialise({'new'},{onComplete=function(s) secondDone=s.success end})
assert(files.cancelled==2 and #handlers==1)
oldExternal('late'); tick(); tick(); tick()
assert(not firstDone and not secondDone and files.data.value~='late')
external('fresh'); drain()
assert(secondDone and not firstDone and files.data.value=='fresh' and info.data.value=='new')

-- Explicit cancel removes the tick handler and leaves the run unfinished.
manager:initialise({'cancelled'}); tick(); tick(); tick()
manager:cancel(); manager:cancel()
assert(files.cancelled==3 and #handlers==0 and not manager:isCompleted() and not manager:isSuccessful())
external('ignored'); tick(); assert(files.data.value=='fresh')

-- A new layer is one register call; a broken module is reported instead of breaking the others.
local extra={data={}}
function extra:load(ctx) self.data={sawFiles=core.layers.modFiles.data.value} end
manager:registerLayer('extra',extra)
manager:registerLayer('broken',nil)
assert(manager:getStatus().total==5 and not manager:isCompleted())
manager:initialise({'fifth'}); tick(); tick(); external('for extra'); drain()
status=manager:getStatus()
assert(extra.data.sawFiles=='for extra' and status.layers[4].status=='loaded')
assert(status.layers[5].status=='failed' and status.layers[5].error:find('load(ctx)',1,true) and not status.success)
-- Registering under an existing name replaces the layer without changing the order.
manager:registerLayer('broken',{load=function() end})
manager:initialise({'sixth'}); tick(); tick(); external('x'); drain()
assert(manager:getStatus().total==5 and manager:isSuccessful())
print('layer lifecycle tests passed')
