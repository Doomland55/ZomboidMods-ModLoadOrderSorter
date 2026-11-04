require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISMouseDrag"

local utils = require('OptionScreens/ModSelector/Refr_utils')

local PADDING = 8
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_MED = getTextManager():getFontHeight(UIFont.Medium)
local FONT_HGT_LRG = getTextManager():getFontHeight(UIFont.Large)
local BUTTON_HGT = FONT_HGT_SMALL + 6


-- MLOS_ScrollPanel derives from ISScrollingListBox. It keeps every parent
-- function (item management, rendering, keyboard/gamepad navigation, tooltips,
-- search-highlight helpers) and adds:
--   * search (optional)
--   * multiselection
--   * move-selected with individual buttons (optional)
--   * drag & drop reordering of items (optional)
--
-- The list IS this derived object, so there is no need to inherit from
-- ISPanelJoypad and embed a child listbox.
local MLOS_ScrollPanel = ISScrollingListBox:derive("MLOS_ScrollPanel")

-- default constructor arguments
--   new(x, y, width, height, label, is_searchable, is_multiselectable, is_items_movable, add_move_buttons)
function MLOS_ScrollPanel:new(x, y, width, height, label, is_searchable, is_multiselectable, is_items_movable, add_move_buttons)
    local o = ISScrollingListBox:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o._label = label
    o._is_searchable = is_searchable
    o._is_multiselectable = is_multiselectable
    o._is_items_movable = is_items_movable
    o._add_move_buttons = add_move_buttons

    -- o.backgroundColor = {r=0.28, g=0.35, b=0.8, a=0.8};

    o.scrollBackgroundColor = {r=0.28, g=0.35, b=0.8, a=0.8};
    o.scrollBorderColor = {r=0.4, g=0.4, b=0.4, a=0.9};

    o.groups = nil
    o.foundItems = {}
    o.foundIndex = 0



    o.scrollRect = {x=0, y=0, width = toInt(width), height = toInt(height)}

    return o
end


-- ============================================================
-- Layout
-- ============================================================

function MLOS_ScrollPanel:instantiate()
    ISScrollingListBox.instantiate(self)
    self:createChildren()
end

