require "ISUI/ISButton"

-- Shared by the legend and the lists so the examples match the actual colors.
local ColorLegend = {}
ColorLegend.modColors = {
    purple = {r=0.75, g=0.30, b=1.00},
    red = {r=0.98, g=0.20, b=0.20},
    yellow = {r=1.00, g=0.75, b=0.20},
    normal = {r=1.00, g=1.00, b=1.00}
}
ColorLegend.fileConflict = {r=1.00, g=0.65, b=0.20}
ColorLegend.selection = {r=0.70, g=0.35, b=0.15, a=0.30}
ColorLegend.search = {r=0.50, g=1.00, b=1.00, a=0.30}

local function colorTag(color)
    return string.format("<RGB:%.2f,%.2f,%.2f>", color.r, color.g, color.b)
end

function ColorLegend:tooltip()
    local entries = {
        {self.modColors.purple, "UI_MLOS_Legend_Purple"},
        {self.modColors.red, "UI_MLOS_Legend_Red"},
        {self.modColors.yellow, "UI_MLOS_Legend_Yellow"},
        {self.modColors.normal, "UI_MLOS_Legend_Normal"},
        {self.fileConflict, "UI_MLOS_Legend_FileConflict"},
        {self.selection, "UI_MLOS_Legend_Selected"},
        {self.search, "UI_MLOS_Legend_Search"}
    }
    local lines = {getText("UI_MLOS_Legend_Title")}
    for _, entry in ipairs(entries) do
        lines[#lines + 1] = colorTag(entry[1]) .. "[###] " .. colorTag(self.modColors.normal) .. getText(entry[2])
    end
    lines[#lines + 1] = colorTag(self.modColors.normal) .. getText("UI_MLOS_Legend_Priority")
    return table.concat(lines, " <LINE> ")
end

-- A hover tooltip keeps the help available without occupying the inspector.
function ColorLegend:addButton(parent, x, y, maxWidth, height)
    local title = getText("UI_MLOS_Legend_Button")
    local width = math.min(maxWidth, getTextManager():MeasureStringX(UIFont.Small, title) + 20)
    local button = ISButton:new(x, y, width, height, title, parent, function() end)
    button:initialise(); button:instantiate()
    button:setFont(UIFont.Small)
    button:setTooltip(self:tooltip())
    button:ignoreWidthChange(); button:ignoreHeightChange()
    parent:addChild(button)
    return button
end

return ColorLegend
