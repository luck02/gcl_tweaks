-- GCL Console - Client-side output window
-- Displays output from /gcl_tweak commands in a scrollable window
-- Toggle visibility with F9
-- Uses direct RPC (invokeClientFunction) for server-to-client data transfer

package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in.
-- namespace GclConsole
GclConsole = {}

-- Configuration
local WINDOW_WIDTH = 500
local WINDOW_HEIGHT = 400

-- UI elements (client-only)
local window = nil
local listBox = nil
local clearButton = nil

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

        -- Create container for content
        local container = window:createContainer(Rect(vec2(10, 10), size - vec2(25, 50)))

        -- Create scrollable ListBox for output
        listBox = container:createListBox(Rect(vec2(0, 0), container.size))
        listBox.fontSize = 12

        -- Create clear button
        clearButton = window:createButton(
            Rect(10, size.y - 35, 100, size.y - 10),
            "Clear",
            "onClearPressed"
        )

        -- Start hidden
        window:hide()

        print("[GCL Console] UI initialized. Press F9 to toggle visibility.")
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

        -- Show window when output arrives
        window:show()

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

-- Global callback wrapper (UI buttons call global functions)
function onClearPressed()
    GclConsole.onClearPressed()
end
