--- Sorting rule editor: transactional draft, grouped relationships and preview.
require 'ISUI/ISPanelJoypad'
require 'ISUI/ISScrollingListBox'
require 'ISUI/ISButton'
require 'ISUI/ISComboBox'
require 'ISUI/ISModalDialog'
local core = require('REfRigERatoR_ModLoadOrderSorter/Core/Core')
local sorter = require('REfRigERatoR_ModLoadOrderSorter/Core/SortingCore')
local scroll = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/ScrollExtensions')
local Model = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/RulesEditorModel')
local Editor = ISPanelJoypad:derive('MLOS_RulesEditor')
local pad = 10
local bh = math.max(25, getTextManager():getFontHeight(UIFont.Small) + 6)
local keys = { 'loadAfter', 'loadBefore', 'incompatibleMods', 'requirements', 'requiredBy' }
local labels = { loadAfter='UI_MLOS_RE_After', loadBefore='UI_MLOS_RE_Before',
    incompatibleMods='UI_MLOS_RE_Incompatible', requirements='UI_MLOS_RE_Requires', requiredBy='UI_MLOS_RE_RequiredBy' }
local badges = { loadAfter='A', loadBefore='B', incompatibleMods='I', requirements='R', requiredBy='D' }
local colors = { loadAfter={r=.2,g=.4,b=.9}, loadBefore={r=.2,g=.7,b=.3},
    incompatibleMods={r=.65,g=.25,b=.85}, requirements={r=.85,g=.55,b=.1}, requiredBy={r=.5,g=.5,b=.5} }
local function tr(key) return getText('UI_MLOS_RE_' .. key) end

local function button(parent, x, y, w, text, handler)
    local b = ISButton:new(x, y, w, bh, text, parent, handler)
    b:initialise(); b:instantiate(); parent:addChild(b)
    return b
end
local function list(parent, x, y, w, h, draw)
    local l = scroll.createList(parent, x, y, w, h)
    l.itemheight = bh; l.font = UIFont.Small; l.doDrawItem = draw
    return l
end
local function drawRow(self, y, row)
    local data = row.item
    local color = data.color
    if color then self:drawRect(0, y, self.width, row.height - 1, .32, color.r, color.g, color.b) end
    if self.selected == row.index then self:drawRect(0, y, self.width, row.height - 1, .32, .7, .7, .7) end
    self:drawText(row.text or '', 4, y + 3, 1, 1, 1, 1, UIFont.Small)
    return y + row.height
end

function Editor:new(x, y, width, height, owner)
    local o = ISPanelJoypad:new(x, y, width, height)
    setmetatable(o, self); self.__index = self
    o.owner = owner
    o.model = Model.new(core.layers.SortingRules:beginEdit())
    o.byId, o.collapsed, o.highlight = {}, {}, {}
    o.view = 'rules'
    o.backgroundColor = { r=0, g=0, b=0, a=.95 }
    return o
end

function Editor:instantiate()
    ISPanelJoypad.instantiate(self)
    self:fillMods()
    self:refresh()
end

function Editor:fillMods()
    self.mods:clear(); self.byId = {}
    for _, row in ipairs(self.owner.modList.items) do
        local item = row.item
        if item and item.modId then
            self.byId[item.modId] = item
            self.mods:addItem(item.name or item.modId, { modId=item.modId, name=item.name or item.modId })
        end
    end
    if #self.mods.items > 0 then self.mods.selected = 1; self.selectedId = self.mods.items[1].item.modId end
end

function Editor:info(id)
    local layer = core.layers.ModsInfo
    return layer and layer.data and layer.data[id] or {}
end
function Editor:name(id)
    local item = self.byId[id]
    return item and (item.name or id) or id
end

