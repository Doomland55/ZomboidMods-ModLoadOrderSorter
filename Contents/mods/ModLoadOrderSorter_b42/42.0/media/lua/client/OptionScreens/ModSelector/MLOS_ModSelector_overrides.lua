---
---	This mod updates the behavior of automatic sorting, added to the Project Zomboid build 42.0. 
--- Adds own topological sorting algorithm for mods load order, 
--- and adds support for sorting rules from the file sorting_rules.txt.
---
--- Details about this mod:
--- Mod: Mod Load Order Sorter
--- Author: REfRigERatoR
--- Profile: https://steamcommunity.com/profiles/76561198108707962/
---
--- This mod has no dependencies
---
require('OptionScreens/ModSelector/ModSelector')
local utils = require('OptionScreens/ModSelector/Refr_utils')
local MLOS_methods = require('OptionScreens/ModSelector/MLOS_Methods')
local MLOS_sorting = require('OptionScreens/ModSelector/MLOS_sorting')
local SortingRulesPanel = require('OptionScreens/ModSelector/MLOS_SortingRulesPanel')

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = math.max(25, FONT_HGT_SMALL + 3 * 2)

local ModLoadOrderPanelOverride = ModSelector.ModLoadOrderPanel
local ModOrderListBoxOverride = ModSelector.ModOrderListBox

local rulesTexture = getTexture("media/ui/MLOS_Button_Rules.png")


--================================================
--      ModLoadOrderPanelOverride Overrides
--================================================
local origCreateChildren = ModLoadOrderPanelOverride.createChildren
local origOnMouseUpOutside = ModLoadOrderPanelOverride.onMouseUpOutside


function ModLoadOrderPanelOverride:createChildren()
    origCreateChildren(self)
    self:addCache()

    self.searchEntry = ISTextEntryBox:new("", self.modList:getX(), self.modList:getY() - 12 - BUTTON_HGT, self.modList:getWidth() / 3.0 , BUTTON_HGT)
    self.searchEntry.font = UIFont.Small
    self.searchEntry.onTextChange = function() self:onChangeText() end
    self.searchEntry:initialise()
    self.searchEntry:instantiate()
    self:addChild(self.searchEntry)

    self.searchBtnPrev = ISButton:new(self.searchEntry:getRight() + 8, self.searchEntry:getY(), BUTTON_HGT, BUTTON_HGT, "/\\", self, self.onSearchButton);
    self.searchBtnPrev.internal = "PREV_SEARCH";
    self.searchBtnPrev:initialise();
    self.searchBtnPrev:instantiate();
    self.searchBtnPrev:setAnchorLeft(true);
    self.searchBtnPrev:setAnchorRight(false);
    self.searchBtnPrev:setAnchorTop(false);
    self.searchBtnPrev:setAnchorBottom(true);
    self.searchBtnPrev.borderColor = {r=1, g=1, b=1, a=0.2};
    self.searchBtnPrev:setFont(UIFont.Small);
    self.searchBtnPrev:ignoreWidthChange();
    self.searchBtnPrev:ignoreHeightChange();
    self:addChild(self.searchBtnPrev);

    self.searchBtnNext = ISButton:new(self.searchBtnPrev:getRight() + 8, self.searchEntry:getY(), BUTTON_HGT, BUTTON_HGT, "\\/", self, self.onSearchButton);
    self.searchBtnNext.internal = "NEXT_SEARCH";
    self.searchBtnNext:initialise();
    self.searchBtnNext:instantiate();
    self.searchBtnNext:setAnchorLeft(true);
    self.searchBtnNext:setAnchorRight(false);
    self.searchBtnNext:setAnchorTop(false);
    self.searchBtnNext:setAnchorBottom(true);
    self.searchBtnNext.borderColor = {r=1, g=1, b=1, a=0.2};
    self.searchBtnNext:setFont(UIFont.Small);
    self.searchBtnNext:ignoreWidthChange();
    self.searchBtnNext:ignoreHeightChange();
    self:addChild(self.searchBtnNext);

    self.sortingRules = SortingRulesPanel:new(self:getRight(), 0, self.width * 0.3, 180, self.modList)
	self.sortingRules:initialise()
	self.sortingRules:instantiate()
    self.sortingRules:setAlwaysOnTop(true)
