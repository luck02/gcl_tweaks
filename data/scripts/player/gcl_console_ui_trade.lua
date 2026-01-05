-- GCL Console UI - Trade Tab
-- Contains the trade dashboard tab UI building and handlers
-- This file is included by gcl_console.lua

if onClient() then
    -- Build the Trade tab UI (spreadsheet layout)
    function GclConsole.buildTradeTab(tab)
        local tabSize = tab.size

        -- Column definitions (x positions and widths)
        local colStation = { x = 5, w = 170 }  -- Station name
        local colStatus = { x = 180, w = 65 }  -- Health status (NEW)
        local colSector = { x = 250, w = 55 }  -- Sector coords
        local colRevenue = { x = 310, w = 95 } -- Revenue
        local colCosts = { x = 410, w = 95 }   -- Costs
        local colProfit = { x = 510, w = 95 }  -- Profit

        local rowHeight = 22
        local headerY = 5
        local dataStartY = 55          -- After status + header row
        local totalsY = tabSize.y - 35 -- Bottom area for totals

        -- Status label at top left
        GclConsole.tradeStatusLabel = tab:createLabel(
            Rect(5, headerY, colSector.x - 10, headerY + 20),
            "Trade scanning: checking...",
            12
        )

        -- Scan Now button (top right)
        local buttonWidth = 80
        GclConsole.scanNowBtn = tab:createButton(
            Rect(tabSize.x - buttonWidth - 5, headerY, tabSize.x - 5, headerY + 22),
            "Scan Now",
            "onScanNow"
        )
        GclConsole.scanNowBtn.tooltip = "Manually trigger a cross-sector scan"

        -- Cooldown label (below button, right-aligned)
        GclConsole.scanCooldownLabel = tab:createLabel(
            Rect(tabSize.x - buttonWidth - 50, headerY + 24, tabSize.x - 5, headerY + 38),
            "",
            10
        )
        GclConsole.scanCooldownLabel:setRightAligned()
        GclConsole.scanCooldownLabel.color = ColorRGB(0.7, 0.7, 0.7)

        -- Header row (below status line)
        local headerRowY = 30
        GclConsole.tradeHeaderLabels = {}

        local headerFrame = tab:createFrame(Rect(0, headerRowY, tabSize.x, headerRowY + rowHeight))
        headerFrame.backgroundColor = ColorARGB(0.3, 0.3, 0.4, 0.8)

        GclConsole.tradeHeaderLabels.station = tab:createLabel(
            Rect(colStation.x, headerRowY + 2, colStation.x + colStation.w, headerRowY + rowHeight), "Station", 11)
        GclConsole.tradeHeaderLabels.status = tab:createLabel(
            Rect(colStatus.x, headerRowY + 2, colStatus.x + colStatus.w, headerRowY + rowHeight), "Status", 11)
        GclConsole.tradeHeaderLabels.sector = tab:createLabel(
            Rect(colSector.x, headerRowY + 2, colSector.x + colSector.w, headerRowY + rowHeight), "Sector", 11)
        GclConsole.tradeHeaderLabels.revenue = tab:createLabel(
            Rect(colRevenue.x, headerRowY + 2, colRevenue.x + colRevenue.w, headerRowY + rowHeight), "Revenue", 11)
        GclConsole.tradeHeaderLabels.costs = tab:createLabel(
            Rect(colCosts.x, headerRowY + 2, colCosts.x + colCosts.w, headerRowY + rowHeight), "Costs", 11)
        GclConsole.tradeHeaderLabels.profit = tab:createLabel(
            Rect(colProfit.x, headerRowY + 2, colProfit.x + colProfit.w, headerRowY + rowHeight), "Profit", 11)

        -- Right-align numeric headers
        GclConsole.tradeHeaderLabels.revenue:setRightAligned()
        GclConsole.tradeHeaderLabels.costs:setRightAligned()
        GclConsole.tradeHeaderLabels.profit:setRightAligned()

        -- Scroll frame for data rows
        local scrollRect = Rect(0, dataStartY, tabSize.x, totalsY - 5)
        GclConsole.tradeScrollFrame = tab:createScrollFrame(scrollRect)

        -- Pre-allocate row UI elements inside scroll frame
        GclConsole.tradeRows = {}
        for i = 1, GclConsole.MAX_TRADE_ROWS do
            local y = (i - 1) * rowHeight
            local row = {}

            -- Alternating row background
            if i % 2 == 0 then
                row.frame = GclConsole.tradeScrollFrame:createFrame(Rect(0, y, tabSize.x - 20, y + rowHeight))
                row.frame.backgroundColor = ColorARGB(0.15, 0.3, 0.3, 0.4)
            end

            row.nameLabel = GclConsole.tradeScrollFrame:createLabel(
                Rect(colStation.x, y + 2, colStation.x + colStation.w, y + rowHeight), "", 11)
            row.statusLabel = GclConsole.tradeScrollFrame:createLabel(
                Rect(colStatus.x, y + 2, colStatus.x + colStatus.w, y + rowHeight), "", 10)
            row.sectorLabel = GclConsole.tradeScrollFrame:createLabel(
                Rect(colSector.x, y + 2, colSector.x + colSector.w, y + rowHeight), "", 11)
            row.revenueLabel = GclConsole.tradeScrollFrame:createLabel(
                Rect(colRevenue.x, y + 2, colRevenue.x + colRevenue.w, y + rowHeight), "", 11)
            row.costsLabel = GclConsole.tradeScrollFrame:createLabel(
                Rect(colCosts.x, y + 2, colCosts.x + colCosts.w, y + rowHeight), "", 11)
            row.profitLabel = GclConsole.tradeScrollFrame:createLabel(
                Rect(colProfit.x, y + 2, colProfit.x + colProfit.w, y + rowHeight), "", 11)

            -- Right-align numeric columns
            row.revenueLabel:setRightAligned()
            row.costsLabel:setRightAligned()
            row.profitLabel:setRightAligned()

            -- Initially hidden
            row.nameLabel:hide()
            row.statusLabel:hide()
            row.sectorLabel:hide()
            row.revenueLabel:hide()
            row.costsLabel:hide()
            row.profitLabel:hide()
            if row.frame then row.frame:hide() end

            GclConsole.tradeRows[i] = row
        end

        -- Totals row at bottom
        local totalsFrame = tab:createFrame(Rect(0, totalsY, tabSize.x, totalsY + rowHeight + 5))
        totalsFrame.backgroundColor = ColorARGB(0.4, 0.2, 0.4, 0.6)

        GclConsole.tradeTotalsLabels = {}
        GclConsole.tradeTotalsLabels.label = tab:createLabel(
            Rect(colStation.x, totalsY + 3, colSector.x + colSector.w, totalsY + rowHeight), "Totals:", 12)
        GclConsole.tradeTotalsLabels.revenue = tab:createLabel(
            Rect(colRevenue.x, totalsY + 3, colRevenue.x + colRevenue.w, totalsY + rowHeight), "—", 12)
        GclConsole.tradeTotalsLabels.costs = tab:createLabel(
            Rect(colCosts.x, totalsY + 3, colCosts.x + colCosts.w, totalsY + rowHeight), "—", 12)
        GclConsole.tradeTotalsLabels.profit = tab:createLabel(
            Rect(colProfit.x, totalsY + 3, colProfit.x + colProfit.w, totalsY + rowHeight), "—", 12)

        GclConsole.tradeTotalsLabels.revenue:setRightAligned()
        GclConsole.tradeTotalsLabels.costs:setRightAligned()
        GclConsole.tradeTotalsLabels.profit:setRightAligned()

        -- Show initial "waiting" message
        GclConsole.tradeRows[1].nameLabel.caption = "Waiting for scan data..."
        GclConsole.tradeRows[1].nameLabel:show()

        -- Request initial status
        invokeServerFunction("getTradeStatus")
    end

    -- Manual scan button
    function GclConsole.onScanNow()
        -- Ignore if on cooldown (safety check - button should be disabled)
        if GclConsole.scanCooldown > 0 then return end

        -- Start cooldown and disable button
        GclConsole.scanCooldown = GclConsole.SCAN_COOLDOWN_TIME
        if GclConsole.scanNowBtn then
            GclConsole.scanNowBtn.active = false
        end
        if GclConsole.scanCooldownLabel then
            -- Format as "0:nn Seconds"
            local secs = math.ceil(GclConsole.SCAN_COOLDOWN_TIME)
            local mins = math.floor(secs / 60)
            local remainingSecs = secs % 60
            GclConsole.scanCooldownLabel.caption = string.format("%d:%02d Seconds", mins, remainingSecs)
        end

        -- Show scanning message in first row
        for i, row in ipairs(GclConsole.tradeRows) do
            row.nameLabel:hide()
            row.statusLabel:hide()
            row.sectorLabel:hide()
            row.revenueLabel:hide()
            row.costsLabel:hide()
            row.profitLabel:hide()
            if row.frame then row.frame:hide() end
        end
        GclConsole.tradeRows[1].nameLabel.caption = "Scanning all sectors..."
        GclConsole.tradeRows[1].nameLabel:show()

        invokeServerFunction("scanAllStations")
    end

    -- Receive status update from server
    function GclConsole.receiveTradeStatus(enabled, stationCount)
        if GclConsole.tradeStatusLabel then
            if enabled then
                GclConsole.tradeStatusLabel.caption = string.format(
                    "Scanning: ON (%d)",
                    stationCount or 0
                )
                GclConsole.tradeStatusLabel.color = ColorRGB(0.3, 1.0, 0.3) -- green
            else
                GclConsole.tradeStatusLabel.caption = "Scanning: OFF"
                GclConsole.tradeStatusLabel.color = ColorRGB(1.0, 0.5, 0.3) -- orange
            end
        end
    end

    -- Receive cross-sector scan results from server
    function GclConsole.receiveAllStationsStats(results)
        if not GclConsole.tradeRows or #GclConsole.tradeRows == 0 then return end

        -- Format currency helper (uses Avorion's built-in formatting with thousand separators)
        local function formatMoney(amount)
            return "¢" .. createMonetaryString(math.floor(amount or 0))
        end

        -- Sort stations by profit descending
        table.sort(results.stations, function(a, b)
            local profitA = a.moneyGained + a.moneyTax - a.moneySpent
            local profitB = b.moneyGained + b.moneyTax - b.moneySpent
            return profitA > profitB
        end)

        -- Populate rows
        for i, row in ipairs(GclConsole.tradeRows) do
            if i <= #results.stations then
                local station = results.stations[i]
                local profit = station.moneyGained + station.moneyTax - station.moneySpent

                row.nameLabel.caption = station.name or "Unknown"
                row.sectorLabel.caption = string.format("%d:%d", station.x or 0, station.y or 0)
                row.revenueLabel.caption = formatMoney(station.moneyGained)
                row.costsLabel.caption = formatMoney(station.moneySpent)
                row.profitLabel.caption = formatMoney(profit)

                -- Status display with color coding
                local status = station.status or "HEALTHY"
                local statusIssue = station.statusIssue or ""
                if status == "HALTED" then
                    row.statusLabel.caption = "HALTED"
                    row.statusLabel.color = ColorRGB(1.0, 0.3, 0.3) -- red
                elseif status == "IDLE" then
                    row.statusLabel.caption = "IDLE"
                    row.statusLabel.color = ColorRGB(1.0, 0.6, 0.2) -- orange
                elseif status == "WARNING" then
                    row.statusLabel.caption = "WARNING"
                    row.statusLabel.color = ColorRGB(1.0, 0.8, 0.2) -- yellow
                else
                    row.statusLabel.caption = "OK"
                    row.statusLabel.color = ColorRGB(0.3, 1.0, 0.3) -- green
                end
                -- Add tooltip with issue details if present
                if statusIssue ~= "" then
                    row.statusLabel.tooltip = statusIssue
                else
                    row.statusLabel.tooltip = nil
                end

                -- Color-code profit
                if profit >= 0 then
                    row.profitLabel.color = ColorRGB(0.3, 1.0, 0.3) -- green
                else
                    row.profitLabel.color = ColorRGB(1.0, 0.3, 0.3) -- red
                end

                row.nameLabel:show()
                row.statusLabel:show()
                row.sectorLabel:show()
                row.revenueLabel:show()
                row.costsLabel:show()
                row.profitLabel:show()
                if row.frame then row.frame:show() end
            else
                -- Hide unused rows
                row.nameLabel:hide()
                row.statusLabel:hide()
                row.sectorLabel:hide()
                row.revenueLabel:hide()
                row.costsLabel:hide()
                row.profitLabel:hide()
                if row.frame then row.frame:hide() end
            end
        end

        -- Update totals
        local totalRevenue = results.totals.moneyGained or 0
        local totalCosts = results.totals.moneySpent or 0
        local totalProfit = totalRevenue + (results.totals.moneyTax or 0) - totalCosts

        if GclConsole.tradeTotalsLabels then
            GclConsole.tradeTotalsLabels.revenue.caption = formatMoney(totalRevenue)
            GclConsole.tradeTotalsLabels.costs.caption = formatMoney(totalCosts)
            GclConsole.tradeTotalsLabels.profit.caption = formatMoney(totalProfit)

            -- Color-code total profit
            if totalProfit >= 0 then
                GclConsole.tradeTotalsLabels.profit.color = ColorRGB(0.3, 1.0, 0.3)
            else
                GclConsole.tradeTotalsLabels.profit.color = ColorRGB(1.0, 0.3, 0.3)
            end
        end

        -- Update status label
        if GclConsole.tradeStatusLabel then
            GclConsole.tradeStatusLabel.caption = string.format(
                "Scanned: %d stations",
                #results.stations
            )
            GclConsole.tradeStatusLabel.color = ColorRGB(0.3, 1.0, 0.3)
        end
    end
end
