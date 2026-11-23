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


local function scrollDoDrawItem(self, y, item, alt)
    local color = item.color or {r = 0.9, g = 0.9, b = 0.9}
    if self.selected == item.index then
        self:drawRect(0, y, self.width, item.height - 1, .3, .6, .6, .6)
    end
    if item.item.icon and item.item.icon ~= "" then
        self:drawTextureScaled(getTexture(item.item.icon), 3, y + 3, item.height - 6, item.height - 6, 1, 1, 1, 1)
    end
    self:drawText(item.item.name, item.height + 6, y + 3, color.r, color.g, color.b, 0.9, self.font )
    return y + item.height
end


function SortingRulesEditor:onComboBoxChange(combobox_obj)
    -- if self.applyBtn.enable ~= true then
    --     -- self.applyBtn.borderColor = borderColorLight
    --     self.applyBtn.enable = true
    -- end
end

function SortingRulesEditor:onEditModeClick(button)
    -- if button.internal == "LOAD_AFTER" then
    --     self:switchEditMode(button, { r = 0.5, g = 0.5, b = 0.5, a = 0.5 })
    -- elseif button.internal == "LOAD_BEFORE" then
    --     self:switchEditMode(button, { r = 0.5, g = 0.5, b = 0.5, a = 0.5 })
    -- elseif button.internal == "INCOMPATIBLE" then
    --     self:switchEditMode(button, { r = 0.5, g = 0.5, b = 0.5, a = 0.5 })
    -- elseif button.internal == "APPLY" then
    --     self:applyChanges()

    --     self.editModeData = nil
    --     self:switchEditMode()
    --     self:onExitSortingRules()
    -- end
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


