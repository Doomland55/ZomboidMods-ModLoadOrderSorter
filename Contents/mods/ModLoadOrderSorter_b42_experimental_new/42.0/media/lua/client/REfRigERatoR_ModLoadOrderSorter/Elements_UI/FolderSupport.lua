-- Optional view-only folders for an ISScrollingListBox. Membership is keyed by
-- the caller's stable item key, not by visible row number. It survives clear /
-- repopulation (e.g. filtering) for the lifetime of the list. Use a stable,
-- unique getKey(item, text) when attaching; call beginUpdate/endUpdate around
-- batches. Folder headers are view rows, so do not attach to a model list that
-- writes its displayed items back as load order. Folders are session-only.
require "ISUI/ISPanelJoypad"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "REfRigERatoR_ModLoadOrderSorter/Elements_UI/ContextMenu"

local FolderSupport = {}
local Controller = {}
Controller.__index = Controller

local function keyFor(controller, row)
    return controller.getKey(row.item, row.text) or row.item or row.text or row
end

local function resetSearch(list)
    if list.foundItems then
        list.foundItems = {}; list.foundIndex = 0; list.foundCounter = 0
    end
end

function Controller:rebuild()
    if self.updateDepth > 0 then
        self.dirty = true; return
    end
    local list = self.list
    local selectedKeys = {}
    if list.selected_map then
        for index, selected in pairs(list.selected_map) do
            local row = list.items[index]
            if selected and row and not row.MLOS_folder then selectedKeys[keyFor(self, row)] = true end
        end
    else
        local row = list.items[list.selected or -1]
        if row and not row.MLOS_folder then selectedKeys[keyFor(self, row)] = true end
    end

    local grouped, loose = {}, {}
    for _, folder in ipairs(self.folders) do grouped[folder.id] = {} end
    for _, row in ipairs(self.entries) do
        local group = grouped[self.membership[keyFor(self, row)]]
        if group then group[#group + 1] = row else loose[#loose + 1] = row end
    end

    local visible = {}
    for _, folder in ipairs(self.folders) do
        local rows = grouped[folder.id]
        visible[#visible + 1] = {
            MLOS_folder = folder,
            text = folder.name,
            item = { name = folder.name, modId = folder.name },
            height = list.itemheight
        }
        if folder.expanded then
            for _, row in ipairs(rows) do visible[#visible + 1] = row end
        end
    end
    for _, row in ipairs(loose) do visible[#visible + 1] = row end

    list.items = visible
    list.selected = -1
    if list.selected_map then
        list.selected_map = {}; list.selected_flat = nil
    end
    for i, row in ipairs(visible) do
        row.index = i
        row.itemindex = i
        if not row.MLOS_folder and selectedKeys[keyFor(self, row)] then
            if list.selected < 0 then list.selected = i end
            if list.selected_map then list.selected_map[i] = true end
        end
    end
    list.mouseoverselected = -1
    self.dirty = false
    resetSearch(list)
end

function Controller:beginUpdate()
    self.updateDepth = self.updateDepth + 1
end

function Controller:endUpdate()
    if self.updateDepth > 0 then self.updateDepth = self.updateDepth - 1 end
    if self.updateDepth == 0 and self.dirty then self:rebuild() end
end

local function cleanName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    return name ~= "" and name or nil
end

function Controller:findFolder(id)
    for _, folder in ipairs(self.folders) do if folder.id == id then return folder end end
end

function Controller:renameFolder(id, name)
    local folder = self:findFolder(id)
    name = cleanName(name)
    if not folder or not name then return false end
    for _, other in ipairs(self.folders) do
        if other ~= folder and other.name:lower() == name:lower() then return false end
    end
    folder.name = name
    self:rebuild()
    return true
end

function Controller:createFolder(name)
    name = cleanName(name)
    if not name then return nil end
    for _, folder in ipairs(self.folders) do
        if folder.name:lower() == name:lower() then return nil end
    end
    self.nextId = self.nextId + 1
    local folder = { id = self.nextId, name = name, expanded = true }
    self.folders[#self.folders + 1] = folder
    self:rebuild()
    return folder
end

function Controller:removeFolder(id)
    for i, folder in ipairs(self.folders) do
        if folder.id == id then
            table.remove(self.folders, i)
            for key, folderId in pairs(self.membership) do
                if folderId == id then self.membership[key] = nil end
            end
            self:rebuild()
            return true
        end
    end
    return false
end

-- Keys must identify individual list items uniquely. A nil folder moves items out.
function Controller:moveItems(keys, folderId)
    if folderId ~= nil and not self:findFolder(folderId) then return false end
    for _, key in ipairs(keys) do self.membership[key] = folderId end
    self:rebuild()
    return true
end

function Controller:setExpanded(id, expanded)
    local folder = self:findFolder(id)
    if not folder then return false end
    folder.expanded = expanded == true
    self:rebuild()
    return true
end

-- Search must be able to find items hidden inside collapsed folders.
function Controller:revealMatches(word)
    local changed = false
    for _, row in ipairs(self.entries) do
        local item = type(row.item) == "table" and row.item or {}
        local name = tostring(item.name or row.text or ""):lower()
        local id = tostring(item.modId or ""):lower()
        if name:find(word, 1, true) or id:find(word, 1, true) then
            local folder = self:findFolder(self.membership[keyFor(self, row)])
            if folder and not folder.expanded then
                folder.expanded = true; changed = true
            end
        end
    end
    if changed then self:rebuild() end
end

-- Prompt for a folder name without depending on ISModalDialog internals.
local function askName(title, initial, accept)
    local width, height = 340, 125
    local panel = ISPanelJoypad:new((getCore():getScreenWidth() - width) / 2,
        (getCore():getScreenHeight() - height) / 2, width, height)
    panel:initialise(); panel:instantiate()
    panel.backgroundColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.98 }
    panel.borderColor = { r = 0.6, g = 0.6, b = 0.6, a = 1 }
    local originalPrerender = panel.prerender
    panel.prerender = function(self)
        if originalPrerender then originalPrerender(self) end
        self:drawText(title, 10, 10, 1, 1, 1, 1, UIFont.Small)
        if self.invalid then self:drawText(getText("UI_MLOS_FolderInvalid"), 10, 65, 1, 0.3, 0.3, 1, UIFont.Small) end
    end
    local entry = ISTextEntryBox:new(initial or "", 10, 33, width - 20, 25)
    entry:initialise(); entry:instantiate(); panel:addChild(entry)
    local function close()
        panel:setVisible(false); panel:removeFromUIManager()
    end
    local ok = ISButton:new(width - 160, 90, 70, 25, getText("UI_MLOS_FolderOK"), panel, function(self)
        if accept(entry:getInternalText()) then close() else self.invalid = true end
    end)
    ok:initialise(); ok:instantiate(); panel:addChild(ok)
    local cancel = ISButton:new(width - 80, 90, 70, 25, getText("UI_MLOS_FolderCancel"), panel, close)
    cancel:initialise(); cancel:instantiate(); panel:addChild(cancel)
    panel:setAlwaysOnTop(true); panel:addToUIManager(); panel:bringToTop(); entry:focus()
end

local function selectedKeys(controller, rowIndex)
    local list = controller.list
    local selected = list.selected_map
    if not selected or not selected[rowIndex] then selected = { [rowIndex] = true } end
    local keys = {}
    for index, value in pairs(selected) do
        local row = value and list.items[index]
        if row and not row.MLOS_folder then keys[#keys + 1] = keyFor(controller, row) end
    end
    return keys
end

local function showMenu(controller, x, y, rowIndex)
    local list = controller.list
    local row = list.items[rowIndex]
    if not row then return end
    if list.MLOS_activeContextMenu and list.MLOS_activeContextMenu:isReallyVisible() then
        list.MLOS_activeContextMenu:close()
    end
    local menu = MLOS_ContextMenu:new(list:getAbsoluteX() + x, list:getAbsoluteY() + y)
    list.MLOS_activeContextMenu = menu
    if row.MLOS_folder then
        local folder = row.MLOS_folder
        menu:addOption(getText("UI_MLOS_FolderRename"), nil, controller, function(self)
            askName(getText("UI_MLOS_FolderName"), folder.name,
                function(name) return self:renameFolder(folder.id, name) end)
        end)
        menu:addOption(getText("UI_MLOS_FolderDelete"), nil, controller, function(self) self:removeFolder(folder.id) end)
    else
        local keys = selectedKeys(controller, rowIndex)
        menu:addOption(getText("UI_MLOS_FolderCreate"), nil, controller, function(self)
            askName(getText("UI_MLOS_FolderName"), "", function(name)
                local folder = self:createFolder(name)
                if not folder then return false end
                self:moveItems(keys, folder.id)
                return true
            end)
        end)
        for _, folder in ipairs(controller.folders) do
            local folderId = folder.id
            menu:addOption(getText("UI_MLOS_FolderMove") .. ": " .. folder.name, nil, controller,
                function(self) self:moveItems(keys, folderId) end)
        end
        menu:addOption(getText("UI_MLOS_FolderRemoveItems"), nil, controller,
            function(self) self:moveItems(keys, nil) end)
    end
    menu:display()
end

function FolderSupport.attach(list, options)
    if not list or not list.items then return nil end
    if list.MLOS_folders then return list.MLOS_folders end
    options = options or {}
    local controller = setmetatable({
        list = list,
        folders = {},
        membership = {},
        entries = {},
        nextId = 0,
        updateDepth = 0,
        getKey = options.getKey or function(item, text)
            if type(item) == "table" then return item.modId or item.name or text or item end
            return text or item
        end
    }, Controller)
    for _, row in ipairs(list.items) do controller.entries[#controller.entries + 1] = row end
    list.MLOS_folders = controller

    local originalAdd, originalClear = list.addItem, list.clear
    list.addItem = function(self, text, item, tooltip)
        originalAdd(self, text, item, tooltip)
        local row = table.remove(self.items)
        controller.entries[#controller.entries + 1] = row
        controller:rebuild()
        return row
    end
    list.clear = function(self)
        originalClear(self)
        controller.entries = {}
        controller:rebuild()
    end

    local originalDraw = list.doDrawItem
    list.doDrawItem = function(self, y, row, alt)
        if row.MLOS_folder then
            local folder = row.MLOS_folder
            self:drawRect(0, y, self:getWidth(), row.height, 0.4, 0.25, 0.25, 0.25)
            self:drawText((folder.expanded and "v " or "> ") .. folder.name, 4, y + 3, 1, 0.85, 0.4, 1, UIFont.Small)
            return y + row.height
        end
        if originalDraw then return originalDraw(self, y, row, alt) end
        return y + row.height
    end
    local originalDown, originalUp = list.onMouseDown, list.onMouseUp
    list.onMouseDown = function(self, x, y)
        local row = self.items[self:rowAt(x, y)]
        if row and row.MLOS_folder then
            self.MLOS_folderClick = true
            controller:setExpanded(row.MLOS_folder.id, not row.MLOS_folder.expanded)
            return true
        end
        self.MLOS_folderClick = false
        if originalDown then return originalDown(self, x, y) end
    end
    list.onMouseUp = function(self, x, y)
        if self.MLOS_folderClick then
            self.MLOS_folderClick = false; return true
        end
        if originalUp then return originalUp(self, x, y) end
    end
    if options.contextMenu ~= false then
        list.onRightMouseUp = function(self, x, y)
            local index = self:rowAt(x, y)
            if index and self.items[index] then
                showMenu(controller, x, y, index); return true
            end
        end
    end
    controller:rebuild()
    return controller
end

return FolderSupport
