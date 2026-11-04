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

--- Cheap signature of a mod: mod.info version + number of lua files.
--- Used to detect changed mods without reading every file.
---@param modId string
---@return string
local function getModSignature(modId)
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

	return tostring(version) .. "|" .. tostring(count)
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
	local separator = getFileSeparator()
	local loadedDirs = {}
	local count = getLoadedLuaCount()
	for i = 0, count - 1 do
		local path = getLoadedLua(i)
		if path then
			local modDir = path:match("^(.-[\\/]mods[\\/][^\\/]+)")
			if modDir then
				loadedDirs[modDir:gsub("[\\/]", separator)] = true
			end
		end
	end
	return loadedDirs
end


--- List of actually loaded lua files (relative to the mod dir) for a loaded mod
---@param modId string
---@param dir string normalized mod root dir
---@return table
local function listLoadedModFiles(modId, dir)
	local separator = getFileSeparator()
	local result = {}
	local count = getLoadedLuaCount()
	for i = 0, count - 1 do
		local path = getLoadedLua(i)
		if path then
			local modDir, filePath = path:match("^(.-[\\/]mods[\\/][^\\/]+)[\\/].-[\\/](.*)$")
			if modDir and filePath then
				modDir = modDir:gsub("[\\/]", separator)
				if modDir == dir then
					table.insert(result, (filePath:gsub("[\\/]", separator)))
				end
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
			tostring(m.isHook == true)
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
		local file, target, lineNum, isHook = value:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
		if file then
			addTo.modifications = addTo.modifications or {}
			table.insert(addTo.modifications, {
				file = file,
				fullTarget = target,
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

	local declaredTables = {}
	local modifiedFunctions = {}
	local savedOriginals = {}

	local lineNum = 0
	local line = reader:readLine()

	while line ~= nil do
		lineNum = lineNum + 1

		-- fast pre-filter: a hook/overwrite always contains "function" or "="
		local hasFunc = line:find("function", 1, true)
		local hasAssign = line:find("=", 1, true)

		if hasFunc or hasAssign then
			local cleanLine = line:gsub("%-%-.*$", "") -- strip comments

			if hasAssign then
				-- declared local tables (not external classes)
				for tblName in cleanLine:gmatch("([%w_]+)%s*=%s*[{%w_:]+") do
					declaredTables[tblName] = true
				end

				-- hook pattern: local old = Class.method
				for tblName, funcName in cleanLine:gmatch("local%s+[%w_]+%s*=%s*([%w_]+)%.([%w_]+)") do
					savedOriginals[tblName .. "." .. funcName] = true
				end

				-- pattern B: Class.method = function
				if hasFunc then
					for tblName, funcName in cleanLine:gmatch("([%w_]+)%.([%w_]+)%s*=%s*function") do
						table.insert(modifiedFunctions, {
							className = tblName,
							methodName = funcName,
							separator = ".",
							line = lineNum
						})
					end
				end
			end

			-- pattern A: function Class:method(...)
			if hasFunc and not cleanLine:find("^%s*local%s+function") then
				for tblName, sep, funcName in cleanLine:gmatch("function%s+([%w_]+)([:.])([%w_]+)%s*%(") do
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
			local isLoaded = (dir ~= nil and loadedDirs[dir] == true)

			if not isLoaded then
				table.insert(self.notLoaded, modId)
			end

			local signature = getModSignature(modId)
			local cached = cache[modId]
			local fresh = (cached ~= nil and cached.complete == true and cached.signature == signature)

			if fresh then
				-- cache is up to date: use it as is, no rescan needed
				self.data[modId] = {
					rootDir = cached.rootDir or dir,
					files = cached.files or self:listModLuaFiles(modId),
					modifications = cached.modifications or {},
					signature = signature,
					complete = true
				}
			else
				table.insert(self.staleMods, modId)
				local files
				if isLoaded then
					files = listLoadedModFiles(modId, dir) -- authoritative list of loaded files
					for _, f in ipairs(files) do
						table.insert(queue, { modId = modId, relPath = f })
					end
				else
					-- not loaded: file list from disk only, contents are NOT analysed
					files = self:listModLuaFiles(modId)
				end
				self.data[modId] = {
					rootDir = dir,
					files = files,
					modifications = (cached and cached.modifications) or {},
					signature = signature,
					complete = false
				}
			end
		end
	end

	-- 3. async analysis of stale (and loaded) mods, then update the cache file
	if #queue > 0 then
		self:startAsyncAnalysis(queue, opts.onProgress, function(result)
			for modId, d in pairs(result) do
				if self.data[modId] then
					self.data[modId].modifications = d.modifications
					self.data[modId].complete = true
				end
			end
			self:saveCache()
			if opts.onComplete then opts.onComplete(self.data) end
		end)
	else
		-- nothing to scan: everything came from the cache
		for modId, d in pairs(self.data) do
			if utils:contains(self.staleMods, modId) and loadedDirs[d.rootDir] then
				d.complete = true
			end
		end
		if opts.onComplete then opts.onComplete(self.data) end
	end

	return self.data
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
	if self.isAnalyzing then
		print("[MLOS] Files analysis is already running, skipping")
		return
	end
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

			if funcsModified and #funcsModified > 0 then
				local data = result[task.modId]
				for _, funcInfo in ipairs(funcsModified) do
					table.insert(data.modifications, {
						file = task.relPath,
						className = funcInfo.className,
						methodName = funcInfo.methodName,
						fullTarget = funcInfo.className .. ":" .. funcInfo.methodName,
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
			end
		else
			self.isAnalyzing = false
			Events.OnFETick.Remove(onTickHandler)
		end
	end

	Events.OnFETick.Add(onTickHandler)
end


--- Synchronous analysis of all loaded files (used for debugging)
---@param modsList table
function MLOS_ModsFiles:analyzeFolders(modsList)
	if not modsList then return {} end
	local queue = {}
	local separator = getFileSeparator()
	local loadedDirs = getLoadedModDirs()
	local dirMap = {}

	for i = 1, #modsList do
		local item = modsList[i].item
		if item then
			local dir = item.modInfo:getDir()
			dir = dir and dir:gsub("[\\/]", separator)
			if dir and loadedDirs[dir] then
				dirMap[dir] = item.modId
			end
		end
	end

	local count = getLoadedLuaCount()
	for i = 0, count - 1 do
		local path = getLoadedLua(i)
		if path then
			local modDir, filePath = path:match("^(.-[\\/]mods[\\/][^\\/]+)[\\/].-[\\/](.*)$")
			if modDir and filePath then
				modDir = modDir:gsub("[\\/]", separator)
				if dirMap[modDir] then
					table.insert(queue, { modId = dirMap[modDir], relPath = filePath:gsub("[\\/]", separator) })
				end
			end
		end
	end

	local result = {}
	for _, task in ipairs(queue) do
		local funcsModified = parseFileFunctions(task.modId, task.relPath)
		if funcsModified and #funcsModified > 0 then
			result[task.modId] = result[task.modId] or { modifications = {} }
			for _, funcInfo in ipairs(funcsModified) do
				table.insert(result[task.modId].modifications, {
					file = task.relPath,
					className = funcInfo.className,
					methodName = funcInfo.methodName,
					fullTarget = funcInfo.className .. ":" .. funcInfo.methodName,
					line = funcInfo.line,
					isHook = funcInfo.isHook
				})
			end
		end
	end
	return result
end


return MLOS_ModsFiles
