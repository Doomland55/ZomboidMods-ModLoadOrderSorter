local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local cacheFileExists = cacheFileExists


local defaultCategoryOrder = { "coreRequirement", "tweaks", "resource", "map", "vehicle", "code",  "weapon", "clothes",  "items", "ui", "other", "translation", "undefined" }
local defaultCategoryConfig = {
	coreRequirement = {
		priority = 1,
		flags = { "isCoreReq" }
	},
	tweaks = {
		priority = 2,
		tags = { "framework", "qol" },
		flags = { "isTweak" }
	},
	vehicle = {
		priority = 3,
		tags = { "vehicles" },
		flags = { "isVehicle" }
	},
	map = {
		priority = 4,
		tags = { "map" },
		flags = { "isMap" }
	},
	weapon = {
		priority = 5,
		tags = { "military", "weapons" },
		flags = { "isWeapon" }
	},
	clothes = {
		priority = 6,
		tags = { "clothing/armor" },
		flags = { "isClothes" }
	},
	items = {
		priority = 7,
		tags = { "items" },
		flags = { "isItem" }
	},
	ui = {
		priority = 8,
		tags = { "interface" },
		flags = { "isUI" }
	},
	code = {
		priority = 9,
		flags = { "isCode" }
	},
	resource = {
		priority = 10,
		tags = { "textures" },
		flags = { "isResource" }
	},
	other = {
		priority = 11,
		tags = { "silly/fun", "misc" }
	},
	translation = {
		priority = 12,
		tags = { "language/translation" },
		flags = { "isTranslation" }
	}
}

MLOS_CORE = MLOS_CORE or {}
MLOS_CORE.MOD_VERSION = "2.0.0"  -- b42.21.0 Huge refactor
MLOS_CORE.MLOS_ROOT = "ModLoadOrderSorter"

MLOS_CORE.preorder = { ModLoadOrderSorter_b42 = 1, ModManager = 1 }
MLOS_CORE.loadCategories = { on = 0, category = 1, off = 2 }
MLOS_CORE.tweakKeys = MLOS_CORE.tweakKeys or { "framework", " api", "_api", "tweak", "interface", "utilit", "bugfix" } --, "optimize"}

MLOS_CORE.categoryConfig = MLOS_CORE.categoryConfig or defaultCategoryConfig
MLOS_CORE.rawCategoryOrder = MLOS_CORE.rawCategoryOrder or defaultCategoryOrder
MLOS_CORE.categoryOrder = MLOS_CORE.categoryOrder or {}


function MLOS_CORE:initCategoryConfig()
	local filePath = self.MLOS_ROOT .. "/categoriesConfig.txt"

	local function dataToTxt(section, data)
		if section == "#MLOS_CORE" then section = "MLOS_CORE" end
		local text = ""
		if data.categories then text = text .. "categories=" .. table.concat(data.categories, ",") .. "\r\n" end
		if data.priority then text = text .. "priority=" .. data.priority .. "\r\n" end
		if not utils:tableIsEmpty(data.tags) then text = text .. "tags=" .. table.concat(data.tags, ",") .. "\r\n" end
		if not utils:tableIsEmpty(data.flags) then text = text .. "flags=" .. table.concat(data.flags, ",") .. "\r\n" end
		return text ~= "" and "[" .. section .. "]\r\n" .. text or nil
	end

	-- Read file or create default
	if cacheFileExists(filePath) ~= true then
		local saveData = utils:MergeTables({["#MLOS_CORE"] = {categories=MLOS_CORE.rawCategoryOrder}}, MLOS_CORE.categoryConfig)
		self:saveTxtFile(filePath, saveData, dataToTxt)
	else
		local rawData = self:readTxtFile(filePath, function(addTo, line) return self:getDataFromString(line, addTo) end )

		-- Extract category order from [MLOS_CORE] section
        -- Load categories are intentionally fixed; config customises tag mappings only.
        MLOS_CORE.rawCategoryOrder = defaultCategoryOrder

		-- Extract category configs
        rawData = rawData or {}
		rawData.MLOS_CORE = nil
		MLOS_CORE.categoryConfig = rawData
	end

	-- always (re)build the category -> index map
	MLOS_CORE.categoryOrder = {}
	for i, v in ipairs(MLOS_CORE.rawCategoryOrder) do MLOS_CORE.categoryOrder[v] = i end
