--- Compatibility with category data from Duncan E.'s "Mod Manager" mod (Workshop ID: 3567084868; Mod ID: ModManager)
--- https://steamcommunity.com/sharedfiles/filedetails/?id=3567084868

local ModListData = require("ModManager/Utils/ModListData")
if ModListData == nil then return end

local ModManagerLayer = {}
ModManagerLayer.data = {}


function ModManagerLayer:getData(modList)
    return self.data
end


function ModManagerLayer:onDone()
    self.completed = true
    return true
end


return ModManagerLayer

