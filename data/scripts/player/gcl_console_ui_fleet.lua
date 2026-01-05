-- GCL Console Fleet Tab - Simplified destination sync
-- Press F11 to broadcast (if no pending) or accept (if pending)
-- 15 second timeout for pending destinations

if onClient() then
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
    end

    -- Broadcast the current galaxy map selection to all players
    function GclConsole.broadcastFleetDestination()
        local x, y = GalaxyMap():getSelectedCoordinates()
        if x and y then
            invokeServerFunction("broadcastFleetDestinationSimple", x, y)
        else
            displayChatMessage("No sector selected on galaxy map.", "Fleet", 1)
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
                GclConsole.refreshFleetTab()
                return
            end

            GalaxyMap():setSelectedCoordinates(dest.x, dest.y)

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
        displayChatMessage(
            string.format("Destination (%d, %d) sent to %d player(s)", x, y, count),
            "Fleet", 0
        )
    end

    callable(GclConsole, "receiveFleetBroadcastResult")
end -- if onClient()
