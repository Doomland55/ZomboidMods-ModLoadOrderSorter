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
local W_REQUIRE = 100   -- require= from mod.info
local W_LOAD = 95       -- loadAfter/loadBefore from mod.info
local W_RULES = 90      -- loadAfter/loadBefore from sorting rules
local W_HOOK = 50       -- overwrite must load before a hook of the same function
local W_SHADOW = 10     -- same lua file in several mods: keep current relative order
local W_SOFT = 5        -- hooks/overwrites of the same target: keep current relative order


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
function MLOS_SortingCore:buildGraph(modsList)
	local layers = core.layers
	local modInfo = (layers.modInfo and layers.modInfo.data) or {}
	local modFiles = (layers.modFiles and layers.modFiles.data) or {}
	local rules = (layers.sortingRules and layers.sortingRules.data) or {}

	local enabled = {}
	local orderIndex = {}
	for i, val in ipairs(modsList) do
		local id = val.item.modId
		enabled[id] = true
		orderIndex[id] = i
	end

	local edges = {}
	self.warnings = {}

	-- 1. hard dependencies from ModsInfo (+ sorting rules merged into it)
	for modId, info in pairs(modInfo) do
		if enabled[modId] then
			local sr = info.sortingRules or rules[modId] or {}
			local function need(dep, w)
				if dep and dep ~= modId and enabled[dep] then addEdge(edges, dep, modId, w) end
			end
			local function before(dep, w)
				if dep and dep ~= modId and enabled[dep] then addEdge(edges, modId, dep, w) end
			end

			for _, dep in ipairs(info.requirements or {}) do need(dep, W_REQUIRE) end
			for _, dep in ipairs(info.loadAfter or {}) do need(dep, W_LOAD) end
			for _, dep in ipairs(info.fixedLoadAfter or {}) do need(dep, W_LOAD) end
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
				table.insert(fileOwners[f], modId)
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
	--    the same target (otherwise the overwrite erases the hook)
	local targetOwners = {} -- fullTarget -> { {mod, isHook}, ... }
	for modId, fdata in pairs(modFiles) do
		if enabled[modId] and fdata.complete ~= false then
			for _, m in ipairs(fdata.modifications or {}) do
				local key = m.fullTarget or ((m.className or "?") .. ":" .. (m.methodName or "?"))
				targetOwners[key] = targetOwners[key] or {}
				table.insert(targetOwners[key], { mod = modId, isHook = (m.isHook == true) })
			end
		end
	end
	for target, owners in pairs(targetOwners) do
		if #owners > 1 then
			local overwrites, hooks = {}, {}
			for _, o in ipairs(owners) do
				if o.isHook then table.insert(hooks, o.mod) else table.insert(overwrites, o.mod) end
			end

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

	return edges, enabled, orderIndex
end


--- Kahn's topological sort. Among all currently available nodes the one with
--- the highest priority (category + rules) is placed first; ties are broken by
--- the current list order and then by mod id. If a cycle is found, the
--- remaining nodes are appended by priority and a warning is emitted.
---@param modsList table modList.items
---@return table sorted array of modIds
function MLOS_SortingCore:sort(modsList)
	local edges, enabled, orderIndex = self:buildGraph(modsList)
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

	-- higher priority first; on equal priority sort by mod id (name),
	-- so the result is deterministic and does not depend on the previous order
	local function better(a, b)
		local pa = (modInfo[a] and modInfo[a].priority) or 0
		local pb = (modInfo[b] and modInfo[b].priority) or 0
		if pa ~= pb then return pa > pb end
		return tostring(a):lower() < tostring(b):lower()
	end

	local sorted = {}
	local placed = {}
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

	-- cycle detected: place the rest by priority and warn the player
	local remaining = {}
	for id in pairs(enabled) do
		if not placed[id] then table.insert(remaining, id) end
	end
	if #remaining > 0 then
		table.sort(remaining, better)
		table.insert(self.warnings, {
			severity = "CRITICAL",
			layer = "SortingRules",
			title = getText("UI_MLOS_Cycle_Title"),
			message = getText("UI_MLOS_Cycle_Msg", table.concat(remaining, ", "))
		})
		for _, id in ipairs(remaining) do
			placed[id] = true
			table.insert(sorted, id)
		end
	end

	return sorted
end


--- Validates the current order and fills per-mod warnings (missing deps,
--- incompatible mods, deps placed below). Returns true when the order is valid.
---@param modsList table modList.items
---@return boolean
function MLOS_SortingCore:validate(modsList)
	local modInfo = (core.layers.modInfo and core.layers.modInfo.data) or {}
	local enabled = {}
	local orderIndex = {}
	for i, val in ipairs(modsList) do
		local id = val.item.modId
		enabled[id] = true
		orderIndex[id] = i
	end

	local isCorrect = true
	for i, val in ipairs(modsList) do
		local modId = val.item.modId
		local info = modInfo[modId]
		if info then
			info.warnings = info.warnings or {}
			info.warnings.wrongOrder = info.warnings.wrongOrder or {}
			local deps = utils:MergeTablesDedup({},
				info.requirements, info.loadAfter, info.fixedLoadAfter,
				(info.sortingRules or {}).loadAfter)
			for _, dep in ipairs(deps or {}) do
				if enabled[dep] and (orderIndex[dep] or 1e9) > i then
					isCorrect = false
					table.insert(info.warnings.wrongOrder, dep)
				end
			end
		end
	end
	return isCorrect
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
