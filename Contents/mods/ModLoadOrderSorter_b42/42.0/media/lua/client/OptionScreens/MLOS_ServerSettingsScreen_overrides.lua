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
require "OptionScreens/ServerSettingsScreen"
local utils = require('OptionScreens/ModSelector/Refr_utils')

local rulesTexture = getTexture("media/ui/MLOS_From_Client.png")
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local FONT_HGT_LARGE = getTextManager():getFontHeight(UIFont.Large)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local UI_BORDER_SPACING = 10

--================================================
--    ChooseModsWindow add fromClient Button
--================================================
local onFromClientButton = function(self, ...)
    self.listbox:clear()
    local currentClientMods = getActivatedMods()
    for i = 1, currentClientMods:size() do
        self:addModToList(currentClientMods:get(i - 1))
    end
end

local function addPageEditFromClientButton(self, ...)
    self.fromClientBtn = ISButton:new(self.buttonMods:getRight() + UI_BORDER_SPACING, self.buttonMods.y, BUTTON_HGT, BUTTON_HGT, "", self, onFromClientButton)
    self.fromClientBtn:setImage(rulesTexture)
    self.fromClientBtn:setTextureRGBA(1, 1, 1, 0.9)
    self.fromClientBtn:setTooltip(getText("UI_MLOS_FromClientBtn_Tooltip"))
    self.fromClientBtn:setAnchorLeft(true)
    self.fromClientBtn:setAnchorTop(false)
    self.fromClientBtn:setAnchorBottom(true)
    self.fromClientBtn.borderColor = { r = 1, g = 1, b = 1, a = 0.1 }
    self:addChild(self.fromClientBtn)
end

--================================================
--             PageEdit overrides
--================================================
local backupPrefix = "__backup__"

local function createSettingsBackup(settings)
    local newName = backupPrefix .. settings:getName()
    settings:duplicateFiles(newName)
end

local function getSettingsByName(settingsName)
    local serverManager = getServerSettingsManager()
    serverManager:readAllSettings()
    for i = 1, serverManager:getSettingsCount() do
        local settings = serverManager:getSettingsByIndex(i - 1)
        if settings:getName() == settingsName then
            return settings
        end
    end
end

local function deleteSettingsBackup(settingsName)
    if not utils:strContainsAny(settingsName, backupPrefix) then settingsName = backupPrefix .. settingsName end
    local settingsToDelete = getSettingsByName(settingsName)
    if settingsToDelete then settingsToDelete:deleteFiles() end
end

local function revertToSettingsBackup(settings)
    if not settings then error("MLOS no settings to revert") end

    local targetName = settings:getName()
    local backupName = targetName
    if not utils:strContainsAny(backupName, backupPrefix) then backupName = backupPrefix .. backupName end

    local backupSettings = getSettingsByName(backupName)
    if backupSettings then
        settings:deleteFiles()
        backupSettings:rename(targetName)
    end
end

local function overrideOnButtonCancel(self, ...)
    local origFunc = self.onButtonCancel
    local override = function(self, ...)
        revertToSettingsBackup(self.settings)
        origFunc(self)
    end
    self.buttonCancel:setOnClick(override, self)
end

local function overrideOnButtonSave(self, ...)
    local origFunc = self.onButtonSave
    local override = function(self, ...)
        deleteSettingsBackup(self.settings:getName())
        origFunc(self)
    end
    self.buttonAccept:setOnClick(override, self)
end

local function newPageEditOnPanelChange(self)
    local labelWidth = 0
    self.currentPanel:setWidth(self.width - self.listbox:getRight() - UI_BORDER_SPACING * 2 - 1)
    local panelWidth = self.currentPanel.width
    local name

    if self.currentPanel.settingNames then
        for i = 1, #self.currentPanel.settingNames do
            name = self.currentPanel.settingNames[i]
            labelWidth = math.max(labelWidth,
                self.currentPanel.labels[name].width + self.currentPanel.controls[name].width + UI_BORDER_SPACING)
        end
        labelWidth = labelWidth + UI_BORDER_SPACING * 2

        local labelLeft = math.max(UI_BORDER_SPACING, (panelWidth - labelWidth) * 0.5)
        local controlLeft = math.min(panelWidth - UI_BORDER_SPACING, labelWidth + (panelWidth - labelWidth) * 0.5)

        for i = 1, #self.currentPanel.settingNames do
            name = self.currentPanel.settingNames[i]
            self.currentPanel.labels[name]:setX(labelLeft)
            self.currentPanel.controls[name]:setX(controlLeft - UI_BORDER_SPACING -
            self.currentPanel.controls[name].width)
            self.currentPanel.controls[name]:bringToTop()
        end

        for i = 1, #self.currentPanel.titles do
            self.currentPanel.titles[i]:setX((panelWidth - self.currentPanel.titles[i].width) / 2)
        end
    end

    for _, panel in ipairs(self.customui) do
        panel:onResolutionChange()
    end
