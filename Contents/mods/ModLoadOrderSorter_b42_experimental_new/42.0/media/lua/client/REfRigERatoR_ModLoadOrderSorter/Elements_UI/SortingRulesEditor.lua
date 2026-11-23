require "ISUI/ISPanelJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local sorter = require('REfRigERatoR_ModLoadOrderSorter/Core/2_SortingCore')
local scrollExt = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/ScrollExtensions')
local popup = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/WarningPopup')

local SortingRulesEditor = ISPanelJoypad:derive('MLOS_SortingRulesEditor')
local colors = { 
    red = { 1, .2, .2 }, 
    purple = { .75, .3, 1 },
    yellow = { 1, .75, .2 } }


-- Shared by rule targets and their edit buttons (in descending display priority).
local ruleStyles = {
    { key = "incompatibleMods", button = "incompatible", color = { r = .65, g = .25, b = .85, a = .35 } },
    { key = "loadBefore", button = "loadBefore", color = { r = .2, g = .7, b = .3, a = .35 } },
    { key = "loadAfter", button = "loadAfter", color = { r = .2, g = .4, b = .9, a = .35 } },
}

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = math.max(25, FONT_HGT_SMALL + 3 * 2)
local PADDING = 10
-- local borderColorLight = {r=0.4, g=0.4, b=0.4, a=0.9}
local borderColorLight = { r = 1, g = 1, b = 1, a = 0.6 }
local borderColorDark = { r = 1, g = 1, b = 1, a = 0.2 }


function SortingRulesEditor:new(x, y, width, height, modOrderPanel)
    local o = ISPanelJoypad:new(x, y, width, height)
    setmetatable(o, self); self.__index = self
    o.owner = modOrderPanel
    o.sortingRules = core.layers.SortingRules:beginEdit()  -- currentRules list

    o.backgroundColor = { r = 0, g = 0, b = 0, a = .95 }
    return o
end

function SortingRulesEditor:instantiate()
    ISPanelJoypad.instantiate(self)
    self:fillMods()
    self:selectTab(self.filesTab)
end


local function createButton(x,y, width, height, name, target, onClick)
    local button = ISButton:new(x, y, width, height, name, target, onClick)
    button:initialise()
    button:instantiate()
    button:ignoreWidthChange()
    button:ignoreHeightChange()
    button:setAnchorsTBLR(true, false, true, false)
    return button
end


function SortingRulesEditor:getRuleBackground(modId)
    if self.editMode then
        if utils:contains(self.editRule[self.editMode.key] or {}, modId) then
            return self.editMode.color
        end
        return nil
    end
    local list = self.modsOrderList
    local selected = list.items[list.selected]
    local rule = selected and self.sortingRules[selected.item.modId]
    if not rule then return nil end

    for _, style in ipairs(ruleStyles) do
        if utils:contains(rule[style.key] or {}, modId) then
            return style.color
        end
    end
    return nil
end

-- Use the draft for the edited mod so badges reflect pending additions/removals.
function SortingRulesEditor:hasRuleTargets(modId, key)
    local rule = self.editMode and self.editModId == modId and self.editRule
        or self.sortingRules[modId]
    return rule ~= nil and rule[key] ~= nil and #rule[key] > 0
end

function SortingRulesEditor:drawRuleBadges(list, y, item)
    local size = item.height - 4
    local gutter = list.vscroll and list.vscroll:getWidth() or 16
    local right = list.width - gutter - 4
    -- Fixed slots from left to right: A, B, I.
    for index, style in ipairs(ruleStyles) do
        if self:hasRuleTargets(item.item.modId, style.key) then
            local left = right - size - (index - 1) * (size + 3)
            local c = style.color
            list:drawRect(left - 1, y + 1, size + 2, size + 2, 1, .08, .08, .08)
            list:drawRect(left, y + 2, size, size, 1, c.r, c.g, c.b)
            local letter = style.key == "loadAfter" and "A" or style.key == "loadBefore" and "B" or "I"
            list:drawTextCentre(letter, left + size / 2, y + 2 + (size - FONT_HGT_SMALL) / 2,
                1, 1, 1, 1, UIFont.Small)
        end
    end
end

