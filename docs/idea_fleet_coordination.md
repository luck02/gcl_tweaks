# Fleet Coordination System

> **Status**: Phase 1 IMPLEMENTED (v1.6.0), Phase 2 PLANNED  
> **Created**: 2026-01-03  
> **Updated**: 2026-01-05  

## Implemented Features (v1.6.0)

### Fleet Jump Destination Sync ✅

**Keybind**: F11 (dual-purpose)

**How it works:**
- Press **F11** with no pending destination → broadcasts your galaxy map selection to all players
- Press **F11** with a pending destination → accepts it (sets your galaxy map coordinates)
- **15 second timeout** - pending destinations auto-expire
- **HUD notification** when destination is received
- No configuration required

**Files:**
- `gcl_console.lua` - F11 handler, Fleet tab upvalues
- `gcl_console_ui_fleet.lua` - Fleet tab UI
- `gcl_console_server.lua` - `broadcastFleetDestinationSimple()` function

---

## Phase 2: Combat Target Sharing (PLANNED)

### Problem Statement

In combat, coordinating focus fire between alliance members is difficult:
- Voice communication introduces delay
- No visual indicator of what your ally is targeting
- Manual target selection loses time in fast-paced fights

### Proposed Feature: Target Call-Out

**Concept**: Press a key to "call" your current target. Alliance members in the same sector receive a notification and can accept to target the same entity.

### User Story

> As Player B, I want to see what Player A is targeting and quickly select the same target so we can focus fire effectively.

### Technical Design

**Keybind**: F12 (dual-purpose, same pattern as F11)
- Press **F12** with no pending target → broadcasts your selected target to alliance members in-sector
- Press **F12** with a pending target → accepts it (attempts to select that entity)

**Key Difference from Jump Sync:**
- Only works for players in the **same sector** (targets don't exist cross-sector)
- Only broadcasts to **alliance members** (not all players)
- Target must still be alive when accepted

### API Research

| API | Context | Purpose |
|-----|---------|---------|
| `Player().selectedObject` | Client | Currently selected entity |
| `ControlUnit():getSelectedTargetIds()` | Both | Selected targets from all seats |
| `Entity(id)` | Both | Get entity by ID |
| `Entity().translatedTitle` | Both | Display name for notification |

**Challenge**: No direct `setSelectedTarget()` API exists.

**Workaround**: Use `GalaxyMap():setSelectedCoordinates()` pattern - we can't force target selection, but we can:
1. Display HUD notification with target name
2. Show visual indicator (if possible via sector callbacks)
3. Player manually clicks to confirm target

### Implementation Plan

#### Server Changes (`gcl_console_server.lua`)

```lua
function GclConsole.broadcastCombatTarget(entityId)
    local sender = Player(callingPlayer) or Player()
    if not sender then return end
    
    local entity = Entity(entityId)
    if not entity or not valid(entity) then return end
    
    local targetName = entity.translatedTitle or entity.name or "Unknown"
    
    -- Only broadcast to alliance members in same sector
    local allPlayers = {Server():getOnlinePlayers()}
    local senderSector = {sender:getSectorCoordinates()}
    local notified = 0
    
    for _, recipient in pairs(allPlayers) do
        if recipient.index ~= sender.index then
            -- Check same sector
            local recipientSector = {recipient:getSectorCoordinates()}
            if recipientSector[1] == senderSector[1] and recipientSector[2] == senderSector[2] then
                -- Check alliance (same alliance or same player group)
                if recipient.allianceIndex == sender.allianceIndex then
                    invokeClientFunction(recipient, "receiveCombatTarget", entityId, targetName, sender.name)
                    notified = notified + 1
                end
            end
        end
    end
    
    invokeClientFunction(sender, "receiveCombatTargetResult", notified, targetName)
end
callable(GclConsole, "broadcastCombatTarget")
```

#### Client Changes (`gcl_console_ui_fleet.lua`)

```lua
GclConsole.pendingCombatTarget = nil  -- {entityId, targetName, senderName, timestamp}
GclConsole.COMBAT_TARGET_TIMEOUT = 15

function GclConsole.broadcastCombatTarget()
    local selected = Player().selectedObject
    if selected and valid(selected) then
        invokeServerFunction("broadcastCombatTarget", selected.id)
    else
        displayChatMessage("No target selected.", "Fleet", 1)
    end
end

function GclConsole.acceptCombatTarget()
    if GclConsole.pendingCombatTarget then
        local target = GclConsole.pendingCombatTarget
        local entity = Entity(target.entityId)
        
        if entity and valid(entity) then
            -- Can't programmatically select, but can cycle to it or show indicator
            displayChatMessage(string.format("Target: %s", target.targetName), "Fleet", 0)
            -- TODO: Visual indicator implementation
        else
            displayChatMessage("Target no longer valid.", "Fleet", 1)
        end
        
        GclConsole.pendingCombatTarget = nil
    end
end

function GclConsole.receiveCombatTarget(entityId, targetName, senderName)
    GclConsole.pendingCombatTarget = {
        entityId = entityId,
        targetName = targetName,
        senderName = senderName,
        timestamp = appTime()
    }
    
    Hud():displayHint(string.format(
        "TARGET: %s (from %s)\nPress F12 to focus (15s)",
        targetName, senderName
    ))
    
    playSound("interface/select", SoundType.UI, 0.5)
end
callable(GclConsole, "receiveCombatTarget")
```

### UI Enhancement Ideas

1. **Target indicator in sector view** - Draw an arrow or highlight around the called target
2. **Fleet tab combat section** - Show currently called target with "Focus" button
3. **Sound cue** - Different sound for combat call-out vs jump destination

### Verification Plan

1. Two players in same sector, same alliance
2. Player A selects enemy, presses F12
3. Player B receives HUD notification with target name
4. Player B presses F12 within 15 seconds
5. Verify: HUD shows "Target: [name]" confirmation

---

## Future Ideas

### Phase 3: Visual Target Indicator
- Use `onPreRenderHud` callback to draw indicator around called target
- Research: How to draw sector-space elements from player script

### Phase 4: Auto-Jump with Leader
- When leader initiates jump, followers auto-jump (opt-in only)
- Dangerous feature - requires explicit consent mechanism

### Phase 5: Formation Flying
- Maintain relative position to leader ship
- Likely requires ship AI script, not player script
