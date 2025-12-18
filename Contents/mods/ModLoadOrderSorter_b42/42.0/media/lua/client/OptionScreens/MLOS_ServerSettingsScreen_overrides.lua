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
require "OptionScreens/ServerSettingsScreen"
local utils = require('OptionScreens/ModSelector/Refr_utils')

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local UI_BORDER_SPACING = 10
local JOYPAD_TEX_SIZE = 32
local BUTTON_PADDING = JOYPAD_TEX_SIZE + UI_BORDER_SPACING*2



MLOS_ServerSettingsScreen_overrides = {}


function MLOS_ServerSettingsScreen_overrides.AddFromClientButton(chooseModsWindow)
    -- local btnWidth = BUTTON_PADDING + getTextManager():MeasureStringX(UIFont.Small, getText("UI_btn_back"))
    local btnWidth = BUTTON_PADDING + getTextManager():MeasureStringX(UIFont.Small, "Use client mods")
	
    chooseModsWindow.fromClientBtn = ISButton:new(chooseModsWindow.buttonMods:getRight() + UI_BORDER_SPACING , chooseModsWindow.buttonMods.y, btnWidth, BUTTON_HGT, "Use client mods", chooseModsWindow, MLOS_ServerSettingsScreen_overrides.OnFromClientButton)
	chooseModsWindow.fromClientBtn:getRight()
    chooseModsWindow.fromClientBtn:initialise()
	chooseModsWindow.fromClientBtn:setAnchorLeft(true)
	chooseModsWindow.fromClientBtn:setAnchorTop(false)
	chooseModsWindow.fromClientBtn:setAnchorBottom(true)
	chooseModsWindow.fromClientBtn.borderColor = {r=1, g=1, b=1, a=0.1}
	chooseModsWindow:addChild(chooseModsWindow.fromClientBtn)

    print("[MLOS] Called AddFromClientButton")
end

function MLOS_ServerSettingsScreen_overrides:OnFromClientButton()
    print("[MLOS] Pressed OnFromClientButton")
    self.listbox:clear()
    local currentClientMods = getActivatedMods()
    for i=1, currentClientMods:size() do
        self:addModToList(currentClientMods:get(i-1))
    end
end


function MLOS_ServerSettingsScreen_overrides.UpdatedOnNextButton(pageEdit)
    print("[MLOS] Called UpdatedOnNextButton")
    pageEdit.chooseModsWindow.buttonAccept:setTitle("puk")

    local origOnButtonNext = pageEdit.chooseModsWindow.onButtonNext
    if not origOnButtonNext then
        print("[MLOS] origOnButtonNext not found")
        return
    end

    local over = function(self)

        -- local cur = self.settings:getServerOptions():getOptionByName("WorkshopItems"):getValue()
        -- print("[MLOS] Curernt settings:", cur)

        local function getWorkshopIdFromDir(dir) return dir:match("108600\\(%d+)\\") end

        local finalData = {}
        for _, item in ipairs(self.listbox.items) do
            local dir = item.item.modInfo:getDir()
            local wsId = getWorkshopIdFromDir(dir)
            -- print("[MLOS] checking item: dir=", dir, " wsId=", wsId )

            if wsId and not utils:contains(finalData, wsId) then
                table.insert(finalData, wsId)
            else
                print("[MLOS] not found workshopId for", dir)
            end
        end

        self.settings:getServerOptions():getOptionByName("WorkshopItems"):setValue(table.concat(finalData, ";"))

        -- utils:tprint(finalData)
        -- local new = self.settings:getServerOptions():getOptionByName("WorkshopItems"):getValue()
        -- print("[MLOS] New settings:", new)
        
        -- self.settings:getServerOptions():getOptionByName("WorkshopItems"):setValue(table.concat(finalData, ";"))
        -- origOnButtonNext(self)

		-- for _, panel in ipairs(self.parent.pageEdit.customui) do
		-- 	if panel.Type == "ServerSettingsScreenWorkshopPanel" then
        --         -- panel:setSettings(self.settings)
        --         -- panel.listbox:clear()
        --         -- for _, wsId in ipairs(finalData) do
        --         --     panel:addItemToList(wsId)
        --         -- end

		-- 		break
		-- 	end
		-- end

        self:setVisible(false)

        local activeMods = ActiveMods.getById("serversettings")
        local modArray = activeMods:getMods()
        modArray:clear()
        for _, item in ipairs(self.listbox.items) do
            modArray:add(item.item.modID)
        end

        self.parent.pageEdit.settings = self.settings
        self.parent.pageEdit.settings:saveFiles()
        self.parent.pageEdit:aboutToShow()
        self.parent.pageEdit:setVisible(true, self.joyfocus)

        for _, panel in ipairs(self.parent.pageEdit.customui) do
            if panel.Type == "ServerSettingsScreenModsPanel" then
                panel.listbox:clear()
                for i = 0, modArray:size()-1 do
                    panel:addModToList(modArray:get(i))
                end
            end

            if panel.Type == "ServerSettingsScreenWorkshopPanel" then
                print("MLOS ServerSettingsScreenWorkshopPanel do: ", panel.settings:getServerOptions():getOptionByName("WorkshopItems"):getValue())
                utils:tprint(panel.listbox.items)
                panel.listbox:clear()
                for _, wsId in ipairs(finalData) do
                    panel:addItemToList(wsId)
                end
                utils:tprint(panel.listbox.items)
                print("MLOS ServerSettingsScreenWorkshopPanel posle: ", panel.settings:getServerOptions():getOptionByName("WorkshopItems"):getValue())
			end
        end

        local reason = "ServerSettingsChange" .. "=" .. self.settings:getName()
        if ActiveMods.requiresResetLua(activeMods) then
            getCore():ResetLua("serversettings", reason)
        end
        
    end

    pageEdit.chooseModsWindow.buttonAccept:setOnClick(over, pageEdit.chooseModsWindow)
