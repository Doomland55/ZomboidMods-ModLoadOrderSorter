local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')


local cacheFile = "modsFilesCache.txt"
local MLOS_ModsFiles = {}
MLOS_ModsFiles.data = {} -- data[modId] = {file1: {overidedClousureName1, overidedClousureName2, ...}}

---@return table
function MLOS_ModsFiles:getData(modList, reread)
	if utils:tableIsEmpty(self.data) or reread == true then
		-- self.data = self:analyzeFolders()
        self:startAsyncAnalysis(modList, nil, function(result) utils:MergeTablesDedup(self.data, result) end)
	end
	return self.data
end



-- function MLOS_ModsFiles:saveBinaryCache(cacheData)
--     local out = getFileOutput("mlos_cache.bin")
--     if not out then return end

--     -- Считаем количество модов
--     local modCount = 0
--     for _ in pairs(cacheData) do modCount = modCount + 1 end
--     out:writeInt(modCount)

--     for modId, data in pairs(cacheData) do
--         out:writeUTF(modId) -- Записываем ID мода
        
--         local modsList = data.modifications or {}
--         out:writeInt(#modsList) -- Сколько функций он модифицирует

--         for _, item in ipairs(modsList) do
--             out:writeUTF(item.file or "")
--             out:writeUTF(item.className or "")
--             out:writeUTF(item.methodName or "")
--             out:writeBoolean(item.isHook == true) -- хук или жесткий оверрайт
--         end
--     end

--     out:flush()
--     out:close()
--     print("[MLOS] Бинарный кэш успешно записан!")
-- end


-- function MLOS_ModsFiles:loadBinaryCache()
--     local input = getFileInput("mlos_cache.bin")
--     if not input then return nil end

--     local cacheData = {}
--     local modCount = input:readInt() -- Читаем число модов

--     for i = 1, modCount do
--         local modId = input:readUTF()
--         local funcCount = input:readInt()
        
--         cacheData[modId] = { modifications = {} }

--         for j = 1, funcCount do
--             local file = input:readUTF()
--             local className = input:readUTF()
--             local methodName = input:readUTF()
--             local isHook = input:readBoolean()

--             table.insert(cacheData[modId].modifications, {
--                 file = file,
--                 className = className,
--                 methodName = methodName,
--                 isHook = isHook
--             })
--         end
--     end

--     input:close()
--     print("[MLOS] Бинарный кэш мгновенно загружен!")
--     return cacheData
-- end




---@param srData table|nil optional
---@param fileName string|nil optional
function MLOS_ModsFiles:saveModFilesCache(srData, fileName)
	local rulesFile = core.MLOS_ROOT .. "/" .. (fileName or RULES_NAME)
	print("MLOS - Saving sorting rules: ", rulesFile)
	core:saveTxtFile(rulesFile, srData or self.data or {}, function(...) return self:getSRDataText(...) end)
end


---@return table rules sorting rules from file
function MLOS_ModsFiles:readModFilesCache(fileName)
	local rulesName = fileName or RULES_NAME
	local rulesFile = core.MLOS_ROOT .. "/" .. rulesName
	local result = nil
	print("MLOS - Reading sorting rules: ", rulesFile)
	-- support auto moving sorting rules to the separate mod folder. will be removed after some game versions (initially added for b42.19.0)

	result = core:readTxtFile(rulesFile, function(addTo, line) return core:getDataFromString(line, addTo) end)
	self:doRulesBackup()
	return result or {}
end





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

        -- ОПТИМИЗАЦИЯ: Быстрый отсев 85-90% строк до применения регулярок!
        -- Если в строке нет ни "=" ни "function", там физически не может быть хука
        local hasFunc = line:find("function", 1, true)
        local hasAssign = line:find("=", 1, true)

        if hasFunc or hasAssign then
            -- Удаляем комментарии только если строка прошла предварительный фильтр
            local cleanLine = line:gsub("%-%-.*$", "")

            -- 1. Детект объявления классов (только если есть '=')
            if hasAssign then
                for tblName in cleanLine:gmatch("([%w_]+)%s*=%s*[{%w_:]+") do
                    declaredTables[tblName] = true
                end

                -- 2. Детект хуков: local old = Class.method
                for tblName, funcName in cleanLine:gmatch("local%s+[%w_]+%s*=%s*([%w_]+)%.([%w_]+)") do
                    savedOriginals[tblName .. "." .. funcName] = true
                end

                -- 3. Паттерн Б: Class.method = function
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

            -- 4. Паттерн А: function Class:method
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

    -- Фильтрация
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


local function fixSeparator(path, separator)
    if not path then return nil end
    return path:gsub("[\\/]", separator)
end


function MLOS_ModsFiles:analyzeFolders(modsList)
	if not modsList then  return {} end

	local separator = getFileSeparator()
	local result = {}

	local dirMap = {}
	for i=1, #modsList do
		local item = modsList[i].item
		if item then
			local modId = item.modId
			local dir = item.modInfo:getDir()
			dir = fixSeparator(dir, separator)

			if dir ~= nil then
				result[modId] = {
					rootDir = dir,
					files = {},
					modifications = {}
				}
				dirMap[dir] = result[modId].files
			end
		end
	end

	local loadedLuaCount = getLoadedLuaCount()
	local path = nil
    local collected = 0
	for i = 0, loadedLuaCount-1 do
		path = getLoadedLua(i)
		local modDir, filePath = path:match("^(.-[\\/]mods[\\/][^\\/]+)[\\/].-[\\/](.*)$")
		if modDir and filePath then
			modDir = fixSeparator(modDir, separator)
			filePath = fixSeparator(filePath, separator)
			if dirMap[modDir] ~= nil then
				table.insert(dirMap[modDir], filePath)
                collected = collected + 1
			end
		end
	end

    -- print("MLOS collected:", collected)
	--  -- 3. Анализируем каждый файл мода на предмет перезаписи функций
    -- for modId, data in pairs(result) do
    --     for _, relFilePath in ipairs(data.files) do
    --         local funcsModified = parseFileFunctions(modId, relFilePath)
            
    --         if funcsModified and #funcsModified > 0 then
    --             for _, funcInfo in ipairs(funcsModified) do
    --                 table.insert(data.modifications, {
    --                     file = relFilePath,
    --                     className = funcInfo.className,
    --                     methodName = funcInfo.methodName,
    --                     fullTarget = funcInfo.className .. ":" .. funcInfo.methodName,
    --                     line = funcInfo.line,
    --                     isHook = funcInfo.isHook -- true: безопасный хук, false: полная перезапись
    --                 })
    --             end
    --         end
    --     end
    -- end

	return result
end



function MLOS_ModsFiles:startAsyncAnalysis(modsList, onProgress, onComplete)
    print("[MLOS] starting files analysing")
    if not modsList then  return {} end

    local separator = getFileSeparator()
    local result = {}
    local filesQueue = {} 

	local dirMap = {}
	for i=1, #modsList do
		local item = modsList[i].item
		if item then
			local modId = item.modId
            if not self.data[modId] then
                local dir = item.modInfo:getDir()
                dir = fixSeparator(dir, separator)
                if dir ~= nil then
                    result[modId] = {
                        rootDir = dir,
                        files = {},
                        modifications = {}
                    }
                    dirMap[dir] = modId
                end
            end
		end
	end

	local loadedLuaCount = getLoadedLuaCount()
	local path = nil
    local collected = 0
	for i = 0, loadedLuaCount-1 do
		path = getLoadedLua(i)
		local modDir, filePath = path:match("^(.-[\\/]mods[\\/][^\\/]+)[\\/].-[\\/](.*)$")
		if modDir and filePath then
			modDir = fixSeparator(modDir, separator)
			if dirMap[modDir] ~= nil then
                filePath = fixSeparator(filePath, separator)
				table.insert(filesQueue, {modId = dirMap[modDir], relPath = filePath })
                collected = collected + 1
			end
		end
	end

    print("[MLOS] added files to queue: ", #filesQueue)

    -- Шаг 2: Создаем корутину-воркер
    local worker = coroutine.create(function()
        local totalFiles = #filesQueue
        local filesPerFrame = 1 -- Сколько файлов анализировать за один кадр игры

        for i, task in ipairs(filesQueue) do
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
                        isHook = funcInfo.isHook
                    })
                end
            end

            -- Каждые N файлов отдаем управление обратно игре, чтобы не фризить кадр
            if i % filesPerFrame == 0 then
                if onProgress then onProgress(i, totalFiles) end
                coroutine.yield() -- Ждем следующий тик игры!
            end
        end

        if onComplete then onComplete(result) end
    end)

    -- Шаг 3: Привязываем корутину к OnTick игры
    local function onTickHandler()
        if coroutine.status(worker) ~= "dead" then
            local success, err = coroutine.resume(worker)
            if not success then
                print("[MLOS ERROR] Analysing error: " .. tostring(err))
                Events.OnFETick.Remove(onTickHandler)
            end
        else
            Events.OnFETick.Remove(onTickHandler)
        end
    end

    Events.OnFETick.Add(onTickHandler)
end


return MLOS_ModsFiles
