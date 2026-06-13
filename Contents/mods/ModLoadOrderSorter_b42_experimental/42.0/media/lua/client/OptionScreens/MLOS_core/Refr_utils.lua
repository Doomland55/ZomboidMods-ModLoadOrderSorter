---
---	Сlass with functions that I use in my mods
---
--- Author: REfRigERatoR
--- Profile: https://steamcommunity.com/profiles/76561198108707962/
---

require('luautils')

local table = table; local pairs = pairs; local ipairs = ipairs; local type = type; local string = string
local tostring = tostring; local fileExists = fileExists; local getFileSeparator = getFileSeparator; local listFilesInModDirectory = listFilesInModDirectory

local ZomboidVersionStr = getGameVersion()
local ZomboidVersionNum = tonumber(string.match(ZomboidVersionStr, "(%d+%.%d+).*"))
local Refr_Utils = {}



function Refr_Utils:clamp(value, min, max)
	if min > max then min, max = max, min end
	return (value < min and min) or (value > max and max) or value
end

function Refr_Utils:fixSlash(value)
	if type(value) == "string" then
		return value:gsub("^\\?", ZomboidVersionNum < 42.15 and "\\" or "")
	end

	if type(value) == "table" then
		for i, val in ipairs(value) do
			value[i] = self:fixSlash(val)
		end
	end
	return value
end

function Refr_Utils:contains(_table, val)
	if val == nil or val == "" then return false end
	for i = 1, #_table do
		if _table[i] == val then
			return true
		end
	end
	return false
end

function Refr_Utils:containsAnyTag(tagsTable, findTags, caseInsesitive)
	for _, val in ipairs(findTags) do
		val = caseInsesitive and val:lower() or val
		for _, tag in ipairs(tagsTable) do
			tag = caseInsesitive and tag:lower() or tag
			if tag == val then
				return true
			end
		end
	end
	return false
end

function Refr_Utils:getString(value, intend, columns)
	if type(value) ~= "table" then return (value and value ~= "off" and tostring(value) or "") end

	local result = table.concat(value, ', ')
	if result ~= "" then return "{ " .. result .. " }" end

	if intend == nil then intend = 0 end
	for k, v in pairs(value) do
		if columns == nil or self:contains(columns, k) then
			local vstr = Refr_Utils:getString(v, intend + 1, columns)
			if vstr ~= "" then
				result = result .. "\n" .. string.rep("  ", intend) .. k .. ": " .. vstr
			end
		end
	end
	return result
end

function Refr_Utils:isExists(modDir, path)
	if type(path) ~= "table" then
		path = { path }
	end

	for _, p in pairs(path) do
		if not fileExists(modDir .. string.gsub(p, "/", getFileSeparator())) then
			return false
		end
	end
	return true
end


local function _mergeTables(result, skip_duplicates, ...)
	local tables = {_n = select("#", ...), ...}
	if tables._n < 1 then return result end

	for i = 1, tables._n do
		-- merge "from" table to "result". add values if list, update if dict and paste if missing
		for k, v in pairs(tables[i] or {}) do
			if type(k) == "number" then
				if skip_duplicates == false or not Refr_Utils:contains(result, v) then
					table.insert(result, v)
				end
			elseif type(k) == "string" then
				if type(v) == "table" then
					result[k] = result[k] or {}
					result[k] = _mergeTables(result[k], skip_duplicates, v)
				else
					result[k] = v
				end
			end
		end
	end
	return result
end


function Refr_Utils:MergeTables(result, ...) return _mergeTables(result, false, ...) end

function Refr_Utils:MergeTablesDedup(result, ...) return _mergeTables(result, true, ...) end

