---
--- Heuristic Lua source scanner for the ModsFiles layer: finds definitions and
--- overwrites of functions of external tables, local aliases and probable
--- hooks. Not a real Lua parser: long comments with "=" and comment markers
--- inside strings may be handled incorrectly.
--- Has no dependency on the game API - the caller supplies the line reader.
---
local Parser = {}


--- Line reader over a string, with the same interface as a game BufferedReader.
---@param source string
---@return table { readLine = function, close = function }
function Parser.stringReader(source)
    local position = 1
    return {
        readLine = function()
            if position > #source then return nil end
            local ending = source:find("[\r\n]", position)
            local line
            if ending then
                line = source:sub(position, ending - 1)
                position = ending + 1
                if source:sub(ending, ending) == "\r" and source:sub(position, position) == "\n" then
                    position = position + 1
                end
            else
                line = source:sub(position)
                position = #source + 1
            end
            return line
        end,
        close = function() end,
    }
end


--- Scans one Lua file; the reader is closed when the scan is finished.
---@param reader table object with readLine() and close()
---@return table list of { className, methodName, separator, line, isHook, alias }
function Parser.parse(reader)
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


return Parser
