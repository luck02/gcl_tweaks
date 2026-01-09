-- GCL Console Fleet Tab - Simplified destination sync
-- Press F11 to broadcast (if no pending) or accept (if pending)
-- 15 second timeout for pending destinations

if onClient() then
    -- Activity log storage (in-memory, cleared on reload)
    GclConsole.fleetActivityLog = {}
    GclConsole.fleetActivityListBox = nil
    GclConsole.MAX_FLEET_LOG_ENTRIES = 50

    -- Build the simplified Fleet tab UI
    function GclConsole.buildFleetTab(tab)
        local tabSize = tab.size
        local padding = 15
        local y = padding

        -- Title / instruction
        local titleLabel = tab:createLabel(
            Rect(padding, y, tabSize.x - padding, y + 30),
            "Fleet Jump Coordination",
            16
        )
        y = y + 40

        -- Instructions
        local instructLabel = tab:createLabel(
            Rect(padding, y, tabSize.x - padding, y + 20),
            "Press F11: Broadcasts your map selection, or accepts a pending destination",
            12
        )
        y = y + 35

        -- Horizontal separator
        tab:createLine(vec2(padding, y), vec2(tabSize.x - padding, y))
        y = y + 15

        -- Status label
        GclConsole.fleetStatusLabel = tab:createLabel(
            Rect(padding, y, tabSize.x - padding, y + 25),
            "Status: Ready to broadcast",
            13
        )
        y = y + 35

        -- Pending destination frame (visible when destination is pending)
        GclConsole.fleetPendingFrame = tab:createFrame(
            Rect(padding, y, tabSize.x - padding, y + 80)
        )
        GclConsole.fleetPendingFrame.backgroundColor = ColorARGB(0.4, 0.2, 0.6, 0.2)

        -- Pending destination label (inside frame)
        GclConsole.fleetDestLabel = tab:createLabel(
            Rect(padding + 10, y + 10, tabSize.x - padding - 10, y + 35),
            "",
            14
        )

        -- Timer label
        GclConsole.fleetTimerLabel = tab:createLabel(
            Rect(padding + 10, y + 40, tabSize.x - padding - 10, y + 60),
            "",
            12
        )

        -- Accept hint
        local acceptHint = tab:createLabel(
            Rect(padding + 10, y + 60, tabSize.x - padding - 10, y + 75),
            "Press F11 to accept",
            11
        )

        y = y + 90

        -- Initially hide pending frame
        GclConsole.fleetPendingFrame:hide()
        GclConsole.fleetDestLabel:hide()
        GclConsole.fleetTimerLabel:hide()

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

        -- Activity log ListBox
        local logHeight = tabSize.y - y - padding - 30
        GclConsole.fleetActivityListBox = tab:createListBox(
            Rect(padding, y, tabSize.x - padding, y + logHeight)
        )
        GclConsole.fleetActivityListBox.fontSize = 11

        -- Populate existing log entries
        for _, entry in ipairs(GclConsole.fleetActivityLog) do
            GclConsole.fleetActivityListBox:addEntry(entry)
        end
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

    -- Broadcast the current galaxy map selection to all players
    function GclConsole.broadcastFleetDestination()
        local x, y = GalaxyMap():getSelectedCoordinates()
        if x and y then
            invokeServerFunction("broadcastFleetDestinationSimple", x, y)
            -- Log immediately (will be confirmed by server response)
            GclConsole.addFleetLogEntry(string.format("SENT: Broadcasting (%d, %d)...", x, y))
        else
            displayChatMessage("No sector selected on galaxy map.", "Fleet", 1)
            GclConsole.addFleetLogEntry("ERROR: No sector selected on galaxy map")
        end
    end

    -- Accept pending destination
    function GclConsole.acceptFleetDestination()
        if GclConsole.pendingFleetDest then
            local dest = GclConsole.pendingFleetDest

            -- Check for timeout
            local age = appTime() - dest.timestamp
            if age > GclConsole.FLEET_DEST_TIMEOUT then
                GclConsole.pendingFleetDest = nil
                displayChatMessage("Fleet destination expired.", "Fleet", 1)
                GclConsole.addFleetLogEntry(string.format("EXPIRED: (%d, %d) from %s", dest.x, dest.y,
                    dest.senderName or "Unknown"))
                GclConsole.refreshFleetTab()
                return
            end

            GalaxyMap():setSelectedCoordinates(dest.x, dest.y)

            -- Log acceptance
            GclConsole.addFleetLogEntry(string.format("ACCEPTED: (%d, %d) from %s", dest.x, dest.y,
                dest.senderName or "Unknown"))

            -- Clear pending and show confirmation
            GclConsole.pendingFleetDest = nil
            displayChatMessage(
                string.format("Destination accepted: (%d, %d)", dest.x, dest.y),
                "Fleet", 0
            )
            GclConsole.refreshFleetTab()
        end
    end

    -- Check for timeout (called from updateClient)
    function GclConsole.updateFleetTimeout(timestep)
        if GclConsole.pendingFleetDest then
            local age = appTime() - GclConsole.pendingFleetDest.timestamp
            if age > GclConsole.FLEET_DEST_TIMEOUT then
                local dest = GclConsole.pendingFleetDest
                GclConsole.addFleetLogEntry(string.format("TIMEOUT: (%d, %d) from %s expired", dest.x, dest.y,
                    dest.senderName or "Unknown"))
                GclConsole.pendingFleetDest = nil
                GclConsole.refreshFleetTab()
            else
                -- Update timer display
                local remaining = math.ceil(GclConsole.FLEET_DEST_TIMEOUT - age)
                if GclConsole.fleetTimerLabel then
                    GclConsole.fleetTimerLabel.caption = string.format(
                        "Expires in %d seconds", remaining
                    )
                end
            end
        end
    end

    -- Refresh the Fleet tab UI based on current state
    function GclConsole.refreshFleetTab()
        if not GclConsole.fleetTab then return end

        if GclConsole.pendingFleetDest then
            local dest = GclConsole.pendingFleetDest

            -- Update status
            if GclConsole.fleetStatusLabel then
                GclConsole.fleetStatusLabel.caption = "Status: Destination pending!"
            end

            -- Update destination display
            if GclConsole.fleetDestLabel then
                GclConsole.fleetDestLabel.caption = string.format(
                    "DESTINATION: (%d, %d) from %s",
                    dest.x, dest.y, dest.senderName or "Unknown"
                )
            end

            -- Show pending frame
            if GclConsole.fleetPendingFrame then
                GclConsole.fleetPendingFrame:show()
            end
            if GclConsole.fleetDestLabel then
                GclConsole.fleetDestLabel:show()
            end
            if GclConsole.fleetTimerLabel then
                GclConsole.fleetTimerLabel:show()
            end
        else
            -- Update status
            if GclConsole.fleetStatusLabel then
                GclConsole.fleetStatusLabel.caption = "Status: Ready to broadcast"
            end

            -- Hide pending frame
            if GclConsole.fleetPendingFrame then
                GclConsole.fleetPendingFrame:hide()
            end
            if GclConsole.fleetDestLabel then
                GclConsole.fleetDestLabel:hide()
            end
            if GclConsole.fleetTimerLabel then
                GclConsole.fleetTimerLabel:hide()
            end
        end
    end

    -- Called via RPC when another player broadcasts a destination
    function GclConsole.receiveFleetDestination(x, y, senderName)
        -- Log received destination
        GclConsole.addFleetLogEntry(string.format("RECEIVED: (%d, %d) from %s", x, y, senderName))

        -- Store pending destination with timestamp
        GclConsole.pendingFleetDest = {
            x = x,
            y = y,
            senderName = senderName,
            timestamp = appTime()
        }

        -- Show HUD notification
        Hud():displayHint(string.format(
            "Fleet destination: (%d, %d) from %s\nPress F11 to accept (15s)",
            x, y, senderName
        ))

        -- Play notification sound
        playSound("interface/select", SoundType.UI, 0.5)

        -- Update Fleet tab UI if visible
        GclConsole.refreshFleetTab()
    end

    callable(GclConsole, "receiveFleetDestination")

    -- Called via RPC when server confirms broadcast
    function GclConsole.receiveFleetBroadcastResult(count, x, y)
        -- Log confirmation
        GclConsole.addFleetLogEntry(string.format("CONFIRMED: (%d, %d) sent to %d player(s)", x, y, count))

        displayChatMessage(
            string.format("Destination (%d, %d) sent to %d player(s)", x, y, count),
            "Fleet", 0
        )
    end

    callable(GclConsole, "receiveFleetBroadcastResult")
end -- if onClient()