end


local function applyOverrides()
    local pageEdit = ServerSettingsScreen.instance.pageEdit
    MLOS_ServerSettingsScreen_overrides.AddFromClientButton(pageEdit.chooseModsWindow)
    MLOS_ServerSettingsScreen_overrides.UpdatedOnNextButton(pageEdit)
end

Events.OnMainMenuEnter.Add(applyOverrides)

-- local origCreate = sss.create
-- local origOnButtonNext = ServerSettingsScreen.instance.pageEdit.chooseModsWindow.onButtonNext

--================================================
--      ServerSettingsScreen Overrides
--================================================
-- function sss:create()
--     origCreate(self)

--     print("ENTER IN ServerSettingsScreen.create OVERRIDES [MLOS]")

--     local choseModWindow = self.pageEdit.chooseModsWindow
--     local origOnButtonNext = choseModWindow.onButtonNext

--     local function newOnButtonNext(self)
--         origOnButtonNext(self)
--         -- origOnButtonNext(SSS.pageEdit.ChooseModsWindow)

--         local finalData = {}
--         for _, item in ipairs(self.listbox.items) do
--             table.insert(finalData, item.item.modInfo:getWorkshopID())
--         end
--         print("MLOS mods workshopIDs:",  table.concat(finalData, ";"))
--     end

--     choseModWindow.onButtonNext = newOnButtonNext
--     -- self.settings:getServerOptions():getOptionByName("SteamWorkshop"):setValue(table.concat(finalData, ";"))
-- end




-- local ss = ServerSettingsScreen.instance.pageEdit
-- local listWindow = ServerSettingsScreen and ServerSettingsScreen.pageEdit and ServerSettingsScreen.pageEdit.chooseModsWindow

-- if listWindow and listWindow.onButtonNext then
--     local original = listWindow.onButtonNext
--     print("MLOS")
--     listWindow.onButtonNext = function(self, ...)
--         local results = {original(self, ...)}
        
--         -- Ваш код после оригинальной функции
--         performCustomLogic(self, ...)
        
--         return unpack(results)
--     end
-- else
--     print("MLOS ListWindow или OnButtonClick не найдены")
-- end

-- function performCustomLogic(self, button, ...)
--     print("MLOS Выполняется пользовательская логика")
--     -- Ваш код здесь
-- end



-- local function patchOnButtonClick()
--     -- Пытаемся найти объект сразу
--     local listWindow = ServerSettingsScreen and ServerSettingsScreen.instance and ServerSettingsScreen.instance.pageEdit and ServerSettingsScreen.instance.pageEdit.chooseModsWindow
    
--     if listWindow and listWindow.onButtonNext then
--         -- Объект найден, патчим
--         local original = listWindow.onButtonNext
--         listWindow.onButtonNext = function(self, ...)
--             original(self, ...)
--             -- Ваш код
--             customButtonClickHandler(self, ...)
--         end
--         return true
--     end
    
--     return false
-- end

-- -- Пытаемся патч сразу
-- if not patchOnButtonClick() then
--     -- Если не получилось, ждем через таймер
--     local attempts = 0
--     local maxAttempts = 50 -- 5 секунд при проверке каждые 100ms
    
--     local timerId = Timer.SetInterval(function()
--         attempts = attempts + 1
--         if patchOnButtonClick() or attempts >= maxAttempts then
--             Timer.Kill(timerId)
--         end
--     end, 100)
-- end

-- function customButtonClickHandler(self, ...)
--     print("MLOS OnButtonClick:")
--     -- Ваша логика
-- end
