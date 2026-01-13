-- GCL Console Fleet Tab - Target Highlighting for combat coordination
-- Mark targets for teammates to see highlighted in the HUD

if onClient() then
    -- Activity log storage (in-memory, cleared on reload)
    GclConsole.fleetActivityLog = {}
    GclConsole.fleetActivityListBox = nil
    GclConsole.MAX_FLEET_LOG_ENTRIES = 50

    -- Check if running as local mod (not from Workshop subscription)
    -- Local mods have non-numeric IDs (folder name), Workshop mods have numeric Steam IDs
    local function isLocalMod()
        -- Use the LOCAL folder name "gcl_tweaks" (contains letters = local)
        -- Workshop installs use numeric ID "3628589261" (pure digits = workshop)
        local modId = "gcl_tweaks"
        -- If ID is purely numeric, it's a Workshop subscription
        -- If it contains letters, it's a local/development mod
        return not modId:match("^%d+$")
    end

    -- Build the Fleet tab UI
    function GclConsole.buildFleetTab(tab)
        local tabSize = tab.size
        local padding = 15
        local y = padding

        -- Title
        local titleLabel = tab:createLabel(
            Rect(padding, y, tabSize.x - padding, y + 30),
            "Target Marking",
            16
        )
        y = y + 35

        -- Enable/Disable toggle for receiving target marks
        GclConsole.targetMarkingToggle = tab:createCheckBox(
            Rect(padding, y, tabSize.x - padding, y + 20),
            "Receive Target Highlights",
            "onTargetMarkingToggled"
        )
        -- Initialize if not yet set (targeting module may not be loaded yet)
        if GclConsole.targetMarkingEnabled == nil then
            GclConsole.targetMarkingEnabled = true
        end
        GclConsole.targetMarkingToggle.checked = GclConsole.targetMarkingEnabled
        y = y + 30

        -- Mark Target button
        local markTargetBtn = tab:createButton(
            Rect(padding, y, padding + 180, y + 30),
            "Mark Target (V)",
            "onFleetMarkTargetPressed"
        )
        markTargetBtn.tooltip = "Highlight your current target for all players in sector"

        -- TEST button (small, on the right side) - only for local/dev mods
        if isLocalMod() then
            local testBtn = tab:createButton(
                Rect(tabSize.x - padding - 60, y, tabSize.x - padding, y + 35),
                "TEST",
                "onSpawnTestTargetPressed"
            )
            testBtn.tooltip = "Test: highlights a random entity in sector"
        end
        y = y + 45

        -- Settings separator
        tab:createLine(vec2(padding, y), vec2(tabSize.x - padding, y))
        y = y + 10
        tab:createLabel(Rect(padding, y, tabSize.x - padding, y + 20), "Highlight Settings:", 14)
        y = y + 25

        -- Duration slider (5-30 seconds)
        tab:createLabel(Rect(padding, y, padding + 80, y + 20), "Duration:", 12)
        GclConsole.durationSlider = tab:createSlider(
            Rect(padding + 85, y - 2, padding + 250, y + 22),
            5, 30, 25, "", "onDurationSliderChanged"
        )
        GclConsole.durationSlider.value = GclConsole.config.fleet.highlightDuration
        GclConsole.durationLabel = tab:createLabel(
            Rect(padding + 260, y, padding + 310, y + 20),
            string.format("%ds", GclConsole.config.fleet.highlightDuration), 12
        )
        y = y + 28

        -- Pulse speed dropdown
        tab:createLabel(Rect(padding, y, padding + 80, y + 20), "Pulse Speed:", 12)
        GclConsole.pulseSpeedCombo = tab:createComboBox(
            Rect(padding + 85, y - 2, padding + 200, y + 22),
            "onPulseSpeedChanged"
        )
        GclConsole.pulseSpeedCombo:addEntry("Slow")
        GclConsole.pulseSpeedCombo:addEntry("Normal")
        GclConsole.pulseSpeedCombo:addEntry("Fast")
        -- Select current setting
        local speedIdx = ({ slow = 0, normal = 1, fast = 2 })[GclConsole.config.fleet.pulseSpeed] or 1
        GclConsole.pulseSpeedCombo:setSelectedIndexNoCallback(speedIdx)
        y = y + 28

        -- Show arrow checkbox
        GclConsole.showArrowCheckbox = tab:createCheckBox(
            Rect(padding, y, padding + 150, y + 20),
            "Show Arrow",
            "onShowArrowChanged"
        )
        GclConsole.showArrowCheckbox.checked = GclConsole.config.fleet.showArrow

        -- Play sound checkbox
        GclConsole.playSoundCheckbox = tab:createCheckBox(
            Rect(padding + 160, y, padding + 310, y + 20),
            "Play Sound",
            "onPlaySoundChanged"
        )
        GclConsole.playSoundCheckbox.checked = GclConsole.config.fleet.playSound
        y = y + 28

        -- Color selection label
        tab:createLabel(Rect(padding, y, padding + 80, y + 20), "Color:", 12)
        y = y + 22

        -- Color selection using buttons (Selection/ColorSelectionItem complex, use simple buttons)
        local colorBtnWidth = 45
        local colorX = padding
        for i, colorEntry in ipairs(GclConsole.HIGHLIGHT_COLORS) do
            local btn = tab:createButton(
                Rect(colorX, y, colorX + colorBtnWidth, y + 25),
                colorEntry.name:sub(1, 3), -- Short name: "Ora", "Red", etc.
                "onColorButtonPressed"
            )
            btn.backgroundColor = ColorRGB(colorEntry.color.r, colorEntry.color.g, colorEntry.color.b)
            btn.tooltip = colorEntry.name
            -- Store color index in button tag (not supported, use workaround)
            colorX = colorX + colorBtnWidth + 5
        end
        y = y + 35

        -- Separator before activity log
        tab:createLine(vec2(padding, y), vec2(tabSize.x - padding, y))
        y = y + 10

        -- Activity log label
        tab:createLabel(
            Rect(padding, y, tabSize.x - padding, y + 20),
            "Activity Log:",
            12
        )
        y = y + 25

        -- Activity log ListBox (remaining space)
        local logHeight = tabSize.y - y - padding - 10
        GclConsole.fleetActivityListBox = tab:createListBox(
            Rect(padding, y, tabSize.x - padding, y + logHeight)
        )
        GclConsole.fleetActivityListBox.fontSize = 11

        -- Populate existing log entries
        for _, entry in ipairs(GclConsole.fleetActivityLog) do
            GclConsole.fleetActivityListBox:addEntry(entry)
        end
    end

    -- Target marking toggle handler
    function GclConsole.onTargetMarkingToggled(checkBox)
        GclConsole.targetMarkingEnabled = checkBox.checked
        if GclConsole.targetMarkingEnabled then
            displayChatMessage("Target marking enabled", "Fleet", 0)
        else
            displayChatMessage("Target marking disabled", "Fleet", 0)
            GclConsole.clearTargetHighlight() -- Clear any active highlight
        end
    end

    -- Mark Target button handler
    function GclConsole.onFleetMarkTargetPressed()
        local player = Player()
        if not player then return end

        local craft = player.craft
        if not craft then
            displayChatMessage("No ship controlled", "Fleet", 1)
            return
        end

        local target = craft.selectedObject
        if not target or not valid(target) then
            displayChatMessage("No target selected. Select a target first (Tab key).", "Fleet", 1)
            return
        end

        invokeServerFunction("broadcastTargetHighlight", target.id.string)
        displayChatMessage(string.format("Marked target: %s", target.name or "Unknown"), "Fleet", 0)
        GclConsole.addFleetLogEntry(string.format("SENT: Marked %s", target.name or "Unknown"))
    end

    -- DEV: Spawn Test Target button handler
    function GclConsole.onSpawnTestTargetPressed()
        invokeServerFunction("devSpawnTestTarget")
        GclConsole.addFleetLogEntry("DEBUG: Requesting test target from server...")
    end

    -- Add entry to the Fleet activity log
    function GclConsole.addFleetLogEntry(message)
        -- Get timestamp
        local timestamp = os.date("%H:%M:%S")
        local entry = string.format("[%s] %s", timestamp, message)

        -- Add to in-memory log
        table.insert(GclConsole.fleetActivityLog, entry)

        -- Trim if too long
        while #GclConsole.fleetActivityLog > GclConsole.MAX_FLEET_LOG_ENTRIES do
            table.remove(GclConsole.fleetActivityLog, 1)
        end

        -- Add to ListBox if it exists and is valid
        if valid(GclConsole.fleetActivityListBox) then
            -- Clear and repopulate to stay in sync with trimmed log
            GclConsole.fleetActivityListBox:clear()
            for _, logEntry in ipairs(GclConsole.fleetActivityLog) do
                GclConsole.fleetActivityListBox:addEntry(logEntry)
            end
        end
    end

    -- Settings callback: Duration slider changed
    function GclConsole.onDurationSliderChanged(slider)
        local val = math.floor(slider.value + 0.5)
        GclConsole.config.fleet.highlightDuration = val
        if GclConsole.durationLabel then
            GclConsole.durationLabel.caption = string.format("%ds", val)
        end
        GclConsole.saveFleetConfig()
    end

    -- Settings callback: Pulse speed dropdown changed
    function GclConsole.onPulseSpeedChanged(comboBox)
        local idx = comboBox.selectedIndex
        local speeds = { "slow", "normal", "fast" }
        GclConsole.config.fleet.pulseSpeed = speeds[idx + 1] or "normal"
        GclConsole.saveFleetConfig()
    end

    -- Settings callback: Show arrow checkbox changed
    function GclConsole.onShowArrowChanged(checkBox)
        GclConsole.config.fleet.showArrow = checkBox.checked
        GclConsole.saveFleetConfig()
    end

    -- Settings callback: Play sound checkbox changed
    function GclConsole.onPlaySoundChanged(checkBox)
        GclConsole.config.fleet.playSound = checkBox.checked
        GclConsole.saveFleetConfig()
    end

    -- Settings callback: Color button pressed
    function GclConsole.onColorButtonPressed(button)
        -- Find matching color by button background
        local btnColor = button.backgroundColor
        for _, colorEntry in ipairs(GclConsole.HIGHLIGHT_COLORS) do
            -- Match by checking if it's this color's button (using tooltip)
            if button.tooltip == colorEntry.name then
                GclConsole.config.fleet.highlightColor = colorEntry.color
                GclConsole.saveFleetConfig()
                displayChatMessage("Highlight color: " .. colorEntry.name, "Fleet", 0)
                break
            end
        end
    end
end -- if onClient()
