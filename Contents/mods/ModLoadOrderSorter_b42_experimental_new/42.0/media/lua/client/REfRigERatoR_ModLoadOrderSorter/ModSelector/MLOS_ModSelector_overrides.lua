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
require("ISUI/ISProgressBar")
require("OptionScreens/ModSelector/ModSelector")

local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local scrollExt = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/ScrollExtensions')
local popup = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/WarningPopup')


local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = math.max(25, FONT_HGT_SMALL + 3 * 2)
local PADDING = 10

local ModLoadOrderPanelOverride = ModSelector.ModLoadOrderPanel


-- #region =========== Local Functions ===========
-- local function updateModsCache(enabldMods)
--     SortingRules:getData(true)
-- 	local currentOrder = ModsInfo:UpdateData(enabldMods, SortingRules.data)
-- end



-- #endregion

--================================================
--      ModLoadOrderPanelOverride Overrides
--================================================
local origCreateChildren = ModLoadOrderPanelOverride.createChildren
local origInstantiate = ModLoadOrderPanelOverride.instantiate


-- #region ================ FIXES =================
function ModLoadOrderPanelOverride:fixMissingModsCrash()
    local modArray = self.model:getActiveMods():getMods():clone()
    local missedMods = {}

    for i = 0, modArray:size()-1 do
        local modId = modArray:get(i)
        if modId ~= nil and not self.model.mods[modId] then
            self.model:setModActive(modId, false)
            table.insert(missedMods, modId)
        end
    end

    if not utils:tableIsEmpty(missedMods) then
        pcall(function(missedMods) error("\n[WARNING] --> [MLOS] Mods: [" .. table.concat(missedMods, ', ') .. "] were not found. They will be disabled to prevent the game from crashing.\n") end, missedMods)
    end
end


function ModLoadOrderPanelOverride:fixBackButtonJoypadFocus()
    local fixedBackFunc = function(slf, button, x, y)
        if button.internal == "BACK" then
            local isChanged = false
            for i, val in ipairs(slf.modList.items) do
                if slf.defaultOrder[i] ~= val.item.modId then
                    isChanged = true
                    break
                end
            end

            if isChanged then
                slf:setVisible(false)
                local w = 300
                local h = 100
                local modal = ISModalDialog:new(getCore():getScreenWidth()/2 - w/2, getCore():getScreenHeight() / 2 - h/2, w, h, getText("UI_mods_backAccept"), true, slf, slf.acceptChanges)
                modal:initialise()
                modal:addToUIManager()
                modal:bringToTop()
                if self.joyfocus then
                    self.joyfocus.focus = modal
                    updateJoypadFocus(self.joyfocus)
                end
                return
            else
                slf:setVisible(false)
                slf:removeFromUIManager()
                ModSelector.instance:setVisible(true, slf.joyfocus)
            end
        end
    end

    self.backButton:setOnClick(fixedBackFunc)
end
-- #endregion

-- #region ============== Autoscroll ==============
-- Scroll list box up or down if mouse is outside 
-- ================================================
function ModLoadOrderPanelOverride:render()
    ISPanelJoypad.render(self)
    ISPanelJoypad.render(self)
    if self.modList.dragItem == nil then return end

    local mY = self:getMouseY()
    local diff = 0
    if mY < self.modList:getY() then diff = mY - self.modList:getY() end
    if mY > self.modList:getBottom() then diff = mY - self.modList:getBottom() end
    if diff == 0 then return end

    self.modList:setYScroll(self.modList:getYScroll() - (diff * 0.02 * UIManager.getMillisSinceLastRender()))
end
--#endregion


function ModLoadOrderPanelOverride:instantiate()
    origInstantiate(self)
    print("MLOS_Start")
    core.layersManager:initialise(self.modList.items)
    print("MLOS_Finish")
    -- updateModsCache(self.modList.items)
end


