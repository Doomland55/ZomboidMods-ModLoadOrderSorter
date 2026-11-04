require "ISUI/ISPanel"
require "ISUI/ISScrollingListBox"
require "ISUI/ISToolTip"

ModSortWarningPopup = ISPanel:derive("ModSortWarningPopup")

local COLLAPSED_SIZE = 48
local EXPANDED_WIDTH = 480
local EXPANDED_HEIGHT = 320
local HEADER_HEIGHT = 30
local SCREEN_PADDING = 15

-- Заранее знаем максимальную ширину текста:
-- Ширина окна (480) - отступ слева (14) - скроллбар и отступ справа (22) = 444 пикселя
local MAX_TEXT_WIDTH = EXPANDED_WIDTH - 36

-- Заранее созданные цвета (чтобы не создавать таблицы в памяти)
local COLOR_CRITICAL = {r=0.9, g=0.2, b=0.2}
local COLOR_WARNING  = {r=0.95, g=0.7, b=0.1}

-- Быстрая обрезка текста (бинарный поиск + защита UTF-8/кириллицы)
local function truncateText(text, font, maxWidth)
    local tm = getTextManager()
    if tm:MeasureStringX(font, text) <= maxWidth then
        return text, false
    end

    local ellipsis = "..."
    local low = 1
    local high = string.len(text)
    local bestLen = 0

    -- Бинарный поиск нужной длины строки (работает мгновенно даже на текстах в 1000 символов)
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local sub = string.sub(text, 1, mid) .. ellipsis
        if tm:MeasureStringX(font, sub) <= maxWidth then
            bestLen = mid
            low = mid + 1
        else
            high = mid - 1
        end
    end

    -- Защита для кириллицы (UTF-8): если разрезали двухбайтовый символ пополам, сдвигаемся на 1 байт назад
    if bestLen > 0 then
        local nextByte = string.byte(text, bestLen + 1)
        if nextByte and nextByte >= 128 and nextByte < 192 then
            bestLen = bestLen - 1
        end
    end

    return string.sub(text, 1, bestLen) .. ellipsis, true
end

function ModSortWarningPopup:new(x, y)
    local o = ISPanel.new(self, x, y, COLLAPSED_SIZE, COLLAPSED_SIZE)
    
    o.anchorX = x
    o.anchorY = y
    
    o.backgroundColor = {r=0.1, g=0.1, b=0.1, a=0.95}
    o.borderColor = {r=0.9, g=0.5, b=0.0, a=1.0}
    
    o.isExpanded = false
    o.warnings = {}
    o.moveWithMouse = false
    
    o:setVisible(false)
    return o
end

function ModSortWarningPopup:createChildren()
    ISPanel.createChildren(self)

    self.listBox = ISScrollingListBox:new(0, HEADER_HEIGHT, EXPANDED_WIDTH, EXPANDED_HEIGHT - HEADER_HEIGHT)
    self.listBox:initialise()
    self.listBox:instantiate()
    self.listBox.itemheight = 48
    self.listBox.backgroundColor = {r=0.05, g=0.05, b=0.05, a=0.9}
    self.listBox.doDrawItem = self.drawWarningItem
    self.listBox.doRepaintStencil = true
    self.listBox:setVisible(false)
    self:addChild(self.listBox)

    self.tooltipUI = ISToolTip:new()
    self.tooltipUI:setOwner(self)
    self.tooltipUI:setVisible(false)
    self.tooltipUI:setAlwaysOnTop(true)
    self.tooltipUI.maxLineWidth = 420
end

