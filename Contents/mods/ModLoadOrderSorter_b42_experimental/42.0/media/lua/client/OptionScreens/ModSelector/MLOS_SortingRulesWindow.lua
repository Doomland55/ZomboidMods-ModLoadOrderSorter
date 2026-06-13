---
--- This mod updates the behavior of automatic sorting, added to the Project Zomboid build 42.0.
--- Adds own topological sorting algorithm for mods load order,
--- and adds support for sorting rules from the file sorting_rules.txt.
---
--- Details about this mod:
--- Mod: Mod Load Order Sorter
--- Author: REfRigERatoR
--- Profile: https://steamcommunity.com/profiles/76561198108707962/
---
--- This file:
--- Standalone Sorting Rules Editor window (3 columns).
---
require "ISUI/ISPanelJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"

local utils = require('OptionScreens/MLOS_core/Refr_utils')
local core = require('OptionScreens/MLOS_core/MLOS_Core')
local sortingRules = require('OptionScreens/MLOS_core/MLOS_Layer_SortingRules')
local sortingCore = require('OptionScreens/MLOS_core/MLOS_SortingCore')
local modsInfoLayer = require('OptionScreens/MLOS_core/MLOS_Layer_ModsInfo')

local SortingRulesWindow = ISPanelJoypad:derive("MLOS_SortingRulesWindow")

local PADDING = 10
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MED = getTextManager():getFontHeight(UIFont.Medium)
local BUTTON_HGT = FONT_HGT_SMALL + 6

local borderColorLight = { r = 1, g = 1, b = 1, a = 0.6 }
local borderColorDark  = { r = 1, g = 1, b = 1, a = 0.2 }


local function _clearList(list)
    if list == nil then return end
    if list.clear then
        list:clear()
        return
    end
    list.items = {}
    list.selected = -1
end

local function _addListItem(list, text, item)
    if list.addItem then
        list:addItem(text, item)
        return
    end
    list.items = list.items or {}
    table.insert(list.items, { text = text, item = item })
end

local function _getModName(modInfo)
    if modInfo == nil then return "" end
    return modInfo.name or (modInfo.object and modInfo.object.item and modInfo.object.item.name) or modInfo.id or ""
end

local function _isSame(a, b)
    return a ~= nil and b ~= nil and tostring(a) == tostring(b)
end

local function _pushUnique(list, value)
    if list == nil or value == nil then return end
    for _, v in ipairs(list) do
        if _isSame(v, value) then return end
    end
    table.insert(list, value)
end

-- ============================================================
-- Construction / Lifecycle
-- ============================================================

function SortingRulesWindow:new(x, y, width, height, modListObj)
    local o = ISPanelJoypad:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.90 }
    o.borderColor = borderColorDark

    o.modListObj = modListObj
    o.selectedModId = nil

    o.editModeData = nil -- { type, curRules[modId]=state('selected'|'locked'), locked[modId]=true }

    SortingRulesWindow.instance = o
    return o
end

-- function SortingRulesWindow.getInstance(modListObj)
--     if SortingRulesWindow.instance == nil then
--         local w = math.floor(getCore():getScreenWidth() * 0.80)
--         local h = math.floor(getCore():getScreenHeight() * 0.70)
--         local x = math.floor((getCore():getScreenWidth() - w) / 2)
--         local y = math.floor((getCore():getScreenHeight() - h) / 2)
--         SortingRulesWindow.instance = SortingRulesWindow:new(x, y, w, h, modListObj)
--         SortingRulesWindow.instance:initialise()
--         SortingRulesWindow.instance:instantiate()
--         SortingRulesWindow.instance:setAlwaysOnTop(true)
--     else
--         SortingRulesWindow.instance.modListObj = modListObj or SortingRulesWindow.instance.modListObj
--     end
--     return SortingRulesWindow.instance
-- end

function SortingRulesWindow:show(joyfocus)
    self:refreshAll()
    self:setVisible(true, joyfocus)
    self:addToUIManager()
    self:bringToTop()
end

function SortingRulesWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    self.modListObj.parent:setVisible(true)
end

