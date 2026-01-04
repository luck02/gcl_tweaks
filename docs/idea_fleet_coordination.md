# Fleet Coordination System - Feature Idea

> **Status**: IDEA  
> **Created**: 2026-01-03  
> **Priority**: High  

## Problem Statement

In multiplayer Avorion, coordinating fleet jumps between two player-operated ships is tedious and error-prone:

**Current Workflow:**
1. User A opens galaxy map, marks a sector, clicks "Enter Coordinates Into Navigation Computer"
2. User A communicates destination to User B (voice/chat)
3. User B opens galaxy map, finds same sector, enters coordinates
4. Both players jump individually (timing often mismatched)

**Issues:**
- Manual coordinate transcription is error-prone
- Timing synchronization is difficult
- Context switching between map and combat is disruptive
- No shared awareness of fleet intent

## Proposed Features

### Feature 1: Fleet Jump Destination Sync

**Concept**: When the "leader" ship sets a jump destination, follower ships automatically receive and optionally set the same destination.

**User Story:**
> As Player B, I want my ship's navigation computer to automatically receive Player A's selected jump destination so we can jump together without manual coordination.

### Feature 2: Shared Combat Targeting

**Concept**: When the leader ship selects a target, follower ships automatically receive and optionally target the same entity.

**User Story:**
> As Player B, I want my turrets to automatically target whatever Player A is targeting so we can focus fire effectively.

## API Research Findings

### Jump Destination APIs

| API | Context | Purpose |
|-----|---------|---------|
| `GalaxyMap().getSelectedCoordinates()` | Client | Get currently selected sector (x, y) |
| `GalaxyMap().setSelectedCoordinates(x, y)` | Client | Set the selected sector destination |
| `HyperspaceEngine():jump(x, y)` | Server | Immediately initiate hyperspace jump |
| `HyperspaceEngine():tryJump(x, y)` | Server | Attempt jump, returns JumpError on failure |
| `HyperspaceEngine().range` | Both | Current jump range in sectors |
| `HyperspaceEngine().currentCooldown` | Both | Time until jump drive is ready |

### Target Selection APIs

| API | Context | Purpose |
|-----|---------|---------|
| `ControlUnit():getSelectedTargetIds()` | Both | Returns list of selected targets from all seats |
| `Entity.selectedObject` | Client | Currently selected entity (if any) |

### Cross-Player Communication

The existing `gcl_console.lua` already demonstrates the pattern:
1. **Server holds shared state**: Leader's destination stored in server-side player values
2. **Polling or event-driven updates**: Followers query server periodically or on demand
3. **Client-side RPC**: `invokeClientFunction` to push updates to followers

## Technical Feasibility Assessment

### Jump Destination Sync: ✅ **FEASIBLE**

**Approach:**
1. Leader clicks "Set As Fleet Destination" button (new UI element)
2. Server stores `{x, y}` in a shared table keyed by playerIndex or alliance
3. Followers receive RPC with destination, calls `GalaxyMap():setSelectedCoordinates(x, y)`
4. Optional: Auto-jump when leader jumps (via callback)

**Challenges:**
- `GalaxyMap` is CLIENT-ONLY - cannot directly set coordinates server-side
- Need to handle players in different sectors (different hyperspace ranges)
- Edge case: What if follower can't reach destination (insufficient range)?

**Solution:**
```lua
-- Leader broadcasts destination
invokeClientFunction(followerPlayer, "receiveFleetDestination", x, y)

-- Follower receives and sets
function GclFleet.receiveFleetDestination(x, y)
    GalaxyMap():setSelectedCoordinates(x, y)
end
```

### Shared Combat Targeting: ⚠️ **PARTIALLY FEASIBLE**

**Challenge:** No direct API to SET a player's selected target.

**Findings:**
- `ControlUnit():getSelectedTargetIds()` only READS targets
- No `setSelectedTarget()` equivalent exposed in the API
- Turrets can be controlled via `TurretAI` but this bypasses player selection UI

