require "ISUI/ISPanelJoypad"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
local root = 'REfRigERatoR_ModLoadOrderSorter/'
local core = require(root .. 'Core/Core')
local utils = require(root .. 'Core/1_Utils')
local sorter = require(root .. 'Core/2_SortingCore')
local scroll = require(root .. 'Elements_UI/ScrollExtensions')
local popup = require(root .. 'Elements_UI/WarningPopup')

local Editor = ISPanelJoypad:derive('MLOS_SortingRulesEditor')
local colors = { red = {1, .2, .2}, purple = {.75, .3, 1}, yellow = {1, .75, .2} }

function Editor:new(x, y, width, height, owner)
    local o = ISPanelJoypad:new(x, y, width, height)
    setmetatable(o, self); self.__index = self
    o.owner = owner
    o.rules = core.layers.sortingRules
    o.working = o.rules:beginEdit()
    o.order = {}
    for _, item in ipairs(owner.modList.items) do table.insert(o.order, item) end
    o.backgroundColor = {r=0, g=0, b=0, a=.95}
    return o
end

local function button(self, x, y, w, text, action)
    local b = ISButton:new(x, y, w, 25, text, self, action)
    b:initialise(); b:instantiate(); self:addChild(b)
    return b
end
local function list(self, x, y, w, h, click, navigation)
    local l = ISScrollingListBox:new(x, y, w, h)
    l:initialise(); l:instantiate(); l.itemheight = 24
    l.doDrawItem = function(box, yy, row)
        local c = row.item.color or {1, 1, 1}
        if box.selected == row.index then box:drawRect(0, yy, box.width, row.height, .3, .6, .6, .6) end
        box:drawText(row.text, 5, yy + 3, c[1], c[2], c[3], 1, UIFont.Small)
        return yy + row.height
    end
    l.onMouseDown = function(box, xx, yy)
        ISScrollingListBox.onMouseDown(box, xx, yy)
        local row = box.items[box.selected]
        if row then click(self, row.item.modId) end
    end
    if navigation then
        -- Do not change the right-hand selection or navigate while a rule is edited.
        for _, method in ipairs({'onMouseDown', 'onMouseUp', 'onRightMouseDown', 'onRightMouseUp'}) do
            local original = l[method]
            if original then
                l[method] = function(box, xx, yy)
                    if self.mode then return true end
                    return original(box, xx, yy)
                end
            end
        end
    end
    self:addChild(l); return l
end
local function combo(self, x, y, w, values, field)
    local c
    c = ISComboBox:new(x, y, w, 25, self, function(owner)
        if owner.refreshing or not owner.selectedId then return end
        local value = values[c.selected]
        local rule = owner.working[owner.selectedId] or {}
        owner.working[owner.selectedId] = rule
        if field == 'category' then rule.category = value ~= 'automatic' and value or nil
        else owner.rules:setPosition(owner.selectedId, field, value) end
        owner:refresh()
    end)
    c:initialise(); c:instantiate()
    for _, value in ipairs(values) do c:addOption(value) end
    self:addChild(c); return c
end

