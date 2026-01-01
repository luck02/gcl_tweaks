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

-- Trade tab UI elements
local tradeListBox = nil
local groupByStationBtn = nil
local groupByGoodBtn = nil
local refreshBtn = nil
local resetBtn = nil
local scanSectorBtn = nil
local groupMode = "station" -- "station" or "good"

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

        -- Create Console tab
        consoleTab = tabbedWindow:createTab("Console", "data/textures/icons/info.png", "Command Output")
        GclConsole.buildConsoleTab(consoleTab)

        -- Create Trade tab
        tradeTab = tabbedWindow:createTab("Trade", "data/textures/icons/money.png", "Trade Statistics")
        GclConsole.buildTradeTab(tradeTab)

        -- Start hidden
        window:hide()

        print("[GCL Console] Tabbed UI initialized. Press F9 to toggle visibility.")
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

    -- Build the Trade tab UI
    function GclConsole.buildTradeTab(tab)
        local tabSize = tab.size

        -- Header row with group toggle buttons
        local buttonWidth = 120
        local buttonHeight = 25
        local buttonY = 5

        groupByStationBtn = tab:createButton(
            Rect(5, buttonY, 5 + buttonWidth, buttonY + buttonHeight),
            "By Station",
            "onGroupByStation"
        )

        groupByGoodBtn = tab:createButton(
            Rect(10 + buttonWidth, buttonY, 10 + buttonWidth * 2, buttonY + buttonHeight),
            "By Good",
            "onGroupByGood"
        )

        -- Refresh and Reset buttons on the right
        refreshBtn = tab:createButton(
            Rect(tabSize.x - buttonWidth * 2 - 15, buttonY, tabSize.x - buttonWidth - 10, buttonY + buttonHeight),
            "Refresh",
            "onTradeRefresh"
        )

        resetBtn = tab:createButton(
            Rect(tabSize.x - buttonWidth - 5, buttonY, tabSize.x - 5, buttonY + buttonHeight),
            "Reset Stats",
            "onTradeReset"
        )

        -- Second row: Scan Sector button
        local row2Y = buttonY + buttonHeight + 5
        scanSectorBtn = tab:createButton(
            Rect(5, row2Y, 5 + buttonWidth + 20, row2Y + buttonHeight),
            "Scan Sector",
            "onScanSector"
        )

        -- Trade data ListBox (moved down to make room for second row)
        local listTop = row2Y + buttonHeight + 10
        tradeListBox = tab:createListBox(Rect(vec2(0, listTop), vec2(tabSize.x, tabSize.y - 10)))
        tradeListBox.fontSize = 12

        -- Initial button states
        GclConsole.updateGroupButtons()

        -- Add initial instructions
        tradeListBox:addEntry("=== Trade Statistics ===", nil)
        tradeListBox:addEntry("", nil)
        tradeListBox:addEntry("Click 'Refresh' to load current stats.", nil)
        tradeListBox:addEntry("", nil)
        tradeListBox:addEntry("Click 'Scan Sector' while near your stations", nil)
        tradeListBox:addEntry("to import their historical trade data.", nil)
    end

    -- Update group button visual states
    function GclConsole.updateGroupButtons()
        if not groupByStationBtn or not groupByGoodBtn then return end

        if groupMode == "station" then
            groupByStationBtn.pressed = true
            groupByGoodBtn.pressed = false
        else
            groupByStationBtn.pressed = false
            groupByGoodBtn.pressed = true
        end
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
    function GclConsole.onGroupByStation()
        groupMode = "station"
        GclConsole.updateGroupButtons()
        GclConsole.refreshTradeData()
    end

    function GclConsole.onGroupByGood()
        groupMode = "good"
        GclConsole.updateGroupButtons()
        GclConsole.refreshTradeData()
    end

    function GclConsole.onTradeRefresh()
        invokeServerFunction("getTradeStatsForClient")
    end

    function GclConsole.onTradeReset()
        invokeServerFunction("resetTradeStats")
        if tradeListBox then
            tradeListBox:clear()
            tradeListBox:addEntry("Statistics reset.", nil)
        end
    end

    -- Scan sector for owned stations
    function GclConsole.onScanSector()
        if tradeListBox then
            tradeListBox:clear()
            tradeListBox:addEntry("Scanning sector for owned stations...", nil)
        end
        invokeServerFunction("scanAndGetStats")
    end

    -- Receive scan results from server
    function GclConsole.receiveScanResult(scannedCount, stats)
        if not tradeListBox then return end

        tradeListBox:clear()

        if scannedCount > 0 then
            tradeListBox:addEntry(string.format("=== Scan Complete: Imported from %d station(s) ===", scannedCount), nil)
        else
            tradeListBox:addEntry("=== Scan Complete: No new data to import ===", nil)
        end
        tradeListBox:addEntry("", nil)

        -- Now display the stats
        GclConsole.receiveTradeStats(stats)
    end

    -- Receive trade stats from server
    function GclConsole.receiveTradeStats(stats)
        if not tradeListBox then return end

        tradeListBox:clear()

        if not stats or not stats.totals then
            tradeListBox:addEntry("No trade data available.", nil)
            return
        end

        -- Format currency helper
        local function formatMoney(amount)
            return string.format("¢%s", tostring(math.floor(amount or 0)))
        end

        -- Header
        local totalProfit = stats.totals.totalProfit or 0
        local profitColor = totalProfit >= 0 and "\\c(0f0)" or "\\c(f00)"
        tradeListBox:addEntry(string.format("=== Trade Summary (%d trades) ===", stats.totals.tradeCount or 0), nil)
        tradeListBox:addEntry(string.format("Total Revenue: %s", formatMoney(stats.totals.totalRevenue)), nil)
        tradeListBox:addEntry(string.format("Total Cost:    %s", formatMoney(stats.totals.totalCost)), nil)
        tradeListBox:addEntry(string.format("Net Profit:    %s", formatMoney(totalProfit)), nil)
        tradeListBox:addEntry("", nil)

        if groupMode == "station" then
            tradeListBox:addEntry("=== By Station ===", nil)
            local hasData = false
            for stationName, data in pairs(stats.byStation or {}) do
                hasData = true
                local profit = (data.earned or 0) - (data.spent or 0)
                tradeListBox:addEntry(string.format("%s", stationName), nil)
                tradeListBox:addEntry(string.format("  Earned: %s  |  Spent: %s  |  Profit: %s",
                    formatMoney(data.earned), formatMoney(data.spent), formatMoney(profit)), nil)
            end
            if not hasData then
                tradeListBox:addEntry("  (No station data yet)", nil)
            end
        else
            tradeListBox:addEntry("=== By Good ===", nil)
            local hasData = false
            for goodName, data in pairs(stats.byGood or {}) do
                hasData = true
                local profit = (data.earned or 0) - (data.spent or 0)
                tradeListBox:addEntry(string.format("%s", goodName), nil)
                tradeListBox:addEntry(string.format("  Sold: %d (%s)  |  Bought: %d (%s)  |  Profit: %s",
                    data.sold or 0, formatMoney(data.earned),
                    data.bought or 0, formatMoney(data.spent),
                    formatMoney(profit)), nil)
            end
            if not hasData then
                tradeListBox:addEntry("  (No goods data yet)", nil)
            end
        end
    end

    -- Refresh trade data display (initial placeholder before server response)
    function GclConsole.refreshTradeData()
        if not tradeListBox then return end

        tradeListBox:clear()
        tradeListBox:addEntry("Loading trade data...", nil)

        -- Request data from server
        invokeServerFunction("getTradeStatsForClient")
    end