function ModLoadOrderPanelOverride:createChildren()
    origCreateChildren(self)

    -- FIXES --
    self:fixMissingModsCrash()
    self:fixBackButtonJoypadFocus()

    -- RESCALE --
    local scrWidth = getCore():getScreenWidth()
    local scrHeight = getCore():getScreenHeight()
    local width = scrWidth * 0.8
    local height = scrHeight * 0.9
    self:setX((scrWidth - width) * 0.5)
    self:setWidth(width)
    self:setY((scrHeight - height) * 0.5)
    self:setHeight(height)

    -- NEW UI Elements --
    self.MLOS_ProgressBar = ISProgressBar:new((width - 100) * 0.5 , self.backButton.y, 100, BUTTON_HGT, "")
    self.MLOS_ProgressBar:setVisible(false)
    self.MLOS_ProgressBar:setAnchorLeft(true)
    self.MLOS_ProgressBar:setAnchorRight(false)
    self.MLOS_ProgressBar:setAnchorTop(false)
    self.MLOS_ProgressBar:setAnchorBottom(true)
    self.MLOS_ProgressBar:ignoreWidthChange()
    self.MLOS_ProgressBar:ignoreHeightChange()
    self:addChild(self.MLOS_ProgressBar)

    self.warningPopup = popup:new(width - 48 - PADDING, PADDING)
    self.warningPopup:setAnchorLeft(true)
    self.warningPopup:setAnchorRight(false)
    self.warningPopup:setAnchorTop(true)
    self.warningPopup:setAnchorBottom(false)
    self.warningPopup:ignoreWidthChange()
    self.warningPopup:ignoreHeightChange()
    self:addChild(self.warningPopup)

    -- ADD NEW FUNCTIONS --
    scrollExt:initialResacale(self.modList, nil, 50, width * 0.5 - PADDING * 2, height - (50 + PADDING + BUTTON_HGT + PADDING))
    scrollExt:modListBoxOverrides(self.modList)
    scrollExt:addTitle(self.modList, "", true, nil) --{r=0.28, g=0.35, b=0.8, a=0.8}
    scrollExt:addBackground(self.modList, nil, {})
    scrollExt:addSearchEntry(self.modList, self:getAbsoluteY() + 50 - self.modList:getAbsoluteY() - 3)
    scrollExt:addMoveButtons(self.modList)
    scrollExt:addMultiselectionSupport(self.modList)

    scrollExt:addContextMenu(self, self.modList.width - PADDING , 50 + 3)
    scrollExt:addContextMenuOption(self, "Save to file", "Save mods to files", function(slf) print("[MLOS] Saved to file") end)
    scrollExt:addContextMenuOption(self, "Save to clipboard", "Save mods to clipboard", function(slf) print("[MLOS] Saved to clipboard") end)
    scrollExt:addContextMenuOption(self, "Open MLOS folder", "Open folder with  Mod Load Order Sorter cache files", function(slf) print("[MLOS] Open MLOS folder") end)

    -- scrollExt:addCollapsableFoldersSupport(self.modList)
    -- scrollExt:addFolder(self.modList, "unsorted")





    scrollExt:addItemContextMenu(self.modList,
        function(selectedItems)
            if #selectedItems > 1 then return "Disable (" .. #selectedItems .. ")"
            else return "Disable" end
        end,
        "Disables selected mods",
        function(slf, selectedItems, clickedRawItem)
            for _, item in ipairs(selectedItems) do
                ModSelector.instance.model:forceActivateMods(item.modInfo, false)

            end
        end
    )

    scrollExt:addItemContextMenu(self.modList,
        "Debug print",
        "Print mod list",
        function(slf, selectedItems, clickedId,  clickedRawItem)
            utils:tprint(ModsInfo.data)
        end
    )
    scrollExt:addItemContextMenu(self.modList,
        "Debug get all mods files ",
        nil,
        function(slf, selectedItems, clickedId, clickedRawItem)
            local loadedLuaCount = getLoadedLuaCount()
            local p = nil
            for i = 0, loadedLuaCount-1 do
                p = getLoadedLua(i)
                if string.find(p, "/workshop/", 1, true) or string.find(p, "/Workshop/", 1, true) then
                    print("MCH Loaded Lua:", p)
                end
            end
        end
    )
    scrollExt:addItemContextMenu(self.modList,
        "Debug analyzeFolders",
        nil,
        function(slf, selectedItems, clickedId, clickedRawItem)
            ModsFiles:analyzeFolders(slf.items)
        end
    )

    scrollExt:addItemContextMenu(self.modList,
        "Debug analyzeFolders Background",
        nil,
        function(slf, selectedItems, clickedId, clickedRawItem)
            ModsFiles:startAsyncAnalysis(slf.items, 
                function(current, total)
                    -- Обновляем текст в UI:
                    myProgressBar:setText(string.format("Анализ модов: %d / %d", current, total))
                    myProgressBar:setProgress(current/total)
                end,
                function(finalResult)
                    print("Анализ завершен без лагов!")
                    -- Запускаем топологическую сортировку модов
                end
            )
        end
    )
    scrollExt:addItemContextMenu(self.modList,
        "Debug popup",  nil,
        function(slf, selectedItems, clickedId,  clickedRawItem)
            local rnd =  ZombRand(0,2)
            slf.parent.warningPopup:addMessage("O blya", "Something wrong with " .. tostring(selectedItems[1].modId) .." fsdfdaslgfmklosrefmgioasrgnadsfgasdfsgjlkdafsnvlvaiolgmlkasdgidciovvmnaskldfgnmklasdm asdjfnajsdfn asdnf asdkjfnioavb jdnf dgjnasdnf jasnvn nandjasfn suaidjkfasbn ", "debug", rnd == 0 and "CRITICAL" or "WARNING")
        end
    )



 

    

    -- -- NEW ELEMENTS 
    -- local modFilesScroll = ISScrollingListBox:new(width * 0.5 + PADDING, 50, width * 0.5 - PADDING * 3, height - (50 + PADDING + BUTTON_HGT + PADDING))
    -- modFilesScroll:initialise()
    -- modFilesScroll:instantiate()
    -- self:addChild(modFilesScroll)

    -- scrollExt:addTitle(modFilesScroll, "Fiels", true, {r=0.28, g=0.35, b=0.8, a=0.8})
    -- scrollExt:addBackground(modFilesScroll, nil, {})
