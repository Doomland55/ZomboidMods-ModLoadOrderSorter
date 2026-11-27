---
--- Layer "ModsFiles": collects the list of lua files of every enabled mod and
--- analyses them for overwritten/hooked functions (see ModsFilesParser).
---
--- One pipeline handles every mod (MLOS_ModsFiles:load):
---   1. read the cache file (modsFilesCache.txt) once per session or on reread;
---   2. ask Steam for active Workshop items' update timestamps;
---   3. per mod: obtain the file list from the optional ZombieBuddy bridge
---      and read via PZ, or, without the bridge, use the Lua files
---      loaded in this session; scan only when the cache entry is not fresh;
---   4. save the cache.
--- Enabled mods that could not be analysed are reported via self.notLoaded.
---
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local CM = require("REfRigERatoR_ModLoadOrderSorter/Core/CorutineManager.lua")
local Parser = require('REfRigERatoR_ModLoadOrderSorter/Layers/ModsFilesParser')

local cacheFileExists = cacheFileExists

local CACHE_FILE = "modsFilesCache.txt"
local STEAM_TIMEOUT_MS = 10000 -- how long to wait for the workshop details before using cached timestamps


local MLOS_ModsFiles = {}
MLOS_ModsFiles.data = {}          -- active mod data keyed by modId
MLOS_ModsFiles.cache = {}
MLOS_ModsFiles.notLoaded = {}     -- modIds whose analysis is incomplete (not loaded in this session / unreadable)
MLOS_ModsFiles.workshopTimes = {} -- workshop id -> update timestamp for this Lua session
MLOS_ModsFiles.checkedWorkshopIds = {} -- queried IDs, including missing/failed results
MLOS_ModsFiles.buddyFailures = {} -- failed attempts for mods without a cache entry


--================================================
--      Cache helpers
--================================================

--- Resolve Workshop IDs from the ModInfo object used by the load-order UI.
local function workshopId(item)
    local ok, id = pcall(utils.getWorkshopId, utils, item.modInfo)
    if ok and id and tostring(id):match("^%d+$") then return tostring(id) end
end

