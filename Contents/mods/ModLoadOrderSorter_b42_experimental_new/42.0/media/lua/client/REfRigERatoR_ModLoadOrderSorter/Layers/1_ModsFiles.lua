---
--- Layer "ModsFiles": collects the list of lua files of every enabled mod and
--- analyses them for overwritten/hooked functions.
--- Analysis of file contents is possible only for enabled AND loaded mods
--- (the authoritative list of loaded files comes from getLoadedLua()).
--- Enabled but not loaded mods are reported via self.notLoaded so the UI can
--- show a "reload Lua" warning.
--- Because parsing is slow and files rarely change, results are stored in a
--- text cache file (modsFilesCache.txt). A mod is rescanned only when its
--- signature (mod.info version + number of lua files) changed or it is
--- missing from the cache.
---
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')

local cacheFileExists = cacheFileExists
local listFilesInModDirectory = listFilesInModDirectory

local CACHE_FILE = "modsFilesCache.txt"
local LUA_DIR = "media/lua"
local FILES_PER_FRAME = 8 -- how many files are parsed per game tick while async scanning

local MLOS_ModsFiles = {}
MLOS_ModsFiles.data = {}        -- data[modId] = { rootDir, files={...}, modifications={...}, signature, complete }
MLOS_ModsFiles.cache = nil      -- raw cache read from file
MLOS_ModsFiles.notLoaded = {}   -- modIds: enabled but without any loaded lua file
MLOS_ModsFiles.staleMods = {}   -- modIds that were (re)scanned in the last run
MLOS_ModsFiles.isAnalyzing = false
MLOS_ModsFiles.progress = { current = 0, total = 0 }


--================================================
--      Cache helpers
--================================================

--- Best-effort workshop update timestamp (seconds) of a mod.
--- Uses querySteamWorkshopItemDetails when the game build exposes it to Lua;
--- returns nil for local mods or builds without the API.
---@param modInfo table ModInfo object (item.modInfo)
---@return string|nil
local function getWorkshopUpdateTimestamp(modInfo)
    local ok, id = pcall(utils.getWorkshopId, utils, modInfo)
    if ok and id then return MLOS_ModsFiles.workshopTimes and MLOS_ModsFiles.workshopTimes[tostring(id)] end
end

--- Cheap signature of a mod: mod.info version + number of lua files +
--- workshop update timestamp (when available). Used to detect changed mods
--- without reading every file.
---@param modId string
---@param modInfo table|nil ModInfo object of the mod
---@return string
local function getModSignature(modId, modInfo)
	local version = ""
	local ok, reader = pcall(getModFileReader, modId, "mod.info", false)
	if ok and reader then
		local line = reader:readLine()
		while line ~= nil do
			local v = line:match("^%s*version%s*=%s*(.-)%s*$")
			if v ~= nil and v ~= "" then version = v break end
			line = reader:readLine()
		end
		reader:close()
	end

	local count = 0
	local okFiles, files = pcall(listFilesInModDirectory, modId, LUA_DIR)
	if okFiles and files then count = files:size() end

	local updateTime = modInfo and getWorkshopUpdateTimestamp(modInfo) or ""

	return tostring(version) .. "|" .. tostring(count) .. "|" .. tostring(updateTime or "")
end


---@param modId string
---@return table list of relative lua file paths of the mod (from disk)
function MLOS_ModsFiles:listModLuaFiles(modId)
	local result = {}
	local ok, files = pcall(listFilesInModDirectory, modId, LUA_DIR)
	if ok and files then
		result = utils:toKahluaTable(files)
	end
	return result
end


