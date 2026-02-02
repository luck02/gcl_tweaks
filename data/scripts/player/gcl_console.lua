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
GclConsole.MAX_SECTOR_ROWS = 50      -- Maximum visible rows (increased from 15 for large station counts)
GclConsole.SECTOR_COOLDOWN_TIME = 30 -- 30 seconds cooldown for sector scan
GclConsole.sectorCooldown = 0        -- Remaining sector scan cooldown

-- Fleet tab UI elements
GclConsole.fleetTab = nil

-- Fleet highlighting configuration (persisted via AzimuthLib)
GclConsole.config = {
    fleet = {
        highlightDuration = 10,                     -- seconds (5-30)
        highlightColor = { r = 1, g = 0.5, b = 0 }, -- orange
        pulseSpeed = "normal",                      -- "slow", "normal", "fast"
        showArrow = true,
        playSound = true
    }
}

-- Available color presets for highlighting
GclConsole.HIGHLIGHT_COLORS = {
    { name = "Orange", color = { r = 1, g = 0.5, b = 0 } },
    { name = "Red",    color = { r = 1, g = 0.2, b = 0.2 } },
    { name = "Yellow", color = { r = 1, g = 1, b = 0 } },
    { name = "Green",  color = { r = 0.2, g = 1, b = 0.2 } },
    { name = "Cyan",   color = { r = 0, g = 1, b = 1 } },
    { name = "Purple", color = { r = 0.8, g = 0.2, b = 1 } },
}

-- Pulse speed multipliers
GclConsole.PULSE_SPEEDS = {
    slow = 0.5,
    normal = 1.0,
    fast = 2.0
}

-- Fleet config options for AzimuthLib validation
local fleetConfigOptions = {
    highlightDuration = { 10, comment = "Duration in seconds (5-30)" },
    highlightColorR = { 1.0, comment = "Red component (0-1)" },
    highlightColorG = { 0.5, comment = "Green component (0-1)" },
    highlightColorB = { 0.0, comment = "Blue component (0-1)" },
    pulseSpeed = { "normal", comment = "Pulse speed: slow, normal, fast" },
    showArrow = { true, comment = "Show direction arrow" },
    playSound = { true, comment = "Play notification sound" }
}

-- Load fleet config using AzimuthLib
function GclConsole.loadFleetConfig()
    if not Azimuth or not Azimuth.loadConfig then
        print("[GCL Fleet] AzimuthLib not available, using defaults")
        return
    end

    local cfg = Azimuth.loadConfig("GclTweaks_Fleet", fleetConfigOptions)

    if cfg then
        GclConsole.config.fleet.highlightDuration = cfg.highlightDuration or 10
        GclConsole.config.fleet.highlightColor = {
            r = cfg.highlightColorR or 1.0,
            g = cfg.highlightColorG or 0.5,
            b = cfg.highlightColorB or 0.0
        }
        GclConsole.config.fleet.pulseSpeed = cfg.pulseSpeed or "normal"
        GclConsole.config.fleet.showArrow = cfg.showArrow
        GclConsole.config.fleet.playSound = cfg.playSound
    end

    print("[GCL Fleet] Config loaded: duration=" .. GclConsole.config.fleet.highlightDuration ..
        ", pulse=" .. GclConsole.config.fleet.pulseSpeed)
end

-- Save fleet config using AzimuthLib
function GclConsole.saveFleetConfig()
    if not Azimuth or not Azimuth.saveConfig then
        print("[GCL Fleet] AzimuthLib not available, config not saved")
        return
    end

    local cfg = GclConsole.config.fleet
    local saveData = {
        highlightDuration = cfg.highlightDuration,
        highlightColorR = cfg.highlightColor.r,
        highlightColorG = cfg.highlightColor.g,
        highlightColorB = cfg.highlightColor.b,
        pulseSpeed = cfg.pulseSpeed,
        showArrow = cfg.showArrow,
        playSound = cfg.playSound
    }

    Azimuth.saveConfig("GclTweaks_Fleet", saveData, fleetConfigOptions)
    print("[GCL Fleet] Config saved")
end

-- Include server-side module (includes goods library and all callable functions)
include("player/gcl_console_server")

