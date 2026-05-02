local utils = require('OptionScreens/MLOS_core/Refr_utils')

local MLOS_CORE = {}
MLOS_CORE.MOD_VERSION = "2.0.0"  -- b42.17.0 Huge refactor
MLOS_CORE.MLOS_ROOT = "ModLoadOrderSorter"

MLOS_CORE.preorder = { ModLoadOrderSorter_b42 = 1, ModManager = 1 }
MLOS_CORE.rawCategoryOrder = { "coreRequirement", "tweaks", "resource", "map", "vehicle", "code", "clothes", "ui", "other",	"translation", "undefined" }
MLOS_CORE.categoryOrder = {}; for i, v in ipairs(MLOS_CORE.rawCategoryOrder) do MLOS_CORE.categoryOrder[v] = i end
MLOS_CORE.loadCategories = { on = 0, category = 1, off = 2 }
MLOS_CORE.tweakKeys = { "framework", " api", "_api", "tweak", "interface", "utilit", "bugfix" } --, "optimize"}
MLOS_CORE.workshopTagsMapping = {
	tweaks = {"framework", "qol"},
	resource = {"textures"},
	map =  {"map"},
	vehicle = {"vehicles"},
	clothes = {"clothing/armor"},
	ui = {"interface"},
	other = {"silly/fun", "misc"},
	translation = {"language/translation"}
}


---@param value string|number|boolean|nil
---@return string
function MLOS_CORE:convertToLoadCategoryString(value)
	if utils:contains({true, "true", 0}, value) then value = "on"
	elseif utils:contains({nil, false, "false", 2}, value) or MLOS_CORE.loadCategories[value] == nil then value = "off" end
	return tostring(value)
end


---@param line string
---@param addTo table optional table to read value
---@returns string table|string
function MLOS_CORE:getDataFromString(line, addTo)
	local key, value = string.match(line, '^%s*(.-)%s*=%s*(.-)%s*$') -- split line by '=' and trim
	key, value = string.lower(key or ""), value or ""          -- replace nil with empty string
	
	local new_value = nil
	if key == "name" or key == "id" then
		new_value = value
	elseif key == "tags" then
		new_value = utils:splitStringBySeparator(value)
	elseif key == "require" then
		new_value = utils:splitStringBySeparator(value)
	elseif key == "loadafter" or key == "loadmodafter" then
		key = "loadAfter"
		new_value = utils:splitStringBySeparator(value)
	elseif key == "loadbefore" or key == "loadmodbefore" then
		key = "loadBefore"
		new_value = utils:splitStringBySeparator(value)
	elseif key == "incompatiblemods" then
		key = "incompatibleMods"
		new_value = utils:splitStringBySeparator(value)
	elseif key == "loadfirst" then
		key = "loadFirst"
		new_value = MLOS_CORE:convertToLoadCategoryString(value)
	elseif key == "loadlast" then
		key = "loadLast"
		new_value = MLOS_CORE:convertToLoadCategoryString(value)
	elseif key == "category" then
		new_value = utils:splitStringBySeparator(value)
		if #new_value > 1 then
			key = "tags"
		else
			new_value = new_value[1]
		end
	end

	if addTo ~= nil then
		if type(new_value) == "table" then
			addTo[key] = utils:fixSlash(utils:MergeTablesDedup(addTo[key] or {}, new_value))
		elseif new_value ~= nil then
			addTo[key] = new_value
		end
		return
	end

	return key, new_value
end

-- Saves data (sorted by name) to the file in format: 
-- [Data Name]
-- <data filed 1>=<data value/s>
-- [Data Name 2]
-- <data filed 2>=<data value/s>
-- ...
---@param filePath string file path
---@param saveData table data to save
---@param dataToTxtFunc any function to convert data to string. shoud have two args (<dataName>, <dataTable>)
function MLOS_CORE:saveTxtFile(filePath, saveData, dataToTxtFunc)
	if not filePath or not saveData or not dataToTxtFunc then return end

	local file = getFileWriter(filePath, true, false)
	local modIds = {}
	for modId, _ in pairs(saveData) do
		table.insert(modIds, modId)
	end
	table.sort(modIds, function(a, b) return tostring(a):lower() < tostring(b):lower() end)

	for _, modId in ipairs(modIds) do
		local data = saveData[modId]
		local text = dataToTxtFunc(modId, data)
		if text~=nil then file:write(text) end
	end
	file:close()
end

-- Reads the file that contains data in format: 
-- [Data Name]
-- <data filed 1>=<data value/s>
-- [Data Name 2]
-- <data filed 2>=<data value/s>
-- ...
---@param fileName string name of file to read
---@param txtToDataFunc any function to convert line to data. should have two args (dataTable, line)
---@return table|nil rules dataTable in format: {dataName1 = {dataField1=dataValue1, ... }, ... }
function MLOS_CORE:readTxtFile(fileName, txtToDataFunc)
	local result = {}
	local curmodname = nil

	local file = getFileReader(fileName, true)
	if file == nil then return nil end

	local line = file:readLine()
	while line ~= nil do
		local modname = utils:fixSlash(string.match(line, '^%s*%[%s*(.-)%s*%]%s*$')) -- detect modname
		if modname ~= nil then
			curmodname = modname
		elseif curmodname ~= nil then
			result[curmodname] = result[curmodname] or {} -- init rule dict for mod
			local currule = result[curmodname]
			if txtToDataFunc then
				txtToDataFunc(currule, line)
			else
				table.insert(currule, line)
			end
		end
		line = file:readLine()
	end
	file:close()
	return result
end

return MLOS_CORE