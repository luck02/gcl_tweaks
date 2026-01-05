-- GCL Console UI - Console Tab
-- Contains the console output tab UI building and handlers
-- This file is included by gcl_console.lua

if onClient() then
    -- Build the Console tab UI
    function GclConsole.buildConsoleTab(tab)
        local tabSize = tab.size

        -- Create scrollable ListBox for output (leave room for button at bottom)
        GclConsole.listBox = tab:createListBox(Rect(vec2(0, 0), vec2(tabSize.x, tabSize.y - 40)))
        GclConsole.listBox.fontSize = 12

        -- Create clear button at bottom
        GclConsole.clearButton = tab:createButton(
            Rect(0, tabSize.y - 35, 100, tabSize.y - 5),
            "Clear",
            "onClearPressed"
        )
    end

    -- Receive output from server via direct RPC (called by invokeClientFunction)
    function GclConsole.receiveOutput(text)
        print("[GCL Console] Received data via RPC: " .. tostring(string.len(text)) .. " bytes")

        if not GclConsole.window then
            GclConsole.initUI()
        end
        if not GclConsole.window or not GclConsole.listBox then return end

        -- Show window and switch to Console tab when output arrives
        GclConsole.window:show()
        if GclConsole.tabbedWindow and GclConsole.consoleTab then
            GclConsole.tabbedWindow:selectTab(GclConsole.consoleTab)
        end

        -- Split into lines and add each to the ListBox
        for line in text:gmatch("[^\n]+") do
            GclConsole.listBox:addEntry(line, nil)
        end

        -- Auto-scroll to bottom
        GclConsole.listBox.scrollPosition = math.max(0, GclConsole.listBox.rows - 1)
        GclConsole.listBox:clampScrollPosition()
    end

    -- Called when Clear button is pressed
    function GclConsole.onClearPressed()
        if GclConsole.listBox then
            GclConsole.listBox:clear()
        end
    end
end
