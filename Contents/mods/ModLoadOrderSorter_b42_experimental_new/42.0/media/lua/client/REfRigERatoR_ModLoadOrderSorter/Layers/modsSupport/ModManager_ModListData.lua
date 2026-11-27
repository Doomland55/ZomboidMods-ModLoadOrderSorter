--- Compatibility with category data from Duncan E.'s "Mod Manager" mod (Workshop ID: 3567084868; Mod ID: ModManager)
--- https://steamcommunity.com/sharedfiles/filedetails/?id=3567084868
---
--- Draft: this layer is not registered. To enable it, add to LayerManager.lua:
---   local modManager = require('REfRigERatoR_ModLoadOrderSorter/Layers/modsSupport/ModManager_ModListData')
---   if modManager then manager:registerLayer("modManager", modManager) end

local ModListData = require("ModManager/Utils/ModListData")
if ModListData == nil then return end

local ModManagerLayer = {}
ModManagerLayer.data = {} -- data[modId] = { category = ... }


--- Layer entry point, see LayerManager.
function ModManagerLayer:load(modList)
    local data = {}
    -- for i, row in ipairs(modList) do
    --     data[row.item.modId] = { ... read from ModListData ... }
    --     -- Report progress using CoroutineManager when implemented.
    -- end
    self.data = data
end


function ModManagerLayer:onStart()
    return nil
end


function ModManagerLayer:onProcess()
    return nil
end


function ModManagerLayer:onFinish()
    return nil
end


return ModManagerLayer