function Editor:updateControls()
    local id = self.selectedId
    local rule = self.model.draft[id] or {}
    self.updating = true
    local function selectValue(combo, value)
        for i = 1, #combo.options do
            if combo:getOptionData(i) == value then combo.selected = i; return end
        end
        combo.selected = 1
    end
    selectValue(self.first, rule.loadFirst or 'off')
    selectValue(self.last, rule.loadLast or 'off')
    selectValue(self.category, rule.category or 'automatic')
    self.updating = false
    self.first.disabled = not id; self.last.disabled = not id; self.category.disabled = not id
    for _, b in ipairs(self.addButtons) do b.enable = id ~= nil end
    self.removeBtn.enable = false
    self.applyBtn.enable = self.model:dirty()
end

function Editor:refreshMods()
    for _, row in ipairs(self.mods.items) do
        local id = row.item.modId
        local rule = self.model.draft[id]
        local marker = self.model:dirty(id) and '* ' or (rule and '+ ' or '')
        local relation = self.highlight[id]
        row.text = marker .. (relation and ('[' .. relation.badges .. '] ') or '') .. self:name(id)
        row.item.color = relation and relation.color or nil
        row.tooltip = id
    end
end

function Editor:refreshRules()
    local id = self.selectedId
    self.details:clear(); self.highlight = {}
    if not id then self:refreshMods(); return end
    local groups = self.model:groups(id, self:info(id))
    for _, key in ipairs(keys) do
        local entries = groups[key]
        local collapsed = self.collapsed[key]
        self.details:addItem((collapsed and '[+] ' or '[-] ') .. getText(labels[key]) .. ' (' .. #entries .. ')',
            { kind='group', key=key, color=colors[key] })
        for _, entry in ipairs(entries) do
            -- Multiple relationships remain visible as text in the group list;
            -- the left list shows the first highlight only.
            local highlight = self.highlight[entry.id]
            if not highlight then
                highlight = { color=colors[key], badges='' }; self.highlight[entry.id] = highlight
            end
            highlight.badges = highlight.badges .. badges[key]
            if not collapsed then
                local source = entry.user and (entry.metadata and tr('Both') or tr('User')) or tr('Info')
                local missing = not self.byId[entry.id] and (' ' .. tr('Missing')) or ''
                local text = '    ' .. self:name(entry.id) .. ' [' .. source .. ']' .. missing
                self.details:addItem(text, { kind='relationship', key=key, id=entry.id, user=entry.user, color=colors[key] }, entry.id)
            end
        end
    end
    self:refreshMods()
end

function Editor:refreshFiles()
    self.details:clear()
    local layer = core.layers.ModsFiles
    local data = layer and layer.data and layer.data[self.selectedId]
    if not data then self.details:addItem(tr('NoFiles'), {kind='message'}); return end
    self.details:addItem(data.complete and tr('FilesComplete') or tr('FilesPartial'), {kind='message'})
    for _, path in ipairs(data.files or {}) do self.details:addItem(path, {kind='file'}, path) end
end

function Editor:refreshPreview()
    self.details:clear()
    if not self.preview then self.details:addItem(tr('PreviewEmpty'), {kind='message'}); return end
    if self.previewStale then self.details:addItem(tr('PreviewStale'), {kind='message'}) end
    for _, warning in ipairs(self.preview.warnings) do
        self.details:addItem('! ' .. tostring(warning.title) .. ': ' .. tostring(warning.message), {kind='message'}, tostring(warning.message))
    end
    for i, id in ipairs(self.preview.ids) do
        self.details:addItem(i .. '. ' .. self:name(id) .. ' (' .. id .. ')', {kind='preview', id=id}, id)
    end
end

function Editor:refresh()
    self:updateControls()
    if self.view == 'files' then self:refreshFiles()
    elseif self.view == 'preview' then self:refreshPreview()
    else self:refreshRules() end
end

function Editor:changed()
    self.message = nil
    if self.preview then self.previewStale = true end
    self.view = 'rules'; self:refresh()
end
function Editor:onCombo(combo)
    if self.updating or not self.selectedId then return end
    local value = combo:getOptionData(combo.selected)
    if value == 'automatic' or value == 'off' then value = nil end
    self.model:set(self.selectedId, combo.internal, value)
    self:changed()
end
function Editor:beginAdd(button)
    if not self.selectedId then return end
    self.addKey = button.internal
    self.view = 'rules'; self:refresh()