end


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
	if value == nil then return end
	
	local new_value = nil
	if key == "name" or key == "id" then
		new_value = value
	elseif key == "tags" or key == "flags" then
		new_value = utils:splitStringBySeparator(value)
	elseif key == "priority" then
		new_value = tonumber(value)
	elseif key == "require" then
		new_value = utils:splitStringBySeparator(value)
	elseif key == "loadafter" or key == "loadmodafter" then
		key = "loadAfter"
		new_value = utils:splitStringBySeparator(value)
	elseif key == "loadbefore" or key == "loadmodbefore" then
		key = "loadBefore"
		new_value = utils:splitStringBySeparator(value)
	elseif key == "incompatiblemods" or key == "incompatible" then
		key = "incompatibleMods"
		new_value = utils:splitStringBySeparator(value)
	elseif key == "loadfirst" then
		key = "loadFirst"
		new_value = MLOS_CORE:convertToLoadCategoryString(value)
	elseif key == "loadlast" then
		key = "loadLast"
		new_value = MLOS_CORE:convertToLoadCategoryString(value)
	elseif key == "categories" then
		new_value = utils:splitStringBySeparator(value)
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
function MLOS_CORE:saveTxtFile(filePath, saveData, dataToTxtFunc, sortData)
	if not filePath or not saveData or not dataToTxtFunc then return end

	local file = getFileWriter(filePath, true, false)
    if not file then return false end
	local sectionNames = {}
	for section, _ in pairs(saveData) do
		table.insert(sectionNames, section)
	end

	table.sort(sectionNames, function(a, b) return tostring(a):lower() < tostring(b):lower() end)

	for _, section in ipairs(sectionNames) do
		local data = saveData[section]
		local text = dataToTxtFunc(section, data)
		if text~=nil then file:write(text .."\n") end
	end
	file:close()
    return true
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
	local curSection = nil

	local file = getFileReader(fileName, true)
	if file == nil then return nil end

	local line = file:readLine()
	while line ~= nil do
		
		if not (line:match("^%s*$") or line:match("^%s*[%-%#%/]+")) then -- skip empty or commentlines
		
			local section = utils:fixSlash(string.match(line, '^%s*%[%s*(.-)%s*%]%s*$')) -- detect modname
			if section ~= nil then
				curSection = section
			elseif curSection ~= nil then
				result[curSection] = result[curSection] or {} -- init rule dict for mod
				local curData = result[curSection]
				if txtToDataFunc then
					txtToDataFunc(curData, line)
				else
					table.insert(curData, line)
				end
			else
				table.insert(result, line)
			end

		end
		line = file:readLine()
	end
	file:close()
	return result
end


-- function MLOS_CORE:saveBinaryCache(cacheData)
--     local out = getFileOutput("mlos_cache.bin")
--     if not out then return end

--     -- Считаем количество модов
--     local modCount = 0
--     for _ in pairs(cacheData) do modCount = modCount + 1 end
--     out:writeInt(modCount)

--     for modId, data in pairs(cacheData) do
--         out:writeUTF(modId) -- Записываем ID мода
        
--         local modsList = data.modifications or {}
--         out:writeInt(#modsList) -- Сколько функций он модифицирует

--         for _, item in ipairs(modsList) do
--             out:writeUTF(item.file or "")
--             out:writeUTF(item.className or "")
--             out:writeUTF(item.methodName or "")
--             out:writeBoolean(item.isHook == true) -- хук или жесткий оверрайт
--         end
--     end

--     out:flush()
--     out:close()
--     print("[MLOS] Бинарный кэш успешно записан!")
-- end


-- function MLOS_CORE:loadBinaryCache()
--     local input = getFileInput("mlos_cache.bin")
--     if not input then return nil end

--     local cacheData = {}
--     local modCount = input:readInt() -- Читаем число модов

--     for i = 1, modCount do
--         local modId = input:readUTF()
--         local funcCount = input:readInt()
        
--         cacheData[modId] = { modifications = {} }

--         for j = 1, funcCount do
--             local file = input:readUTF()
--             local className = input:readUTF()
--             local methodName = input:readUTF()
--             local isHook = input:readBoolean()

--             table.insert(cacheData[modId].modifications, {
--                 file = file,
--                 className = className,
--                 methodName = methodName,
--                 isHook = isHook
--             })
--         end
--     end

--     input:close()
--     print("[MLOS] Бинарный кэш мгновенно загружен!")
--     return cacheData
-- end


MLOS_CORE:initCategoryConfig()
return MLOS_CORE