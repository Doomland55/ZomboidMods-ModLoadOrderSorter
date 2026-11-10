--- Uniform lifecycle for registered layers. Work is scheduled on OnFETick;
--- dependencies are awaited inside layers, not encoded in this manager.
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local LayerRun = require('REfRigERatoR_ModLoadOrderSorter/Layers/LayerRun')
if not core then return end

local registeredLayers = {
    { name = "sortingRules", path = "REfRigERatoR_ModLoadOrderSorter/Layers/SortingRules" },
    { name = "modFiles", path = "REfRigERatoR_ModLoadOrderSorter/Layers/ModsFiles" },
    { name = "modInfo", path = "REfRigERatoR_ModLoadOrderSorter/Layers/ModsInfo" },
}

core.layers = core.layers or {}
core.layersManager = core.layersManager or {}


--- Merged data of all layers for one mod (sorting rules have the highest priority)
---@param modId string
---@return table
function core.layersManager:getMergedData(modId)
	local result = {}
	for i = 1, #registeredLayers do
		local layer = registeredLayers[i]
		local layerObj = core.layers[layer.name]
		if layerObj and layerObj.loaded and layerObj.data and layerObj.data[modId] then
			utils:MergeTablesDedup(result, layerObj.data[modId])
		end
	end
	return result
end


---@param modId string
---@param valueName string
---@return any
function core.layersManager:getValue(modId, valueName)
	return self:getMergedData(modId)[valueName]
end


---@return boolean true when the (possibly async) initialisation finished
function core.layersManager:isCompleted()
	return self.completed == true
end


--- Aggregate warnings supplied by the registered layers and lifecycle errors.
function core.layersManager:getWarnings()
    local warnings = {}
    for _, entry in ipairs(registeredLayers) do
        local layer = core.layers[entry.name]
        if layer and layer.loaded and type(layer.getWarnings) == "function" then
            for _, warning in ipairs(layer:getWarnings() or {}) do warnings[#warnings + 1] = warning end
        end
        if layer and layer.status == "failed" then
            warnings[#warnings + 1] = {
                severity = "CRITICAL", layer = entry.name,
                title = getText("UI_MLOS_Layer_Error_Title"), message = tostring(layer.error or "Unknown error")
            }
        end
    end
    return warnings
end


-- Every layer starts its own work with getData(modsList, context).
-- All registered objects exist in core.layers before any getData is invoked.
local manager = core.layersManager

function manager:registerLayer(name, path)
    assert(not self.run or not self.run.active, "Cannot register a layer while analysis is running")
    assert(type(name) == "string" and type(path) == "string", "A layer needs a name and module path")
    for _, entry in ipairs(registeredLayers) do
        assert(entry.name ~= name, "Duplicate layer: " .. name)
    end
    registeredLayers[#registeredLayers + 1] = { name = name, path = path }
    self.completed = false
end

function manager:isSuccessful()
    local status = self:getStatus()
    return status.completed and status.loaded == status.total
end

function manager:getStatus()
    local result = { total = #registeredLayers, finished = 0, loaded = 0, failed = 0, cancelled = 0, progress = 0, layers = {} }
    for _, entry in ipairs(registeredLayers) do
        local layer = core.layers[entry.name]
        local state = layer and layer.status or "pending"
        local progress = layer and layer.layerProgress or nil
        local item = { name = entry.name, status = state, loaded = layer and layer.loaded == true,
            waitingFor = layer and layer.waitingFor, error = layer and layer.error, progress = progress }
        result.layers[#result.layers + 1] = item
        if state == "loaded" or state == "failed" then
            result.finished = result.finished + 1
            result.progress = result.progress + 1
            if state == "loaded" then result.loaded = result.loaded + 1 else result.failed = result.failed + 1 end
        elseif state == "cancelled" then
            result.cancelled = result.cancelled + 1
        elseif state == "running" and progress and progress.total and progress.total > 0 then
            result.progress = result.progress + math.max(0, math.min(1, progress.current / progress.total))
        end
    end
    result.completed = self.completed == true
    result.success = result.completed and result.loaded == result.total
    return result
end

function manager:cancel()
    local run = self.run
    if not LayerRun.stop(run) then return end
    for _, entry in ipairs(registeredLayers) do
        local layer = core.layers[entry.name]
        if layer and layer.status ~= "loaded" and layer.status ~= "failed" then
            layer.loaded = false
            layer.status = "cancelled"
            layer.waitingFor = nil
        end
        if layer and type(layer.cancel) == "function" then
            local ok, err = pcall(layer.cancel, layer)
            if not ok then print("[MLOS] Failed to cancel layer " .. entry.name .. ": " .. tostring(err)) end
        end
    end
    self.completed = false
end

--- Initialise all layers uniformly; subsequent calls cancel the previous run.
function manager:initialise(modsList, callbacks)
    self:cancel()
    callbacks = callbacks or {}
    self.completed = false
    -- Load all objects first, so layers can find dependencies regardless of order.
    for _, entry in ipairs(registeredLayers) do
        local layer = core.layers[entry.name]
        if not layer or layer._loadFailed then
            local ok, result = pcall(require, entry.path)
            if ok and type(result) == "table" and type(result.getData) == "function" then
                layer = result
            else
                layer = { _loadFailed = true }
                layer.error = ok and "Layer must return a table with getData" or tostring(result)
            end
            core.layers[entry.name] = layer
        end
        layer.loaded = false
        layer.status = layer._loadFailed and "failed" or "pending"
        if not layer._loadFailed then layer.error = nil end
        layer.waitingFor, layer.layerProgress = nil, nil
    end
    self.layers = core.layers
    LayerRun.start(self, registeredLayers, modsList or {}, callbacks)
end
