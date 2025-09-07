---
---	This mod updates the behavior of automatic sorting, added to the Project Zomboid build 42.0. 
--- Adds own topological sorting algorithm for mods load order, 
--- and adds support for sorting rules from the file sorting_rules.txt.
---
--- Details about this mod:
--- Mod: Mod Load Order Sorter
--- Author: REfRigERatoR
--- Profile: https://steamcommunity.com/profiles/76561198108707962/
---
--- This mod has no dependencies
---
local utils = require('OptionScreens/ModSelector/Refr_utils')

local RULES_FILE = "sorting_rules.txt"

local preorder = { ModManager = 1, ModManagerServer = 2, modoptions = 3 }
local rawCategoryOrder = { "coreRequirement", "resource", "map", "vehicle", "tweaks", "code", "clothes", "ui", "other",	"translation", "undefined" }
local categoryOrder = {}; for i, v in ipairs(rawCategoryOrder) do categoryOrder[v] = i end
local loadCategories = { on = 0, category = 1, off = 2 }


local ModSorter = {}
ModSorter.modsInfoCache = {}

function ModSorter:getRawCategoryOrder() return rawCategoryOrder end
function ModSorter:getLoadCategories() return loadCategories end

-- \/ ================================== SORTING RULES ================================== \/

local function convertToLoadCategory(value)
	if utils:contains({nil, false, "false", 2}, value) then value = "off"
	elseif utils:contains({true, "true", 0}, value) then value = "on" end
	return loadCategories[value] or 0
end

local function getSRDataText(modId, loadAfter, loadBefore, incompatibleMods, loadfirst, loadlast)
	local text = ""
	if not utils:tableIsEmpty(loadAfter) then text = text .. "loadAfter=" .. table.concat(loadAfter, ",") .. "\r\n" end
	if not utils:tableIsEmpty(loadBefore) then text = text .. "loadBefore=" .. table.concat(loadBefore, ",") .. "\r\n" end
	if not utils:tableIsEmpty(incompatibleMods) then text = text .. "incompatibleMods=" .. table.concat(incompatibleMods, ",") .. "\r\n" end
	if loadfirst ~= nil and loadfirst ~= 'off' then text = text .. "loadFirst=" .. loadfirst .. "\r\n" end
	if loadlast ~= nil and loadlast ~= 'off' then text = text .. "loadLast=" .. loadlast .. "\r\n" end
	return text ~= "" and "[" .. modId .. "]\r\n" .. text or nil
end

function ModSorter:addSortingRule(modId, loadAfter, loadBefore, incompatibleMods, loadfirst, loadlast)
	local file = getFileWriter(RULES_FILE, true, true)
	local text = getSRDataText(modId, loadAfter, loadBefore, incompatibleMods, loadfirst, loadlast)
	if text~=nil then file:write(text) end
	file:close()
end

function ModSorter:updateSortingRule(modId, loadAfter, loadBefore, incompatibleMods, loadfirst, loadlast)
	if self.sortingRulesCache == nil then self:readSortingRules() end

	local rulesFromFile = self.sortingRulesCache[modId] or {}
	rulesFromFile.loadAfter = loadAfter or rulesFromFile.loadAfter or {}
	rulesFromFile.loadBefore = loadBefore or rulesFromFile.loadBefore or {}
	rulesFromFile.incompatibleMods = incompatibleMods or rulesFromFile.incompatibleMods or {}
	rulesFromFile.loadFirst = loadfirst or rulesFromFile.loadFirst or "off"
	rulesFromFile.loadLast = loadlast or rulesFromFile.loadLast or "off"
	self.sortingRulesCache[modId] = rulesFromFile
	return self.sortingRulesCache
end

function ModSorter:updateExtraModInfoSortingRules(extraModInfo, rulesFromFile)
	rulesFromFile.loadAfter = utils:MergeTablesDedup(rulesFromFile.loadAfter or {}, extraModInfo.loadAfter)
	rulesFromFile.loadBefore = utils:MergeTablesDedup(rulesFromFile.loadBefore or {}, extraModInfo.loadBefore)
	rulesFromFile.incompatibleMods = utils:MergeTablesDedup(rulesFromFile.incompatibleMods or {}, extraModInfo.incompatibleMods)
	rulesFromFile.loadFirst = convertToLoadCategory(rulesFromFile.loadFirst or extraModInfo.loadFirst)
	rulesFromFile.loadLast = convertToLoadCategory(rulesFromFile.loadLast or extraModInfo.loadLast)

	extraModInfo.sortingRules = rulesFromFile