end



-- function ModLoadOrderPanelOverride:autoSort()
--     -- Sort mods  (targetOrder is an array of modId)
--     local targetOrder = MLOS_sorting:SortModsOrder(self.modList.items)
--     -- apply mods order
--     local newItems = {}
--     for i, val in ipairs(targetOrder) do
--         newItems[i] = MLOS_sorting.modsInfoCache[val].object
--     end
--     self.modList.items = newItems
-- end


-- function ModLoadOrderPanelOverride:getTooltip(modInfo)
--     return nil
-- end


-- function ModLoadOrderPanelOverride:updateCache()
--     self:onChangeText()
--     if not utils:tableIsEmpty(self.multiselected) then
--         self.multiselected = {}
--         self.multiselected_counter = 150 * #self.multiselected_temp
--     end
-- end


-- function ModLoadOrderPanelOverride:onSaveButton(button)
--     local modIDs, workshopIDs = utils:getModsIDs(self.modList.items)

--     local text_parts = {"Mods=", table.concat(modIDs, ";"), "\n", "WorkshopItems=", table.concat(workshopIDs, ";")}
--     if button.internal == "COPY_TO_CB" then 
--         Clipboard.setClipboard(table.concat(text_parts, ""))
--     end

--     if button.internal == "SAVE_TO_FILE" then 
--         local file = getFileWriter(modsInfoFileName, true, false)
--         file:write(table.concat(text_parts, ""))
--         file:close()
--     end

