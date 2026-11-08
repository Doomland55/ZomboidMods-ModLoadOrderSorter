-- Run from the repository root with Lua 5.1: lua tests/folders_and_popup.lua
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/'
package.path = base .. '?.lua;' .. package.path
local root = 'REfRigERatoR_ModLoadOrderSorter/'
local function noop() end
for _, name in ipairs({'ISUI/ISPanelJoypad','ISUI/ISScrollingListBox','ISUI/ISButton',
    'ISUI/ISTextEntryBox','ISUI/ISToolTip','ISUI/ISLabel','ISUI/ISComboBox','ISUI/ISMouseDrag',
    root..'Elements_UI/ContextMenu'}) do package.preload[name]=function() return true end end
UIFont={Small=1,Medium=2,Large=3}
getText=function(key) return key end
getTextManager=function() return {getFontHeight=function() return 12 end,
    MeasureStringX=function(_,_,text) return #text * 5 end} end
getCore=function() return {getScreenWidth=function() return 1024 end,getScreenHeight=function() return 768 end} end
getTexture=function() return {} end
local utils={}
function utils:tableIsEmpty(t) if not t then return true end; for _ in pairs(t) do return false end; return true end
package.loaded[root..'Core/1_Utils']=utils
ISPanelJoypad={}
function ISPanelJoypad:derive() local cls={}; setmetatable(cls,{__index=self}); return cls end
function ISPanelJoypad:new(x,y,w,h)
    local obj={x=x,y=y,width=w,height=h,children={},visible=true}
    setmetatable(obj,{__index=self}); return obj
end
ISPanelJoypad.initialise=noop; ISPanelJoypad.instantiate=noop; ISPanelJoypad.prerender=noop
local lastPanel
ISPanelJoypad.setAlwaysOnTop=noop; ISPanelJoypad.addToUIManager=function(self) lastPanel=self end; ISPanelJoypad.removeFromUIManager=noop
ISPanelJoypad.bringToTop=noop; ISPanelJoypad.setWantKeyEvents=noop
function ISPanelJoypad:addChild(child) child.parent=self; self.children[#self.children+1]=child end
function ISPanelJoypad:setVisible(v) self.visible=v end
function ISPanelJoypad:getIsVisible() return self.visible end
function ISPanelJoypad:setX(v) self.x=v end; function ISPanelJoypad:setY(v) self.y=v end
function ISPanelJoypad:setWidth(v) self.width=v end; function ISPanelJoypad:setHeight(v) self.height=v end
function ISPanelJoypad:getWidth() return self.width end; function ISPanelJoypad:getHeight() return self.height end
function ISPanelJoypad:drawText(text) self.lastText=text end
ISPanelJoypad.drawRect=noop; ISPanelJoypad.drawRectBorder=noop; ISPanelJoypad.drawTextCentre=noop
ISPanelJoypad.onMouseUp=noop; ISPanelJoypad.onMouseDownOutside=noop

ISScrollingListBox={}
function ISScrollingListBox:new(x,y,w,h)
    local obj={x=x,y=y,width=w,height=h,items={},selected=-1,itemheight=24,mouseoverselected=-1}
    setmetatable(obj,{__index=self}); return obj
end
ISScrollingListBox.initialise=noop; ISScrollingListBox.instantiate=noop; ISScrollingListBox.onMouseUp=noop
function ISScrollingListBox:onMouseDown(x,y) self.selected=self:rowAt(x,y) end
function ISScrollingListBox:rowAt(x,y) return y end
function ISScrollingListBox:getAbsoluteX() return 0 end; function ISScrollingListBox:getAbsoluteY() return 0 end
function ISScrollingListBox:setVisible(v) self.visible=v end
function ISScrollingListBox:addItem(text,item,tooltip)
    local row={text=text,item=item,tooltip=tooltip,index=#self.items+1,itemindex=#self.items+1,height=self.itemheight}
    self.items[#self.items+1]=row; return row
end
function ISScrollingListBox:clear() self.items={}; self.selected=-1 end
function ISScrollingListBox:ensureVisible(index) self.ensured=index end
function ISScrollingListBox:doDrawItem(y,row) return y+row.height end
function ISScrollingListBox:getWidth() return self.width end
ISScrollingListBox.drawRect=noop; ISScrollingListBox.drawText=noop

ISButton={}
function ISButton:new(x,y,w,h,text,target,onclick)
    local obj={x=x,y=y,width=w,height=h,text=text,target=target,onclick=onclick}; setmetatable(obj,{__index=self}); return obj
end
ISButton.initialise=noop; ISButton.instantiate=noop; ISButton.setFont=noop; ISButton.setTooltip=noop
ISButton.ignoreWidthChange=noop; ISButton.ignoreHeightChange=noop; ISButton.setImage=noop; ISButton.setTextureRGBA=noop
function ISButton:getRight() return self.x+self.width end; function ISButton:getY() return self.y end
ISTextEntryBox={}
function ISTextEntryBox:new(text,x,y,w,h)
    local obj={text=text,x=x,y=y,width=w,height=h}; setmetatable(obj,{__index=self}); return obj
end
ISTextEntryBox.initialise=noop; ISTextEntryBox.instantiate=noop; ISTextEntryBox.setPlaceholderText=noop
ISTextEntryBox.setClearButton=noop; ISTextEntryBox.bringToTop=noop; ISTextEntryBox.focus=noop
function ISTextEntryBox:getInternalText() return self.text end
function ISTextEntryBox:getRight() return self.x+self.width end; function ISTextEntryBox:getY() return self.y end
local menu
MLOS_ContextMenu={}
function MLOS_ContextMenu:new() menu={options={}}; setmetatable(menu,{__index=self}); return menu end
function MLOS_ContextMenu:addOption(title,tooltip,target,action) self.options[#self.options+1]={title=title,target=target,action=action} end
MLOS_ContextMenu.display=noop
MLOS_ContextMenu.isReallyVisible=function() return false end
MLOS_ContextMenu.close=noop

-- Exercise the real search extension and folder callbacks together.
_G.next=nil
local scroll=require(root..'Elements_UI/ScrollExtensions')
local parent=ISPanelJoypad:new(0,0,500,500)
local list=ISScrollingListBox:new(0,0,400,300); parent:addChild(list)
list:addItem('Alpha.lua',{name='Alpha.lua',modId='a'},'alpha tooltip')
list:addItem('Beta.lua',{name='Beta.lua',modId='b'},'beta tooltip')
list:addItem('Other.lua',{name='Other.lua',modId='c'})
scroll:addSearchEntry(list,0)
local folders=scroll:addFoldersSupport(list)
local f=assert(folders:createFolder('First'))
assert(not folders:createFolder(' first '))
assert(folders:moveItems({'a','b'},f.id))
assert(#list.items==4 and list.items[1].MLOS_folder==f and list.items[2].item.modId=='a')
assert(list.items[2].tooltip=='alpha tooltip')
list.selected=3
list:onMouseDown(0,1); list:onMouseUp(0,1)
assert(not f.expanded and #list.items==2 and list.items[2].item.modId=='c' and list.selected==-1)
-- Search expands a matching collapsed folder; special characters are literal.
list.searchEntry.text='Beta'; list.searchEntry.onTextChange()
assert(f.expanded and list.foundIndex==1 and list.items[list.foundItems[1]].item.modId=='b')
list.searchEntry.text='['; list.searchEntry.onTextChange(); assert(#list.foundItems==0)
list.searchEntry.text='Beta'; list.searchEntry.onTextChange()
folders:setExpanded(f.id,false)
local nextButton
for _, child in ipairs(parent.children) do if child.internal=='NEXT_SEARCH' then nextButton=child end end
assert(nextButton); nextButton.onclick(nextButton.target, nextButton)
assert(f.expanded and list.items[list.foundItems[list.foundIndex]].item.modId=='b')
-- Right click moves the clicked item into another folder via its menu option.
local g=assert(folders:createFolder('Second'))
local cIndex
for i,row in ipairs(list.items) do if row.item.modId=='c' then cIndex=i end end
list:onRightMouseUp(0,cIndex)
local move
for _, option in ipairs(menu.options) do if option.title=='UI_MLOS_FolderMove: Second' then move=option end end
assert(move); move.action(move.target)
assert(folders.membership.c==g.id)
-- Clear/refill is batched, preserves memberships and updates row indices.
folders:setExpanded(f.id,false); folders:beginUpdate(); list:clear()
list:addItem('Beta.lua',{name='Beta.lua',modId='b'},'updated')
list:addItem('Other.lua',{name='Other.lua',modId='c'})
folders:endUpdate()
assert(#list.items==3 and list.items[1].MLOS_folder==f and list.items[2].MLOS_folder==g)
assert(list.items[3].item.modId=='c' and list.items[3].itemindex==3)
folders:setExpanded(f.id,true); assert(list.items[2].item.modId=='b' and list.items[2].tooltip=='updated')
assert(folders:renameFolder(g.id,'Renamed')); assert(not folders:renameFolder(g.id,'First'))
assert(folders:removeFolder(g.id)); assert(folders.membership.c==nil and list.items[#list.items].item.modId=='c')
assert(not folders:moveItems({'b'},999))
-- The UI prompt creates a named folder and moves the clicked item into it.
local looseIndex = #list.items
list:onRightMouseUp(0,looseIndex)
local create = menu.options[1]; create.action(create.target)
assert(lastPanel and #lastPanel.children==3)
local entry, ok = lastPanel.children[1], lastPanel.children[2]
entry.text='First'; ok.onclick(ok.target,ok)
assert(lastPanel.invalid and lastPanel.visible)
entry.text='My folder'; ok.onclick(ok.target,ok)
assert(not lastPanel.visible and folders.membership.c~=nil)
local newFolder=folders:findFolder(folders.membership.c)
assert(newFolder and newFolder.name=='My folder')
-- A multiselection moves together and keeps source item order.
local multi=ISScrollingListBox:new(0,0,400,300)
multi:addItem('One',{name='One',modId='one'})
multi:addItem('Two',{name='Two',modId='two'})
multi:addItem('Three',{name='Three',modId='three'})
local mf=scroll:addFoldersSupport(multi)
local group=assert(mf:createFolder('Group'))
multi.selected_map={[2]=true,[3]=true} -- folder header is row one
multi:onRightMouseUp(0,2)
local multiMove
for _, option in ipairs(menu.options) do if option.title=='UI_MLOS_FolderMove: Group' then multiMove=option end end
assert(multiMove); multiMove.action(multiMove.target)
assert(mf.membership.one==group.id and mf.membership.two==group.id and not mf.membership.three)
assert(multi.items[2].item.modId=='one' and multi.items[3].item.modId=='two')
print('folder view, context menu and search tests passed')

-- Copy feedback belongs to the popup, not to its child list, and expires.
local clipboard
Clipboard={setClipboard=function(text) clipboard=text end}
local Popup=require(root..'Elements_UI/WarningPopup')
local popup=Popup:new(0,0); popup:createChildren()
popup:addMessage('Warning','Details','Layer','WARNING')
popup:setExpanded(true)
popup.listBox:onMouseUp(0,1)
assert(clipboard=='[Layer] Warning\nDetails' and popup.copiedFlash==90)
assert(popup.listBox.copiedFlash==nil)
popup:prerender(); assert(popup.lastText=='UI_MLOS_CopiedToClipboard' and popup.copiedFlash==89)
for _=1,89 do popup:prerender() end
popup:prerender(); assert(popup.lastText==popup.headerText and popup.copiedFlash==0)
popup.listBox:onMouseUp(0,2); assert(popup.copiedFlash==0)
popup.listBox:onMouseUp(0,1); popup:clearWarnings(); assert(popup.copiedFlash==0)
print('popup clipboard feedback tests passed')
