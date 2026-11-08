-- Run from the repository root with Lua 5.1: lua tests/editor_interaction.lua
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/'
package.path = base .. '?.lua;' .. package.path
local root = 'REfRigERatoR_ModLoadOrderSorter/'
local function noop() end

-- Minimal ISUI stand-ins to exercise event handlers rather than only navigate().
ISPanelJoypad = {}
function ISPanelJoypad:derive() local c = {}; setmetatable(c, {__index=self}); return c end
function ISPanelJoypad:new(x,y,w,h) return {x=x,y=y,width=w,height=h,children={}} end
function ISPanelJoypad:createChildren() end
function ISPanelJoypad:addChild(child) child.parent=self; self.children[#self.children+1]=child end
function ISPanelJoypad:setVisible(value) self.visible=value end
function ISPanelJoypad:removeFromUIManager() end

ISScrollingListBox = {}
function ISScrollingListBox:new(x,y,w,h)
    local o = {x=x,y=y,width=w,height=h,items={},selected=-1}
    return setmetatable(o, {__index=self})
end
ISScrollingListBox.initialise = noop; ISScrollingListBox.instantiate = noop
function ISScrollingListBox:clear() self.items={}; self.selected=-1 end
function ISScrollingListBox:addItem(text, item) self.items[#self.items+1]={text=text,item=item,index=#self.items+1,height=24} end
function ISScrollingListBox:ensureVisible(index) self.visibleIndex=index end
function ISScrollingListBox:onMouseDown(x,y) self.selected=x; self.downs=(self.downs or 0)+1 end
function ISScrollingListBox:onMouseUp() self.ups=(self.ups or 0)+1 end
function ISScrollingListBox:onRightMouseDown() self.rightDowns=(self.rightDowns or 0)+1 end
function ISScrollingListBox:onRightMouseUp() self.rightUps=(self.rightUps or 0)+1 end
ISButton = {}
function ISButton:new() return setmetatable({}, {__index={initialise=noop,instantiate=noop}}) end
ISComboBox = {}
function ISComboBox:new() return setmetatable({selected=1,options={}}, {__index={initialise=noop,instantiate=noop,addOption=function(self,v) self.options[#self.options+1]=v end}}) end
UIFont={Small=1}
getTextManager=function() return {getFontHeight=function() return 12 end} end

for _, name in ipairs({'ISUI/ISPanelJoypad','ISUI/ISScrollingListBox','ISUI/ISButton','ISUI/ISComboBox',
    'ISUI/ISProgressBar','ISUI/ISTickBox','ISUI/ISToolTip','OptionScreens/ModSelector/ModSelector'}) do
    package.preload[name]=function() return true end
end
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end
local utils={}
function utils:deepCopy(value) return copy(value) end
function utils:indexOf(t, value) for i,v in ipairs(t) do if v==value then return i end end end
function utils:contains(t, value) return self:indexOf(t,value) ~= nil end
function utils:tableIsEmpty(t) if not t then return true end; for _ in pairs(t) do return false end; return true end
local rules={data={A={loadAfter={}}}}
function rules:beginEdit() self.working=copy(self.data); return self.working end
function rules:setPosition(id, key, value) self.working[id][key]=value end
local core={rawCategoryOrder={'code','undefined'},layers={modInfo={data={
    A={name='A', requirements={'B'},requiredBy={'C'}},B={name='B'},C={name='C'}
}},modFiles={data={}},sortingRules=rules}}
local sorter={validate=function() return {} end}
local scroll={addSearchEntry=function(_, list) list.foundItems={}; list.foundIndex=0; list.foundCounter=0 end}
local popup={new=function() return {addMessage=noop,addError=noop} end}
package.loaded[root..'Core/1_Utils']=utils
package.loaded[root..'Core/Core']=core
package.loaded[root..'Core/2_SortingCore']=sorter
package.loaded[root..'Elements_UI/ScrollExtensions']=scroll
package.loaded[root..'Elements_UI/WarningPopup']=popup
-- Match PZ, where the global next iterator is unavailable.
_G.next=nil
local Editor=require(root..'Elements_UI/SortingRulesEditor')
local owner={modList={items={
    {item={modId='A',name='A'}},{item={modId='B',name='B'}},{item={modId='C',name='C'}}
}}}
local editor=Editor:new(0,0,900,600,owner)
editor:createChildren()
editor.mods.foundItems={2}; editor.mods.foundIndex=1; editor.mods.foundCounter=3
editor.mods:onMouseDown(1,0)
assert(editor.selectedId=='A' and #editor.mods.foundItems==0 and editor.mods.foundIndex==0 and editor.mods.foundCounter==0)
editor:toggleMode('loadAfter')
editor.mods:onMouseDown(2,0)
assert(editor.selectedId=='A' and editor.mode=='loadAfter' and editor.pending[1]=='B')
for _, list in ipairs({editor.ruleList,editor.requiredList,editor.requiredByList}) do
    assert(#list.items > 0)
    list.selected=-1
    list:onMouseDown(1,0); list:onMouseUp(1,0)
    list:onRightMouseDown(1,0); list:onRightMouseUp(1,0)
    assert(list.selected==-1 and not list.downs and not list.ups and not list.rightDowns and not list.rightUps)
    assert(editor.selectedId=='A' and editor.mode=='loadAfter' and #editor.pending==1 and editor.pending[1]=='B')
end
editor:navigate('C') -- callers other than the mouse must not discard the edit either
assert(editor.mode=='loadAfter' and editor.selectedId=='A' and editor.pending[1]=='B')
editor:applyMode()
assert(editor.mode==nil and editor.working.A.loadAfter[1]=='B')
editor.requiredList:onMouseDown(1,0); editor.requiredList:onMouseUp(1,0)
assert(editor.selectedId=='B' and editor.requiredList.ups==1)
editor:toggleMode('loadBefore'); editor.mods:onMouseDown(3,0); editor:cancelMode()
assert(editor.selectedId=='B' and editor.working.B == nil)
for _, mode in ipairs({'loadAfter', 'loadBefore', 'incompatibleMods'}) do
    editor:navigate('A')
    editor:toggleMode(mode)
    editor.mods:onMouseDown(3,0)
    local before = table.concat(editor.pending, ',')
    for _, list in ipairs({editor.ruleList, editor.requiredList, editor.requiredByList}) do
        local selected = list.selected
        list:onMouseDown(1,0); list:onMouseUp(1,0)
        assert(list.selected == selected and editor.selectedId == 'A' and editor.mode == mode)
        assert(table.concat(editor.pending, ',') == before)
    end
    editor:cancelMode()
end
print('editor interaction tests passed')

-- Inspector must handle both selection forms without the global iterator.
ModSelector={ModLoadOrderPanel={createChildren=noop,instantiate=noop}}
require(root..'ModSelector/MLOS_ModSelector_overrides')
local panel=setmetatable({modList={items=owner.modList.items,selected=1,selected_map={}},
    conflictFilter={isSelected=function() return false end},
    filesList={parent={},items={},clear=function(self) self.items={} end,
        addItem=function(self,text,item) self.items[#self.items+1]={text=text,item=item} end}},
    {__index=ModSelector.ModLoadOrderPanel})
core.layers.modFiles.data={A={files={'a.lua'}},B={files={'b.lua'}}}
panel:MLOS_refresh()
assert(#panel.filesList.items==1 and panel.filesList.items[1].text=='a.lua')
panel.modList.selected_map={[2]=true}
panel:MLOS_refresh()
assert(#panel.filesList.items==1 and panel.filesList.items[1].text=='b.lua')
print('inspector selection tests passed with next unavailable')
