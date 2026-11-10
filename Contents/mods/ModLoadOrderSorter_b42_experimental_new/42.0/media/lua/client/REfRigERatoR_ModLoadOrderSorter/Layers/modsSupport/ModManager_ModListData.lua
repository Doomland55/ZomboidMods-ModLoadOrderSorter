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
function ModManagerLayer:load(ctx)
    local data = {}
    -- for i, row in ipairs(ctx.mods) do
    --     data[row.item.modId] = { ... read from ModListData ... }
    --     ctx:step(i, #ctx.mods)
    -- end
    self.data = data
end


return ModManagerLayer
