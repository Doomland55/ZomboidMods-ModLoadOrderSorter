local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')

if not core then return end

local registeredLayers = {
    {name="modFiles", path = "REfRigERatoR_ModLoadOrderSorter/Layers/1_ModsFiles"},
    {name="modInfo", path = "REfRigERatoR_ModLoadOrderSorter/Layers/2_ModsInfo"},
    {name="sortingRules", path = "REfRigERatoR_ModLoadOrderSorter/Layers/3_SortingRules"},
}

core.layers = core.layers or {}
core.layersManager = core.layersManager or {}

function core.layersManager:getMergedData(modId)
    local layers = core.layers
    local result = {}
    for i=1, #registeredLayers do
        local layer = registeredLayers[i]
        local layerObj = layers[layer.name] or {}
        if layerObj and layerObj.data and layerObj.data[modId] then
            utils:MergeTablesDedup(result, layerObj.data[modId])
        end
    end
    return result
end


function core.layersManager:getValue(modId, valueName)
    return self:getMergedData(modId)[valueName]
end

local function onDone()
    core.layersManager.completed = false
    for i=1, #registeredLayers do
    end
end

function core.layersManager:initialise(modsList)
    local layers = core.layers
    for i=1, #registeredLayers do
        local layer = registeredLayers[i]

        local layerObj = layers[layer.name] or require(layer.path)
        if layerObj and layerObj.getData ~= nil then
            layerObj:getData(modsList, true)
            layers[layer.name] = layerObj
        end
    end

    -- local mergedLayers = {}
    -- for modId, data in pairs()
    -- utils:MergeTablesDedup(mergedLayers, layerObj.data)
    -- core.layers.all = mergedLayers
end

-- Events.OnMainMenuEnter.Add(function() core.layersManager:initialise() end)