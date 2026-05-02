local core = require('OptionScreens/MLOS_core/MLOS_Core')
local utils = require('OptionScreens/MLOS_core/Refr_utils')

local RULES_NAME = "sorting_rules.txt"
local RULES_FILE = core.MLOS_ROOT .. "/" .. RULES_NAME

local MLOS_SortingRules = {}
MLOS_SortingRules.data = {}  -- data from modInfo. data[modId] = {name, desc, category, requirements, loadAfter, ...}


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

-- function MLOS_SortingRules:addSortingRule(modId, loadAfter, loadBefore, incompatibleMods, loadfirst, loadlast, category)
-- 	local file = getFileWriter(RULES_FILE, true, true)
-- 	local text = getSRDataText(modId, loadAfter, loadBefore, incompatibleMods, loadfirst, loadlast, category)
-- 	if text~=nil then file:write(text) end
-- 	file:close()
-- 	self.data = nil
-- end

function MLOS_SortingRules:updateSortingRule(modId, data)
	if utils:tableIsEmpty(self.data) then self:readSortingRules() end

	local rulesFromFile = self.data[modId] or {}
	rulesFromFile.loadAfter = data.loadAfter or rulesFromFile.loadAfter
	rulesFromFile.loadBefore = data.loadBefore or rulesFromFile.loadBefore
	rulesFromFile.incompatibleMods = data.incompatibleMods or rulesFromFile.incompatibleMods
	rulesFromFile.loadFirst = data.loadFirst or rulesFromFile.loadFirst
	rulesFromFile.loadLast = data.loadLast or rulesFromFile.loadLast
	rulesFromFile.category = data.category
	
	self.data[modId] = rulesFromFile
	return self.data
end


---@param srData table|nil optional
---@param name string|nil optional
function MLOS_SortingRules:saveSortingRules(srData, name)
	core:saveTxtFile(name or RULES_FILE, srData or self.data or {}, function(...) return self:getSRDataText(...) end)
end


function MLOS_SortingRules:doRulesBackup()
	local backupname = ("%s/%s_%s.backup"):format(core.MLOS_ROOT, RULES_NAME:sub(1, -5), core.MOD_VERSION)
	if cacheFileExists(backupname) == false then
		self:saveSortingRules(self.data, backupname)
	end
end


---@return table rules sorting rules from file
function MLOS_SortingRules:readSortingRules()
	-- support auto moving sorting rules to the separate mod folder. will be removed after some game versions (initially added for b42.17.0)
	if cacheFileExists(RULES_FILE) == false then  
		if cacheFileExists(RULES_NAME) == false then self:saveSortingRules(); return self.data end
		self.data = core:readTxtFile(RULES_NAME, function(addTo, line) return core:getDataFromString(line, addTo) end )
		self:saveSortingRules(self.data, RULES_FILE)
		self:doRulesBackup()
		return self.data
	end

	self.data = core:readTxtFile(RULES_FILE, function(addTo, line) return core:getDataFromString(line, addTo) end)
	self:doRulesBackup()
	return self.data
end

return MLOS_SortingRules