-- end

-- --================================================
-- --           Search Items methods
-- --================================================


-- function ModLoadOrderPanelOverride:onChangeText()
--     if not utils:tableIsEmpty(self.foundItems) then
--         self.foundItems = {}
--         self.foundIndex = 0
--     end
-- end


-- function ModLoadOrderPanelOverride:searchItems()
--     if not utils:tableIsEmpty(self.foundItems) then return end

--     local searchWord = string.lower(self.searchEntry:getInternalText())
--     if not searchWord or searchWord == "" then return end

--     for i, item in ipairs(self.modList.items) do
--         if string.find(string.lower(item.item.name), searchWord) or string.find(string.lower(item.item.modId), searchWord) then
--             table.insert(self.foundItems, i)
--         end
--     end
-- end


-- function ModLoadOrderPanelOverride:onSearchButton(button)
--     self:searchItems()
--     if utils:tableIsEmpty(self.foundItems) then return end

--     if button.internal == "NEXT_SEARCH" then self.foundIndex = self.foundIndex + 1 end
--     if button.internal == "PREV_SEARCH" then self.foundIndex = self.foundIndex - 1 end

--     if self.foundIndex > #self.foundItems then self.foundIndex = 1 end
--     if self.foundIndex < 1 then self.foundIndex = #self.foundItems end

--     local itemIndex = self.foundItems[self.foundIndex]
--     if itemIndex ~= nil then
--         self.modList:ensureVisible(itemIndex)
--         self.foundCounter = 400
--     end
-- end

-- --================================================
-- -- Scroll list box up or down if mouse is outside 
-- --================================================

-- function ModLoadOrderPanelOverride:render()
--     ISPanelJoypad.render(self)
--     if self.modList.dragItem == nil then return end

--     local mY = self:getMouseY()
--     local diff = 0
--     if mY < self.modList:getY() then diff = mY - self.modList:getY() end
--     if mY > self.modList:getBottom() then diff = mY - self.modList:getBottom() end
--     if diff == 0 then return end

--     self.modList:setYScroll(self.modList:getYScroll() - (diff * 0.02 * UIManager.getMillisSinceLastRender()))
-- end

-- --================================================
-- --      ModOrderListBoxOverride Overrides
-- --================================================

-- local origDoDrawItem = ModOrderListBoxOverride.doDrawItem
-- local origOnMouseDown = ModOrderListBoxOverride.onMouseDown


-- function ModOrderListBoxOverride:updateModsColor()
--     self.parent:updateCache()
--     self.mouseOverRulesIcon = nil

--     self.parent.acceptButton.enable = MLOS_sorting:validateSorting(self.items)
--     for i, val in ipairs(self.items) do
--         val.itemindex = i  -- update item index
-- 		local extraModInfo = MLOS_sorting.modsInfoCache[val.item.modId]
--         if extraModInfo ~= nil then
--             if not utils:tableIsEmpty(extraModInfo.warnings.missing) then
--                 val.color = {r = 0.98, g = 0.08, b = 0.08}
--             elseif not utils:tableIsEmpty(extraModInfo.warnings.incompatible) then
--                 val.color = {r = 0.65, g = 0.08, b = 0.90}
--             elseif not utils:tableIsEmpty(extraModInfo.warnings.rules) then
--                 val.color = {r = 0.98, g = 0.66, b = 0.06}
--             else
--                 val.color = {r = 0.10, g = 0.62, b = 0.08}
--             end

--             val.tooltip = MLOS_methods:getTooltipText(extraModInfo)
--         end
--     end
-- end


-- function ModOrderListBoxOverride:doDrawItem(y, item, alt)
--     local parent = self.parent
--     if parent.foundCounter > 0 and parent.foundIndex > 0 and parent.foundItems[parent.foundIndex] == item.itemindex then
--         parent.foundCounter = parent.foundCounter - 1
--         local alpha = 0.30
--         if parent.foundCounter < 80 then alpha = alpha - (alpha * alpha) end
--         self:drawRect(0, (y), self:getWidth(), item.height-1, alpha, 0.5, 1, 1)
--     end

