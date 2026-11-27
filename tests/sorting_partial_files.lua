-- Run from repository root with Lua 5.1.
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/REfRigERatoR_ModLoadOrderSorter/'
local prefix = 'REfRigERatoR_ModLoadOrderSorter/'
local utils = {}
function utils:contains(values, value)
    for _, v in ipairs(values) do if v == value then return true end end
    return false
end
local core = { layers = {}, rawCategoryOrder = {'undefined'}, categoryOrder = {undefined = 1} }
package.loaded[prefix .. 'Core/1_Utils'] = utils
package.loaded[prefix .. 'Core/Core'] = core
function getText(key) return key end
package.loaded[prefix .. 'Core/BinaryHeap'] = dofile(base .. 'Core/BinaryHeap.lua')
package.loaded[prefix .. 'Core/SortingData'] = dofile(base .. 'Core/SortingData.lua')
package.loaded[prefix .. 'Core/SortingGraph'] = dofile(base .. 'Core/SortingGraph.lua')
local sorter = dofile(base .. 'Core/SortingCore.lua')
local mods = {{item={modId='A'}}, {item={modId='B'}}}
core.layers.ModsFiles = { data = {
    A={ complete=false, modifications={{className='Class',methodName='method',isHook=false}} },
    B={ complete=true, modifications={{className='Class',methodName='method',isHook=true}} },
}}
local graph = sorter:buildGraph(mods)
assert(graph.A and graph.A[1].to == 'B', 'partial analysis must contribute hook edges')
core.layers.ModsFiles.data.A.complete = nil
graph = sorter:buildGraph(mods)
assert(not graph.A, 'data without an analysis completeness status must be ignored')
print('Partial ModsFiles sorting tests passed')
