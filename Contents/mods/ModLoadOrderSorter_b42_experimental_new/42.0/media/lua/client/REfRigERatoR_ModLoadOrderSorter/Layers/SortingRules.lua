local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local cacheFileExists = cacheFileExists

local RULES_NAME = "sorting_rules.txt"

local MLOS_SortingRules = {}
MLOS_SortingRules.data = {} -- saved rules by mod ID


---@return table
function MLOS_SortingRules:getData(modsList, reread)
	if not self.loaded or reread == true then
		self.data = self:readSortingRules()
        self.loaded = true
	end
	return self.data
end


function MLOS_SortingRules:beginEdit()
    self:getData()
    self.saved = utils:deepCopy(self.data)
    self.working = utils:deepCopy(self.saved)
    return self.working
end

function MLOS_SortingRules:discardEdit()
    self.working = utils:deepCopy(self.saved or self.data)
    return self.working
end

function MLOS_SortingRules:setPosition(modId, field, value)
    if field ~= "loadFirst" and field ~= "loadLast" then return end
    if value ~= "on" and value ~= "category" then value = "off" end
    self.working = self.working or utils:deepCopy(self.data)
    local rule = self.working[modId] or {}
    self.working[modId] = rule
    rule[field] = value
    if value ~= "off" then rule[field == "loadFirst" and "loadLast" or "loadFirst"] = "off" end
end

function MLOS_SortingRules:commitEdit()
    local working = self.working or self.data
    if not self:saveSortingRules(working) then return false end
    self.data = utils:deepCopy(working)
    self.saved = utils:deepCopy(self.data)
    self.working = utils:deepCopy(self.data)
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
	local rulesFile = core.MLOS_ROOT .. "/" .. (fileName or RULES_NAME)
	print("MLOS - Saving sorting rules: ", rulesFile)
	return core:saveTxtFile(rulesFile, srData or self.data or {}, function(...) return self:getSRDataText(...) end)
end


---@return table rules sorting rules from file
function MLOS_SortingRules:readSortingRules(fileName)
    local rulesName = fileName or RULES_NAME
    local rulesFile = core.MLOS_ROOT .. "/" .. rulesName
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
