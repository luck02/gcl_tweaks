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

        -- Trade data ListBox
        local listTop = buttonY + buttonHeight + 10
        tradeListBox = tab:createListBox(Rect(vec2(0, listTop), vec2(tabSize.x, tabSize.y - 10)))
        tradeListBox.fontSize = 12

        -- Initial button states
        GclConsole.updateGroupButtons()

        -- Add placeholder text
        tradeListBox:addEntry("Trade statistics will appear here once", nil)
        tradeListBox:addEntry("the tracking system is implemented.", nil)
        tradeListBox:addEntry("", nil)
        tradeListBox:addEntry("Coming soon:", nil)
        tradeListBox:addEntry("  - Revenue from station trades", nil)
        tradeListBox:addEntry("  - Profit per production cycle", nil)
        tradeListBox:addEntry("  - Group by Station or by Good", nil)
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
        GclConsole.refreshTradeData()
    end

    function GclConsole.onTradeReset()
        -- TODO: Implement reset via server call
        if tradeListBox then
            tradeListBox:clear()
            tradeListBox:addEntry("Statistics reset.", nil)
        end
    end

    -- Refresh trade data display
    function GclConsole.refreshTradeData()
        if not tradeListBox then return end

        tradeListBox:clear()
        tradeListBox:addEntry("Refreshing trade data...", nil)
        tradeListBox:addEntry("(Trade tracking not yet implemented)", nil)
    end
end -- if onClient()

-- SERVER-SIDE IMPLEMENTATION
if onServer() then
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
