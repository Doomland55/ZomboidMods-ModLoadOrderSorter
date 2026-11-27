require "ISUI/ISPanelJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISToolTip"
require "ISUI/ISModalDialog"
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local sorter = require('REfRigERatoR_ModLoadOrderSorter/Core/2_SortingCore')
local scrollExt = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/ScrollExtensions')
local popup = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/WarningPopup')


local SortingRulesEditor = ISPanelJoypad:derive('MLOS_SortingRulesEditor')
-- Shared by rule targets and their edit buttons (in descending display priority).
local ruleStyles = {
    incompatibleMods = { letter = "I", button = "incompatible", color = { r = .65, g = .25, b = .85, a = .35 } },
    loadBefore = { letter = "B", button = "loadBefore", color = { r = .2, g = .7, b = .3, a = .35 } },
    loadAfter = { letter = "A", button = "loadAfter", color = { r = .2, g = .4, b = .9, a = .35 } },
    require = { letter = "R" },
    requiredBy = { letter = "D" },
    changed = {letter = "*", textColor = { r = 1, g = 0, b = 0, a = 0.7 }},
    default = {textColor = { r = 1, g = 1, b = 1, a = 1 }, color={ r = 0, g = 0, b = 0, a = .95 }}
}

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = math.max(25, FONT_HGT_SMALL + 3 * 2)
local PADDING = 10
local DEFAULT_TEXT_COLOR = {r = 0.9, g = 0.9, b = 0.9}
local borderColorLight = { r = 1, g = 1, b = 1, a = 0.6 }
local borderColorDark = { r = 1, g = 1, b = 1, a = 0.2 }

function SortingRulesEditor:new(x, y, width, height, modOrderPanel)
    local o = ISPanelJoypad:new(x, y, width, height)
    setmetatable(o, self); self.__index = self
    o.owner = modOrderPanel
    o.sortingRules = core.layers.SortingRules:beginEdit()  -- deepCopy of currentRules list

    o.editModeData = nil
    o.modsById = {} -- {modId: item}
    o.changesList = {} -- {modId: changesDict}
    o.higlightMods = {}

    -- o.savedRules = utils:deepCopy(o.sortingRules)
    -- o.dirtyRules = {}
    o.backgroundColor = { r = 0, g = 0, b = 0, a = .95 }
    return o
end


--- OK
function SortingRulesEditor:instantiate()
    ISPanelJoypad.instantiate(self)
    self:fillMods()
    self:selectTab(self.filesTab)
end


--- OK
function SortingRulesEditor:fillMods()
    self.modsOrderList:clear()
    self.modsById = {}

    local items = self.owner.modList.items
    for i=1, #items do
        local row = items[i].item
        local item = self.modsOrderList:addItem("", {icon=row.icon, modId=row.modId, name=row.name})
        item.color = DEFAULT_TEXT_COLOR
        item.tooltip = items[i].tooltip
        self.modsById[row.modId] = item.item
    end
    self.modsOrderList.selected = 0
end


--- OK
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

--- OK
function SortingRulesEditor:refreshInfoList()
    self.infoList:clear()
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
        self.infoList:addItem("", {name = mod and mod.name or value, modId = tab ~= "FILES_TAB" and value or nil})
    end
end


function SortingRulesEditor:prerender()
    ISPanelJoypad.prerender(self)
    local title = 'Sorting Rules Editor'
    -- if self:inEditMode() then
    --     local row = self.modsOrderList.items[self.editSelected]
    --     title = getText("UI_MLOS_Editor_Editing", self[self.editMode.button].title, row.item.name)
    -- end
    -- if self.hasUnsavedChanges then title = title .. " *" end
    self:drawTextCentre(title, self.width * 0.5, PADDING * 2, 1, 1, 1, 1, UIFont.Large)
end


