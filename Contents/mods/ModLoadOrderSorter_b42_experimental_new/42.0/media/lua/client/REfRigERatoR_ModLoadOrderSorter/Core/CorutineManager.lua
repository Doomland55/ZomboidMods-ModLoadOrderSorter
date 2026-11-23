--[[
    CoroutineManager.lua
    Менеджер корутин для Project Zomboid (Build 41 / 42).

    Выполняет тяжёлые функции порциями (по бюджету времени на тик), не блокируя
    интерфейс главного меню. Внутри задачи можно ждать произвольного состояния
    (например, результата фонового java-потока) без холостого цикла.

    Файл: media/lua/client/REfRigERatoR_ModLoadOrderSorter/Core/CorutineManager2.lua
    Подключение: local CM = require "REfRigERatoR_ModLoadOrderSorter/Core/CorutineManager2.lua"

    Отличия от CorutineManager.lua (v1):
      - waitUntil / sleep / await — неблокирующие паузы и ожидание условий
      - parallel=true — round-robin с квантованием бюджета
      - skipWaiting — пропуск ожидающих задач в последовательном режиме
      - OnTickEvenPaused — работает и на паузе
      - waitBatch — дождаться конкретной пачки задач (вместо waitAll)
      - Throttled onProgress — не чаще раза на 1%
      - Прямой прогресс-бар и текстовая подпись из checkpoint / setProgress
]]

CoroutineManager = CoroutineManager or {}
local CM = CoroutineManager

-- ============================================================
--  Настройки
-- ============================================================
CM.budgetMs    = 6      -- мс на тик для ВСЕХ задач суммарно
CM.parallel    = true   -- true  = round-robin, бюджет тика делится между задачами
                        -- false = строго по очереди (работает только первая задача)
CM.skipWaiting = false  -- только для parallel=false:
                        --   false = пока первая задача ждёт (waitUntil/sleep/await), остальные тоже стоят
                        --   true  = пока первая задача ждёт, работает следующая готовая задача
CM.debug       = false

-- ============================================================
--  Внутреннее состояние
-- ============================================================
local tasks      = {}    -- активные задачи (массив, порядок = порядок запуска)
local waiters    = {}    -- коллбеки CM.waitAll
local groups     = {}    -- ожидания конкретных наборов задач CM.waitFor
local nextId     = 1
local hooked     = false
local tickId     = 0
local lastTickMs = -1
local deadline   = 0    -- конец бюджета текущего тика
local sliceEnd   = 0    -- конец кванта текущей задачи (<= deadline)
local rrCursor   = 1    -- позиция round-robin между тиками
local current    = nil  -- задача, выполняющаяся в данный момент
local progressBar  = nil -- UI-элемент прогресс-бара

local unpack, now = unpack, getTimestampMs


local function log(msg)
    if CM.debug then print("[CoroutineManager] " .. tostring(msg)) end
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if not ok then print("[CoroutineManager] callback error: " .. tostring(err)) end
end

local function clamp01(v)
    if v == nil then return 0 end
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

-- ============================================================
--  Объект задачи
-- ============================================================
local Task = {}
Task.__index = Task

function Task:getId()       return self.id end
function Task:getName()     return self.name end
function Task:getStatus()   return self.status end   -- pending|running|waiting|finished|error|cancelled
function Task:getProgress() return self.progress end
function Task:getResult()   return self.result end
function Task:getResults()  return self.results end
function Task:getError()    return self.error end
function Task:isWaiting()   return self.status == "waiting" end
function Task:isDone()
    local s = self.status
    return s == "finished" or s == "error" or s == "cancelled"
end
function Task:cancel()      CM.cancel(self) end
function Task:elapsedMs()
    if not self.startedAt then return 0 end
    return (self.finishedAt or now()) - self.startedAt
end

local function isTask(v) return type(v) == "table" and getmetatable(v) == Task end

-- ============================================================
--  Запуск и управление задачами (вызывается снаружи)
-- ============================================================

--- opts = {
---    name, args = {...},
---    onStart(task), onProgress(task, p),
---    onFinish(task, ...), onError(task, err)
--- }
function CM.run(fn, opts)
    assert(type(fn) == "function", "CoroutineManager.run: первым аргументом должна быть функция")
    opts = opts or {}

    local task = setmetatable({
        id = nextId,
        name = opts.name or ("task#" .. nextId),
        args = opts.args or {},
        status = "pending",
        progress = 0,
        lastReported = nil,
        onStart = opts.onStart, onProgress = opts.onProgress,
        onFinish = opts.onFinish, onError = opts.onError,
        -- служебные поля ожидания
        waitFn = nil, waitTimeoutAt = nil, waitInterval = 0, waitNextCheck = 0,
        parkedTick = -1, resumeArgs = nil,
    }, Task)
    nextId = nextId + 1

    task.co = coroutine.create(function()
        return fn(unpack(task.args))
    end)

    table.insert(tasks, task)
    log("queued '" .. task.name .. "'")
    CM.hook()
    return task
