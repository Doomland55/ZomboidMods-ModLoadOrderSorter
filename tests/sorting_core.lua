-- Run from repository root using Lua 5.1.
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/REfRigERatoR_ModLoadOrderSorter/'
local prefix = 'REfRigERatoR_ModLoadOrderSorter/'
local core = { rawCategoryOrder={'early','middle','late','undefined'},
    categoryOrder={early=1,middle=2,late=3,undefined=4}, MLOS_ROOT='test', layers={} }
local utils = {}
function utils:joinpath(a,b) return a .. '/' .. b end
package.loaded[prefix .. 'Core/Core'] = core
package.loaded[prefix .. 'Core/1_Utils'] = utils
function getText(key, ...) return key .. ':' .. table.concat({...}, ',') end
local saved
function getFileWriter() return {write=function(_, s) saved=s end,close=function() end} end
local heap = dofile(base .. 'Core/BinaryHeap.lua')
package.loaded[prefix .. 'Core/BinaryHeap'] = heap
package.loaded[prefix .. 'Core/SortingData'] = dofile(base .. 'Core/SortingData.lua')
package.loaded[prefix .. 'Core/SortingGraph'] = dofile(base .. 'Core/SortingGraph.lua')
local sorter = dofile(base .. 'Core/SortingCore.lua')
local function equal(actual, expected)
 assert(#actual == #expected, 'wrong count: ' .. table.concat(actual, ','))
 for i=1,#expected do assert(actual[i] == expected[i], 'at ' .. i .. ': ' .. table.concat(actual, ',')) end
end
local function row(id, name) return { item={modId=id,name=name or id} } end
local function layers(info, files, rules)
 core.layers={ModsInfo={data=info or {}}, ModsFiles={data=files or {}}, SortingRules={data=rules or {}}}
end
-- The heap's ordering and empty behavior.
local q = heap.new(function(a,b) return a < b end)
assert(q:isEmpty() and q:pop() == nil and q:peek() == nil)
for _, n in ipairs({5,2,7,2,9,1}) do q:push(n) end
local popped = {}; while not q:isEmpty() do popped[#popped+1] = q:pop() end
equal(popped,{1,2,2,5,7,9})
-- Priority: globally first/last, category, within-category first/last, name, ID.
layers({A={name='Zulu',category='middle'}, B={name='Alpha',category='middle'},
 C={name='Late',category='late'}, D={name='Early',category='early'}, E={name='Beta',category='middle'}}, nil,
 {C={loadFirst='on'},D={loadLast='on'},E={loadFirst='category'}})
equal(sorter:sort({row('A'),row('B'),row('C'),row('D'),row('E')}),{'C','E','B','A','D'})
-- Explicit order promotes categories transitively; all layer arrays are merged.
layers({A={category='early',requirements={'B'},loadAfter={'D'}}, B={category='late',requirements={'C'}},
 C={category='late'},D={category='middle'},E={category='middle'}},
 {A={loadAfter={'E'},category='middle'}}, {A={category='early',loadAfter={'E','D'}}})
local list={row('A'),row('B'),row('C'),row('D'),row('E')}
local edges, _, _, cats = sorter:buildGraph(list)
assert(cats.A==1 and cats.B==1 and cats.C==1 and cats.D==1 and cats.E==1)
local beforeWarnings = sorter.warnings
local effective, baseCats = sorter:calculateCategories(list)
assert(effective.B=='early' and effective.C=='early' and baseCats.B=='late')
assert(sorter.warnings==beforeWarnings and core.layers.ModsInfo.data.B.category=='late')
local result=sorter:sort(list)
local index={}; for i,id in ipairs(result) do index[id]=i end
assert(index.C < index.B and index.B < index.A and index.D < index.A and index.E < index.A)
assert(core.layers.ModsInfo.data.B.category=='late' and core.layers.ModsInfo.data.B.effectiveCategory=='early')
-- Rules apply even when ModsInfo is missing; no later layer can replace requirements.
layers({A={category='early',requirements={'B'}}}, {A={requirements={'C'}}},
 {A={requirements={'C'}}, C={loadBefore={'B'}}})
result=sorter:sort({row('A'),row('B'),row('C')}); index={}; for i,id in ipairs(result) do index[id]=i end
assert(index.C<index.B and index.B<index.A)
-- Mod metadata edges outrank a conflicting user edge.
layers({A={loadAfter={'B'}, custom={one=1, list={'x'}}},B={}},
 {A={custom={two=2,list={'y'}}}}, {B={loadAfter={'A'}},A={custom={one=3}}})
local collected = package.loaded[prefix .. 'Core/SortingData'].collect({row('A'),row('B')})
assert(collected.A.custom.one==3 and collected.A.custom.two==2)
equal(collected.A.custom.list,{'x','y'})
result=sorter:sort({row('A'),row('B')}); equal(result,{'B','A'})
assert(sorter.brokenEdges[1].weight==90)
-- File shadow preserves current relative order, hook follows overwrite.
layers({A={category='middle'}, B={category='middle'}}, {
 A={complete=false,files={'same.lua'},modifications={{className='X',methodName='f',isHook=true}}},
 B={complete=true,files={'same.lua'},modifications={{className='X',methodName='f',isHook=false}}}})
result=sorter:sort({row('A'),row('B')})
equal(result,{'B','A'}); assert(#sorter.brokenEdges==1 and sorter.brokenEdges[1].weight==10)
-- On a hard cycle preserve all nodes, break weaker rule before a requirement.
layers({A={category='middle',requirements={'B'}},B={category='middle'}}, nil,
 {B={loadAfter={'A'}}})
result=sorter:sort({row('A'),row('B')}); equal(result,{'B','A'})
assert(#sorter.brokenEdges==1 and sorter.brokenEdges[1].weight==90 and #sorter.warnings>0)
-- Self-cycle is reported, and duplicate rows are preserved by both sort/apply.
layers({A={category='middle',requirements={'A'}},B={category='middle'}})
local a1,a2,b=row('A'),row('A'),row('B')
result=sorter:sort({b,a1,a2}); equal(result,{'B','A','A'})
assert(#sorter.brokenEdges == 1 and sorter.brokenEdges[1].from=='A')
local scroll={items={b,a1,a2}}; sorter:applyOrder(scroll,result)
assert(#scroll.items==3 and scroll.items[1]==b and scroll.items[2]==a1 and scroll.items[3]==a2)
assert(saved=='B;A;A')
-- Incompatibilities from all layers are unioned and de-duplicated.
layers({A={incompatibleMods={'B'}}}, {A={incompatibleMods={'C'}}}, {A={incompatibleMods={'B','C'}}})
assert(#sorter:getIncompatibleWarnings({row('A'),row('B'),row('C')})==2)
print('Binary heap and sorting core tests passed')
