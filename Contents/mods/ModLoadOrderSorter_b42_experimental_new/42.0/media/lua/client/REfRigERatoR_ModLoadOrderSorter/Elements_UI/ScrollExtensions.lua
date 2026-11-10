require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISComboBox"
require "ISUI/ISMouseDrag"
require "REfRigERatoR_ModLoadOrderSorter/Elements_UI/ContextMenu"
local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')


local MLOS_ScrollExtensions = {}

local PADDING = 8
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6


-- #region ====================== Tools =======================
-- New variables:
-- ScrollObject: -
-- ScrollObject.parent: -
--=============================================================

local function updateRectValues(slf, x, y, width, height, isOffset)
    if isOffset then
        height = slf.height + (height or -(y or 0))
        width = slf.width + (width or -(x or 0))
        x = slf.x + (x or 0)
        y = slf.y + (y or 0)
    else
        x = x or slf.x
        y = y or slf.y
        width = width or slf.width
        height = height or slf.height
    end

    if slf.vscroll then
        slf.vscroll:setHeight(height - (slf.hscroll and 17 or 0))
        slf.vscroll.minimumHeight = slf.vscroll.height
        if width ~= slf.width then
            slf.vscroll:setX(width - 17)
        end
    end
    if slf.hscroll then
        slf.hscroll:setWidth(width - (slf.vscroll and 17 or 0))
        slf.hscroll.minimumWidth = slf.hscroll.width
        if height ~= slf.height then
            slf.hscroll:setY(height - 17)
        end
    end

    slf:setX(x)
    slf:setY(y)
    slf:setHeight(height)
    slf:setWidth(width)
end
-- #endregion


function MLOS_ScrollExtensions:initialResacale(scrollObject, x, y, width, height)
    updateRectValues(scrollObject, x, y, width, height)
end


-- #region Title
-- ============================================================
--                         Title
-- New variables:
-- ScrollObject: -
-- ScrollObject.parent: -
-- ============================================================

function MLOS_ScrollExtensions:addTitle(scrollObject, titleText, inCenter, backgroundColor, fontSize)
    if not scrollObject or not titleText then return end

    fontSize = fontSize or UIFont.Medium

    local sizeInPixels = getTextManager():getFontFromEnum(fontSize):getLineHeight()

    local absoluteBounds = scrollObject:getAbsoluteBounds()
    absoluteBounds.height = sizeInPixels + PADDING

    updateRectValues(scrollObject, nil, sizeInPixels + PADDING, nil, nil, true)

    local localBounds = scrollObject:toLocalBounds(absoluteBounds)
    local origPrerender = scrollObject.prerender
    scrollObject.prerender = function(slf)
        local yscroll = slf:getYScroll()

        if not utils:tableIsEmpty(backgroundColor) then
            slf:drawRect(0, localBounds.y - yscroll, slf.width, localBounds.height, backgroundColor.a, backgroundColor.r, backgroundColor.g, backgroundColor.b)
        end
        -- slf:drawRectBorder(0, localBounds.y - yscroll, slf.width, localBounds.height, 0.5, slf.borderColor.r, slf.borderColor.g, slf.borderColor.b)

        if titleText and titleText ~= "" then
            if inCenter then
                slf:drawTextCentre(titleText, localBounds.width * 0.5,  localBounds.y - yscroll + PADDING * 0.5, 1, 1, 1, 1, fontSize)
            else
                slf:drawText(titleText, PADDING * 0.5,  localBounds.y - yscroll + PADDING * 0.5 , 1, 1, 1, 1, fontSize)
            end
        end

        origPrerender(slf)
    end

end
-- #endregion


-- #region ============== Background and Borders ==============
-- New variables:
-- ScrollObject: -
-- ScrollObject.parent: -
-- ============================================================