-- TODO добавить смену величины щрифта (или укрупнить по дефолту)
function SortingRulesWindow:prerender()
    ISPanelJoypad.prerender(self)

    self:drawTextCentre(getText("UI_MLOS_SortingRules"), self.width / 2, PADDING, 1, 1, 1, 1, UIFont.Medium)

    local y = PADDING + FONT_HGT_MED + PADDING
    local colW = self:_getColumnWidth()

    self:drawText(getText("UI_MLOS_SortingRulesWindow_ColMods"), PADDING, y, 1, 1, 1, 1, UIFont.Small)
    self:drawText(getText("UI_MLOS_SortingRulesWindow_ColRules"), PADDING * 2 + colW, y, 1, 1, 1, 1, UIFont.Small)
    self:drawText(getText("UI_MLOS_SortingRulesWindow_ColDetails"), PADDING * 3 + colW * 2, y, 1, 1, 1, 1, UIFont.Small)
end


function SortingRulesWindow:createChildren()
    -- ISPanelJoypad.createChildren(self)

    local headerH = PADDING + FONT_HGT_MED + PADDING + FONT_HGT_SMALL + PADDING
    local bottomH = PADDING + BUTTON_HGT + PADDING

    local colW = self:_getColumnWidth()
    local contentH = self.height - headerH - bottomH
    local listH = contentH

    local x1 = PADDING
    local x2 = PADDING * 2 + colW
    local x3 = PADDING * 3 + colW * 2

    local y0 = headerH

    -- Column 1: Mods list
    self.modsList = ISScrollingListBox:new(x1, y0, colW, listH)
    self.modsList:initialise()
    self.modsList:instantiate()
    self.modsList.itemheight = FONT_HGT_SMALL + 6
    self.modsList.doDrawItem = function(list, y, item, alt) return self:doDrawModsItem(list, y, item, alt) end
    self.modsList.onMouseDown = function(list, x, y)
        ISScrollingListBox.onMouseDown(list, x, y)
        -- TODO добавить мультиселект

        if self.editModeData ~= nil then
            -- In edit mode: clicking a mod toggles it in the current rule,
            -- while keeping the main selected mod unchanged.
            local modId = self:_getSelectedModId()
            if modId ~= nil and not _isSame(modId, self.selectedModId) then
                self:toggleRuleTarget(modId)
            end
        else
            self:onSelectModFromModsList()
        end
    end
    self:addChild(self.modsList)

    -- Column 2: Controls
    self.loadAfterBtn = ISButton:new(x2, y0, colW, BUTTON_HGT, getText("UI_MLOS_SortingRules_load_after_btn"), self, self.onRuleButton)
    self.loadAfterBtn.internal = "LOAD_AFTER"
    self.loadAfterBtn:initialise()
    self.loadAfterBtn:instantiate()
    self.loadAfterBtn.borderColor = borderColorLight
    self.loadAfterBtn:setFont(UIFont.Small)
    self:addChild(self.loadAfterBtn)

    self.loadBeforeBtn = ISButton:new(x2, self.loadAfterBtn:getBottom() + PADDING, colW, BUTTON_HGT, getText("UI_MLOS_SortingRules_load_before_btn"), self, self.onRuleButton)
    self.loadBeforeBtn.internal = "LOAD_BEFORE"
    self.loadBeforeBtn:initialise()
    self.loadBeforeBtn:instantiate()
    self.loadBeforeBtn.borderColor = borderColorLight
    self.loadBeforeBtn:setFont(UIFont.Small)
    self:addChild(self.loadBeforeBtn)

    self.incompatibleBtn = ISButton:new(x2, self.loadBeforeBtn:getBottom() + PADDING, colW, BUTTON_HGT, getText("UI_MLOS_SortingRules_incompatible_btn"), self, self.onRuleButton)
    self.incompatibleBtn.internal = "INCOMPATIBLE"
    self.incompatibleBtn:initialise()
    self.incompatibleBtn:instantiate()
    self.incompatibleBtn.borderColor = borderColorLight
    self.incompatibleBtn:setFont(UIFont.Small)
    self:addChild(self.incompatibleBtn)

    local loadTr = {
        on = getText("UI_MLOS_SortingRules_yes"),
        off = getText("UI_MLOS_SortingRules_no"),
        category = getText("UI_MLOS_SortingRules_in_category")
    }
    self.loadFirstComboBox = ISComboBox:new(x2, self.incompatibleBtn:getBottom() + PADDING, colW, BUTTON_HGT, self, self.onComboBoxChanged)
    self.loadFirstComboBox.borderColor = borderColorLight
    for name, _ in pairs(core.loadCategories) do
        self.loadFirstComboBox:addOptionWithData(getText("UI_MLOS_SortingRules_LoadFirst") .. ": " .. loadTr[name], name)
    end
    self:addChild(self.loadFirstComboBox)

    self.loadLastComboBox = ISComboBox:new(x2, self.loadFirstComboBox:getBottom() + PADDING, colW, BUTTON_HGT, self, self.onComboBoxChanged)
    self.loadLastComboBox.borderColor = borderColorLight
    for name, _ in pairs(core.loadCategories) do
        self.loadLastComboBox:addOptionWithData(getText("UI_MLOS_SortingRules_LoadLast") .. ": " .. loadTr[name], name)
    end
    self:addChild(self.loadLastComboBox)

    self.categoryComboBox = ISComboBox:new(x2, self.loadLastComboBox:getBottom() + PADDING, colW, BUTTON_HGT, self, self.onComboBoxChanged)
    self.categoryComboBox.borderColor = borderColorLight
    self:addChild(self.categoryComboBox)

    self.applyBtn = ISButton:new(x2, self.categoryComboBox:getBottom() + PADDING, colW, BUTTON_HGT, getText("UI_MLOS_SortingRules_apply_btn"), self, self.onRuleButton)
    self.applyBtn.internal = "APPLY"
    self.applyBtn:initialise()
    self.applyBtn:instantiate()
    self.applyBtn.borderColor = borderColorDark
    self.applyBtn:setFont(UIFont.Small)
    self.applyBtn.enable = false
    self:addChild(self.applyBtn)

    -- TODO добавить сюда информационную панель с данными о выбранном моде (ИЛИ добавить тултипы при наведении на мод - лучше)

    -- Column 3: Rule list (top) + Required by (bottom)
    local thirdTopH = math.floor(listH * 0.55)
    local thirdBottomH = listH - thirdTopH - PADDING

    self.ruleModsList = ISScrollingListBox:new(x3, y0, colW, thirdTopH)
    self.ruleModsList:initialise()
    self.ruleModsList:instantiate()
    self.ruleModsList.itemheight = FONT_HGT_SMALL + 6
    self.ruleModsList.doDrawItem = function(list, y, item, alt) return self:doDrawRuleModItem(list, y, item, alt) end
    self.ruleModsList.onMouseDown = function(list, x, y)
        ISScrollingListBox.onMouseDown(list, x, y)
        self:onClickRuleModsListItem()
    end
    self:addChild(self.ruleModsList)

    self.requiredByList = ISScrollingListBox:new(x3, self.ruleModsList:getBottom() + PADDING, colW, thirdBottomH)
    self.requiredByList:initialise()
    self.requiredByList:instantiate()
    self.requiredByList.itemheight = FONT_HGT_SMALL + 6
    self.requiredByList.doDrawItem = function(list, y, item, alt) return self:doDrawSimpleModItem(list, y, item, alt) end
    self:addChild(self.requiredByList)

    -- Bottom buttons
    local yBottom = self.height - BUTTON_HGT - PADDING

    self.cancelBtn = ISButton:new(PADDING, yBottom, colW, BUTTON_HGT, getText("UI_MLOS_SortingRulesWindow_Cancel"), self, self.onBottomButton)
    self.cancelBtn.internal = "CANCEL"
    self.cancelBtn:initialise()
    self.cancelBtn:instantiate()
    self.cancelBtn.borderColor = borderColorLight
    self.cancelBtn:setFont(UIFont.Small)
    self:addChild(self.cancelBtn)

    self.simulateBtn = ISButton:new(PADDING * 2 + colW, yBottom, colW, BUTTON_HGT, getText("UI_MLOS_SortingRulesWindow_Simulate"), self, self.onBottomButton)
    self.simulateBtn.internal = "SIMULATE"
    self.simulateBtn:initialise()
    self.simulateBtn:instantiate()
    self.simulateBtn.borderColor = borderColorLight
    self.simulateBtn:setFont(UIFont.Small)
    self:addChild(self.simulateBtn)

    self.saveExitBtn = ISButton:new(PADDING * 3 + colW * 2, yBottom, colW, BUTTON_HGT, getText("UI_MLOS_SortingRulesWindow_SaveExit"), self, self.onBottomButton)
    self.saveExitBtn.internal = "SAVE_EXIT"
    self.saveExitBtn:initialise()
    self.saveExitBtn:instantiate()
    self.saveExitBtn.borderColor = borderColorLight
    self.saveExitBtn:setFont(UIFont.Small)
    self:addChild(self.saveExitBtn)

    -- initial state
    self:setControlsEnabled(false)
    _clearList(self.ruleModsList)
    _clearList(self.requiredByList)

    self:populateModsListFromModSelector()
