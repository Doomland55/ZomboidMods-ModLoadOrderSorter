local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local CM = require("REfRigERatoR_ModLoadOrderSorter/Core/CorutineManager.lua")
local cacheFileExists = cacheFileExists

local RULES_NAME = "sorting_rules.txt"

local MLOS_SortingRules = {}
MLOS_SortingRules.data = {} -- saved rules by mod ID



-- The rules file is read once per Lua session unless a reread is requested.
function MLOS_SortingRules:getData(_, reread)
    self:onStart()
    if utils:tableIsEmpty(self.data) or reread == true then
        self.data = self:readSortingRules()
    end
    self:onFinish()
    return self.data
end

function MLOS_SortingRules:onStart() CM:setProgress(0, "[SortingRules] processing ...") end
function MLOS_SortingRules:onFinish() CM:setProgress(1, "[SortingRules] finished") end



function MLOS_SortingRules:beginEdit()
    self:getData()
    return utils:deepCopy(self.data)
end

function MLOS_SortingRules:commitEdit(newData)
    if not self:saveSortingRules(newData) then return false end
    self.data = newData
    return true
end



---@return string | nil
function MLOS_SortingRules:getSRDataText(modId, data)
	local saveData = data or self.data[modId]
	local text = ""
	if not utils:tableIsEmpty(saveData.loadAfter) then text = text .. "loadAfter=" .. table.concat(saveData.loadAfter, ",") .. "\r\n" end
	if not utils:tableIsEmpty(saveData.loadBefore) then text = text .. "loadBefore=" .. table.concat(saveData.loadBefore, ",") .. "\r\n" end
	if not utils:tableIsEmpty(saveData.incompatibleMods) then text = text .. "incompatibleMods=" .. table.concat(saveData.incompatibleMods, ",") .. "\r\n" end
	if saveData.loadFirst ~= nil and saveData.loadFirst ~= 'off' then text = text .. "loadFirst=" .. saveData.loadFirst .. "\r\n" end
	if saveData.loadLast ~= nil and saveData.loadLast ~= 'off' then text = text .. "loadLast=" .. saveData.loadLast .. "\r\n" end
	if saveData.category ~= nil then text = text .. "category=" .. saveData.category .. "\r\n" end
	return text ~= "" and "[" .. modId .. "]\r\n" .. text or nil
end


---@param srData table|nil optional
---@param fileName string|nil optional
function MLOS_SortingRules:saveSortingRules(srData, fileName)
	local rulesFile = utils:joinpath(core.MLOS_LAYERS_ROOT, fileName or RULES_NAME)
	print("MLOS - Saving sorting rules: ", rulesFile)
	return core:saveTxtFile(rulesFile, srData or self.data or {}, function(...) return self:getSRDataText(...) end)
end


---@return table rules sorting rules from file
function MLOS_SortingRules:readSortingRules(fileName)
    local rulesName = fileName or RULES_NAME
    local rulesFile = utils:joinpath(core.MLOS_LAYERS_ROOT, rulesName)
    print("MLOS - Reading sorting rules: ", rulesFile)
    -- Migrate the legacy file once without prepending the root twice.
    if cacheFileExists(rulesFile) ~= true then
        if cacheFileExists(rulesName) == false then self:saveSortingRules(); return self.data or {} end
        local old = core:readTxtFile(rulesName, function(addTo, line) core:getDataFromString(line, addTo) end) or {}
        self:saveSortingRules(old)
        return old
    end
    return core:readTxtFile(rulesFile, function(addTo, line) core:getDataFromString(line, addTo) end) or {}
end


return MLOS_SortingRules