function MLOS_ScrollExtensions:addBackground(scrollObject, backgroundColor, borderColor)
    if not scrollObject then return end

    if borderColor ~= nil then
        if not utils:tableIsEmpty(borderColor) then
            scrollObject.borderColor = borderColor
        end
        scrollObject.drawBorder = true
    end

    if not utils:tableIsEmpty(backgroundColor) then
        scrollObject.backgroundColor = backgroundColor
    end
end
-- #endregion


-- #region ================ Create List Object ================
function MLOS_ScrollExtensions.createList(parent, x, y, width, height)
    local list = ISScrollingListBox:new(x, y, width, height)
    list:initialise()
    list:instantiate()

    local colors = core.COLORS
    list.doDrawItem = function(slf, y, item, alt)
        local color = item.item.conflict and colors.fileConflict or colors.reset
        if slf.selected == item.index then 
            slf:drawRect(0, y, slf.width, item.height, 0.25, 0.6, 0.6, 0.6) 
        end
        slf:drawText(item.text, 4, y+3, color.r, color.g, color.b, 1, UIFont.Small)
        return y + item.height
    end
    parent:addChild(list)
    return list
end
-- #endregion


-- #region =================== Search Entry ===================
-- New variables:
-- ScrollObject: foundItems, foundIndex, foundCounter, searchEntry
-- ScrollObject.parent: -
-- ============================================================


local function searchItems(scrollObject)
    if not scrollObject or not utils:tableIsEmpty(scrollObject.foundItems) then return end

    local searchWord = string.lower(scrollObject.searchEntry:getInternalText() or "")
    if searchWord == "" then return end
    if scrollObject.MLOS_folders then scrollObject.MLOS_folders:revealMatches(searchWord) end

    for i, row in ipairs(scrollObject.items) do
        local item = type(row.item) == "table" and row.item or {}
        local name = tostring(item.name or row.text or ""):lower()
        local id = tostring(item.modId or ""):lower()
        if name:find(searchWord, 1, true) or id:find(searchWord, 1, true) then
            table.insert(scrollObject.foundItems, i)
        end
    end
end


local function getSearchResult(scrollObject)
    if scrollObject.foundIndex > #scrollObject.foundItems then scrollObject.foundIndex = 1 end
    if scrollObject.foundIndex < 1 then scrollObject.foundIndex = #scrollObject.foundItems end

    local itemIndex = scrollObject.foundItems[scrollObject.foundIndex]
    if itemIndex ~= nil then
        scrollObject:ensureVisible(itemIndex)
        scrollObject.foundCounter = 400
    end
end


local function searchNext(scrollObject)
    searchItems(scrollObject)
    scrollObject.foundIndex = scrollObject.foundIndex + 1
    getSearchResult(scrollObject)
end


local function searchPrev(scrollObject)
    searchItems(scrollObject)
    scrollObject.foundIndex = scrollObject.foundIndex - 1
    getSearchResult(scrollObject)
end


local function onChangeText(scrollObject, autoNext)
    scrollObject.foundItems = {}
    scrollObject.foundIndex = 0
    searchItems(scrollObject)
    if autoNext then
        searchNext(scrollObject)
    end
end


local function addSearchHighlight(scrollObject)
    if not scrollObject.doDrawItem then return end

    local originalDoDrawItems = scrollObject.doDrawItem
    scrollObject.doDrawItem = function(slf, y, item, alt)

        if scrollObject.foundCounter > 0 and scrollObject.foundIndex > 0 and scrollObject.foundItems[scrollObject.foundIndex] == item.itemindex then
            scrollObject.foundCounter = scrollObject.foundCounter - 1
            local color = core.COLORS.search
            local alpha = color.a
            if scrollObject.foundCounter < 80 then alpha = alpha - (alpha * alpha) end
            slf:drawRect(0, (y), slf:getWidth(), item.height-1, alpha, color.r, color.g, color.b)
        end

        return originalDoDrawItems(slf, y, item, alt)
    end

end