end

--- Дождаться завершения ВСЕХ запущенных задач (любой пачки).
--- Если очередь уже пуста — коллбек вызовется сразу.
function CM.waitAll(callback)
    if #tasks == 0 then safeCall(callback) return end
    table.insert(waiters, callback)
end

--- Дождаться завершения конкретного набора задач.
--- list = { task1, task2, ... }, callback(list)
function CM.waitFor(list, callback)
    if isTask(list) then list = { list } end
    table.insert(groups, { list = list, cb = callback })
    CM._checkGroups()
end

--- Дождаться завершения конкретной пачки задач (без ожидания будущих задач).
--- list = { task1, task2, ... }, callback(list)
--- Реализована через счётчик: при завершении каждой задачи из списка
--- счётчик уменьшается; когда достигает 0 — коллбек вызывается.
function CM.waitBatch(batchList, callback)
    if type(batchList) == "table" and isTask(batchList) then
        batchList = { batchList }
    end
    assert(type(batchList) == "table", "CoroutineManager.waitBatch: ожидается таблица задач")
    assert(type(callback) == "function", "CoroutineManager.waitBatch: ожидается callback")

    local pending = #batchList
    if pending == 0 then
        safeCall(callback)
        return
    end

    -- Обёртка-счётчик для каждой задачи в пачке
    for _, t in ipairs(batchList) do
        if t:isDone() then
            pending = pending - 1
        else
            local origFinish = t.onFinish
            local origError  = t.onError

            local function onDone()
                pending = pending - 1
                if pending <= 0 then safeCall(callback) end
                if origFinish then origFinish(t, unpack(t.results or {})) end
            end

            t.onFinish = onDone
            t.onError  = function(task, err)
                pending = pending - 1
                if pending <= 0 then safeCall(callback) end
                if origError then origError(task, err) end
            end
        end
    end
end

--- Отменить задачу (коллбеки onFinish/onError не вызываются).
function CM.cancel(task)
    if task and not task:isDone() then
        task.status = "cancelled"
        task.finishedAt = now()
        task.waitFn = nil
        log("cancelled '" .. task.name .. "'")
    end
end

--- Отменить все задачи.
function CM.cancelAll()
    for _, t in ipairs(tasks) do CM.cancel(t) end
end

function CM.isBusy()      return #tasks > 0 end
function CM.count()       return #tasks end
function CM.getTasks()    return tasks end
function CM.inTask()      return current ~= nil end
function CM.currentTask() return current end
function CM.setBudget(ms) CM.budgetMs = ms end

-- ============================================================
--  Прогресс-бар (UI)
-- ============================================================

--- Установить UI-элемент прогресс-бара (должен иметь :setProgress(v) и :setText(s)).
function CM:setProgressBar(pb)
    progressBar = pb
end

--- Сообщить о прогрессе без отдачи кадра.
--- progress — 0..1, info — текстовая подпись (опционально).
function CM.setProgress(progress, info)
    if current and progress ~= nil then
        current.progress = clamp01(progress)
        if progressBar then
            if info then progressBar:setText(info) end
            progressBar:setProgress(current.progress)
        end
    end
end

-- ============================================================
--  Функции, вызываемые ВНУТРИ задачи
-- ============================================================

local function requireTask(fnName)
    if not current then
        error("CoroutineManager." .. fnName .. ": можно вызывать только внутри задачи из CM.run()", 3)
    end
    return current
end

--- Дешёвая точка отдачи кадра: yield только если квант задачи исчерпан.
--- Вне задачи ничего не делает, поэтому ту же функцию можно вызвать синхронно.
--- progress (0..1) и info (текст для UI) — опционально.
function CM.checkpoint(progress, info)
    if not current then return end
    CM.setProgress(progress, info)
    if now() >= sliceEnd then coroutine.yield() end
end

--- Принудительно отдать кадр: задача продолжится в СЛЕДУЮЩЕМ тике.
--- progress — опционально.
function CM.yield(progress, info)
	if not current then return end
	CM.setProgress(progress, info)
    task.parkedTick = tickId
    coroutine.yield()
end

--- Получить объект задачи, которая выполняется прямо сейчас.
--- Вызывается ВНУТРИ тяжёлой функции (снаружи вернёт nil).
function CM.getCurrentTask()
    return current
