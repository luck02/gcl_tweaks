-- GCL Tweaks: Enhanced Cargo Tab
-- Replaces vanilla cargo tab with readable item names, values, and status indicators

package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("stringutility")
include("callable")

-- namespace GclCargoTab
GclCargoTab = {}

-- UI elements
local playerCargoFrame = nil
local selfCargoFrame = nil
local playerTotalCargoBar = nil
local selfTotalCargoBar = nil

local playerCargoRows = {}
local selfCargoRows = {}

-- State
local cargosByButton = {}
local cargosByTextBox = {}
local textboxIndexByButton = {}
local playerCargoName = {}
local selfCargoName = {}
local playerCargoTextBoxByIndex = {}
local selfCargoTextBoxByIndex = {}
local missionIngredients = {} -- cached ingredients from turret mission

-- Colors
local COLOR_STOLEN = ColorRGB(1.0, 0.3, 0.3)
local COLOR_ILLEGAL = ColorRGB(1.0, 0.5, 0.0)
local COLOR_MISSION = ColorRGB(0.3, 1.0, 0.5)
local COLOR_NORMAL = ColorRGB(0.8, 0.8, 0.8)

function GclCargoTab.build(tabbedWindow)
    local cargoTab = tabbedWindow:createTab("Cargo" % _t, "data/textures/icons/trade.png", "Exchange Cargo" % _t)

    local vSplit = UIVerticalSplitter(Rect(cargoTab.size), 10, 0, 0.5)

    -- Create scroll frames
    playerCargoFrame = cargoTab:createScrollFrame(vSplit.left)
    selfCargoFrame = cargoTab:createScrollFrame(vSplit.right)

    -- Use left coordinates for both listers since they're relative
    local leftLister = UIVerticalLister(vSplit.left, 8, 10)
    local rightLister = UIVerticalLister(vSplit.left, 8, 10)

    leftLister.marginRight = 10
    rightLister.marginRight = 10

    -- Transfer all buttons
    local playerTransferAllCargoButton = playerCargoFrame:createButton(Rect(), "Transfer All >>" % _t,
        "onGclPlayerTransferAllCargoPressed")
    leftLister:placeElementCenter(playerTransferAllCargoButton)
    playerTransferAllCargoButton.textSize = 14

    local selfTransferAllCargoButton = selfCargoFrame:createButton(Rect(), "<< Transfer All" % _t,
        "onGclSelfTransferAllCargoPressed")
    rightLister:placeElementCenter(selfTransferAllCargoButton)
    selfTransferAllCargoButton.textSize = 14

    -- Total cargo bars
    playerTotalCargoBar = playerCargoFrame:createNumbersBar(Rect())
    leftLister:placeElementCenter(playerTotalCargoBar)

    selfTotalCargoBar = selfCargoFrame:createNumbersBar(Rect())
    rightLister:placeElementCenter(selfTotalCargoBar)

    -- Create cargo rows (100 max like vanilla)
    for i = 1, 100 do
        -- Player side row
        local row = GclCargoTab.createCargoRow(playerCargoFrame, leftLister, true, i)
        table.insert(playerCargoRows, row)

        -- Self side row
        local row = GclCargoTab.createCargoRow(selfCargoFrame, rightLister, false, i)
        table.insert(selfCargoRows, row)
    end

    -- Load mission ingredients on init
    GclCargoTab.fetchMissionIngredients()
end