local function scrollDoDrawItem(self, y, item, alt, background)
    local color = item.color or {r = 0.9, g = 0.9, b = 0.9}
    if background then
        self:drawRect(0, y, self.width, item.height - 1, background.a, background.r, background.g, background.b)
    end
    if self.selected == item.index then
        self:drawRect(0, y, self.width, item.height - 1, .3, .6, .6, .6)
    end
    if item.item.icon and item.item.icon ~= "" then
        self:drawTextureScaled(getTexture(item.item.icon), 3, y + 3, item.height - 6, item.height - 6, 1, 1, 1, 1)
    end
    self:drawText(item.item.name, item.height + 6, y + 3, color.r, color.g, color.b, 0.9, self.font )
    return y + item.height
end


function SortingRulesEditor:onComboBoxChange(combo)
    local selected = self.modsOrderList.items[self.modsOrderList.selected]
    if not selected then return end
    local rule = self.editRule or self.sortingRules[selected.item.modId] or {}
    if not self.editMode then self.sortingRules[selected.item.modId] = rule end
    local key = combo == self.loadFirstComboBox and "loadFirst"
        or combo == self.loadLastComboBox and "loadLast" or "category"
    local value = combo:getOptionData(combo.selected)
    if key == "category" and value == "automatic" then value = nil end
    rule[key] = value
end

function SortingRulesEditor:refreshEditingList()
    self.editingModeList:clear()
    if not self.editMode then return end
    for _, id in ipairs(self.editRule[self.editMode.key] or {}) do
        local data = {modId = id, name = id}
        for _, row in ipairs(self.modsOrderList.items) do
            if row.item.modId == id then data = row.item; break end
        end
        self.editingModeList:addItem("", data)
    end
end

-- Reserve the scrollbar gutter even when it is hidden, so the cross never moves.
local function removeButtonBounds(list)
    local size = list.itemheight - 4
    local gutter = list.vscroll and list.vscroll:getWidth() or 16
    return list.width - gutter - size - 4, size
end

function SortingRulesEditor:onEditingListMouseDown(list, x, y)
    if not self.editMode then return end
    local index = list:rowAt(x, y)
    local row = index and list.items[index]
    if not row then return end
    local left, size = removeButtonBounds(list)
    -- rowAt handles scrolling; reject the padding above/below the icon as well.
    local top = (index - 1) * list.itemheight + list:getYScroll() + 2
    if x < left or x >= left + size or y < top or y >= top + size then return end
    local ids = self.editRule[self.editMode.key]
    local at = utils:indexOf(ids, row.item.modId)
    if at then
        table.remove(ids, at)
        self:refreshEditingList()
    end
end

function SortingRulesEditor:finishEdit()
    self.editMode = nil
    self.editRule = nil
    self.editOriginalRule = nil
    self.editModId = nil
    self.editSelected = nil
    self.modeApplyBtn.enable = false
    self.modeCancelBtn.enable = false
    self.editingModeList.borderColor = borderColorLight
    for _, style in ipairs(ruleStyles) do
        self[style.button].enable = true
        self[style.button].borderColor = borderColorLight
    end
    self:refreshEditingList()
    self:onModClick()
end

function SortingRulesEditor:cancelMode()
    if not self.editMode then return end
    self.sortingRules[self.editModId] = utils:deepCopy(self.editOriginalRule)
    self:finishEdit()
end

function SortingRulesEditor:onEditModeClick(button)
    local style
    for _, candidate in ipairs(ruleStyles) do
        if self[candidate.button] == button then style = candidate; break end
    end
    if not style then return end
    if self.editMode then return end
    local selected = self.modsOrderList.items[self.modsOrderList.selected]
    if not selected then return end
    self.editMode = style
    self.editModId = selected.item.modId
    self.editSelected = self.modsOrderList.selected
    -- Keep nil intact so cancelling a new rule does not leave an empty entry.
    self.editOriginalRule = utils:deepCopy(self.sortingRules[self.editModId])
    self.editRule = utils:deepCopy(self.editOriginalRule or {})
    self.editRule[style.key] = self.editRule[style.key] or {}
    button.borderColor = {r = 1, g = 1, b = 1, a = 1}
    self.modeApplyBtn.enable = true
    self.modeCancelBtn.enable = true
    for _, candidate in ipairs(ruleStyles) do self[candidate.button].enable = false end
    self.editingModeList.borderColor = {r = style.color.r, g = style.color.g, b = style.color.b, a = 1}
    self:refreshEditingList()
end