end

function SortingRulesWindow:_getColumnWidth()
    return math.floor((self.width - PADDING * 4) / 3)
end

-- ============================================================
-- Rendering / List drawing
-- ============================================================

function SortingRulesWindow:doDrawSimpleModItem(list, y, item, alt)
    local h = item.height or list.itemheight or (FONT_HGT_SMALL + 6)
    local a = 0.9
    local r, g, b = 1, 1, 1

    if list.selected == item.index then
        list:drawRect(0, y, list:getWidth(), h - 1, 0.25, 0.7, 0.35, 0.15)
    end

    list:drawText(item.text or "", 8, y + 2, r, g, b, a, UIFont.Small)
    return y + h
end

function SortingRulesWindow:doDrawModsItem(list, y, item, alt)
    local h = item.height or list.itemheight or (FONT_HGT_SMALL + 6)
    local modId = item.item and item.item.modId

    if self.selectedModId ~= nil and _isSame(modId, self.selectedModId) then
        list:drawRect(0, y, list:getWidth(), h - 1, 0.20, 0.5, 1.0, 1.0)
    elseif list.selected == item.index then
        list:drawRect(0, y, list:getWidth(), h - 1, 0.25, 0.7, 0.35, 0.15)
    end

    if self.editModeData ~= nil and modId ~= nil then
        local state = self.editModeData.curRules and self.editModeData.curRules[modId]
        if state == 'selected' then
            list:drawRect(0, y, list:getWidth(), h - 1, 0.35, 0.5, 0.5, 0.5)
        elseif state == 'locked' then
            list:drawRect(0, y, list:getWidth(), h - 1, 0.30, 1.0, 0.0, 0.0)
        end
    end

    list:drawText(item.text or "", 8, y + 2, 1, 1, 1, 0.9, UIFont.Small)
    return y + h