function MLOS_ScrollPanel:createChildren()
    if self._add_move_buttons and self._is_items_movable then
        self.scrollRect.width = self.scrollRect.width - (BUTTON_HGT * 2) - PADDING

        local buttonsData = {
            {title=">>|", internal="UP_TO_BEGINNING", tooltip="Move selected to beginning"},
            {title=">>", internal="UP_10", tooltip="Move selected up by 10"},
            {title=">", internal="UP_1", tooltip="Move selected up by 1"},
            {title="<", internal="DOWN_1", tooltip="Move selected down by 1"},
            {title="<<", internal="DOWN_10", tooltip="Move selected down by 10"},
            {title="|<<", internal="DOWN_TO_END", tooltip="Move selected to end"},
            start_x = self.scrollRect.width,
            start_y = self.scrollRect.y + (self._is_searchable and (BUTTON_HGT + PADDING) or 0)
        }

        for _, btn in ipairs(buttonsData) do
            local button = ISButton:new(buttonsData.start_x, buttonsData.start_y, BUTTON_HGT * 2, BUTTON_HGT, btn.title, self, self.onMoveButton)
            button.internal = btn.internal
            button:initialise()
            button:instantiate()
            button:setTooltip(btn.tooltip)
            button.borderColor = {r=1, g=1, b=1, a=0.2}
            button:setFont(UIFont.Small)
            button:ignoreWidthChange()
            button:ignoreHeightChange()
            self:addChild(button)

            buttonsData.start_y = buttonsData.start_y + BUTTON_HGT + PADDING
        end
    end

    if self._is_searchable then
        self.searchEntry = ISTextEntryBox:new("", self.scrollRect.width / 2 , self.scrollRect.y + PADDING / 2 , self.scrollRect.width / 2 - 2 * (BUTTON_HGT + PADDING), BUTTON_HGT)
        self.searchEntry.font = UIFont.Small
        self.searchEntry.onTextChange = function() self:onChangeText() end
        self.searchEntry:initialise()
        self.searchEntry:instantiate()
        self:addChild(self.searchEntry)
        self.searchEntry:bringToTop()

        local searchBtnPrev = ISButton:new(self.searchEntry:getRight() + PADDING, self.searchEntry:getY(), BUTTON_HGT, BUTTON_HGT, "/\\", self, self.onSearchButton)
        searchBtnPrev.internal = "PREV_SEARCH"
        searchBtnPrev:initialise()
        searchBtnPrev:instantiate()
        searchBtnPrev.borderColor = {r=1, g=1, b=1, a=0.2}
        searchBtnPrev:setFont(UIFont.Small)
        searchBtnPrev:ignoreWidthChange()
        searchBtnPrev:ignoreHeightChange()
        self:addChild(searchBtnPrev)

        local searchBtnNext = ISButton:new(searchBtnPrev:getRight() + PADDING, self.searchEntry:getY(), BUTTON_HGT, BUTTON_HGT, "\\/", self, self.onSearchButton)
        searchBtnNext.internal = "NEXT_SEARCH"
        searchBtnNext:initialise()
        searchBtnNext:instantiate()
        searchBtnNext.borderColor = {r=1, g=1, b=1, a=0.2}
        searchBtnNext:setFont(UIFont.Small)
        searchBtnNext:ignoreWidthChange()
        searchBtnNext:ignoreHeightChange()
        self:addChild(searchBtnNext)
    end
    if self._is_searchable or (self._label ~= nil and self._label ~= "") then
        self.scrollRect.y = self.scrollRect.y + FONT_HGT_MED + PADDING
        self.scrollRect.height = self.scrollRect.height - self.scrollRect.y
    end

    if self.vscroll then
        self.scrollRect.width = self.scrollRect.width - 17
        self.vscroll:setX(self.scrollRect.x + self.scrollRect.width)
        self.vscroll:setY(self.scrollRect.y)
        self.vscroll:setHeight(self.scrollRect.height - (self.hscroll and 17 or 0))
        print(self:getScrollHeight(), self.vscroll:getScrollHeight(), self.scrollRect.height)
        -- self:setScrollHeight(self.scrollRect.height)
    end
    if self.hscroll then
        self.scrollRect.height = self.scrollRect.height - 17
        self.hscroll:setX(self.scrollRect.x)
        self.hscroll:setY(self.scrollRect.y + self.scrollRect.height)
        self.hscroll:setWidth(self.scrollRect.width)
    end
end


-- ============================================================
-- Item management
-- ============================================================

-- function MLOS_ScrollPanel:clear()
--     self.scroll_list:clear()
--     self:clearSelection()
-- end

-- function MLOS_ScrollPanel:addItem(name, data)
--     self.scroll_list:addItem(name, data)
--     return self
-- end

-- function MLOS_ScrollPanel:addItems(items)
--     for _, item in ipairs(items) do
--         self:addItem(unpack(item))
--     end
-- end


-- ============================================================
-- Multiselection
-- ============================================================

-- set o.selectionMode = "multi" in `new` to enable multiselection; the list
-- will then toggle items instead of overwriting `self.selected`.

-- function MLOS_ScrollPanel:onMouseDown(x, y)
--     local row = self:rowAt(x, y)

--     if row > #self.items then
--         row = #self.items
--     end
--     if row < 1 then
--         return
--     end

--     local item = self.items[row]

--     if self._is_multiselectable then
--         item.selected = not item.selected
--     else
--         self.selected = row
--     end

--     self:invokeOnMouseDownFunction()
-- end


function MLOS_ScrollPanel:getSelectedItems()
    local selected = self.selected
    if type(selected) ~= "table" then
        selected = {selected,}
    end
    return selected
end


-- function MLOS_ScrollPanel:getSelectedCount()
--     local count = 0
--     for _, item in ipairs(self.items) do
--         if item.selected then
--             count = count + 1
--         end
--     end
--     return count
-- end


-- function MLOS_ScrollPanel:iteratorSelected()
--     return ipairs(self:getSelectedItems())
-- end


-- function MLOS_ScrollPanel:clearSelection()
--     for _, item in ipairs(self.items) do
--         item.selected = false
--     end
-- end


