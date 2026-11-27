--- Layer lifecycle: register layers and launch their getData tasks through
--- CoroutineManager. The completion callback runs after queued tasks finish.
---
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local CM = require("REfRigERatoR_ModLoadOrderSorter/Core/CorutineManager.lua")
if not core or not CM then return end

local registeredLayers = {
    {name="SortingRules", path="REfRigERatoR_ModLoadOrderSorter/Layers/SortingRules.lua"},
    {name="ModsInfo", path="REfRigERatoR_ModLoadOrderSorter/Layers/ModsInfo.lua"},
    {name="ModsFiles", path="REfRigERatoR_ModLoadOrderSorter/Layers/ModsFiles.lua"},
}

core.layers = core.layers or {}
core.layersManager = core.layersManager or {}

local LayerManager = core.layersManager


function LayerManager:initialise(modList, options)
    options = options or {}

    for i=1, #registeredLayers do
        local layerData = registeredLayers[i]
        local layerObject = core.layers[layerData.name] or require(layerData.path)
        if layerData.name and layerData.path and layerObject and layerObject.getData then
            layerObject:getData(modList, options.reread)
            core.layers[layerData.name] = layerObject
        end
    end

    CM.waitAll(options.onComplete)
end


return LayerManager