end -- if onClient()

-- SERVER-SIDE IMPLEMENTATION
if onServer() then
    -- Trade data storage key
    local TRADE_STATS_KEY = "gcl_trade_stats"

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

    -- Initialize trade tracking
    function GclConsole.initialize()
        local player = Player()
        if not player then return end

        -- Register for trading callbacks
        player:registerCallback("onTradingManagerSellToPlayer", "onTradingManagerSellToPlayer")
        player:registerCallback("onTradingManagerBuyFromPlayer", "onTradingManagerBuyFromPlayer")

        print("[GCL Console] Server-side trade tracking initialized for " .. player.name)
    end

    -- Get current trade stats from player values
    function GclConsole.getTradeStats()
        local player = Player()
        if not player then return {} end

        local statsJson = player:getValue(TRADE_STATS_KEY)
        if not statsJson then
            -- Initialize empty stats structure
            return {
                byStation = {},
                byGood = {},
                totals = {
                    totalRevenue = 0,
                    totalCost = 0,
                    totalProfit = 0,
                    tradeCount = 0
                }
            }
        end

        -- Parse JSON (simple table for now)
        -- Note: Avorion stores tables directly, no JSON parsing needed
        return statsJson
    end

    -- Save trade stats to player values
    function GclConsole.saveTradeStats(stats)
        local player = Player()
        if not player then return end

        player:setValue(TRADE_STATS_KEY, stats)
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

                    if ok == 0 and data and data.stats then
                        local traderStats = data.stats

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
                        print(string.format("[GCL Trade] Could not get stats from %s (script: %s, result: %s)",
                            stationName, scriptName, tostring(ok)))
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

function onGroupByStation()
    GclConsole.onGroupByStation()
end

function onGroupByGood()
    GclConsole.onGroupByGood()
end

function onTradeRefresh()
    GclConsole.onTradeRefresh()
end

function onTradeReset()
    GclConsole.onTradeReset()
end

function onScanSector()
    GclConsole.onScanSector()
end
