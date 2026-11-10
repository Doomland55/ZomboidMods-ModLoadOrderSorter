-- Lifecycle support shared by layers: one scheduled tick, error isolation,
-- dependency diagnostics and cancellation. Each layer owns its work callback.
local ticks = require('REfRigERatoR_ModLoadOrderSorter/Layers/TickScheduler')
local LayerRun = {}

function LayerRun.start(manager, entries, modsList, callbacks)
    local run = { active = true, tasks = {} }
    manager.run = run
    for _, entry in ipairs(entries) do
        run.tasks[entry.name] = { name = entry.name, layer = manager.layers[entry.name] }
    end

    local function fail(task, err, force)
        local layer = task.layer
        if not run.active or layer.status == "failed" or (layer.status == "loaded" and not force) then return end
        layer.status, layer.loaded, layer.error, layer.waitingFor = "failed", false, tostring(err), nil
        task.onTick = nil
        if type(layer.cancel) == "function" then
            local ok, cancelError = pcall(layer.cancel, layer)
            if not ok then print("[MLOS] Failed to cancel layer " .. task.name .. ": " .. tostring(cancelError)) end
        end
    end

    for _, entry in ipairs(entries) do
        local task = run.tasks[entry.name]
        if task.layer.status ~= "failed" then
            local context = { reread = callbacks.reread == true }
            function context:isCancelled() return not run.active end
            function context:onTick(fn)
                assert(type(fn) == "function", "onTick expects a function")
                task.onTick = fn
            end
            function context:stopTick() task.onTick = nil end
            function context:complete()
                if not run.active or task.layer.status == "failed" or task.layer.loaded then return end
                task.layer.status, task.layer.loaded, task.layer.waitingFor = "loaded", true, nil
                task.onTick = nil
            end
            function context:fail(err) fail(task, err) end
            function context:progress(current, total)
                if run.active and not task.layer.loaded and task.layer.status ~= "failed" then
                    task.layer.layerProgress = { current = tonumber(current) or 0, total = tonumber(total) or 0 }
                end
            end
            -- Non-blocking: call again next tick until the dependency is ready.
            function context:waitFor(name)
                local dependency = run.tasks[name]
                if not dependency then error("Unknown layer dependency: " .. tostring(name)) end
                if dependency.layer.status == "failed" then
                    error("Dependency " .. tostring(name) .. " failed: " .. tostring(dependency.layer.error))
                end
                if not dependency.layer.loaded then
                    task.layer.status, task.layer.waitingFor = "waiting", name
                    return nil
                end
                task.layer.status, task.layer.waitingFor = "running", nil
                return dependency.layer
            end
            task.context = context
            task.layer.status = "running"
            local ok, err = pcall(task.layer.getData, task.layer, modsList, context)
            if not ok then fail(task, err, true) end
        end
    end

    local function onTick()
        if not run.active then return end
        for _, entry in ipairs(entries) do
            if not run.active then return end
            local task = run.tasks[entry.name]
            if task.onTick and task.layer.status ~= "failed" and not task.layer.loaded then
                local ok, err = pcall(task.onTick)
                if not ok then fail(task, err, true) end
            end
        end
        if not run.active then return end
        -- Only explicitly reported waits can be diagnosed as cycles.
        for _, entry in ipairs(entries) do
            local task = run.tasks[entry.name]
            if task.layer.status == "waiting" then
                local visited, chain, current = {}, {}, task
                while current and current.layer.status == "waiting" do
                    if visited[current.name] then
                        fail(current, "Cyclic layer dependency: " .. table.concat(chain, " -> ") .. " -> " .. current.name)
                        break
                    end
                    visited[current.name] = true
                    chain[#chain + 1] = current.name
                    current = run.tasks[current.layer.waitingFor]
                end
            end
        end
        local state = manager:getStatus()
        if state.finished == state.total then
            manager.completed = true
            state.completed, state.success = true, state.loaded == state.total
            run.active = false
            ticks:remove(onTick)
        end
        if callbacks.onProgress then
            local ok, err = pcall(callbacks.onProgress, state)
            if not ok then print("[MLOS] Progress callback failed: " .. tostring(err)) end
        end
        if manager.run ~= run then return end
        if state.completed and callbacks.onComplete then
            local ok, err = pcall(callbacks.onComplete, state)
            if not ok then print("[MLOS] Completion callback failed: " .. tostring(err)) end
        end
    end
    run.tick = onTick
    ticks:add(onTick, function(err)
        for _, entry in ipairs(entries) do fail(run.tasks[entry.name], err) end
        run.active = false
        manager.completed = true
        print("[MLOS] Layer lifecycle tick failed: " .. tostring(err))
        local ok, state = pcall(manager.getStatus, manager)
        if ok then
            if callbacks.onProgress then pcall(callbacks.onProgress, state) end
            if manager.run == run and callbacks.onComplete then pcall(callbacks.onComplete, state) end
        end
    end)
    if callbacks.onProgress then
        local ok, err = pcall(callbacks.onProgress, manager:getStatus())
        if not ok then print("[MLOS] Progress callback failed: " .. tostring(err)) end
    end
    return run
end

function LayerRun.stop(run)
    if not run or not run.active then return false end
    run.active = false
    ticks:remove(run.tick)
    return true
end
return LayerRun
