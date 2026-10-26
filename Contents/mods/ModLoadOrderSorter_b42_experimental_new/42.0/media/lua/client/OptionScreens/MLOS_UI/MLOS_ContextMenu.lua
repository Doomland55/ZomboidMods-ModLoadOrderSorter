require "ISUI/ISPanelJoypad"
require "ISUI/ISButton"

MLOS_ContextMenu = ISPanelJoypad:derive("MLOS_ContextMenu")

function MLOS_ContextMenu:new(x, y)
    local o = ISPanelJoypad:new(x, y, 100, 10)
    setmetatable(o, self)
    self.__index = self

    o.x = x
    o.y = y
    o.options = {}
    o.itemHeight = 22
    o.minWidth = 140
    o.pad = 3

    -- Стиль рамки в духе интерфейса PZ
    o.backgroundColor = {r = 0.10, g = 0.10, b = 0.10, a = 0.95}
    o.borderColor =     {r = 0.35, g = 0.35, b = 0.35, a = 1.00}

    o:setAlwaysOnTop(true)
    return o
end

-- Добавление опции (аналог context:addOption)
function MLOS_ContextMenu:addOption(title, tooltip, target, onSelect, ...)
    local opt = {
        title = title,
        tooltip = tooltip, 
        target = target,
        onSelect = onSelect,
        args = { ... }
    }
    table.insert(self.options, opt)
    return opt
end

-- Сборка и отображение на экране
function MLOS_ContextMenu:display()
    self:clearChildren()

    local font = UIFont.Small
    local fontHgt = getTextManager():getFontHeight(font)
    local maxWidth = self.minWidth

    -- 1. Считаем максимальную ширину по тексту
    for _, opt in ipairs(self.options) do
        local strW = getTextManager():MeasureStringX(font, opt.title) + 24
        if strW > maxWidth then maxWidth = strW end
    end

    local currentY = self.pad
    local btnWidth = maxWidth - (self.pad * 2)

    -- 2. Создаем кнопки ISButton для каждой строки
    for _, opt in ipairs(self.options) do
        local btn = ISButton:new(self.pad, currentY, btnWidth, self.itemHeight, opt.title, self, self.onButtonClick)
        btn:initialise()
        btn:instantiate()
        btn:setTooltip(opt.tooltip)
        btn:setFont(font)
        btn.optData = opt

        self:addChild(btn)
        currentY = currentY + self.itemHeight + 1
    end

    self:setWidth(maxWidth)
    self:setHeight(currentY + self.pad - 1)

    -- 3. Защита от вылета за пределы экрана
    local screenW = getCore():getScreenWidth()
    local screenH = getCore():getScreenHeight()

    if self.x + self.width > screenW then
        self:setX(screenW - self.width)
    end
    if self.y + self.height > screenH then
        self:setY(screenH - self.height)
    end

    -- Добавляем в интерфейс
    self:setAlwaysOnTop(true)
    self:addToUIManager()
end



-- Обработка клика по кнопке
function MLOS_ContextMenu:onButtonClick(button)
    local opt = button.optData
    if opt and opt.onSelect then
        opt.onSelect(opt.target, unpack(opt.args))
    end

    self:close()
end


function MLOS_ContextMenu:onMouseDownOutside(x, y)
    if self:isMouseOver() then
        return
    end
    self:close()
end


function MLOS_ContextMenu:onRightMouseDownOutside(x, y)
    self:onMouseDownOutside(x, y) 
end

function MLOS_ContextMenu:onMouseDown(x, y)
    return true
end


function MLOS_ContextMenu:onMouseUp(x, y)
    return true
end


function MLOS_ContextMenu:close()
    self:setVisible(false)
    self:removeFromUIManager()
end