-- #region Ctrl+F hotkey support
local function onSearchKeyFocus(self, key)
    self.searchKeyConsumed = false
    local isCtrlHeld = isKeyDown(Keyboard.KEY_LCONTROL)
    local isFHeld = key == Keyboard.KEY_F

    if not self.searchEntry:isFocused() and isCtrlHeld and isFHeld then
        self.searchEntry:focus()
        self.searchKeyConsumed = true
    end
end

local function isSearchKeyConsumed(self)
    return self.searchKeyConsumed
end
-- #endregion


--- @param scrollObject any
--- @param offset any - nil - добавляем поиск inPlace , то есть добавляем поиск и сдвигаем скрол лист под поиск. Число - значит не двигаем скролл лист, но двигаем поиск по вертикали
function MLOS_ScrollExtensions:addSearchEntry(scrollObject, offset)
    if scrollObject == nil or scrollObject.parent == nil then return end

    local scrollParent = scrollObject.parent
    scrollObject.foundItems = {}
    scrollObject.foundIndex = 0
    scrollObject.foundCounter = 0

    -- TODO Переделать получение y координаты. отвязаться от принудительного применения Padding
    local search_y = scrollObject.y
    if offset ~= nil then search_y = search_y + offset end

    local searchEntry = ISTextEntryBox:new("", scrollObject.x , search_y, scrollObject.width / 2 - 2 * (BUTTON_HGT + PADDING), BUTTON_HGT)
    if offset == nil then
        updateRectValues(scrollObject, nil, BUTTON_HGT + PADDING, nil, nil, true)
    end

    searchEntry.font = UIFont.Small
    searchEntry.onTextChange = function() onChangeText(scrollObject, true ) end
    searchEntry:initialise()
    searchEntry:instantiate()
    searchEntry:setPlaceholderText("Find: ...")
    searchEntry:setClearButton(true)
    scrollParent:addChild(searchEntry)
    searchEntry:bringToTop()
    scrollObject.searchEntry = searchEntry

    local searchBtnPrev = ISButton:new(searchEntry:getRight() + PADDING, searchEntry:getY(), BUTTON_HGT, BUTTON_HGT, "", scrollParent, function(_) searchPrev(scrollObject) end)
    searchBtnPrev.internal = "PREV_SEARCH"
    searchBtnPrev:initialise()
    searchBtnPrev:instantiate()
    searchBtnPrev.borderColor = {r=1, g=1, b=1, a=0.2}
    searchBtnPrev:setFont(UIFont.Small)
    searchBtnPrev:ignoreWidthChange()
    searchBtnPrev:ignoreHeightChange()
    searchBtnPrev:setImage(getTexture("media/ui/MLOS_search_up.png"))
    searchBtnPrev:setTextureRGBA(1,1,1,0.8)
    scrollParent:addChild(searchBtnPrev)

    local searchBtnNext = ISButton:new(searchBtnPrev:getRight() + PADDING, searchEntry:getY(), BUTTON_HGT, BUTTON_HGT, "", scrollParent,  function(_) searchNext(scrollObject) end)
    searchBtnNext.internal = "NEXT_SEARCH"
    searchBtnNext:initialise()
    searchBtnNext:instantiate()
    searchBtnNext.borderColor = {r=1, g=1, b=1, a=0.2}
    searchBtnNext:setFont(UIFont.Small)
    searchBtnNext:ignoreWidthChange()
    searchBtnNext:ignoreHeightChange()
    searchBtnNext:setImage(getTexture("media/ui/MLOS_search_down.png"))
    searchBtnNext:setTextureRGBA(1,1,1,0.8)
    scrollParent:addChild(searchBtnNext)

    addSearchHighlight(scrollObject)

    -- Ctrl+F hotkey support
    scrollParent:setWantKeyEvents(true)
    scrollParent.onKeyRelease = scrollParent.onKeyRelease or function(slf, key) onSearchKeyFocus(scrollObject, key) end
    scrollParent.isKeyConsumed = scrollParent.isKeyConsumed or function(slf) isSearchKeyConsumed(scrollObject) end

    return searchEntry
