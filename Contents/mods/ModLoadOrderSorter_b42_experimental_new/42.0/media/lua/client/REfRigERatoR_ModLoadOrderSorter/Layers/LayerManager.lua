--- Layer lifecycle for a single analysis run. Synchronous errors and task
--- failures are recorded per layer; callers may still use available data.
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local CM = require('REfRigERatoR_ModLoadOrderSorter/Core/CorutineManager.lua')
if not core or not CM then return end

local registeredLayers = {
    {name="SortingRules", path="REfRigERatoR_ModLoadOrderSorter/Layers/SortingRules.lua"},
    {name="ModsInfo", path="REfRigERatoR_ModLoadOrderSorter/Layers/ModsInfo.lua"},
    {name="ModsFiles", path="REfRigERatoR_ModLoadOrderSorter/Layers/ModsFiles.lua"},
}

core.layers = core.layers or {}
core.layersManager = core.layersManager or {}
local LayerManager = core.layersManager

local function cancelRun(run)
    if not run or run.completed then return end
    for _, task in ipairs(run.tasks) do
        if not task:isDone() then CM.cancel(task) end
    end
end

local function startLayer(run, spec, modList, reread)
    local state = { name = spec.name }
    run.layers[#run.layers + 1] = state
    local ok, layer = pcall(function() return core.layers[spec.name] or require(spec.path) end)
    if not ok or type(layer) ~= "table" or type(layer.getData) ~= "function" then
        state.error = ok and "Layer is missing getData" or tostring(layer)
        return
    end
    state.layer = layer
    core.layers[spec.name] = layer
    local started, result = pcall(layer.getData, layer, modList, reread)
    if not started then
        state.error = tostring(result)
    elseif CM.isTask(result) then
        state.task = result
        run.tasks[#run.tasks + 1] = result
    end
end

local function completeRun(manager, run, callback)
    if manager.run ~= run then return end
    for _, state in ipairs(run.layers) do
        if state.task and state.task:getStatus() ~= "finished" then
            state.error = tostring(state.task:getError() or state.task:getStatus())
        end
    end
    run.completed = true
    if callback then callback(run) end
end

--- Start all layers. Replacing a run cancels its outstanding tasks, so an old
--- result cannot overwrite the new selection. Unrelated CM tasks are untouched.
function LayerManager:initialise(modList, options)
    options = options or {}
    local previous = self.run
    local run = { layers = {}, tasks = {}, completed = false }
    self.run = run
    cancelRun(previous)
    for _, spec in ipairs(registeredLayers) do
        startLayer(run, spec, modList, options.reread)
    end
    CM.waitFor(run.tasks, function() completeRun(self, run, options.onComplete) end)
    return run
end

function LayerManager:isCompleted()
    return self.run ~= nil and self.run.completed
end

function LayerManager:isSuccessful()
    if not self:isCompleted() then return false end
    for _, state in ipairs(self.run.layers) do
        if state.error then return false end
    end
    return true
end

local function errorWarning(name, err)
    return {
        severity = "CRITICAL", layer = name,
        title = getText("UI_MLOS_Layer_Error_Title"),
        message = getText("UI_MLOS_Layer_Error_Msg", name, tostring(err)),
    }
end

--- Errors refer to this run; successful layers can additionally report their
--- own warnings. A failed warning provider must not break the entire panel.
function LayerManager:getWarnings()
    local warnings = {}
    if not self:isCompleted() then return warnings end
    for _, state in ipairs(self.run.layers) do
        if state.error then
            warnings[#warnings + 1] = errorWarning(state.name, state.error)
        elseif state.layer and type(state.layer.getWarnings) == "function" then
            local ok, items = pcall(state.layer.getWarnings, state.layer)
            if ok and type(items) == "table" then
                for _, warning in ipairs(items) do warnings[#warnings + 1] = warning end
            elseif not ok then
                warnings[#warnings + 1] = errorWarning(state.name, items)
            end
        end
    end
    return warnings
end

return LayerManager
