local utils = require('OptionScreens/MLOS_core/Refr_utils')
local core = require('OptionScreens/MLOS_core/MLOS_Core')

local MLOS_ModsInfo = {}
MLOS_ModsInfo.data = {} -- data from modInfo. data[modId] = {name, desc, category, requirements, loadAfter, ...}


local function readModInfoFile(modId)
	local result = {}

	local file = getModFileReader(modId, "mod.info", false)
	if file == nil then return result end

	local line = file:readLine()
	while line ~= nil do
		core:getDataFromString(line, result)
		line = file:readLine()
	end
	file:close()

	return result
end


local function getPriority(mod)
	local catCount = #core.rawCategoryOrder * 10

	local effectiveCategory = mod.sortingRules.category or mod.category
    local priority = (catCount - (core.categoryOrder[effectiveCategory] - 1) * 10) -- range: 0 ... catCount

	-- Правила сортировки
	if core.preorder[mod.id] ~= nil then priority = priority + catCount + 1000 + core.preorder[mod.id] end
    if (mod.sortingRules.loadFirst or mod.loadFirst)  == "on" then priority = priority + catCount + 100 end
	if (mod.sortingRules.loadLast or mod.loadLast) == "on" then priority = priority - catCount - 100 end
	if (mod.sortingRules.loadFirst or mod.loadFirst) == "category" then priority = priority + 1 end
    if (mod.sortingRules.loadLast or mod.loadLast) == "category"then priority = priority - 1 end
    return priority
end


local function getFlags(directories, name, maps)
	local flags = {}
	flags.isTweak = utils:strContainsAny(name, core.tweakKeys)
	flags.isMap = not utils:tableIsEmpty(maps)

	-- check the remaining flags based on the existence of specific folders or files
	for _, modDir in ipairs(directories) do
		if modDir ~= nil then
			modDir = string.gsub(modDir, "\\", "/")

			flags.isModels = flags.isModels or utils:isExists(modDir, "/media/models_X/") or utils:isExists(modDir, "/media/models/")
			flags.isTextures = flags.isTextures or utils:isExists(modDir, "/media/textures/") or utils:isExists(modDir, "/media/texturepacks/")
			flags.isVehicleModels = flags.isVehicleModels or utils:isExists(modDir, "/media/models_X/vehicles/") or utils:isExists(modDir, "/media/models/vehicles/")
			flags.isCodeExist = flags.isCodeExist or utils:isExists(modDir, "/media/lua/client/") or utils:isExists(modDir, "/media/lua/server/") or utils:isExists(modDir, "/media/scripts/") or utils:isExists(modDir, "/media/shared/")
			flags.isSkinned = flags.isSkinned or utils:isExists(modDir, { "/media/models_X/Skinned/", "/media/textures/" }) or utils:isExists(modDir, "/media/clothing/")
			flags.isUI = flags.isUI or utils:isExists(modDir, { "/media/textures/ui/", "/media/ui/" })
			flags.isTranslation = flags.isTranslation or utils:isExists(modDir, "/media/lua/shared/Translate/" .. Translator.getLanguage():name())
			flags.isResource = flags.isResource or utils:isExists(modDir, "media/resource/") or utils:isExists(modDir, "media/sound/")
		end
	end

	return flags
end


local function getCategory(flags)
	local result = "undefined"

	-- apply category based on detected flags
	local function _checkAndApplyCategory(_categoryName, _expression)
		if _expression then
			result = core.categoryOrder[result] > core.categoryOrder[_categoryName] and _categoryName or result
		end
	end

	_checkAndApplyCategory("translation", flags.isTranslation and not (flags.isCodeExist or flags.isMap or flags.isTweak or flags.isModels or flags.isSkinned or flags.isResource or flags.isUI))
	_checkAndApplyCategory("ui", flags.isUI)
	_checkAndApplyCategory("clothes", flags.isSkinned)
	_checkAndApplyCategory("code", flags.isCodeExist and not (flags.isModels or flags.isMap or flags.isTweak  or flags.isVehicleModels or flags.isTextures or flags.isUI or flags.isResource))
	_checkAndApplyCategory("vehicle", flags.isVehicleModels and not (flags.isMap))
	_checkAndApplyCategory("map", flags.isMap and not (flags.isVehicleModels))
	_checkAndApplyCategory("resource", (flags.isTextures or flags.isResource) and not (flags.isTranslation or flags.isCodeExist or flags.isModels or flags.isMap or flags.isUI))
	_checkAndApplyCategory("tweaks", flags.isTweak)
	_checkAndApplyCategory("other", result == "undefined")
	return result
end


function MLOS_ModsInfo:getExtraModInfo(modInfoObj, modObject)
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
		tags = {},
		object = modObject
	}
	extraModInfo.maps = utils:toKahluaTable(getMapFoldersForMod(extraModInfo.id))

	extraModInfo = utils:MergeTablesDedup(extraModInfo, readModInfoFile(extraModInfo.id))

	-- detect category from tags
	if not utils:tableIsEmpty(extraModInfo.tags) then
		for _, i in ipairs(extraModInfo.tags) do
			local tag = i:lower()
			for k,v in pairs(core.workshopTagsMapping) do
				if tag == k or utils:contains(v, tag) then
					extraModInfo.category = k
					break
				end
			end
			if extraModInfo.category ~= nil then break end
		end
	end
	if core.categoryOrder[extraModInfo.category] ~= nil then
		return extraModInfo
	end
	
	extraModInfo.flags = getFlags( { modInfoObj:getVersionDir(), modInfoObj:getCommonDir() } , extraModInfo.name, extraModInfo.maps )
	extraModInfo.category = getCategory(extraModInfo.flags)
	
	local temp_flags = {}
	for k, v in pairs(extraModInfo.flags) do if v then table.insert(temp_flags, k) end end
	extraModInfo.flags = temp_flags

	return extraModInfo
end

---@param modsList table list of mods
---@return table current order
function MLOS_ModsInfo:UpdateData(modsList, sortingRulesCache)
	local curentOrder = {}

	for _, val in ipairs(modsList) do
		local modId = val.item.modId
		local extraModInfo = self.data[modId] or self:getExtraModInfo(val.item.modInfo, val)
		
		-- recalculate cache 
		extraModInfo.warnings = {}
		extraModInfo.sortingRules = sortingRulesCache[modId] or {}
		extraModInfo.fixedLoadAfter = {}
		extraModInfo.priority = getPriority(extraModInfo)
		
		self.data[modId] = extraModInfo

		table.insert(curentOrder, modId)
	end

	for curmod, modinfo in pairs(self.data) do
		local loadbefore = utils:MergeTablesDedup({}, modinfo.loadBefore, modinfo.sortingRules.loadBefore)
		if loadbefore ~= nil then
			for _, val in ipairs(loadbefore) do
				local valModInfo = self.data[val]
				if val ~= nil and valModInfo ~= nil then
					utils:MergeTablesDedup(valModInfo.fixedLoadAfter, { curmod })
				end
			end
		end
	end

	return curentOrder
end

return MLOS_ModsInfo