function SortingRulesEditor:applyMode()
    if not self.editMode then return end
    self.sortingRules[self.editModId] = utils:deepCopy(self.editRule)
    self:finishEdit()
end

function SortingRulesEditor:applyChanges()
    if self.editMode then self:applyMode() end
    if not core.layers.SortingRules:commitEdit(utils:deepCopy(self.sortingRules)) then
        self.warningPopup:addMessage("Sorting Rules", "Failed to save sorting rules.", "SortingRules", "CRITICAL")
    end
end

function SortingRulesEditor:onModsOrderMouseDown(box, x, y)
    ISScrollingListBox.onMouseDown(box, x, y)
    if self.editMode then
        local clicked = box.items[box:rowAt(x, y)]
        box.selected = self.editSelected
        if not clicked or clicked.item.modId == self.editModId then return end
        local ids = self.editRule[self.editMode.key]
        local index = utils:indexOf(ids, clicked.item.modId)
        if index then table.remove(ids, index) else table.insert(ids, clicked.item.modId) end
        self:refreshEditingList()
    else
        self:onModClick()
    end
end

function SortingRulesEditor:fillMods()
    self.modsOrderList:clear()

    local items = self.owner.modList.items
    for i=1, #items do
        local row = items[i].item
        local item = self.modsOrderList:addItem("", {icon=row.icon, modId=row.modId, name=row.name})
        item.color = {r = 0.9, g = 0.9, b = 0.9}
        -- item.tooltip = self:getTooltip(row.modInfo)
    end
    self.modsOrderList.selected = 0

    -- self.mods:clear()
