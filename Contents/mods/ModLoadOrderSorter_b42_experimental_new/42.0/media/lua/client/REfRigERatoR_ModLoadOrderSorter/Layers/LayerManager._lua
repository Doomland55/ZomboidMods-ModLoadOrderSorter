---
--- Layer lifecycle.
---
--- A layer is a table with `load(self, ctx)`. The manager runs `load` inside a
--- coroutine on Events.OnFETick, one layer after another in registration order,
--- so a layer may read `core.layers.<name>.data` of every layer registered
--- before it. Returning from `load` means "ready", raising an error means
--- "failed". Inside `load`:
---   ctx.mods    - snapshot of modList.items the analysis was started for
---   ctx.reread  - true when cached data must be read again
---   ctx:step(current, total) - report progress; yields when the frame budget is spent
---   ctx:wait()  - yield until the next frame (waiting for an external result)
--- step/wait must not be called inside pcall: a yield cannot cross it.
---
--- Optional layer methods: `getWarnings()` (list of { severity, layer, title,
--- message }) and `cancel()` (release external resources when the layer is
--- interrupted or fails).
---
local root = 'REfRigERatoR_ModLoadOrderSorter/'
local core = require(root .. 'Core/Core')
if not core then return end

local FRAME_BUDGET_MS = 8 -- time the layers may use per front-end tick

core.layers = core.layers or {}
core.layersManager = core.layersManager or {}
local manager = core.layersManager
manager.names = manager.names or {} -- registration order


local function notify(callback, status)
    if not callback then return end
    local ok, err = pcall(callback, status)
    if not ok then print("[MLOS] Layer callback failed: " .. tostring(err)) end
end

local function release(layer, name)
    if type(layer.cancel) ~= "function" then return end
    local ok, err = pcall(layer.cancel, layer)
    if not ok then print("[MLOS] Failed to cancel layer " .. name .. ": " .. tostring(err)) end
end


---@param name string key in core.layers
---@param layer table module with load(self, ctx)
function manager:registerLayer(name, layer)
    assert(type(name) == "string", "A layer needs a name")
    self:cancel()
    if type(layer) ~= "table" or type(layer.load) ~= "function" then
        -- Keep the other layers usable and report the broken one through the normal failure path.
        layer = { data = {}, load = function() error("Layer '" .. name .. "' must be a table with load(ctx)", 0) end }
    end
    local known = false
    for _, existing in ipairs(self.names) do known = known or existing == name end
    if not known then self.names[#self.names + 1] = name end -- re-registering replaces the layer in place
    core.layers[name] = layer
    self.run = nil
end


--- Stops the current analysis. Its coroutines are simply never resumed again,
--- so late external callbacks of the old run cannot affect a new one.
function manager:cancel()
    local run = self.run
    if not run or run.completed or run.cancelled then return end
    run.cancelled = true
    Events.OnFETick.Remove(run.tick)
    for _, state in ipairs(run.states) do
        if state.status == "running" then release(core.layers[state.name], state.name) end
    end
end


--- Starts the analysis of all layers; a previous unfinished run is cancelled.
---@param modsList table modList.items
---@param options table|nil { reread = bool, onProgress = func(status), onComplete = func(status) }
function manager:initialise(modsList, options)
    self:cancel()
    options = options or {}
    local mods = {}
    for i, row in ipairs(modsList or {}) do mods[i] = row end

    local run = { states = {}, index = 1 }
    self.run = run
    for i, name in ipairs(self.names) do
        local layer = core.layers[name]
        local state = { name = name, status = "pending", progress = { current = 0, total = 0 } }
        local ctx = { mods = mods, reread = options.reread == true }
        function ctx:wait() coroutine.yield() end
        function ctx:step(current, total)
            if current then state.progress.current = current end
            if total then state.progress.total = total end
            if getTimestampMs() >= run.deadline then coroutine.yield() end
        end
        state.worker = coroutine.create(function() layer:load(ctx) end)
        run.states[i] = state
    end

    function run.tick()
        if self.run ~= run or run.cancelled or run.completed then return end
        run.deadline = getTimestampMs() + FRAME_BUDGET_MS
        local state = run.states[run.index]
        while state do
            state.status = "running"
            local ok, err = coroutine.resume(state.worker)
            if ok and coroutine.status(state.worker) ~= "dead" then break end -- yielded: continue on the next tick
            if ok then
                state.status = "loaded"
            else
                state.status, state.error = "failed", tostring(err)
                print("[MLOS] Layer " .. state.name .. " failed: " .. state.error)
                release(core.layers[state.name], state.name)
            end
            run.index = run.index + 1
            state = run.states[run.index]
            if getTimestampMs() >= run.deadline then break end
        end
        if not state then
            run.completed = true
            Events.OnFETick.Remove(run.tick)
        end
        local status = self:getStatus()
        notify(options.onProgress, status)
        if run.completed and self.run == run then notify(options.onComplete, status) end
    end

    Events.OnFETick.Add(run.tick)
    notify(options.onProgress, self:getStatus())
end


--- Snapshot of the analysis for the UI.
---@return table { total, finished, failed, progress, completed, success, layers = { { name, status, error, progress } } }
function manager:getStatus()
    local run = self.run
    local result = { total = #self.names, finished = 0, failed = 0, progress = 0, layers = {} }
    for i, name in ipairs(self.names) do
        local state = run and run.states[i] or { name = name, status = "pending", progress = { current = 0, total = 0 } }
        result.layers[i] = { name = name, status = state.status, error = state.error, progress = state.progress }
        if state.status == "loaded" or state.status == "failed" then
            result.finished = result.finished + 1
            result.progress = result.progress + 1
            if state.status == "failed" then result.failed = result.failed + 1 end
        elseif state.progress.total > 0 then
            result.progress = result.progress + math.max(0, math.min(1, state.progress.current / state.progress.total))
        end
    end
    result.completed = run ~= nil and run.completed == true
    result.success = result.completed and result.failed == 0
    return result
end

---@return boolean true when every layer finished, successfully or not
function manager:isCompleted() return self:getStatus().completed end

---@return boolean true when every layer finished without an error
function manager:isSuccessful() return self:getStatus().success end


--- Warnings of the loaded layers plus one critical entry per failed layer.
function manager:getWarnings()
    local warnings = {}
    for _, state in ipairs(self:getStatus().layers) do
        local layer = core.layers[state.name]
        if state.status == "loaded" and type(layer.getWarnings) == "function" then
            for _, warning in ipairs(layer:getWarnings() or {}) do warnings[#warnings + 1] = warning end
        elseif state.status == "failed" then
            warnings[#warnings + 1] = {
                severity = "CRITICAL", layer = state.name,
                title = getText("UI_MLOS_Layer_Error_Title"), message = tostring(state.error or "Unknown error")
            }
        end
    end
    return warnings
end


manager:registerLayer("sortingRules", require(root .. 'Layers/SortingRules'))
manager:registerLayer("modInfo", require(root .. 'Layers/ModsInfo'))
manager:registerLayer("modFiles", require(root .. 'Layers/ModsFiles'))

return manager
