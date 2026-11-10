local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local listFilesInModDirectory = listFilesInModDirectory

local MLOS_ModsInfo = {}
MLOS_ModsInfo.data = {} -- data[modId] = { id, name, category, requirements, loadAfter, loadBefore, incompatibleMods, requiredBy, warnings.missing, ... }


--- Layer entry point, see LayerManager. Collects facts from mod.info for the
--- enabled mods only; everything that depends on sorting rules or on the
--- current order (graph, incompatibilities, validation) lives in SortingCore.
function MLOS_ModsInfo:load(ctx)
    local data = {}
    for i, row in ipairs(ctx.mods) do
        local modId = row.item.modId
        local info = (ctx.reread ~= true and self.data[modId]) or self:getExtraModInfo(row)
        info.requiredBy = {}
        info.warnings = { missing = {} }

        if info.category == nil or not utils:contains(core.rawCategoryOrder, info.category) then
            pcall(function() error("\n[ERROR] --> [MLOS] Mod: [" .. tostring(info.name) .. "] have unknown category: " .. tostring(info.category) .. "\n") end )
        end

        data[modId] = info
        ctx:step(i, #ctx.mods)
    end

    -- Reverse requirements and requirements that are not enabled.
    for modId, info in pairs(data) do
        for _, dep in ipairs(info.requirements or {}) do
            if data[dep] then
                table.insert(data[dep].requiredBy, modId)
            else
                table.insert(info.warnings.missing, dep)
            end
        end
    end

    self.data = data
end

function MLOS_ModsInfo:getWarnings()
    local warnings = {}
    for modId, info in pairs(self.data or {}) do
        if info.warnings and not utils:tableIsEmpty(info.warnings.missing) then
            warnings[#warnings + 1] = {
                severity = "CRITICAL", layer = "ModsInfo",
                title = getText("UI_MLOS_MissingDep_Title") .. " [" .. tostring(info.name or modId) .. "]",
                message = getText("UI_MLOS_MissingDep_Msg", tostring(info.name or modId), table.concat(info.warnings.missing, ", "))
            }
        end
    end
    return warnings
end


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

	local modinfoFileData = readModInfoFile(extraModInfo.id)
	modinfoFileData.id = nil
	modinfoFileData.name = nil
	modinfoFileData.requirements = modinfoFileData.require
	modinfoFileData.require = nil
	extraModInfo = utils:MergeTablesDedup(extraModInfo, modinfoFileData)


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



return MLOS_ModsInfo