end

--- Ждать, пока predicate() не вернёт истинное значение.
--- Пока задача ждёт, её корутина НЕ резюмится: планировщик сам проверяет
--- predicate не чаще одного раза за тик (или раз в intervalMs).
---
--- opts (необязательно) - число (timeoutMs) или таблица:
---     timeoutMs  - через сколько мс сдаться (по умолчанию ждать бесконечно)
---     intervalMs - как часто проверять predicate (по умолчанию каждый тик)
---     progress   - выставить прогресс задачи на время ожидания
---
--- Возвращает:  true, <значение predicate>   - условие выполнено
---              false, "timeout"             - истёк таймаут
--- Если predicate бросит ошибку - задача завершится с onError.
function CM.waitUntil(predicate, opts)
    local task = requireTask("waitUntil")
    assert(type(predicate) == "function", "CoroutineManager.waitUntil: ожидалась функция")
    if type(opts) == "number" then opts = { timeoutMs = opts } end
    opts = opts or {}
    if opts.progress ~= nil then task.progress = clamp01(opts.progress) end

    -- быстрый путь: условие уже выполнено - не отдаём кадр
    local value = predicate()
    if value then return true, value end

    local t = now()
    task.waitFn        = predicate
    task.waitTimeoutAt = opts.timeoutMs and (t + opts.timeoutMs) or nil
    task.waitInterval  = opts.intervalMs or 0
    task.waitNextCheck = t + task.waitInterval
    task.status        = "waiting"
    task.parkedTick    = tickId          -- в этом тике уже проверили
    log("'" .. task.name .. "' waiting")

    return coroutine.yield()             -- планировщик резюмит с (true, value) или (false, "timeout")
end

--- Неблокирующая пауза.
function CM.sleep(ms, progress)
    local untilTs = now() + (ms or 0)
    CM.waitUntil(function() return now() >= untilTs end, { progress = progress })
end

--- Ждать завершения другой задачи (или списка задач) изнутри задачи.
--- Для одной задачи возвращает: true, <результаты задачи...>
--- Для списка: true.   При таймауте: false, "timeout"
function CM.await(target, timeoutMs)
    local task = requireTask("await")
    local single = isTask(target)
    local list = single and { target } or target

    for _, t in ipairs(list) do
        if t == task then error("CoroutineManager.await: задача не может ждать саму себя", 2) end
        -- В строго последовательном режиме работает только первая задача в очереди,
        -- поэтому любая другая незавершённая задача никогда не стартует -> дедлок.
        if not CM.parallel and not CM.skipWaiting and not t:isDone() then
            error("CoroutineManager.await: дедлок - '" .. t.name .. "' не сможет выполниться, пока ждёт '"
                .. task.name .. "' (parallel=false, skipWaiting=false)", 2)
        end
    end

    local ok, why = CM.waitUntil(function()
        for _, t in ipairs(list) do
            if not t:isDone() then return false end
        end
        return true
    end, timeoutMs)

    if not ok then return false, why end
    if single then return true, unpack(target.results or {}) end
    return true
end

-- ============================================================
--  Планировщик
-- ============================================================

local function finishTask(task, results)
    task.status     = "finished"
    task.finishedAt = now()
    task.progress   = 1
    task.results    = results
    task.result     = results[1]
    if task.lastReported ~= 1 then
        task.lastReported = 1
        safeCall(task.onProgress, task, 1)
    end
    log(string.format("finished '%s' за %d мс", task.name, task:elapsedMs()))
    safeCall(task.onFinish, task, unpack(results))
end

local function failTask(task, err)
    task.status     = "error"
    task.finishedAt = now()
    task.error      = err
    task.waitFn     = nil
    print("[CoroutineManager] задача '" .. task.name .. "' упала: " .. tostring(err))
    safeCall(task.onError, task, err)
end

--- Проверить условие ожидания. true = задачу можно резюмировать.
local function checkWait(task, t)
    if t < task.waitNextCheck then return false end
    task.waitNextCheck = t + task.waitInterval

    local ok, value = pcall(task.waitFn)
    if not ok then
        failTask(task, "waitUntil predicate: " .. tostring(value))
        return true                         -- задача isDone -> будет удалена
    end
    if value then
        task.waitFn, task.status = nil, "running"
        task.resumeArgs = { true, value }
        return true
    end
    if task.waitTimeoutAt and t >= task.waitTimeoutAt then
        task.waitFn, task.status = nil, "running"
        task.resumeArgs = { false, "timeout" }
        return true
    end
    return false
end