end
function Editor:addTarget(key, target)
    if self.model:add(self.selectedId, key, target) then self:changed() end
end
function Editor:onModClick(list, x, y)
    ISScrollingListBox.onMouseDown(list, x, y)
    local row = list.items[list.mouseoverselected]
    if not row then return end
    if self.addKey then
        local id, key = row.item.modId, self.addKey
        self.addKey = nil
        self:addTarget(key, id)
        -- Keep the source selection, including after selecting itself.
        for i, entry in ipairs(list.items) do if entry.item.modId == self.selectedId then list.selected = i; break end end
    else
        self.selectedId = row.item.modId
        self.view = 'rules'; self:refresh()
    end
end
function Editor:onModRightClick(list, x, y)
    local row = list.items[list.mouseoverselected]
    if not row or not self.selectedId or row.item.modId == self.selectedId then return end
    local target = row.item.modId
    local menu = MLOS_ContextMenu:new(list:getAbsoluteX() + x, list:getAbsoluteY() + y)
    for _, key in ipairs({ 'loadAfter', 'loadBefore', 'incompatibleMods' }) do
        local relation = key
        menu:addOption(self:name(self.selectedId) .. ': ' .. getText(labels[key]) .. ' ' .. self:name(target), nil,
            self, function(editor) editor:addTarget(relation, target) end)
    end
    menu:display()
end
function Editor:onDetailsClick(list, x, y)
    ISScrollingListBox.onMouseDown(list, x, y)
    local row = list.items[list.mouseoverselected]
    self.removeBtn.enable = row and row.item.kind == 'relationship' and row.item.user == true or false
    if row and row.item.kind == 'group' then
        self.collapsed[row.item.key] = not self.collapsed[row.item.key]
        self:refreshRules()
    end
end
function Editor:removeSelected()
    local row = self.details.items[self.details.selected]
    if row and row.item.kind == 'relationship' and row.item.user then
        if self.model:remove(self.selectedId, row.item.key, row.item.id) then self:changed() end
    end
end
function Editor:save()
    local ok, err = self.model:commit()
    if not ok then
        self.message = tr('SaveError') .. ': ' .. tostring(err)
        return
    end
    self.message = tr('Saved')
    self:refresh()
end

-- Sorting currently updates effectiveCategory and singleton warning fields.
-- Restore these after preview so it has no effect on the active editor/game state.
function Editor:simulate()
    local infoLayer = core.layers.ModsInfo
    local info = infoLayer and infoLayer.data or {}
    local categories = {}
    for id, record in pairs(info) do categories[id] = { value = record.effectiveCategory } end
    local warnings, edges, broken = sorter.warnings, sorter.lastEdges, sorter.brokenEdges
    local ok, result = pcall(sorter.sort, sorter, self.owner.modList.items, self.model.draft)
    local previewWarnings = sorter.warnings
    for id, saved in pairs(categories) do if info[id] then info[id].effectiveCategory = saved.value end end
    sorter.warnings, sorter.lastEdges, sorter.brokenEdges = warnings, edges, broken
    if not ok then self.message = tr('PreviewError') .. ': ' .. tostring(result); return end
    self.preview = { ids=result, warnings=previewWarnings or {} }
    self.previewStale = false; self.view = 'preview'; self.addKey = nil; self:refresh()
end
function Editor:setView(button)
    self.addKey = nil; self.view = button.internal; self:refresh()
end
function Editor:cancelAdd() self.addKey = nil end
function Editor:close()
    self.addKey = nil
    if self.dialog then return end
    if not self.model:dirty() then self:discardAndClose(); return end
    local w, h = 300, 100
    local dialog = ISModalDialog:new((getCore():getScreenWidth()-w)/2, (getCore():getScreenHeight()-h)/2,
        w, h, getText('UI_MLOS_Editor_Discard'), true, self, function(editor, b)
            editor.dialog = nil
            if b.internal == 'YES' then editor:discardAndClose() end
        end)
    self.dialog = dialog; dialog:initialise(); dialog:addToUIManager(); dialog:setAlwaysOnTop(true)
