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
require "ISUI/ISPanelJoypad"
local utils = require('OptionScreens/ModSelector/Refr_utils')
local MLOS_sorting = require('OptionScreens/ModSelector/MLOS_sorting')

local SortingRulesPanel = ISPanelJoypad:derive("SortingRulesPanel")

local PADDING = 10
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local borderColorLight = { r = 1, g = 1, b = 1, a = 0.6 }
local borderColorDark = { r = 1, g = 1, b = 1, a = 0.2 }


function SortingRulesPanel:new(x, y, width, height, modListObj)
    local o = ISPanelJoypad:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.background = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.9 }
    o.borderColor = { r = 1, g = 1, b = 1, a = 0.2 }
    o.modListObj=modListObj

    SortingRulesPanel.instance = o
    return o
end


function SortingRulesPanel:prerender()
    ISPanelJoypad.prerender(self)
    self:drawTextCentre(getText("UI_MLOS_SortingRules"), self.width / 2, PADDING, 1, 1, 1, 1, UIFont.Medium)
    self:drawTextCentre(self.modInfoCache.name, self.width / 2, PADDING * 2 + getTextManager():getFontHeight(UIFont.Small), 1, 1, 1, 1, UIFont.Small)
end


function SortingRulesPanel:addCache()
    self.editModeData = nil
    self.modInfoCache = nil

    -- add extra overrides
    self.origDoDrawItem = self.modListObj.doDrawItem
    self.modListObj.doDrawItem = function(modListObj, y, item, alt) return self:drawItem_override(modListObj, y, item, alt) end

    local orig_onmouse = self.modListObj.parent.onOptionMouseDown
    local newOnMouse = function(modpanel, button, x, y)
        self:onExitSortingRules();
        orig_onmouse(modpanel, button, x, y)
    end
    self.modListObj.parent.autoButton.onclick = newOnMouse
    self.modListObj.parent.backButton.onclick = newOnMouse
    self.modListObj.parent.acceptButton.onclick = newOnMouse
end


function SortingRulesPanel:createChildren()
    self:addCache()

    self.loadAfter = ISButton:new(PADDING, 2 * PADDING + getTextManager():getFontHeight(UIFont.Medium) + getTextManager():getFontHeight(UIFont.Small), self.width - PADDING * 2, BUTTON_HGT, getText("UI_MLOS_SortingRules_load_after_btn"), self, self.onButtonClick);
    self.loadAfter.internal = "LOAD_AFTER";
    self.loadAfter:initialise();
    self.loadAfter:instantiate();
    self.loadAfter:setAnchorsTBLR(true, false, true, false);
    self.loadAfter.borderColor = borderColorLight;
    self.loadAfter:setFont(UIFont.Small);
    self.loadAfter:ignoreWidthChange();
    self.loadAfter:ignoreHeightChange();
    self:addChild(self.loadAfter);

    self.loadBefore = ISButton:new(PADDING, self.loadAfter:getBottom() + PADDING, self.width - PADDING * 2, BUTTON_HGT, getText("UI_MLOS_SortingRules_load_before_btn"), self, self.onButtonClick);
    self.loadBefore.internal = "LOAD_BEFORE";
    self.loadBefore:initialise();
    self.loadBefore:instantiate();
    self.loadBefore:setAnchorsTBLR(true, false, true, false);
    self.loadBefore.borderColor = borderColorLight;
    self.loadBefore:setFont(UIFont.Small);
    self.loadBefore:ignoreWidthChange();
    self.loadBefore:ignoreHeightChange();
    self:addChild(self.loadBefore);

    self.incompatible = ISButton:new(PADDING, self.loadBefore:getBottom() + PADDING, self.width - PADDING * 2, BUTTON_HGT, getText("UI_MLOS_SortingRules_incompatible_btn"), self, self.onButtonClick);
    self.incompatible.internal = "INCOMPATIBLE";
    self.incompatible:initialise();
    self.incompatible:instantiate();
    self.incompatible:setAnchorsTBLR(true, false, true, false);
    self.incompatible.borderColor = borderColorLight;
    self.incompatible:setFont(UIFont.Small);
    self.incompatible:ignoreWidthChange();
    self.incompatible:ignoreHeightChange();
    self:addChild(self.incompatible);

    local loadTr = {on=getText("UI_MLOS_SortingRules_yes"), off=getText("UI_MLOS_SortingRules_no"), category=getText("UI_MLOS_SortingRules_in_category")}
    local loadFirstTr = getText("UI_MLOS_SortingRules_LoadFirst")
    local loadLastTr = getText("UI_MLOS_SortingRules_LoadLast")

    -- loadFirst
    self.loadFirstComboBox = ISComboBox:new(PADDING, self.incompatible:getBottom() + PADDING, self.width - PADDING * 2, BUTTON_HGT, self, self.onComboBoxChange)
    self.loadFirstComboBox.borderColor = borderColorLight
    for name, _ in pairs(MLOS_sorting:getLoadCategories()) do self.loadFirstComboBox:addOptionWithData(loadFirstTr .. ": " .. loadTr[name], name) end
    self:addChild(self.loadFirstComboBox)

    -- loadLast
    self.loadLastComboBox = ISComboBox:new(PADDING, self.loadFirstComboBox:getBottom() + PADDING, self.width - PADDING * 2, BUTTON_HGT, self, self.onComboBoxChange)
    self.loadLastComboBox.borderColor = borderColorLight
    for name, _ in pairs(MLOS_sorting:getLoadCategories()) do self.loadLastComboBox:addOptionWithData(loadLastTr .. ": " .. loadTr[name], name) end
    self:addChild(self.loadLastComboBox)

    -- category 
    self.categoryComboBox = ISComboBox:new(PADDING, self.loadLastComboBox:getBottom() + PADDING, self.width - PADDING * 2, BUTTON_HGT, self, self.onComboBoxChange)
    self.categoryComboBox.borderColor = borderColorLight
    self:addChild(self.categoryComboBox)

    self.applyBtn = ISButton:new(PADDING, self.categoryComboBox:getBottom() + PADDING, self.width - PADDING * 2, BUTTON_HGT, getText("UI_MLOS_SortingRules_apply_btn"), self, self.onButtonClick);
    self.applyBtn.internal = "APPLY";
    self.applyBtn:initialise();
    self.applyBtn:instantiate();
    self.applyBtn:setAnchorsTBLR(true, false, true, false);
    self.applyBtn:setFont(UIFont.Small);
    self.applyBtn:ignoreWidthChange();
    self.applyBtn:ignoreHeightChange();
    self:addChild(self.applyBtn);
    self.applyBtn.enable = false
