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
-- local utils = require('OptionScreens/MLOS_core/Refr_utils')
local utils = require('OptionScreens/MLOS_core/Refr_utils')
local ModsInfo = require('OptionScreens/MLOS_core/MLOS_Layer_ModsInfo')
local SortingRules = require('OptionScreens/MLOS_core/MLOS_Layer_SortingRules')
local WorkshopInfo = require('OptionScreens/MLOS_core/MLOS_Layer_WorkshopInfo')

local ModSorter = {}

local function _compareModIds(aId, bId)
	local a = ModsInfo.data[aId]
	local b = ModsInfo.data[bId]
	if a == nil or b == nil then
		return tostring(aId):lower() < tostring(bId):lower()
	end
    if a.priority ~= b.priority then
        return a.priority > b.priority
    end
    return a.id:lower() < b.id:lower()  -- Если приоритеты равны, сортируем по имени
end


local function dependencyCycleException(vistingMods)
	local visited = {}; for k, _ in pairs(vistingMods) do table.insert(visited, k) end
	error("WARNING: Dependencyes Cycle Detected for " .. utils:getString(visited))
end


local function topologicalSort(modsList, modsCache)
	local sorted = {}
	local visited = {}
	local visiting = {}

	local function visit(mod)
		if visiting[mod.id] then
			pcall(dependencyCycleException, visiting)
			return
		end
		
		if not visited[mod.id] then
			visiting[mod.id] = true
			for _, dep in ipairs(mod.requirements) do
				if modsCache[dep] ~= nil then
					visit(modsCache[dep])
				end
			end

			-- apply sorting rules
			for _, dep in ipairs(mod.fixedLoadAfter or {}) do
				if modsCache[dep] ~= nil then
					visit(modsCache[dep])
				end
			end
			visiting[mod.id] = nil
			visited[mod.id] = true
			table.insert(sorted, mod.id)
		end
	end

	for _, mod in ipairs(modsList) do
		visit(modsCache[mod])
	end
	return sorted
end


function ModSorter:sortModsOrder(mods_list)
	print("[MLOS] Preparing mods cache!")
    SortingRules:readSortingRules()
	local currentOrder = ModsInfo:UpdateData(mods_list, SortingRules.data)

	print("[MLOS] Mods sorting STARTED!")
	table.sort(currentOrder, _compareModIds)
	return topologicalSort(currentOrder, ModsInfo.data)
end

-- ================================ Validaing ================================

function ModSorter:validateSorting(modsList)
    SortingRules:readSortingRules()
	local curOrder = ModsInfo:UpdateData(modsList, SortingRules.data)
	
	local enbledMods = {}
	for _, val in ipairs(curOrder) do
		enbledMods[val.id] = true
	end

	-- Validating Order
	local isCorrectOrder = true
	local checkedIds = {}
	for _, val in ipairs(modsList) do
		local sortingRrules = SortingRules[val.item.modId] or {}
		local extraModInfo = ModsInfo.data[val.item.modId]
		extraModInfo.warnings = {incompatible = {}, missing={}, rules={}}

		for _, _req in ipairs(extraModInfo.requirements or {}) do
			if not checkedIds[_req] then
				isCorrectOrder = false
				table.insert(extraModInfo.warnings.missing, _req)
			end
		end

		for _, _req in ipairs(sortingRrules.loadAfter or {}) do
			if self.modsInfoCache[_req] and not checkedIds[_req] then
				table.insert(extraModInfo.warnings.rules, _req)
			end
		end

		for _, _req in ipairs(sortingRrules.incompatibleMods or {}) do
			if self.modsInfoCache[_req] and enbledMods[_req] then
				table.insert(extraModInfo.warnings.incompatible, _req)
			end
		end
		checkedIds[extraModInfo.id] = true
	end
	return isCorrectOrder
end

return ModSorter