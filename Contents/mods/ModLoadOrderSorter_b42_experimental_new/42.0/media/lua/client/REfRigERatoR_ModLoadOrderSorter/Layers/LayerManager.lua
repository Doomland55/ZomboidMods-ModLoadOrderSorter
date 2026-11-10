---
--- Layers manager: loads and initialises all data layers in the right order:
---   1. sortingRules (fast, synchronous read of sorting_rules.txt)
---   2. modInfo      (synchronous, reads data from Project Zomboid + mod.info, merged with rules)
---   3. modFiles     (cache read is synchronous; stale mods are analysed asynchronously)
--- and provides merged per-mod data and aggregated warnings for the UI.
---
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')

if not core then return end

-- order matters for merging: later layers override earlier ones (sorting rules win)
local registeredLayers = {
	{ name = "sortingRules", path = "REfRigERatoR_ModLoadOrderSorter/Layers/SortingRules" },
	-- { name = "ZombieBuddy",     path = "REfRigERatoR_ModLoadOrderSorter/Layers/1_ModsFiles" },
	{ name = "modFiles",     path = "REfRigERatoR_ModLoadOrderSorter/Layers/ModsFiles" },
	{ name = "modInfo",      path = "REfRigERatoR_ModLoadOrderSorter/Layers/ModsInfo" },
	-- { name = "mod_modFolders", path = "REfRigERatoR_ModLoadOrderSorter/Layers/3_SortingRules" },
}

core.layers = core.layers or {}
core.layersManager = core.layersManager or {}


--- Merged data of all layers for one mod (sorting rules have the highest priority)
---@param modId string
---@return table
function core.layersManager:getMergedData(modId)
	local result = {}
	for i = 1, #registeredLayers do
		local layer = registeredLayers[i]
		local layerObj = core.layers[layer.name]
		if layerObj and layerObj.data and layerObj.data[modId] then
			utils:MergeTablesDedup(result, layerObj.data[modId])
		end
	end
	return result
end


---@param modId string
---@param valueName string
---@return any
function core.layersManager:getValue(modId, valueName)
	return self:getMergedData(modId)[valueName]
end


---@return boolean true when the (possibly async) initialisation finished
function core.layersManager:isCompleted()
	return self.completed == true
end


--- Aggregated warnings of all layers, ready to be shown in the warning popup
---@return table list of { title, message, layer, severity }
function core.layersManager:getWarnings()
	local warnings = {}

	local modFiles = core.layers.modFiles
	if modFiles and modFiles:hasNotLoadedMods() then
		table.insert(warnings, {
			severity = "WARNING",
			layer = "ModsFiles",
			title = getText("UI_MLOS_Warning_NotLoaded_Title"),
			message = getText("UI_MLOS_Warning_NotLoaded_Msg", table.concat(modFiles.notLoaded, ", "))
		})
	end

	local modInfo = core.layers.modInfo
	if modInfo and modInfo.data then
		for modId, info in pairs(modInfo.data) do
			if info.warnings then
				if not utils:tableIsEmpty(info.warnings.missing) then
					table.insert(warnings, {
						severity = "CRITICAL",
						layer = "ModsInfo",
						title = getText("UI_MLOS_MissingDep_Title") .. " [" .. tostring(info.name or modId) .. "]",
						message = getText("UI_MLOS_MissingDep_Msg", tostring(info.name or modId), table.concat(info.warnings.missing, ", "))
					})
				end
				if not utils:tableIsEmpty(info.warnings.incompatible) then
					table.insert(warnings, {
						severity = "CRITICAL",
						layer = "ModsInfo",
						title = getText("UI_MLOS_Incompatible_Title") .. " [" .. tostring(info.name or modId) .. "]",
						message = getText("UI_MLOS_Incompatible_Msg", tostring(info.name or modId), table.concat(info.warnings.incompatible, ", "))
					})
				end
			end
		end
	end

	return warnings
end



--- Initialises all layers.
---@param modsList table modList.items of the load order panel
---@param callbacks table|nil { reread=bool, onFilesProgress=func(cur,total), onComplete=func() }
function core.layersManager:initialise(modsList, callbacks)
	callbacks = callbacks or {}
	local layers = core.layers
	self.completed = false

	-- load layer modules once
	for i = 1, #registeredLayers do
		local layer = registeredLayers[i]
		if not layers[layer.name] then
			local layerObj = require(layer.path)
			layerObj:getData(modsList, callbacks)
			layers[layer.name] = layerObj
		end
	end

	-- -- 1. sorting rules (fast, from file)
	-- layers.sortingRules:getData(modsList, callbacks.reread)

	-- -- 2. mod info (from game + mod.info, merged with sorting rules)
	-- self.currentOrder = layers.modInfo:getData(modsList, layers.sortingRules.data, callbacks.reread)

	-- 3. mod files: initialised LAST, so it can consume data of the layers
	--    below (modInfo / sortingRules) via core.layers, e.g. to tell apart
	--    intentional overwrites (explicit dependencies) from real conflicts.
	--    Cache read is synchronous, stale mods are analysed async with progress
	layers.modFiles:queryAndGetData(modsList, {
		reread = callbacks.reread,
		onProgress = callbacks.onFilesProgress,
		onComplete = function(_data)
			self.completed = true
			if callbacks.onComplete then callbacks.onComplete() end
		end,
	})
end