function GclCargoTab.createCargoRow(frame, lister, isPlayerSide, index)
    local row = {}

    -- Row height for grid display
    local rowHeight = 26
    local rect = lister:placeCenter(vec2(lister.inner.width, rowHeight))

    -- Grid Layout: [Icon] [Indicator] [Name] [Qty] [Value] [TextBox] [Button]
    -- Proportions: 26px | 20px | 40% | 15% | 20% | 60px | 30px
    local iconWidth = 26
    local indicatorWidth = 18
    local buttonWidth = 30
    local textBoxWidth = 55

    -- Calculate remaining width for text columns
    local controlsWidth = buttonWidth + textBoxWidth + 10 -- with spacing
    local leftWidth = rect.width - controlsWidth

    -- Create splits for the layout
    local mainSplit = UIVerticalSplitter(rect, 5, 0, (leftWidth / rect.width))

    -- Left side: Icon, indicator, name, qty, value
    local leftRect = mainSplit.left

    -- Icon (fixed width on far left)
    local iconRect = Rect(leftRect.lower, vec2(leftRect.lower.x + iconWidth, leftRect.upper.y))
    row.icon = frame:createPicture(iconRect, "")
    row.icon.isIcon = true

    -- Remaining width after icon
    local afterIconRect = Rect(vec2(leftRect.lower.x + iconWidth + 2, leftRect.lower.y), leftRect.upper)

    -- Split remaining into: indicator | name | qty | value
    -- Indicator: 18px fixed
    local indicatorRect = Rect(afterIconRect.lower, vec2(afterIconRect.lower.x + indicatorWidth, afterIconRect.upper.y))
    row.indicator = frame:createLabel(indicatorRect, "", 12)
    row.indicator:setCenterAligned()

    -- After indicator
    local afterIndicatorRect = Rect(vec2(afterIconRect.lower.x + indicatorWidth, afterIconRect.lower.y),
        afterIconRect.upper)
    local remainingWidth = afterIndicatorRect.width

    -- Name: 50%, Qty: 20%, Value: 30%
    local nameWidth = remainingWidth * 0.50
    local qtyWidth = remainingWidth * 0.18
    local valueWidth = remainingWidth * 0.32

    local nameRect = Rect(afterIndicatorRect.lower,
        vec2(afterIndicatorRect.lower.x + nameWidth, afterIndicatorRect.upper.y))
    row.nameLabel = frame:createLabel(nameRect, "", 12)
    row.nameLabel:setLeftAligned()

    local qtyRect = Rect(vec2(nameRect.upper.x, afterIndicatorRect.lower.y),
        vec2(nameRect.upper.x + qtyWidth, afterIndicatorRect.upper.y))
    row.qtyLabel = frame:createLabel(qtyRect, "", 12)
    row.qtyLabel:setRightAligned()

    local valueRect = Rect(vec2(qtyRect.upper.x, afterIndicatorRect.lower.y),
        vec2(qtyRect.upper.x + valueWidth, afterIndicatorRect.upper.y))
    row.valueLabel = frame:createLabel(valueRect, "", 12)
    row.valueLabel:setRightAligned()

    -- Right side: TextBox and Button
    local rightRect = mainSplit.right
    local rightSplit = UIVerticalSplitter(rightRect, 3, 0, 0.6)

    -- TextBox for amount
    row.textBox = frame:createTextBox(rightSplit.left,
        isPlayerSide and "onGclPlayerTransferCargoTextEntered" or "onGclSelfTransferCargoTextEntered")
    row.textBox.allowedCharacters = "0123456789"
    row.textBox.clearOnClick = true

    -- Transfer button
    row.button = frame:createButton(rightSplit.right, "",
        isPlayerSide and "onGclPlayerTransferCargoPressed" or "onGclSelfTransferCargoPressed")
    row.button.icon = isPlayerSide and "data/textures/icons/arrow-right2.png" or "data/textures/icons/arrow-left2.png"

    -- Store mappings
    cargosByButton[row.button.index] = index
    cargosByTextBox[row.textBox.index] = index
    textboxIndexByButton[row.button.index] = row.textBox.index

    if isPlayerSide then
        table.insert(playerCargoName, "")
    else
        table.insert(selfCargoName, "")
    end

    row.visible = false
    return row
end

function GclCargoTab.setRowVisible(row, visible)
    row.icon.visible = visible
    row.indicator.visible = visible
    row.nameLabel.visible = visible
    row.qtyLabel.visible = visible
    row.valueLabel.visible = visible
    row.textBox.visible = visible
    row.button.visible = visible
    row.visible = visible