end

function ModSorter:updateSortingRulesLoadAfter()
	for curmod, modinfo in pairs(self.modsInfoCache) do
		local loadbefore = modinfo.sortingRules.loadBefore
		if loadbefore ~= nil then
			for _, val in ipairs(loadbefore) do
				local valModInfo = self.modsInfoCache[val]
				if val ~= nil and valModInfo ~= nil then
					valModInfo.sortingRules.loadAfter = utils:MergeTablesDedup(valModInfo.sortingRules.loadAfter or {}, { curmod })
				end
			end
		end
	end
end

function ModSorter:saveSortingRules(SR_Data, name)
	local file_name = name or RULES_FILE
	local file_data = SR_Data or self.sortingRulesCache

	local file = getFileWriter(file_name, true, false)
	for modId, data in pairs(file_data) do
		local text = getSRDataText(modId, data.loadAfter, data.loadBefore, data.incompatibleMods, data.loadFirst, data.loadLast)
		if text~=nil then file:write(text) end
	end
	file:close()
end

function ModSorter:readSortingRules()
	local rules = {}
	local curmodname = nil

	local file = getFileReader(RULES_FILE, true)
	local line = file:readLine()
	while line ~= nil do
		local modname = utils:addSlashToBeginnig(string.match(line, '%[%s*(.-)%s*%]')) -- split line by '=' and trim
		if modname ~= nil then curmodname = modname end
		if curmodname ~= nil then
			rules[curmodname] = rules[curmodname] or {} -- init rule dict for mod
			local currule = rules[curmodname]

			local key, value = string.match(line, '^%s*(.-)%s*=%s*(.-)%s*$') -- split line by '=' and trim
			key, value = string.lower(key or ""), value or ""                -- replace nil with empty string
			if key == "loadafter" or key == "loadmodafter" then
				currule.loadAfter = utils:addSlashToBeginnig(utils:MergeTablesDedup(currule.loadAfter or {}, utils:splitStringBySeparator(value)))
			elseif key == "loadbefore"  or key == "loadmodbefore" then
				currule.loadBefore = utils:addSlashToBeginnig(utils:MergeTablesDedup(currule.loadBefore or {}, utils:splitStringBySeparator(value)))
			elseif key == "incompatiblemods" or key == "incompatible" then
				currule.incompatibleMods = utils:addSlashToBeginnig(utils:MergeTablesDedup(currule.incompatibleMods or {}, utils:splitStringBySeparator(value)))
			elseif key == "loadfirst" then
				currule.loadFirst = convertToLoadCategory(value)
			elseif key == "loadlast" then
				currule.loadLast = convertToLoadCategory(value)
			elseif key ~= "" then
				print("[[readSortingRules]]: Unsupported key", key, " Skipping...")
			end
		end
		line = file:readLine()
	end
	file:close()
	self.sortingRulesCache = rules
	return rules
end
-- /\ ================================== SORTING RULES ================================== /\

local function readModInfoFile(modId)
	-- read mod.info file
	local result = {}

	local file = getModFileReader(modId, "mod.info", false)
	if file == nil then return result end

	local line = file:readLine()
	while line ~= nil do
		local key, value = string.match(line, '^%s*(.-)%s*=%s*(.-)%s*$') -- split line by '=' and trim
		key, value = string.lower(key or ""), value or ""          -- replace nil with empty string

		if key == "name" then
			result.name = value
		elseif key == "id" then
			result.id = value
		elseif key == "tags" then
			result.tags = utils:splitStringBySeparator(value)
		elseif key == "require" then
			result.requirements = utils:splitStringBySeparator(value)
		elseif key == "loadafter" then
			result.loadAfter = utils:splitStringBySeparator(value)
		elseif key == "loadbefore" then
			result.loadBefore = utils:splitStringBySeparator(value)
		elseif key == "incompatiblemods" then
			result.incompatibleMods = utils:splitStringBySeparator(value)
		elseif key == "loadfirst" then
			result.loadFirst = convertToLoadCategory(value)
		elseif key == "loadlast" then
			result.loadLast = convertToLoadCategory(value)
		end

		line = file:readLine()
	end
	file:close()

end