-- function MLOS_ScrollPanel:setSelectedRow(row)
--     self:clearSelection()
--     if self.items[row] then
--         self.items[row].selected = true
--     end
-- end


-- function MLOS_ScrollPanel:setSelectedRows(rows)
--     self:clearSelection()
--     for _, row in ipairs(rows) do
--         if self.items[row] then
--             self.items[row].selected = true
--         end
--     end
-- end


-- function MLOS_ScrollPanel:getSelectedIDs()
--     local ids = {}
--     for _, item in ipairs(self:getSelectedItems()) do
--         ids[#ids + 1] = item.item and item.item.id or item.item
--     end
--     return ids
-- end


-- ============================================================
-- Search
-- ============================================================

function MLOS_ScrollPanel:onChangeText()
    if not utils:tableIsEmpty(self.foundItems) then
        self.foundItems = {}
        self.foundIndex = 0
    end
end


function MLOS_ScrollPanel:searchItems()
    if not utils:tableIsEmpty(self.foundItems) then return end

    local searchWord = string.lower(self.searchEntry:getInternalText())
    if not searchWord or searchWord == "" then return end

    self.foundItems = {}
    self.foundIndex = 0

    for i, item in ipairs(self.items) do
        if string.find(string.lower(item.item.name), searchWord) or string.find(string.lower(item.item.modId), searchWord) then
            table.insert(self.foundItems, i)
        end
    end
end


function MLOS_ScrollPanel:onSearchButton(button)
    self:searchItems()
    if utils:tableIsEmpty(self.foundItems) then return end

    if button.internal == "NEXT_SEARCH" then self.foundIndex = self.foundIndex + 1 end
    if button.internal == "PREV_SEARCH" then self.foundIndex = self.foundIndex - 1 end

    if self.foundIndex > #self.foundItems then self.foundIndex = 1 end
    if self.foundIndex < 1 then self.foundIndex = #self.foundItems end

    local itemIndex = self.foundItems[self.foundIndex]
    if itemIndex ~= nil then
        self:ensureVisible(itemIndex)
        self.foundCounter = 400
    end
end


-- ============================================================
-- Move buttons (reorder selected items)
-- ============================================================

-- -- helper: move a single item to a new position
-- local function moveItemTo(self, item, newIndex)
--     for i = 1, #self.items do
--         if self.items[i] == item then
--             table.remove(self.items, i)
--             table.insert(self.items, newIndex, item)
--             return true
--         end
--     end
--     return false
-- end


-- function MLOS_ScrollPanel:onMoveButton(button)
--     if not self._is_items_movable then return end

--     local selected = self:getSelectedItems()
--     if #selected == 0 then
--         return
--     end

--     -- local moved = false

--     if button.internal == "UP_TO_BEGINNING" then
        
--         for _, item in ipairs(selected) do
--             print("Moving item ", item, "to BEGINNING")
--             -- if moveItemTo(self, item, 1) then
--             --     moved = true
--             -- end
--         end
--     elseif button.internal == "DOWN_TO_END" then
--         for _, item in ipairs(selected) do
--             print("Moving item ", item, "to END")
--             -- if moveItemTo(self, item, #self.items) then
--             --     moved = true
--             -- end
--         end
--     else
--         for _, item in ipairs(selected) do
--             print("Moving item ", item, "to INDEX", button.internal)
--             -- if moveItemTo(self, item, self.selected) then
--             --     moved = true
--             -- end
--         end
--     end

--     -- if moved then
--     --     self:invokeOnMouseDownFunction()
--     -- end
-- end


-- ============================================================
-- Drag & drop (reorder)
-- ============================================================

-- -- collect the items being dragged by matching against the current items
-- local function getDraggedItems(self)
--     local dragged = {}
--     for _, item in ipairs(self.items) do
--         for _, d in ipairs(ISMouseDrag.dragging) do
--             if item.item and item.item == d then
--                 table.insert(dragged, item)
--             end
--         end
--     end
--     return dragged
-- end


-- function MLOS_ScrollPanel:onItemDrag(x, y, obj)
--     if not self._is_items_movable then return end

--     if #ISMouseDrag.dragging == 0 then return end

--     local row = self:rowAt(x, y)
--     if row < 1 or row > #self.items then return end

--     -- rebuild the items list so dragged items appear at the drop position
--     self:reorderItems(row)

--     -- hand the drag back to the global system so other panels can accept it
--     if ISMouseDrag.draggingFocus == self then
--         ISMouseDrag.draggingFocus:onMouseUpOutside(0, 0)
--         ISMouseDrag.draggingFocus = nil
--         ISMouseDrag.dragging = nil
--     end

--     self:invokeOnMouseDownFunction()
-- end


-- function MLOS_ScrollPanel:onItemDrop(x, y, obj)
--     if not self._is_items_movable then return end

--     if #ISMouseDrag.dragging == 0 then return end

--     local row = self:rowAt(x, y)
--     if row < 1 or row > #self.items then return end

--     -- rebuild the items list so dragged items are inserted at the drop position
--     self:reorderItems(row)

--     if ISMouseDrag.draggingFocus == self then
--         ISMouseDrag.draggingFocus:onMouseUpOutside(0, 0)
--         ISMouseDrag.draggingFocus = nil
--         ISMouseDrag.dragging = nil
--     end

--     self:invokeOnMouseDownFunction()
-- end


-- function MLOS_ScrollPanel:reorderItems(targetRow)
--     local dragged = getDraggedItems(self)
--     if #dragged == 0 then return end

--     local before = {}
--     local after = {}
--     for _, item in ipairs(self.items) do
--         local found = false
--         for _, d in ipairs(dragged) do
--             if item.item and item.item == d then
--                 found = true
--             end
--         end
--         if found then
--             table.insert(dragged, dragged, item) -- insert into dragged list at this position
--         elseif targetRow > #before then
--             table.insert(after, item)
--         else
--             table.insert(before, item)
--         end
--     end

--     -- self.items = table.concat(before, after, dragged, after)
-- end


-- ============================================================
-- Drag start tracking (mouse down on a selected item)
-- ============================================================

function MLOS_ScrollPanel:onMouseDown(x, y)
    -- ISScrollingListBox.onMouseDown(self, x, y)

    -- if not self._is_items_movable then return end

    -- local row = self:rowAt(x, y)
    -- if row < 1 or row > #self.items then return end

    -- local item = self.items[row]
    -- if not item.item then return end

    -- -- begin drag of the selected item(s)
    -- ISMouseDrag.dragging = {}
    -- table.insert(ISMouseDrag.dragging, item.item)
    -- for _, sel in ipairs(self:getSelectedItems()) do
    --     if sel.item and sel.item ~= item.item then
    --         table.insert(ISMouseDrag.dragging, sel.item)
    --     end
    -- end

    -- ISMouseDrag.draggingFocus = self
    if self:isMouseOverScrollRect() then
        print("isMouseOverScrollRect:", x, y)
    else
        print(x, y)
    end
     
end


function MLOS_ScrollPanel:onMouseWheel(del)
    if self:isMouseOverScrollRect() then
        ISScrollingListBox.onMouseWheel(self, del)
    end
end


function MLOS_ScrollPanel:isMouseOverScrollRect()
    local scrollX = self:getXScroll()
    local scrollY = self:getYScroll()
    if utils:inRange(self:getMouseX(), self.scrollRect.x - scrollX, self.scrollRect.x + self.scrollRect.width - scrollX) and
       utils:inRange(self:getMouseY(), self.scrollRect.y - scrollY, self.scrollRect.y + self.scrollRect.height - scrollY) then
        return true
    end
    return false
end

-- ============================================================
-- Default functions overrides
-- ============================================================

function MLOS_ScrollPanel:getScrollAreaWidth()
	if self:isVScrollBarVisible() then
		return self.scrollRect.width - self.vscroll:getWidth()
	end
	return self.scrollRect.width
end

function MLOS_ScrollPanel:getScrollAreaHeight()
	if self.hscroll then
		return self.scrollRect.height - self.hscroll:getHeight()
	end
	return self.scrollRect.height
end

-- ============================================================
-- Local draw helpers (group styling)
-- ============================================================

local function drawGroup(obj, y, item, alt, h, textColor)
    obj:drawRectBorder(0, y, obj:getWidth(), h, 0.5, obj.borderColor.r, obj.borderColor.g, obj.borderColor.b)
    obj:drawText(item.text, 15, y + (h - obj.fontHgt) / 2, textColor.r, textColor.g, textColor.b, textColor.a, obj.font)
    return y + h
end


local function drawItem(obj, y, item, alt, h, textColor)
    local offset = 0
    if item.group_id and item.group_id ~= 0 and obj.group[item.group_id] then
        offset = PADDING * (obj.group[item.group_id] or 1)
    end
    obj:drawRectBorder(offset, y, obj:getWidth() - offset, h, 0.5, obj.borderColor.r, obj.borderColor.g, obj.borderColor.b)
    obj:drawText(item.text, PADDING + offset, y + (h - obj.fontHgt) / 2, textColor.r, textColor.g, textColor.b, textColor.a, obj.font)
    return y + h
end


-- ============================================================
-- Rendering / List drawing
-- ============================================================

function MLOS_ScrollPanel:getStensilRect()
    local scrollX = self:getXScroll()
    local scrollY = self:getYScroll()
    local stensilRect = {
        x=self.scrollRect.x - scrollX + 1,
        y=self.scrollRect.y - scrollY + 1
    }
    stensilRect.x2 = stensilRect.x + self.scrollRect.width - 1 + (self:isVScrollBarVisible() and 3 or 0)
    stensilRect.y2 = stensilRect.y + self.scrollRect.height - 1

    -- This is to handle this listbox being inside a scrolling parent.
	if self:parentsHaveScrollChildren() then 
		stensilRect.x = self.javaObject:clampToParentX(self:getAbsoluteX() + stensilRect.x) - self:getAbsoluteX()
		stensilRect.x2 = self.javaObject:clampToParentX(self:getAbsoluteX() + stensilRect.x2) - self:getAbsoluteX()
		stensilRect.y = self.javaObject:clampToParentY(self:getAbsoluteY() + stensilRect.y) - self:getAbsoluteY()
		stensilRect.y2 = self.javaObject:clampToParentY(self:getAbsoluteY() + stensilRect.y2) - self:getAbsoluteY()
	end
    stensilRect.width = stensilRect.x2 - stensilRect.x
    stensilRect.height = stensilRect.y2 - stensilRect.y
    return stensilRect
end


function MLOS_ScrollPanel:prerender()
    local scrollX = self:getXScroll()
    local scrollY = self:getYScroll()
    local stensilRect = self:getStensilRect()

    -- backgrounds
    if self.backgroundColor.a > 0 then
	    self:drawRect(self.x - scrollX, self.y - scrollY, self.width, self.height, self.backgroundColor.a, self.backgroundColor.r, self.backgroundColor.g, self.backgroundColor.b);
    end
    if self.scrollBackgroundColor.a > 0 then
	    self:drawRect(stensilRect.x, stensilRect.y, stensilRect.width, stensilRect.height, self.scrollBackgroundColor.a, self.scrollBackgroundColor.r, self.scrollBackgroundColor.g, self.scrollBackgroundColor.b);
    end

    -- borders
    if self.drawBorder then
		self:drawRectBorder(self.x - scrollX, self.y - scrollY, self.width, self.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
	end
    if self.scrollBorderColor.a > 0 then
        self:drawRectBorder(stensilRect.x, stensilRect.y, stensilRect.width, stensilRect.height, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)
    end

    --label
    if self._label ~= nil and self._label ~= "" then
        self:drawText(self._label, PADDING * 0.5 - scrollX, PADDING * 0.5 - scrollY, 1, 1, 1, 1, UIFont.Medium)
    end

    if utils:tableIsEmpty(self.items) then return end

    -- DRAW ITEMS
	-- self:setStencilRect(self.scrollRect.x + 1, scrollrect_y + 1, self.scrollRect.width - 2, self.scrollRect.height - 2)

	local y = self.scrollRect.y
	local alt = false

	-- self.listHeight = 0;
	for i, item in ipairs(self.items) do
		if not item.height then item.height = self.itemheight end -- compatibililty
        item.index = i;

		-- if alt and self.altBgColor then
		-- 	self:drawRect(stensilRect.x, y, stensilRect.width - 1, item.height-1, self.altBgColor.a, self.altBgColor.r, self.altBgColor.g, self.altBgColor.b);
        -- end

		y = self:doDrawItem(y, item, false);
		alt = not alt
	end
    self.listHeight = y

    -- self:setScrollHeight((y))
    -- self:clearStencilRect()

    local mouseY = self:getMouseY()
	self:updateSmoothScrolling()
	if mouseY ~= self:getMouseY() and self:isMouseOverScrollRect() then
		self:onMouseMove(0, self:getMouseY() - mouseY)
	end
	-- self:updateTooltip()





    -- ISScrollingListBox.prerender(self)

    -- self:drawText(self._label, PADDING * 0.5, PADDING * 0.5 - self:getYScroll(), 1, 1, 1, 1, UIFont.Medium)
    -- self:drawRectBorder(self.scrollRect.x, self.scrollRect.y - self:getYScroll(), self.scrollRect.width, self.scrollRect.height - self.scrollRect.y, self.borderColor.a, self.borderColor.r, self.borderColor.g, self.borderColor.b)


end

function MLOS_ScrollPanel:doDrawItem(y, item, alt)
    local h = item.height or self.itemheight or self.boxSize or 10
    local yscroll = self:getYScroll()
    -- if h <= 0 or (y - yscroll + h < self.scrollRect.y) or (y - yscroll >= h) then
    --     return y + h
    -- end

    local textColor = item.textColor or self.textColor
    if self.selected == item.index or utils:contains(self.selected, item.index) then
        self:drawSelection(0, y, self.scrollRect.width - 2, h-1)
        textColor = item.selectedTextColor or self.selectedTextColor
    elseif (self.mouseoverselected == item.index) and self:isMouseOver() and not self:isMouseOverScrollBar() then
        self:drawMouseOverHighlight(0, y, self.scrollRect.width - 2, h-1)
    end

    -- check item is group
    if item.is_group then
        return drawGroup(self, y, item, alt, h, textColor)
    end

    -- -- check is item in group and group is visible
    -- if item.group_id and item.group_id ~= 0 and self.group[item.group_id] then
    --     return drawItem(self, y, item, alt, h, textColor)
    -- end

    -- return y + h

    return drawItem(self, y, item, alt, h, textColor)
end

-- function ModOrderListBox:doDrawItem(y, item, alt)
--     local isMouseOver = self.mouseoverselected == item.index

--     if self.parent.joyfocus ~= nil and self.selected == item.index then
--         self:drawRect(0, (y), self:getWidth(), item.height-1, 0.3, 0.7, 0.35, 0.15)
--     end

--     if self.dragItem == item then
--         self:drawRect(0, (y), self:getWidth(), item.height-1, 0.3, 0.7, 0.35, 0.15)
--     end
--     self:drawRectBorder(0, (y), self:getWidth(), item.height, 0.5, self.borderColor.r, self.borderColor.g, self.borderColor.b)

--     local shift = (item.height - self.boxSize)/2
--     self:drawTexture(self.dragTexture, shift, shift + y, 1, 1, 1, 1)
--     if isMouseOver and ((self:getMouseX() > shift) and (self:getMouseX() < self.boxSize + shift) and (self:getMouseY() > shift + y) and (self:getMouseY() < shift + y + self.boxSize)) then
--         self.mouseOverDragIcon = item
--     end

--     if item.item.icon ~= "" then
--         self:drawTextureScaled(getTexture(item.item.icon), item.height + 8, y + (item.height - 28) / 2, 28, 28, 1, 1, 1, 1)
--     else
--         self:drawTextureScaled(Texture.getWhite(), item.height + 8, y + (item.height - 28) / 2, 28, 28, 0.1, 1, 1, 1)
--     end

--     local itemPadY = self.itemPadY or (item.height - self.fontHgt) / 2
--     self:drawText(item.item.name, item.height + 50, (y)+itemPadY, item.color.r, item.color.g, item.color.b, 0.9, self.font)

--     y = y + item.height
--     return y
-- end




return MLOS_ScrollPanel
