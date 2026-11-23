-- Run from the repository root with Lua 5.1: lua tests/editor_rule_highlights.lua
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/'
package.path = base .. '?.lua;' .. package.path
local root = 'REfRigERatoR_ModLoadOrderSorter/'
ISPanelJoypad = {derive = function() return {} end}
UIFont = {Small = 1}
getTextManager = function() return {getFontHeight = function() return 12 end} end
for _, name in ipairs({'ISUI/ISPanelJoypad', 'ISUI/ISScrollingListBox', 'ISUI/ISButton', 'ISUI/ISComboBox',
    root .. 'Core/Core', root .. 'Core/2_SortingCore', root .. 'Elements_UI/ScrollExtensions',
    root .. 'Elements_UI/WarningPopup'}) do
    package.preload[name] = function() return {} end
end
package.preload[root .. 'Core/1_Utils'] = function()
    return {contains = function(_, values, target)
        for _, value in ipairs(values) do if value == target then return true end end
        return false
    end}
end
local editor = require(root .. 'Elements_UI/SortingRulesEditor')
local view = setmetatable({
    modsOrderList = {selected = 1, items = {{item = {modId = 'mod1'}}, {item = {modId = 'mod2'}}}},
    sortingRules = {mod1 = {loadAfter = {'mod2'}, loadBefore = {'mod3', 'mod4'}, incompatibleMods = {'mod10'}}},
}, {__index = editor})
local blue = assert(view:getRuleBackground('mod2'))
local green = assert(view:getRuleBackground('mod3'))
local purple = assert(view:getRuleBackground('mod10'))
assert(blue.b > blue.r and blue.b > blue.g)
assert(green.g > green.r and green.g > green.b)
assert(purple.r > purple.g and purple.b > purple.g)
assert(view:getRuleBackground('mod4') == green)
assert(view:getRuleBackground('mod1') == nil)
assert(view:getRuleBackground('unknown') == nil)
-- Overlapping rules have deterministic priority.
view.sortingRules.mod1.loadBefore = {'mod2'}
assert(view:getRuleBackground('mod2') == green)
view.sortingRules.mod1.incompatibleMods = {'mod2'}
assert(view:getRuleBackground('mod2') == purple)
-- Selection and working-copy changes take effect without cached stale colors.
view.modsOrderList.selected = 2
assert(view:getRuleBackground('mod2') == nil)
view.sortingRules.mod2 = {loadAfter = {'mod1'}}
assert(view:getRuleBackground('mod1') == blue)
view.modsOrderList.selected = 0
assert(view:getRuleBackground('mod1') == nil)
print('editor_rule_highlights: OK')