end

function SortingRulesWindow:doDrawRuleModItem(list, y, item, alt)
    local h = item.height or list.itemheight or (FONT_HGT_SMALL + 6)
    local modId = item.item and item.item.modId
    local state = self.editModeData and self.editModeData.curRules and modId and self.editModeData.curRules[modId] or nil

    if state == 'locked' then
        list:drawRect(0, y, list:getWidth(), h - 1, 0.25, 1.0, 0.0, 0.0)
    elseif list.selected == item.index then
        list:drawRect(0, y, list:getWidth(), h - 1, 0.25, 0.7, 0.35, 0.15)
    end

    local suffix = state == 'locked' and " [LOCK]" or ""
    list:drawText((item.text or "") .. suffix, 8, y + 2, 1, 1, 1, 0.9, UIFont.Small)
    return y + h
end

-- ============================================================
-- Data population / State
-- ============================================================

function SortingRulesWindow:setControlsEnabled(enabled)
    self.loadAfterBtn.enable = enabled
    self.loadBeforeBtn.enable = enabled
    self.incompatibleBtn.enable = enabled

    self.loadFirstComboBox:setEnabled(enabled)
    self.loadLastComboBox:setEnabled(enabled)
    self.categoryComboBox:setEnabled(enabled)

    if not enabled then
        self.applyBtn.enable = false
        self.applyBtn.borderColor = borderColorDark
    end
end

function SortingRulesWindow:populateModsListFromModSelector(optionalOrder)
    _clearList(self.modsList)

    local byId = {}
    if self.modListObj ~= nil and self.modListObj.items ~= nil then
        for _, it in ipairs(self.modListObj.items) do
            local modId = it and it.item and it.item.modId
            if modId ~= nil then
                byId[modId] = it.item
            end
        end
    end

    local order = optionalOrder
    if order == nil and self.modListObj ~= nil and self.modListObj.items ~= nil then
        order = {}
        for _, it in ipairs(self.modListObj.items) do
            local modId = it and it.item and it.item.modId
            if modId ~= nil then table.insert(order, modId) end
        end
    end

    for _, modId in ipairs(order or {}) do
        local item = byId[modId]
        if item == nil then
            -- fallback: try resolved cache (if available)
            local obj = modsInfoLayer.data[modId] and modsInfoLayer.data[modId].object
            item = obj and obj.item or nil
        end
        if item ~= nil then
            _addListItem(self.modsList, item.name or item.modId or tostring(modId), item)
        end
    end