--- Можно ли выполнять задачу прямо сейчас (в этом тике)?
local function canRun(task, t)
    if task:isDone() then return true end            -- нужно убрать из очереди
    if task.parkedTick == tickId then return false end
    if task.waitFn and not checkWait(task, t) then
        task.parkedTick = tickId                     -- проверка не чаще раза за тик
        return false
    end
    return true
end

--- Найти индекс первой runnable-задачи (round-robin или линейный).
local function pickTask(startIdx, t)
    local n = #tasks
    if n == 0 then return nil end

    if not CM.parallel then
        for idx = 1, n do
            if canRun(tasks[idx], t) then return idx end
            if not CM.skipWaiting then return nil end -- строго: только первая задача
        end
        return nil
    end

    -- round-robin с квантованием
    for k = 0, n - 1 do
        local idx = ((startIdx - 1 + k) % n) + 1
        if canRun(tasks[idx], t) then return idx end
    end
    return nil
end

--- Удалить элемент из массива. Swap-remove за O(1) — порядок не важен.
local function removeTaskByIndex(tasksArr, idx)
    tasksArr[idx] = tasksArr[#tasksArr]
    table.remove(tasksArr)
end

--- Удалить группу из groups за O(1) swap-remove.
local function removeGroupByIndex(groupsArr, idx)
    groupsArr[idx] = groupsArr[#groupsArr]
    table.remove(groupsArr)
end

--- Один шаг задачи. true = убрать из очереди.
local function stepTask(task)
    if task:isDone() then return true end

    if task.status == "pending" then
        task.status    = "running"
        task.startedAt = now()
        log("start '" .. task.name .. "'")
        safeCall(task.onStart, task)
        if task:isDone() then return true end
    end

    local args = task.resumeArgs
    task.resumeArgs = nil

    current = task
    local results
    if args then
        results = { coroutine.resume(task.co, unpack(args)) }
    else
        results = { coroutine.resume(task.co) }
    end
    current = nil

    if task.status == "cancelled" then return true end  -- отменили изнутри

    local ok = table.remove(results, 1)
    if not ok then
        failTask(task, results[1])
        return true
    end

    if coroutine.status(task.co) == "dead" then
        finishTask(task, results)
        return true
    end

    -- Отчитаться о прогрессе не чаще 1 раза на шаг
    if task.progress ~= task.lastReported then
        task.lastReported = task.progress
        safeCall(task.onProgress, task, task.progress)
    end
    return false
end

--- Очистить коллбеки из waitAll.
local function flushWaiters()
    if #waiters == 0 then return end
    local list = waiters
    waiters = {}
    for _, cb in ipairs(list) do safeCall(cb) end
end

--- Проверить и завершить группы (CM.waitFor).
function CM._checkGroups()
    local i = 1
    while i <= #groups do
        local g, allDone = groups[i], true
        for _, t in ipairs(g.list) do
            if not t:isDone() then allDone = false; break end
        end
        if allDone then
            removeGroupByIndex(groups, i)
            safeCall(g.cb, g.list)
        else
            i = i + 1
        end
    end
end

--- Обработчик тика. Подписывается автоматически через CM.hook().
function CM.update()
    local t = now()
    -- защита от двойного вызова за один кадр (OnFETick + OnTickEvenPaused и т.п.)
    if t == lastTickMs then return end
    lastTickMs = t
    if #tasks == 0 then return end

    tickId   = tickId + 1
    deadline = t + CM.budgetMs

    local cursor = CM.parallel and rrCursor or 1
    while #tasks > 0 do
        local tn = now()
        if tn >= deadline then break end

        local idx = pickTask(cursor, tn)
        if not idx then break end           -- все задачи ждут / отдали кадр

        -- квант: в parallel бюджет делится между задачами
        if CM.parallel then
            sliceEnd = math.min(deadline, tn + math.max(1, CM.budgetMs / #tasks))
        else
            sliceEnd = deadline
        end

        if stepTask(tasks[idx]) then
            -- O(1) swap-remove: порядок не важен
            removeTaskByIndex(tasks, idx)
            cursor = idx
        else
            cursor = idx + 1
        end
        if cursor > #tasks then cursor = 1 end
    end
    rrCursor = cursor

    CM._checkGroups()
    if #tasks == 0 then flushWaiters() end
end

--- Подписка на события игры. Вызывается автоматически при первом CM.run().
function CM.hook()
    if hooked or not Events then return end
    hooked = true
    -- Главное меню: тикает только OnFETick
    if Events.OnFETick then Events.OnFETick.Add(CM.update) end
    -- В игре (в т.ч. на паузе)
    -- if Events.OnTickEvenPaused then Events.OnTickEvenPaused.Add(CM.update) end
    log("hooked to Events")
end

return CM