-- #region My Local functions
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
    local color = item.color or DEFAULT_TEXT_COLOR
    local modId = item.item.modId

    -- local bc = self.borderColor or item.borderColor
    -- if bc then self:drawRectBorder(0, y, self.width, item.height - 1, bc.a, bc.r, bc.g, bc.b) end
    local parent = self.parent

    local bg = parent.higlightMods[modId] or item.background
    if bg then self:drawRect(0, y, self.width, item.height - 1, bg.a, bg.r, bg.g, bg.b) end

    if self.selected == item.index then
        local scolor = core.COLORS.selection
        self:drawRect(0, y, self.width, item.height - 1, scolor.a, scolor.r, scolor.g, scolor.b)
    end
    if item.item.icon and item.item.icon ~= "" then
        self:drawTextureScaled(getTexture(item.item.icon), 3, y + 3, item.height - 6, item.height - 6, 1, 1, 1, 1)
    end
    self:drawText(item.item.name, item.height + 6, y + 3, color.r, color.g, color.b, 0.9, self.font )
    return y + item.height
end

local function drawIcon(slf, _, localx, localy, element, name)
    local style = ruleStyles[name] or {}
    local color = style.color
    local textColor = style.textColor or ruleStyles.default.textColor
    if color then slf:drawRect(localx, localy + element.y, element.width, element.height, 0.8, color.r, color.g, color.b) end
    slf:drawTextCentre(style.letter, localx + element.width * 0.5, localy + element.y, textColor.r, textColor.g, textColor.b, textColor.a, UIFont.Small)
end

