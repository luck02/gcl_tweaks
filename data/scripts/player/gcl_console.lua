-- GCL Console - Client-side output window with tabbed interface
-- Displays output from /gcl_tweak commands in a scrollable window
-- Toggle visibility with F9
-- Uses AzimuthLib CustomTabbedWindow for tabbed UI
-- Uses direct RPC (invokeClientFunction) for server-to-client data transfer

package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")

-- AzimuthLib for tabbed window (workaround for buggy native TabbedWindow in Hud context)
local CustomTabbedWindow = include("azimuthlib-customtabbedwindow")

-- AzimuthLib basic for config persistence (setValue can't store tables)
local Azimuth = include("azimuthlib-basic")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in.
-- namespace GclConsole
GclConsole = {}

-- Configuration
local WINDOW_WIDTH = 700
local WINDOW_HEIGHT = 500

-- UI elements (client-only)
local window = nil
local tabbedWindow = nil
local consoleTab = nil
local tradeTab = nil
local listBox = nil
local clearButton = nil

-- Trade tab UI elements (spreadsheet layout)
local tradeStatusLabel = nil
local scanNowBtn = nil
local scanCooldownLabel = nil -- Shows countdown below button
local tradeScrollFrame = nil
local tradeRows = {}          -- Array of {frame, nameLabel, sectorLabel, revenueLabel, costsLabel, profitLabel}
local tradeHeaderLabels = {}  -- Column headers
local tradeTotalsLabels = {}  -- Totals row labels
local MAX_TRADE_ROWS = 20     -- Maximum visible rows before scrolling
local SCAN_COOLDOWN_TIME = 60 -- 60 seconds cooldown after scan
local scanCooldown = 0        -- Remaining cooldown time

-- CLIENT-SIDE IMPLEMENTATION
if onClient() then
    local TOGGLE_KEY = KeyboardKey.F9

    -- Initialize the UI
    function GclConsole.initUI()
        if window then return end -- Already initialized

        local res = getResolution()
        local size = vec2(WINDOW_WIDTH, WINDOW_HEIGHT)

        -- Create window in top-right area
        window = Hud():createWindow(Rect(res.x - size.x - 20, 100, res.x - 20, 100 + size.y))
        window.caption = "GCL Console"
        window.showCloseButton = true
        window.moveable = true

        -- Create CustomTabbedWindow using AzimuthLib
        -- This works around the buggy native TabbedWindow in Hud context
        tabbedWindow = CustomTabbedWindow(GclConsole, window, Rect(vec2(5, 5), size - vec2(15, 15)))

        -- Set up tab selection callback for persistence
        tabbedWindow.onSelectedFunction = "onTabSelected"

        -- Create Console tab
        consoleTab = tabbedWindow:createTab("Console", "data/textures/icons/info.png", "Command Output")
        GclConsole.buildConsoleTab(consoleTab)

        -- Create Trade tab
        tradeTab = tabbedWindow:createTab("Trade", "data/textures/icons/money.png", "Trade Statistics")
        GclConsole.buildTradeTab(tradeTab)

        -- Restore saved tab selection (default to Trade)
        local savedTab = Player():getValue("gcl_console_tab") or "Trade"
        local tabToSelect = tabbedWindow:getTab(savedTab)
        if tabToSelect then
            tabbedWindow:selectTab(tabToSelect)
        end

        -- Start hidden
        window:hide()

        print("[GCL Console] Tabbed UI initialized. Press F9 to toggle visibility.")
    end

    -- Tab selection callback - save preference
    function GclConsole.onTabSelected(tab)
        -- Guard: Player() can return nil or partial object during early initialization
        -- when createTab triggers this callback before the player is fully available
        local ok, err = pcall(function()
            local player = Player()
            if tab and tab.name and player and player.setValue then
                player:setValue("gcl_console_tab", tab.name)
            end
        end)
        -- Silently ignore errors during initialization
    end

    -- Build the Console tab UI
    function GclConsole.buildConsoleTab(tab)
        local tabSize = tab.size

        -- Create scrollable ListBox for output (leave room for button at bottom)
        listBox = tab:createListBox(Rect(vec2(0, 0), vec2(tabSize.x, tabSize.y - 40)))
        listBox.fontSize = 12

        -- Create clear button at bottom
        clearButton = tab:createButton(
            Rect(0, tabSize.y - 35, 100, tabSize.y - 5),
            "Clear",
            "onClearPressed"
        )
    end

    -- Build the Trade tab UI (spreadsheet layout)
    function GclConsole.buildTradeTab(tab)
        local tabSize = tab.size

        -- Column definitions (x positions and widths)
        local colStation = { x = 5, w = 220 }   -- Station name
        local colSector = { x = 230, w = 60 }   -- Sector coords
        local colRevenue = { x = 295, w = 100 } -- Revenue
        local colCosts = { x = 400, w = 100 }   -- Costs
        local colProfit = { x = 505, w = 100 }  -- Profit

        local rowHeight = 22
        local headerY = 5
        local dataStartY = 55          -- After status + header row
        local totalsY = tabSize.y - 35 -- Bottom area for totals

        -- Status label at top left
        tradeStatusLabel = tab:createLabel(
            Rect(5, headerY, colSector.x - 10, headerY + 20),
            "Trade scanning: checking...",
            12
        )

        -- Scan Now button (top right)
        local buttonWidth = 80
        scanNowBtn = tab:createButton(
            Rect(tabSize.x - buttonWidth - 5, headerY, tabSize.x - 5, headerY + 22),
            "Scan Now",
            "onScanNow"
        )
        scanNowBtn.tooltip = "Manually trigger a cross-sector scan"

        -- Cooldown label (below button, right-aligned)
        scanCooldownLabel = tab:createLabel(
            Rect(tabSize.x - buttonWidth - 50, headerY + 24, tabSize.x - 5, headerY + 38),
            "",
            10
        )
        scanCooldownLabel:setRightAligned()
        scanCooldownLabel.color = ColorRGB(0.7, 0.7, 0.7)

        -- Header row (below status line)
        local headerRowY = 30
        tradeHeaderLabels = {}

        local headerFrame = tab:createFrame(Rect(0, headerRowY, tabSize.x, headerRowY + rowHeight))
        headerFrame.backgroundColor = ColorARGB(0.3, 0.3, 0.4, 0.8)

        tradeHeaderLabels.station = tab:createLabel(
            Rect(colStation.x, headerRowY + 2, colStation.x + colStation.w, headerRowY + rowHeight), "Station", 11)
        tradeHeaderLabels.sector = tab:createLabel(
            Rect(colSector.x, headerRowY + 2, colSector.x + colSector.w, headerRowY + rowHeight), "Sector", 11)
        tradeHeaderLabels.revenue = tab:createLabel(
            Rect(colRevenue.x, headerRowY + 2, colRevenue.x + colRevenue.w, headerRowY + rowHeight), "Revenue", 11)
        tradeHeaderLabels.costs = tab:createLabel(
            Rect(colCosts.x, headerRowY + 2, colCosts.x + colCosts.w, headerRowY + rowHeight), "Costs", 11)
        tradeHeaderLabels.profit = tab:createLabel(
            Rect(colProfit.x, headerRowY + 2, colProfit.x + colProfit.w, headerRowY + rowHeight), "Profit", 11)

        -- Right-align numeric headers
        tradeHeaderLabels.revenue:setRightAligned()
        tradeHeaderLabels.costs:setRightAligned()
        tradeHeaderLabels.profit:setRightAligned()

        -- Scroll frame for data rows
        local scrollRect = Rect(0, dataStartY, tabSize.x, totalsY - 5)
        tradeScrollFrame = tab:createScrollFrame(scrollRect)

        -- Pre-allocate row UI elements inside scroll frame
        tradeRows = {}
        for i = 1, MAX_TRADE_ROWS do
            local y = (i - 1) * rowHeight
            local row = {}

            -- Alternating row background
            if i % 2 == 0 then
                row.frame = tradeScrollFrame:createFrame(Rect(0, y, tabSize.x - 20, y + rowHeight))
                row.frame.backgroundColor = ColorARGB(0.15, 0.3, 0.3, 0.4)
            end

            row.nameLabel = tradeScrollFrame:createLabel(
                Rect(colStation.x, y + 2, colStation.x + colStation.w, y + rowHeight), "", 11)
            row.sectorLabel = tradeScrollFrame:createLabel(
                Rect(colSector.x, y + 2, colSector.x + colSector.w, y + rowHeight), "", 11)
            row.revenueLabel = tradeScrollFrame:createLabel(
                Rect(colRevenue.x, y + 2, colRevenue.x + colRevenue.w, y + rowHeight), "", 11)
            row.costsLabel = tradeScrollFrame:createLabel(
                Rect(colCosts.x, y + 2, colCosts.x + colCosts.w, y + rowHeight), "", 11)
            row.profitLabel = tradeScrollFrame:createLabel(
                Rect(colProfit.x, y + 2, colProfit.x + colProfit.w, y + rowHeight), "", 11)

            -- Right-align numeric columns
            row.revenueLabel:setRightAligned()
            row.costsLabel:setRightAligned()
            row.profitLabel:setRightAligned()

            -- Initially hidden
            row.nameLabel:hide()
            row.sectorLabel:hide()
            row.revenueLabel:hide()
            row.costsLabel:hide()
            row.profitLabel:hide()
            if row.frame then row.frame:hide() end

            tradeRows[i] = row
        end

        -- Totals row at bottom
        local totalsFrame = tab:createFrame(Rect(0, totalsY, tabSize.x, totalsY + rowHeight + 5))
        totalsFrame.backgroundColor = ColorARGB(0.4, 0.2, 0.4, 0.6)

        tradeTotalsLabels = {}
        tradeTotalsLabels.label = tab:createLabel(
            Rect(colStation.x, totalsY + 3, colSector.x + colSector.w, totalsY + rowHeight), "Totals:", 12)
        tradeTotalsLabels.revenue = tab:createLabel(
            Rect(colRevenue.x, totalsY + 3, colRevenue.x + colRevenue.w, totalsY + rowHeight), "—", 12)
        tradeTotalsLabels.costs = tab:createLabel(
            Rect(colCosts.x, totalsY + 3, colCosts.x + colCosts.w, totalsY + rowHeight), "—", 12)
        tradeTotalsLabels.profit = tab:createLabel(
            Rect(colProfit.x, totalsY + 3, colProfit.x + colProfit.w, totalsY + rowHeight), "—", 12)

        tradeTotalsLabels.revenue:setRightAligned()
        tradeTotalsLabels.costs:setRightAligned()
        tradeTotalsLabels.profit:setRightAligned()

        -- Show initial "waiting" message
        tradeRows[1].nameLabel.caption = "Waiting for scan data..."
        tradeRows[1].nameLabel:show()

        -- Request initial status
        invokeServerFunction("getTradeStatus")
    end

    -- Get the parent player index (required for player scripts)
    function GclConsole.getParentIndex()
        return Player().index
    end

    function GclConsole.initialize()
        -- Initialize UI on client start
        GclConsole.initUI()
    end

    -- Key debounce state
    local wasKeyDown = false
    local keyCooldown = 0
    local KEY_COOLDOWN_TIME = 0.3 -- 300ms cooldown between toggles

    -- Called every frame on client
    function GclConsole.updateClient(timestep)
        -- Update key cooldown
        if keyCooldown > 0 then
            keyCooldown = keyCooldown - timestep
        end

        -- Update scan button cooldown
        if scanCooldown > 0 then
            scanCooldown = scanCooldown - timestep
            -- Update button and label state
            if scanCooldown <= 0 then
                if scanNowBtn then
                    scanNowBtn.active = true
                end
                if scanCooldownLabel then
                    scanCooldownLabel.caption = ""
                end
            else
                -- Format as "0:nn Seconds"
                local secs = math.ceil(scanCooldown)
                local mins = math.floor(secs / 60)
                local remainingSecs = secs % 60
                if scanCooldownLabel then
                    scanCooldownLabel.caption = string.format("%d:%02d Seconds", mins, remainingSecs)
                end
            end
        end

        -- Handle F9 toggle with debounce
        local isKeyDown = Keyboard():keyPressed(TOGGLE_KEY)
        if isKeyDown and not wasKeyDown and keyCooldown <= 0 then
            GclConsole.toggle()
            keyCooldown = KEY_COOLDOWN_TIME
        end
        wasKeyDown = isKeyDown
    end

    -- Receive output from server via direct RPC (called by invokeClientFunction)
    function GclConsole.receiveOutput(text)
        print("[GCL Console] Received data via RPC: " .. tostring(string.len(text)) .. " bytes")

        if not window then
            GclConsole.initUI()
        end
        if not window or not listBox then return end

        -- Show window and switch to Console tab when output arrives
        window:show()
        if tabbedWindow and consoleTab then
            tabbedWindow:selectTab(consoleTab)
        end

        -- Split into lines and add each to the ListBox
        for line in text:gmatch("[^\n]+") do
            listBox:addEntry(line, nil)
        end

        -- Auto-scroll to bottom
        listBox.scrollPosition = math.max(0, listBox.rows - 1)
        listBox:clampScrollPosition()
    end

    -- Toggle visibility
    function GclConsole.toggle()
        GclConsole.initUI()
        if not window then return end

        if window.visible then
            window:hide()
        else
            window:show()
        end
    end

    -- Show the console
    function GclConsole.show()
        GclConsole.initUI()
        if window then window:show() end
    end

    -- Hide the console
    function GclConsole.hide()
        GclConsole.initUI()
        if window then window:hide() end
    end

    -- Called when Clear button is pressed
    function GclConsole.onClearPressed()
        if listBox then
            listBox:clear()
        end
    end

    -- Trade tab button callbacks

    -- Manual scan button
    function GclConsole.onScanNow()
        -- Ignore if on cooldown (safety check - button should be disabled)
        if scanCooldown > 0 then return end

        -- Start cooldown and disable button
        scanCooldown = SCAN_COOLDOWN_TIME
        if scanNowBtn then
            scanNowBtn.active = false
        end
        if scanCooldownLabel then
            -- Format as "0:nn Seconds"
            local secs = math.ceil(SCAN_COOLDOWN_TIME)
            local mins = math.floor(secs / 60)
            local remainingSecs = secs % 60
            scanCooldownLabel.caption = string.format("%d:%02d Seconds", mins, remainingSecs)
        end

        -- Show scanning message in first row
        for i, row in ipairs(tradeRows) do
            row.nameLabel:hide()
            row.sectorLabel:hide()
            row.revenueLabel:hide()
            row.costsLabel:hide()
            row.profitLabel:hide()
            if row.frame then row.frame:hide() end
        end
        tradeRows[1].nameLabel.caption = "Scanning all sectors..."
        tradeRows[1].nameLabel:show()

        invokeServerFunction("scanAllStations")
    end

    -- Receive status update from server
    function GclConsole.receiveTradeStatus(enabled, stationCount)
        if tradeStatusLabel then
            if enabled then
                tradeStatusLabel.caption = string.format(
                    "Scanning: ON (%d)",
                    stationCount or 0
                )
                tradeStatusLabel.color = ColorRGB(0.3, 1.0, 0.3) -- green
            else
                tradeStatusLabel.caption = "Scanning: OFF"
                tradeStatusLabel.color = ColorRGB(1.0, 0.5, 0.3) -- orange
            end
        end
    end

    -- Receive cross-sector scan results from server
    function GclConsole.receiveAllStationsStats(results)
        if not tradeRows or #tradeRows == 0 then return end

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
        for i, row in ipairs(tradeRows) do
            if i <= #results.stations then
                local station = results.stations[i]
                local profit = station.moneyGained + station.moneyTax - station.moneySpent

                row.nameLabel.caption = station.name or "Unknown"
                row.sectorLabel.caption = string.format("%d:%d", station.x or 0, station.y or 0)
                row.revenueLabel.caption = formatMoney(station.moneyGained)
                row.costsLabel.caption = formatMoney(station.moneySpent)
                row.profitLabel.caption = formatMoney(profit)

                -- Color-code profit
                if profit >= 0 then
                    row.profitLabel.color = ColorRGB(0.3, 1.0, 0.3) -- green
                else
                    row.profitLabel.color = ColorRGB(1.0, 0.3, 0.3) -- red
                end

                row.nameLabel:show()
                row.sectorLabel:show()
                row.revenueLabel:show()
                row.costsLabel:show()
                row.profitLabel:show()
                if row.frame then row.frame:show() end
            else
                -- Hide unused rows
                row.nameLabel:hide()
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

        if tradeTotalsLabels then
            tradeTotalsLabels.revenue.caption = formatMoney(totalRevenue)
            tradeTotalsLabels.costs.caption = formatMoney(totalCosts)
            tradeTotalsLabels.profit.caption = formatMoney(totalProfit)

            -- Color-code total profit
            if totalProfit >= 0 then
                tradeTotalsLabels.profit.color = ColorRGB(0.3, 1.0, 0.3)
            else
                tradeTotalsLabels.profit.color = ColorRGB(1.0, 0.3, 0.3)
            end
        end

        -- Update status label
        if tradeStatusLabel then
            tradeStatusLabel.caption = string.format(
                "Scanned: %d stations",
                #results.stations
            )
            tradeStatusLabel.color = ColorRGB(0.3, 1.0, 0.3)
        end
    end
end -- if onClient()

-- SERVER-SIDE IMPLEMENTATION
if onServer() then
    -- Trade data storage key
    local TRADE_STATS_KEY = "gcl_trade_stats"

    -- Scan interval (5 minutes = 300 seconds)
    local SCAN_INTERVAL = 300

    -- Send output to the client via direct RPC
    -- This is called by commands via player:invokeFunction()
    function GclConsole.sendOutput(output)
        -- For player scripts, Player() (no args) returns the owning player
        -- callingPlayer is only set for invokeServerFunction from client
        local player = Player()

        if player then
            invokeClientFunction(player, "receiveOutput", output)
            print("[GCL Console] Sent output to player " .. tostring(player.name) .. " via RPC")
        else
            print("[GCL Console] ERROR: No player found to send output to")
        end
    end

    callable(GclConsole, "sendOutput")

    -- Initialize trade tracking and automatic scanning
    function GclConsole.initialize()
        local player = Player()
        if not player then return end

        -- Register for trading callbacks (keep for local sector trades)
        player:registerCallback("onTradingManagerSellToPlayer", "onTradingManagerSellToPlayer")
        player:registerCallback("onTradingManagerBuyFromPlayer", "onTradingManagerBuyFromPlayer")

        -- Check if automatic scanning is enabled (default: on)
        local enabled = player:getValue("gcl_scantrade_enabled")
        if enabled == nil then enabled = true end

        if enabled then
            -- Schedule first scan 5 minutes after login
            deferredCallback(SCAN_INTERVAL, "performScheduledScan")
            print("[GCL Console] Automatic trade scanning enabled. First scan in " .. SCAN_INTERVAL .. " seconds.")
        else
            print("[GCL Console] Automatic trade scanning disabled.")
        end

        print("[GCL Console] Server-side trade tracking initialized for " .. player.name)
    end

    -- Restart the scan timer (called when user enables scanning via command)
    function GclConsole.restartScanTimer()
        local player = Player()
        if not player then return end

        deferredCallback(SCAN_INTERVAL, "performScheduledScan")
        print("[GCL Console] Scan timer restarted. Next scan in " .. SCAN_INTERVAL .. " seconds.")
    end

    callable(GclConsole, "restartScanTimer")

    -- Scheduled scan callback (called by deferredCallback)
    function performScheduledScan()
        local player = Player()
        if not valid(player) then return end

        -- Check if still enabled
        local enabled = player:getValue("gcl_scantrade_enabled")
        if enabled == nil then enabled = true end

        if enabled then
            -- Perform the scan
            GclConsole.scanAllStations()

            -- Schedule next scan
            deferredCallback(SCAN_INTERVAL, "performScheduledScan")
            print("[GCL Console] Scheduled scan complete. Next scan in " .. SCAN_INTERVAL .. " seconds.")
        else
            print("[GCL Console] Scheduled scan skipped - scanning disabled.")
        end
    end

    -- Scan ALL owned stations across ALL sectors using ShipDatabaseEntry
    function GclConsole.scanAllStations()
        local player = Player()
        if not player then
            player = Player(callingPlayer)
        end
        if not player then return end

        local results = {
            stations = {},
            totals = { moneySpent = 0, moneyGained = 0, moneyTax = 0 }
        }

        -- Collect factions to scan (player and optionally alliance)
        local factions = { player }
        if player.alliance then
            table.insert(factions, player.alliance)
        end

        for _, faction in pairs(factions) do
            local shipNames = { faction:getShipNames() }
            for _, name in pairs(shipNames) do
                if faction:getShipType(name) == EntityType.Station then
                    local entry = ShipDatabaseEntry(faction.index, name)
                    local x, y = entry:getCoordinates()
                    local secured = entry:getSecuredScriptValues()

                    local stationStats = {
                        name = name,
                        x = x,
                        y = y,
                        moneySpent = 0,
                        moneyGained = 0,
                        moneyTax = 0
                    }

                    -- Find trading scripts and extract stats
                    for scriptIndex, values in pairs(secured or {}) do
                        local stats = nil
                        -- Check various data structures used by different scripts
                        if values.tradingData and values.tradingData.stats then
                            stats = values.tradingData.stats
                        elseif values.stats then
                            stats = values.stats
                        end

                        if stats then
                            stationStats.moneySpent = stationStats.moneySpent + (stats.moneySpentOnGoods or 0)
                            stationStats.moneyGained = stationStats.moneyGained + (stats.moneyGainedFromGoods or 0)
                            stationStats.moneyTax = stationStats.moneyTax + (stats.moneyGainedFromTax or 0)
                        end
                    end

                    -- Only include stations with trading activity
                    if stationStats.moneySpent > 0 or stationStats.moneyGained > 0 then
                        results.totals.moneySpent = results.totals.moneySpent + stationStats.moneySpent
                        results.totals.moneyGained = results.totals.moneyGained + stationStats.moneyGained
                        results.totals.moneyTax = results.totals.moneyTax + stationStats.moneyTax
                        table.insert(results.stations, stationStats)
                    end
                end
            end
        end

        print(string.format("[GCL Console] Cross-sector scan: found %d stations with trade data", #results.stations))
        invokeClientFunction(player, "receiveAllStationsStats", results)
    end

    callable(GclConsole, "scanAllStations")

    -- Get trade status for client
    function GclConsole.getTradeStatus()
        local player = Player()
        if not player then
            player = Player(callingPlayer)
        end
        if not player then return end

        local enabled = player:getValue("gcl_scantrade_enabled")
        if enabled == nil then enabled = true end

        -- Count stations (quick count without full scan)
        local stationCount = 0
        local factions = { player }
        if player.alliance then
            table.insert(factions, player.alliance)
        end

        for _, faction in pairs(factions) do
            local shipNames = { faction:getShipNames() }
            for _, name in pairs(shipNames) do
                if faction:getShipType(name) == EntityType.Station then
                    stationCount = stationCount + 1
                end
            end
        end

        invokeClientFunction(player, "receiveTradeStatus", enabled, stationCount)
    end

    callable(GclConsole, "getTradeStatus")

    -- Get current trade stats from player-specific config file
    function GclConsole.getTradeStats()
        local player = Player()
        if not player then return {} end

        -- Use player name in config file for per-player stats
        local configName = "gcl_trade_stats_" .. tostring(player.index)
        local defaults = {
            byStation = {},
            byGood = {},
            stationHistory = {},
            totals = {
                totalRevenue = 0,
                totalCost = 0,
                totalProfit = 0,
                tradeCount = 0
            }
        }

        -- Load using AzimuthLib - handles Table serialization
        local stats = Azimuth.loadConfig(configName, defaults)

        -- Ensure all required fields exist (loadConfig may not deep-merge defaults)
        stats = stats or {}
        stats.byStation = stats.byStation or {}
        stats.byGood = stats.byGood or {}
        stats.stationHistory = stats.stationHistory or {}
        stats.totals = stats.totals or {}
        stats.totals.totalRevenue = stats.totals.totalRevenue or 0
        stats.totals.totalCost = stats.totals.totalCost or 0
        stats.totals.totalProfit = stats.totals.totalProfit or 0
        stats.totals.tradeCount = stats.totals.tradeCount or 0

        return stats
    end

    -- Save trade stats to player-specific config file
    function GclConsole.saveTradeStats(stats)
        local player = Player()
        if not player then return end

        local configName = "gcl_trade_stats_" .. tostring(player.index)
        Azimuth.saveConfig(configName, stats)
    end

    -- Record a sale (station sold to player = player revenue when player resells)
    -- This is called when a station SELLS goods TO the player
    -- From player's trading perspective: player BOUGHT goods (expense)
    function GclConsole.recordPurchase(goodName, amount, price, stationName)
        local stats = GclConsole.getTradeStats()

        -- Update by-good stats
        if not stats.byGood[goodName] then
            stats.byGood[goodName] = {
                bought = 0,
                sold = 0,
                spent = 0,
                earned = 0
            }
        end
        stats.byGood[goodName].bought = stats.byGood[goodName].bought + amount
        stats.byGood[goodName].spent = stats.byGood[goodName].spent + price

        -- Update by-station stats
        if stationName and stationName ~= "" then
            if not stats.byStation[stationName] then
                stats.byStation[stationName] = {
                    bought = 0,
                    sold = 0,
                    spent = 0,
                    earned = 0,
                    goods = {}
                }
            end
            stats.byStation[stationName].bought = stats.byStation[stationName].bought + amount
            stats.byStation[stationName].spent = stats.byStation[stationName].spent + price

            -- Track goods per station
            if not stats.byStation[stationName].goods[goodName] then
                stats.byStation[stationName].goods[goodName] = { bought = 0, sold = 0, spent = 0, earned = 0 }
            end
            stats.byStation[stationName].goods[goodName].bought = stats.byStation[stationName].goods[goodName].bought +
                amount
            stats.byStation[stationName].goods[goodName].spent = stats.byStation[stationName].goods[goodName].spent +
                price
        end

        -- Update totals
        stats.totals.totalCost = stats.totals.totalCost + price
        stats.totals.totalProfit = stats.totals.totalRevenue - stats.totals.totalCost
        stats.totals.tradeCount = stats.totals.tradeCount + 1

        GclConsole.saveTradeStats(stats)
    end

    -- Record a purchase (station bought from player = player sold goods)
    -- This is called when a station BUYS goods FROM the player
    -- From player's trading perspective: player SOLD goods (revenue)
    function GclConsole.recordSale(goodName, amount, price, stationName)
        local stats = GclConsole.getTradeStats()

        -- Update by-good stats
        if not stats.byGood[goodName] then
            stats.byGood[goodName] = {
                bought = 0,
                sold = 0,
                spent = 0,
                earned = 0
            }
        end
        stats.byGood[goodName].sold = stats.byGood[goodName].sold + amount
        stats.byGood[goodName].earned = stats.byGood[goodName].earned + price

        -- Update by-station stats
        if stationName and stationName ~= "" then
            if not stats.byStation[stationName] then
                stats.byStation[stationName] = {
                    bought = 0,
                    sold = 0,
                    spent = 0,
                    earned = 0,
                    goods = {}
                }
            end
            stats.byStation[stationName].sold = stats.byStation[stationName].sold + amount
            stats.byStation[stationName].earned = stats.byStation[stationName].earned + price

            -- Track goods per station
            if not stats.byStation[stationName].goods[goodName] then
                stats.byStation[stationName].goods[goodName] = { bought = 0, sold = 0, spent = 0, earned = 0 }
            end
            stats.byStation[stationName].goods[goodName].sold = stats.byStation[stationName].goods[goodName].sold +
                amount
            stats.byStation[stationName].goods[goodName].earned = stats.byStation[stationName].goods[goodName].earned +
                price
        end

        -- Update totals
        stats.totals.totalRevenue = stats.totals.totalRevenue + price
        stats.totals.totalProfit = stats.totals.totalRevenue - stats.totals.totalCost
        stats.totals.tradeCount = stats.totals.tradeCount + 1

        GclConsole.saveTradeStats(stats)
    end

    -- Reset all trade stats
    function GclConsole.resetTradeStats()
        local player = Player()
        if not player then return end

        player:setValue(TRADE_STATS_KEY, nil)
        print("[GCL Console] Trade statistics reset for " .. player.name)
    end

    callable(GclConsole, "resetTradeStats")

    -- Get trade stats for client display
    function GclConsole.getTradeStatsForClient()
        local stats = GclConsole.getTradeStats()
        local player = Player()
        if player then
            invokeClientFunction(player, "receiveTradeStats", stats)
        end
    end

    callable(GclConsole, "getTradeStatsForClient")

    -- Scan all owned stations in current sector and import their historical stats
    -- This captures trade data from before the mod was installed
    function GclConsole.scanOwnedStations()
        local player = Player()
        if not player then return 0 end

        local sector = Sector()
        if not sector then
            print("[GCL Trade] No sector available for scanning")
            return 0
        end

        local playerFactionIndex = player.index
        local allianceIndex = player.allianceIndex

        -- Get all stations in the sector
        local stations = { sector:getEntitiesByType(EntityType.Station) }
        local scannedCount = 0
        local stats = GclConsole.getTradeStats()

        -- Initialize station history tracking if needed
        if not stats.stationHistory then
            stats.stationHistory = {}
        end

        for _, station in pairs(stations) do
            -- Check if player or alliance owns this station
            local isOwned = station.factionIndex == playerFactionIndex
            if allianceIndex and station.factionIndex == allianceIndex then
                isOwned = true
            end

            if isOwned then
                local stationName = station.name or "Unknown Station"
                local stationId = tostring(station.id)

                -- Try to get factory stats via script
                local hasFactory = station:hasScript("factory.lua")
                local hasConsumer = station:hasScript("consumer.lua")
                local hasTradingPost = station:hasScript("tradingpost.lua")

                if hasFactory or hasConsumer or hasTradingPost then
                    -- Try to invoke function to get trader stats
                    -- Since there's no callable getStats, we need to access via the TradingAPI secure method
                    local scriptName = hasFactory and "factory.lua" or
                        (hasConsumer and "consumer.lua" or "tradingpost.lua")

                    -- Access the trader stats through secure data
                    local ok, data = station:invokeFunction(scriptName, "secure")

                    -- Stats are nested in tradingData (via secureTradingGoods())
                    local traderStats = nil
                    if ok == 0 and data then
                        if data.tradingData and data.tradingData.stats then
                            traderStats = data.tradingData.stats
                        elseif data.stats then
                            traderStats = data.stats
                        end
                    end

                    if traderStats then
                        -- Check if we've already imported this station's data
                        local previousImport = stats.stationHistory[stationId]
                        local prevSpent = previousImport and previousImport.moneySpentOnGoods or 0
                        local prevGained = previousImport and previousImport.moneyGainedFromGoods or 0

                        -- Calculate delta (new trades since last import)
                        local deltaSpent = (traderStats.moneySpentOnGoods or 0) - prevSpent
                        local deltaGained = (traderStats.moneyGainedFromGoods or 0) - prevGained

                        -- Only import if there's new data
                        if deltaSpent > 0 or deltaGained > 0 then
                            -- Update by-station stats (from station's perspective)
                            -- Station spent = station bought goods (our factory bought ingredients)
                            -- Station gained = station sold goods (our factory sold products)
                            if not stats.byStation[stationName] then
                                stats.byStation[stationName] = {
                                    bought = 0,
                                    sold = 0,
                                    spent = 0,
                                    earned = 0,
                                    goods = {},
                                    isOwnedStation = true
                                }
                            end

                            stats.byStation[stationName].isOwnedStation = true

                            -- For owned stations, "spent" is what the factory spent on ingredients
                            -- "earned" is what the factory earned selling products
                            stats.byStation[stationName].spent = stats.byStation[stationName].spent + deltaSpent
                            stats.byStation[stationName].earned = stats.byStation[stationName].earned + deltaGained

                            -- Update totals (from player perspective with owned stations)
                            -- Factory earning = our revenue
                            -- Factory spending = our cost
                            stats.totals.totalRevenue = stats.totals.totalRevenue + deltaGained
                            stats.totals.totalCost = stats.totals.totalCost + deltaSpent
                            stats.totals.totalProfit = stats.totals.totalRevenue - stats.totals.totalCost

                            -- Record this import to avoid double-counting
                            stats.stationHistory[stationId] = {
                                moneySpentOnGoods = traderStats.moneySpentOnGoods or 0,
                                moneyGainedFromGoods = traderStats.moneyGainedFromGoods or 0,
                                lastImport = os.time and os.time() or 0
                            }

                            scannedCount = scannedCount + 1
                            print(string.format("[GCL Trade] Imported stats from %s: earned +%d, spent +%d",
                                stationName, deltaGained, deltaSpent))
                        end
                    else
                        print(string.format(
                            "[GCL Trade] Could not get stats from %s (script: %s, result: %s, has tradingData: %s)",
                            stationName, scriptName, tostring(ok), tostring(data and data.tradingData ~= nil)))
                    end
                end
            end
        end

        if scannedCount > 0 then
            GclConsole.saveTradeStats(stats)
        end

        print(string.format("[GCL Trade] Scanned sector: imported stats from %d stations", scannedCount))
        return scannedCount
    end

    callable(GclConsole, "scanOwnedStations")

    -- Scan and then return stats to client
    function GclConsole.scanAndGetStats()
        local scanned = GclConsole.scanOwnedStations()
        local stats = GclConsole.getTradeStats()
        local player = Player()
        if player then
            invokeClientFunction(player, "receiveScanResult", scanned, stats)
        end
    end

    callable(GclConsole, "scanAndGetStats")

    -- Attach trade hook scripts to owned stations in the current sector
    function GclConsole.attachTradeHooks()
        local player = Player()
        if not player then return 0 end

        local sector = Sector()
        if not sector then
            print("[GCL Trade] No sector available for hook attachment")
            if player then
                invokeClientFunction(player, "receiveHookResult", 0, "No sector available")
            end
            return 0
        end

        local playerFactionIndex = player.index
        local allianceIndex = player.allianceIndex

        -- Get all stations in the sector
        local stations = { sector:getEntitiesByType(EntityType.Station) }
        local attachedCount = 0

        for _, station in pairs(stations) do
            -- Check if player or alliance owns this station
            local isOwned = station.factionIndex == playerFactionIndex
            if allianceIndex and station.factionIndex == allianceIndex then
                isOwned = true
            end

            if isOwned then
                local stationName = station.name or "Unknown Station"

                -- Only attach if station has trading capability
                local hasFactory = station:hasScript("factory.lua")
                local hasConsumer = station:hasScript("consumer.lua")
                local hasTradingPost = station:hasScript("tradingpost.lua")

                if hasFactory or hasConsumer or hasTradingPost then
                    -- addScriptOnce ensures we don't add duplicates
                    local added = station:addScriptOnce("data/scripts/entity/gcl_trade_hook.lua")
                    if added then
                        attachedCount = attachedCount + 1
                        print(string.format("[GCL Trade] Attached hook to %s", stationName))
                    else
                        print(string.format("[GCL Trade] Hook already attached to %s", stationName))
                    end
                end
            end
        end

        print(string.format("[GCL Trade] Attached hooks to %d stations", attachedCount))

        if player then
            invokeClientFunction(player, "receiveHookResult", attachedCount, nil)
        end

        return attachedCount
    end

    callable(GclConsole, "attachTradeHooks")

    -- Record a station sale (station sold goods = station revenue)
    function GclConsole.recordStationSale(stationName, goodName, amount, price)
        GclConsole.recordSale(goodName, amount, price, stationName)
    end

    callable(GclConsole, "recordStationSale")

    -- Record a station purchase (station bought goods = station expense)
    function GclConsole.recordStationPurchase(stationName, goodName, amount, price)
        GclConsole.recordPurchase(goodName, amount, price, stationName)
    end

    callable(GclConsole, "recordStationPurchase")

    -- Server-side receiver for station trade events (called by gcl_trade_hook.lua)
    -- This is invoked via player:invokeFunction from the station script
    function GclConsole.receiveStationTradeEvent(stationName, eventType, goodName, amount, price)
        print(string.format("[GCL Console Server] Received trade event: %s %s %d %s for %d",
            stationName, eventType, amount, goodName, price))

        -- Record to stats
        if eventType == "sell" then
            GclConsole.recordSale(goodName, amount, price, stationName)
        else
            GclConsole.recordPurchase(goodName, amount, price, stationName)
        end

        -- Forward to client for live UI update
        local player = Player()
        if player then
            invokeClientFunction(player, "receiveStationTradeEvent",
                stationName, eventType, goodName, amount, price)
        end
    end

    callable(GclConsole, "receiveStationTradeEvent")
end

-- Trading callbacks (must be global for registerCallback)
function onTradingManagerSellToPlayer(goodName, amount, price)
    -- Station SOLD to player = player BOUGHT (expense)
    -- Try to get the station name from Entity()
    local entity = Entity()
    local stationName = entity and entity.name or "Unknown Station"

    print("[GCL Trade] Player bought " .. amount .. " " .. goodName .. " for " .. price .. " from " .. stationName)
    GclConsole.recordPurchase(goodName, amount, price, stationName)
end

function onTradingManagerBuyFromPlayer(goodName, amount, price)
    -- Station BOUGHT from player = player SOLD (revenue)
    local entity = Entity()
    local stationName = entity and entity.name or "Unknown Station"

    print("[GCL Trade] Player sold " .. amount .. " " .. goodName .. " for " .. price .. " to " .. stationName)
    GclConsole.recordSale(goodName, amount, price, stationName)
end

-- Global callback wrappers (UI buttons call global functions)
function onClearPressed()
    GclConsole.onClearPressed()
end

function onScanNow()
    GclConsole.onScanNow()
end
