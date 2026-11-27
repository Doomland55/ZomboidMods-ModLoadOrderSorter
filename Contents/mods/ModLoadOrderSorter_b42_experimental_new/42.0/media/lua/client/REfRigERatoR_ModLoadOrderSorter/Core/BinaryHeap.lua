--- Min-heap; `less(a, b)` is a strict, deterministic priority comparator.
--- Public API: new(less), push(value), pop(), peek(), isEmpty(). Lua 5.1.
local Heap = {}
Heap.__index = Heap

function Heap.new(less)
    assert(type(less) == "function", "BinaryHeap requires a comparator")
    return setmetatable({ items = {}, less = less }, Heap)
end

function Heap:isEmpty() return #self.items == 0 end
function Heap:peek() return self.items[1] end

function Heap:push(value)
    local items, less = self.items, self.less
    local i = #items + 1
    while i > 1 do
        local parent = math.floor(i / 2)
        if not less(value, items[parent]) then break end
        items[i] = items[parent]
        i = parent
    end
    items[i] = value
end

function Heap:pop()
    local items, less = self.items, self.less
    local n = #items
    if n == 0 then return nil end
    local result, last = items[1], items[n]
    items[n] = nil
    n = n - 1
    if n == 0 then return result end
    local i = 1
    while i * 2 <= n do
        local child = i * 2
        if child < n and less(items[child + 1], items[child]) then child = child + 1 end
        if not less(items[child], last) then break end
        items[i] = items[child]
        i = child
    end
    items[i] = last
    return result
end

return Heap