local function getExtraModInfo(modInfoObj, modObject)
	local extraModInfo = {
		name = modInfoObj:getName(),
		id = modInfoObj:getId(),
		category = modInfoObj:getCategory(),
		requirements = utils:toKahluaTable(modInfoObj:getRequire()),
		loadAfter = utils:toKahluaTable(modInfoObj:getLoadAfter()),
		loadBefore = utils:toKahluaTable(modInfoObj:getLoadBefore()),
		incompatibleMods = utils:toKahluaTable(modInfoObj:getIncompatible()),
		loadFirst = "off",
		loadLast = "off",
        maps = {},
        warnings = {},
		flags = {},
		object = modObject
	}

	extraModInfo = utils:MergeTablesDedup(extraModInfo, readModInfoFile())

	if categoryOrder[extraModInfo.category] == nil then
		extraModInfo.category = "undefined"
	else
		return extraModInfo
	end

	-- Mod is Tweak?
	local frameworkKeys = { "framework", " api", "tweak", "interface", "utilit" } --, "optimize"}
	extraModInfo.flags.isTweak = utils:strContainsAny(extraModInfo.name, frameworkKeys)

	-- Mod with maps?
	local mapList = utils:toKahluaTable(getMapFoldersForMod(extraModInfo.id))
	extraModInfo.flags.isMap = (mapList and #mapList > 0 and true) or false
	extraModInfo.maps = utils:MergeTablesDedup(extraModInfo.maps, mapList)

	-- check the remaining flags based on the existence of specific folders or files
	local directories = {modInfoObj:getVersionDir() or "", modInfoObj:getCommonDir() or ""}
	for _, modDir in ipairs(directories) do
		modDir = string.gsub(modDir, "\\", "/")

		local foldersCheck = {
			isModels = (extraModInfo.flags.isModels and true) or (utils:isExists(modDir, "/media/models_X/") or utils:isExists(modDir, "/media/models/")),
			isTextures = (extraModInfo.flags.isTextures and true) or (utils:isExists(modDir, "/media/textures/") or utils:isExists(modDir, "/media/texturepacks/")),
			isVehicleModels = (extraModInfo.flags.isVehicleModels and true) or (utils:isExists(modDir, "/media/models_X/vehicles/") or utils:isExists(modDir, "/media/models/vehicles/")),
			isCodeExist = (extraModInfo.flags.isCodeExist and true) or (utils:isExists(modDir, "/media/lua/client/") or utils:isExists(modDir, "/media/lua/server/") or utils:isExists(modDir, "/media/scripts/") or utils:isExists(modDir, "/media/shared/")),
			isSkinned = (extraModInfo.flags.isSkinned and true) or utils:isExists(modDir, { "/media/models_X/Skinned/", "/media/textures/" }),
			isUI = (extraModInfo.flags.isUI and true) or utils:isExists(modDir, { "/media/textures/ui/", "/media/ui/" }),
			isTranslation = (extraModInfo.flags.isTranslation and true) or utils:isExists(modDir, "/media/lua/shared/Translate/" .. Translator.getLanguage():name()),
			isResource = (extraModInfo.flags.isResource and true) or utils:isExists(modDir, "media/resource/")
		}
		extraModInfo.flags = utils:MergeTablesDedup(extraModInfo.flags, foldersCheck)
	end

	-- apply category based on detected flags
	local function _checkAndApplyCategory(categoryName, expression)
		if expression then
			extraModInfo.category = categoryOrder[extraModInfo.category] > categoryOrder[categoryName] and categoryName or extraModInfo.category
		end
	end

	_checkAndApplyCategory("translation", extraModInfo.flags.isTranslation and not (extraModInfo.flags.isCodeExist or extraModInfo.flags.isModels or extraModInfo.flags.isTextures))
	_checkAndApplyCategory("ui", extraModInfo.flags.isUI)
	_checkAndApplyCategory("clothes", extraModInfo.flags.isSkinned)
	_checkAndApplyCategory("code", extraModInfo.flags.isCodeExist and not (extraModInfo.flags.isModels or extraModInfo.flags.isTextures or extraModInfo.flags.isUI or extraModInfo.flags.isResource))
	_checkAndApplyCategory("tweaks", extraModInfo.flags.isTweak)
	_checkAndApplyCategory("vehicle", extraModInfo.flags.isVehicleModels and extraModInfo.flags.isTextures)
	_checkAndApplyCategory("map", extraModInfo.flags.isMap)
	_checkAndApplyCategory("resource", (extraModInfo.flags.isTextures or extraModInfo.flags.isResource) and not (extraModInfo.flags.isCodeExist or extraModInfo.flags.isModels or extraModInfo.flags.isMap or extraModInfo.flags.isUI))
	_checkAndApplyCategory("other", extraModInfo.category == "undefined")

	local temp_flags = {}
	for k, v  in pairs(extraModInfo.flags) do if v then table.insert(temp_flags, k) end end
	extraModInfo.flags = temp_flags

	return extraModInfo
end

local function initialSortMods(a, b)
	if preorder[a.id] ~= preorder[b.id] then
		return (preorder[a.id] or 10000) < (preorder[b.id] or 10000)
	end
	local a_sr = a.sortingRules
	local b_sr = b.sortingRules
	-- sorting rules loadFirst/loadLast in whole mod list
	if a_sr.loadFirst ~= b_sr.loadFirst and (a_sr.loadFirst == "on" or b_sr.loadFirst == "on") then
		return loadCategories[a_sr.loadFirst] < loadCategories[b_sr.loadFirst]
	end
	if a_sr.loadLast ~= b_sr.loadLast and (a_sr.loadLast == "on" or b_sr.loadLast == "on") then
		return loadCategories[a_sr.loadLast] > loadCategories[b_sr.loadLast]
	end
	-- sort by category
	if categoryOrder[a.category] ~= categoryOrder[b.category] then
		return categoryOrder[a.category] < categoryOrder[b.category]
	end
	-- sorting rules loadFirst/loadLast in category
	if a_sr.loadFirst ~= b_sr.loadFirst then
		return loadCategories[a_sr.loadFirst] < loadCategories[b_sr.loadFirst]
	end
	if a_sr.loadLast ~= b_sr.loadLast then
		return loadCategories[a_sr.loadLast] > loadCategories[b_sr.loadLast]
	end

	return a.id:lower() < b.id:lower()
end

local function topological_sort(mods_list, mods_cache)
	local sorted = {}
	local visited = {}
	local visiting = {}

	local function visit(mod)
		if visiting[mod.id] then error("Dependencyes Cycle Detected for " .. mod.id) end

		if not visited[mod.id] then
			mods_cache[mod.id].warnings = {}
			visiting[mod.id] = true
			for _, dep in ipairs(mod.requirements) do
				if mods_cache[dep] ~= nil then
					visit(mods_cache[dep])
				end
			end
			-- apply sorting rules
			for _, dep in ipairs(mod.sortingRules.loadAfter or {}) do
				if mods_cache[dep] ~= nil then
					visit(mods_cache[dep])
				end
			end
			visiting[mod.id] = nil
			visited[mod.id] = true
			table.insert(sorted, mod.id)
		end
	end

	for _, mod in ipairs(mods_list) do
		visit(mod)
	end
	return sorted
end


function ModSorter:initModsInfoCache(modsList)
    local sortingRules = self:readSortingRules()

	local currentOrder = {}
	for _, val in ipairs(modsList) do
		local extraModInfo = self.modsInfoCache[val.item.modId] or getExtraModInfo(val.item.modInfo, val)
		self:updateExtraModInfoSortingRules(extraModInfo, sortingRules[extraModInfo.id] or {})
		table.insert(currentOrder, extraModInfo)
		self.modsInfoCache[val.item.modId] = extraModInfo
	end
	self:updateSortingRulesLoadAfter()
    return currentOrder
end


function ModSorter:SortModsOrder(modsList)
	print("Mods sorting STARTED!")
    local currentOrder = self:initModsInfoCache(modsList)
	table.sort(currentOrder, initialSortMods)
	return topological_sort(currentOrder, self.modsInfoCache)
end

-- ================================ Validaing ================================

function ModSorter:validateSorting(modsList)
	self:initModsInfoCache(modsList)

	-- Validating Order
	local isCorrectOrder = true
	local checkedIds = {}
	for _, val in ipairs(modsList) do
		local _extraModInfo = self.modsInfoCache[val.item.modId]
		_extraModInfo.warnings = {incompatible = {}, missing={}, rules={}}

		for _, _req in ipairs(_extraModInfo.requirements) do
			if not utils:contains(checkedIds, _req) then
				isCorrectOrder = false
				table.insert(_extraModInfo.warnings.missing, _req)
			end
		end

		for _, _req in ipairs(_extraModInfo.sortingRules.loadAfter) do
			if self.modsInfoCache[_req] ~= nil and not utils:contains(checkedIds, _req) then
				table.insert(_extraModInfo.warnings.rules, _req)
			end
		end

		for _, _req in ipairs(_extraModInfo.sortingRules.incompatibleMods) do
			if self.modsInfoCache[_req] ~= nil then
				table.insert(_extraModInfo.warnings.incompatible, _req)
			end
		end
		table.insert(checkedIds, _extraModInfo.id)
	end
	return isCorrectOrder
end

return ModSorter