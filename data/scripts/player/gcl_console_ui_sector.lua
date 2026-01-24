-- GCL Console UI - Sector Tab
-- Contains the sector diagnostics tab UI building and handlers
-- This file is included by gcl_console.lua

if onClient() then
    -- Build the Sector tab UI (detailed in-sector diagnostics)
    function GclConsole.buildSectorTab(tab)
        local tabSize = tab.size

        -- Column definitions (adjusted widths for target button)
        local colStation = { x = 5, w = 110 }       -- Station name (narrower)
        local colStatus = { x = 120, w = 55 }       -- Status
        local colCargo = { x = 180, w = 45 }        -- Cargo %
        local colLines = { x = 230, w = 40 }        -- Lines active
        local colIngredients = { x = 275, w = 280 } -- Missing ingredients
        local colTarget = { x = 560, w = 30 }       -- Target button

        local rowHeight = 22
        local headerY = 5
        local dataStartY = 55

        -- Status label at top left
        GclConsole.sectorStatusLabel = tab:createLabel(
            Rect(5, headerY, 300, headerY + 20),
            "Click 'Scan Sector' to analyze local factories",
            12
        )
        GclConsole.sectorStatusLabel.color = ColorRGB(0.7, 0.7, 0.7)

        -- Scan Sector button (top right)
        local buttonWidth = 100
        GclConsole.sectorScanBtn = tab:createButton(
            Rect(tabSize.x - buttonWidth - 5, headerY, tabSize.x - 5, headerY + 22),
            "Scan Sector",
            "onScanSector"
        )
        GclConsole.sectorScanBtn.tooltip = "Query detailed diagnostics for owned factories in current sector"

        -- Cooldown label
        GclConsole.sectorCooldownLabel = tab:createLabel(
            Rect(tabSize.x - buttonWidth - 50, headerY + 24, tabSize.x - 5, headerY + 38),
            "",
            10
        )
        GclConsole.sectorCooldownLabel:setRightAligned()
        GclConsole.sectorCooldownLabel.color = ColorRGB(0.7, 0.7, 0.7)

        -- Header row
        local headerRowY = 30
        GclConsole.sectorHeaderLabels = {}

        local headerFrame = tab:createFrame(Rect(0, headerRowY, tabSize.x, headerRowY + rowHeight))
        headerFrame.backgroundColor = ColorARGB(0.3, 0.3, 0.4, 0.8)

        GclConsole.sectorHeaderLabels.station = tab:createLabel(
            Rect(colStation.x, headerRowY + 2, colStation.x + colStation.w, headerRowY + rowHeight), "Station", 11)
        GclConsole.sectorHeaderLabels.status = tab:createLabel(
            Rect(colStatus.x, headerRowY + 2, colStatus.x + colStatus.w, headerRowY + rowHeight), "Status", 11)
        GclConsole.sectorHeaderLabels.cargo = tab:createLabel(
            Rect(colCargo.x, headerRowY + 2, colCargo.x + colCargo.w, headerRowY + rowHeight), "Cargo", 11)
        GclConsole.sectorHeaderLabels.lines = tab:createLabel(
            Rect(colLines.x, headerRowY + 2, colLines.x + colLines.w, headerRowY + rowHeight), "Lines", 11)
        GclConsole.sectorHeaderLabels.ingredients = tab:createLabel(
            Rect(colIngredients.x, headerRowY + 2, colIngredients.x + colIngredients.w, headerRowY + rowHeight),
            "Missing Ingredients", 11)

        -- Scroll frame for data rows
        local scrollRect = Rect(0, dataStartY, tabSize.x, tabSize.y - 10)
        GclConsole.sectorScrollFrame = tab:createScrollFrame(scrollRect)

        -- Pre-allocate row UI elements
        GclConsole.sectorRows = {}
        for i = 1, GclConsole.MAX_SECTOR_ROWS do
            local y = (i - 1) * rowHeight
            local row = {}

            -- Alternating row background
            if i % 2 == 0 then
                row.frame = GclConsole.sectorScrollFrame:createFrame(Rect(0, y, tabSize.x - 20, y + rowHeight))
                row.frame.backgroundColor = ColorARGB(0.15, 0.2, 0.3, 0.5)
            end

            -- Create labels
            row.nameLabel = GclConsole.sectorScrollFrame:createLabel(
                Rect(colStation.x, y + 2, colStation.x + colStation.w, y + rowHeight), "", 10)
            row.statusLabel = GclConsole.sectorScrollFrame:createLabel(
                Rect(colStatus.x, y + 2, colStatus.x + colStatus.w, y + rowHeight), "", 10)
            row.cargoLabel = GclConsole.sectorScrollFrame:createLabel(
                Rect(colCargo.x, y + 2, colCargo.x + colCargo.w, y + rowHeight), "", 10)
            row.linesLabel = GclConsole.sectorScrollFrame:createLabel(
                Rect(colLines.x, y + 2, colLines.x + colLines.w, y + rowHeight), "", 10)
            row.ingredientsLabel = GclConsole.sectorScrollFrame:createLabel(
                Rect(colIngredients.x, y + 2, colIngredients.x + colIngredients.w, y + rowHeight), "", 10)

            -- Target button
            row.targetBtn = GclConsole.sectorScrollFrame:createButton(
                Rect(colTarget.x, y + 1, colTarget.x + colTarget.w, y + rowHeight - 1),
                "", "onSectorTargetStation"
            )
            row.targetBtn.icon = "data/textures/icons/position-marker.png"
            row.targetBtn.tooltip = "Target this station"

            -- Storage for entity ID (set when diagnostics are received)
            row.entityId = nil

            -- Initially hidden
            row.nameLabel:hide()
            row.statusLabel:hide()
            row.cargoLabel:hide()
            row.linesLabel:hide()
            row.ingredientsLabel:hide()
            row.targetBtn:hide()
            if row.frame then row.frame:hide() end

            GclConsole.sectorRows[i] = row
        end
    end

    -- Scan sector button handler
    function GclConsole.onScanSector()
        -- Ignore if on cooldown
        if GclConsole.sectorCooldown > 0 then return end

        -- Start cooldown and disable button
        GclConsole.sectorCooldown = GclConsole.SECTOR_COOLDOWN_TIME
        if GclConsole.sectorScanBtn then
            GclConsole.sectorScanBtn.active = false
        end

        -- Show scanning message
        if GclConsole.sectorStatusLabel then
            GclConsole.sectorStatusLabel.caption = "Scanning sector..."
            GclConsole.sectorStatusLabel.color = ColorRGB(1.0, 1.0, 0.3) -- yellow
        end

        -- Hide all rows and show scanning message
        for i, row in ipairs(GclConsole.sectorRows) do
            if row.nameLabel then row.nameLabel:hide() end
            if row.statusLabel then row.statusLabel:hide() end
            if row.cargoLabel then row.cargoLabel:hide() end
            if row.linesLabel then row.linesLabel:hide() end
            if row.ingredientsLabel then row.ingredientsLabel:hide() end
            if row.targetBtn then row.targetBtn:hide() end
            if row.frame then row.frame:hide() end
            row.entityId = nil -- Clear saved entity ID
        end

        invokeServerFunction("getInSectorDiagnostics")
    end

    -- Receive detailed diagnostics for in-sector stations (populates Sector tab)
    function GclConsole.receiveSectorDiagnostics(diagnostics)
        local diagList = {}

        -- Convert diagnostics map to array for display
        for stationName, diag in pairs(diagnostics or {}) do
            table.insert(diagList, diag)
        end

        -- Update status label
        if GclConsole.sectorStatusLabel then
            if #diagList > 0 then
                GclConsole.sectorStatusLabel.caption = string.format("Found %d factory stations", #diagList)
                GclConsole.sectorStatusLabel.color = ColorRGB(0.3, 1.0, 0.3) -- green
            else
                GclConsole.sectorStatusLabel.caption = "No owned factories in this sector"
                GclConsole.sectorStatusLabel.color = ColorRGB(0.7, 0.7, 0.7) -- gray
            end
        end

        -- Populate rows
        for i, row in ipairs(GclConsole.sectorRows) do
            if i <= #diagList then
                local diag = diagList[i]

                -- Station name
                row.nameLabel.caption = diag.name or "Unknown"

                -- Status with color
                local status = "OK"
                local statusColor = ColorRGB(0.3, 1.0, 0.3) -- green
                if diag.issue == "Missing ingredients" then
                    status = "HALTED"
                    statusColor = ColorRGB(1.0, 0.3, 0.3) -- red
                elseif diag.issue == "Cargo nearly full" then
                    status = "WARNING"
                    statusColor = ColorRGB(1.0, 0.8, 0.2) -- yellow
                elseif diag.activeProductions == 0 and diag.maxProductions and diag.maxProductions > 0 then
                    status = "IDLE"
                    statusColor = ColorRGB(1.0, 0.6, 0.2) -- orange
                end
                row.statusLabel.caption = status
                row.statusLabel.color = statusColor

                -- Cargo percentage
                row.cargoLabel.caption = string.format("%d%%", diag.cargoFillPercent or 0)
                if diag.cargoFillPercent and diag.cargoFillPercent > 90 then
                    row.cargoLabel.color = ColorRGB(1.0, 0.5, 0.2) -- orange-ish
                else
                    row.cargoLabel.color = ColorRGB(0.8, 0.8, 0.8)
                end

                -- Production lines
                local activeLines = diag.activeProductions or 0
                local maxLines = diag.maxProductions or 0
                row.linesLabel.caption = string.format("%d/%d", activeLines, maxLines)

                -- Missing ingredients (compact format)
                local missingList = {}
                for _, ing in ipairs(diag.ingredients or {}) do
                    if not ing.optional and ing.have < ing.need then
                        table.insert(missingList, string.format("%s (%d/%d)", ing.name, ing.have, ing.need))
                    end
                end
                if #missingList > 0 then
                    row.ingredientsLabel.caption = table.concat(missingList, ", ")
                    row.ingredientsLabel.color = ColorRGB(1.0, 0.5, 0.5) -- light red
                else
                    row.ingredientsLabel.caption = "—"
                    row.ingredientsLabel.color = ColorRGB(0.6, 0.6, 0.6)
                end

                -- Store entity ID for targeting
                row.entityId = diag.entityId

                -- Show row
                row.nameLabel:show()
                row.statusLabel:show()
                row.cargoLabel:show()
                row.linesLabel:show()
                row.ingredientsLabel:show()
                if row.targetBtn then row.targetBtn:show() end
                if row.frame then row.frame:show() end
            else
                -- Hide unused rows
                row.entityId = nil
                if row.nameLabel then row.nameLabel:hide() end
                if row.statusLabel then row.statusLabel:hide() end
                if row.cargoLabel then row.cargoLabel:hide() end
                if row.linesLabel then row.linesLabel:hide() end
                if row.ingredientsLabel then row.ingredientsLabel:hide() end
                if row.targetBtn then row.targetBtn:hide() end
                if row.frame then row.frame:hide() end
            end
        end
    end

    -- Target station button handler
    function GclConsole.onSectorTargetStation(button)
        -- Find which row this button belongs to
        for i, row in ipairs(GclConsole.sectorRows) do
            if row.targetBtn and row.targetBtn.index == button.index then
                if row.entityId then
                    -- Target the station using numerical index (works for non-host clients)
                    local entity = Entity(row.entityId)
                    if valid(entity) then
                        Player().selectedObject = entity
                    end
                end
                return
            end
        end
    end
end
