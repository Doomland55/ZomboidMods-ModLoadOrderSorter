---
--- Layer "ModsFiles": collects the list of lua files of every enabled mod and
--- analyses them for overwritten/hooked functions (see ModsFilesParser).
---
--- One pipeline handles every mod (MLOS_ModsFiles:load):
---   1. read the cache file (modsFilesCache.txt) once per session or on reread;
---   2. ask Steam for workshop update timestamps (part of the cache signature);
---   3. per mod: take the file list and contents from the optional ZombieBuddy
---      bridge (any enabled mod can be read) or, without it, from the lua files
---      loaded in this session; parse only when the cache entry is not fresh;
---   4. save the cache.
--- Enabled mods that could not be analysed are reported via self.notLoaded.
---
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local Parser = require('REfRigERatoR_ModLoadOrderSorter/Layers/ModsFilesParser')

local cacheFileExists = cacheFileExists
local listFilesInModDirectory = listFilesInModDirectory

local CACHE_FILE = "modsFilesCache.txt"
local LUA_DIR = "media/lua"
local STEAM_TIMEOUT_MS = 30000 -- how long to wait for the workshop details before using cached timestamps

local MLOS_ModsFiles = {}
MLOS_ModsFiles.data = {}          -- data[modId] = { rootDir, files={...}, modifications={...}, signature, fsSignature, complete }
MLOS_ModsFiles.cache = nil        -- raw cache read from file
MLOS_ModsFiles.notLoaded = {}     -- modIds whose analysis is incomplete (not loaded in this session / unreadable)
MLOS_ModsFiles.staleMods = {}     -- modIds that were (re)scanned in the last run
MLOS_ModsFiles.workshopTimes = {} -- workshop id -> update timestamp from the last Steam answer


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