end

function SortingRulesWindow:_ensureModsInfoCache()
    if self.modListObj == nil or self.modListObj.items == nil then return end

    -- Keep mods info cache in sync so that cycle checks use fresh requirements + sortingRules.
    -- sortingRules:readSortingRules()
    -- modsInfoLayer:UpdateData(self.modListObj.items, sortingRules.data)
end

function SortingRulesWindow:_buildDependencyGraph()
    -- Graph of dependencies: deps[A] = {B, C} means A depends on B and C (B must load before A).
    self:_ensureModsInfoCache()

    local deps = {}
    local active = {}
    if self.modListObj ~= nil and self.modListObj.items ~= nil then
        for _, it in ipairs(self.modListObj.items) do
            local id = it and it.item and it.item.modId
            if id ~= nil then
                active[id] = true
                deps[id] = deps[id] or {}
            end
        end
    end

    for modId, _ in pairs(active) do
        local info = modsInfoLayer.data[modId]
        if info ~= nil then
            -- hard requirements
            for _, req in ipairs(info.requirements or {}) do
                if active[req] then _pushUnique(deps[modId], req) end
            end

            -- apply sorting rules (from file) + mod.info rules
            local la = utils:MergeTablesDedup({}, info.loadAfter, (info.sortingRules and info.sortingRules.loadAfter) or {})
            for _, dep in ipairs(la or {}) do
                if active[dep] then _pushUnique(deps[modId], dep) end
            end

            local lb = utils:MergeTablesDedup({}, info.loadBefore, (info.sortingRules and info.sortingRules.loadBefore) or {})
            for _, target in ipairs(lb or {}) do
                -- loadBefore means: target depends on modId
                if active[target] then
                    deps[target] = deps[target] or {}
                    _pushUnique(deps[target], modId)
                end
            end
        end
    end

    return deps
end

function SortingRulesWindow:_hasPath(deps, fromId, toId)
    if deps == nil or fromId == nil or toId == nil then return false end
    if _isSame(fromId, toId) then return true end

    local visited = {}
    local stack = { fromId }

    while #stack > 0 do
        local cur = table.remove(stack)
        if cur ~= nil and not visited[cur] then
            visited[cur] = true
            local nexts = deps[cur] or {}
            for _, n in ipairs(nexts) do
                if _isSame(n, toId) then
                    return true
                end
                if not visited[n] then
                    table.insert(stack, n)
                end
            end
        end
    end
    return false
end

function SortingRulesWindow:_wouldCreateCycle(ruleType, currentModId, targetModId)
    if ruleType ~= 'LOAD_AFTER' and ruleType ~= 'LOAD_BEFORE' then return false end
    if currentModId == nil or targetModId == nil then return false end
    if _isSame(currentModId, targetModId) then return true end

    local deps = self:_buildDependencyGraph()

    -- If we add an edge edgeFrom -> edgeTo, it creates a cycle iff there is already a path edgeTo -> edgeFrom.
    local edgeFrom, edgeTo
    if ruleType == 'LOAD_AFTER' then
        edgeFrom, edgeTo = currentModId, targetModId
    else
        -- LOAD_BEFORE current before target == target depends on current
        edgeFrom, edgeTo = targetModId, currentModId
    end

    return self:_hasPath(deps, edgeTo, edgeFrom)
end

function SortingRulesWindow:refreshAll()
    self.selectedModId = nil
    self.editModeData = nil

    self:setControlsEnabled(false)
    _clearList(self.ruleModsList)
    _clearList(self.requiredByList)

    self:populateModsListFromModSelector()
end

function SortingRulesWindow:_getSelectedModId()
    local idx = self.modsList and self.modsList.selected
    local entry = idx and self.modsList.items and self.modsList.items[idx] or nil
    return entry and entry.item and entry.item.modId or nil
end

function SortingRulesWindow:_getSelectedRuleModId()
    local idx = self.ruleModsList and self.ruleModsList.selected
    local entry = idx and self.ruleModsList.items and self.ruleModsList.items[idx] or nil
    return entry and entry.item and entry.item.modId or nil