-- Добавление предупреждения: ВСЕ вычисления происходят ровно 1 раз здесь!
function ModSortWarningPopup:addMessage(title, message, layerName, severity)
    title = title or "Conflict"
    message = message or ""
    layerName = layerName or "Base"
    severity = severity or "WARNING"

    local fullTitle = string.format("[%s] %s", layerName, title)
    
    -- Один раз обрезаем текст под размер окна
    local displayTitle, isTitleLong = truncateText(fullTitle, UIFont.Small, MAX_TEXT_WIDTH)
    local displayMessage, isMsgLong = truncateText(message, UIFont.Small, MAX_TEXT_WIDTH)
    local isLong = isTitleLong or isMsgLong

    -- Один раз определяем цвета и текст для тултипа
    local isCrit = (severity == "CRITICAL")
    local colorTag = isCrit and "<RGB:1,0.3,0.3>" or "<RGB:1,0.8,0.2>"

    local warningData = {
        displayTitle = displayTitle,
        displayMessage = displayMessage,
        barColor = isCrit and COLOR_CRITICAL or COLOR_WARNING,
        isLong = isLong,
        tooltipName = isLong and fullTitle or nil,
        tooltipDesc = isLong and (colorTag .. message) or nil
    }
    
    table.insert(self.warnings, warningData)
    self.listBox:addItem(displayTitle, warningData)

    -- Обновляем текст шапки один раз при добавлении
    self.headerText = string.format("Found problems (%d):", #self.warnings)
    self.countStr = tostring(#self.warnings)

    if not self:getIsVisible() then
        self:setVisible(true)
        self:bringToTop()
    end
end


function ModSortWarningPopup:addWarning(title, message, layerName)
    self:addMessage(title, message, layerName, "WARNING")
end


function ModSortWarningPopup:addError(title, message, layerName)
    self:addMessage(title, message, layerName, "CRITICAL")
end


-- Отрисовка элемента списка: ТЕПЕРЬ 0 ВЫЧИСЛЕНИЙ, только чистый рендер!
function ModSortWarningPopup:drawWarningItem(y, item, alt)
    local data = item.item
    local width = self:getWidth()
    
    if self.mouseoverselected == item.index then
        self:drawRect(0, y, width, item.height, 0.25, 0.4, 0.3, 0.1)
    elseif alt then
        self:drawRect(0, y, width, item.height, 0.15, 0.25, 0.25, 0.25)
    end
    self:drawRectBorder(0, y, width, item.height, 0.3, 0.4, 0.4, 0.4)

    local c = data.barColor
    self:drawRect(0, y, 6, item.height, 1.0, c.r, c.g, c.b)

    self:drawText(data.displayTitle, 14, y + 5, c.r, c.g, c.b, 1.0, UIFont.Small)
    self:drawText(data.displayMessage, 14, y + 24, 0.9, 0.9, 0.9, 1.0, UIFont.Small)

    return y + item.height
end

-- Очистка всех предупреждений
function ModSortWarningPopup:clearWarnings()
    self.warnings = {}
    self.listBox:clear()
    self:hideTooltip()
    self:setExpanded(false)
    self:setVisible(false)
end

function ModSortWarningPopup:hideTooltip()
    if self.tooltipUI and self.tooltipUI:getIsVisible() then
        self.tooltipUI:setVisible(false)
        self.tooltipUI:removeFromUIManager()
    end
end

function ModSortWarningPopup:setExpanded(expand)
    if self.isExpanded == expand then return end
    self.isExpanded = expand

    if self.isExpanded then
        self:setWidth(EXPANDED_WIDTH)
        self:setHeight(EXPANDED_HEIGHT)
        
        -- 2. Проверяем границы экрана (или родительского окна), чтобы не вылезти за край
        local maxW = self.parent and self.parent:getWidth() or getCore():getScreenWidth()
        local maxH = self.parent and self.parent:getHeight() or getCore():getScreenHeight()
        
        local newX = self.anchorX
        local newY = self.anchorY
        
        if newX + EXPANDED_WIDTH > maxW - SCREEN_PADDING then
            newX = maxW - EXPANDED_WIDTH - SCREEN_PADDING
        end
        if newY + EXPANDED_HEIGHT > maxH - SCREEN_PADDING then
            newY = maxH - EXPANDED_HEIGHT - SCREEN_PADDING
        end
        if newX < SCREEN_PADDING then newX = SCREEN_PADDING end
        if newY < SCREEN_PADDING then newY = SCREEN_PADDING end
        
        self:setX(newX)
        self:setY(newY)

        self.listBox:setVisible(true)
        self:bringToTop()
    else
        self:hideTooltip()
        self:setX(self.anchorX)
        self:setY(self.anchorY)
        self:setWidth(COLLAPSED_SIZE)
        self:setHeight(COLLAPSED_SIZE)
        
        self.listBox:setVisible(false)
    end
end

function ModSortWarningPopup:onMouseUp(x, y)
    ISPanel.onMouseUp(self, x, y)

    if not self.isExpanded then
        if x >= 0 and x <= self.width and y >= 0 and y <= self.height then
            self:setExpanded(true)
        end
    else
        if y >= 0 and y <= HEADER_HEIGHT then
            self:setExpanded(false)
        end
    end
end

function ModSortWarningPopup:onMouseDownOutside(x, y)
    ISPanel.onMouseDownOutside(self, x, y)
    
    if self.isExpanded and not self:isMouseOver() then
        self:setExpanded(false)
    end
end

-- Тултип просто берет готовые строки из data
function ModSortWarningPopup:updateTooltip()
    if not self.isExpanded or not self.listBox:isMouseOver() then
        self:hideTooltip()
        return
    end

    local row = self.listBox.mouseoverselected
    if row and row ~= -1 and self.listBox.items[row] then
        local data = self.listBox.items[row].item
        if data and data.isLong then
            self.tooltipUI.name = data.tooltipName
            self.tooltipUI.description = data.tooltipDesc

            if not self.tooltipUI:getIsVisible() then
                self.tooltipUI:setVisible(true)
                self.tooltipUI:addToUIManager()
                self.tooltipUI.followMouse = true
            end
            return
        end
    end

    self:hideTooltip()
end

function ModSortWarningPopup:prerender()
    ISPanel.prerender(self)

    if not self.isExpanded then
        if self:isMouseOver() then
            self:drawRect(2, 2, COLLAPSED_SIZE - 4, COLLAPSED_SIZE - 4, 0.35, 1.0, 0.6, 0.0)
        else
            self:drawRect(4, 4, COLLAPSED_SIZE - 8, COLLAPSED_SIZE - 8, 0.2, 0.8, 0.4, 0.0)
        end

        self:drawTextCentre("!", COLLAPSED_SIZE / 2, 6, 1.0, 0.85, 0.1, 1.0, UIFont.Large)

        self:drawRect(COLLAPSED_SIZE - 22, COLLAPSED_SIZE - 18, 20, 16, 0.95, 0.8, 0.1, 0.1)
        self:drawTextCentre(self.countStr or "0", COLLAPSED_SIZE - 12, COLLAPSED_SIZE - 17, 1.0, 1.0, 1.0, 1.0, UIFont.Small)
    else
        self:drawRect(0, 0, self.width, HEADER_HEIGHT, 1.0, 0.2, 0.12, 0.02)
        self:drawRectBorder(0, 0, self.width, HEADER_HEIGHT, 1.0, 0.9, 0.5, 0.0)
        self:drawText(self.headerText or "", 10, 7, 1.0, 0.85, 0.2, 1.0, UIFont.Small)
    end
end


function ModSortWarningPopup:render()
    ISPanel.render(self)
    self:updateTooltip()
end


return  ModSortWarningPopup