end

function SortingRulesPanel:onMouseUpOutside(x, y)
    if not (self.modListObj.parent:isMouseOver() or self:isMouseOver()) then
        self:onExitSortingRules()
    end
end

function SortingRulesPanel:updateTooltips(modInfo)
    local text = getText("UI_MLOS_ClickEditMode_Tooltip")
    if modInfo == nil then
        self.loadAfter:setTooltip(text)
        self.loadBefore:setTooltip(text)
        self.incompatible:setTooltip(text)
    else
        local curRulesText = getText("UI_MLOS_CurrentRules_Tooltip")
        self.loadAfter:setTooltip(text .. "\n" .. curRulesText .. utils:getString(modInfo.sortingRules.loadAfter, 0))
        self.loadBefore:setTooltip(text .. "\n" .. curRulesText .. utils:getString(modInfo.sortingRules.loadBefore, 0))
        self.incompatible:setTooltip(text .. "\n" .. curRulesText .. utils:getString(modInfo.sortingRules.incompatibleMods, 0))
    end
    self.applyBtn:setTooltip(getText("UI_MLOS_SaveRules_Tooltip"))
end


function SortingRulesPanel:onComboBoxChange(combobox_obj)
    if self.applyBtn.enable ~= true then
        self.applyBtn.borderColor = borderColorLight
        self.applyBtn.enable = true
    end
end


function SortingRulesPanel:updateComboBoxValues(modInfo)
    self.categoryComboBox:clear()
    local categoryTr = getText("UI_MLOS_SortingRules_Category")
    for _, name in pairs(MLOS_sorting:getRawCategoryOrder()) do
        self.categoryComboBox:addOptionWithData(categoryTr .. ": " .. (modInfo.category == name and name .. " *" or name), name)
    end

    if modInfo ~= nil then
        self.loadFirstComboBox:selectData(modInfo.sortingRules.loadFirst or modInfo.loadFirst)
        self.loadLastComboBox:selectData(modInfo.sortingRules.loadLast or modInfo.loadLast)
        self.categoryComboBox:selectData(modInfo.sortingRules.category or modInfo.category)
        self.loadFirstComboBox.prev_selected = self.loadFirstComboBox.selected
        self.loadLastComboBox.prev_selected = self.loadLastComboBox.selected
        self.categoryComboBox.prev_selected = self.categoryComboBox.selected
    end
end


--===============================
function SortingRulesPanel:isOpened()
    return self.modInfoCache ~= nil
end

function SortingRulesPanel:inEditMode()
    return self.editModeData ~= nil
end
--===============================


