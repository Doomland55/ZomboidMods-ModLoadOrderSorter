local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/REfRigERatoR_ModLoadOrderSorter/'
local prefix = 'REfRigERatoR_ModLoadOrderSorter/'
local utils = {}
function utils:tableIsEmpty(t) return not t or next(t) == nil end
function utils:joinpath(a,b) return a .. '/' .. b end
local cm = {}
function cm:setProgress() end
local core = { MLOS_LAYERS_ROOT = 'root' }
function core:readTxtFile() return nil end
function core:saveTxtFile() return false end
function cacheFileExists(path) return path == 'root/sorting_rules.txt' end
package.loaded[prefix .. 'Core/1_Utils'] = utils
package.loaded[prefix .. 'Core/Core'] = core
package.loaded[prefix .. 'Core/CorutineManager.lua'] = cm
local rules = dofile(base .. 'Layers/SortingRules.lua')
rules.data = { previous = {} }
local ok = pcall(rules.getData, rules, nil, true)
assert(not ok and rules.data.previous, 'unreadable rules must report failure and retain old data')
function cacheFileExists() return false end
-- Module captured cacheFileExists, so simulate a separate session after replacing it.
rules = dofile(base .. 'Layers/SortingRules.lua')
ok = pcall(rules.getData, rules, nil, true)
assert(not ok, 'failed initial rules file creation must report an error')
print('SortingRules error tests passed')