--     if utils:contains(parent.multiselected, item.itemindex) then
--         self:drawRect(0, (y), self:getWidth(), item.height-1, 0.3, 0.7, 0.35, 0.15)
--     end

--     if parent.multiselected_counter > 0 and utils:contains(parent.multiselected_temp, item.itemindex) then
--         parent.multiselected_counter = parent.multiselected_counter - 1
--         self:drawRect(0, (y), self:getWidth(), item.height-1, 0.2, 0.58, 1, 0.12)
--     end

--     -- sorting rules icon
--     local isMouseOver = self.mouseoverselected == item.index
--     local shift = (item.height - self.boxSize)/2
--     local textureX = self:getWidth() - shift - self.boxSize - 20
--     local sr = self.parent.sortingRules
--     if sr.modInfoCache == nil or (sr.modInfoCache.id == item.item.modId) then
--         self:drawTexture(rulesTexture, textureX, shift + y, 1, 1, 1, 1)
--     end
--     if isMouseOver then
--         local mX, mY = self:getMouseX(), self:getMouseY()
--         if (mX > textureX) and (mX < textureX + self.boxSize) and (mY > shift + y) and (mY < shift + y + self.boxSize) then
--             self.mouseOverRulesIcon = item
--         else
--             self.mouseOverRulesIcon = nil
--         end
--     end

--     return origDoDrawItem(self, y, item, alt)
-- end


-- function ModOrderListBoxOverride:onMouseDown(x, y)
--     origOnMouseDown(self, x, y)
--     local row = utils:clamp(self:rowAt(x, y), 1, #self.items)

--     if self.parent.sortingRules:onClickItemInList(self.mouseOverRulesIcon, self.items[row]) then
--         if not utils:tableIsEmpty(self.parent.multiselected) then self.parent.multiselected = {} end
--         return
--     end

--     if self.mouseOverDragIcon then
--         if utils:tableIsEmpty(self.parent.multiselected) or utils:getElementIndex(self.parent.multiselected, self.dragItem.itemindex) == nil then
--             self.parent.multiselected = {self.dragItem.itemindex,}
--         end
--         return
--     end
--     self.parent.multiselected = MLOS_methods:selectObject(self.parent.multiselected, row, isCtrlKeyDown(), isShiftKeyDown())
--     if not utils:tableIsEmpty(self.parent.multiselected) then
--         self.parent.multiselected_temp = {}
--     end
-- end


-- function ModOrderListBoxOverride:onMouseUp(x, y)
--     ISScrollingListBox.onMouseUp(self, x, y)

--     if self.dragItem ~= nil then
--         local clickedRow = (y / self.itemheight) + 1.0
--         local row = clickedRow - clickedRow % 1
--         local drob = clickedRow % 1

--         if row > self.dragItem.itemindex and drob <= 0.5 then row = row - 1 end
--         row = utils:clamp(row, 1, self:size())

--         if row ~= self.dragItem.itemindex then
--             local initial_count = #self.items
--             self.parent.multiselected_temp = MLOS_methods:moveElements(self, self.parent.multiselected, row, self.dragItem.itemindex)

--             if initial_count ~= #self.items then
--                 error("items size changed! Expected size: " .. initial_count .. ", Actual size: " .. #self.items)
--             end
--             self:updateModsColor()
--         end
--     end
--     self.dragItem = nil
-- end


-- function ModOrderListBoxOverride:onMouseUpOutside(x, y)
--     ISScrollingListBox.onMouseUpOutside(self, x, y)
--     if self.parent:isMouseOver() then
--         self:onMouseUp(x,y)
--     end
--     self.dragItem = nil
-- end