function SortingRulesPanel:onClickItemInList(itemToOpen, clickedItem)
    if itemToOpen then
        if not self:isOpened() then
            self:onEnterSortingRules(itemToOpen)
            return true
        elseif self.modInfoCache.id == itemToOpen.item.modId then
            self:onExitSortingRules()
            return false
        end
    end
    if clickedItem and self:inEditMode() then
        self:onClickItemInEditMode(clickedItem)
        return true
    end
    if self:isOpened() then self:onExitSortingRules() end
    return false
end


function SortingRulesPanel:onEnterSortingRules(item)
    self.modInfoCache = MLOS_sorting.modsInfoCache[item.item.modId]
    if self.modInfoCache == nil then return end
    self:setHeight(PADDING*9 + BUTTON_HGT*7 + getTextManager():getFontHeight(UIFont.Medium) + getTextManager():getFontHeight(UIFont.Small))
    self:setY(getMouseY() - self:getHeight()/2)
    self:updateTooltips(self.modInfoCache)
    self:updateComboBoxValues(self.modInfoCache)
    self:setVisible(true)
    self:addToUIManager()
end


function SortingRulesPanel:onExitSortingRules(onlyUpdate)
    self.applyBtn.enable = false
    self.loadAfter.enable = true
    self.loadBefore.enable = true
    self.incompatible.enable = true
    self.loadFirstComboBox:setEnabled(true)
    self.loadLastComboBox:setEnabled(true)
    self.categoryComboBox:setEnabled(true)
    self.applyBtn.borderColor = borderColorDark
    self.loadAfter.borderColor = borderColorLight
    self.loadBefore.borderColor = borderColorLight
    self.incompatible.borderColor = borderColorLight
    self.loadFirstComboBox.borderColor = borderColorLight
    self.loadLastComboBox.borderColor = borderColorLight
    self.categoryComboBox.borderColor = borderColorLight

    self:updateTooltips()
    self.editModeData = nil

    if not onlyUpdate then
        self:close()
        self.modInfoCache = nil
        self:removeFromUIManager()
    end
end


local function updateModRulesList(modInfo, editModeData)
    local devRules = editModeData.type == "LOAD_AFTER" and modInfo.loadAfter or
                     editModeData.type == "LOAD_BEFORE" and modInfo.loadBefore or
                     editModeData.type == "INCOMPATIBLE" and modInfo.incompatibleMods or nil

    local rules = editModeData.type == "LOAD_AFTER" and modInfo.sortingRules.loadAfter or
                  editModeData.type == "LOAD_BEFORE" and modInfo.sortingRules.loadBefore or
                  editModeData.type == "INCOMPATIBLE" and modInfo.sortingRules.incompatibleMods or nil

    if rules ~= nil then
        for _, modId in ipairs(rules) do
            -- logic to prevent circular dependencies with loadBefore and loadAfter
            local modCache = MLOS_sorting.modsInfoCache[modId] or {}
            local devRulesOfModCache = editModeData.type == "LOAD_AFTER" and modCache.loadBefore or
                                       editModeData.type == "LOAD_BEFORE" and modCache.loadAfter or {}
            local temp = editModeData.color
            if utils:contains(devRules, modId) or utils:contains(devRulesOfModCache, modId)  then
                temp = { r = 1, g = 0, b = 0, a = 0.3 }
            end
            editModeData.curRules[modId] = temp
        end
    end
end


function SortingRulesPanel:onClickItemInEditMode(item)
    if self.editModeData == nil or item.item.modId == self.modInfoCache.id then return end

    local modId = item.item.modId
    local color = self.editModeData.curRules[modId]
    if modId == nil or (color ~= nil and color ~= self.editModeData.color) then return end

    -- TODO check applyBefore 
    -- if loadAfter contains mod from loadBefore then disable. and overwise
    if color == nil then
        self.editModeData.curRules[modId] = self.editModeData.color
    else
        self.editModeData.curRules[modId] = nil
    end
end