end

function GclCargoTab.fetchMissionIngredients()
    missionIngredients = {}

    local player = Player()
    if not player then return end

    -- Try to get turret building mission ingredients
    -- Path must be player/missions/turretbuilding.lua for player scripts
    local ok, result = player:invokeFunction("player/missions/turretbuilding.lua", "secure")
    if ok == 0 and result and result.data and result.data.custom and result.data.custom.ingredients then
        for _, ingredient in pairs(result.data.custom.ingredients) do
            if ingredient.name and ingredient.amount then
                missionIngredients[ingredient.name] = ingredient.amount
            end
        end
    end
end

function GclCargoTab.isMissionIngredient(goodName)
    return missionIngredients[goodName] ~= nil
end

function GclCargoTab.getMissionNeeded(goodName)
    return missionIngredients[goodName] or 0
end

function GclCargoTab.refreshUI()
    local playerShip = Player().craft
    local ship = Entity()

    GclCargoTab.fetchMissionIngredients()
    GclCargoTab.refreshCargoUI(playerShip, ship)
end

function GclCargoTab.refreshCargoUI(playerShip, ship)
    -- Clear totals
    playerTotalCargoBar:clear()
    selfTotalCargoBar:clear()

    playerTotalCargoBar:setRange(0, playerShip.maxCargoSpace)
    selfTotalCargoBar:setRange(0, ship.maxCargoSpace)

    -- Save textbox values for restoration
    local playerAmountByIndex = {}
    local selfAmountByIndex = {}
    for cargoName, index in pairs(playerCargoTextBoxByIndex) do
        if playerCargoRows[index] then
            playerAmountByIndex[cargoName] = playerCargoRows[index].textBox.text
        end
    end
    for cargoName, index in pairs(selfCargoTextBoxByIndex) do
        if selfCargoRows[index] then
            selfAmountByIndex[cargoName] = selfCargoRows[index].textBox.text
        end
    end

    playerCargoTextBoxByIndex = {}
    selfCargoTextBoxByIndex = {}

    -- Hide all rows first
    for _, row in pairs(playerCargoRows) do
        GclCargoTab.setRowVisible(row, false)
    end
    for _, row in pairs(selfCargoRows) do
        GclCargoTab.setRowVisible(row, false)
    end

    -- Update player cargo
    for i = 1, playerShip.numCargos do
        local row = playerCargoRows[i]
        if not row then break end

        local good, amount = playerShip:getCargo(i - 1)
        if good and amount then
            GclCargoTab.setRowVisible(row, true)

            playerCargoName[i] = good.name

            -- Determine color and indicator
            local color = COLOR_NORMAL
            local indicator = ""

            if good.stolen then
                color = COLOR_STOLEN
                indicator = "⚠"
            elseif good.illegal then
                color = COLOR_ILLEGAL
                indicator = "!"
            end

            if GclCargoTab.isMissionIngredient(good.name) then
                color = COLOR_MISSION
                indicator = "★"
            end

            row.indicator.caption = indicator
            row.indicator.color = color

            -- Set icon
            row.icon.picture = good.icon

            -- Populate grid columns
            local value = good.price * amount
            local displayName = good:displayName(amount)

            row.nameLabel.caption = displayName
            row.nameLabel.color = color

            row.qtyLabel.caption = "x" .. createMonetaryString(amount)
            row.qtyLabel.color = color

            row.valueLabel.caption = "\194\162" .. createMonetaryString(value) -- ¢ symbol
            row.valueLabel.color = color

            -- Tooltip with full details
            local tooltip = displayName .. "\n"
            tooltip = tooltip .. "Quantity: " .. createMonetaryString(amount) .. "\n"
            tooltip = tooltip .. "Unit Price: " .. createMonetaryString(good.price) .. "\n"
            tooltip = tooltip .. "Total Value: " .. createMonetaryString(value)
            if good.stolen then
                tooltip = tooltip .. "\n\194\167(255,100,100)STOLEN" -- § symbol
            end
            if good.illegal then
                tooltip = tooltip .. "\n\194\167(255,180,0)ILLEGAL"
            end
            if GclCargoTab.isMissionIngredient(good.name) then
                tooltip = tooltip ..
                    "\n\194\167(100,255,150)Mission Ingredient (Need: " .. GclCargoTab.getMissionNeeded(good.name) .. ")"
            end
            row.nameLabel.tooltip = tooltip

            -- Restore textbox value
            if not row.textBox.isTypingActive then
                local boxAmount = GclCargoTab.clampNumberString(playerAmountByIndex[good.name] or tostring(amount),
                    amount)
                playerCargoTextBoxByIndex[good.name] = i
                if boxAmount == "" then
                    row.textBox.text = tostring(amount)
                else
                    row.textBox.text = boxAmount
                end
            end

            -- Update cargo bar
            playerTotalCargoBar:addEntry(amount * good.size, displayName, ColorInt(0xffa0a0a0))
        end
    end

    -- Update self cargo
    for i = 1, ship.numCargos do
        local row = selfCargoRows[i]
        if not row then break end

        local good, amount = ship:getCargo(i - 1)
        if good and amount then
            GclCargoTab.setRowVisible(row, true)

            selfCargoName[i] = good.name

            -- Determine color and indicator
            local color = COLOR_NORMAL
            local indicator = ""

            if good.stolen then
                color = COLOR_STOLEN
                indicator = "⚠"
            elseif good.illegal then
                color = COLOR_ILLEGAL
                indicator = "!"
            end

            if GclCargoTab.isMissionIngredient(good.name) then
                color = COLOR_MISSION
                indicator = "★"
            end

            row.indicator.caption = indicator
            row.indicator.color = color

            -- Set icon
            row.icon.picture = good.icon

            -- Populate grid columns
            local value = good.price * amount
            local displayName = good:displayName(amount)

            row.nameLabel.caption = displayName
            row.nameLabel.color = color

            row.qtyLabel.caption = "x" .. createMonetaryString(amount)
            row.qtyLabel.color = color

            row.valueLabel.caption = "\194\162" .. createMonetaryString(value) -- ¢ symbol
            row.valueLabel.color = color

            -- Tooltip with full details
            local tooltip = displayName .. "\n"
            tooltip = tooltip .. "Quantity: " .. createMonetaryString(amount) .. "\n"
            tooltip = tooltip .. "Unit Price: " .. createMonetaryString(good.price) .. "\n"
            tooltip = tooltip .. "Total Value: " .. createMonetaryString(value)
            if good.stolen then
                tooltip = tooltip .. "\n\194\167(255,100,100)STOLEN"
            end
            if good.illegal then
                tooltip = tooltip .. "\n\194\167(255,180,0)ILLEGAL"
            end
            if GclCargoTab.isMissionIngredient(good.name) then
                tooltip = tooltip ..
                    "\n\194\167(100,255,150)Mission Ingredient (Need: " .. GclCargoTab.getMissionNeeded(good.name) .. ")"
            end
            row.nameLabel.tooltip = tooltip

            -- Restore textbox value
            if not row.textBox.isTypingActive then
                local boxAmount = GclCargoTab.clampNumberString(selfAmountByIndex[good.name] or tostring(amount), amount)
                selfCargoTextBoxByIndex[good.name] = i
                if boxAmount == "" then
                    row.textBox.text = tostring(amount)
                else
                    row.textBox.text = boxAmount
                end
            end

            -- Update cargo bar
            selfTotalCargoBar:addEntry(amount * good.size, displayName, ColorInt(0xffa0a0a0))
        end
    end