end

local function fixLayout()
    local instance = ServerSettingsScreen.instance

    -- Fix server page layout if there are no mods that perform the same function.
    local skipIfModExists = { "\\ClientModsToServer" }
    local activeMods = getActivatedMods()
    for _, modId in ipairs(skipIfModExists) do if activeMods:contains(modId) then return end end

    -- fix window size
    local core = getCore()
    local curW = core:getScreenWidth()
    local curH = core:getScreenHeight()
    local perc = curW / curH
    local targetH = curH * 0.78
    local targetW = targetH * perc

    instance:setX((curW - targetW) * 0.5)
    instance:setY((curH - targetH) * 0.5)
    instance:setWidth(targetW)
    instance:setHeight(targetH)
    instance:recalcSize()
    instance:onResolutionChange()

    -- resize chooseModsWindow
    local chooseModsWindow = instance.pageEdit.chooseModsWindow
    local lsitboxW = targetW * 0.5
    chooseModsWindow.listbox:setWidth(lsitboxW)
    chooseModsWindow.listbox:setHeight(targetH - FONT_HGT_LARGE - UI_BORDER_SPACING * 4 - BUTTON_HGT - 2)
    chooseModsWindow.listbox:setX(targetW * 0.5 - lsitboxW * 0.5)
    chooseModsWindow.buttonAccept:setX(targetW - UI_BORDER_SPACING - 1 - chooseModsWindow.buttonAccept:getWidth())
    chooseModsWindow.buttonMods:setX(targetW * 0.5 - chooseModsWindow.buttonMods:getWidth() * 0.5)
    chooseModsWindow.fromClientBtn:setX(chooseModsWindow.buttonMods:getRight() + UI_BORDER_SPACING)

    -- fix panels
    for _, panel in ipairs(instance.pageEdit.customui) do
        if panel.Type == "ServerSettingsScreenModsPanel" then
            if panel.button then
                panel.button:setVisible(false)
            end
        end
    end
end

--================================================
--    ChooseModsWindow add fromClient Button
--================================================
-- local function getWorkshopId(modInfo)
--     if modInfo == nil then return nil end
--     local workshopId = modInfo:getWorkshopID()
--     if not workshopId or workshopId == "" then
--         local dir = modInfo:getDir()
--         return dir:match("108600\\(%d+)\\")
--     end
-- end

local function updateServerActiveMods(mods, settingsName)
    local activeMods = ActiveMods.getById("serversettings")
    local modArray = activeMods:getMods()
    modArray:clear()
    for _, item in ipairs(mods) do
        modArray:add(item.item.modID)
    end

    if ActiveMods.requiresResetLua(activeMods) then
        local reason = "ServerSettingsChange=" .. settingsName
        getCore():ResetLua("serversettings", reason)
        return true
    else
        return false
    end
end

local function newChooseModsWindowOnNextButton(self, ...)
    -- local modIDs = {}
    -- local workshopIDs = {}
    -- for _, item in ipairs(self.listbox.items) do
    --     local workshopId = getWorkshopId(item.item.modInfo)
    --     if workshopId and workshopId ~= "" then
    --         table.insert(modIDs, item.item.modID)
    --         utils:MergeTablesDedup(workshopIDs, {workshopId})
    --     else
    --         pcall(function(modId) error("\n[MLOS] Mod " .. modId .. " not found. Subscribe to the missing mod or save changes to the server configuration (missing mods will be removed from the mod list).") end, item.item.modID)
    --     end
    -- end
    local modIDs, workshopIDs = utils:getModsIDs(self.listbox.items)
    createSettingsBackup(self.settings)
    self.settings:getServerOptions():getOptionByName("Mods"):setValue(table.concat(modIDs, ";"))
    self.settings:getServerOptions():getOptionByName("WorkshopItems"):setValue(table.concat(workshopIDs, ";"))
    self.settings:saveFiles()

    self:setVisible(false)
    if not updateServerActiveMods(self.listbox.items, self.settings:getName()) then
        self.parent.pageEdit.settings = self.settings
        self.parent.pageEdit:aboutToShow()
        self.parent.pageEdit:setVisible(true, self.joyfocus)
    end
end

--================================================
--    Apply ServerSettingsScreen Overrides
--================================================

local function applyOverrides()
    local pageEdit = ServerSettingsScreen.instance.pageEdit
    overrideOnButtonCancel(pageEdit)
    overrideOnButtonSave(pageEdit)
    pageEdit.onPanelChange = function(self, ...) newPageEditOnPanelChange(self) end

    local chooseModsWindow = pageEdit.chooseModsWindow
    addPageEditFromClientButton(chooseModsWindow)
    chooseModsWindow.buttonAccept:setOnClick(newChooseModsWindowOnNextButton, chooseModsWindow)
    fixLayout()
end

Events.OnResolutionChange.Add(fixLayout)
Events.OnMainMenuEnter.Add(applyOverrides)
