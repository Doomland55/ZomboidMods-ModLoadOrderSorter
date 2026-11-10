-- Shared front-end tick dispatcher. Callbacks are isolated and may remove or
-- replace themselves; the game event is installed only while work exists.
local scheduler = { jobs = {}, order = {}, listening = false }
local dispatch

local function stopIfEmpty()
    if scheduler.listening and not next(scheduler.jobs) then
        Events.OnFETick.Remove(dispatch)
        scheduler.listening = false
    end
end

function scheduler:add(callback, onError)
    assert(type(callback) == "function", "tick callback must be a function")
    assert(not self.jobs[callback], "tick callback already registered")
    local job = { callback = callback, onError = onError }
    self.jobs[callback] = job
    self.order[#self.order + 1] = job
    if not self.listening then
        self.listening = true
        Events.OnFETick.Add(dispatch)
    end
    return callback
end

function scheduler:remove(callback)
    if not callback or not self.jobs[callback] then return end
    self.jobs[callback] = nil
    for i = #self.order, 1, -1 do
        if self.order[i].callback == callback then table.remove(self.order, i); break end
    end
    stopIfEmpty()
end

dispatch = function()
    local snapshot = {}
    for i, job in ipairs(scheduler.order) do snapshot[i] = job end
    for _, job in ipairs(snapshot) do
        if scheduler.jobs[job.callback] == job then
            local ok, err = pcall(job.callback)
            if not ok then
                scheduler:remove(job.callback)
                if job.onError then
                    local handled, handlerError = pcall(job.onError, err)
                    if not handled then print("[MLOS] Tick error handler failed: " .. tostring(handlerError)) end
                else
                    print("[MLOS] Tick callback failed: " .. tostring(err))
                end
            end
        end
    end
    stopIfEmpty()
end

return scheduler