end

function GclCargoTab.clampNumberString(str, max)
    if str == "" then return "" end

    local num = tonumber(str)
    if not num then return "" end

    if num > max then num = max end

    return tostring(num)
end

-- Transfer callbacks - delegate to vanilla TransferCrewGoods functions
function GclCargoTab.onPlayerTransferAllCargoPressed(button)
    invokeServerFunction("transferAllCargo", Player().craftIndex, false)
end

function GclCargoTab.onSelfTransferAllCargoPressed(button)
    invokeServerFunction("transferAllCargo", Player().craftIndex, true)
end

function GclCargoTab.onPlayerTransferCargoPressed(button)
    local cargo = cargosByButton[button.index]
    if cargo == nil then return end

    local textboxIndex = textboxIndexByButton[button.index]
    if not textboxIndex then return end

    local box = TextBox(textboxIndex)
    if not box then return end

    local amount = tonumber(box.text) or 0
    if amount == 0 then return end

    invokeServerFunction("transferCargo", cargo - 1, Player().craftIndex, false, amount)
end

function GclCargoTab.onSelfTransferCargoPressed(button)
    local cargo = cargosByButton[button.index]
    if cargo == nil then return end

    local textboxIndex = textboxIndexByButton[button.index]
    if not textboxIndex then return end

    local box = TextBox(textboxIndex)
    if not box then return end

    local amount = tonumber(box.text) or 0
    if amount == 0 then return end

    invokeServerFunction("transferCargo", cargo - 1, Player().craftIndex, true, amount)
