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
	{ name = "modFiles",     path = "REfRigERatoR_ModLoadOrderSorter/Layers/1_ModsFiles" },
	{ name = "modInfo",      path = "REfRigERatoR_ModLoadOrderSorter/Layers/2_ModsInfo" },
	{ name = "sortingRules", path = "REfRigERatoR_ModLoadOrderSorter/Layers/3_SortingRules" },
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


--- Builds a full debug dump (all layers data + dependency graph + last sort
--- results) as plain text. Used for bug reports - can be saved to a file or
--- copied to the clipboard.
---@param modsList table modList.items of the load order panel
---@return string
function core.layersManager:dumpDebugData(modsList)
	local sorter = require('REfRigERatoR_ModLoadOrderSorter/Core/2_SortingCore')
	local parts = {}
	local dateStr = ""
	-- os is unavailable in Kahlua.
	table.insert(parts, "=== MLOS DEBUG DUMP " .. dateStr .. " ===")
	table.insert(parts, "MOD_VERSION=" .. tostring(core.MOD_VERSION))

	local modInfo = (core.layers.modInfo and core.layers.modInfo.data) or {}
	local modFiles = (core.layers.modFiles and core.layers.modFiles.data) or {}
	local rules = (core.layers.sortingRules and core.layers.sortingRules.data) or {}

	-- per-mod data in current list order
	table.insert(parts, "=== MODS (current order) ===")
	for i, val in ipairs(modsList or {}) do
		local id = val.item.modId
		local info = modInfo[id] or {}
		local fdata = modFiles[id] or {}
		local sr = info.sortingRules or rules[id] or {}
		table.insert(parts, string.format("[%d] %s | name=%s | category=%s | effectiveCategory=%s | priority=%s | complete=%s",
			i, id, tostring(info.name), tostring(info.category), tostring(info.effectiveCategory), tostring(info.priority), tostring(fdata.complete)))
		table.insert(parts, "  require=" .. utils:getString(info.requirements))
		table.insert(parts, "  loadAfter=" .. utils:getString(info.loadAfter))
		table.insert(parts, "  loadBefore=" .. utils:getString(info.loadBefore))
		table.insert(parts, "  fixedLoadAfter=" .. utils:getString(info.fixedLoadAfter))
		table.insert(parts, "  incompatible=" .. utils:getString(info.incompatibleMods))
		table.insert(parts, "  rules: loadAfter=" .. utils:getString(sr.loadAfter)
			.. " loadBefore=" .. utils:getString(sr.loadBefore)
			.. " incompatible=" .. utils:getString(sr.incompatibleMods)
			.. " loadFirst=" .. tostring(sr.loadFirst) .. " loadLast=" .. tostring(sr.loadLast)
			.. " category=" .. tostring(sr.category))
		table.insert(parts, "  warnings=" .. utils:getString(info.warnings))
		table.insert(parts, "  files(" .. #(fdata.files or {}) .. ")=" .. table.concat(fdata.files or {}, ","))
		for _, m in ipairs(fdata.modifications or {}) do
			table.insert(parts, string.format("  func: %s%s -> %s | isHook=%s | file=%s | line=%s",
				tostring(m.className), tostring(m.methodName and ":" or ""), tostring(m.fullTarget),
				tostring(m.isHook), tostring(m.file), tostring(m.line)))
		end
	end

	-- dependency graph: capture last sort results first, then rebuild the
	-- graph fresh for the current mod list
	local lastWarnings = sorter.warnings or {}
	local lastBroken = sorter.brokenEdges or {}
	local edges = modsList and sorter:buildGraph(modsList) or sorter.lastEdges
	table.insert(parts, "=== GRAPH EDGES (from -> to [weight]) ===")
	local edgeLines = {}
	for from, list in pairs(edges or {}) do
		for _, e in ipairs(list) do
			table.insert(edgeLines, string.format("%s -> %s [%d]", from, e.to, e.weight))
		end
	end
	table.sort(edgeLines)
	for _, s in ipairs(edgeLines) do table.insert(parts, s) end

	-- last sort results
	table.insert(parts, "=== BROKEN EDGES (last sort) ===")
	for _, e in ipairs(lastBroken) do
		table.insert(parts, string.format("%s -> %s [%d]", e.from, e.to, e.weight))
	end
	table.insert(parts, "=== WARNINGS (last sort) ===")
	for _, w in ipairs(lastWarnings) do
		table.insert(parts, tostring(w.severity) .. " [" .. tostring(w.layer) .. "] " .. tostring(w.title) .. ": " .. tostring(w.message))
	end

	return table.concat(parts, "\n")
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
			layers[layer.name] = require(layer.path)
		end
	end

	-- 1. sorting rules (fast, from file)
	layers.sortingRules:getData(modsList, callbacks.reread)

	-- 2. mod info (from game + mod.info, merged with sorting rules)
	self.currentOrder = layers.modInfo:getData(modsList, layers.sortingRules.data, callbacks.reread)

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
