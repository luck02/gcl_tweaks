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
GclConsole.WINDOW_WIDTH = 700
GclConsole.WINDOW_HEIGHT = 500

-- UI elements (stored in namespace so included modules can access them)
GclConsole.window = nil
GclConsole.tabbedWindow = nil
GclConsole.consoleTab = nil
GclConsole.tradeTab = nil
GclConsole.sectorTab = nil
GclConsole.listBox = nil
GclConsole.clearButton = nil

-- Trade tab UI elements (spreadsheet layout)
GclConsole.tradeStatusLabel = nil
GclConsole.scanNowBtn = nil
GclConsole.scanCooldownLabel = nil -- Shows countdown below button
GclConsole.tradeScrollFrame = nil
GclConsole.tradeRows = {}          -- Array of {frame, nameLabel, sectorLabel, revenueLabel, costsLabel, profitLabel}
GclConsole.tradeHeaderLabels = {}  -- Column headers
GclConsole.tradeTotalsLabels = {}  -- Totals row labels
GclConsole.MAX_TRADE_ROWS = 20     -- Maximum visible rows before scrolling
GclConsole.SCAN_COOLDOWN_TIME = 60 -- 60 seconds cooldown after scan
GclConsole.scanCooldown = 0        -- Remaining cooldown time

-- Sector tab UI elements (detailed in-sector diagnostics)
GclConsole.sectorStatusLabel = nil
GclConsole.sectorScanBtn = nil
GclConsole.sectorCooldownLabel = nil
GclConsole.sectorScrollFrame = nil
GclConsole.sectorRows = {}           -- Array of {frame, nameLabel, statusLabel, cargoLabel, linesLabel, ingredientsLabel}
GclConsole.sectorHeaderLabels = {}   -- Column headers
GclConsole.MAX_SECTOR_ROWS = 15      -- Maximum visible rows
GclConsole.SECTOR_COOLDOWN_TIME = 30 -- 30 seconds cooldown for sector scan
GclConsole.sectorCooldown = 0        -- Remaining sector scan cooldown

-- Fleet tab UI elements (simplified - no leader/follower roles)
GclConsole.fleetTab = nil
GclConsole.fleetStatusLabel = nil  -- Shows current state
GclConsole.fleetDestLabel = nil    -- Shows pending destination
GclConsole.fleetPendingFrame = nil -- Highlight frame for pending dest
GclConsole.fleetTimerLabel = nil   -- Countdown timer
GclConsole.pendingFleetDest = nil  -- {x, y, senderName, timestamp}
GclConsole.FLEET_DEST_TIMEOUT = 15 -- 15 seconds timeout for pending destinations

-- Include server-side module (includes goods library and all callable functions)
include("player/gcl_console_server")