--     for _, row in ipairs(self.order) do
--         local id = row.item.modId
--         local c = colors[status[id]] or { 1, 1, 1 }
--         if self.mode and id == self.selectedId then
--             c = { .5, .5, .5 }
--         elseif self.mode and utils:contains(self.pending, id) then
--             c = { .3, .85, 1 }
--         end
--         self.mods:addItem(row.item.name, { modId = id, name = row.item.name, color = c })
--         self.mods.items[#self.mods.items].itemindex = #self.mods.items
--         if id == self.selectedId then self.mods.selected = #self.mods.items end
--     end
end


function SortingRulesEditor:updateScrollLists()
end


-- Refresh only on selection/tab events, never from the draw loop.
function SortingRulesEditor:refreshInfoList()
    self.infoList:clear()
    self.infoList:setYScroll(0)
    local selected = self.modsOrderList.items[self.modsOrderList.selected]
    if not selected then return end

    local id = selected.item.modId
    local infoLayer = core.layers.ModsInfo
    local info = infoLayer and infoLayer.data[id] or {}
    local tab = self.infoList.selectedTab
    local data = {}
    if tab == "FILES_TAB" then
        local filesLayer = core.layers.ModsFiles
        local mod = filesLayer and filesLayer.data[id]
        data = mod and mod.files or {}
    elseif tab == "REQUIRED_TAB" then
        data = info.requirements or {}
    elseif tab == "REQUIRED_BY_TAB" then
        data = info.requiredBy or {}
    end

    for _, value in ipairs(data) do
        local mod = tab ~= "FILES_TAB" and infoLayer and infoLayer.data[value]
        self.infoList:addItem("", {name = mod and mod.name or value,
            modId = tab ~= "FILES_TAB" and value or nil})
    end
end

local function selectComboValue(combo, value)
    combo.selected = 1
    for i = 1, #combo.options do
        if combo:getOptionData(i) == value then
            combo.selected = i
            return
        end
    end
end

function SortingRulesEditor:onModClick()
    local selected = self.modsOrderList.items[self.modsOrderList.selected]
    local rule = selected and self.sortingRules[selected.item.modId] or {}
    rule = rule or {}
    -- Assigning selected does not invoke the change callback or modify rules.
    selectComboValue(self.loadFirstComboBox, rule.loadFirst or "off")
    selectComboValue(self.loadLastComboBox, rule.loadLast or "off")
    selectComboValue(self.categoryComboBox, rule.category or "automatic")
    self.loadFirstComboBox.enable = selected ~= nil
    self.loadLastComboBox.enable = selected ~= nil
    self.categoryComboBox.enable = selected ~= nil
    self:refreshInfoList()
end

function SortingRulesEditor:selectTab(button)
    if self.infoList.selectedTab == button.internal then return end
    self.infoList.selectedTab = button.internal
    for _, btn in ipairs({self.filesTab, self.requiredTab, self.requiredByTab}) do
        local color = btn.internal == button.internal and borderColorLight or borderColorDark
        btn.borderColor = color
        btn.textColor = color
    end
    self:refreshInfoList()
end


function SortingRulesEditor:createChildren()
    local y_offset = 50 + PADDING
    local innerWitdth = self.width - (PADDING * 4)
    local innerHeight = self.height - y_offset - PADDING * 2 - BUTTON_HGT

    -- #region General Elements
    local infoBtn = createButton(self.width - PADDING * 2 - BUTTON_HGT, PADDING, BUTTON_HGT, BUTTON_HGT)
    infoBtn.internal = 'INFO'
    infoBtn:setTooltip(getText("UI_MLOS_Info_Msg"))  -- TODO change text
    infoBtn:setTextureRGBA(1.0, 1.0, 1.0, 0.8)
    infoBtn:setImage(getTexture("media/ui/MLOS_question_mark.png"))
    infoBtn.isBorderVisible = false
    self:addChild(infoBtn)

    self.warningPopup = popup:new(infoBtn.x - 48 - PADDING, PADDING)
    self.warningPopup:setAnchorsTBLR(true, false,true, false)
    self.warningPopup:ignoreWidthChange()
    self.warningPopup:ignoreHeightChange()
    self:addChild(self.warningPopup)

    self.applyBtn = createButton(self.width - PADDING * 2 - BUTTON_HGT * 4, self.height - PADDING - BUTTON_HGT, BUTTON_HGT * 4, BUTTON_HGT, "Apply", self, self.applyChanges)
    self:addChild(self.applyBtn)

    self.closeBtn = createButton(PADDING * 2, self.applyBtn.y, BUTTON_HGT * 4, BUTTON_HGT, "Close", self, self.close)
    self:addChild(self.closeBtn)
    -- #endregion


    -- #region Current mods order (left)
    local modsOrder = scrollExt.createList(self, PADDING * 2, y_offset, innerWitdth * 0.4 - PADDING, innerHeight)
    modsOrder.itemheight = FONT_HGT_SMALL + 8
    scrollExt:addTitle(modsOrder, function()
        return self.editMode and getText("UI_MLOS_Editor_ClickHint") or "Mods Order:"
    end, nil, nil, UIFont.Small, - BUTTON_HGT - PADDING)
    modsOrder.borderColor = borderColorLight
    modsOrder.font = UIFont.Small
    modsOrder.doDrawItem = function(list, y, item, alt)
        local nextY = scrollDoDrawItem(list, y, item, alt, self:getRuleBackground(item.item.modId))
        self:drawRuleBadges(list, y, item)
        if self.editMode and item.item.modId == self.editModId then
            list:drawRectBorder(0, y, list.width, item.height - 1, 1, 1, 1, 1)
        end
        return nextY
    end
    modsOrder.onMouseDown = function(box, x, y)
        self:onModsOrderMouseDown(box, x, y)
    end
    scrollExt:addSearchEntry(modsOrder, nil, true)
    scrollExt:addBackground(modsOrder, nil, {})
    self.modsOrderList = modsOrder
    self:addChild(self.modsOrderList)
    -- #endregion

    -- Buttons block (center)
    local center_x = modsOrder:getRight() + PADDING
    local panel = ISPanel:new(center_x, self.modsOrderList.y, innerWitdth * 0.2 + 1, BUTTON_HGT * 4 + PADDING * 5)
    panel:initialise()
    panel:instantiate()
    panel.borderColor = borderColorLight
    self:addChild(panel)

    self.loadAfter = createButton(center_x + PADDING, self.modsOrderList.y + PADDING, panel.width - PADDING * 2, BUTTON_HGT, getText("UI_MLOS_SortingRules_load_after_btn"), self, self.onEditModeClick)
    self.loadAfter.internal = "LOAD_AFTER"
    self:addChild(self.loadAfter)

    self.loadBefore = createButton(center_x + PADDING, self.loadAfter:getBottom() + PADDING, self.loadAfter.width, BUTTON_HGT, getText("UI_MLOS_SortingRules_load_before_btn"), self, self.onEditModeClick);
    self.loadBefore.internal = "LOAD_BEFORE"
    self:addChild(self.loadBefore)

    self.incompatible = createButton(center_x + PADDING, self.loadBefore:getBottom() + PADDING, self.loadAfter.width, BUTTON_HGT, getText("UI_MLOS_SortingRules_incompatible_btn"), self, self.onEditModeClick);
    self.incompatible.internal = "INCOMPATIBLE"
    self:addChild(self.incompatible)

    for _, style in ipairs(ruleStyles) do
        local button = self[style.button]
        local c = style.color
        button.backgroundColor = { r = c.r, g = c.g, b = c.b, a = c.a }
        button.backgroundColorMouseOver = { r = c.r, g = c.g, b = c.b, a = .6 }
    end

    local actionWidth = (self.loadAfter.width - PADDING) / 2
    self.modeCancelBtn = createButton(center_x + PADDING, self.incompatible:getBottom() + PADDING,
        actionWidth, BUTTON_HGT, getText("UI_MLOS_Editor_Cancel"), self, self.cancelMode)
    self.modeCancelBtn.enable = false
    self:addChild(self.modeCancelBtn)
    self.modeApplyBtn = createButton(self.modeCancelBtn:getRight() + PADDING, self.modeCancelBtn.y,
        actionWidth, BUTTON_HGT, getText("UI_MLOS_Editor_Apply"), self, self.applyMode)
    self.modeApplyBtn.enable = false
    self:addChild(self.modeApplyBtn)

    local loadTr = {on=getText("UI_MLOS_SortingRules_yes"), off=getText("UI_MLOS_SortingRules_no"), category=getText("UI_MLOS_SortingRules_in_category")}
    local loadFirstTr = getText("UI_MLOS_SortingRules_LoadFirst")
    local loadLastTr = getText("UI_MLOS_SortingRules_LoadLast")

    self.loadFirstComboBox = ISComboBox:new(center_x, self.modeApplyBtn:getBottom() + PADDING * 2, innerWitdth * 0.2 - PADDING, BUTTON_HGT, self, self.onComboBoxChange)
    self:addChild(self.loadFirstComboBox)

    self.loadLastComboBox = ISComboBox:new(center_x, self.loadFirstComboBox:getBottom() + PADDING, self.loadFirstComboBox.width, BUTTON_HGT, self, self.onComboBoxChange)
    self:addChild(self.loadLastComboBox)

    for _, name in ipairs({"off", "on", "category"}) do
        self.loadFirstComboBox:addOptionWithData(loadFirstTr .. ": " .. tostring(loadTr[name]), name)
        self.loadLastComboBox:addOptionWithData(loadLastTr .. ": " .. tostring(loadTr[name]), name)
    end

    self.categoryComboBox = ISComboBox:new(center_x, self.loadLastComboBox:getBottom() + PADDING, self.loadFirstComboBox.width, BUTTON_HGT, self, self.onComboBoxChange)
    self:addChild(self.categoryComboBox)
    self.categoryComboBox:addOptionWithData("Automatic", "automatic")
    for _, category in ipairs(core.rawCategoryOrder) do
        self.categoryComboBox:addOptionWithData(category, category)
    end
    self.loadFirstComboBox.enable = false
    self.loadLastComboBox.enable = false
    self.categoryComboBox.enable = false



    -- Editing list (right)
    local editingModeList = scrollExt.createList(self, PADDING * 2 + innerWitdth * 0.6, self.modsOrderList.y, innerWitdth * 0.4, innerHeight * 0.5 - PADDING - BUTTON_HGT)
    editingModeList.itemheight = FONT_HGT_SMALL + 8
    editingModeList.font = UIFont.Small
    editingModeList.doDrawItem = function(list, y, item, alt)
        local nextY = scrollDoDrawItem(list, y, item, alt)
        if self.editMode then
            local left, size = removeButtonBounds(list)
            -- Opaque backing keeps long mod names from obscuring the action.
            list:drawRect(left - 2, y, size + 4, item.height, 1, .08, .08, .08)
            list:drawRect(left, y + 2, size, size, 1, .55, .08, .08)
            list:drawTextCentre("X", left + size / 2, y + 2 + (size - FONT_HGT_SMALL) / 2,
                1, .3, .3, 1, UIFont.Small)
        end
        return nextY
    end
    editingModeList.onMouseDown = function(list, x, y)
        self:onEditingListMouseDown(list, x, y)
    end
    scrollExt:addTitle(editingModeList, function()
        if not self.editMode then return "Mods in selected mode:" end
        return getText("UI_MLOS_Editor_Targets", self[self.editMode.button].title,
            tostring(#(self.editRule[self.editMode.key] or {})))
    end, nil, nil, UIFont.Small, - BUTTON_HGT - PADDING)
    scrollExt:addBackground(editingModeList, nil, {})
    editingModeList.borderColor = borderColorLight
    self.editingModeList = editingModeList


    -- #region info section
    self.filesTab = createButton(center_x, y_offset + innerHeight * 0.5 + PADDING, BUTTON_HGT * 4, BUTTON_HGT, "Files", self, self.selectTab)
    self.filesTab.internal = "FILES_TAB"
    self:addChild(self.filesTab)

    self.requiredTab = createButton(self.filesTab:getRight(), self.filesTab.y, BUTTON_HGT * 4, BUTTON_HGT, "Required", self, self.selectTab)
    self.requiredTab.internal = "REQUIRED_TAB"
    self:addChild(self.requiredTab)

    self.requiredByTab = createButton(self.requiredTab:getRight(), self.filesTab.y, BUTTON_HGT * 4, BUTTON_HGT, "Required By", self, self.selectTab)
    self.requiredByTab.internal = "REQUIRED_BY_TAB"
    self:addChild(self.requiredByTab)

    local infoList = scrollExt.createList(self, center_x, self.filesTab:getBottom() - 1, innerWitdth * 0.6, self.modsOrderList:getBottom() - self.filesTab:getBottom() + 2)
    infoList.itemheight = FONT_HGT_SMALL + 8
    infoList.font = UIFont.Small
    infoList.doDrawItem = scrollDoDrawItem
    scrollExt:addBackground(infoList, nil, {})
    infoList.borderColor = borderColorLight
    self.infoList = infoList

    --#endregion

    -- self:fillModList()
    -- self:selectTab(self.filesTab)
end

-- function SortingRulesEditor:createChildren()
--     local w = math.floor((self.width - 40) / 3)
--     local x1, x2, x3 = 10, 20 + w, 30 + 2 * w
--     local top, bottom = 65, self.height - 50

--     self.mods = list(self, x1, top, w, bottom - top, self.selectMod)
--     scroll:addSearchEntry(self.mods, -50)
--     self.modeButtons = {}
--     for i, mode in ipairs({ 'loadAfter', 'loadBefore', 'incompatibleMods' }) do
--         local b = button(self, x2, top + (i - 1) * 30, w, mode, function(owner) owner:toggleMode(mode) end)
--         self.modeButtons[#self.modeButtons + 1] = b
--     end
--     self.applyButton = button(self, x2, top + 100, w / 2 - 3, 'Apply', self.applyMode)
--     self.cancelButton = button(self, x2 + w / 2 + 3, top + 100, w / 2 - 3, 'Cancel', self.cancelMode)
--     local cats = { 'automatic' }
--     for _, cat in ipairs(core.rawCategoryOrder) do table.insert(cats, cat) end
--     self.category = combo(self, x2, top + 155, w, cats, 'category'); self.categories = cats
--     self.first = combo(self, x2, top + 210, w, { 'off', 'on', 'category' }, 'loadFirst')
--     self.last = combo(self, x2, top + 265, w, { 'off', 'on', 'category' }, 'loadLast')
    
--     local h = math.floor((bottom - top - 60) / 3)
--     self.ruleList = list(self, x3, top + 20, w, h, self.navigate, true)
--     self.requiredList = list(self, x3, top + 40 + h, w, h, self.navigate, true)
--     self.requiredByList = list(self, x3, top + 60 + 2 * h, w, h, self.navigate, true)
--     button(self, x1, self.height - 35, w, 'Exit without saving', self.discard)
--     button(self, x2, self.height - 35, w, 'Simulate', self.simulate)
--     button(self, x3, self.height - 35, w, 'Save and exit', self.save)
--     self.warningPopup = popup:new(self.width - 60, 5); self:addChild(self.warningPopup)
--     self:refresh()

-- end

function SortingRulesEditor:prerender()
    ISPanelJoypad.prerender(self)
    local title = 'Sorting Rules Editor'
    if self.editMode then
        local row = self.modsOrderList.items[self.editSelected]
        title = getText("UI_MLOS_Editor_Editing", self[self.editMode.button].title, row.item.name)
    end
    self:drawTextCentre(title, self.width * 0.5, PADDING * 2, 1, 1, 1, 1, UIFont.Large)
end

-- function SortingRulesEditor:selectMod(id)
--     if self.mode then
--         if id == self.selectedId then return end
--         local at = utils:indexOf(self.pending, id)
--         if at then table.remove(self.pending, at) else table.insert(self.pending, id) end
--     else
--         self.selectedId = id
--     end
--     self:refresh()
-- end

-- function SortingRulesEditor:navigate(id)
--     if self.mode then return end
--     local found = false
--     for _, row in ipairs(self.order) do
--         if row.item.modId == id then
--             found = true; break
--         end
--     end
--     if not found then return end
--     self.selectedId = id
--     self:refresh()
--     for i, row in ipairs(self.mods.items) do
--         if row.item.modId == id then
--             self.mods:ensureVisible(i); break
--         end
--     end
-- end

-- function SortingRulesEditor:toggleMode(mode)
--     if not self.selectedId then return end
--     if self.mode == mode then
--         self:cancelMode(); return
--     end
--     self.mode = mode
--     self.pending = utils:deepCopy((self.working[self.selectedId] or {})[mode] or {})
--     self:refresh()
-- end

-- function SortingRulesEditor:cancelMode()
--     self.mode = nil; self.pending = nil; self:refresh()
-- end

-- function SortingRulesEditor:applyMode()
--     if not self.mode then return end
--     local rule = self.working[self.selectedId] or {}; self.working[self.selectedId] = rule
--     rule[self.mode] = utils:deepCopy(self.pending)
--     self:cancelMode()
-- end

-- function SortingRulesEditor:refresh()
--     local status = sorter:validate(self.order, self.working)
--     local info = core.layers.modInfo.data
--     self.mods:clear()
--     for _, row in ipairs(self.order) do
--         local id = row.item.modId
--         local c = colors[status[id]] or { 1, 1, 1 }
--         if self.mode and id == self.selectedId then
--             c = { .5, .5, .5 }
--         elseif self.mode and utils:contains(self.pending, id) then
--             c = { .3, .85, 1 }
--         end
--         self.mods:addItem(row.item.name, { modId = id, name = row.item.name, color = c })
--         self.mods.items[#self.mods.items].itemindex = #self.mods.items
--         if id == self.selectedId then self.mods.selected = #self.mods.items end
--     end
--     local function fill(box, ids)
--         box:clear()
--         for _, id in ipairs(ids or {}) do
--             box:addItem((info[id] and info[id].name) or id, { modId = id, name = (info[id] and info[id].name) or id })
--         end
--     end
--     local data = info[self.selectedId] or {}
--     fill(self.ruleList, self.pending)
--     fill(self.requiredList, data.requirements)
--     fill(self.requiredByList, data.requiredBy)
--     local rule = self.working[self.selectedId] or {}
--     self.refreshing = true
--     self.category.selected = utils:indexOf(self.categories, rule.category or 'automatic') or 1
--     self.first.selected = utils:indexOf({ 'off', 'on', 'category' }, rule.loadFirst or 'off') or 1
--     self.last.selected = utils:indexOf({ 'off', 'on', 'category' }, rule.loadLast or 'off') or 1
--     self.refreshing = false
--     for _, b in ipairs(self.modeButtons) do b.enable = self.selectedId ~= nil end
--     self.applyButton.enable = self.mode ~= nil; self.cancelButton.enable = self.mode ~= nil
--     self.category.enable = self.selectedId ~= nil; self.first.enable = self.selectedId ~= nil; self.last.enable = self
--         .selectedId ~= nil
--     self.mods.foundItems = {}; self.mods.foundIndex = 0; self.mods.foundCounter = 0
-- end

-- function SortingRulesEditor:simulate()
--     local ids = sorter:sort(self.order, self.working)
--     local rows = {}; for _, row in ipairs(self.order) do rows[row.item.modId] = row end
--     self.order = {}; for _, id in ipairs(ids) do table.insert(self.order, rows[id]) end
--     for _, w in ipairs(sorter.warnings) do self.warningPopup:addMessage(w.title, w.message, w.layer, w.severity) end
--     self:refresh()
-- end

function SortingRulesEditor:close()
    self:setVisible(false)
    self.owner:setVisible(true)
    self:removeFromUIManager()
end

return SortingRulesEditor
