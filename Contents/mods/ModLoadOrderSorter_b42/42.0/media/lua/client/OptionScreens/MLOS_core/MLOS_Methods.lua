local utils = require('OptionScreens/MLOS_core/Refr_utils')

local MLOSMethods = {}


function MLOSMethods:getTooltipText(extraModInfo)
    local addText = function(desc, data_table)
        if not utils:tableIsEmpty(data_table) then
            return desc .. ":\n- " .. table.concat(data_table, ", ") .. " <RGB:0.8,0.8,0.8> \n"
        end
        return " <RGB:0.8,0.8,0.8> "
    end

    local text = ""
    text = text .. addText(" <RGB:0.98,0.08,0.08> " .. getText("UI_ModManagerLoadOrderSorter_Missing_Warning"), extraModInfo.warnings.missing)
    text = text .. addText(" <RGB:0.88,0.08,0.08> " .. getText("UI_ModManagerLoadOrderSorter_WrongOrder_Warning"), extraModInfo.warnings.wrongOrder)
    text = text .. addText(" <RGB:0.65,0.08,0.90> " .. getText("UI_ModManagerLoadOrderSorter_Incompatible_Warning"), extraModInfo.warnings.incompatible)
    text = text .. addText(" <RGB:0.98,0.66,0.06> " .. getText("UI_ModManagerLoadOrderSorter_Rules_Warning"), extraModInfo.warnings.rules)

    local debugText = ""
    if true or isDebugEnabled() == true then
        local _names = {"category", "requirements", "flags", "maps"}
        debugText = utils:getString(extraModInfo, 0, _names)
        if not utils:tableIsEmpty(extraModInfo.sortingRules) then
            debugText = debugText .. "\n<RGB:1.0,0.98,0.804>SortingRules:" .. utils:getString(extraModInfo.sortingRules, 0) .. "\n<RGB:0.8,0.8,0.8>"
        end
        debugText = debugText:match( "^%s*(.-)%s*$" )
    end
    return extraModInfo.id:gsub("\\", "") .. "\n" .. text .. debugText
end


function MLOSMethods:selectObject(multiselected, row, ctrlPressed, shiftPressed)
    if row <= 0 then return multiselected end
    
    local selectedIndices = multiselected

    local function toggleNumberInArray(array, number)
        local found_index = utils:getElementIndex(array, number)
        if found_index ~= nil then table.remove(array, found_index)
        else table.insert(array, number) end
        return found_index
    end

    local function isInOrder(tbl)
        for i=1, #tbl-1  do
            if math.abs(tbl[i+1] - tbl[i]) ~= 1 then return false end
        end
        return true
    end

    if shiftPressed and not utils:tableIsEmpty(selectedIndices) then
        local latestRow = selectedIndices[#selectedIndices]

        if not isInOrder(selectedIndices) then
            selectedIndices = {latestRow,}
        end

        local offset = (latestRow > row and -1 or 1)
        local firstWasSelected = utils:getElementIndex(selectedIndices, latestRow + offset)
        for i = latestRow + offset, row, offset do
            toggleNumberInArray(selectedIndices, i)
        end
        if firstWasSelected then toggleNumberInArray(selectedIndices, latestRow) end

    elseif ctrlPressed then
        toggleNumberInArray(selectedIndices, row)
    else
        selectedIndices = {row, }
    end
    return selectedIndices
end


function MLOSMethods:moveElements(scrollObj, indices, clickIndex, dragIndex)
    local shift = clickIndex - dragIndex
    local shiftChange = shift > 0 and -1 or 1

    -- сортируем в нужном порядке в зависимости от того в какую сторону тянем
    if shift > 0 then table.sort(indices, function(a, b) return a > b end)
    else table.sort(indices, function(a, b) return a < b end) end

    -- пересчитываем сдвиг, если тянем не за крайний элемент
    for i=clickIndex, dragIndex - shiftChange, shiftChange do
        if utils:contains(indices, i) then shift = shift + shiftChange end
    end

    local newIndexes = {}
    local items = scrollObj.items
    local size = #items

    for i, index in ipairs(indices) do
        repeat
            local newIndex = index + shift
            if newIndex > 0 and utils:contains(indices, newIndex) then break end
            if index < 1 or index > size then break end

            newIndex = utils:clamp(newIndex,
                                   1 + (shiftChange > 0 and (i -shiftChange) or 0),
                                   size - (shiftChange < 0 and (i +shiftChange) or 0))

            local element = table.remove(items, index)
            table.insert(items, newIndex, element)

            indices[i] = index * -1
            newIndexes[i] = newIndex
        until true
    end
    return newIndexes
end

return MLOSMethods