--- Paths of all lua files loaded in this Lua session, with forward slashes.
---@return table
local function getLoadedLuaPaths()
    local paths = {}
    for i = 0, getLoadedLuaCount() - 1 do
        local path = getLoadedLua(i)
        if path then paths[#paths + 1] = path:gsub("\\", "/") end
        if i % 128 == 0 then CM.checkpoint() end
    end
    return paths
end

--- Lua files of one mod among the loaded ones, relative to its version/common root.
local function listLoadedModFiles(dir, modInfo, paths)
    local result, seen = {}, {}
    local roots = { dir }
    local ok, version = pcall(function() return modInfo:getVersionDir() end)
    if ok and version then roots[#roots + 1] = version end
    local commonOK, common = pcall(function() return modInfo:getCommonDir() end)
    if commonOK and common then roots[#roots + 1] = common end
    for i, root in ipairs(roots) do roots[i] = root:gsub("\\", "/"):gsub("/$", "") end
    for i, path in ipairs(paths) do
        for _, root in ipairs(roots) do
            if path:sub(1, #root + 1) == root .. "/" then
                -- getModFileReader expects paths relative to a mod version or common root.
                local rel = path:match("(media/lua/.*)$")
                if rel and not seen[rel] then
                    seen[rel] = true; result[#result + 1] = rel
                end
                break
            end
        end
        if i % 128 == 0 then CM.checkpoint() end
    end
    return result
end


-- #region ========= Cache file IO ================

---@param modId string
---@param data table
---@return string
local function cacheDataToText(modId, data)
    local lines = {}
    table.insert(lines, "complete=" .. tostring(data.complete == true))
    if data.updatedTime then table.insert(lines, "updatedTime=" .. tostring(data.updatedTime)) end
    if data.lastAnalyzedTime then table.insert(lines, "lastAnalyzedTime=" .. tostring(data.lastAnalyzedTime)) end
    if data.buddyFailedAt then table.insert(lines, "buddyFailedAt=" .. tostring(data.buddyFailedAt)) end
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
    if key == "signature" or key == "fssignature" then
        MLOS_ModsFiles.cacheNeedsMigration = true
    elseif key == "updatedtime" then
        addTo.updatedTime = tonumber(value)
    elseif key == "lastanalyzedtime" then
        addTo.lastAnalyzedTime = tonumber(value)
    elseif key == "buddyfailedat" then
        addTo.buddyFailedAt = tonumber(value)
    elseif key == "complete" then
        addTo.complete = (value == "true")
    elseif key == "files" then
        addTo.files = utils:splitStringBySeparator(value)
    elseif key == "mod" then
        -- file|fullTarget|line|isHook[|alias] - alias field is optional (old caches)
        local file, target, lineNum, isHook, alias = value:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|?(.*)$")
        if file then
            local className, methodName = target:match("^(.*)[:.]([%w_]+)$")
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
    local path = utils:joinpath(core.MLOS_LAYERS_ROOT, CACHE_FILE)
    print("[MLOS] Saving mods files cache: " .. path)
    return core:saveTxtFile(path, self.cache, cacheDataToText)
end

--- Reads the cache file
---@return table
function MLOS_ModsFiles:readCache()
    local path = utils:joinpath(core.MLOS_LAYERS_ROOT, CACHE_FILE)
    if cacheFileExists(path) ~= true then return {} end
    print("[MLOS] Reading mods files cache: " .. path)
    local cache = core:readTxtFile(path, cacheLineToData)
    if not cache then error("Cannot read existing cache " .. path) end
    return cache
end
-- #endregion


-- #region ========= Steam update timestamps =========

--- Workshop update timestamps by workshop id. Yields until Steam answers or the
--- timeout passes; returns nil when there is no usable answer.
---@return table|nil
local function fetchWorkshopTimes(workshopIds)
    if type(querySteamWorkshopItemDetails) ~= "function" or type(getSteamWorkshopItemIDs) ~= "function" then return nil end
    -- B42 returns a fresh Java ArrayList; reuse it to pass only active IDs.
    local ok, ids = pcall(getSteamWorkshopItemIDs)
    if not ok or not ids then return nil end
    local built = pcall(function()
        ids:clear()
        for _, id in ipairs(workshopIds) do ids:add(id) end
    end)
    if not built then return nil end
    if ids:size() == 0 then return {} end

    local status, details
    local function onDetails(queryStatus, info)
        if status ~= "Completed" then status, details = queryStatus, info end
    end
    -- arg1 is nil, so the callback receives (status, details).
    ok = pcall(querySteamWorkshopItemDetails, ids, onDetails, nil)
    if not ok then return nil end
    CM.setProgress(0.1, "[ModsFiles] fetching workshop times ...")
    local finished = CM.waitUntil(function() return status == "Completed" end,
        { timeoutMs = STEAM_TIMEOUT_MS, intervalMs = 20 })
    if not finished or status ~= "Completed" or not details then return nil end

    local times = {}
    ok = pcall(function()
        for i = 0, details:size() - 1 do
            local detail = details:get(i)
            local time = tonumber(detail:getTimeUpdated())
            if time and time > 0 then times[tostring(detail:getIDString())] = time end
        end
    end)
    return ok and times or nil
end

--- Query each Workshop ID at most once per Lua session. Previously unavailable
--- IDs stay unknown until the next session; newly activated IDs are queried.
local function updateWorkshopTimes(self, modList)
    if self.fetchInProgress then
        local finished = CM.waitUntil(function() return not self.fetchInProgress end,
            { timeoutMs = STEAM_TIMEOUT_MS + 1000 })
        if not finished then return end
    end
    local ids, seen = {}, {}
    for _, row in ipairs(modList) do
        local id = row.item and workshopId(row.item)
        if id and not self.checkedWorkshopIds[id] and not seen[id] then
            ids[#ids + 1] = id
            seen[id] = true
        end
    end
    if #ids == 0 then return end

    self.fetchInProgress = true
    self.fetchOwner = type(CM.currentTask) == "function" and CM.currentTask() or nil
    local times = fetchWorkshopTimes(ids)
    self.fetchInProgress = false
    self.fetchOwner = nil
    for _, id in ipairs(ids) do self.checkedWorkshopIds[id] = true end
    if times then
        for _, id in ipairs(ids) do self.workshopTimes[id] = times[id] end
    end
end

-- #endregion

-- #region ========== ZombieBuddy bridge =========

local function buddyAvailable()
    return type(MLOS_listModFiles) == "function"
end

-- Convert root-relative Java paths to paths accepted by getModFileReader.
-- B42 looks in the version directory before common for duplicate paths.
local function modRootPrefix(root, child)
    if not root or not child then return nil end
    root = root:gsub("\\", "/"):gsub("/$", "")
    child = child:gsub("\\", "/"):gsub("/$", "")
    if child:sub(1, #root + 1) ~= root .. "/" then return nil end
    local prefix = child:sub(#root + 2)
    if prefix == "" or prefix:find("/", 1, true) or prefix == ".." then return nil end
    return prefix .. "/"
end

local function listBuddyLuaFiles(item)
    local ok, entries = pcall(MLOS_listModFiles, item.modId)
    if not ok or not entries then return nil end
    local info = item.modInfo
    local version = modRootPrefix(info:getDir(), info:getVersionDir())
    local common = modRootPrefix(info:getDir(), info:getCommonDir())
    if not version or not common then return nil end
    local files, seen = {}, {}
    local read, count = pcall(function() return entries:size() end)
    if not read or type(count) ~= "number" or count < 0 then return nil end
    for i = 0, count - 1 do
        local valid, path = pcall(function() return entries:get(i) end)
        if not valid or type(path) ~= "string" or path:find("\\", 1, true)
            or path:find("\n", 1, true) or path:find("\r", 1, true)
            or path:find("/../", 1, true) or path:sub(1, 1) == "/" then return nil end
        local relative
        if path:sub(1, #version) == version then relative = path:sub(#version + 1)
        elseif path:sub(1, #common) == common then relative = path:sub(#common + 1) end
        if relative and relative:sub(1, 10) == "media/lua/" and relative:lower():sub(-4) == ".lua" then
            -- The cache format uses commas and pipes as delimiters.
            if relative:find(",", 1, true) or relative:find("|", 1, true) then return nil end
            if not seen[relative] then seen[relative] = true; files[#files + 1] = relative end
        end
        CM.checkpoint()
    end
    table.sort(files)
    return files
end


--================================================
--      Scan of one mod
--================================================

-- Keep the existing ordered file array for UI compatibility, and expose each
-- file's modification targets by path as required by layer consumers.
local function indexFileTargets(data)
    for _, mod in pairs(data) do
        for i, file in ipairs(mod.files or {}) do
            mod.files[file] = {}
            if i % 128 == 0 then CM.checkpoint() end
        end
        for i, change in ipairs(mod.modifications or {}) do
            if mod.files and mod.files[change.file] then
                table.insert(mod.files[change.file], change.fullTarget)
            end
            if i % 128 == 0 then CM.checkpoint() end
        end
    end
end

local function appendModifications(result, filename, functions)
    for i, funcInfo in ipairs(functions) do
        table.insert(result, {
            file = filename,
            className = funcInfo.className,
            methodName = funcInfo.methodName,
            fullTarget = funcInfo.className .. (funcInfo.separator or ":") .. funcInfo.methodName,
            alias = funcInfo.alias,
            line = funcInfo.line,
            isHook = funcInfo.isHook
        })
        if i % 128 == 0 then CM.checkpoint() end
    end
end

--- A nested coroutine provides an error boundary without yielding through pcall.
--- Parser.parse periodically yields; the outer task enforces the frame budget.
local function parseReader(reader)
    local task = type(CM.currentTask) == "function" and CM.currentTask() or nil
    if task then task.mlosReader = reader end
    local worker = coroutine.create(function()
        return Parser.parse(reader, function() coroutine.yield() end)
    end)
    while true do
        local ok, result = coroutine.resume(worker)
        if not ok then
            pcall(function() reader:close() end)
            if task then task.mlosReader = nil end
            return nil, result
        end
        if coroutine.status(worker) == "dead" then
            if task then task.mlosReader = nil end
            return result
        end
        CM.checkpoint()
    end
end

--- Parse the mod's files, yielding between files and within large files.
local function parseFiles(modId, files)
    local modifications, failed = {}, false
    for _, path in ipairs(files) do
        local ok, reader = pcall(getModFileReader, modId, path, false)
        if ok and reader then
            local parsed, err = parseReader(reader)
            if parsed then
                appendModifications(modifications, path, parsed)
            else
                print("[MLOS] Cannot parse " .. tostring(modId) .. "/" .. tostring(path) .. ": " .. tostring(err))
                failed = true
            end
        else
            failed = true
        end
        CM.checkpoint()
    end
    return modifications, failed
end

local MAX_CACHE_AGE = 24 * 60 * 60

-- Never call the scanner to check freshness: even enumerating all files can be
-- expensive. Unknown/old cache formats are rescanned once.
local function needsScan(cached, updatedTime, now)
    if not cached or not cached.lastAnalyzedTime then return true end
    if updatedTime then
        return not cached.updatedTime or updatedTime > cached.updatedTime
    end
    local age = now - cached.lastAnalyzedTime
    return age < 0 or age > MAX_CACHE_AGE
end

-- isModActive checks the game's loaded mod IDs, not the UI's current selection.
local function isLoadedInSession(item)
    if type(isModActive) ~= "function" then return false end
    local ok, loaded = pcall(isModActive, item.modInfo)
    return ok and loaded == true
end

--- A loaded-file snapshot may omit shadowed or unexecuted files, so it is not
--- marked complete, even if the mod itself is loaded in the current session.
local function scanLoaded(item, getLoadedPaths, isLoaded)
    if not isLoaded then return nil end
    local modInfo = item.modInfo
    local dir = modInfo:getDir()
    if not dir or dir == "" then return nil end
    local files = listLoadedModFiles(dir, modInfo, getLoadedPaths())
    local changes, failed = parseFiles(item.modId, files)
    if failed then return nil end
    return { rootDir = dir, files = files, modifications = changes, complete = false }
end

function MLOS_ModsFiles:scanMod(item, getLoadedPaths, useBuddy, isLoaded)
    if useBuddy then
        local files = listBuddyLuaFiles(item)
        if files then
            local changes, failed = parseFiles(item.modId, files)
            if not failed then
                return { files = files, modifications = changes, complete = true }, false
            end
        end
        print("[MLOS] ZombieBuddy scan failed for " .. tostring(item.modId) .. "; using loaded files")
        return scanLoaded(item, getLoadedPaths, isLoaded), true
    end
    return scanLoaded(item, getLoadedPaths, isLoaded), false
end

--================================================
--      Layer API
--================================================
local function cleanupTask(self, task)
    if task.mlosReader then
        pcall(function() task.mlosReader:close() end)
        task.mlosReader = nil
    end
    if self.fetchOwner == task then
        self.fetchInProgress, self.fetchOwner = false, nil
    end
end

function MLOS_ModsFiles:getData(modList, reread)
    return CM.run(self.load, {
        name = "ModsFiles", args = { self, modList, reread },
        onStart = function()
            self.error = nil
            CM:setProgress(0, "[ModsFiles] processing ...")
        end,
        onFinish = function() CM:setProgress(1, "[ModsFiles] finished") end,
        onError = function(task, err)
            cleanupTask(self, task)
            self.error = tostring(err)
            print("[MLOS] ModsFiles analysis failed: " .. self.error)
        end,
        onCancel = function(task) cleanupTask(self, task) end
    })
end

--- Load the whole persistent cache before requesting Steam. Only active mods
--- are exposed in data; inactive entries stay in cache and are written back.
function MLOS_ModsFiles:load(modList, reread)
    if not self.cacheLoaded or reread then
        local ok, cache = pcall(self.readCache, self)
        if not ok then error("[MLOS] Cannot read ModsFiles cache: " .. tostring(cache)) end
        self.cache = cache or {}
        self.cacheLoaded = true
    end
    updateWorkshopTimes(self, modList)
    local now = getTimestamp()
    local loadedPaths
    local function getLoadedPaths()
        if not loadedPaths then loadedPaths = getLoadedLuaPaths() end
        return loadedPaths
    end
    local useBuddy = buddyAvailable()
    local data, notLoaded = {}, {}
    for i, row in ipairs(modList) do
        local item = row.item
        if item and item.modId and item.modInfo then
            local id = item.modId
            local isLoaded = isLoadedInSession(item)
            local cached = self.cache[id]
            local wid = workshopId(item)
            local updatedTime = wid and self.workshopTimes[wid] or nil
            local result = cached
            local failedAt = (cached and cached.buddyFailedAt) or self.buddyFailures[id]
            local failureAge = failedAt and (now - failedAt)
            local canTryBuddy = useBuddy and (reread or not failureAge or failureAge < 0 or failureAge > MAX_CACHE_AGE)
            local needsUpdate = needsScan(cached, updatedTime, now)
            local needsUpgrade = canTryBuddy and cached and cached.complete ~= true
            -- A stale complete snapshot must not be replaced by a partial fallback.
            -- While Buddy is cooling down, keep the old data and warn instead of
            -- repeatedly parsing the same partial files on each screen opening.
            local deferred = needsUpdate and useBuddy and not canTryBuddy and cached and cached.complete
            if deferred then
                notLoaded[#notLoaded + 1] = id
            elseif needsUpdate or needsUpgrade then
                local scanned, buddyFailed = self:scanMod(item, getLoadedPaths, canTryBuddy, isLoaded)
                if buddyFailed then
                    failedAt = getTimestamp()
                    self.buddyFailures[id] = failedAt
                    if cached then cached.buddyFailedAt = failedAt; self.cacheDirty = true end
                elseif canTryBuddy and scanned and scanned.complete then
                    failedAt = nil
                    self.buddyFailures[id] = nil
                end
                if scanned and cached and cached.complete and not scanned.complete then
                    -- Do not replace a complete snapshot with a partial one.
                    scanned = nil
                end
                if scanned then
                    scanned.lastAnalyzedTime = getTimestamp()
                    scanned.buddyFailedAt = failedAt
                    -- Without Steam retain the old comparison point, not a guessed one.
                    scanned.updatedTime = updatedTime or (cached and cached.updatedTime)
                    self.cache[id] = scanned
                    result = scanned
                    self.cacheDirty = true
                else
                    print("[MLOS] Could not analyse " .. tostring(id) .. "; preserving cache")
                    notLoaded[#notLoaded + 1] = id
                end
            end
            if result then
                data[id] = result
                if not result.complete and not isLoaded and notLoaded[#notLoaded] ~= id then
                    notLoaded[#notLoaded + 1] = id
                end
            end
        end
        CM.checkpoint(i / math.max(#modList, 1), "[ModsFiles] " .. tostring(i) .. "/" .. tostring(#modList))
    end
    indexFileTargets(data)
    self.data, self.notLoaded = data, notLoaded
    if self.cacheDirty or self.cacheNeedsMigration then
        local ok, saved = pcall(self.saveCache, self)
        if not ok or not saved then error("[MLOS] Failed to save ModsFiles cache: " .. tostring(saved)) end
        self.cacheDirty, self.cacheNeedsMigration = false, false
    end
end


function MLOS_ModsFiles:getWarnings()
    if not self:hasNotLoadedMods() then return {} end
    return { {
        severity = "WARNING",
        layer = "ModsFiles",
        title = getText("UI_MLOS_Warning_NotLoaded_Title"),
        message = getText("UI_MLOS_Warning_NotLoaded_Msg", table.concat(self.notLoaded, ", "))
    } }
end

---@return boolean true if a selected mod is not loaded or analysis failed
function MLOS_ModsFiles:hasNotLoadedMods()
    return not utils:tableIsEmpty(self.notLoaded)
end

return MLOS_ModsFiles
