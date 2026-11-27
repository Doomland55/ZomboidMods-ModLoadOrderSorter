-- Transaction and UI flow regression tests with lightweight PZ UI stubs.
local root = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/REfRigERatoR_ModLoadOrderSorter/'
local prefix = 'REfRigERatoR_ModLoadOrderSorter/'
local function copy(t)
 if type(t) ~= 'table' then return t end
 local out = {}; for k,v in pairs(t) do out[k] = copy(v) end; return out
end
local persisted = { A={loadAfter={'B'}}, Missing={loadBefore={'A'}} }
local fail = false
local info = { A={category='map',loadAfter={'B','C'},requirements={'B'}}, B={}, C={} }
local core={rawCategoryOrder={'map','undefined'},layers={
 ModsInfo={data=info}, ModsFiles={data={A={complete=false,files={'a.lua'}}}},
 SortingRules={beginEdit=function() return copy(persisted) end,
 commitEdit=function(_, value) if fail then return false end; persisted=value; return true end}}}
package.loaded[prefix..'Core/Core']=core
package.loaded[prefix..'Core/1_Utils']={deepCopy=function(_, t) return copy(t) end,
 tableIsEmpty=function(_, t) for _ in pairs(t) do return false end; return true end}
-- Kahlua in Project Zomboid does not expose the global next function.
local originalNext = next
next = nil
local Model=dofile(root..'Elements_UI/RulesEditorModel.lua')
package.loaded[prefix..'Elements_UI/RulesEditorModel']=Model
local empty = Model.new({})
empty:set('A', 'category', 'map')
assert(empty.draft.A.category == 'map')
empty:set('A', 'category', nil)
assert(empty.draft.A == nil)
local m=Model.new(persisted)
local groups=m:groups('A',info.A)
assert(#groups.loadAfter==2 and groups.loadAfter[1].metadata and groups.loadAfter[1].user)
assert(groups.loadAfter[2].metadata and not groups.loadAfter[2].user)
assert(m:remove('A','loadAfter','B') and #m:groups('A',info.A).loadAfter==2)
assert(m:add('A','loadBefore','C') and not m:add('A','loadBefore','C'))
assert(not m:add('A','loadBefore','A') and m:dirty('A'))
fail=true; assert(not m:commit() and persisted.A.loadAfter[1]=='B')
fail=false; assert(m:commit() and not m:dirty()); assert(persisted.Missing.loadBefore[1]=='A')

local Base={}
function Base:derive() local t={}; t.__index=t; return setmetatable(t,{__index=self}) end
function Base:new(x,y,w,h) return setmetatable({x=x,y=y,width=w,height=h,children={}}, {__index=self}) end
function Base:initialise() if self.createChildren then self:createChildren() end end
function Base:instantiate() end
function Base:addChild(o) self.children[#self.children+1]=o; o.parent=self end
function Base:setVisible(v) self.visible=v end
function Base:removeFromUIManager() end
function Base:drawText() end
function Base:drawTextCentre() end
function Base:prerender() end
ISPanelJoypad=Base
ISScrollingListBox={onMouseDown=function(self) self.selected=self.mouseoverselected end}
ISButton=Base:derive()
function ISButton:new(x,y,w,h,title,target,callback) local o=Base.new(self,x,y,w,h); o.title=title; o.target=target; o.callback=callback; return o end
ISComboBox=Base:derive()
function ISComboBox:new(x,y,w,h,target,callback) local o=Base.new(self,x,y,w,h); o.target=target;o.callback=callback;o.options={};return o end
function ISComboBox:addOptionWithData(label,data) self.options[#self.options+1]={label,data} end
function ISComboBox:getOptionData(i) return self.options[i][2] end
ISModalDialog=Base:derive()
for _, n in ipairs({'ISUI/ISPanelJoypad','ISUI/ISScrollingListBox','ISUI/ISButton','ISUI/ISComboBox','ISUI/ISModalDialog'}) do package.loaded[n]=true end
UIFont={Small=1,Medium=2}
function getText(k) return k end
function getTextManager() return {getFontHeight=function() return 15 end} end
function getCore() return {getScreenWidth=function() return 1200 end,getScreenHeight=function() return 800 end} end
local scroll={}
function scroll.createList(parent,x,y,w,h)
 local l=Base.new(Base,x,y,w,h); l.items={};l.selected=0
 function l:clear() self.items={};self.selected=0 end
 function l:addItem(text,item,tooltip) local r={text=text,item=item,tooltip=tooltip,index=#self.items+1};self.items[#self.items+1]=r;return r end
 parent:addChild(l);return l
end
function scroll:addSearchEntry() end
package.loaded[prefix..'Elements_UI/ScrollExtensions']=scroll
local sorter={warnings={'old'},lastEdges={old=true},brokenEdges={}}
function sorter:calculateCategories(rows, rules)
 local effective = { A='map', B='undefined', C='undefined' }
 if rules.A and rules.A.loadAfter then
  for _, dep in ipairs(rules.A.loadAfter) do effective[dep] = 'map' end
 end
 return effective, { A='map', B='undefined', C='undefined' }
end
function sorter:sort(rows,rules)
 assert(rules.A.loadBefore[1]=='C'); info.A.effectiveCategory='temporary'
 self.warnings={{title='cycle',message='details'}};self.lastEdges={};self.brokenEdges={}
 return {'B','A','C'}
end
package.loaded[prefix..'Core/SortingCore']=sorter
local Editor=dofile(root..'Elements_UI/RulesEditor.lua')
local owner={modList={items={{item={modId='A',name='Alpha'}},{item={modId='B',name='Beta'}},{item={modId='C',name='Gamma'}}}},setVisible=function(self,v) self.visible=v end}
local e=Editor:new(0,0,1000,700,owner); e:initialise();e:instantiate()
assert(e.selectedId=='A' and e.details.items[1].item.kind=='group')
assert(e.mods.items[1].item.kind=='category' and e.mods.items[1].item.category=='map')
assert(e.mods.items[2].item.modId=='A' and e.mods.items[3].item.category=='undefined')
-- Category toggles never change the source mod or consume the add mode.
e.addKey='incompatibleMods';e.mods.mouseoverselected=3;e:onModClick(e.mods,0,0)
assert(e.selectedId=='A' and e.addKey=='incompatibleMods' and #e.mods.items==3)
e:revealCategoryMatches('beta'); assert(#e.mods.items==5 and e.mods.items[4].item.modId=='B')
e.mods.mouseoverselected=4;e:onModClick(e.mods,0,0)
assert(e.model.draft.A.incompatibleMods[1]=='B' and e.mods.selected==2 and e.model:dirty())
-- Unsaved explicit ordering moves B to A's category immediately.
e.model:add('A','loadAfter','B'); e:changed()
assert(e.effectiveCategories.B=='map' and e.mods.items[3].item.modId=='B')
assert(e.mods.items[3].text:find('^',1,true))
assert(e.mods.items[3].tooltip:find('map',1,true))
local original=sorter.warnings;e:simulate();assert(e.view=='preview' and e.preview.ids[1]=='B')
assert(sorter.warnings==original and info.A.effectiveCategory==nil and owner.modList.items[1].item.modId=='A')
core.layersManager={run={completed=false}}
e:update(); assert(e.previewStale)
e.previewStale=false; core.layersManager.run.completed=true; e:update(); assert(e.previewStale)
e.model:set('A','category','map');e:changed(); assert(e.previewStale)
e.view='files';e:refresh();assert(#e.details.items==2)
e.view='rules';e:refresh();local selected
for i,r in ipairs(e.details.items) do if r.item.id=='B' and r.item.key=='loadAfter' and r.item.user then selected=i end end
-- The new user rule and metadata are both visible.
assert(selected~=nil and e.details.items[selected].item.user)
fail=true;e:save();assert(e.model:dirty() and e.message:find('SaveError'))
fail=false;e:save();assert(not e.model:dirty() and persisted.A.incompatibleMods[1]=='B')
next = originalNext
print('Rules editor model and UI flow tests passed')