end


function ModLoadOrderPanelOverride:onMouseUpOutside(x, y)
    origOnMouseUpOutside(self, x, y)
    if self.modList.dragItem ~= nil then return end
    if not self:isMouseOver() then
        self.multiselected = {}
    end
end


function ModLoadOrderPanelOverride:autoSort()
    -- Sort mods  (targetOrder is an array of modId)
    local targetOrder = MLOS_sorting:SortModsOrder(self.modList.items)
    -- apply mods order
    local newItems = {}
    for i, val in ipairs(targetOrder) do
        newItems[i] = MLOS_sorting.modsInfoCache[val].object
    end
    self.modList.items = newItems
end


function ModLoadOrderPanelOverride:getTooltip(modInfo)
    return nil
end


function ModLoadOrderPanelOverride:addCache()
    self.foundItems = {}
    self.foundIndex = 0
    self.foundCounter = 0

    self.multiselected = {}
    self.multiselected_temp = {}
    self.multiselected_counter = 150
end


function ModLoadOrderPanelOverride:updateCache()
    self:onChangeText()
    if not utils:tableIsEmpty(self.multiselected) then
        self.multiselected = {}
        self.multiselected_counter = 150 * #self.multiselected_temp
    end
end


--================================================
--           Search Items methods
--================================================


function ModLoadOrderPanelOverride:onChangeText()
    if not utils:tableIsEmpty(self.foundItems) then
        self.foundItems = {}
        self.foundIndex = 0
    end
end


function ModLoadOrderPanelOverride:searchItems()
    if not utils:tableIsEmpty(self.foundItems) then return end

    local searchWord = string.lower(self.searchEntry:getInternalText())
    if not searchWord or searchWord == "" then return end

    for i, item in ipairs(self.modList.items) do
        if string.find(string.lower(item.item.name), searchWord) or string.find(string.lower(item.item.modId), searchWord) then
            table.insert(self.foundItems, i)
        end
    end
end


function ModLoadOrderPanelOverride:onSearchButton(button)
    self:searchItems()
    if utils:tableIsEmpty(self.foundItems) then return end

    if button.internal == "NEXT_SEARCH" then self.foundIndex = self.foundIndex + 1 end
    if button.internal == "PREV_SEARCH" then self.foundIndex = self.foundIndex - 1 end

    if self.foundIndex > #self.foundItems then self.foundIndex = 1 end
    if self.foundIndex < 1 then self.foundIndex = #self.foundItems end

    local itemIndex = self.foundItems[self.foundIndex]
    if itemIndex ~= nil then
        self.modList:ensureVisible(itemIndex)
        self.foundCounter = 400
    end
end

--================================================
-- Scroll list box up or down if mouse is outside 
--================================================

function ModLoadOrderPanelOverride:render()
    ISPanelJoypad.render(self)
    if self.modList.dragItem == nil then return end

    local mY = self:getMouseY()
    local diff = 0
    if mY < self.modList:getY() then diff = mY - self.modList:getY() end
    if mY > self.modList:getBottom() then diff = mY - self.modList:getBottom() end
    if diff == 0 then return end

    self.modList:setYScroll(self.modList:getYScroll() - (diff * 0.02 * UIManager.getMillisSinceLastRender()))
end

--================================================
--      ModOrderListBoxOverride Overrides
--================================================

local origDoDrawItem = ModOrderListBoxOverride.doDrawItem
local origOnMouseDown = ModOrderListBoxOverride.onMouseDown


function ModOrderListBoxOverride:updateModsColor()
    self.parent:updateCache()
    self.mouseOverRulesIcon = nil

    self.parent.acceptButton.enable = MLOS_sorting:validateSorting(self.items)
    for i, val in ipairs(self.items) do
        val.itemindex = i  -- update item index
		local extraModInfo = MLOS_sorting.modsInfoCache[val.item.modId]
        if extraModInfo ~= nil then
            if not utils:tableIsEmpty(extraModInfo.warnings.missing) then
                val.color = {r = 0.98, g = 0.08, b = 0.08}
            elseif not utils:tableIsEmpty(extraModInfo.warnings.incompatible) then
                val.color = {r = 0.65, g = 0.08, b = 0.90}
            elseif not utils:tableIsEmpty(extraModInfo.warnings.rules) then
                val.color = {r = 0.98, g = 0.66, b = 0.06}
            else
                val.color = {r = 0.10, g = 0.62, b = 0.08}
            end

            val.tooltip = MLOS_methods:getTooltipText(extraModInfo)
        end
    end
