-- GCL Console Targeting Module
-- Client-side render callback for fleet target highlighting
-- Displays pulsing visual indicators on highlighted targets

if onClient() then
    -- Targeting state
    GclConsole.highlightedTarget = nil
    GclConsole.highlightExpiry = 0
    -- HIGHLIGHT_DURATION now read from GclConsole.config.fleet.highlightDuration
    GclConsole.targetMarkingEnabled = true -- Toggle for receiving highlights

    -- Initialize targeting system
    function GclConsole.initTargetingUI()
        -- Register callback using namespace pattern (vanilla uses "onPostRenderIndicators" with Namespace.onPostRenderIndicators)
        Player():registerCallback("onPostRenderIndicators", "onPostRenderIndicators")
        print("[GCL Fleet] Target highlighting initialized")
    end

    -- Receive target highlight from another player (RPC handler)
    function GclConsole.receiveTargetHighlight(targetEntityId, senderName)
        print(string.format("[GCL Fleet] receiveTargetHighlight called: id=%s, sender=%s",
            tostring(targetEntityId), tostring(senderName)))

        -- Check if receiving is enabled
        if not GclConsole.targetMarkingEnabled then
            print("[GCL Fleet] Target marking disabled, ignoring highlight")
            return
        end

        local entity = Sector():getEntity(Uuid(targetEntityId))
        if not entity then
            print("[GCL Fleet] Target entity not found: " .. tostring(targetEntityId))
            return
        end

        -- Use config duration
        local duration = GclConsole.config.fleet.highlightDuration or 10
        GclConsole.highlightedTarget = entity
        GclConsole.highlightExpiry = appTime() + duration
        print(string.format("[GCL Fleet] Target stored: %s, expiry: %.1f", entity.name or "Unknown",
            GclConsole.highlightExpiry))

        -- HUD notification
        Hud():displayHint(string.format("Target marked by %s: %s", senderName, entity.name or "Unknown"))

        -- Play sound if enabled
        if GclConsole.config.fleet.playSound then
            playSound("interface/select", SoundType.UI, 0.5)
        end

        -- Log entry
        GclConsole.addFleetLogEntry(string.format("RECEIVED: %s marked %s", senderName, entity.name or "Unknown"))
    end

    callable(GclConsole, "receiveTargetHighlight")

    -- Clear current target highlight
    function GclConsole.clearTargetHighlight()
        if GclConsole.highlightedTarget then
            GclConsole.highlightedTarget = nil
            GclConsole.addFleetLogEntry("EXPIRED: Target highlight cleared")
        end
    end

    -- Broadcast confirmation handler (called from server)
    function GclConsole.onTargetBroadcastConfirmed(targetName, playerCount)
        GclConsole.addFleetLogEntry(string.format("CONFIRMED: %s sent to %d player(s)", targetName, playerCount))
    end

    callable(GclConsole, "onTargetBroadcastConfirmed")
end -- if onClient()

-- Render callback implementation (the actual logic)
-- Defined at global scope but checks client state internally
local renderFrameCount = 0
function GclConsole.renderTargetIndicator_impl()
    renderFrameCount = renderFrameCount + 1
    if renderFrameCount == 1 or renderFrameCount % 300 == 0 then
        print(string.format("[GCL Fleet] onPostRenderIndicators frame %d, hasTarget: %s",
            renderFrameCount, tostring(GclConsole.highlightedTarget ~= nil)))
    end

    if not GclConsole.highlightedTarget then return end

    -- Check if entity still exists
    if not valid(GclConsole.highlightedTarget) then
        GclConsole.clearTargetHighlight()
        return
    end

    local t = appTime()

    -- Check expiry
    if t > GclConsole.highlightExpiry then
        GclConsole.clearTargetHighlight()
        return
    end

    local renderer = UIRenderer()
    local entity = GclConsole.highlightedTarget

    -- Get config values with fallbacks
    local cfg = GclConsole.config and GclConsole.config.fleet or {}
    local baseColor = cfg.highlightColor or { r = 1, g = 0.5, b = 0 }
    local pulseSpeedName = cfg.pulseSpeed or "normal"
    local pulseMultiplier = (GclConsole.PULSE_SPEEDS and GclConsole.PULSE_SPEEDS[pulseSpeedName]) or 1.0
    local showArrow = cfg.showArrow
    if showArrow == nil then showArrow = true end

    -- Calculate pulse values (scaled by pulse speed multiplier)
    local fastPulse = (math.sin(t * 8 * pulseMultiplier) + 1) / 2 -- color cycle
    local slowPulse = (math.sin(t * 3 * pulseMultiplier) + 1) / 2 -- size pulse

    -- Pulsing color: interpolate between base color and brighter/dimmer variant
    local pulseIntensity = 0.3 + fastPulse * 0.7 -- 0.3 to 1.0
    local currentColor = ColorRGB(
        baseColor.r * pulseIntensity,
        baseColor.g * pulseIntensity,
        baseColor.b * pulseIntensity
    )

    -- Entity outline (targeter bracket)
    renderer:renderEntityTargeter(entity, currentColor)

    -- Pulsing TargetIndicator
    local indicator = TargetIndicator(entity)
    indicator.color = currentColor
    indicator.size = 80 + math.floor(slowPulse * 40) -- 80-120
    renderer:renderTargetIndicator(indicator)

    -- Dual-layer arrow pointing to target (if enabled)
    -- Made bigger, bolder, and flashing per user request
    if showArrow then
        -- Calculate screen position of entity for arrow direction
        local screenPos, onScreen = renderer:calculateEntityTargeter(entity)

        -- Strong flash effect (0 to 1, faster cycle)
        local flashPulse = (math.sin(t * 12 * pulseMultiplier) + 1) / 2 -- 0 to 1, fast

        -- Size pulsing: start large and pulse larger
        local arrowWidth = 40 + fastPulse * 20  -- 40-60 pixels wide
        local arrowLength = 80 + slowPulse * 40 -- 80-120 pixels long

        -- Flash between full brightness and dimmed
        local flashIntensity = 0.5 + flashPulse * 0.5 -- 0.5 to 1.0
        local flashColor = ColorRGB(
            baseColor.r * flashIntensity,
            baseColor.g * flashIntensity,
            baseColor.b * flashIntensity
        )

        -- Black outline for visibility against any background (thick)
        renderer:renderEntityArrow(entity, arrowWidth + 8, arrowLength + 16, 250, ColorRGB(0, 0, 0), 0.15)
        -- Colored core arrow (large and bold)
        renderer:renderEntityArrow(entity, arrowWidth, arrowLength, 250, flashColor, 0.15)

        -- Additional inner glow layer for more visibility
        local glowColor = ColorRGB(
            math.min(1, baseColor.r * 1.5),
            math.min(1, baseColor.g * 1.5),
            math.min(1, baseColor.b * 1.5)
        )
        renderer:renderEntityArrow(entity, arrowWidth * 0.5, arrowLength * 0.6, 250, glowColor, 0.15)
    end

    renderer:display()
end