end

-- #endregion


-- Opt-in view folders. Do not attach them to a load-order list: folder rows
-- are display-only and must never be passed to the game's mod-order model.
function MLOS_ScrollExtensions:addFoldersSupport(scrollObject, options)
    local folders = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/FolderSupport')
    return folders.attach(scrollObject, options)
end


-- #region ============== Multiselection support ==============
-- New variables:
-- ScrollObject: selected_map, selected_flat
-- ScrollObject.parent: -
-- ============================================================
local selectionAnchor = nil
local function selectItem(selectedMap, row, ctrlPressed, shiftPressed)
    if selectedMap == nil or not row then return {} end

    if shiftPressed and selectionAnchor then
        local from = math.min(selectionAnchor, row)
        local to = math.max(selectionAnchor, row)

        selectedMap = {}
        for i = from, to do
            selectedMap[i] = true
        end
    elseif ctrlPressed then
        selectedMap[row] = selectedMap[row] == nil and true or nil
        selectionAnchor = row
    else
        selectionAnchor = row
        local saved = selectedMap[row]
        selectedMap[row] = nil
        if utils:tableIsEmpty(selectedMap) then
            selectedMap = { [row] = saved == nil and true or nil }
        else
            selectedMap = { [row] = true }
        end
    end
    return selectedMap
end



local function getSelectedItemsDict(scrollObject)
    if not scrollObject then return {} end

    local selected_map = scrollObject.selected_map
    if selected_map and not utils:tableIsEmpty(selected_map) then
        return selected_map
    end

    local selected = scrollObject.selected
    local items = scrollObject.items
    if selected and items and selected > 0 and selected <= #items then
        return { [selected] = true, }
    end
    return {}
end


local function getSelectedItemsFlat(scrollObject)
    if not scrollObject then return {} end

    local selected_flat = scrollObject.selected_flat
    if selected_flat and not utils:tableIsEmpty(selected_flat) then
        return selected_flat
    end

    local dict = getSelectedItemsDict(scrollObject)
    if utils:tableIsEmpty(dict) then
        return {}
    end

    selected_flat = utils:toFlatTable(dict)
    table.sort(selected_flat)

    scrollObject.selected_flat = selected_flat
    return selected_flat
end


local function applySelection(scrollObject, newSelectedMap)
    if not scrollObject then return end

    scrollObject.selected_flat = nil

    local multiselect_supported = scrollObject.selected_map and true or false
    local count = 0
    local firstIndex = nil

    if newSelectedMap then
        for index, isSelected in pairs(newSelectedMap) do
            if isSelected then
                count = count + 1
                if not firstIndex or index < firstIndex then
                    firstIndex = index
                end
            end
        end
    end

    if count == 0 then
        scrollObject.selected = -1
        scrollObject.selected_map = multiselect_supported and {} or nil
    else
        selectionAnchor = firstIndex
        scrollObject.selected_map = multiselect_supported and newSelectedMap or nil
        scrollObject.selected = firstIndex
    end
end


function MLOS_ScrollExtensions:addMultiselectionSupport(scrollObject)
    if not scrollObject or not scrollObject.items then return end

    scrollObject.selected_map = {}
    scrollObject.selected_flat = {}
end
-- #endregion


-- #region =================== Move Buttons ===================
-- New variables:
-- ScrollObject: -
-- ScrollObject.parent: -
-- ============================================================

