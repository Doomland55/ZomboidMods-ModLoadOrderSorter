---
--- Sorting core: builds a directed dependency graph (DAG) from all layers
--- (mod.info requirements, loadAfter/loadBefore, sorting rules, file shadowing
--- and function overwrites/hooks from the ModsFiles layer) and runs a
--- topological sort (Kahn's algorithm) with category priorities.
--- Cycles are detected, reported as warnings and broken by priority.
--- The resulting order can be applied to the mod list (with a backup file).
---
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')

local MLOS_SortingCore = {}
MLOS_SortingCore.warnings = {} -- list of { title, message, layer, severity } from the last sort

local BACKUP_FILE = "loadOrderBackup.txt"

-- edge weights (hard deps must never be broken, soft ones may be dropped on cycles)
local W_REQUIRE = 100 -- require= from mod.info
local W_LOAD = 95     -- loadAfter/loadBefore from mod.info
local W_RULES = 90    -- loadAfter/loadBefore from sorting rules
local W_HOOK = 50     -- overwrite must load before a hook of the same function
local W_SHADOW = 10   -- same lua file in several mods: keep current relative order
local W_SOFT = 5      -- hooks/overwrites of the same target: keep current relative order


local function addEdge(edges, from, to, weight)
	if from == nil or to == nil or from == to then return end
	edges[from] = edges[from] or {}
	for _, e in ipairs(edges[from]) do
		if e.to == to then
			if weight > e.weight then e.weight = weight end
			return
		end
	end
	table.insert(edges[from], { to = to, weight = weight })
end


local function hasAnyEdge(edges, from, to)
	for _, e in ipairs(edges[from] or {}) do
		if e.to == to then return true end
	end
	return false
end


--- Soft edge (keep current relative order). Never added against an existing
--- edge in the opposite direction - that would create an artificial cycle.
local function addSoftEdge(edges, from, to, weight)
	if hasAnyEdge(edges, to, from) then return end
	addEdge(edges, from, to, weight)
end


local function sortByCurrentOrder(ids, orderIndex)
	table.sort(ids, function(a, b)
		return (orderIndex[a] or 1e9) < (orderIndex[b] or 1e9)
	end)
	return ids
end


--- True when a hard dependency (require / loadAfter / loadBefore / sorting
--- rules, i.e. weight >= W_RULES) exists between a and b in any direction.
--- Such an explicit dependency means the overwrite order was set on purpose.
local function hasHardEdge(edges, a, b)
	for _, e in ipairs(edges[a] or {}) do
		if e.to == b and e.weight >= W_RULES then return true end
	end
	for _, e in ipairs(edges[b] or {}) do
		if e.to == a and e.weight >= W_RULES then return true end
	end
	return false
end


--- Builds the dependency graph.
--- Edge A -> B means "A must be loaded before B".
---@param modsList table modList.items
---@return table edges, table enabled, table orderIndex
function MLOS_SortingCore:buildGraph(modsList, activeRules)
	local layers = core.layers
	local modInfo = (layers.modInfo and layers.modInfo.data) or {}
	local modFiles = (layers.modFiles and layers.modFiles.data) or {}
	local rules = activeRules or (layers.sortingRules and layers.sortingRules.data) or {}

	local enabled = {}
	local orderIndex = {}
	for i, val in ipairs(modsList) do
		local id = val.item.modId
		enabled[id] = true
		orderIndex[id] = i
	end

	local edges = {}
	self.warnings = {}

	-- 1. hard dependencies from ModsInfo and from the sorting rules
	for modId, info in pairs(modInfo) do
		if enabled[modId] then
			local sr = rules[modId] or {}
			local function need(dep, w)
				if dep and dep ~= modId and enabled[dep] then addEdge(edges, dep, modId, w) end
			end
			local function before(dep, w)
				if dep and dep ~= modId and enabled[dep] then addEdge(edges, modId, dep, w) end
			end

			for _, dep in ipairs(info.requirements or {}) do need(dep, W_REQUIRE) end
			for _, dep in ipairs(info.loadAfter or {}) do need(dep, W_LOAD) end
			for _, dep in ipairs(info.loadBefore or {}) do before(dep, W_LOAD) end
			for _, dep in ipairs(sr.loadAfter or {}) do need(dep, W_RULES) end
			for _, dep in ipairs(sr.loadBefore or {}) do before(dep, W_RULES) end
		end
	end

	-- 2. file shadowing: the same lua file in several mods -> later mod in the
	--    current order wins, so keep the current relative order for them
	local fileOwners = {}
	for modId, fdata in pairs(modFiles) do
		if enabled[modId] then
			for _, f in ipairs(fdata.files or {}) do
				fileOwners[f] = fileOwners[f] or {}
				if not utils:contains(fileOwners[f], modId) then
					table.insert(fileOwners[f], modId)
				end
			end
		end
	end
	for _, owners in pairs(fileOwners) do
		if #owners > 1 then
			sortByCurrentOrder(owners, orderIndex)
			for i = 2, #owners do
				addEdge(edges, owners[i - 1], owners[i], W_SHADOW)
			end
		end
	end

	-- 3. function modifications: a full overwrite must load before any hook of
	--    the same target (otherwise the overwrite erases the hook).
	--    One entry per mod per target: a mod overwriting its own target in
	--    several files is NOT a conflict (intra-mod analysis is skipped).
	local targetOwners = {} -- fullTarget -> { [modId] = isHook }
	for modId, fdata in pairs(modFiles) do
		if enabled[modId] and fdata.complete ~= false then
			for _, m in ipairs(fdata.modifications or {}) do
				local key = ((m.className or "?") .. "." .. (m.methodName or "?"))
				targetOwners[key] = targetOwners[key] or {}
				if targetOwners[key][modId] == nil then
					targetOwners[key][modId] = (m.isHook == true)
				elseif m.isHook ~= true then
					targetOwners[key][modId] = false -- hard overwrite dominates over a hook
				end
			end
		end
	end
	for target, owners in pairs(targetOwners) do
		local overwrites, hooks = {}, {}
		for mod, isHook in pairs(owners) do
			if isHook then table.insert(hooks, mod) else table.insert(overwrites, mod) end
		end
		local ownerCount = #overwrites + #hooks
		if ownerCount > 1 then
			if #overwrites > 1 then
				-- several mods fully overwrite the same function. When two of them
				-- are already connected by an explicit hard dependency (require /
				-- loadAfter / loadBefore / sorting rules), the overwrite was made
				-- on purpose and no warning is needed for that pair.
				local conflicting = {}
				for i = 1, #overwrites do
					for j = i + 1, #overwrites do
						local a, b = overwrites[i], overwrites[j]
						if not hasHardEdge(edges, a, b) then
							table.insert(conflicting, a .. " <-> " .. b)
						end
					end
				end
				if #conflicting > 0 then
					table.insert(self.warnings, {
						severity = "CRITICAL",
						layer = "ModsFiles",
						title = getText("UI_MLOS_Conflict_Overwrite_Title"),
						message = getText("UI_MLOS_Conflict_Overwrite_Msg", table.concat(conflicting, "; "), target)
					})
				end
			end

			for _, ow in ipairs(overwrites) do
				for _, hk in ipairs(hooks) do
					if ow ~= hk then addEdge(edges, ow, hk, W_HOOK) end
				end
			end

			-- keep current relative order inside each group
			for _, group in ipairs({ hooks, overwrites }) do
				if #group > 1 then
					sortByCurrentOrder(group, orderIndex)
					for i = 2, #group do
						addSoftEdge(edges, group[i - 1], group[i], W_SOFT)
					end
				end
			end
		end
	end

	-- 4. effective category per mod: a mod must never sit in a category that
	--    comes AFTER the category of a mod which depends on it. For every hard
	--    edge U -> V (U loads before V, weight >= W_RULES) the category index
	--    of U is pulled up to at most the index of V (fixpoint propagation).
	local catCount = #core.rawCategoryOrder
	local catIndex = {}
	local enabledCount = 0
	for id in pairs(enabled) do
		enabledCount = enabledCount + 1
		local info = modInfo[id]
		local cat = (rules[id] or {}).category or (info and info.category) or (modFiles[id] and modFiles[id].category) or "undefined"
		catIndex[id] = core.categoryOrder[cat] or catCount
		if info then info.effectiveCategory = core.rawCategoryOrder[catIndex[id]] end
	end
	for _ = 1, enabledCount do
		local changed = false
		for from, list in pairs(edges) do
			if catIndex[from] ~= nil then
				for _, e in ipairs(list) do
					if e.weight >= W_RULES and catIndex[e.to] ~= nil and catIndex[e.to] < catIndex[from] then
						catIndex[from] = catIndex[e.to]
						local info = modInfo[from]
						if info then info.effectiveCategory = core.rawCategoryOrder[catIndex[from]] end
						changed = true
					end
				end
			end
		end
		if not changed then break end
	end
	-- Heuristic edges must not force a later category ahead of an earlier one.
	for from, list in pairs(edges) do
		for i = #list, 1, -1 do
			local e = list[i]
			if e.weight < W_RULES and catIndex[from] > catIndex[e.to] then table.remove(list, i) end
		end
	end

	return edges, enabled, orderIndex, catIndex
end

-- Shared by sorting and validation so positional rules have identical meaning.
local function positionRank(id, rules, categories)
	local rule = rules[id] or {}
	if rule.loadFirst == "on" then return 0, 0, 0 end
	if rule.loadLast == "on" then return 2, 0, 0 end
	local position = rule.loadFirst == "category" and -1 or (rule.loadLast == "category" and 1 or 0)
	return 1, categories[id] or #core.rawCategoryOrder, position
end


--- Kahn's topological sort. Among all currently available nodes the one with
--- the highest priority (category + rules) is placed first; ties are broken by
--- mod id (name). When a cycle is found, the WEAKEST remaining edge is removed
--- and the sort continues - soft "keep current order" hints (shadowing / hook
--- order, weights 5-10) are broken first, hard dependencies (require /
--- loadAfter / loadBefore / rules, weights >= 90) are preserved whenever
--- possible. Broken edges are reported as a warning.
---@param modsList table modList.items
---@return table sorted array of modIds
function MLOS_SortingCore:sort(modsList, activeRules)
	local edges, enabled, _, catIndex = self:buildGraph(modsList, activeRules)
	self.lastEdges = edges
	self.brokenEdges = {}
	local modInfo = (core.layers.modInfo and core.layers.modInfo.data) or {}

	local indegree = {}
	for id in pairs(enabled) do indegree[id] = 0 end
	for _, list in pairs(edges) do
		for _, e in ipairs(list) do
			indegree[e.to] = (indegree[e.to] or 0) + 1
		end
	end

	local ready = {}
	for id, d in pairs(indegree) do
		if d == 0 then table.insert(ready, id) end
	end

	-- Rank ready nodes by global position, promoted category and category position.
	local rules = activeRules or (core.layers.sortingRules and core.layers.sortingRules.data) or {}
	local function better(a, b)
		local ag, ac, ap = positionRank(a, rules, catIndex)
		local bg, bc, bp = positionRank(b, rules, catIndex)
		if ag ~= bg then return ag < bg end
		if ac ~= bc then return ac < bc end
		if ap ~= bp then return ap < bp end
		local an = tostring((modInfo[a] or {}).name or a):lower()
		local bn = tostring((modInfo[b] or {}).name or b):lower()
		if an ~= bn then return an < bn end
		return tostring(a) < tostring(b)
	end

	local sorted = {}
	local placed = {}

	local function placeReady()
		while #ready > 0 do
			local best = 1
			for i = 2, #ready do
				if better(ready[i], ready[best]) then best = i end
			end
			local id = table.remove(ready, best)
			if not placed[id] then
				placed[id] = true
				table.insert(sorted, id)
				for _, e in ipairs(edges[id] or {}) do
					indegree[e.to] = indegree[e.to] - 1
					if indegree[e.to] == 0 then table.insert(ready, e.to) end
				end
			end
		end
	end

	placeReady()

	-- cycle breaking: remove the weakest edge between unplaced nodes
	while true do
		local remaining = 0
		for id in pairs(enabled) do
			if not placed[id] then remaining = remaining + 1 end
		end
		if remaining == 0 then break end

		-- Only remove an edge that actually participates in a cycle, not an
		-- unrelated low-priority edge downstream from one.
		local function reaches(start, target, seen)
			if start == target then return true end
			if seen[start] or placed[start] then return false end
			seen[start] = true
			for _, edge in ipairs(edges[start] or {}) do
				if reaches(edge.to, target, seen) then return true end
			end
			return false
		end
		local weakest = nil -- { list=..., idx=..., from=..., to=..., weight=... }
		for from, list in pairs(edges) do
			if not placed[from] then
				for i, e in ipairs(list) do
					if not placed[e.to] and reaches(e.to, from, {}) then
						if weakest == nil or e.weight < weakest.weight or (e.weight == weakest.weight and (from .. "\0" .. e.to) < (weakest.from .. "\0" .. weakest.to)) then
							weakest = { list = list, idx = i, from = from, to = e.to, weight = e.weight }
						end
					end
				end
			end
		end
		if weakest == nil then break end -- safety net, should not happen

		table.remove(weakest.list, weakest.idx)
		indegree[weakest.to] = indegree[weakest.to] - 1
		table.insert(self.brokenEdges, { from = weakest.from, to = weakest.to, weight = weakest.weight })
		if indegree[weakest.to] == 0 then table.insert(ready, weakest.to) end
		placeReady()
	end

	-- report broken edges (usually only soft order-hints were dropped)
	if #self.brokenEdges > 0 then
		local involved = {}
		local hasHard = false
		for _, e in ipairs(self.brokenEdges) do
			if e.weight >= W_RULES then hasHard = true end
			if not utils:contains(involved, e.from) then table.insert(involved, e.from) end
			if not utils:contains(involved, e.to) then table.insert(involved, e.to) end
		end
		table.sort(involved)
		table.insert(self.warnings, {
			severity = hasHard and "CRITICAL" or "WARNING",
			layer = "SortingRules",
			title = getText("UI_MLOS_Cycle_Title"),
			-- when only soft order-hints were dropped, say so explicitly -
			-- there is no real dependency cycle, just conflicting order hints
			message = (hasHard and getText("UI_MLOS_Cycle_Msg", table.concat(involved, ", "))
					or getText("UI_MLOS_OrderHintBroken_Msg", table.concat(involved, ", ")))
				.. " | " .. (function()
					local details = {}
					for _, e in ipairs(self.brokenEdges) do details[#details + 1] = e.from ..
						" -> " .. e.to .. " (" .. e.weight .. ")" end
					return table.concat(details, "; ")
				end)()
		})
	end

	for _, warning in ipairs(self:getIncompatibleWarnings(modsList, rules)) do
		table.insert(self.warnings, warning)
	end

	return sorted
end

--- Enabled mods that are declared incompatible by mod.info or by the sorting
--- rules; one warning per pair. Does not need a sort, so it can be shown as
--- soon as the layers are loaded.
---@param modsList table modList.items
---@param activeRules table|nil working rules; saved rules are used by default
---@return table list of { severity, layer, title, message }
function MLOS_SortingCore:getIncompatibleWarnings(modsList, activeRules)
	local info = (core.layers.modInfo and core.layers.modInfo.data) or {}
	local rules = activeRules or (core.layers.sortingRules and core.layers.sortingRules.data) or {}
	local enabled = {}
	for _, val in ipairs(modsList) do enabled[val.item.modId] = true end

	local function name(id) return tostring((info[id] or {}).name or id) end
	local warnings, reported = {}, {}
	for _, val in ipairs(modsList) do
		local id = val.item.modId
		for _, list in ipairs({ (info[id] or {}).incompatibleMods or {}, (rules[id] or {}).incompatibleMods or {} }) do
			for _, other in ipairs(list) do
				local key = id < other and (id .. " / " .. other) or (other .. " / " .. id)
				if enabled[other] and id ~= other and not reported[key] then
					reported[key] = true
					table.insert(warnings, {
						severity = "CRITICAL", layer = "ModsInfo",
						title = getText("UI_MLOS_Incompatible_Title"),
						message = getText("UI_MLOS_Incompatible_Msg", name(id), name(other))
					})
				end
			end
		end
	end
	return warnings
end

--- Returns the highest-severity validation status for each affected mod.
---@param modsList table modList.items
---@return table status by mod ID (purple, red or yellow)
function MLOS_SortingCore:validate(modsList, activeRules)
	local info = (core.layers.modInfo and core.layers.modInfo.data) or {}
	local rules = activeRules or (core.layers.sortingRules and core.layers.sortingRules.data) or {}
	local _, enabled, index, cats = self:buildGraph(modsList, rules)
	local status = {}
	local severity = { yellow = 1, red = 2, purple = 3 }
	local function mark(id, color)
		if not status[id] or severity[color] > severity[status[id]] then status[id] = color end
	end
	for id in pairs(enabled) do
		local data, rule = info[id] or {}, rules[id] or {}
		for _, dep in ipairs(data.requirements or {}) do
			if not enabled[dep] or index[dep] > index[id] then mark(id, "red") end
		end
		for _, list in ipairs({ data.incompatibleMods or {}, rule.incompatibleMods or {} }) do
			for _, other in ipairs(list) do
				if enabled[other] then
					mark(id, "purple"); mark(other, "purple")
				end
			end
		end
		for _, list in ipairs({ data.loadAfter or {}, rule.loadAfter or {} }) do
			for _, other in ipairs(list) do
				if enabled[other] and index[other] > index[id] then mark(id, "yellow") end
			end
		end
		for _, list in ipairs({ data.loadBefore or {}, rule.loadBefore or {} }) do
			for _, other in ipairs(list) do
				if enabled[other] and index[other] < index[id] then mark(id, "yellow") end
			end
		end
	end
	for i = 1, #modsList do
		local a = modsList[i].item.modId
		local ag, ac, ap = positionRank(a, rules, cats)
		for j = i + 1, #modsList do
			local b = modsList[j].item.modId
			local bg, bc, bp = positionRank(b, rules, cats)
			if ag > bg or (ag == bg and (ac > bc or (ac == bc and ap > bp))) then
				mark(a, "yellow"); mark(b, "yellow")
			end
		end
	end
	return status
end

--- Applies the sorted order to the load order panel.
--- The current order is backed up to loadOrderBackup.txt first.
---@param panel table ModLoadOrderPanel
---@param sortedIds table array of modIds
function MLOS_SortingCore:applyOrder(panel, sortedIds)
	if not panel or not panel.modList then return end

	-- backup current order
	local current = {}
	for _, val in ipairs(panel.modList.items) do
		table.insert(current, val.item.modId)
	end
	local file = getFileWriter(core.MLOS_ROOT .. "/" .. BACKUP_FILE, true, false)
	if file then
		file:write(table.concat(current, ";"))
		file:close()
	end

	-- rebuild items in the new order
	local byId = {}
	for _, val in ipairs(panel.modList.items) do
		byId[val.item.modId] = val
	end
	local newItems = {}
	for _, id in ipairs(sortedIds) do
		if byId[id] then
			table.insert(newItems, byId[id])
			byId[id] = nil
		end
	end
	-- safety net: append anything that was not in sortedIds
	for _, val in ipairs(panel.modList.items) do
		if byId[val.item.modId] then table.insert(newItems, val) end
	end

	panel.modList.items = newItems
	for i, val in ipairs(newItems) do
		val.itemindex = i
	end
	panel.modList.selected = 1
	print("[MLOS] New load order applied (" .. #newItems .. " mods). Backup saved to " .. BACKUP_FILE)
end

return MLOS_SortingCore
