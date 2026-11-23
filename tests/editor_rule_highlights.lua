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
local core = require(root .. 'Core/Core')
core.layers = {
    ModsInfo = {data = {mod1 = {requirements = {'mod2', 'missing'}, requiredBy = {'mod3'}},
        mod2 = {name = 'Second mod'}}},
    ModsFiles = {data = {mod1 = {files = {'client/a.lua', 'shared/b.lua'}}}},
}
local function combo(values)
    return {options = values, getOptionData = function(self, i) return self.options[i] end}
end
view.loadFirstComboBox = combo({'off', 'on', 'category'})
view.loadLastComboBox = combo({'off', 'on', 'category'})
view.categoryComboBox = combo({'automatic', 'code', 'map'})
view.infoList = {items = {}, clears = 0,
    clear = function(self) self.items = {}; self.clears = self.clears + 1 end,
    setYScroll = function(self, value) self.scroll = value end,
    addItem = function(self, _, item) self.items[#self.items + 1] = item end}
view.filesTab = {internal = 'FILES_TAB'}
view.requiredTab = {internal = 'REQUIRED_TAB'}
view.requiredByTab = {internal = 'REQUIRED_BY_TAB'}
view.sortingRules.mod1 = {loadFirst = 'category', loadLast = 'on', category = 'map'}
view.modsOrderList.selected = 1
view:selectTab(view.filesTab)
assert(view.infoList.items[1].name == 'client/a.lua')
local clears = view.infoList.clears
view:onModClick()
assert(view.infoList.clears == clears + 1) -- exactly one info refresh per click
assert(view.loadFirstComboBox.selected == 3 and view.loadLastComboBox.selected == 2)
assert(view.categoryComboBox.selected == 3)
view:selectTab(view.requiredTab)
assert(view.infoList.items[1].name == 'Second mod')
assert(view.infoList.items[2].name == 'missing')
view:selectTab(view.requiredByTab)
assert(view.infoList.items[1].name == 'mod3')
view.sortingRules.mod2 = nil
view.modsOrderList.selected = 2
view:onModClick()
assert(#view.infoList.items == 0 and view.infoList.scroll == 0)
assert(view.infoList.selectedTab == 'REQUIRED_BY_TAB')
assert(view.loadFirstComboBox.selected == 1 and view.loadLastComboBox.selected == 1)
assert(view.categoryComboBox.selected == 1 and view.categoryComboBox.enable)
assert(view.sortingRules.mod2 == nil) -- displaying defaults must not create rules
view.modsOrderList.selected = 0
view:onModClick()
assert(not view.categoryComboBox.enable and #view.infoList.items == 0)
local utils = require(root .. 'Core/1_Utils')
function utils:deepCopy(value)
    if type(value) ~= 'table' then return value end
    local result = {}; for k, v in pairs(value) do result[k] = self:deepCopy(v) end
    return result
end
function utils:indexOf(values, target)
    for i, value in ipairs(values) do if value == target then return i end end
end
core.layers.SortingRules = {data = {mod1 = {loadAfter = {'mod2'}, loadBefore = {'mod3'}}}}
view.sortingRules.mod1 = utils:deepCopy(core.layers.SortingRules.data.mod1)
view.modsOrderList.selected = 1
view.loadAfter = {}; view.loadBefore = {}; view.incompatible = {}; view.modeApplyBtn = {}; view.modeCancelBtn = {}
view.editingModeList = {items = {}, clear = view.infoList.clear, addItem = view.infoList.addItem, clears = 0}
ISScrollingListBox = {onMouseDown = function(box, x) box.selected = x end}
view.modsOrderList.rowAt = function(_, x) return x end
view:onEditModeClick(view.loadAfter)
assert(view.editMode.key == 'loadAfter' and view.modeApplyBtn.enable)
assert(view.editingModeList.items[1].modId == 'mod2')
assert(view:getRuleBackground('mod3') == nil)
view:onModsOrderMouseDown(view.modsOrderList, 2, 0)
assert(view.modsOrderList.selected == 1 and #view.editingModeList.items == 0)
assert(#view.sortingRules.mod1.loadAfter == 1)
view:onModsOrderMouseDown(view.modsOrderList, 2, 0)
assert(#view.editingModeList.items == 1)
view:onModsOrderMouseDown(view.modsOrderList, 1, 0)
assert(#view.editingModeList.items == 1) -- no self reference
view.loadFirstComboBox.selected = 2
view:onComboBoxChange(view.loadFirstComboBox)
assert(view.editRule.loadFirst == 'on' and view.sortingRules.mod1.loadFirst == nil)
view:applyMode()
assert(not view.editMode and view.sortingRules.mod1.loadFirst == 'on')
assert(core.layers.SortingRules.data.mod1.loadFirst == nil)
view:onEditModeClick(view.loadAfter)
view:onModsOrderMouseDown(view.modsOrderList, 2, 0)
view:cancelMode()
assert(not view.editMode and view.sortingRules.mod1.loadFirst == 'on')
assert(view.editOriginalRule == nil)
assert(view.sortingRules.mod1.loadAfter[1] == 'mod2')
-- All mode buttons are disabled; even direct calls cannot switch modes.
assert(view.loadAfter.enable and view.loadBefore.enable and view.incompatible.enable)
assert(not view.modeApplyBtn.enable and not view.modeCancelBtn.enable)
view:onEditModeClick(view.loadAfter)
assert(not view.loadAfter.enable and not view.loadBefore.enable and not view.incompatible.enable)
assert(view.modeApplyBtn.enable and view.modeCancelBtn.enable)
view:onModsOrderMouseDown(view.modsOrderList, 2, 0)
view:onEditModeClick(view.loadBefore)
assert(view.editMode.key == 'loadAfter')
assert(#view.editRule.loadAfter == 0)
view:cancelMode()
assert(view.sortingRules.mod1.loadAfter[1] == 'mod2')
assert(view.sortingRules.mod1.loadFirst == 'on')
assert(view.loadAfter.enable and view.loadBefore.enable and view.incompatible.enable)
-- Cancelling a mod with no original rule restores nil, not an empty table.
view.modsOrderList.selected = 2
view.sortingRules.mod2 = nil
view:onEditModeClick(view.incompatible)
view:onModsOrderMouseDown(view.modsOrderList, 1, 0)
view:cancelMode()
assert(view.sortingRules.mod2 == nil)
view.modsOrderList.selected = 1
view.categoryComboBox.selected = 2
view:onComboBoxChange(view.categoryComboBox)
assert(view.sortingRules.mod1.category == 'code')
view.categoryComboBox.selected = 1
view:onComboBoxChange(view.categoryComboBox)
assert(view.sortingRules.mod1.category == nil)
function core.layers.SortingRules:commitEdit(data) self.data = data; return true end
view:applyChanges()
assert(core.layers.SortingRules.data ~= view.sortingRules)
-- Remove a disabled/missing mod directly from the editing list, including scrolling.
view.editingModeList.addItem = function(self, _, item)
    self.items[#self.items + 1] = {item = item}
end
view.sortingRules.mod1.loadAfter = {'mod2', 'disabledMod'}
view:onEditModeClick(view.loadAfter)
local list = view.editingModeList
list.width = 200; list.itemheight = 20
list.getYScroll = function() return -20 end
list.rowAt = function(_, _, y) return math.floor((y + 20) / 20) + 1 end
assert(list.items[2].item.modId == 'disabledMod')
view:onEditingListMouseDown(list, 10, 5) -- name is not a remove action
assert(#view.editRule.loadAfter == 2)
view:onEditingListMouseDown(list, 166, 1) -- outside icon vertically
assert(#view.editRule.loadAfter == 2)
view:onEditingListMouseDown(list, 166, 5)
assert(#view.editRule.loadAfter == 1 and #list.items == 1)
assert(#view.sortingRules.mod1.loadAfter == 2) -- still a draft
view:cancelMode()
assert(view.sortingRules.mod1.loadAfter[2] == 'disabledMod')
view:onEditModeClick(view.loadAfter)
view:onEditingListMouseDown(list, 166, 5)
view:applyMode()
assert(#view.sortingRules.mod1.loadAfter == 1)
view:onEditingListMouseDown(list, 166, 5) -- safe outside edit mode
print('editor_rule_highlights: OK')
