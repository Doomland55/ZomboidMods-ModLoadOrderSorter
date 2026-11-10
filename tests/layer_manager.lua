-- Run from repository root using Lua 5.1 (or lupa.lua51).
local root='REfRigERatoR_ModLoadOrderSorter/'
package.path='Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/?.lua;'..package.path
local handlers={}
Events={OnFETick={Add=function(f) handlers[#handlers+1]=f end,Remove=function(f)
    for i=#handlers,1,-1 do if handlers[i]==f then table.remove(handlers,i) end end
end}}
local function tick()
    local copy={}; for i,f in ipairs(handlers) do copy[i]=f end
    for _,f in ipairs(copy) do
        local active=false; for _,v in ipairs(handlers) do if v==f then active=true end end
        if active then f() end
    end
end
local function drain()
    local n=0; while #handlers>0 do n=n+1; assert(n<100,'lifecycle did not finish'); tick() end
end
getText=function(k) return k end
local utils={}
function utils:MergeTablesDedup(out,src) for k,v in pairs(src or {}) do out[k]=v end end
local core={layers={}}
package.loaded[root..'Core/1_Utils']=utils
package.loaded[root..'Core/Core']=core
local mode='ok'
local starts, deferred = {}, {}
local cancelled=0
local rules={data={}}
function rules:getData(mods,ctx)
    starts.rules=(starts.rules or 0)+1
    assert(core.layers.modInfo and core.layers.modFiles and core.layers.extra)
    self.seenReread=ctx.reread
    if mode=='startFail' then error('start failed') end
    local count=0
    ctx:onTick(function()
        count=count+1
        if count<3 then return end
        if mode=='failedRule' then error('bad rule data') end
        self.data={value=mods[1]}; ctx:complete()
        if mode=='finishFail' then error('failure after completion') end
    end)
end
local files={data={}}
function files:getData(mods,ctx)
    starts.files=(starts.files or 0)+1
    ctx:progress(1,4)
    deferred[#deferred+1]=ctx
end
function files:cancel() cancelled=cancelled+1 end
function files:getWarnings() return {{title='file warning'}} end
local info={data={}}
function info:getData(mods,ctx)
    starts.info=(starts.info or 0)+1
    ctx:onTick(function()
        local required = mode=='cycle' and 'extra' or 'sortingRules'
        if not ctx:waitFor(required) then return end
        assert(core.layers[required].loaded)
        if mode=='ok' then assert(core.layers.sortingRules.data.value==mods[1]) end
        self.data={value=mods[1]}; ctx:complete()
    end)
end
local extra={data={}}
function extra:getData(mods,ctx)
    starts.extra=(starts.extra or 0)+1
    ctx:onTick(function()
        if not ctx:waitFor(mode=='missing' and 'unknown' or 'modInfo') then return end
        self.data={value=mods[1]}; ctx:complete()
    end)
end
package.loaded[root..'Layers/SortingRules']=rules
package.loaded[root..'Layers/ModsFiles']=files
package.loaded[root..'Layers/ModsInfo']=info
package.loaded[root..'Layers/extra']=extra
require(root..'Layers/LayerManager')
local manager=core.layersManager
manager:registerLayer('extra',root..'Layers/extra')
local calls,latest=0
manager:initialise({'first'},{reread=true,onProgress=function(s) latest=s end,onComplete=function() calls=calls+1 end})
assert(not manager:isCompleted() and #handlers==1 and latest.finished==0 and latest.total==4)
assert(starts.rules==1 and starts.info==1 and starts.files==1 and starts.extra==1)
tick()
assert(rules.status=='running' and info.status=='waiting' and info.waitingFor=='sortingRules')
assert(files.status=='running' and files.layerProgress.current==1 and extra.status=='waiting')
assert(manager:getStatus().progress==0.25 and calls==0)
tick(); tick()
assert(rules.loaded and info.loaded and extra.loaded and not files.loaded and calls==0)
assert(rules.seenReread and manager:getStatus().finished==3 and #manager:getWarnings()==0)
local old=deferred[1]
manager:initialise({'second'},{onComplete=function() calls=calls+10 end})
assert(cancelled==1 and old:isCancelled())
old:complete(); assert(not files.loaded)
tick(); tick(); tick()
assert(info.loaded and info.data.value=='second' and not files.loaded and calls==0)
deferred[2]:complete(); drain()
assert(manager:isCompleted() and manager:isSuccessful() and calls==10)
assert(manager:getStatus().loaded==4 and #manager:getWarnings()==1)
mode='failedRule'
manager:initialise({'third'},{onComplete=function(s) assert(not s.success); calls=calls+100 end})
deferred[#deferred]:complete(); drain()
assert(not manager:isSuccessful() and manager:isCompleted())
assert(rules.status=='failed' and info.status=='failed' and extra.status=='failed' and files.loaded)
assert(#manager:getWarnings()==4 and calls==110)
mode='missing'; manager:initialise({'fourth'}); deferred[#deferred]:complete(); drain()
assert(extra.status=='failed' and extra.error:find('Unknown layer dependency',1,true))
mode='cycle'; manager:initialise({'fifth'}); deferred[#deferred]:complete(); drain()
assert(not manager:isSuccessful() and info.status=='failed' and extra.status=='failed')
assert(info.error:find('Cyclic',1,true) or extra.error:find('Cyclic',1,true))
for _, failingMode in ipairs({'startFail','finishFail'}) do
    mode=failingMode; manager:initialise({'error'})
    deferred[#deferred]:complete(); drain()
    assert(rules.status=='failed' and info.status=='failed' and extra.status=='failed')
end
mode='ok'; manager:initialise({'cancelled'}); tick()
local cancelledCtx=deferred[#deferred]
manager:cancel()
assert(cancelledCtx:isCancelled() and #handlers==0 and not manager:isCompleted())
assert(manager:getStatus().cancelled>0)
cancelledCtx:complete()
assert(files.status=='cancelled' and not files.loaded)
-- Dispatcher removes broken jobs without affecting other jobs, even when jobs mutate it.
local scheduler=require(root..'Layers/TickScheduler')
local errors,ran=0,0
local function broken() error('tick failure') end
local function good() ran=ran+1; scheduler:remove(good) end
scheduler:add(broken,function(err) assert(tostring(err):find('tick failure')); errors=errors+1 end)
scheduler:add(good)
assert(#handlers==1); tick(); assert(errors==1 and ran==1 and #handlers==0)
-- A callback added during dispatch runs next frame; a removed callback is skipped.
local seen={}
local second
local function first()
    seen[#seen+1]='first'; scheduler:remove(first); scheduler:remove(second)
    local function newJob() seen[#seen+1]='new'; scheduler:remove(newJob) end
    scheduler:add(newJob)
end
second=function() seen[#seen+1]='second' end
scheduler:add(first); scheduler:add(second); tick()
assert(table.concat(seen,',')=='first' and #handlers==1)
tick(); assert(table.concat(seen,',')=='first,new' and #handlers==0)
print('uniform layer lifecycle tests passed')
