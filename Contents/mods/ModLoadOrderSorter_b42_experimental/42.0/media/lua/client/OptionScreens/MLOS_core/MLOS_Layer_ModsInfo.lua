local utils = require('OptionScreens/MLOS_core/Refr_utils')
local core = require('OptionScreens/MLOS_core/MLOS_Core')
local listFilesInModDirectory = listFilesInModDirectory

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
	local effectiveCategory = mod.sortingRules.category or mod.category or "undefined"
    local priority = (catCount - (core.categoryOrder[effectiveCategory] - 1) * 10) -- range: 0 ... catCount

	-- Правила сортировки
	if core.preorder[mod.id] ~= nil then priority = priority + catCount + 1000 + core.preorder[mod.id] end
    if (mod.sortingRules.loadFirst or mod.loadFirst)  == "on" then priority = priority + catCount + 100 end
	if (mod.sortingRules.loadLast or mod.loadLast) == "on" then priority = priority - catCount - 100 end
	if (mod.sortingRules.loadFirst or mod.loadFirst) == "category" then priority = priority + 1 end
    if (mod.sortingRules.loadLast or mod.loadLast) == "category"then priority = priority - 1 end
    return priority
end


local isLinux = isSystemLinux()
local lang = Translator.getLanguage():name()
local TAG_PATTERNS = {
    isItem = {
        "/media/lua/server/items",  "/media/lua/client/items",
		"/media/lua/shared/Recipes", "/media/lua/shared/Definitions",
        "/media/lua/server/Items", "/media/lua/shared/Items", "/media/lua/client/Items",
		"/media/scripts/[item|recipe].txt"
    },
    isClothes = {
        "/media/clothing", "/media/models_x/Skinned/Clothes", "/media/models_x/WorldItems/Clothes",
        "/media/textures/clothes", "/media/lua/shared/items/Clothing", "/media/lua/shared/Items/Clothing",
        "/media/lua/client/CharacterCustomisation", "/media/lua/shared/CharacterCustomisation",
        "/media/models_X/Skinned/Clothes", "/media/models_X/WorldItems/Clothes", "/media/textures/Clothes"
    },
    isWeapon = {
        "/media/models_x/weapons", "/media/textures/weapons", "/media/scripts/firearms",
        "/media/scripts/GunPartItem", "/media/lua/client/WeaponAbility", 
		"/media/scripts/WeaponAbility", "/media/lua/shared/Items/Weapon", "/media/models_X/weapons"
    },
    isMap = {
        "/media/maps/", "/media/mapszones/"
    },
    isUI = {
        "/media/ui/", "/media/lua/client/UI", "/media/lua/shared/DT/Common/UI",
        "/media/lua/client/ISUI", "/media/lua/client/EquipmentUI", "/media/lua/client/OptionScreens",
        "/media/textures/UI", "/media/textures/ui"
    },
    isVehicle = {
        "/media/AnimSets/player-vehicle", "/media/scripts/vehicles",
        "/media/models_X/vehicles", "/media/models_x/vehicles", "/media/textures/vehicles",
        "/media/sound/vehicles", "/media/lua/client/Vehicles", "/media/lua/server/Vehicles", "/media/lua/shared/Vehicles"
    },
    isCode = {
        "/media/lua/client/", "/media/lua/server/", "/media/lua/shared/", "/media/scripts/"
    },
    isTranslation = {
        "/media/lua/shared/Translate/" .. lang, "/media/lua/shared/translate/" .. lang
    },
    isResource = {
        "/media/sound/", "/media/textures/", "/media/texturepacks/", "/media/models_X/", "/media/models_x/",
        "/media/shaders/", "/media/animsets", "/media/AnimSets/", "/media/resource/", "/media/scripts/sound",
        "/media/scripts/sounds", "/media/sound/Instruments", "/media/sound/voice",
        "/media/textures/FX", "/media/effects/"
    }
}

local function extractFlags(extraModInfo)
	local modInfo = extraModInfo.object.item.modInfo
	local versionDir = modInfo:getVersionDir()
	local commonDir = modInfo:getCommonDir()

    local paths_tags = {}

    for tag, patterns in pairs(TAG_PATTERNS) do
		local checked_path = {}

		for _, pattern in ipairs(patterns) do
			
			local directory, filename = utils:splitPath(pattern)
			local dir_low = directory:lower()

			if checked_path[dir_low] == nil or isLinux then
				checked_path[dir_low] = checked_path[dir_low] or true
				if utils:isExists(versionDir, directory) or utils:isExists(commonDir, directory) then
					if filename ~= "" then
						local files = checked_path[dir_low] ~= true and checked_path[dir_low] or listFilesInModDirectory(extraModInfo.id, directory)
						checked_path[dir_low] = utils:toKahluaTable(files)
						
						if utils:doesModHaveFile(checked_path[dir_low], filename) then
							paths_tags[dir_low] = tag
							break
						end

					else
						paths_tags[dir_low] = tag
						break
					end
				end
			end
		end
	end

	local temp_flags = {}
	for v, tag in pairs(paths_tags) do
		local is_specific = true
		for p, _ in pairs(paths_tags) do
			if p ~= v and string.find(p, v, 1, true) then
				is_specific = false
				break
			end
		end
		if is_specific then temp_flags[tag] = true end
	end

	temp_flags.isTweak = temp_flags.isTweak or utils:strContainsAny(extraModInfo.name, core.tweakKeys)
	temp_flags.isMap = temp_flags.isMap or not utils:tableIsEmpty(extraModInfo.maps)

	local flags = {}
	for k, v in pairs(temp_flags) do if v then table.insert(flags, k) end end

	if #flags >= 7 and temp_flags.isResource and temp_flags.isUI and temp_flags.isCode then table.insert(flags, "isCoreReq") end
	return flags
end


local function getCategoryFromTagsMapping(_table, isTags)
	local cur_category = nil
	local cur_prioirty = 1000
	for category, data in pairs(core.categoryConfig) do
		if data.priority and data.priority < cur_prioirty then
			local checkWith = (isTags and data.tags or data.flags) or {}
			if _table and utils:containsAnyTag(_table, checkWith, true) then
				cur_prioirty = data.priority
				cur_category = category
			end
		end
	end
	return cur_category
end


function MLOS_ModsInfo:getExtraModInfo(modObject)
	local modInfoObj = modObject.item.modInfo
	local extraModInfo = {
		name = modInfoObj:getName(),
		id = modInfoObj:getId(),
		category = modInfoObj:getCategory() or nil,
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
		extraModInfo.category = getCategoryFromTagsMapping(extraModInfo.tags, true)
	end

	if not core.categoryOrder[extraModInfo.category] then
		extraModInfo.flags = extractFlags(extraModInfo)
		extraModInfo.category = getCategoryFromTagsMapping(extraModInfo.flags, false) or "undefined"
	end

	return extraModInfo
end


---@param modsList table list of mods
---@return table current order
function MLOS_ModsInfo:UpdateData(modsList, sortingRulesCache)
	local curentOrder = {}

	for _, val in ipairs(modsList) do
		local modId = val.item.modId
		local extraModInfo = self.data[modId] or self:getExtraModInfo(val)
		
		-- recalculate cache 
		extraModInfo.warnings = {}
		extraModInfo.sortingRules = sortingRulesCache[modId] or {}
		extraModInfo.fixedLoadAfter = {}

		if not utils:contains(core.rawCategoryOrder, extraModInfo.category) then
			pcall(function() error("\n[ERROR] --> [MLOS] Mod: [" .. extraModInfo.name .. "] have unknown category: " .. extraModInfo.category .. "\n") end )
		end

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
