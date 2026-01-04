-- GCL Trade Hook - Entity script for capturing station trade events
-- This script is injected onto alliance stations to capture trade callbacks
-- and forward them to player console scripts for real-time tracking.
--
-- Usage: station:addScriptOnce("data/scripts/entity/gcl_trade_hook.lua")

package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in.
-- namespace GclTradeHook
GclTradeHook = {}

-- Server-side only
if onServer() then
    function GclTradeHook.initialize()
        local entity = Entity()
        local stationName = entity.name or "Unknown Station"

        -- Register for Entity-level trade callbacks (these ALWAYS fire, unlike Player-scoped)
        entity:registerCallback("onTradingManagerBuyFromPlayer", "onStationBuy")
        entity:registerCallback("onTradingManagerSellToPlayer", "onStationSell")

        print("[GCL Trade Hook] Initialized on station: " .. stationName)
    end

    -- Called when the station BUYS goods FROM a trader (station spends money)
    -- From station perspective: expense (we bought ingredients)
    function GclTradeHook.onStationBuy(goodName, amount, price)
        local entity = Entity()
        local stationName = entity.name or "Unknown Station"

        print(string.format("[GCL Trade Hook] %s bought %d %s for %d", stationName, amount, goodName, price))

        GclTradeHook.broadcastTradeEvent("buy", goodName, amount, price, stationName)
    end

    -- Called when the station SELLS goods TO a trader (station earns money)
    -- From station perspective: revenue (we sold products)
    function GclTradeHook.onStationSell(goodName, amount, price)
        local entity = Entity()
        local stationName = entity.name or "Unknown Station"

        print(string.format("[GCL Trade Hook] %s sold %d %s for %d", stationName, amount, goodName, price))

        GclTradeHook.broadcastTradeEvent("sell", goodName, amount, price, stationName)
    end

    -- Broadcast trade event to all alliance/faction member players in the sector
    function GclTradeHook.broadcastTradeEvent(eventType, goodName, amount, price, stationName)
        local entity = Entity()
        local ownerFactionIndex = entity.factionIndex

        -- Find all players in the sector who are members of the owning faction/alliance
        local sector = Sector()
        if not sector then return end

        local players = { sector:getPlayers() }

        for _, player in pairs(players) do
            local shouldNotify = false

            -- Check if player is the faction owner
            if player.index == ownerFactionIndex then
                shouldNotify = true
            end

            -- Check if player's alliance owns the station
            if player.allianceIndex and player.allianceIndex == ownerFactionIndex then
                shouldNotify = true
            end

            if shouldNotify then
                -- Try to invoke the console script on this player
                local ok, err = player:invokeFunction("gcl_console.lua", "receiveStationTradeEvent",
                    stationName, eventType, goodName, amount, price)

                if ok ~= 0 then
                    print(string.format("[GCL Trade Hook] Failed to notify player %s: error %s",
                        player.name or "Unknown", tostring(ok)))
                else
                    print(string.format("[GCL Trade Hook] Notified player %s of %s event",
                        player.name or "Unknown", eventType))
                end
            end
        end
    end
end
