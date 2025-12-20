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
local BUTTON_HGT = FONT_HGT_SMALL + 6
local UI_BORDER_SPACING = 10
local JOYPAD_TEX_SIZE = 32
local BUTTON_PADDING = JOYPAD_TEX_SIZE + UI_BORDER_SPACING*2


--================================================
--    ChooseModsWindow add fromClient Button
--================================================
local onFromClientButton = function(self, ...)
    self.listbox:clear()
    local currentClientMods = getActivatedMods()
    for i=1, currentClientMods:size() do
        self:addModToList(currentClientMods:get(i-1))
    end
end

local function addPageEditFromClientButton(self, ...)
    self.fromClientBtn = ISButton:new(self.buttonMods:getRight() + UI_BORDER_SPACING , self.buttonMods.y, BUTTON_HGT, BUTTON_HGT, "", self, onFromClientButton)
    self.fromClientBtn:setImage(rulesTexture)
    self.fromClientBtn:setTextureRGBA(1, 1, 1, 0.9)
    self.fromClientBtn:setTooltip("Use mods from client")
	self.fromClientBtn:getRight()
    self.fromClientBtn:initialise()
	self.fromClientBtn:setAnchorLeft(true)
	self.fromClientBtn:setAnchorTop(false)
	self.fromClientBtn:setAnchorBottom(true)
	self.fromClientBtn.borderColor = {r=1, g=1, b=1, a=0.1}
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
    for i=1,serverManager:getSettingsCount() do
		local settings = serverManager:getSettingsByIndex(i-1)
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

--================================================
--    ChooseModsWindow add fromClient Button
--================================================
local function getWorkshopId(modInfo)
    local workshopId = modInfo:getWorkshopID()
    if not workshopId or workshopId == "" then
        local dir = modInfo:getDir()
        return dir:match("108600\\(%d+)\\")
    end
end

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

local function newChooseModsOnNextButton(self, ...)
    local modIDs = {}
    local workshopIDs = {}
    for _, item in ipairs(self.listbox.items) do
        table.insert(modIDs, item.item.modID)
        local workshopId = getWorkshopId(item.item.modInfo)
        if workshopId and workshopId ~= "" and not utils:contains(workshopIDs, workshopId) then
            table.insert(workshopIDs, workshopId)
        else
            print("[MLOS] not found workshopId for", item.item.modInfo:getId())
        end
    end

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

    local chooseModsWindow = pageEdit.chooseModsWindow
    addPageEditFromClientButton(chooseModsWindow)
    chooseModsWindow.buttonAccept:setOnClick(newChooseModsOnNextButton, chooseModsWindow)
end

Events.OnMainMenuEnter.Add(applyOverrides)
