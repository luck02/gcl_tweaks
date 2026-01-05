-- GCL Console Server Module
-- Contains all server-side logic for trade tracking, station scanning, and diagnostics
-- This file is included by gcl_console.lua

if onServer() then
    -- goods library for getInSectorDiagnostics (server-only)
    include("goods")

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
                        stationId = name, -- Use name as ID since we don't have entity ID cross-sector
                        name = name,
                        x = x,
                        y = y,
                        moneySpent = 0,
                        moneyGained = 0,
                        moneyTax = 0,
                        status = "HEALTHY",
                        statusIssue = ""
                    }

                    -- Find trading scripts and extract stats + health status
                    local hasFactory = false
                    local maxProductions = 0
                    local activeProductions = 0

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

                        -- Detect factory scripts by checking for production-related fields
                        if values.maxNumProductions then
                            hasFactory = true
                            maxProductions = values.maxNumProductions

                            -- Count active productions
                            if values.currentProductions then
                                if type(values.currentProductions) == "table" then
                                    -- Count non-nil entries in currentProductions
                                    for _, prod in pairs(values.currentProductions) do
                                        if prod then
                                            activeProductions = activeProductions + 1
                                        end
                                    end
                                end
                            end
                        end

                        -- Check for delivery chain errors (warnings) from tradingmanager
                        if stationStats.status ~= "HALTED" then
                            if values.deliveredStationsErrors then
                                for _, err in pairs(values.deliveredStationsErrors) do
                                    if err and err ~= "" then
                                        stationStats.status = "WARNING"
                                        stationStats.statusIssue = "Delivery: " .. tostring(err)
                                        break
                                    end
                                end
                            end
                            if stationStats.status ~= "WARNING" and values.deliveringStationsErrors then
                                for _, err in pairs(values.deliveringStationsErrors) do
                                    if err and err ~= "" then
                                        stationStats.status = "WARNING"
                                        stationStats.statusIssue = "Supply: " .. tostring(err)
                                        break
                                    end
                                end
                            end
                        end
                    end

                    -- Heuristic: If factory has production capacity but 0 active productions, mark as IDLE
                    if hasFactory and stationStats.status == "HEALTHY" then
                        if activeProductions == 0 then
                            stationStats.status = "IDLE"
                            stationStats.statusIssue = string.format("0/%d production lines active", maxProductions)
                        end
                    end

                    -- Include stations with trading activity OR status issues
                    if stationStats.moneySpent > 0 or stationStats.moneyGained > 0 or stationStats.status ~= "HEALTHY" then
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

    -- Get detailed diagnostics for stations in the player's current sector
    -- This provides specific ingredient shortages and cargo fill info
    function GclConsole.getInSectorDiagnostics()
        local player = Player()
        if not player then
            player = Player(callingPlayer)
        end
        if not player then return end

        local sector = Sector()
        if not sector then
            print("[GCL Console] No sector available for in-sector diagnostics")
            invokeClientFunction(player, "receiveSectorDiagnostics", {})
            return
        end

        local playerFactionIndex = player.index
        local allianceIndex = player.allianceIndex

        -- Get all stations in the sector
        local stations = { sector:getEntitiesByType(EntityType.Station) }
        local diagnostics = {}

        for _, station in pairs(stations) do
            -- Check if player or alliance owns this station
            local isOwned = station.factionIndex == playerFactionIndex
            if allianceIndex and station.factionIndex == allianceIndex then
                isOwned = true
            end

            if isOwned then
                local stationName = station.name or "Unknown Station"
                local hasFactory = station:hasScript("factory.lua")

                if hasFactory then
                    -- Query factory secure data
                    local ok, data = station:invokeFunction("factory.lua", "secure")

                    if ok == 0 and data then
                        -- Count active productions
                        local activeProductions = 0
                        local maxProductions = data.maxNumProductions or 0
                        if data.currentProductions then
                            for _, prod in pairs(data.currentProductions) do
                                if prod then activeProductions = activeProductions + 1 end
                            end
                        end

                        local diag = {
                            stationId = stationName,
                            name = stationName,
                            ingredients = {},
                            cargoFillPercent = 0,
                            activeProductions = activeProductions,
                            maxProductions = maxProductions,
                            issue = nil
                        }

                        -- Get cargo fill percentage
                        local maxCargo = station.maxCargoSpace or 1
                        local freeCargo = station.freeCargoSpace or 0
                        diag.cargoFillPercent = math.floor((1 - freeCargo / maxCargo) * 100)

                        -- Check ingredient stocks vs requirements
                        if data.production and data.production.ingredients then
                            for _, ingredient in pairs(data.production.ingredients) do
                                -- Get current stock from cargo bay
                                -- Access the goods table for the good definition
                                local goodName = ingredient.name
                                local have = 0

                                -- Try to get cargo amount for this good
                                local goodDef = goods and goods[goodName]
                                if goodDef then
                                    have = station:getCargoAmount(goodDef:good()) or 0
                                end

                                local need = ingredient.amount
                                local isOptional = ingredient.optional == 1

                                table.insert(diag.ingredients, {
                                    name = goodName,
                                    need = need,
                                    have = have,
                                    optional = isOptional
                                })

                                -- Mark issue if missing required ingredients
                                if not isOptional and have < need then
                                    diag.issue = "Missing ingredients"
                                end
                            end
                        end

                        -- Check for cargo-full issue
                        if diag.cargoFillPercent > 90 and not diag.issue then
                            diag.issue = "Cargo nearly full"
                        end

                        -- Use station name as key for client lookup
                        diagnostics[stationName] = diag

                        print(string.format("[GCL Console] In-sector diagnostics for %s: cargo %d%%, issue: %s",
                            stationName, diag.cargoFillPercent, diag.issue or "none"))
                    else
                        print(string.format("[GCL Console] Failed to get secure data from %s: %s",
                            stationName, tostring(ok)))
                    end
                end
            end
        end

        local diagCount = 0
        for _ in pairs(diagnostics) do diagCount = diagCount + 1 end
        print(string.format("[GCL Console] In-sector diagnostics complete: %d stations analyzed", diagCount))

        invokeClientFunction(player, "receiveSectorDiagnostics", diagnostics)
    end

    callable(GclConsole, "getInSectorDiagnostics")

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