function SortingRulesPanel:applyChanges()
    -- local devRules = self.editModeData.type == "LOAD_AFTER" and self.modInfoCache.loadAfter or
    --                  self.editModeData.type == "LOAD_BEFORE" and self.modInfoCache.loadBefore or
    --                  self.editModeData.type == "INCOMPATIBLE" and self.modInfoCache.incompatibleMods or nil
    -- local rules = self.editModeData.type == "LOAD_AFTER" and self.modInfoCache.sortingRules.loadAfter or
    --               self.editModeData.type == "LOAD_BEFORE" and self.modInfoCache.sortingRules.loadBefore or
    --               self.editModeData.type == "INCOMPATIBLE" and self.modInfoCache.sortingRules.incompatibleMods or nil
    -- local rulesFromFile = utils:tableDifference(devRules, rules)

    -- add mod only if they are not in dev rules
    local modlist = {}
    local editModeData = self.editModeData or {}
    if self.editModeData ~= nil then
        for modId, color in pairs(self.editModeData.curRules) do
            if color == self.editModeData.color then
                table.insert(modlist, modId)
            end
        end
    end
    
    -- local newRules = utils:tableDifference(modlist, rulesFromFile)
    -- for _, modId in ipairs(newRules) do
    --     local _cache = MLOS_sorting.modsInfoCache[modId]
        
    --     if self.editModeData.type == "LOAD_AFTER" then
    --         local cacheloadbeforeDiff = utils:tableDifference(_cache.sortingRules.loadBefore, _cache.loadBefore)
    --         local index = utils:getElementIndex(_cache.sortingRules.loadBefore, modId)
    --         if index and utils:contains(cacheloadbeforeDiff, modId) then
    --             table.remove(_cache.sortingRules.loadBefore, index)
    --         end
    --         for modId, color in pairs(self.editModeData.curRules) do
    --             if color == self.editModeData.color then
    --                 table.insert(modSortingRules.loadAfter, modId)
    --             end
    --         end
    --         modSortingRules.loadAfter = rules
    --     end

    -- end

    MLOS_sorting:updateSortingRule(self.modInfoCache.id,
                                   editModeData.type == "LOAD_AFTER" and modlist or nil,
                                   editModeData.type == "LOAD_BEFORE" and modlist or nil,
                                   editModeData.type == "INCOMPATIBLE" and modlist or nil,
                                   self.loadFirstComboBox:getOptionData(self.loadFirstComboBox.selected),
                                   self.loadLastComboBox:getOptionData(self.loadLastComboBox.selected),
                                   self.categoryComboBox:getOptionData(self.categoryComboBox.selected))
    MLOS_sorting:saveSortingRules()
    self.modListObj:updateModsColor()
end

function SortingRulesPanel:switchEditMode(button, color)
    if button ~= nil and self.editModeData == nil then
        if self.applyBtn.enable == true then self:updateComboBoxValues(self.modInfoCache) end

        self.loadAfter.enable = button.internal == self.loadAfter.internal
        self.loadBefore.enable = button.internal == self.loadBefore.internal
        self.incompatible.enable = button.internal == self.incompatible.internal
        self.loadFirstComboBox:setEnabled(false)
        self.loadLastComboBox:setEnabled(false)
        self.categoryComboBox:setEnabled(false)
        self.loadFirstComboBox.borderColor = borderColorDark
        self.loadLastComboBox.borderColor = borderColorDark
        self.categoryComboBox.borderColor = borderColorDark

        self.loadAfter.borderColor = button.internal == self.loadAfter.internal and borderColorLight or borderColorDark
        self.loadBefore.borderColor = button.internal == self.loadBefore.internal and borderColorLight or borderColorDark
        self.incompatible.borderColor = button.internal == self.incompatible.internal and borderColorLight or borderColorDark
        button:setTooltip(getText("UI_MLOS_ClickCloseWithoutSaving_Tooltip"))

        self.editModeData = { type = button.internal, curRules = {}, color = color }
        updateModRulesList(self.modInfoCache, self.editModeData)

        self.applyBtn.borderColor = borderColorLight
        self.applyBtn.enable = true
    else
        self:onExitSortingRules(true)
    end
end

function SortingRulesPanel:onButtonClick(button)
    if button.internal == "LOAD_AFTER" then
        self:switchEditMode(button, { r = 0.5, g = 0.5, b = 0.5, a = 0.5 })
    elseif button.internal == "LOAD_BEFORE" then
        self:switchEditMode(button, { r = 0.5, g = 0.5, b = 0.5, a = 0.5 })
    elseif button.internal == "INCOMPATIBLE" then
        self:switchEditMode(button, { r = 0.5, g = 0.5, b = 0.5, a = 0.5 })
    elseif button.internal == "APPLY" then
        self:applyChanges()

        self.editModeData = nil
        self:switchEditMode()
        self:onExitSortingRules()
    end
end


--================================================
--               Extra Overrides
--================================================


function SortingRulesPanel:drawItem_override(modListObj, y, item, alt)
    local color = self.editModeData ~= nil and self.editModeData.curRules[item.item.modId] or nil
    if color ~= nil then
        modListObj:drawRect(0, (y), modListObj:getWidth(), item.height-1, color.a, color.r, color.g, color.b)
    end

    return self.origDoDrawItem(modListObj, y, item, alt)
end

return SortingRulesPanel
