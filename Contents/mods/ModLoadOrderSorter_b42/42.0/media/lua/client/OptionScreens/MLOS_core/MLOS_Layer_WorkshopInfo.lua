local utils = require('OptionScreens/MLOS_core/Refr_utils')
local core = require('OptionScreens/MLOS_core/MLOS_Core')

local MLOS_WorkshopInfo = {}
MLOS_WorkshopInfo.data = {} -- data from Workshop. data[modId] = {name, desc, category, requirements, loadAfter, ...}


function MLOS_WorkshopInfo:load()
end

function MLOS_WorkshopInfo:save()
end

function MLOS_WorkshopInfo.getWorkshopData()
	print("MLOS_getWorkshopData")
end


-- Events.OnMainMenuEnter.Add(MLOS_WorkshopInfo.getWorkshopData)

return MLOS_WorkshopInfo