end


function ModOrderListBoxOverride:doDrawItem(y, item, alt)
    local parent = self.parent
    if parent.foundCounter > 0 and parent.foundIndex > 0 and parent.foundItems[parent.foundIndex] == item.itemindex then
        parent.foundCounter = parent.foundCounter - 1
        local alpha = 0.30
        if parent.foundCounter < 80 then alpha = alpha - (alpha * alpha) end
        self:drawRect(0, (y), self:getWidth(), item.height-1, alpha, 0.5, 1, 1)
    end

    if utils:contains(parent.multiselected, item.itemindex) then
        self:drawRect(0, (y), self:getWidth(), item.height-1, 0.3, 0.7, 0.35, 0.15)
    end

    if parent.multiselected_counter > 0 and utils:contains(parent.multiselected_temp, item.itemindex) then
        parent.multiselected_counter = parent.multiselected_counter - 1
        self:drawRect(0, (y), self:getWidth(), item.height-1, 0.2, 0.58, 1, 0.12)
    end

    -- sorting rules icon
    local isMouseOver = self.mouseoverselected == item.index
    local shift = (item.height - self.boxSize)/2
    local textureX = self:getWidth() - shift - self.boxSize - 20
    local sr = self.parent.sortingRules
    if sr.modInfoCache == nil or (sr.modInfoCache.id == item.item.modId) then
        self:drawTexture(rulesTexture, textureX, shift + y, 1, 1, 1, 1)
    end
    if isMouseOver then
        local mX, mY = self:getMouseX(), self:getMouseY()
        if (mX > textureX) and (mX < textureX + self.boxSize) and (mY > shift + y) and (mY < shift + y + self.boxSize) then
            self.mouseOverRulesIcon = item
        else
            self.mouseOverRulesIcon = nil
        end
    end

    return origDoDrawItem(self, y, item, alt)
end


function ModOrderListBoxOverride:onMouseDown(x, y)
    origOnMouseDown(self, x, y)
    local row = utils:clamp(self:rowAt(x, y), 1, #self.items)

    if self.parent.sortingRules:onClickItemInList(self.mouseOverRulesIcon, self.items[row]) then
        if not utils:tableIsEmpty(self.parent.multiselected) then self.parent.multiselected = {} end
        return
    end

    if self.mouseOverDragIcon then
        if utils:tableIsEmpty(self.parent.multiselected) or utils:getElementIndex(self.parent.multiselected, self.dragItem.itemindex) == nil then
            self.parent.multiselected = {self.dragItem.itemindex,}
        end
        return
    end
    self.parent.multiselected = MLOS_methods:selectObject(self.parent.multiselected, row, isCtrlKeyDown(), isShiftKeyDown())
    if not utils:tableIsEmpty(self.parent.multiselected) then
        self.parent.multiselected_temp = {}
    end
end


function ModOrderListBoxOverride:onMouseUp(x, y)
    ISScrollingListBox.onMouseUp(self, x, y)

    if self.dragItem ~= nil then
        local clickedRow = (y / self.itemheight) + 1.0
        local row = clickedRow - clickedRow % 1
        local drob = clickedRow % 1

        if row > self.dragItem.itemindex and drob <= 0.5 then row = row - 1 end
        row = utils:clamp(row, 1, self:size())

        if row ~= self.dragItem.itemindex then
            local initial_count = #self.items
            self.parent.multiselected_temp = MLOS_methods:moveElements(self, self.parent.multiselected, row, self.dragItem.itemindex)

            if initial_count ~= #self.items then
                error("items size changed! Expected size: " .. initial_count .. ", Actual size: " .. #self.items)
            end
            self:updateModsColor()
        end
    end
    self.dragItem = nil
end