---@param items any - array of items
---@param indices table - selected indexes to move
---@param toIndex number - index to move TO
---@param stickToItem boolean - If false, the target index will not be modified (meaning the moved items will be placed at the specified toIndex). If true, the index will be adjusted by the number of moved items when moving downward (meaning the placement is anchored to a specific item rather than an index).
local function moveElements(items, indices, toIndex, stickToItem)
    local itemsN = #items
    local indicesN = #indices
    toIndex = utils:clamp(toIndex, 1, itemsN + 1)

    local imin = toIndex
    local imax = toIndex
    local countLessThanToIndex = 0

    -- создаем маппинг новых индексов
    local indexesMap = {}
    for i=1, indicesN do
        local oldId = indices[i]
        if oldId < imin then imin = oldId end
        if oldId > imax then imax = oldId end
        if oldId < toIndex then countLessThanToIndex = countLessThanToIndex + 1 end

        indexesMap[oldId * -1] = true -- inverted index - to remove
    end
    if stickToItem then toIndex = utils:clamp(toIndex - countLessThanToIndex, 1, itemsN + 1) end
    if toIndex + countLessThanToIndex > itemsN then toIndex = (itemsN + 1) - indicesN end
    imax = utils:clamp(imax + countLessThanToIndex, 1, itemsN)


    -- создаем кэш перемещаемых индексов
    local movingIndexesCache = {}
    local movedIndexes = {}
    local icache = 1
    local toSortId = 0
    for i = imin, imax do
        if not indexesMap[i * -1] then
            movingIndexesCache[icache] = i
            icache = icache + 1
        else
            movedIndexes[#movedIndexes + 1] = toIndex + toSortId
            indexesMap[toIndex + toSortId] = i
            toSortId = toSortId + 1
            indexesMap[i * -1] = nil
        end
    end

    -- Основной цикл перемещения элементов
    local result = {}
    icache = 1
    for i=1, itemsN do
        local item = nil
        if indexesMap[i] then
            item = items[indexesMap[i]]
            indexesMap[i] = true
        elseif i > imin-1 and i < imax + 1 then
            item = items[movingIndexesCache[icache]]
            icache = icache + 1
        else
            item = items[i]
        end
        if item.itemindex then item.itemindex = i end
        result[i] = item
    end

    if #result ~= itemsN then
        error("[ERROR] MLOS: Items size changed! Expected size: " .. itemsN .. ", Actual size: " .. #result)
    end

    return {items = result, movedIndexesMap = indexesMap, movedIndexesFlat = movedIndexes}
end


local function onMoveButton(self, button, scrollObject)
    local selected = getSelectedItemsFlat(scrollObject)
    if #selected == 0 then return end

    local initial_count = #scrollObject.items
    local toIndex = 0

    if button.internal == "UP_TO_BEGINNING" then
        toIndex = 1
    elseif button.internal == "UP_10" then
        toIndex = selected[1] - 10
    elseif button.internal == "UP_1" then
         toIndex = selected[1] - 1
    elseif button.internal == "DOWN_1" then
        toIndex = selected[1] + 1
    elseif button.internal == "DOWN_10" then
        toIndex = selected[1] + 10
    elseif button.internal == "DOWN_TO_END" then
        toIndex = initial_count + 1
    end

    local result = moveElements(scrollObject.items, selected, toIndex, false)
    scrollObject.items = result.items
    applySelection(scrollObject, result.movedIndexesMap)
    scrollObject:ensureVisible(scrollObject.selected)

    if scrollObject.searchEntry then
        onChangeText(scrollObject, false)
    end
end


-- Should be called after addSearchEntry
function MLOS_ScrollExtensions:addMoveButtons(scrollObject)
    if not scrollObject or not scrollObject.parent or not scrollObject.items then return end

    local scrollParent = scrollObject.parent

    scrollObject:setWidth(scrollObject.width - (BUTTON_HGT * 2) - PADDING)

    local buttonsData = {
        {title=">>|", internal="UP_TO_BEGINNING", tooltip="Move selected to beginning"},
        {title=">>", internal="UP_10", tooltip="Move selected up by 10"},
        {title=">", internal="UP_1", tooltip="Move selected up by 1"},
        {title="<", internal="DOWN_1", tooltip="Move selected down by 1"},
        {title="<<", internal="DOWN_10", tooltip="Move selected down by 10"},
        {title="|<<", internal="DOWN_TO_END", tooltip="Move selected to end"},
        start_x = scrollObject:getRight() + PADDING,
        start_y = scrollObject.y
    }

    for _, btn in ipairs(buttonsData) do
        local button = ISButton:new(buttonsData.start_x, buttonsData.start_y, BUTTON_HGT * 2, BUTTON_HGT, btn.title, scrollParent, function(slf, _btn) onMoveButton(slf, _btn, scrollObject) end)
        button.internal = btn.internal
        button:initialise()
        button:instantiate()
        button:setTooltip(btn.tooltip)
        button.borderColor = {r=1, g=1, b=1, a=0.2}
        button:setFont(UIFont.Small)
        button:ignoreWidthChange()
        button:ignoreHeightChange()
        scrollParent:addChild(button)

        buttonsData.start_y = buttonsData.start_y + BUTTON_HGT + PADDING
    end
end
-- #endregion


-- #region ================== Add AutoScroll ==================
function MLOS_ScrollExtensions.addAutoscrollWhileDrag(scrollObject)
    if scrollObject == nil or scrollObject.parent == nil then return end

    local origPrerender = scrollObject.parent.prerender
    scrollObject.parent.prerender = function(slf)
        if origPrerender then origPrerender(slf) end

        if scrollObject:isVScrollBarVisible() and scrollObject.dragItem ~= nil then
            local mY = slf:getMouseY()
            local diff = 0
            if mY < scrollObject:getY() then diff = mY - scrollObject:getY() end
            if mY > scrollObject:getBottom() then diff = mY - scrollObject:getBottom() end
            if diff == 0 then return end

            scrollObject:setYScroll(scrollObject:getYScroll() - (diff * 0.02 * UIManager.getMillisSinceLastRender()))
        end
    end
end
-- #endregion



-- #region Override render

local function modListBox_drawOnlyModCard(self, y, item, alt)
    local mouseX = self:getMouseX()
    local mouseY = self:getMouseY()

    local isMouseOverItem = self.mouseoverselected == item.index
    local selected_map = getSelectedItemsDict(self)

    if selected_map[item.index] ~= nil then
        local color = core.COLORS.selection
        self:drawRect(0, (y), self:getWidth(), item.height-1, color.a, color.r, color.g, color.b)
    end

    self:drawRectBorder(0, (y), self:getWidth(), item.height, isMouseOverItem and 1 or 0.5, self.borderColor.r, self.borderColor.g, self.borderColor.b)

    -- mod card (vanilla code) do not touch
    local shift = (item.height - self.boxSize)/2
    local mouseOverDragTexture = utils:pointInRect(mouseX, mouseY, {x = shift, y = shift + y, height = self.boxSize, width = self.boxSize})
    self:drawTexture(self.dragTexture, shift, shift + y, mouseOverDragTexture and 1 or 0.5, 1, 1, 1)
    if mouseOverDragTexture and self.mouseOverDragIcon ~= item then
        self.mouseOverDragIcon = item
    end
    
    if item.item.icon ~= "" then
        self:drawTextureScaled(getTexture(item.item.icon), item.height + 8, y + (item.height - 28) / 2, 28, 28, 1, 1, 1, 1)
    else
        self:drawTextureScaled(Texture.getWhite(), item.height + 8, y + (item.height - 28) / 2, 28, 28, 0.1, 1, 1, 1)
    end

    local itemPadY = self.itemPadY or (item.height - self.fontHgt) / 2
    self:drawText(item.item.name, item.height + 50, (y)+itemPadY, item.color.r, item.color.g, item.color.b, 0.9, self.font)

    if item.y0 ~= y then item.y0 = y end
    y = y + item.height
    return y
end

local function modListBox_onMouseUpOutside(self, x, y)
    ISScrollingListBox.onMouseUpOutside(self, x, y)
    if self.parent and self.parent:isMouseOver() then
        self:onMouseUp(x,y)
    end
    self.dragItem = nil
end

local function modListBox_onMouseUp(self, x, y)
    ISScrollingListBox.onMouseUp(self, x, y)

    if self.dragItem ~= nil and (x >= 0 and x <= self.width) then
        local row = self.mouseoverselected
        local selectedIndexes = getSelectedItemsFlat(self)
        if row < 0 and y > 0 then row = #self.items + 1 end

        if row ~= self.dragItem.itemindex then
            local isHalf = false
            local selectedItem = self.items[row]
            if selectedItem ~= nil and selectedItem.y0 and y < selectedItem.y0 + selectedItem.height * 0.5 then
                isHalf = true
            end

            local result = moveElements(self.items, selectedIndexes, row, isHalf)
            self.items = result.items  -- flat table
            applySelection(self, result.movedIndexesMap)
            self:updateModsColor()
        end
    end
    self.dragItem = nil
end


function MLOS_ScrollExtensions:modListBoxOverrides(scrollObject)
    local origOnMouseDown = scrollObject.onMouseDown

    scrollObject.onMouseDown = function(slf, x, y)
        origOnMouseDown(slf, x, y)

        local row = slf.mouseoverselected
        local itemsCount = slf.items and #slf.items or 0
        if not row or row < 1 or row > itemsCount then
            return
        end

        local selectedDict = getSelectedItemsDict(slf)
        local isRowAlreadySelected = selectedDict[row] == true

        if slf.dragItem ~= nil then
            if isRowAlreadySelected then
                return
            end
            applySelection(slf, { [row] = true })
            return
        end

        if slf.selected_map == nil then
            applySelection(slf, { [row] = selectedDict[row] == nil and true or nil })
        else
            slf.selected_map = selectItem(slf.selected_map, row, isCtrlKeyDown(), isShiftKeyDown())
            applySelection(slf, slf.selected_map)
        end
    end

    scrollObject.onMouseUp = modListBox_onMouseUp
    scrollObject.onMouseUpOutside = modListBox_onMouseUpOutside
    scrollObject.doDrawItem = modListBox_drawOnlyModCard
end
-- #endregion


-- #region ============== RMB Item Context Menu ===============
-- New variables:
-- ScrollObject: MLOS_ItemContextMenu, MLOS_activeContextMenu
-- ScrollObject.parent: -
-- ============================================================
local function initialiseItemContextMenu(scrollObject)
    if scrollObject.MLOS_ItemContextMenu ~= nil then return end

    scrollObject.MLOS_ItemContextMenu = {}

    local origOnRightMouseUp = scrollObject.onRightMouseUp
    scrollObject.onRightMouseUp = function(slf, x, y)
        if origOnRightMouseUp then origOnRightMouseUp(slf, x, y) end

        local row = slf:rowAt(x, y)
        local itemsCount = slf.items and #slf.items or 0
        if not row or row < 1 or row > itemsCount then return end

        local selectedDict = getSelectedItemsDict(slf)
        if not selectedDict[row] then
            applySelection(slf, { [row] = true })
        end

        local selectedIndexes = getSelectedItemsFlat(slf)
        local selectedRawItems = {}
        for _, idx in ipairs(selectedIndexes) do
            local itemData = slf.items[idx]
            if itemData then
                table.insert(selectedRawItems, itemData.item or itemData)
            end
        end
        local clickedRawItem = slf.items[row].item or slf.items[row]

        if slf.MLOS_activeContextMenu and slf.MLOS_activeContextMenu:isReallyVisible() then
            slf.MLOS_activeContextMenu:close()
            slf.MLOS_activeContextMenu = nil
        end

        local screenX = slf:getAbsoluteX() + x + slf:getXScroll() + PADDING
        local screenY = slf:getAbsoluteY() + y + slf:getYScroll() - BUTTON_HGT * 0.3

        local context = MLOS_ContextMenu:new(screenX, screenY)
        slf.MLOS_activeContextMenu = context

        for _, entry in ipairs(slf.MLOS_ItemContextMenu) do
            local isEnabled = true
            if entry.enabled ~= nil then
                if type(entry.enabled) == "function" then
                    isEnabled = entry.enabled(selectedRawItems, clickedRawItem, entry.arguments)
                else
                    isEnabled = entry.enabled
                end
            end

            local title = entry.name
            if type(title) == "function" then
                title = title(selectedRawItems, clickedRawItem)
            end
            
            if isEnabled then
                context:addOption(
                    title,
                    entry.tooltip,
                    slf,
                    entry.menuFunction,
                    selectedRawItems,
                    row,
                    clickedRawItem
                )
            end
        end

        context:display()
    end
end

function MLOS_ScrollExtensions:addItemContextMenu(scrollObject, menuName, tooltip, menuFunc, enabledFunc)
    if not scrollObject or not scrollObject.items then return end

    initialiseItemContextMenu(scrollObject)

    scrollObject.MLOS_ItemContextMenu[#scrollObject.MLOS_ItemContextMenu + 1] = {
        name = menuName,
        tooltip = tooltip,
        menuFunction = menuFunc,
        enabled = enabledFunc
    }
end
-- #endregion


-- #region =================== Context Menu ===================
-- New variables:
-- ScrollObject: MLOS_ItemContextMenu, MLOS_activeContextMenu
-- ScrollObject.parent: -
-- ============================================================

local function MLOS_ContextMenuOnButton(target, button)
    if button.MLOS_ContextMenus == nil then return end

    if target.MLOS_activeContextMenu and target.MLOS_activeContextMenu:isReallyVisible() then
        target.MLOS_activeContextMenu:close()
        target.MLOS_activeContextMenu = nil
    end

    local context = MLOS_ContextMenu:new(target:getAbsoluteX() + button:getRight(), target:getAbsoluteY() + button.y)
    target.MLOS_activeContextMenu = context

    for _, entry in ipairs(button.MLOS_ContextMenus) do
            local title = entry.name
            if type(title) == "function" then
                title = title(target)
            end

            context:addOption(
                title,
                entry.tooltip,
                target,
                entry.menuFunction
            )
        end

        context:display()
end

function MLOS_ScrollExtensions:addContextMenuOption(contextMenuBtn, name, tooltip, func)
    if not contextMenuBtn or not contextMenuBtn.MLOS_ContextMenus then return end

    contextMenuBtn.MLOS_ContextMenus[#contextMenuBtn.MLOS_ContextMenus + 1] = {
        name = name,
        tooltip = tooltip,
        menuFunction = func
    }
end

---comment
---@param target any
---@param x any
---@param y any
---@param tooltip any
---@return ISButton
function MLOS_ScrollExtensions:addContextMenu(target, x, y, tooltip)
    if not target then return end

    local contextMenuBtn = ISButton:new(x, y, BUTTON_HGT, BUTTON_HGT, nil, target, MLOS_ContextMenuOnButton)
    contextMenuBtn:initialise()
    contextMenuBtn:instantiate()
    contextMenuBtn:setTooltip(tooltip)
    contextMenuBtn:ignoreWidthChange()
    contextMenuBtn:ignoreHeightChange()
    contextMenuBtn.isBorderVisible = false
    contextMenuBtn:setTextureRGBA(1.0, 1.0, 1.0, 0.8)
    contextMenuBtn:setImage(getTexture("media/ui/MLOS_menu_vertical_dots.png"))

    contextMenuBtn.MLOS_ContextMenus = {}
    return contextMenuBtn
end
-- #endregion





return MLOS_ScrollExtensions