end

function SortingRulesWindow:onSelectModFromModsList()
    local modId = self:_getSelectedModId()
    if modId == nil then return end

    -- if switching mod while editing -> exit edit mode without applying
    if self.editModeData ~= nil and (self.selectedModId == nil or not _isSame(self.selectedModId, modId)) then
        self:exitEditMode(true)
    end

    self.selectedModId = modId

    -- keep caches hot, so requirements/"required by" is correct
    self:_ensureModsInfoCache()

    self:setControlsEnabled(true)
    self:refreshCombosForSelectedMod()
    self:updateRequiredByList(modId)

    -- clear top rule list until a rule is chosen
    _clearList(self.ruleModsList)

    -- rules buttons are available again
    self:setRuleButtonsEnabled(true)
end

function SortingRulesWindow:refreshCombosForSelectedMod()
    self.categoryComboBox:clear()

    local modInfo = modsInfoLayer.data[self.selectedModId]
    if modInfo == nil then return end

    local categoryTr = getText("UI_MLOS_SortingRules_Category")
    for _, name in ipairs(core.rawCategoryOrder) do
        self.categoryComboBox:addOptionWithData(categoryTr .. ": " .. (modInfo.category == name and name .. " *" or name), name)
    end

    self.loadFirstComboBox:selectData(modInfo.sortingRules.loadFirst or modInfo.loadFirst)
    self.loadLastComboBox:selectData(modInfo.sortingRules.loadLast or modInfo.loadLast)
    self.categoryComboBox:selectData(modInfo.sortingRules.category or modInfo.category)

    self.loadFirstComboBox.prev_selected = self.loadFirstComboBox.selected
    self.loadLastComboBox.prev_selected = self.loadLastComboBox.selected
    self.categoryComboBox.prev_selected = self.categoryComboBox.selected

    self.applyBtn.enable = false
    self.applyBtn.borderColor = borderColorDark
end

function SortingRulesWindow:updateRequiredByList(modId)
    _clearList(self.requiredByList)

    if modId == nil then return end

    -- list of active mods that require the selected mod
    local activeOrder = {}
    if self.modListObj ~= nil and self.modListObj.items ~= nil then
        for _, it in ipairs(self.modListObj.items) do
            local id = it and it.item and it.item.modId
            if id ~= nil then table.insert(activeOrder, id) end
        end
    end

    for _, otherId in ipairs(activeOrder) do
        if not _isSame(otherId, modId) then
            local info = modsInfoLayer.data[otherId]
            if info ~= nil and info.requirements ~= nil and utils:contains(info.requirements, modId) then
                _addListItem(self.requiredByList, _getModName(info), { modId = otherId })
            end
        end
    end
end

function SortingRulesWindow:setRuleButtonsEnabled(enabled)
    self.loadAfterBtn.enable = enabled
    self.loadBeforeBtn.enable = enabled
    self.incompatibleBtn.enable = enabled

    self.loadAfterBtn.borderColor = enabled and borderColorLight or borderColorDark
    self.loadBeforeBtn.borderColor = enabled and borderColorLight or borderColorDark
    self.incompatibleBtn.borderColor = enabled and borderColorLight or borderColorDark

    self.loadFirstComboBox:setEnabled(enabled)
    self.loadLastComboBox:setEnabled(enabled)
    self.categoryComboBox:setEnabled(enabled)

    self.loadFirstComboBox.borderColor = enabled and borderColorLight or borderColorDark
    self.loadLastComboBox.borderColor = enabled and borderColorLight or borderColorDark
    self.categoryComboBox.borderColor = enabled and borderColorLight or borderColorDark
end

-- ============================================================
-- Edit mode / rules selection
-- ============================================================

function SortingRulesWindow:_getRuleListForType(modInfo, ruleType)
    if modInfo == nil or modInfo.sortingRules == nil then return {} end
    if ruleType == "LOAD_AFTER" then
        return modInfo.sortingRules.loadAfter or {}
    elseif ruleType == "LOAD_BEFORE" then
        return modInfo.sortingRules.loadBefore or {}
    elseif ruleType == "INCOMPATIBLE" then
        return modInfo.sortingRules.incompatibleMods or {}
    end
    return {}
end