--- Paths of all lua files loaded in this Lua session, with forward slashes.
---@return table
local function getLoadedLuaPaths()
    local paths = {}
    for i = 0, getLoadedLuaCount() - 1 do
        local path = getLoadedLua(i)
        if path then paths[#paths + 1] = path:gsub("\\", "/") end
    end
    return paths
end

--- Lua files of one mod among the loaded ones, relative to its version/common root.
local function listLoadedModFiles(modId, dir, modInfo, paths)
    local result, seen = {}, {}
    local roots = {dir}
    local ok, version = pcall(function() return modInfo:getVersionDir() end)
    if ok and version then roots[#roots + 1] = version end
    local commonOK, common = pcall(function() return modInfo:getCommonDir() end)
    if commonOK and common then roots[#roots + 1] = common end
    for _, path in ipairs(paths or getLoadedLuaPaths()) do
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
	if data.fsSignature then table.insert(lines, "fssignature=" .. data.fsSignature) end
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
	elseif key == "fssignature" then
		addTo.fsSignature = value
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
--      Steam
--================================================

--- Workshop update timestamps by workshop id. Yields until Steam answers or the
--- timeout passes; returns nil when there is no usable answer.
---@return table|nil
local function fetchWorkshopTimes(ctx)
    if type(querySteamWorkshopItemDetails) ~= "function" or type(getSteamWorkshopItemIDs) ~= "function" then return nil end
    local ok, ids = pcall(getSteamWorkshopItemIDs)
    if not ok or not ids then return nil end
    local sized, count = pcall(function() return ids:size() end)
    if sized and count == 0 then return nil end

    -- The game calls back with (arg, "Completed", details) or (arg, "NotCompleted").
    local status, details
    local function onDetails(_, queryStatus, info)
        if status == nil and (queryStatus == "Completed" or queryStatus == "NotCompleted") then
            status, details = queryStatus, info
        end
    end
    if not pcall(querySteamWorkshopItemDetails, ids, onDetails, MLOS_ModsFiles) then return nil end

    local deadline = getTimestampMs() + STEAM_TIMEOUT_MS
    while status == nil and getTimestampMs() < deadline do ctx:wait() end
    if status ~= "Completed" or not details then return nil end

    local times = {}
    for i = 0, details:size() - 1 do
        local detail = details:get(i)
        times[tostring(detail:getIDString())] = tostring(detail:getTimeUpdated())
    end
    return times
end


--================================================
--      ZombieBuddy bridge
--================================================

local function buddyAvailable()
    return type(MLOS_BuddyBegin) == "function" and type(MLOS_BuddyState) == "function"
        and type(MLOS_BuddyCount) == "function" and type(MLOS_BuddyPath) == "function"
        and type(MLOS_BuddySource) == "function" and type(MLOS_BuddyFingerprint) == "function"
        and type(MLOS_BuddyRelease) == "function"
end

function MLOS_ModsFiles:releaseBuddyJob()
    if self.buddyJob then
        pcall(MLOS_BuddyRelease, self.buddyJob)
        self.buddyJob = nil
    end
end

--- Starts the Java scan of one mod and yields until it is finished. One mod at
--- a time keeps the bridge snapshot bounded.
---@return table|nil { files, fingerprint, read = function(index) } or nil when the bridge failed for this mod
function MLOS_ModsFiles:openBuddySnapshot(ctx, modId)
    local ok, job = pcall(MLOS_BuddyBegin, modId)
    if not ok or not job then return nil end
    self.buddyJob = job

    local state
    repeat
        ok, state = pcall(MLOS_BuddyState, job)
        if ok and state == "pending" then ctx:wait() end
    until not ok or state ~= "pending"
    if not ok or state ~= "ready" then return nil end

    local snapshot = { files = {} }
    local valid = pcall(function()
        local count = MLOS_BuddyCount(job)
        snapshot.fingerprint = MLOS_BuddyFingerprint(job)
        if type(count) ~= "number" or count < 0 or type(snapshot.fingerprint) ~= "string" then
            error("invalid bridge result for " .. tostring(modId))
        end
        for n = 0, count - 1 do
            local path = MLOS_BuddyPath(job, n)
            if type(path) ~= "string" then error("invalid bridge path") end
            snapshot.files[n + 1] = path
        end
    end)
    if not valid then return nil end

    function snapshot.read(index)
        local read, source = pcall(MLOS_BuddySource, job, index - 1)
        return read and source or nil
    end
    return snapshot
end


--================================================
--      Scan of one mod
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

local function appendModifications(result, filename, functions)
    for _, funcInfo in ipairs(functions) do
        table.insert(result, {
            file = filename,
            className = funcInfo.className,
            methodName = funcInfo.methodName,
            fullTarget = funcInfo.className .. (funcInfo.separator or ":") .. funcInfo.methodName,
            alias = funcInfo.alias,
            line = funcInfo.line,
            isHook = funcInfo.isHook
        })
    end
end

--- Parses the given files of one mod, yielding between files when needed.
---@param readSource function|nil (index) -> file text; nil = read with getModFileReader
---@return table modifications
---@return boolean failed true when at least one file could not be read
local function parseFiles(ctx, modId, files, readSource)
    local modifications, failed = {}, false
    for index, path in ipairs(files) do
        local reader
        if readSource then
            local source = readSource(index)
            reader = type(source) == "string" and Parser.stringReader(source) or nil
        else
            local ok, fileReader = pcall(getModFileReader, modId, path, false)
            reader = ok and fileReader or nil
        end
        if reader then
            appendModifications(modifications, path, Parser.parse(reader))
        else
            failed = true
        end
        ctx:step()
    end
    return modifications, failed
end

-- Older caches have no filesystem fingerprint. They are reusable only if their
-- complete file list matches the bridge snapshot and the normal signature matches.
local function sameFiles(a, b)
    if not a then return #b == 0 end
    if #a ~= #b then return false end
    local seen = {}
    for _, name in ipairs(a) do seen[name] = (seen[name] or 0) + 1 end
    for _, name in ipairs(b) do
        if not seen[name] or seen[name] == 0 then return false end
        seen[name] = seen[name] - 1
    end
    return true
end

--- Signature for the cache check. Without a Steam answer the cached timestamp
--- is kept, so a failed query does not invalidate every cache entry.
function MLOS_ModsFiles:getSignature(item, cached)
    local signature = getModSignature(item.modId, item.modInfo)
    if self.steamUnavailable and cached and cached.signature then
        local oldTime = cached.signature:match("|([^|]*)$")
        if oldTime then signature = signature:gsub("|[^|]*$", "|" .. oldTime) end
    end
    return signature
end

--- Bridge mode: the Java worker listed and read every lua file of the mod,
--- whether it is loaded in this session or not.
---@return table|nil data of the mod; nil when a file could not be read (the caller falls back)
---@return boolean rescanned
local function scanSnapshot(ctx, item, cached, signature, snapshot)
    local files = snapshot.files
    local result = {
        rootDir = item.modInfo:getDir(), files = files, modifications = {},
        signature = signature, fsSignature = snapshot.fingerprint, complete = true
    }
    local fresh = cached ~= nil and cached.complete == true and cached.signature == signature
        and sameFiles(cached.files, files)
        and (not cached.fsSignature or cached.fsSignature == snapshot.fingerprint)
    if fresh then
        if #files > 0 then result.modifications = cached.modifications or {} end
        return result, false
    end

    local modifications, failed = parseFiles(ctx, item.modId, files, snapshot.read)
    if failed then return nil, true end
    result.modifications = modifications
    return result, true
end

--- Normal mode: files are known only for mods loaded in this Lua session, the
--- rest keeps whatever the cache has. `bridgeFailed` marks a mod whose bridge
--- scan failed - a failed disk enumeration never becomes a complete or empty mod.
---@return table data of the mod
---@return boolean incomplete the mod must be reported in notLoaded
---@return boolean rescanned
local function scanLoaded(ctx, item, cached, signature, loadedPaths, bridgeFailed)
    local modId = item.modId
    local dir = item.modInfo:getDir()
    dir = dir and dir:gsub("[\\/]", getFileSeparator())
    local loadedFiles = dir and listLoadedModFiles(modId, dir, item.modInfo, loadedPaths) or {}
    local isLoaded = #loadedFiles > 0
    -- for loaded mods the authoritative list comes from getLoadedLua(), for the rest - from disk
    local files = isLoaded and loadedFiles or MLOS_ModsFiles:listModLuaFiles(modId)
    local result = {
        rootDir = dir, files = files, modifications = (cached and cached.modifications) or {},
        signature = signature, complete = false
    }

    if #files == 0 and not bridgeFailed then
        -- the mod has no lua files at all (textures/recipes/etc. only):
        -- nothing to analyse, so it is complete by definition
        result.complete = true
        return result, false, false
    end

    if not bridgeFailed and cached ~= nil and cached.complete == true and cached.signature == signature then
        -- cache is up to date: use it as is, no rescan needed
        result.files = cached.files or files
        result.fsSignature = cached.fsSignature
        result.complete = true
        return result, not isLoaded, false
    end

    -- contents can be read only for loaded mods
    local failed = false
    if isLoaded then
        result.modifications, failed = parseFiles(ctx, modId, files)
        result.complete = not failed and not bridgeFailed
    end
    return result, not isLoaded or failed or bridgeFailed, true
end

---@return table data of the mod
---@return boolean incomplete
---@return boolean rescanned
function MLOS_ModsFiles:scanMod(ctx, item, loadedPaths, useBuddy)
    local cached = self.cache[item.modId]
    local signature = self:getSignature(item, cached)
    if not useBuddy then
        return scanLoaded(ctx, item, cached, signature, loadedPaths, false)
    end

    local result, rescanned
    local snapshot = self:openBuddySnapshot(ctx, item.modId)
    if snapshot then result, rescanned = scanSnapshot(ctx, item, cached, signature, snapshot) end
    self:releaseBuddyJob()
    if result then return result, false, rescanned end

    print("[MLOS] ZombieBuddy scan failed for " .. tostring(item.modId) .. "; using legacy data")
    return scanLoaded(ctx, item, cached, signature, loadedPaths, true)
end


--================================================
--      Layer API
--================================================

--- Layer entry point, see LayerManager.
function MLOS_ModsFiles:load(ctx)
    if ctx.reread or self.cache == nil then self.cache = self:readCache() end

    local times = fetchWorkshopTimes(ctx)
    self.steamUnavailable = times == nil
    self.workshopTimes = times or {}

    local loadedPaths = getLoadedLuaPaths()
    local useBuddy = buddyAvailable()
    local data, notLoaded, stale = {}, {}, {}
    for i, row in ipairs(ctx.mods) do
        local item = row.item
        if item then
            local result, incomplete, rescanned = self:scanMod(ctx, item, loadedPaths, useBuddy)
            data[item.modId] = result
            if incomplete then notLoaded[#notLoaded + 1] = item.modId end
            if rescanned then stale[#stale + 1] = item.modId end
        end
        ctx:step(i, #ctx.mods)
    end

    indexFileTargets(data)
    self.data, self.notLoaded, self.staleMods = data, notLoaded, stale
    self:saveCache()
end

--- Called by the manager when the analysis is interrupted or fails.
function MLOS_ModsFiles:cancel()
    self:releaseBuddyJob()
end

function MLOS_ModsFiles:getWarnings()
    if not self:hasNotLoadedMods() then return {} end
    return {{ severity = "WARNING", layer = "ModsFiles",
        title = getText("UI_MLOS_Warning_NotLoaded_Title"),
        message = getText("UI_MLOS_Warning_NotLoaded_Msg", table.concat(self.notLoaded, ", ")) }}
end

---@return boolean true if the analysis of some enabled mods is incomplete in this Lua session
function MLOS_ModsFiles:hasNotLoadedMods()
    return not utils:tableIsEmpty(self.notLoaded)
end


return MLOS_ModsFiles