local function calcTooltip(label, info, ids)
    local lines = {getText("UI_MLOS_Editor_Badge_" .. label, tostring(#ids))}
    for i=1, #ids do
        local mod = info and info.data[ids[i]]
        local name = mod and mod.name or ids[i]
        lines[#lines + 1] = name
    end
    return table.concat(lines, " <LINE> ")
end

local function drawRuleBadges(slf, item, localx, localy, element)
    local mouseX = slf:getMouseX()
    local mouseY = slf:getMouseY()

    local modId = item.item.modId
    local modSR = slf.parent.sortingRules[modId] or {}

    local layer = core.layers.ModsInfo
    local info = layer and layer.data[item.item.modId] or {}

    local changes = slf.parent.changesList[modId] or {}
    local changedIds = {}; for k, _ in pairs(changes) do changedIds[#changedIds+1] = k end

    local namesVisibility = {
        changed = { ids = changedIds, tooltip = "Changes"},
        require = { ids = info.requirements, tooltip = "Required mods"},
        requiredBy = { ids = info.requiredBy, tooltip = "Dependent mods"},
        incompatibleMods = { ids = modSR.incompatibleMods, tooltip = "Incompatible Mods"},
        loadBefore = { ids = modSR.loadBefore, tooltip = "LoadBefore mods"},
        loadAfter = { ids = modSR.loadAfter, tooltip = "LoadAfter mods"},
    }

    for name, data in pairs(namesVisibility) do
        if not utils:tableIsEmpty(data.ids) then
            localx = localx - element.width - 3
            drawIcon(slf, item, localx, localy, element, name)
            if slf.mouseoverselected == item.index and utils.pointInRectCoords(mouseX, mouseY, localx, localy + element.y, element.width, element.height) then
                slf.mouseOverElement = element
                local elementId = item.index * 1000 + localx
                if element.id ~= elementId then
                    element.index = item.index
                    element.tooltip = calcTooltip(name, layer, data.ids)
                    element.id = elementId
                end
            end
        end
    end
end

-- #endregion






-- #region Editing mode
function SortingRulesEditor:inEditMode()
    return self.editModeData ~= nil
end

function SortingRulesEditor:onEditingEnter(mode)
    local selected = self.modsOrderList.selected
    if selected and not (selected > 1 and selected <= #self.modsOrderList.items) then return end

    self.editModeData = {
        item = self.modsOrderList.selected,
        data = nil
    }

    -- load data to UI editing scroll list
    self:fillEditingList()

    -- highlight data in modsOrder list

    -- disable buttons
end

function SortingRulesEditor:onEditingExit(save)
    -- check is dirty
    if save == true then
        -- apply changes (from editing list to data)
    end
    -- clear editing scroll list
    -- enable buttons
    self.editModeData = nil
end


local function onEditingListMouseDown(self, x, y)
    local editor = self.parent
    if not editor:inEditMode() then return end
    self:removeItemByIndex(self.mouseOverElement.index)
end

-- #endregion





function SortingRulesEditor:addToChanges(modId, name, value)
    local origData = self.sortingRules[modId] or {}
    local changes = self.changesList[modId] or {}

    if origData[name] ~= value then changes[name] = value
    else changes[name] = nil end
    self.changesList[modId] = changes
end


function SortingRulesEditor:onComboBoxChange(combo)
    local selected = self.modsOrderList.items[self.modsOrderList.selected]
    if not selected then return end

    local modId = selected.item.modId
    local key = combo.internal
    local value = combo:getOptionData(combo.selected)

    self:addToChanges(modId, key, value)
end


function SortingRulesEditor:updateComboBoxValues(item)
    local modId = item.item.modId
    local rule = self.sortingRules[modId] or {}

    local modsInfo = core.layers.ModsInfo
    local info = modsInfo and modsInfo.data and modsInfo.data[modId] or {}

    self.loadFirstComboBox:selectData(rule.loadFirst or "off")
    self.loadLastComboBox:selectData(rule.loadLast or "off")
    self.categoryComboBox:selectData(rule.category or info.category or "undefined")
end


local function highlightModRules(self, modId)
    self.higlightMods = {}
    local modSR = self.sortingRules[modId] or {}

    local namesVisibility = {
        loadAfter = modSR.loadAfter,
        loadBefore = modSR.loadBefore,
        incompatibleMods = modSR.incompatibleMods,}

    for name, data in pairs(namesVisibility) do
        local styles = ruleStyles[name]
        for i=1, #data do
            self.higlightMods[data[i]] = styles.color
        end
    end
end


function SortingRulesEditor.onModsOrderMouseDown(slf, x, y)
    ISScrollingListBox.onMouseDown(slf, x, y)
    local clickedId = slf.mouseoverselected
    local item = slf.items[clickedId]
    if not item then return end

    local parent = slf.parent
    local modId = item.item.modId
    if parent:inEditMode() then
        if parent.editModeData.data[modId] == nil then
            local data = parent.modsById[modId] or {modId = modId, name = modId}
            parent.editingModeList:addItem("", data)
            parent.editModeData.data[modId] = true
        else
            parent.editingModeList:removeItemByIndex(clickedId)
            parent.editModeData.data[modId] = nil
        end
    else
        parent:updateComboBoxValues(item)
        parent:refreshInfoList()
    end

    -- higlight mods for rules
    highlightModRules(parent, modId)
end


function SortingRulesEditor.onInfoListMouseDown(slf, x, y)
    ISScrollingListBox.onMouseDown(slf, x, y)
    local parent = slf.parent
    if parent:inEditMode() or slf.selectedTab == "FILES_TAB" then return end

    local index = slf.mouseoverselected
    local row = index and slf.items[index]
    if not row then return end
    for i, mod in ipairs(parent.modsOrderList.items) do
        if mod.item.modId == row.item.modId then
            parent.modsOrderList.selected = i
            parent.modsOrderList:ensureVisible(i)
            -- self:onModClick()
            return
        end
    end
end



function SortingRulesEditor:close()
    if self.closeDialog then return end
    if self.hasUnsavedChanges then
        local w = 300
        local h = 100
        local dialog = ISModalDialog:new(getCore():getScreenWidth()/2 - w/2, getCore():getScreenHeight() / 2 - h/2, w, h, getText("UI_MLOS_Editor_Discard"), true,
            self, function(editor, button)
                editor.closeDialog = nil
                if button.internal == "YES" then editor:discardAndClose() end
            end)
        self.closeDialog = dialog
        dialog:initialise()
        dialog:addToUIManager()
        dialog:setAlwaysOnTop(true)
        return
    end
    self:discardAndClose()
end


function SortingRulesEditor:discardAndClose()
    self:setVisible(false)
    self.owner:setVisible(true)
    self:removeFromUIManager()
end




-- local EMPTY_RULE = {}
-- local function sameRule(a, b)
--     a, b = a or EMPTY_RULE, b or EMPTY_RULE
--     if (a.loadFirst or "off") ~= (b.loadFirst or "off")
--         or (a.loadLast or "off") ~= (b.loadLast or "off") or a.category ~= b.category then return false end
--     for _, style in ipairs(ruleStyles) do
--         local left, right = a[style.key] or EMPTY_RULE, b[style.key] or EMPTY_RULE
--         if #left ~= #right then return false end
--         local ids = {}
--         for _, id in ipairs(left) do ids[id] = (ids[id] or 0) + 1 end
--         for _, id in ipairs(right) do
--             if not ids[id] or ids[id] == 0 then return false end
--             ids[id] = ids[id] - 1
--         end
--     end
--     return true
-- end



-- function SortingRulesEditor:updateDirty(modId)
--     local rule = self.editMode and self.editModId == modId and self.editRule or self.sortingRules[modId]
--     self.dirtyRules[modId] = not sameRule(rule, self.savedRules[modId]) or nil
--     self.hasUnsavedChanges = not utils:tableIsEmpty(self.dirtyRules)
--     self.applyBtn.enable = self.hasUnsavedChanges
-- end



-- -- Rebuilt on selection/edit events, not for each visible row on every frame.
-- function SortingRulesEditor:refreshRuleBackgrounds()
--     local backgrounds = {}
--     self.ruleBackgrounds = backgrounds
--     if self.editMode then
--         for _, id in ipairs(self.editRule[self.editMode.key]) do
--             backgrounds[id] = self.editMode.color
--         end
--         return
--     end
--     local list = self.modsOrderList
--     local selected = list.items[list.selected]
--     local rule = selected and self.sortingRules[selected.item.modId]
--     if not rule then return end
--     for _, style in ipairs(ruleStyles) do
--         local ids = rule[style.key]
--         if ids then
--             for _, id in ipairs(ids) do
--                 if not backgrounds[id] then backgrounds[id] = style.color end
--             end
--         end
--     end
-- end

-- function SortingRulesEditor:getRuleBackground(modId)
--     return self.ruleBackgrounds and self.ruleBackgrounds[modId]
-- end







-- function SortingRulesEditor:onComboBoxChange(combo)
--     local selected = self.modsOrderList.items[self.modsOrderList.selected]
--     if not selected then return end
--     local rule = self.editRule or self.sortingRules[selected.item.modId] or {}
--     if not self.editMode then self.sortingRules[selected.item.modId] = rule end
--     local key = combo == self.loadFirstComboBox and "loadFirst"
--         or combo == self.loadLastComboBox and "loadLast" or "category"
--     local value = combo:getOptionData(combo.selected)
--     if key == "category" and value == "automatic" then value = nil end
--     rule[key] = value
--     self:updateDirty(selected.item.modId)
-- end


function SortingRulesEditor:fillEditingList()
    self.editingModeList:clear()
    if not self:inEditMode() then return end

    for name, _ in pairs(self.editModeData.data) do
        local data = self.modsById[name] or {modId = name, name = name}
        self.editingModeList:addItem("", data)
    end
end




-- function SortingRulesEditor:finishEdit()
--     local modId = self.editModId
--     self.editMode = nil
--     self.editRule = nil
--     self.editOriginalRule = nil
--     self.editModId = nil
--     self.editSelected = nil
--     self.modeApplyBtn.enable = false
--     self.modeCancelBtn.enable = false
--     self.simulateBtn.enable = true
--     self.editingModeList.borderColor = borderColorLight
--     for _, style in ipairs(ruleStyles) do
--         self[style.button].enable = true
--         self[style.button].borderColor = borderColorLight
--     end
--     self:updateDirty(modId)
--     self:refreshEditingList()
--     self:onModClick()
-- end

-- function SortingRulesEditor:cancelMode()
--     if not self.editMode then return end
--     self.sortingRules[self.editModId] = utils:deepCopy(self.editOriginalRule)
--     self:finishEdit()
-- end

-- function SortingRulesEditor:onEditModeClick(button)
--     local style
--     for _, candidate in ipairs(ruleStyles) do
--         if self[candidate.button] == button then style = candidate; break end
--     end
--     if not style then return end
--     if self.editMode then return end
--     local selected = self.modsOrderList.items[self.modsOrderList.selected]
--     if not selected then return end
--     self.editMode = style
--     self.editModId = selected.item.modId
--     self.editSelected = self.modsOrderList.selected
--     -- Keep nil intact so cancelling a new rule does not leave an empty entry.
--     self.editOriginalRule = utils:deepCopy(self.sortingRules[self.editModId])
--     self.editRule = utils:deepCopy(self.editOriginalRule or {})
--     self.editRule[style.key] = self.editRule[style.key] or {}
--     button.borderColor = {r = 1, g = 1, b = 1, a = 1}
--     self.modeApplyBtn.enable = true
--     self.modeCancelBtn.enable = true
--     self.simulateBtn.enable = false
--     for _, candidate in ipairs(ruleStyles) do self[candidate.button].enable = false end
--     self.editingModeList.borderColor = {r = style.color.r, g = style.color.g, b = style.color.b, a = 1}
--     self:refreshEditingList()
-- end

-- function SortingRulesEditor:applyMode()
--     if not self.editMode then return end
--     self.sortingRules[self.editModId] = utils:deepCopy(self.editRule)
--     self:finishEdit()
-- end

-- function SortingRulesEditor:simulate()
--     -- if self.editMode then return end
--     -- local list = self.modsOrderList
--     -- local selected = list.items[list.selected]
--     -- local selectedId = selected and selected.item.modId
--     -- local sortedIds = sorter:sort(list.items, self.sortingRules)
--     -- -- Do not call applyOrder: it writes the real load-order backup to disk.
--     -- local byId, reordered = {}, {}
--     -- for _, row in ipairs(list.items) do byId[row.item.modId] = row end
--     -- for _, id in ipairs(sortedIds) do
--     --     if byId[id] then
--     --         reordered[#reordered + 1] = byId[id]
--     --         byId[id] = nil
--     --     end
--     -- end
--     -- for _, row in ipairs(list.items) do
--     --     if byId[row.item.modId] then
--     --         reordered[#reordered + 1] = row
--     --         byId[row.item.modId] = nil
--     --     end
--     -- end
--     -- list.items = reordered
--     -- list.selected = 0
--     -- for i, row in ipairs(reordered) do
--     --     row.index = i
--     --     row.itemindex = i
--     --     if row.item.modId == selectedId then list.selected = i end
--     -- end
--     -- -- Search results contain row indices from the old order.
--     -- list.foundItems = {}
--     -- list.foundIndex = 0
--     -- list.foundCounter = 0
--     -- if list.selected > 0 then list:ensureVisible(list.selected) end
--     -- self:onModClick()
--     -- for _, warning in ipairs(sorter.warnings or {}) do
--     --     self.warningPopup:addMessage(warning.title, warning.message, warning.layer, warning.severity)
--     -- end
-- end

-- function SortingRulesEditor:applyChanges()
--     if self.editMode then self:applyMode() end
--     if not core.layers.SortingRules:commitEdit(utils:deepCopy(self.sortingRules)) then
--         self.warningPopup:addMessage("Sorting Rules", "Failed to save sorting rules.", "SortingRules", "CRITICAL")
--         return
--     end
--     self.savedRules = utils:deepCopy(self.sortingRules)
--     self.dirtyRules = {}
--     self.hasUnsavedChanges = false
--     self.applyBtn.enable = false
-- end




-- -- Refresh only on selection/tab events, never from the draw loop.
-- function SortingRulesEditor:refreshInfoList()
--     self.infoList:clear()
--     self.infoList:setYScroll(0)
--     local selected = self.modsOrderList.items[self.modsOrderList.selected]
--     if not selected then return end

--     local id = selected.item.modId
--     local infoLayer = core.layers.ModsInfo
--     local info = infoLayer and infoLayer.data[id] or {}
--     local tab = self.infoList.selectedTab
--     local data = {}
--     if tab == "FILES_TAB" then
--         local filesLayer = core.layers.ModsFiles
--         local mod = filesLayer and filesLayer.data[id]
--         data = mod and mod.files or {}
--     elseif tab == "REQUIRED_TAB" then
--         data = info.requirements or {}
--     elseif tab == "REQUIRED_BY_TAB" then
--         data = info.requiredBy or {}
--     end

--     for _, value in ipairs(data) do
--         local mod = tab ~= "FILES_TAB" and infoLayer and infoLayer.data[value]
--         self.infoList:addItem("", {name = mod and mod.name or value,
--             modId = tab ~= "FILES_TAB" and value or nil})
--     end
-- end

-- local function selectComboValue(combo, value)
--     combo.selected = 1
--     for i = 1, #combo.options do
--         if combo:getOptionData(i) == value then
--             combo.selected = i
--             return
--         end
--     end
-- end



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

    self.applyBtn = createButton(self.width - PADDING * 2 - BUTTON_HGT * 4, self.height - PADDING - BUTTON_HGT, BUTTON_HGT * 4, BUTTON_HGT, getText("UI_MLOS_Editor_Apply"), self, self.applyChanges)
    self.applyBtn.enable = false
    self:addChild(self.applyBtn)

    local closeBtn = createButton(PADDING * 2, self.applyBtn.y, BUTTON_HGT * 4, BUTTON_HGT, "Close", self, self.close)
    self:addChild(closeBtn)

    self.simulateBtn = createButton((self.width - BUTTON_HGT * 4) / 2, self.applyBtn.y, BUTTON_HGT * 4, BUTTON_HGT, getText("UI_MLOS_Editor_Simulate"), self, self.simulate)
    self:addChild(self.simulateBtn)
    -- #endregion

    -- #region Current mods order (left)
    local modsOrder = scrollExt.createList(self, PADDING * 2, y_offset, innerWitdth * 0.4 - PADDING, innerHeight)
    modsOrder.itemheight = FONT_HGT_SMALL + 8
    modsOrder.borderColor = borderColorLight
    modsOrder.font = UIFont.Small
    modsOrder.doDrawItem = scrollDoDrawItem
    scrollExt:addTitle(modsOrder, function() return self.editMode and getText("UI_MLOS_Editor_ClickHint") or "Mods Order:" end, nil, nil, UIFont.Small, - BUTTON_HGT - PADDING * 0.5)
    scrollExt:addSearchEntry(modsOrder, nil, true)
    scrollExt:addBackground(modsOrder, nil, {})
    scrollExt.addItemElement(modsOrder, -5, 3, modsOrder.itemheight - 7, modsOrder.itemheight - 7, drawRuleBadges,  true, nil, nil, true )
    -- scrollExt:addItemContextMenu(modsOrder, "Add to LoadAfter", nil, function(slf, selectedRawItems, row, item) local modId = item.item.modId;  end)
    modsOrder.onMouseDown = self.onModsOrderMouseDown
    self.modsOrderList = modsOrder
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

    for _, style in pairs(ruleStyles) do
        if style.button then
            local button = self[style.button]
            local c = style.color
            button.backgroundColor = { r = c.r, g = c.g, b = c.b, a = c.a }
            button.backgroundColorMouseOver = { r = c.r, g = c.g, b = c.b, a = .6 }
        end
    end

    local actionWidth = (self.loadAfter.width - PADDING) / 2
    self.modeCancelBtn = createButton(center_x + PADDING, self.incompatible:getBottom() + PADDING, actionWidth, BUTTON_HGT, getText("UI_MLOS_Editor_Cancel"), self, self.cancelMode)
    self.modeCancelBtn.enable = false
    self:addChild(self.modeCancelBtn)

    self.modeApplyBtn = createButton(self.modeCancelBtn:getRight() + PADDING, self.modeCancelBtn.y, actionWidth, BUTTON_HGT, getText("UI_MLOS_Editor_Apply"), self, self.applyMode)
    self.modeApplyBtn.enable = false
    self:addChild(self.modeApplyBtn)


    local loadTr = {on=getText("UI_MLOS_SortingRules_yes"), off=getText("UI_MLOS_SortingRules_no"), category=getText("UI_MLOS_SortingRules_in_category")}
    local loadFirstTr = getText("UI_MLOS_SortingRules_LoadFirst")
    local loadLastTr = getText("UI_MLOS_SortingRules_LoadLast")

    self.loadFirstComboBox = ISComboBox:new(center_x, self.modeApplyBtn:getBottom() + PADDING * 2, innerWitdth * 0.2 - PADDING, BUTTON_HGT, self, self.onComboBoxChange)
    self.loadFirstComboBox.internal = "loadFirst"
    self:addChild(self.loadFirstComboBox)

    self.loadLastComboBox = ISComboBox:new(center_x, self.loadFirstComboBox:getBottom() + PADDING, self.loadFirstComboBox.width, BUTTON_HGT, self, self.onComboBoxChange)
    self.loadLastComboBox.internal = "loadLast"
    self:addChild(self.loadLastComboBox)

    for _, name in ipairs({"off", "on", "category"}) do
        self.loadFirstComboBox:addOptionWithData(loadFirstTr .. ": " .. tostring(loadTr[name]), name)
        self.loadLastComboBox:addOptionWithData(loadLastTr .. ": " .. tostring(loadTr[name]), name)
    end

    self.categoryComboBox = ISComboBox:new(center_x, self.loadLastComboBox:getBottom() + PADDING, self.loadFirstComboBox.width, BUTTON_HGT, self, self.onComboBoxChange)
    self.categoryComboBox.internal = "category"
    self:addChild(self.categoryComboBox)
    -- self.categoryComboBox:addOptionWithData("Automatic", "automatic")
    for _, category in ipairs(core.rawCategoryOrder) do
        self.categoryComboBox:addOptionWithData(category, category)
    end
    -- self.loadFirstComboBox.disabled = true
    -- self.loadLastComboBox.disabled = true
    -- self.categoryComboBox.disabled = true

    -- Editing list (right)
    local editingModeList = scrollExt.createList(self, PADDING * 2 + innerWitdth * 0.6, self.modsOrderList.y, innerWitdth * 0.4, innerHeight * 0.5 - PADDING - BUTTON_HGT)
    editingModeList.itemheight = FONT_HGT_SMALL + 8
    editingModeList.font = UIFont.Small
    editingModeList.selected = 0
    editingModeList.doDrawItem = scrollDoDrawItem
    scrollExt.addItemElement(editingModeList, - 8 - editingModeList.itemheight , 3, editingModeList.itemheight - 3, editingModeList.itemheight - 3, Texture.getWhite(), true, "Remove item", onEditingListMouseDown)
    scrollExt:addTitle(editingModeList, 
        function()
            if not self:inEditMode() then return "Mods in selected mode:" end
            return getText("UI_MLOS_Editor_Targets", self[self.editMode.button].title, tostring(#(self.editRule[self.editMode.key] or {}))) end, 
            nil, nil, UIFont.Small, - BUTTON_HGT - PADDING * 0.5)
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
    infoList.onMouseDown = self.onInfoListMouseDown
    self.infoList = infoList

    --#endregion

end

return SortingRulesEditor