function SortingRulesWindow:_getDevRuleListForType(modInfo, ruleType)
    if modInfo == nil then return {} end
    if ruleType == "LOAD_AFTER" then
        return modInfo.loadAfter or {}
    elseif ruleType == "LOAD_BEFORE" then
        return modInfo.loadBefore or {}
    elseif ruleType == "INCOMPATIBLE" then
        return modInfo.incompatibleMods or {}
    end
    return {}
end

function SortingRulesWindow:_isLockedRuleTarget(currentModInfo, ruleType, targetModId)
    if currentModInfo == nil or targetModId == nil then return false end

    -- lock rules coming from mod.info (cannot be edited from sorting_rules.txt)
    local devRules = self:_getDevRuleListForType(currentModInfo, ruleType)
    if utils:contains(devRules, targetModId) then
        return true
    end

    -- prevent circular dependencies for LOAD_AFTER/LOAD_BEFORE, by locking targets that declare the opposite rule in mod.info
    if ruleType == "LOAD_AFTER" or ruleType == "LOAD_BEFORE" then
        local targetInfo = modsInfoLayer.data[targetModId]
        if targetInfo ~= nil then
            local oppositeDev = (ruleType == "LOAD_AFTER") and (targetInfo.loadBefore or {}) or (targetInfo.loadAfter or {})
            if utils:contains(oppositeDev, currentModInfo.id) then
                return true
            end
        end
    end

    return false
end

function SortingRulesWindow:enterEditMode(ruleType)
    if self.selectedModId == nil then return end

    self:_ensureModsInfoCache()
    local modInfo = modsInfoLayer.data[self.selectedModId]
    if modInfo == nil then return end

    self.editModeData = { type = ruleType, curRules = {} }

    -- Disable other controls while editing the rule list
    self:setRuleButtonsEnabled(false)

    if ruleType == "LOAD_AFTER" then self.loadAfterBtn.enable = true
    elseif ruleType == "LOAD_BEFORE" then self.loadBeforeBtn.enable = true
    elseif ruleType == "INCOMPATIBLE" then self.incompatibleBtn.enable = true end

    self.loadAfterBtn.borderColor = (ruleType == "LOAD_AFTER") and borderColorLight or borderColorDark
    self.loadBeforeBtn.borderColor = (ruleType == "LOAD_BEFORE") and borderColorLight or borderColorDark
    self.incompatibleBtn.borderColor = (ruleType == "INCOMPATIBLE") and borderColorLight or borderColorDark

    -- Preload current rules for that type
    local existing = self:_getRuleListForType(modInfo, ruleType)
    for _, id in ipairs(existing or {}) do
        if id ~= nil then
            local locked = self:_isLockedRuleTarget(modInfo, ruleType, id)
            self.editModeData.curRules[id] = locked and 'locked' or 'selected'
        end
    end

    self:rebuildRuleModsList()

    self.applyBtn.enable = true
    self.applyBtn.borderColor = borderColorLight
end

function SortingRulesWindow:exitEditMode(onlyUpdate)
    self.editModeData = nil
    _clearList(self.ruleModsList)

    if self.selectedModId ~= nil then
        self:setRuleButtonsEnabled(true)
    else
        self:setControlsEnabled(false)
    end

    if not onlyUpdate then
        self.applyBtn.enable = false
        self.applyBtn.borderColor = borderColorDark
    end
end

function SortingRulesWindow:rebuildRuleModsList()
    _clearList(self.ruleModsList)

    if self.editModeData == nil or self.editModeData.curRules == nil then return end

    -- Keep stable order using modsList order (current window order)
    local order = {}
    if self.modsList and self.modsList.items then
        for _, it in ipairs(self.modsList.items) do
            local id = it.item and it.item.modId
            if id ~= nil and self.editModeData.curRules[id] ~= nil then
                table.insert(order, id)
            end
        end
    end

    for _, id in ipairs(order) do
        local info = modsInfoLayer.data[id]
        _addListItem(self.ruleModsList, _getModName(info), { modId = id })
    end
end