-- CLIENT-SIDE IMPLEMENTATION
if onClient() then
    -- Include client UI modules (they rely on upvalues declared above)
    include("player/gcl_console_ui_console")
    include("player/gcl_console_ui_trade")
    include("player/gcl_console_ui_sector")
    include("player/gcl_console_ui_fleet")
    include("player/gcl_console_ui_targeting")

    local TOGGLE_KEY = KeyboardKey.F9

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
        -- Load saved fleet configuration
        GclConsole.loadFleetConfig()

        -- Don't call initUI here - createWindow API isn't available yet
        -- UI will be created lazily on F9 press or when output is received
        print("[GCL Console] Client script initialized. Press F9 to open console.")

        -- Register targeting render callback directly in main script
        -- (Callbacks registered from included modules may not be found by the engine)
        Player():registerCallback("onPostRenderIndicators", "onPostRenderIndicators")
        print("[GCL Fleet] Target highlighting initialized")
    end

    -- Key debounce state
    local wasKeyDown = false
    local keyCooldown = 0
    local KEY_COOLDOWN_TIME = 0.3 -- 300ms cooldown between toggles

    -- Mark Target key (V) debounce state
    local wasMarkKeyDown = false
    local markKeyCooldown = 0
    local MARK_TARGET_KEY = KeyboardKey._V

    -- Called every frame on client
    function GclConsole.updateClient(timestep)
        -- Render target highlighting (callback not firing, so call directly)
        if GclConsole.renderTargetIndicator_impl then
            GclConsole.renderTargetIndicator_impl()
        end

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

        -- Handle V key for Mark Target with debounce
        if markKeyCooldown > 0 then
            markKeyCooldown = markKeyCooldown - timestep
        end
        local isMarkKeyDown = Keyboard():keyPressed(MARK_TARGET_KEY)
        if isMarkKeyDown and not wasMarkKeyDown and markKeyCooldown <= 0 then
            GclConsole.onFleetMarkTargetPressed()
            markKeyCooldown = KEY_COOLDOWN_TIME
        end
        wasMarkKeyDown = isMarkKeyDown
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

function onTargetMarkingToggled(checkBox)
    GclConsole.onTargetMarkingToggled(checkBox)
end

function onFleetMarkTargetPressed()
    GclConsole.onFleetMarkTargetPressed()
end

function onSpawnTestTargetPressed()
    GclConsole.onSpawnTestTargetPressed()
end

function onDurationSliderChanged(slider)
    GclConsole.onDurationSliderChanged(slider)
end

function onPulseSpeedChanged(comboBox)
    GclConsole.onPulseSpeedChanged(comboBox)
end

function onShowArrowChanged(checkBox)
    GclConsole.onShowArrowChanged(checkBox)
end

function onPlaySoundChanged(checkBox)
    GclConsole.onPlaySoundChanged(checkBox)
end

function onColorButtonPressed(button)
    GclConsole.onColorButtonPressed(button)
end

-- Escort loot callbacks
function onEscortLootTogglePressed()
    GclConsole.onEscortLootTogglePressed()
end

function onEscortLootEnableAllPressed()
    GclConsole.onEscortLootEnableAllPressed()
end

function onEscortLootDisableAllPressed()
    GclConsole.onEscortLootDisableAllPressed()
end

function onEscortLootRefreshPressed()
    GclConsole.onEscortLootRefreshPressed()
end

-- Sector tab sorting callbacks
function onSectorSortByStation()
    GclConsole.onSectorSortByStation()
end

function onSectorSortByStatus()
    GclConsole.onSectorSortByStatus()
end

function onSectorSortByCargo()
    GclConsole.onSectorSortByCargo()
end

function onSectorSortByLines()
    GclConsole.onSectorSortByLines()
end

function onSectorSortByIngredients()
    GclConsole.onSectorSortByIngredients()
end

function onSectorTargetStation(button)
    GclConsole.onSectorTargetStation(button)
end

-- Global engine callbacks (Avorion calls these, not namespace-qualified versions)
function initialize()
    if onClient() then
        GclConsole.initialize()
    elseif onServer() then
        GclConsole.initialize()
    end
end

function updateClient(timestep)
    GclConsole.updateClient(timestep)
end

-- Global render callback (Avorion looks for this in the script's global namespace)
function onPostRenderIndicators()
    if GclConsole.renderTargetIndicator_impl then
        GclConsole.renderTargetIndicator_impl()
    end
end
