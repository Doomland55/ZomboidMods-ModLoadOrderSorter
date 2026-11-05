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
require("ISUI/ISTickBox")
require("ISUI/ISToolTip")
require("ISUI/ISScrollingListBox")
require("ISUI/ISButton")
require("OptionScreens/ModSelector/ModSelector")

local utils = require('REfRigERatoR_ModLoadOrderSorter/Core/1_Utils')
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local layersManager = require('REfRigERatoR_ModLoadOrderSorter/Layers/Manager')
local sortingCore = require('REfRigERatoR_ModLoadOrderSorter/Core/2_SortingCore')
local scrollExt = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/ScrollExtensions')
local popup = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/WarningPopup')
local Editor = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/SortingRulesEditor')


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
    self:MLOS_updateView()
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
    local panel = self
    print("[MLOS] Layers initialisation STARTED")
    if self.MLOS_ProgressBar then
        self.MLOS_ProgressBar:setVisible(true)
        self.MLOS_ProgressBar:setText("Checking workshop updates...")
        self.MLOS_ProgressBar:setProgress(0)
    end
    core.layersManager:initialise(self.modList.items, {
        onFilesProgress = function(current, total)
            if panel.MLOS_ProgressBar then
                panel.MLOS_ProgressBar:setVisible(true)
                panel.MLOS_ProgressBar:setText(getText("UI_MLOS_Analysis_Progress", current, total))
                panel.MLOS_ProgressBar:setProgress(total > 0 and (current / total) or 1)
            end
        end,
        onComplete = function()
            print("[MLOS] Layers initialisation FINISHED")
            if panel.MLOS_ProgressBar then panel.MLOS_ProgressBar:setVisible(false) end
            panel:showLayerWarnings()
            panel:MLOS_refresh()
        end,
    })
end


--- Shows aggregated warnings of all layers in the warning popup
--- (e.g. enabled mods that are not loaded in this Lua session -> reload Lua)
function ModLoadOrderPanelOverride:showLayerWarnings()
    if not self.warningPopup then return end
    local warnings = core.layersManager:getWarnings()
    for _, w in ipairs(warnings) do
        self.warningPopup:addMessage(w.title, w.message, w.layer, w.severity)
    end
end


-- Topological auto sort: builds the dependency graph from all layers,
-- sorts the mods and applies the new order (with a backup file)
function ModLoadOrderPanelOverride:autoSort()
    local sortedIds = sortingCore:sort(self.modList.items)
    sortingCore:applyOrder(self, sortedIds)

    if self.warningPopup then
        for _, w in ipairs(sortingCore.warnings) do
            self.warningPopup:addMessage(w.title, w.message, w.layer, w.severity)
        end
    end
    self.modList.selected_map = {}; self.modList.selected_flat = nil
    self:MLOS_refresh()
    print("[MLOS] " .. getText("UI_MLOS_SortApplied"))
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
    self.MLOS_ProgressBar = ISProgressBar:new((width * (1 - 0.2)) * 0.5 , self.backButton.y, width * 0.2, BUTTON_HGT, "")
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

    local x = width * 0.5 + PADDING
    local rightWidth = width - x - PADDING
    local sortButton = ISButton:new(x, 10, 150, BUTTON_HGT, "Auto sort", self, self.autoSort)
    sortButton:initialise(); sortButton:instantiate(); self:addChild(sortButton)
    local editButton = ISButton:new(x + 160, 10, 150, BUTTON_HGT, "Rules editor", self, function(panel)
        if not core.layers.sortingRules or not core.layers.modInfo then return end
        local w, h = getCore():getScreenWidth() * .9, getCore():getScreenHeight() * .85
        local editor = Editor:new((getCore():getScreenWidth()-w)/2, (getCore():getScreenHeight()-h)/2, w, h, panel)
        editor:initialise(); editor:instantiate()
        if panel.fileTooltip:getIsVisible() then panel.fileTooltip:setVisible(false); panel.fileTooltip:removeFromUIManager() end
        panel:setVisible(false)
        editor:addToUIManager(); editor:bringToTop()
    end)
    editButton:initialise(); editButton:instantiate(); self:addChild(editButton)
    self.conflictFilter = ISTickBox:new(x, 46, rightWidth, 25, "", self, function(panel) panel:MLOS_refresh() end)
    self.conflictFilter:initialise(); self.conflictFilter:instantiate()
    self.conflictFilter:addOption("Show conflicts only"); self:addChild(self.conflictFilter)
    local inspector = ISPanel:new(x, 76, rightWidth, height - 76 - BUTTON_HGT - 20)
    inspector:initialise(); inspector:instantiate(); self:addChild(inspector)
    local list = ISScrollingListBox:new(0, 40, rightWidth, inspector.height - 40)
    list:initialise(); list:instantiate(); list.itemheight = FONT_HGT_SMALL + 8
    list.doDrawItem = function(box, y, row)
        local color = row.item.conflict and {1, .65, .2} or {1,1,1}
        if box.selected == row.index then box:drawRect(0,y,box.width,row.height,.25,.6,.6,.6) end
        box:drawText(row.text, 4, y+3, color[1],color[2],color[3],1,UIFont.Small)
        return y + row.height
    end
    inspector:addChild(list); self.filesList = list
    scrollExt:addSearchEntry(list, -40)
    self.fileTooltip = ISToolTip:new(); self.fileTooltip:setOwner(self)
    self.fileTooltip:setVisible(false); self.fileTooltip:setAlwaysOnTop(true); self.fileTooltip.followMouse = true
    scrollExt:addContextMenu(self, self.modList.width - PADDING, 53)
    scrollExt:addContextMenuOption(self, "Re-scan files", "Rebuild the file analysis cache", function(panel)
        core.layersManager:initialise(panel.modList.items, {
            reread = true,
            onFilesProgress = function(n, total)
                panel.MLOS_ProgressBar:setVisible(true)
                panel.MLOS_ProgressBar:setProgress(total > 0 and n / total or 1)
            end,
            onComplete = function()
                panel.MLOS_ProgressBar:setVisible(false); panel:MLOS_refresh(); panel:showLayerWarnings()
            end
        })
    end)