**Workaround Options:**
1. **Display-only**: Show leader's target in UI, player manually clicks to target
2. **Turret override**: Force player's turrets to fire at leader's target (bypasses player control)
3. **Target suggestion**: Highlight leader's target in sector view

**Recommendation:** Start with display-only; true target sync may require engine changes.

## Proposed Implementation

### Phase 1: Fleet Ops Tab (UI Foundation)

Add a "Fleet" tab to the GCL Console:

```
┌───────────────────────────────────────────────────────────────────────┐
│ GCL Console                                                    [X]    │
├───────────────────────────────────────────────────────────────────────┤
│  [Console]  [Trade]  [Fleet]                                          │
├───────────────────────────────────────────────────────────────────────┤
│  Fleet Role: [●] Leader  [○] Follower                                 │
│                                                                       │
│  --- Leader Mode ---                                                  │
│  Jump Destination: (120, -45)              [Broadcast]                │
│  Current Target: "Xsotan Destroyer"        [Broadcast Target]         │
│                                                                       │
│  --- Followers ---                                                    │
│  • PlayerB (SteelClaw) - In range ✓                                   │
│  • PlayerC (Hunter)    - Out of range (needs 2 more sectors)          │
├───────────────────────────────────────────────────────────────────────┤
│  [✓] Auto-sync jump destination                                       │
│  [✓] Show leader's target indicator                                   │
│  [ ] Auto-jump when leader jumps                                      │
└───────────────────────────────────────────────────────────────────────┘
```

### Phase 2: Jump Destination Sync

**Data Flow:**
```
Leader Client                Server                    Follower Client
     │                          │                            │
     │ "Broadcast Destination"  │                            │
     ├─────────────────────────►│                            │
     │                          │ Store {x, y, leaderId}     │
     │                          ├───────────────────────────►│
     │                          │ invokeClientFunction       │
     │                          │                            │
     │                          │              setSelectedCoordinates(x, y)
     │                          │                            │
```

**Implementation Files:**
- `gcl_console.lua`: Add Fleet tab UI
- New server function: `broadcastFleetDestination(x, y)`
- New client function: `receiveFleetDestination(x, y)`

### Phase 3: Target Sharing (Display Only)

- Leader broadcasts target entity ID
- Followers display an icon/highlight on that entity in sector view
- Players still manually select target, but have visual guidance

### Phase 4: Auto-Jump (Optional, Advanced)

When leader initiates jump:
1. Server callback on `onJumpRouteCalculationStarted`
2. Server notifies all followers
3. Followers auto-trigger jump (if enabled in settings)

## Configuration Options

```lua
fleetConfig = {
    role = "follower",           -- "leader" | "follower" | "none"
    leaderPlayerIndex = nil,     -- Who to follow
    autoSyncDestination = true,  -- Auto-update nav when leader broadcasts
    showLeaderTarget = true,     -- Highlight leader's target in sector
    autoJumpWithLeader = false,  -- Dangerous: auto-jump on leader's command
}
```

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| No setSelectedTarget API | Confirmed | Medium | Display-only target sharing initially |
| Players in different sectors | Medium | Low | Only sync when in same sector |
| Griefing potential (unwanted jumps) | Low | High | Require explicit "follow" consent |
| Range mismatch | Medium | Low | Show range warning in UI |

## Open Questions

1. **Scope**: Should this work across alliances, or just within player's own ships/group?
2. **Persistence**: Should fleet role persist across sessions, or reset on login?
3. **UI Location**: New tab in GCL Console, or separate Fleet window?
4. **Target Sync Depth**: Display only, or attempt turret control?
5. **Auto-jump**: Too dangerous to implement? Require confirmation?

## Next Steps

1. Implement Fleet tab UI shell
2. Implement destination broadcast/receive
3. Test with two players in same sector
4. Add range validation feedback
5. Implement target display (optional)