--- Map of mod root dir -> true for every mod that has at least one loaded lua file
---@return table
local function getLoadedModDirs()
    local paths = {}
    for i = 0, getLoadedLuaCount() - 1 do
        local path = getLoadedLua(i)
        if path then paths[#paths + 1] = path:gsub("\\", "/") end
    end
    return paths
end

local function listLoadedModFiles(modId, dir, modInfo, paths)
    local result, seen = {}, {}
    local roots = {dir}
    local ok, version = pcall(function() return modInfo:getVersionDir() end)
    if ok and version then roots[#roots + 1] = version end
    local commonOK, common = pcall(function() return modInfo:getCommonDir() end)
    if commonOK and common then roots[#roots + 1] = common end
    for _, path in ipairs(paths or getLoadedModDirs()) do
        for _, root in ipairs(roots) do
            root = root:gsub("\\", "/"):gsub("/$", "")
            if path:sub(1, #root + 1) == root .. "/" then
                -- getModFileReader expects paths relative to a mod version or common root.
                local rel = path:match("(media/lua/.*)$")
                if rel and not seen[rel] then seen[rel] = true; result[#result+1] = rel end
                break
            end
        end
    end
    return result
end


--================================================
--      Cache file IO
--================================================

---@param modId string
---@param data table
---@return string
local function cacheDataToText(modId, data)
	local lines = {}
	table.insert(lines, "signature=" .. tostring(data.signature or ""))
	table.insert(lines, "complete=" .. tostring(data.complete == true))
	if not utils:tableIsEmpty(data.files) then
		table.insert(lines, "files=" .. table.concat(data.files, ","))
	end
	for _, m in ipairs(data.modifications or {}) do
		table.insert(lines, "mod=" .. table.concat({
			m.file or "",
			m.fullTarget or ((m.className or "") .. ":" .. (m.methodName or "")),
			tostring(m.line or 0),
			tostring(m.isHook == true),
			m.alias or ""
		}, "|"))
	end
	return "[" .. modId .. "]\r\n" .. table.concat(lines, "\r\n")
end


local function cacheLineToData(addTo, line)
	local key, value = line:match('^%s*(.-)%s*=%s*(.-)%s*$')
	if key == nil then return end
	key = key:lower()
	if key == "signature" then
		addTo.signature = value
	elseif key == "complete" then
		addTo.complete = (value == "true")
	elseif key == "files" then
		addTo.files = utils:splitStringBySeparator(value)
	elseif key == "mod" then
		-- file|fullTarget|line|isHook[|alias] - alias field is optional (old caches)
		local file, target, lineNum, isHook, alias = value:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|?(.*)$")
		if file then
			local className, methodName = target:match("^(.-):([^:]+)$")
			addTo.modifications = addTo.modifications or {}
			table.insert(addTo.modifications, {
				file = file,
				fullTarget = target,
				className = className,
				methodName = methodName,
				alias = (alias ~= nil and alias ~= "") and alias or nil,
				line = tonumber(lineNum),
				isHook = (isHook == "true")
			})
		end
	end
end


--- Saves current layer data to the cache file
function MLOS_ModsFiles:saveCache()
	if utils:tableIsEmpty(self.data) then return end
	local path = core.MLOS_ROOT .. "/" .. CACHE_FILE
	print("[MLOS] Saving mods files cache: " .. path)
	core:saveTxtFile(path, self.data, cacheDataToText)
	self.cache = self.data
end


--- Reads the cache file
---@return table
function MLOS_ModsFiles:readCache()
	local path = core.MLOS_ROOT .. "/" .. CACHE_FILE
	if cacheFileExists(path) ~= true then return {} end
	print("[MLOS] Reading mods files cache: " .. path)
	local result = core:readTxtFile(path, cacheLineToData)
	return result or {}
end


--================================================
--      Lua file parser (overwrites / hooks)
--================================================

local function parseFileFunctions(modId, filename)
	local success, reader = pcall(getModFileReader, modId, filename, false)
	if not success or not reader then return nil end

	local declaredTables = {}   -- real table literals: "X = {"
	local aliasMap = {}         -- localName -> resolved dotted target ("A.B.C") or "require:<path>"
	local modifiedFunctions = {}
	local savedOriginals = {}

	-- resolve an alias chain, including dotted heads:
	-- local B = A.C; local D = B.E  =>  D resolves to A.C.E
	-- BOUNDED: cyclic aliases (A->B, B->A.C or "local X = X.foo") must never
	-- cause an infinite loop with ever-growing strings (OOM in the game)
	local MAX_RESOLVE_STEPS = 8
	local MAX_RESOLVED_LEN = 256
	local function resolve(name)
		local cur = name
		for _ = 1, MAX_RESOLVE_STEPS do
			if type(cur) ~= "string" or #cur > MAX_RESOLVED_LEN then break end
			local head, rest = cur:match("^([%w_]+)%.?(.*)$")
			if not head or not aliasMap[head] then break end
			local resolvedHead = aliasMap[head]
			local newCur = (rest ~= nil and rest ~= "") and (resolvedHead .. "." .. rest) or resolvedHead
			if newCur == cur or #newCur > MAX_RESOLVED_LEN then break end
			cur = newCur
		end
		return cur
	end

	-- store an alias only when it does not reference itself (directly or via a chain)
	local function addAlias(localName, rhs)
		local resolved = resolve(rhs)
		if resolved == localName then return end
		if resolved:sub(1, #localName + 1) == (localName .. ".") then return end
		aliasMap[localName] = resolved
	end

	local lineNum = 0
    local inBlockComment = false
	local line = reader:readLine()

	while line ~= nil do
		lineNum = lineNum + 1

        -- Strip line and long comments across lines before detecting definitions.
        local clean = ""
        local rest = line
        while #rest > 0 do
            if inBlockComment then
                local close = rest:find("]]", 1, true)
                if not close then rest = "" else rest = rest:sub(close + 2); inBlockComment = false end
            else
                local comment = rest:find("--", 1, true)
                if not comment then clean = clean .. rest; rest = ""
                else
                    clean = clean .. rest:sub(1, comment - 1)
                    if rest:sub(comment, comment + 3) == "--[[" then
                        inBlockComment = true; rest = rest:sub(comment + 4)
                    else rest = "" end
                end
            end
        end
        line = clean
		-- fast pre-filter: a hook/overwrite always contains "function" or "="
		local hasFunc = line:find("function", 1, true)
		local hasAssign = line:find("=", 1, true)

		if hasFunc or hasAssign then
			local cleanLine = line:gsub("%-%-.*$", "") -- strip comments

			if hasAssign then
				-- declared local tables (real table literals only: "X = {").
				-- "local X = SomeClass:derive()" or "X = X or {}" are NOT local
				-- tables - methods on them modify an external/shared class.
				for tblName in cleanLine:gmatch("([%w_]+)%s*=%s*%{") do
					declaredTables[tblName] = true
				end

				-- alias: local X = A.B.C (pure dotted assignment).
				-- This lets us detect that "function X:m()" and "function A.B.C:m()"
				-- written via different local names are the SAME target.
				local localName, rhs = cleanLine:match("^%s*local%s+([%w_]+)%s*=%s*([%w_.]+)%s*$")
				if localName and rhs and not rhs:find(":derive") then
					addAlias(localName, rhs)
				end

				-- alias to a required module: local X = require("path")
				local reqName, reqPath = cleanLine:match("^%s*local%s+([%w_]+)%s*=%s*require%s*[%(%s]*[\"']([^\"']+)[\"']")
				if reqName and reqPath then
					addAlias(reqName, "require:" .. reqPath)
				end

				-- hook pattern: local old = Class.method (resolve aliases too)
				for tblName, funcName in cleanLine:gmatch("local%s+[%w_]+%s*=%s*([%w_.]+)%.([%w_]+)") do
					savedOriginals[resolve(tblName) .. "." .. funcName] = true
				end

				-- pattern B: Class.method = function  (dotted names allowed)
				if hasFunc then
					for tblName, funcName in cleanLine:gmatch("([%w_.]+)%.([%w_]+)%s*=%s*function") do
						table.insert(modifiedFunctions, {
							className = tblName,
							methodName = funcName,
							separator = ".",
							line = lineNum
						})
					end
				end
			end

			-- pattern A: function Class:method(...)  (dotted names allowed)
			if hasFunc and not cleanLine:find("^%s*local%s+function") then
				for tblName, sep, funcName in cleanLine:gmatch("function%s+([%w_.]+)([:.])([%w_]+)%s*%(") do
					table.insert(modifiedFunctions, {
						className = tblName,
						methodName = funcName,
						separator = sep,
						line = lineNum
					})
				end
			end
		end

		line = reader:readLine()
	end
	reader:close()

	-- resolve aliases so that the same object referenced via different local
	-- names produces the same modification target
	for _, modData in ipairs(modifiedFunctions) do
		local resolved = resolve(modData.className)
		if resolved ~= modData.className then
			modData.alias = modData.className
			modData.className = resolved
		end
	end

	-- keep only modifications of external (not locally declared) tables
	local externalModifications = {}
	for _, modData in ipairs(modifiedFunctions) do
		if not declaredTables[modData.className] then
			local fullFuncKey = modData.className .. "." .. modData.methodName
			modData.isHook = (savedOriginals[fullFuncKey] == true)
			table.insert(externalModifications, modData)
		end
	end

	return externalModifications
end


--================================================
--      Public API
--================================================

-- Keep the existing ordered file array for UI compatibility, and expose each
-- file's modification targets by path as required by layer consumers.
local function indexFileTargets(data)
    for _, mod in pairs(data) do
        for _, file in ipairs(mod.files or {}) do mod.files[file] = {} end
        for _, change in ipairs(mod.modifications or {}) do
            if mod.files and mod.files[change.file] then
                table.insert(mod.files[change.file], change.fullTarget)
            end
        end
    end
end

--- Main entry point.
---@param modsList table list of mod list items (modList.items)
---@param opts table|nil { reread=bool, onProgress=func(cur,total), onComplete=func(data) }
---@return table self.data
function MLOS_ModsFiles:getData(modsList, opts)
	opts = opts or {}
	if not modsList then return self.data end

	-- 1. read cache file (once per session, or forced)
	if opts.reread == true or self.cache == nil then
		self.cache = self:readCache()
	end
	local cache = self.cache or {}

	local separator = getFileSeparator()
	local loadedDirs = getLoadedModDirs()

	self.data = {}
	self.notLoaded = {}
	self.staleMods = {}
	local queue = {} -- { {modId, relPath}, ... } files to parse

	-- 2. build per-mod data from cache + current state
	for i = 1, #modsList do
		local item = modsList[i].item
		if item then
			local modId = item.modId
			local dir = item.modInfo:getDir()
			dir = dir and dir:gsub("[\\/]", separator)
			local loadedFiles = dir and listLoadedModFiles(modId, dir, item.modInfo, loadedDirs) or {}
			local isLoaded = #loadedFiles > 0

			-- file list: for loaded mods the authoritative list comes from getLoadedLua(),
			-- for the rest (or when the loaded list is empty) - from disk
			local files
			if isLoaded then
				files = loadedFiles
				if #files == 0 then files = self:listModLuaFiles(modId) end
			else
				files = self:listModLuaFiles(modId)
			end

			local signature = getModSignature(modId, item.modInfo)
            local cached = cache[modId]
            if self.steamUnavailable and cached and cached.signature then
                local oldTime = cached.signature:match("|([^|]*)$")
                if oldTime then signature = signature:gsub("|[^|]*$", "|" .. oldTime) end
            end

			if #files == 0 then
				-- the mod has no lua files at all (textures/recipes/etc. only):
				-- nothing to analyse, so it is complete by definition
				self.data[modId] = {
					rootDir = dir,
					files = {},
					modifications = (cached and cached.modifications) or {},
					signature = signature,
					complete = true
				}
			else
				if not isLoaded then
					-- has lua files, but none of them are loaded in this session
					table.insert(self.notLoaded, modId)
				end

				local fresh = (cached ~= nil and cached.complete == true and cached.signature == signature)

				if fresh then
					-- cache is up to date: use it as is, no rescan needed
					self.data[modId] = {
						rootDir = cached.rootDir or dir,
						files = cached.files or files,
						modifications = cached.modifications or {},
						signature = signature,
						complete = true
					}
				else
					table.insert(self.staleMods, modId)
					self.data[modId] = {
						rootDir = dir,
						files = files,
						modifications = (cached and cached.modifications) or {},
						signature = signature,
						complete = false
					}
					-- contents are analysed only for loaded mods
					if isLoaded then
						for _, f in ipairs(files) do
							table.insert(queue, { modId = modId, relPath = f })
						end
					end
				end
			end
		end
	end

	-- 3. async analysis of stale (and loaded) mods, then update the cache file
	if #queue > 0 then
		self:startAsyncAnalysis(queue, opts.onProgress, function(result)
			for modId, d in pairs(result) do
				if self.data[modId] then
					self.data[modId].modifications = d.modifications
					self.data[modId].complete = not d.failed
				end
			end
            indexFileTargets(self.data)
			self:saveCache()
			if opts.onComplete then opts.onComplete(self.data) end
		end)
	else
		-- nothing to scan: everything came from the cache (or needs no analysis)
        indexFileTargets(self.data)
		if opts.onComplete then opts.onComplete(self.data) end
	end

	return self.data
end


-- Steam details are asynchronous. On failure reuse cached timestamps rather
-- than invalidating every entry; local signatures still detect obvious edits.
function MLOS_ModsFiles:queryAndGetData(modsList, opts)
    if self.tickHandler then Events.OnFETick.Remove(self.tickHandler); self.tickHandler = nil end
    self.isAnalyzing = false
    self.requestGeneration = (self.requestGeneration or 0) + 1
    local generation = self.requestGeneration
    local function finish(status, info)
        if generation ~= self.requestGeneration then return end
        self.workshopTimes = {}
        self.steamUnavailable = status ~= "Completed" or not info
        if not self.steamUnavailable then
            for i = 0, info:size() - 1 do
                local detail = info:get(i)
                self.workshopTimes[tostring(detail:getIDString())] = tostring(detail:getTimeUpdated())
            end
        end
        self:getData(modsList, opts)
    end
    if type(querySteamWorkshopItemDetails) ~= "function" or type(getSteamWorkshopItemIDs) ~= "function" then
        finish("NotCompleted")
        return
    end
    local ok, ids = pcall(getSteamWorkshopItemIDs)
    if not ok or not ids then finish("NotCompleted"); return end
    local sized, count = pcall(function() return ids:size() end)
    if sized and count == 0 then finish("NotCompleted"); return end
    local called = false
    local function callback(_, status, info)
        if status ~= "Completed" and status ~= "NotCompleted" then return end
        if called then return end
        called = true
        finish(status, info)
    end
    local success = pcall(querySteamWorkshopItemDetails, ids, callback, self)
    if not success and not called then called = true; finish("NotCompleted") end
end


---@return boolean true if some mods are enabled but not loaded in this Lua session
function MLOS_ModsFiles:hasNotLoadedMods()
	return not utils:tableIsEmpty(self.notLoaded)
end


--- Coroutine-based analysis: parses files in small batches per game tick so the UI does not freeze.
---@param queue table { {modId, relPath}, ... }
---@param onProgress function|nil function(current, total)
---@param onComplete function|nil function(result) result[modId] = { modifications = {...} }
function MLOS_ModsFiles:startAsyncAnalysis(queue, onProgress, onComplete)
    if self.tickHandler then Events.OnFETick.Remove(self.tickHandler); self.tickHandler = nil end
    self.isAnalyzing = false
	if not queue or #queue == 0 then
		if onComplete then onComplete({}) end
		return
	end

	self.isAnalyzing = true
	print("[MLOS] Starting files analysis, files in queue: " .. #queue)

	local result = {}
	for _, task in ipairs(queue) do
		result[task.modId] = result[task.modId] or { modifications = {} }
	end

	local worker = coroutine.create(function()
		local totalFiles = #queue
		self.progress = { current = 0, total = totalFiles }

		for i, task in ipairs(queue) do
			local funcsModified = parseFileFunctions(task.modId, task.relPath)

            if not funcsModified then result[task.modId].failed = true end
			if funcsModified and #funcsModified > 0 then
				local data = result[task.modId]
				for _, funcInfo in ipairs(funcsModified) do
					table.insert(data.modifications, {
						file = task.relPath,
						className = funcInfo.className,
						methodName = funcInfo.methodName,
						fullTarget = funcInfo.className .. (funcInfo.separator or ":") .. funcInfo.methodName,
						alias = funcInfo.alias,
						line = funcInfo.line,
						isHook = funcInfo.isHook -- true: safe hook, false: full overwrite
					})
				end
			end

			-- yield control back to the game every FILES_PER_FRAME files
			if i % FILES_PER_FRAME == 0 then
				self.progress.current = i
				if onProgress then onProgress(i, totalFiles) end
				coroutine.yield()
			end
		end

		self.progress.current = totalFiles
		if onProgress then onProgress(totalFiles, totalFiles) end
		if onComplete then onComplete(result) end
	end)

	local function onTickHandler()
		if coroutine.status(worker) ~= "dead" then
			local success, err = coroutine.resume(worker)
			if not success then
				print("[MLOS ERROR] Files analysis error: " .. tostring(err))
				self.isAnalyzing = false
				Events.OnFETick.Remove(onTickHandler)
                self.tickHandler = nil
                for _, mod in pairs(result) do mod.failed = true end
                if onComplete then onComplete(result) end
			end
		else
			self.isAnalyzing = false
			Events.OnFETick.Remove(onTickHandler)
		end
	end

    self.tickHandler = onTickHandler
	Events.OnFETick.Add(onTickHandler)
end


--- Synchronous analysis of all loaded files (used for debugging)
---@param modsList table
function MLOS_ModsFiles:analyzeFolders(modsList)
    local result = {}
    local paths = getLoadedModDirs()
    for _, row in ipairs(modsList or {}) do
        local item = row.item
        local dir = item and item.modInfo:getDir()
        if dir then
            for _, file in ipairs(listLoadedModFiles(item.modId, dir, item.modInfo, paths)) do
                local functions = parseFileFunctions(item.modId, file)
                for _, f in ipairs(functions or {}) do
                    result[item.modId] = result[item.modId] or {modifications={}}
                    table.insert(result[item.modId].modifications, {
                        file=file, className=f.className, methodName=f.methodName,
                        fullTarget=f.className .. (f.separator or ':') .. f.methodName,
                        line=f.line, isHook=f.isHook, alias=f.alias
                    })
                end
            end
        end
    end
    return result
end


return MLOS_ModsFiles