end

-- Validation and inspector are shared between mouse selection, drag/reorder,
-- completed analysis and editor saves. The signature avoids rebuilding every frame.
function ModLoadOrderPanelOverride:MLOS_updateView()
    if not self.modList or not self.filesList or not core.layers.modInfo then return end
    local parts = {}
    for _, row in ipairs(self.modList.items) do parts[#parts+1] = row.item.modId end
    for index in pairs(self.modList.selected_map or {}) do parts[#parts+1] = "@" .. index end
    parts[#parts+1] = tostring(self.modList.selected)
    local signature = table.concat(parts, "|")
    if signature ~= self.MLOS_viewSignature then self.MLOS_viewSignature = signature; self:MLOS_refresh() end
    local list = self.filesList
    local row = list:isMouseOver() and list.items[list.mouseoverselected or -1] or nil
    if row then
        self.fileTooltip.name = row.text
        self.fileTooltip.description = table.concat(row.item.details, " <LINE> ")
        if not self.fileTooltip:getIsVisible() then self.fileTooltip:addToUIManager(); self.fileTooltip:setVisible(true) end
    elseif self.fileTooltip:getIsVisible() then
        self.fileTooltip:setVisible(false); self.fileTooltip:removeFromUIManager()
    end
end

function ModLoadOrderPanelOverride:MLOS_refresh()
    if not self.filesList or not core.layers.modInfo then return end
    local status = sortingCore:validate(self.modList.items)
    local colors = {red={r=.98,g=.2,b=.2}, purple={r=.75,g=.3,b=1}, yellow={r=1,g=.75,b=.2}}
    for i, row in ipairs(self.modList.items) do
        row.itemindex = i
        row.color = colors[status[row.item.modId]] or {r=1,g=1,b=1}
    end
    local data = core.layers.modFiles and core.layers.modFiles.data or {}
    local files, targets = {}, {}
    for id, mod in pairs(data) do
        for _, file in ipairs(mod.files or {}) do
            files[file] = files[file] or {}; files[file][id] = true
        end
        for _, m in ipairs(mod.modifications or {}) do
            local target = (m.className or '') .. '.' .. (m.methodName or '')
            targets[target] = targets[target] or {}; targets[target][id] = true
        end
    end
    local function count(set) local n=0; for _ in pairs(set or {}) do n=n+1 end; return n end
    local selected = self.modList.selected_map or {}
    if not next(selected) and self.modList.selected and self.modList.selected > 0 then selected = {[self.modList.selected]=true} end
    local union = {}
    for i in pairs(selected) do
        local row = self.modList.items[i]
        local id = row and row.item.modId
        local mod = id and data[id]
        if mod then
            for _, file in ipairs(mod.files or {}) do
                local entry = union[file] or {details={}, conflict=count(files[file]) > 1, seen={}}
                union[file] = entry
                if not entry.seen[id] then
                    entry.seen[id] = true
                    local owners = {}; for owner in pairs(files[file] or {}) do owners[#owners+1] = owner end
                    table.sort(owners)
                    entry.details[#entry.details+1] = "File: " .. table.concat(owners, ", ")
                end
            end
            for _, m in ipairs(mod.modifications or {}) do
                local entry = union[m.file]
                if entry then
                    local target = (m.className or '') .. '.' .. (m.methodName or '')
                    entry.details[#entry.details+1] = id .. ': ' .. (m.fullTarget or target)
                    if count(targets[target]) > 1 then
                        entry.conflict = true
                        local owners = {}; for owner in pairs(targets[target]) do owners[#owners+1] = owner end
                        table.sort(owners)
                        entry.details[#entry.details+1] = target .. " : " .. table.concat(owners, ", ")
                    end
                end
            end
        end
    end
    self.filesList:clear()
    self.filesList.parent.foundItems = {}; self.filesList.parent.foundIndex = 0
    local names = {}; for name in pairs(union) do names[#names+1] = name end; table.sort(names)
    local only = self.conflictFilter:isSelected(1)
    for _, name in ipairs(names) do
        if not only or union[name].conflict then
            union[name].name = name; union[name].modId = name
            self.filesList:addItem(name, union[name])
            self.filesList.items[#self.filesList.items].itemindex = #self.filesList.items
        end
    end
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