function SortingRulesWindow:toggleRuleTarget(targetModId)
    if self.editModeData == nil or self.selectedModId == nil or targetModId == nil then return end

    if _isSame(targetModId, self.selectedModId) then return end

    local currentInfo = modsInfoLayer.data[self.selectedModId]
    if currentInfo == nil then return end

    -- lock check (mod.info rules / circular)
    if self:_isLockedRuleTarget(currentInfo, self.editModeData.type, targetModId) then
        self.editModeData.curRules[targetModId] = 'locked'
        self:rebuildRuleModsList()
        return
    end

    -- cycle prevention for loadAfter/loadBefore
    if self:_wouldCreateCycle(self.editModeData.type, self.selectedModId, targetModId) then
        -- silently ignore (no UI messaging primitives here), but keep list unchanged
        return
    end

    local state = self.editModeData.curRules[targetModId]
    if state == nil then
        self.editModeData.curRules[targetModId] = 'selected'
    elseif state == 'selected' then
        self.editModeData.curRules[targetModId] = nil
    else
        -- locked: ignore
        return
    end

    self:rebuildRuleModsList()
end

function SortingRulesWindow:onClickRuleModsListItem()
    if self.editModeData == nil then return end

    local targetModId = self:_getSelectedRuleModId()
    if targetModId == nil then return end

    local state = self.editModeData.curRules[targetModId]
    if state == 'locked' then
        return
    end

    self:toggleRuleTarget(targetModId)
end

-- ============================================================
-- Apply / Buttons
-- ============================================================

function SortingRulesWindow:onComboBoxChanged()
    if self.selectedModId == nil then return end
    if self.editModeData ~= nil then return end

    self.applyBtn.enable = true
    self.applyBtn.borderColor = borderColorLight
end

function SortingRulesWindow:onRuleButton(button)
    if self.selectedModId == nil then return end

    if button.internal == "LOAD_AFTER" or button.internal == "LOAD_BEFORE" or button.internal == "INCOMPATIBLE" then
        if self.editModeData ~= nil and self.editModeData.type == button.internal then
            -- cancel edit mode
            self:exitEditMode(false)
        else
            self:enterEditMode(button.internal)
        end
        return
    end

    if button.internal == "APPLY" then
        self:applyChanges()
        return
    end
end

function SortingRulesWindow:applyChanges()
    if self.selectedModId == nil then return end

    self:_ensureModsInfoCache()

    local update = {
        loadFirst = self.loadFirstComboBox:getOptionData(self.loadFirstComboBox.selected),
        loadLast = self.loadLastComboBox:getOptionData(self.loadLastComboBox.selected),
        category = self.categoryComboBox:getOptionData(self.categoryComboBox.selected),
    }

    if self.editModeData ~= nil then
        local list = {}
        for id, state in pairs(self.editModeData.curRules or {}) do
            if state == 'selected' then
                table.insert(list, id)
            end
        end

        if self.editModeData.type == "LOAD_AFTER" then update.loadAfter = list end
        if self.editModeData.type == "LOAD_BEFORE" then update.loadBefore = list end
        if self.editModeData.type == "INCOMPATIBLE" then update.incompatibleMods = list end
    end

    sortingRules:updateSortingRule(self.selectedModId, update)
    sortingRules:saveSortingRules()

    if self.modListObj and self.modListObj.updateModsColor then
        self.modListObj:updateModsColor()
    end

    self.applyBtn.enable = false
    self.applyBtn.borderColor = borderColorDark

    if self.editModeData ~= nil then
        self:exitEditMode(false)
    end

    -- refresh combo selections from updated cache
    self:refreshCombosForSelectedMod()
end

function SortingRulesWindow:onBottomButton(button)
    if button.internal == "CANCEL" then
        self:close()
        
        return
    end

    if button.internal == "SIMULATE" then
        self:simulateSorting()
        return
    end

    if button.internal == "SAVE_EXIT" then
        if self.applyBtn.enable == true then
            self:applyChanges()
        end
        self:close()
        return
    end
end

function SortingRulesWindow:simulateSorting()
    if self.modListObj == nil or self.modListObj.items == nil then return end

    -- Make sure current file rules are loaded
    sortingRules:readSortingRules()

    local ok, targetOrder = pcall(function()
        return sortingCore:sortModsOrder(self.modListObj.items)
    end)

    if ok and targetOrder ~= nil then
        self:populateModsListFromModSelector(targetOrder)

        -- keep selection if possible
        if self.selectedModId ~= nil and self.modsList and self.modsList.items then
            for i, it in ipairs(self.modsList.items) do
                if it.item and _isSame(it.item.modId, self.selectedModId) then
                    self.modsList.selected = i
                    break
                end
            end
        end
    end
end
return SortingRulesWindow
