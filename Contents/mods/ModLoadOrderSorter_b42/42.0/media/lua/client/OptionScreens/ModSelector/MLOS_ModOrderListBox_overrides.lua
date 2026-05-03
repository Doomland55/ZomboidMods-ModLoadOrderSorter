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

require('OptionScreens/ModSelector/MLOS_ModSelector_overrides')
local utils = require('OptionScreens/MLOS_core/Refr_utils')
local MLOS_methods = require('OptionScreens/MLOS_core/MLOS_Methods')
local MLOS_sorting = require('OptionScreens/MLOS_core/MLOS_SortingCore')
local MLOS_ModInfoLayer = require('OptionScreens/MLOS_core/MLOS_Layer_ModsInfo')


local ModOrderListBoxOverride = ModSelector.ModOrderListBox

-- local rulesTexture = getTexture("media/ui/MLOS_Button_Rules.png")

--================================================
--      ModOrderListBoxOverride Overrides
--================================================
ModOrderListBoxOverride.multiselected = {}
ModOrderListBoxOverride.multiselected_temp = {}
ModOrderListBoxOverride.multiselected_counter = 150

local origDoDrawItem = ModOrderListBoxOverride.doDrawItem
local origOnMouseDown = ModOrderListBoxOverride.onMouseDown


function ModOrderListBoxOverride:updateCache()
    self.parent:onChangeText()
    if not utils:tableIsEmpty(self.multiselected) then
        self.multiselected = {}; for k, v in ipairs(self.multiselected_temp) do self.multiselected[k] = v end
        self.multiselected_counter = 150 * #self.multiselected_temp
    end
end


function ModOrderListBoxOverride:updateModsColor()
    self:updateCache()
    -- self.mouseOverRulesIcon = nil

    self.parent.acceptButton.enable = MLOS_sorting:validateSorting(self.items)
    for i, val in ipairs(self.items) do
        val.itemindex = i  -- update item index
		local extraModInfo = MLOS_ModInfoLayer.data[val.item.modId]
        if extraModInfo ~= nil then
            if not utils:tableIsEmpty(extraModInfo.warnings.missing) then
                val.color = {r = 0.98, g = 0.08, b = 0.08}
            elseif not utils:tableIsEmpty(extraModInfo.warnings.wrongOrder) then
                val.color = {r = 0.88, g = 0.08, b = 0.08}
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

    -- highlight found item. search logic in the MLOS_ModSelector_overrides
    if parent.foundCounter > 0 and parent.foundIndex > 0 and parent.foundItems[parent.foundIndex] == item.itemindex then
        parent.foundCounter = parent.foundCounter - 1
        local alpha = 0.30
        if parent.foundCounter < 80 then alpha = alpha - (alpha * alpha) end
        self:drawRect(0, (y), self:getWidth(), item.height-1, alpha, 0.5, 1, 1)
    end

    -- highlight multiselected items 
    if self.multiselected_counter > 0 and utils:contains(self.multiselected_temp, item.itemindex) then
        self.multiselected_counter = self.multiselected_counter - 1
        self:drawRect(0, (y), self:getWidth(), item.height-1, 0.2, 0.58, 1, 0.12)
    elseif utils:contains(self.multiselected, item.itemindex) then
        self:drawRect(0, (y), self:getWidth(), item.height-1, 0.3, 0.7, 0.35, 0.15)
    end

    -- -- sorting rules icon
    -- local isMouseOver = self.mouseoverselected == item.index
    -- local shift = (item.height - self.boxSize)/2
    -- local textureX = self:getWidth() - shift - self.boxSize - 20
    -- local sr = self.parent.sortingRules
    -- if sr.modInfoCache == nil or (sr.modInfoCache.id == item.item.modId) then
    --     self:drawTexture(rulesTexture, textureX, shift + y, 1, 1, 1, 1)
    -- end
    -- if isMouseOver then
    --     local mX, mY = self:getMouseX(), self:getMouseY()
    --     if (mX > textureX) and (mX < textureX + self.boxSize) and (mY > shift + y) and (mY < shift + y + self.boxSize) then
    --         self.mouseOverRulesIcon = item
    --     else
    --         self.mouseOverRulesIcon = nil
    --     end
    -- end

    return origDoDrawItem(self, y, item, alt)
end


function ModOrderListBoxOverride:onMouseDown(x, y)
    origOnMouseDown(self, x, y)
    -- local row = utils:clamp(self:rowAt(x, y), 1, #self.items)

    -- if self.parent.sortingRules:onClickItemInList(self.mouseOverRulesIcon, self.items[row]) then
    --     -- if not utils:tableIsEmpty(self.parent.multiselected) then self.parent.multiselected = {} end
    --     return
    -- end

    if self.mouseOverDragIcon then
        if utils:tableIsEmpty(self.multiselected) or utils:getElementIndex(self.multiselected, self.dragItem.itemindex) == nil then
            self.multiselected = {self.dragItem.itemindex,}
        end
        return
    end

    local row = self:rowAt(x, y)

    if row <= 0 then self.multiselected = {}; return end

    self.multiselected = MLOS_methods:selectObject(self.multiselected, row, isCtrlKeyDown(), isShiftKeyDown())
    if not utils:tableIsEmpty(self.multiselected) then
        self.multiselected_temp = {}
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
            self.multiselected_temp = MLOS_methods:moveElements(self, self.multiselected, row, self.dragItem.itemindex)

            if initial_count ~= #self.items then
                error("items size changed! Expected size: " .. initial_count .. ", Actual size: " .. #self.items)
            end
            self:updateModsColor()
        end
    end
    self.dragItem = nil
end


function ModOrderListBoxOverride:onMouseUpOutside(x, y)
    ISScrollingListBox.onMouseUpOutside(self, x, y)
    if self.parent:isMouseOver() or self.dragItem ~= nil then
        self:onMouseUp(x,y)
    else
        self.multiselected = {}
    end
    self.dragItem = nil
end