function SortingRulesEditor:selectTab(button)
    if self.infoList.selectedTab == button.internal then return end

    local function changeColor(btn, toDark)
        local color = toDark and borderColorLight or borderColorDark
        btn.borderColor = color
        btn.textColor = color
    end

    local function loadInfo(btn)
        local label = btn.internal

        local selectedItem = self.modsOrderList.items[self.modsOrderList.selected]
        if not selectedItem then return end
        local sr = core.layers.SortingRules.data[selectedItem.item.modId]
        if not sr then return end

        self.infoList:clear()
        local data = {}
        if label == "FILES_TAB" then -- TODO replace with propper data
        elseif label == "REQUIRED_TAB" then
            data = sr.loadAfter or {}  -- TODO replace with propper data
        elseif label == "REQUIRED_BY_TAB" then
            data = sr.loadBefore or {} -- TODO replace with propper data
        end

        for i=1, #data do
            self.infoList:addItem("", {name=data[i]})
        end
    end

    local allTabButtons = {self.filesTab, self.requiredTab, self.requiredByTab}
    for i=1, #allTabButtons do
        local btn = allTabButtons[i]
        if btn.internal == button.internal then loadInfo(btn) end
        changeColor(btn, btn.internal == button.internal)
    end

    self.infoList.selectedTab = button.internal
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

    self.applyBtn = createButton(self.width - PADDING * 2 - BUTTON_HGT * 4, self.height - PADDING - BUTTON_HGT, BUTTON_HGT * 4, BUTTON_HGT, "Apply", self, self.applyMode)
    self:addChild(self.applyBtn)

    self.closeBtn = createButton(PADDING * 2, self.applyBtn.y, BUTTON_HGT * 4, BUTTON_HGT, "Close", self, self.close)
    self:addChild(self.closeBtn)
    -- #endregion


    -- #region Current mods order (left)
    local modsOrder = scrollExt.createList(self, PADDING * 2, y_offset, innerWitdth * 0.4 - PADDING, innerHeight)
    modsOrder.itemheight = FONT_HGT_SMALL + 8
    scrollExt:addTitle(modsOrder, "Mods Order:", nil, nil, nil, - BUTTON_HGT - PADDING)
    modsOrder.borderColor = borderColorLight
    modsOrder.font = UIFont.Small
    modsOrder.doDrawItem = scrollDoDrawItem
    -- modsOrder.onMouseDown = function(box, xx, yy)
    --     ISScrollingListBox.onMouseDown(box, xx, yy)
    --     local row = box.items[box.selected]
    --     if row then click(self, row.item.modId) end
    -- end
    scrollExt:addSearchEntry(modsOrder, nil, true)
    scrollExt:addBackground(modsOrder, nil, {})
    self.modsOrderList = modsOrder
    self:addChild(self.modsOrderList)
    -- #endregion

    -- Buttons block (center)
    local center_x = modsOrder:getRight() + PADDING
    local panel = ISPanel:new(center_x, self.modsOrderList.y, innerWitdth * 0.2 + 1, BUTTON_HGT * 3 + PADDING * 4)
    panel:initialise()
    panel:instantiate()
    panel.borderColor = borderColorLight
    self:addChild(panel)

    self.loadAfter = createButton(center_x + PADDING, self.modsOrderList.y + PADDING, panel.width - PADDING * 2, BUTTON_HGT, getText("UI_MLOS_SortingRules_load_after_btn"), self, self.onButtonClick)
    self.loadAfter.internal = "LOAD_AFTER"
    self:addChild(self.loadAfter)

    self.loadBefore = createButton(center_x + PADDING, self.loadAfter:getBottom() + PADDING, self.loadAfter.width, BUTTON_HGT, getText("UI_MLOS_SortingRules_load_before_btn"), self, self.onButtonClick);
    self.loadBefore.internal = "LOAD_BEFORE"
    self:addChild(self.loadBefore)

    self.incompatible = createButton(center_x + PADDING, self.loadBefore:getBottom() + PADDING, self.loadAfter.width, BUTTON_HGT, getText("UI_MLOS_SortingRules_incompatible_btn"), self, self.onButtonClick);
    self.incompatible.internal = "INCOMPATIBLE"
    self:addChild(self.incompatible)


    local loadTr = {on=getText("UI_MLOS_SortingRules_yes"), off=getText("UI_MLOS_SortingRules_no"), category=getText("UI_MLOS_SortingRules_in_category")}
    local loadFirstTr = getText("UI_MLOS_SortingRules_LoadFirst")
    local loadLastTr = getText("UI_MLOS_SortingRules_LoadLast")

    self.loadFirstComboBox = ISComboBox:new(center_x, self.incompatible:getBottom() + PADDING * 3, innerWitdth * 0.2 - PADDING, BUTTON_HGT, self, self.onComboBoxChange)
    self:addChild(self.loadFirstComboBox)

    self.loadLastComboBox = ISComboBox:new(center_x, self.loadFirstComboBox:getBottom() + PADDING, self.loadFirstComboBox.width, BUTTON_HGT, self, self.onComboBoxChange)
    self:addChild(self.loadLastComboBox)

    for name, _ in pairs(core.loadCategories) do
        self.loadFirstComboBox:addOptionWithData(loadFirstTr .. ": " .. tostring(loadTr[name]), name)
        self.loadLastComboBox:addOptionWithData(loadLastTr .. ": " .. tostring(loadTr[name]), name)
    end

    self.categoryComboBox = ISComboBox:new(center_x, self.loadLastComboBox:getBottom() + PADDING, self.loadFirstComboBox.width, BUTTON_HGT, self, self.onComboBoxChange)
    self:addChild(self.categoryComboBox)



    -- Editing list (right)
    local editingModeList = scrollExt.createList(self, PADDING * 2 + innerWitdth * 0.6, self.modsOrderList.y, innerWitdth * 0.4, innerHeight * 0.5 - PADDING - BUTTON_HGT)
    editingModeList.itemheight = FONT_HGT_SMALL + 8
    scrollExt:addTitle(editingModeList, "Mods in selected mode:", nil, nil, nil, - BUTTON_HGT - PADDING)
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
    self:drawTextCentre('Sorting Rules Editor', self.width * 0.5, PADDING * 2, 1, 1, 1, 1, UIFont.Large)
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