function Editor:createChildren()
    ISPanelJoypad.createChildren(self)
    local w = math.floor((self.width - 40) / 3)
    local x1, x2, x3 = 10, 20 + w, 30 + 2*w
    local top, bottom = 65, self.height - 50
    self.mods = list(self, x1, top, w, bottom-top, self.selectMod)
    scroll:addSearchEntry(self.mods, -50)
    self.modeButtons = {}
    for i, mode in ipairs({'loadAfter', 'loadBefore', 'incompatibleMods'}) do
        local b = button(self, x2, top + (i-1)*30, w, mode, function(owner) owner:toggleMode(mode) end)
        self.modeButtons[#self.modeButtons+1] = b
    end
    self.applyButton = button(self, x2, top+100, w/2-3, 'Apply', self.applyMode)
    self.cancelButton = button(self, x2+w/2+3, top+100, w/2-3, 'Cancel', self.cancelMode)
    local cats = {'automatic'}
    for _, cat in ipairs(core.rawCategoryOrder) do table.insert(cats, cat) end
    self.category = combo(self, x2, top+155, w, cats, 'category'); self.categories = cats
    self.first = combo(self, x2, top+210, w, {'off','on','category'}, 'loadFirst')
    self.last = combo(self, x2, top+265, w, {'off','on','category'}, 'loadLast')
    local h = math.floor((bottom-top-60)/3)
    self.ruleList = list(self, x3, top+20, w, h, self.navigate, true)
    self.requiredList = list(self, x3, top+40+h, w, h, self.navigate, true)
    self.requiredByList = list(self, x3, top+60+2*h, w, h, self.navigate, true)
    button(self, x1, self.height-35, w, 'Exit without saving', self.discard)
    button(self, x2, self.height-35, w, 'Simulate', self.simulate)
    button(self, x3, self.height-35, w, 'Save and exit', self.save)
    self.warningPopup = popup:new(self.width-60, 5); self:addChild(self.warningPopup)
    self:refresh()
end
function Editor:prerender()
    ISPanelJoypad.prerender(self)
    local w = math.floor((self.width - 40) / 3)
    local x2, x3, top = 20+w, 30+2*w, 65
    self:drawText('Category', x2, top+135, 1,1,1,1,UIFont.Small)
    self:drawText('Load First', x2, top+190, 1,1,1,1,UIFont.Small)
    self:drawText('Load Last', x2, top+245, 1,1,1,1,UIFont.Small)
    local h = math.floor((self.height-50-top-60)/3)
    self:drawText(self.mode or 'Rule targets', x3, top, 1,1,1,1,UIFont.Small)
    self:drawText('Required', x3, top+20+h, 1,1,1,1,UIFont.Small)
    self:drawText('Required By', x3, top+40+2*h, 1,1,1,1,UIFont.Small)
end
function Editor:selectMod(id)
    if self.mode then
        if id == self.selectedId then return end
        local at = utils:indexOf(self.pending, id)
        if at then table.remove(self.pending, at) else table.insert(self.pending, id) end
    else self.selectedId = id end
    self:refresh()
end
function Editor:navigate(id)
    if self.mode then return end
    local found = false
    for _, row in ipairs(self.order) do if row.item.modId == id then found = true; break end end
    if not found then return end
    self.selectedId = id
    self:refresh()
    for i, row in ipairs(self.mods.items) do if row.item.modId == id then self.mods:ensureVisible(i); break end end
end
function Editor:toggleMode(mode)
    if not self.selectedId then return end
    if self.mode == mode then self:cancelMode(); return end
    self.mode = mode
    self.pending = utils:deepCopy((self.working[self.selectedId] or {})[mode] or {})
    self:refresh()
end
function Editor:cancelMode() self.mode = nil; self.pending = nil; self:refresh() end
function Editor:applyMode()
    if not self.mode then return end
    local rule = self.working[self.selectedId] or {}; self.working[self.selectedId] = rule
    rule[self.mode] = utils:deepCopy(self.pending)
    self:cancelMode()
end
function Editor:refresh()
    local status = sorter:validate(self.order, self.working)
    local info = core.layers.modInfo.data
    self.mods:clear()
    for _, row in ipairs(self.order) do
        local id = row.item.modId
        local c = colors[status[id]] or {1,1,1}
        if self.mode and id == self.selectedId then c = {.5,.5,.5}
        elseif self.mode and utils:contains(self.pending, id) then c = {.3,.85,1} end
        self.mods:addItem(row.item.name, {modId=id, name=row.item.name, color=c})
        self.mods.items[#self.mods.items].itemindex = #self.mods.items
        if id == self.selectedId then self.mods.selected = #self.mods.items end
    end
    local function fill(box, ids)
        box:clear()
        for _, id in ipairs(ids or {}) do
            box:addItem((info[id] and info[id].name) or id, {modId=id, name=(info[id] and info[id].name) or id})
        end
    end
    local data = info[self.selectedId] or {}
    fill(self.ruleList, self.pending)
    fill(self.requiredList, data.requirements)
    fill(self.requiredByList, data.requiredBy)
    local rule = self.working[self.selectedId] or {}
    self.refreshing = true
    self.category.selected = utils:indexOf(self.categories, rule.category or 'automatic') or 1
    self.first.selected = utils:indexOf({'off','on','category'}, rule.loadFirst or 'off') or 1
    self.last.selected = utils:indexOf({'off','on','category'}, rule.loadLast or 'off') or 1
    self.refreshing = false
    for _, b in ipairs(self.modeButtons) do b.enable = self.selectedId ~= nil end
    self.applyButton.enable = self.mode ~= nil; self.cancelButton.enable = self.mode ~= nil
    self.category.enable = self.selectedId ~= nil; self.first.enable = self.selectedId ~= nil; self.last.enable = self.selectedId ~= nil
    self.mods.foundItems = {}; self.mods.foundIndex = 0; self.mods.foundCounter = 0
end
function Editor:simulate()
    local ids = sorter:sort(self.order, self.working)
    local rows = {}; for _, row in ipairs(self.order) do rows[row.item.modId] = row end
    self.order = {}; for _, id in ipairs(ids) do table.insert(self.order, rows[id]) end
    for _, w in ipairs(sorter.warnings) do self.warningPopup:addMessage(w.title, w.message, w.layer, w.severity) end
    self:refresh()
end
function Editor:close()
    self:setVisible(false); self:removeFromUIManager()
    self.owner:setVisible(true)
end
function Editor:discard() self.rules:discardEdit(); self:close() end
function Editor:save()
    if not self.rules:commitEdit() then
        self.warningPopup:addError("Save failed", "Could not write sorting rules.", "SortingRules")
        return
    end
    core.layers.modInfo:getData(self.owner.modList.items, self.rules.data, false)
    if self.owner.MLOS_refresh then self.owner:MLOS_refresh() end
    self:close()
end
return Editor