end
function Editor:discardAndClose()
    self:setVisible(false); self.owner:setVisible(true); self:removeFromUIManager()
end
function Editor:prerender()
    ISPanelJoypad.prerender(self)
    self:drawTextCentre(tr('Title') .. (self.model:dirty() and ' *' or ''), self.width/2, pad, 1,1,1,1,UIFont.Medium)
    local name = self.selectedId and (self:name(self.selectedId) .. ' (' .. self.selectedId .. ')  |  ' .. tr('Detected') .. ': ' .. tostring(self:info(self.selectedId).category or 'undefined')) or tr('Select')
    self:drawText(tr('Legend'), pad, 40, .8,.8,.8,1,UIFont.Small)
    self:drawText(name, self.rightX, 40, 1,1,1,1,UIFont.Small)
    local hint = self.addKey and (tr('ChooseTarget') .. ': ' .. getText(labels[self.addKey])) or (self.message or '')
    self:drawText(hint, pad, self.height - bh - 30, 1,.8,.3,1,UIFont.Small)
end

function Editor:createChildren()
    local x, top = pad, 70
    local leftW = math.floor(self.width * .39) - pad
    self.rightX = leftW + pad * 2
    local rightW = self.width - self.rightX - pad
    local bottom = self.height - bh - 45
    self.mods = list(self, x, top, leftW, bottom - top, drawRow)
    scroll:addSearchEntry(self.mods, nil, false)
    self.mods.onMouseDown = function(l, a, b) self:onModClick(l, a, b) end
    self.mods.onRightMouseDown = function(l, a, b) self:onModRightClick(l, a, b); return true end
    local y = top
    local function combo(key, options)
        local c = ISComboBox:new(self.rightX, y, rightW, bh, self, self.onCombo)
        c.internal = key; c:initialise(); c:instantiate(); self:addChild(c)
        for _, option in ipairs(options) do c:addOptionWithData(option[1], option[2]) end
        y = y + bh + 4
        return c
    end
    local function priorities(label)
        return { {label .. ': ' .. tr('Off'),'off'}, {label .. ': ' .. tr('On'),'on'}, {label .. ': ' .. tr('CategoryOnly'),'category'} }
    end
    self.first = combo('loadFirst', priorities(tr('First')))
    self.last = combo('loadLast', priorities(tr('Last')))
    local cats = { {tr('AutoCategory'), 'automatic'} }
    for _, category in ipairs(core.rawCategoryOrder) do cats[#cats + 1] = {tr('Category') .. ': ' .. category, category} end
    self.category = combo('category', cats)
    local bw = (rightW - 2 * 4) / 3
    self.addButtons = {}
    for i, key in ipairs({ 'loadAfter', 'loadBefore', 'incompatibleMods' }) do
        local b = button(self, self.rightX + (i-1)*(bw+4), y, bw, '+ ' .. getText(labels[key]), self.beginAdd)
        b.internal = key; self.addButtons[#self.addButtons + 1] = b
    end
    y = y + bh + 4
    local viewW = (rightW - 3*4)/4
    for i, view in ipairs({ {'Rules','rules'}, {'Files','files'}, {'Preview','preview'} }) do
        local b = button(self, self.rightX + (i-1)*(viewW+4), y, viewW, tr(view[1]), self.setView); b.internal = view[2]
    end
    self.removeBtn = button(self, self.rightX + 3*(viewW+4), y, viewW, tr('Remove'), self.removeSelected)
    y = y + bh + 4
    self.details = list(self, self.rightX, y, rightW, math.max(bh, bottom-y), drawRow)
    self.details.onMouseDown = function(l, a, b) self:onDetailsClick(l, a, b) end
    local foot = self.height - bh - pad
    button(self, pad, foot, 100, tr('Close'), self.close)
    button(self, 115, foot, 100, tr('CancelAdd'), self.cancelAdd)
    button(self, self.width-220, foot, 100, tr('Simulate'), self.simulate)
    self.applyBtn = button(self, self.width-110, foot, 100, tr('Save'), self.save)
end
return Editor