function Refr_Utils:splitStringBySeparator(input_str, separator)
	local result = {}
	local pattern = string.format("([^%s]+)", separator or ",;")
	local fixed_equals = input_str:gsub("%w+%s*=", "")
	fixed_equals:gsub(pattern, function(c) result[#result + 1] = luautils.trim(c) end)
	return result
end

function Refr_Utils:strContainsAny(str, val)
	if type(val) == "table" then
		for _, v in ipairs(val) do
			if self:strContainsAny(str, v) then
				return true
			end
		end
		return false
	end
	return (str ~= nil and val ~= "" and string.find(string.lower(str), val)) and true or false
end

function Refr_Utils:tableIsEmpty(tbl)
	if tbl == nil then return true end
	for _, _ in pairs(tbl) do
		return false
	end
	return true
end

function Refr_Utils:tableDifference(table1, table2)
	-- returns elements that are in table1 but not in table2
	local set1 = {}; for _, value in ipairs(table1) do set1[value] = true end
	local set2 = {}; for _, value in ipairs(table2) do set2[value] = true end

	local difference = {}
	for _, value in ipairs(table1) do
		if not set2[value] then table.insert(difference, value) end
	end
	for _, value in ipairs(table2) do
		if not set1[value] then table.insert(difference, value) end
	end
	return difference
end

function Refr_Utils:getElementIndex(tbl, value)
	for i, v in ipairs(tbl) do
		if v == value then return i end
	end
	return nil
end

function Refr_Utils:toKahluaTable(array)
	local result = {}
	if array ~= nil then
		for j = 0, array:size() - 1 do
			local data = array:get(j)
			if type(data) == "string" then
				data = luautils.trim(data)
			end
			table.insert(result, data)
		end
	end
	return result
end

function Refr_Utils:getWorkshopId(modInfo)
	if modInfo == nil then return nil end
	local workshopId = modInfo:getWorkshopID()
	if not workshopId or workshopId == "" then
		local dir = modInfo:getDir()
		return dir:match("108600\\(%d+)\\")
	end
	return workshopId
end

-- TODO посмотреть, может и не нужна эта функция. есть внутренняя функция для получения всех воркшоп айди + можнно получать из кеша (но для этого кеш должен быть прогружен)
function Refr_Utils:getModsIDs(activeModsItems)
	local modIDs = {}
	local workshopIDs = {}
	for _, item in ipairs(activeModsItems) do
		local workshopId = self:getWorkshopId(item.item.modInfo)
		local itemId = item.item.modID or item.item.modId or ""
		if workshopId and workshopId ~= "" then -- itemId ~= "ModLoadOrderSorter_b42_experimental" and 
			table.insert(modIDs, itemId)
			self:MergeTablesDedup(workshopIDs, { workshopId })
		else
			pcall(
			function(modId) error("\n[MLOS] Mod " ..
				modId ..
				" not found. Subscribe to the missing mod or save changes to the server configuration (missing mods will be removed from the mod list).") end,
				itemId)
		end
	end
	return modIDs, workshopIDs
end

function Refr_Utils:tprint(tbl, indent)
	-- used for debugging
	if not indent then indent = 0 end
	if type(tbl) ~= "table" then
		print(tostring(tbl)); return;
	end
	for k, v in pairs(tbl) do
		local formatting = string.rep("  ", indent) .. k .. ": "
		if type(v) == "table" then
			print(formatting)
			self:tprint(v, indent + 1)
		else
			print(formatting .. tostring(v))
		end
	end
end

--- Returns a dirname and filename from a given path
--- @param path string 
--- @return string dirname, string filename
function Refr_Utils:splitPath(path)
    path = path:gsub("[/\\]+$", "") -- remove slashes from the end
    if path == "" then return "", ""  end

    local basename = path:match("[^/\\]+$")

    if basename and basename:match("%.") then
        local dirname = path:sub(1, #path - #basename - 1)
        dirname = dirname:gsub("[/\\]+$", "")
        return dirname, basename
    else
        return path, ""
    end
end


-- function Refr_Utils:isPathExistsInMod(modId, pattern)
-- 	local modInfo = getModInfoByID(modId)
-- 	local directory, filename = self:splitPath(pattern)
-- 	if directory ~= "" then
-- 		if fileExists(modDir .. string.gsub(directory, "/", getFileSeparator())) then
-- 			if filename == "" then return true end
			
-- 			local files = listFilesInModDirectory(modId, directory)

-- 		end
-- 	end
-- 	return false
-- end

--- Проверяет соответствует ли имя файла паттерну вида "*[item|recipe]*.txt"
--- @param filename string имя файла
--- @param pattern string паттерн, например "*[item|recipe]*.txt" или "*item*.txt"
--- @return boolean
function Refr_Utils:filenameMatchesPattern(filename, pattern)
	-- Извлекаем расширение файла (например ".txt")
	local extension = pattern:match("(%.[^.]+)$")
	if extension then
		-- Проверяем расширение
		if not filename:find(extension .. "$") then
			return false
		end
		-- Удаляем расширение из паттерна для дальнейших проверок
		pattern = pattern:sub(1, -(#extension + 1))
	end
	
	-- Ищем [option1|option2|...] в паттерне
	local options_str = pattern:match("%[([^%]]+)%]")
	if options_str then
		-- Есть список вариантов - проверяем, содержится ли хоть один
		local found = false
		for option in options_str:gmatch("[^|]+") do
			option = option:match("^%s*(.-)%s*$") -- trim
			if option ~= "" and filename:find(option, 1, true) then
				found = true
				break
			end
		end
		if not found then return false end
		-- Удаляем [option1|option2] из паттерна
		pattern = pattern:gsub("%[[^%]]*%]", "")
	end
	
	-- Оставшиеся звёздочки просто игнорируем (они означают "любые символы")
	-- Проверяем остальные части паттерна (без *)
	pattern = pattern:gsub("%*", "")
	if pattern ~= "" and not filename:find(pattern, 1, true) then
		return false
	end
	
	return true
end


function Refr_Utils:doesModHaveFile(files, filename_pattern)
	-- Проверяем каждый файл по паттерну
	for _, file in ipairs(files) do
		-- Берём только имя файла (без пути)
		local file_basename = file:match("([^\\/]+)$") or file
		if self:filenameMatchesPattern(file_basename:lower(), filename_pattern:lower()) then
			return true
		end
	end
	return false
end

-- --- Проверяет, есть ли в директории файл, соответствующий паттерну
-- --- @param modDir string корневая директория мода
-- --- @param pathPattern string путь с паттерном, например "/scripts/*[item|recipe]*.txt"
-- --- @return boolean
-- function Refr_Utils:doesModHaveFileMatching(modDir, pathPattern)
-- 	-- Разделяем путь на директорию и имя файла
-- 	local lastSlash = pathPattern:match("^(.*/)")
-- 	local filename_pattern = pathPattern:match("[^/\\]+$")
-- 	if not filename_pattern then return false end
-- 	if not filename_pattern:find("%.", 1, true) then  return false end -- if filename_pattern is not a file (doesn't contain .) then return false

-- 	if not lastSlash then lastSlash = "" end
	
-- 	-- Проверяем существует ли директория
-- 	if lastSlash ~= "" then
-- 		local dir_check = lastSlash:sub(1, -2) -- убираем последний /
-- 		if not self:isExists(modDir, dir_check) then
-- 			return false
-- 		end
-- 	end
	
-- 	-- Получаем список файлов в директории
-- 	local directory = modDir .. string.gsub(lastSlash, "/", getFileSeparator())
-- 	local files = listFilesInModDirectory(directory)
	
-- 	if type(files) ~= "table" then
-- 		return false
-- 	end
	
-- 	-- Проверяем каждый файл по паттерну
-- 	for _, file in ipairs(files) do
-- 		-- Берём только имя файла (без пути)
-- 		local file_basename = file:match("([^\\/]+)$") or file
-- 		if self:filenameMatchesPattern(file_basename, filename_pattern) then
-- 			return true
-- 		end
-- 	end
	
-- 	return false
-- end

return Refr_Utils