end

function GclCargoTab.onPlayerTransferCargoTextEntered(textBox)
    local enteredNumber = tonumber(textBox.text)
    if enteredNumber == nil then
        enteredNumber = 0
    end

    local newNumber = enteredNumber

    local cargoIndex = cargosByTextBox[textBox.index]
    if not cargoIndex then return end

    local sender = Entity(Player().craftIndex)
    local _, maxAmount = sender:getCargo(cargoIndex - 1)

    maxAmount = maxAmount or 0

    if newNumber > maxAmount then
        newNumber = maxAmount
    end

    if newNumber ~= enteredNumber then
        textBox.text = newNumber
    end
end

function GclCargoTab.onSelfTransferCargoTextEntered(textBox)
    local enteredNumber = tonumber(textBox.text)
    if enteredNumber == nil then
        enteredNumber = 0
    end

    local newNumber = enteredNumber

    local cargoIndex = cargosByTextBox[textBox.index]
    if not cargoIndex then return end

    local sender = Entity()
    local good, maxAmount = sender:getCargo(cargoIndex - 1)
    maxAmount = maxAmount or 0

    if newNumber > maxAmount then
        newNumber = maxAmount
    end

    if newNumber ~= enteredNumber then
        textBox.text = newNumber
    end
end

-- Define callbacks on TransferCrewGoods table
-- Avorion looks up callbacks as TransferCrewGoods.xxx when UI is created in this script context
TransferCrewGoods = TransferCrewGoods or {}

TransferCrewGoods.onGclPlayerTransferAllCargoPressed = function(button)
    GclCargoTab.onPlayerTransferAllCargoPressed(button)
end

TransferCrewGoods.onGclSelfTransferAllCargoPressed = function(button)
    GclCargoTab.onSelfTransferAllCargoPressed(button)
end

TransferCrewGoods.onGclPlayerTransferCargoPressed = function(button)
    GclCargoTab.onPlayerTransferCargoPressed(button)
end

TransferCrewGoods.onGclSelfTransferCargoPressed = function(button)
    GclCargoTab.onSelfTransferCargoPressed(button)
end

TransferCrewGoods.onGclPlayerTransferCargoTextEntered = function(textBox)
    GclCargoTab.onPlayerTransferCargoTextEntered(textBox)
end

TransferCrewGoods.onGclSelfTransferCargoTextEntered = function(textBox)
    GclCargoTab.onSelfTransferCargoTextEntered(textBox)
end
