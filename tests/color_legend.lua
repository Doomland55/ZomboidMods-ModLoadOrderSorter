-- Run from the repository root with Lua 5.1: lua tests/color_legend.lua
local base = 'Contents/mods/ModLoadOrderSorter_b42_experimental_new/42.0/media/lua/client/'
package.path = base .. '?.lua;' .. package.path
package.preload['ISUI/ISButton'] = function() return true end
UIFont = {Small=1}
getText = function(key) return key end
getTextManager = function() return {MeasureStringX=function(_, _, text) return #text * 5 end} end
ISButton = {}
function ISButton:new(x, y, w, h, title, target, callback)
    local o = {x=x,y=y,width=w,height=h,title=title,target=target,callback=callback}
    setmetatable(o,{__index=self}); return o
end
function ISButton:initialise() end
function ISButton:instantiate() end
function ISButton:setFont(font) self.font=font end
function ISButton:setTooltip(text) self.tooltip=text end
function ISButton:ignoreWidthChange() end
function ISButton:ignoreHeightChange() end
local legend = require('REfRigERatoR_ModLoadOrderSorter/Elements_UI/ColorLegend')
local tooltip = legend:tooltip()
local expected = {
    {'<RGB:0.75,0.30,1.00>', 'UI_MLOS_Legend_Purple'},
    {'<RGB:0.98,0.20,0.20>', 'UI_MLOS_Legend_Red'},
    {'<RGB:1.00,0.75,0.20>', 'UI_MLOS_Legend_Yellow'},
    {'<RGB:1.00,1.00,1.00>', 'UI_MLOS_Legend_Normal'},
    {'<RGB:1.00,0.65,0.20>', 'UI_MLOS_Legend_FileConflict'},
    {'<RGB:0.70,0.35,0.15>', 'UI_MLOS_Legend_Selected'},
    {'<RGB:0.50,1.00,1.00>', 'UI_MLOS_Legend_Search'}
}
for _, row in ipairs(expected) do assert(tooltip:find(row[1]..'[###] <RGB:1.00,1.00,1.00>'..row[2],1,true)) end
assert(tooltip:find('UI_MLOS_Legend_Priority',1,true))
local parent={children={}}
function parent:addChild(child) self.children[#self.children+1]=child end
local button=legend:addButton(parent,10,20,80,25)
assert(parent.children[1]==button and button.tooltip==tooltip and button.width==80)
assert(button.x==10 and button.y==20 and button.height==25)
print('color legend tests passed')