-- CLIENT-SIDE IMPLEMENTATION
if onClient() then
    -- Include client UI modules (they rely on upvalues declared above)
    include("player/gcl_console_ui_console")
    include("player/gcl_console_ui_trade")
    include("player/gcl_console_ui_sector")
    include("player/gcl_console_ui_fleet")

    local TOGGLE_KEY = KeyboardKey.F9
    local FLEET_KEY = KeyboardKey.F11 -- Broadcasts if no pending dest, accepts if pending

    -- Initialize the UI
    function GclConsole.initUI()
        print("[GCL Console] initUI called")
        if GclConsole.window then
            print("[GCL Console] Window already exists, skipping")
            return
        end

        local res = getResolution()
        local size = vec2(GclConsole.WINDOW_WIDTH, GclConsole.WINDOW_HEIGHT)

        -- Create window in top-right area using Hud (always available in player scripts)
        -- Note: Hud windows don't support createContainer, but CustomTabbedWindow works with them
        GclConsole.window = Hud():createWindow(Rect(res.x - size.x - 20, 100, res.x - 20, 100 + size.y))
        GclConsole.window.caption = "GCL Console"
        GclConsole.window.showCloseButton = true
        GclConsole.window.moveable = true

        -- Create tabbed window using AzimuthLib
        -- CustomTabbedWindow(namespace, parent, rect, onSelectedFunction)
        -- Window from ScriptUI supports createContainer, so tabs will be inside the window
        local tabRect = Rect(vec2(10, 10), size - vec2(20, 20))
        GclConsole.tabbedWindow = CustomTabbedWindow(GclConsole, GclConsole.window, tabRect, "onTabSelected")

        -- Create tabs
        GclConsole.consoleTab = GclConsole.tabbedWindow:createTab("Console", "data/textures/icons/info.png",
            "Command Output")
        GclConsole.buildConsoleTab(GclConsole.consoleTab)

        GclConsole.tradeTab = GclConsole.tabbedWindow:createTab("Trade", "data/textures/icons/money.png",
            "Economy Health Dashboard")
        GclConsole.buildTradeTab(GclConsole.tradeTab)

        GclConsole.sectorTab = GclConsole.tabbedWindow:createTab("Sector", "data/textures/icons/factory-arm.png",
            "In-Sector Diagnostics")
        GclConsole.buildSectorTab(GclConsole.sectorTab)

        GclConsole.fleetTab = GclConsole.tabbedWindow:createTab("Fleet", "data/textures/icons/escort.png",
            "Fleet Coordination")
        GclConsole.buildFleetTab(GclConsole.fleetTab)

        -- Restore saved tab selection (default to Trade)
        local savedTab = Player():getValue("gcl_console_tab") or "Trade"
        local tabToSelect = GclConsole.tabbedWindow:getTab(savedTab)
        if tabToSelect then
            GclConsole.tabbedWindow:selectTab(tabToSelect)
        end

        -- Start hidden
        GclConsole.window:hide()

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

    -- Get the parent player index (required for player scripts)
    function GclConsole.getParentIndex()
        return Player().index
    end

    function GclConsole.initialize()
        -- Don't call initUI here - createWindow API isn't available yet
        -- UI will be created lazily on F9 press or when output is received
        print("[GCL Console] Client script initialized. Press F9 to open console.")
    end

    -- Key debounce state
    local wasKeyDown = false
    local wasFleetKeyDown = false
    local keyCooldown = 0
    local KEY_COOLDOWN_TIME = 0.3 -- 300ms cooldown between toggles

    -- Called every frame on client
    function GclConsole.updateClient(timestep)
        -- Update key cooldown
        if keyCooldown > 0 then
            keyCooldown = keyCooldown - timestep
        end

        -- Update scan button cooldown
        if GclConsole.scanCooldown > 0 then
            GclConsole.scanCooldown = GclConsole.scanCooldown - timestep
            -- Update button and label state
            if GclConsole.scanCooldown <= 0 then
                if GclConsole.scanNowBtn then
                    GclConsole.scanNowBtn.active = true
                end
                if GclConsole.scanCooldownLabel then
                    GclConsole.scanCooldownLabel.caption = ""
                end
            else
                -- Format as "0:nn Seconds"
                local secs = math.ceil(GclConsole.scanCooldown)
                local mins = math.floor(secs / 60)
                local remainingSecs = secs % 60
                if GclConsole.scanCooldownLabel then
                    GclConsole.scanCooldownLabel.caption = string.format("%d:%02d Seconds", mins, remainingSecs)
                end
            end
        end

        -- Update sector scan button cooldown
        if GclConsole.sectorCooldown > 0 then
            GclConsole.sectorCooldown = GclConsole.sectorCooldown - timestep
            if GclConsole.sectorCooldown <= 0 then
                if GclConsole.sectorScanBtn then
                    GclConsole.sectorScanBtn.active = true
                end
                if GclConsole.sectorCooldownLabel then
                    GclConsole.sectorCooldownLabel.caption = ""
                end
            else
                local secs = math.ceil(GclConsole.sectorCooldown)
                if GclConsole.sectorCooldownLabel then
                    GclConsole.sectorCooldownLabel.caption = string.format("%d sec", secs)
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

        -- Handle F10: broadcasts if no pending destination, accepts if there is one
        local isFleetKeyDown = Keyboard():keyPressed(FLEET_KEY)
        if isFleetKeyDown and not wasFleetKeyDown then
            GclConsole.handleFleetKey()
        end
        wasFleetKeyDown = isFleetKeyDown

        -- Check for fleet destination timeout
        GclConsole.updateFleetTimeout(timestep)
    end

    -- F10 handler: dual-purpose key
    function GclConsole.handleFleetKey()
        if GclConsole.pendingFleetDest then
            -- Accept pending destination
            GclConsole.acceptFleetDestination()
        else
            -- Broadcast current galaxy map selection
            GclConsole.broadcastFleetDestination()
        end
    end

    -- Toggle visibility
    function GclConsole.toggle()
        GclConsole.initUI()
        if not GclConsole.window then return end

        if GclConsole.window.visible then
            GclConsole.window:hide()
        else
            GclConsole.window:show()
        end
    end

    -- Show the console
    function GclConsole.show()
        GclConsole.initUI()
        if GclConsole.window then GclConsole.window:show() end
    end

    -- Hide the console
    function GclConsole.hide()
        GclConsole.initUI()
        if GclConsole.window then GclConsole.window:hide() end
    end
end -- if onClient()

-- Global callback wrappers (UI buttons call global functions)
function onClearPressed()
    GclConsole.onClearPressed()
end

function onScanNow()
    GclConsole.onScanNow()
end

function onScanSector()
    GclConsole.onScanSector()
end
