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
local utils = require('OptionScreens/MLOS_core/Refr_utils')

local MLOS_sorting = require('OptionScreens/MLOS_core/MLOS_SortingCore')
local MLOS_ModInfoLayer = require('OptionScreens/MLOS_core/MLOS_Layer_ModsInfo')
-- local SortingRulesPanel = require('OptionScreens/ModSelector/MLOS_SortingRulesPanel')
local SortingRulesWindow = require('OptionScreens/ModSelector/MLOS_SortingRulesWindow')

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = math.max(25, FONT_HGT_SMALL + 3 * 2)

local ModLoadOrderPanelOverride = ModSelector.ModLoadOrderPanel

local toClipboardTexture = getTexture("media/ui/MLOS_To_Clipboard.png")
local toFileTexture = getTexture("media/ui/MLOS_To_Folder.png")

local modsInfoFileName="sorted_mods_info.ini"

--================================================
--      ModLoadOrderPanelOverride Overrides
--================================================
local origInstantiate = ModLoadOrderPanelOverride.instantiate
local origCreateChildren = ModLoadOrderPanelOverride.createChildren

function ModLoadOrderPanelOverride:instantiate()
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
        pcall(function(missedMods) error("\n[ERROR] --> [MLOS] Mods: [" .. table.concat(missedMods, ', ') .. "] were not found. They will be disabled to prevent the game from crashing.\n") end, missedMods)
    end

    origInstantiate(self)
end


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

    self.copyToCBButton = ISButton:new(self.width - 16 - BUTTON_HGT, 16, BUTTON_HGT, BUTTON_HGT, "", self, self.onSaveButton);
    self.copyToCBButton.internal = "COPY_TO_CB";
    self.copyToCBButton:initialise();
    self.copyToCBButton:instantiate();
    self.copyToCBButton:setAnchorLeft(true);
    self.copyToCBButton:setAnchorRight(false);
    self.copyToCBButton:setAnchorTop(false);
    self.copyToCBButton:setAnchorBottom(true);
    self.copyToCBButton:setImage(toClipboardTexture);
    self.copyToCBButton:setTextureRGBA(1,1,1,0.8);
    self.copyToCBButton.borderColor = {r=1, g=1, b=1, a=0};
    self.copyToCBButton:setFont(UIFont.Small);
    self.copyToCBButton:ignoreWidthChange();
    self.copyToCBButton:ignoreHeightChange();
    self.copyToCBButton:setTooltip(getText("UI_MLOS_SaveToClipboard_Tooltip"))
    self:addChild(self.copyToCBButton);

    self.saveToFile = ISButton:new(self.copyToCBButton:getX() - BUTTON_HGT - 8, self.copyToCBButton:getY(), BUTTON_HGT, BUTTON_HGT, "", self, self.onSaveButton);
    self.saveToFile.internal = "SAVE_TO_FILE";
    self.saveToFile:initialise();
    self.saveToFile:instantiate();
    self.saveToFile:setAnchorLeft(true);
    self.saveToFile:setAnchorRight(false);
    self.saveToFile:setAnchorTop(false);
    self.saveToFile:setAnchorBottom(true);
    self.saveToFile:setImage(toFileTexture);
    self.saveToFile:setTextureRGBA(1,1,1,0.8);
    self.saveToFile.borderColor = {r=1, g=1, b=1, a=0};
    self.saveToFile:setFont(UIFont.Small);
    self.saveToFile:ignoreWidthChange();
    self.saveToFile:ignoreHeightChange();
    self.saveToFile:setTooltip(string.format(getText("UI_MLOS_SaveToFile_Tooltip"), modsInfoFileName));
    self:addChild(self.saveToFile);

    local width = self.width*1.4
    local height = self.height
    self.sortingRulesWindow = SortingRulesWindow:new(
        (getCore():getScreenWidth() - width)/2,
        (getCore():getScreenHeight() - height)/2,
        width, height, self.modList)
    self.sortingRulesWindow:initialise()
    self.sortingRulesWindow:instantiate()
    self.sortingRulesWindow:setAlwaysOnTop(true)
    
    self.openSortingRulesButton = ISButton:new(self.autoButton:getRight() - self.autoButton.width - 8 - self.autoButton.width - 20,
                                               self.autoButton:getBottom() - BUTTON_HGT,
                                               self.autoButton.width, BUTTON_HGT, "Sorting rules", self, self.onSRButton);
    self.openSortingRulesButton:initialise();
    self.openSortingRulesButton:instantiate();
    self.openSortingRulesButton:setAnchorLeft(true);
    self.openSortingRulesButton:setAnchorRight(false);
    self.openSortingRulesButton:setAnchorTop(false);
    self.openSortingRulesButton:setAnchorBottom(true);
    self.openSortingRulesButton:setTextureRGBA(1,1,1,0.8);
    self.openSortingRulesButton.borderColor = {r=1, g=1, b=1, a=0};
    self.openSortingRulesButton:setFont(UIFont.Small);
    self.openSortingRulesButton:ignoreWidthChange();
    self.openSortingRulesButton:ignoreHeightChange();
    -- self.openSortingRulesButton:setTooltip(getText("UI_MLOS_SaveToClipboard_Tooltip"))
    self:addChild(self.openSortingRulesButton);
end


function ModLoadOrderPanelOverride:autoSort()
    -- Sort mods  (targetOrder is an array of modId)
    local targetOrder = MLOS_sorting:sortModsOrder(self.modList.items)
    -- utils:tprint(targetOrder)

    -- apply mods order
    local newItems = {}
    for i, val in ipairs(targetOrder) do
        
		-- local mod = MLOS_ModInfoLayer.data[val]
		-- print(mod.id)
		-- print("", "category", mod.category)
		-- print("", "requirements", table.concat(mod.requirements, ', '))
		-- print("", "loadAfter", table.concat(mod.loadAfter, ', '))
		-- print("", "loadBefore",table.concat( mod.loadBefore, ', '))
		-- print("", "incompatibleMods", table.concat(mod.incompatibleMods, ', '))
		-- print("", "loadFirst", mod.loadFirst)
		-- print("", "loadLast", mod.loadLast)
		-- print("", "maps", table.concat(mod.maps, ', '))
		-- print("", "warnings", table.concat(mod.warnings, ', '))
		-- print("", "flags", table.concat(mod.flags, ', '))
		-- print("", "tags", table.concat(mod.tags, ', '))
		-- print("", "fixedLoadAfter", table.concat(mod.fixedLoadAfter, ', '))
		-- print("", "sortingRules"); utils:tprint(mod.sortingRules, 3)

        newItems[i] = MLOS_ModInfoLayer.data[val].object
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
end


function ModLoadOrderPanelOverride:onSaveButton(button)
    local modIDs, workshopIDs = utils:getModsIDs(self.modList.items)

    local text_parts = {"Mods=", table.concat(modIDs, ";"), "\n", "WorkshopItems=", table.concat(workshopIDs, ";")}
    if button.internal == "COPY_TO_CB" then 
        Clipboard.setClipboard(table.concat(text_parts, ""))
    end

    if button.internal == "SAVE_TO_FILE" then 
        local file = getFileWriter(modsInfoFileName, true, false)
        file:write(table.concat(text_parts, ""))
        file:close()
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
-- Open Sorting Rules Window
--================================================

function ModLoadOrderPanelOverride:onSRButton(button)
    self.sortingRulesWindow:show(self.joyfocus)
    self:setVisible(false)
end