# GCL Console File Split Implementation Plan

> **Purpose**: Refactor the 1,577-line `gcl_console.lua` into smaller, more maintainable files.  
> **Why**: Improves tooling reliability and makes future edits more focused.

## Current State

```
data/scripts/player/gcl_console.lua  (1,577 lines, 65KB)
├── Variables & includes          (lines 1-58)
├── CLIENT: if onClient() then    (lines 59-...)
│   ├── initUI()                  (~30 lines)
│   ├── buildConsoleTab()         (~20 lines)
│   ├── buildTradeTab()           (~135 lines)
│   ├── buildSectorTab()          (~95 lines)
│   ├── updateClient()            (~55 lines)
│   ├── onScanNow(), onScanSector() (~30+65 lines)
│   ├── receiveSectorDiagnostics() (~90 lines)
│   ├── receiveAllStationsStats() (~100 lines)
│   └── ...other client handlers
├── SERVER: else (onServer)       (lines ~850-end)
│   ├── scanAllStations()         (~100 lines)
│   ├── getInSectorDiagnostics()  (~115 lines)
│   ├── attachTradeHooks()        (~100 lines)
│   └── ...other server functions
└── end
```

## Target Architecture

```
data/scripts/player/
├── gcl_console.lua               (Main entry, ~150 lines)
├── gcl_console_ui.lua            (Shared UI/client setup, ~100 lines)
├── gcl_console_trade.lua         (Trade tab, ~250 lines)
├── gcl_console_sector.lua        (Sector tab, ~200 lines)
└── gcl_console_server.lua        (Server functions, ~450 lines)
```

---

## Implementation Steps

### Step 1: Create `gcl_console_server.lua`

**Rationale**: Server code is cleanest to extract - no shared UI state.

**Contains:**
- `scanAllStations()` + callable
- `getInSectorDiagnostics()` + callable
- `attachTradeHooks()` + callable
- `scanOwnedStations()` + callable
- `scanAndGetStats()` + callable
- `getTradeStatus()` + callable
- `getTradeStats()` + callable

**Pattern:**
```lua
-- gcl_console_server.lua
-- Server-side functions for GCL Console

-- These functions are added to the GclConsole namespace
-- Must be included after GclConsole = {} is defined

if onServer() then
    function GclConsole.scanAllStations()
        -- ... existing code ...
    end
    callable(GclConsole, "scanAllStations")
    
    -- ... other server functions ...
end
```

**Verification:**
- All `callable()` registrations included
- `invokeClientFunction()` calls work correctly

---

### Step 2: Create `gcl_console_trade.lua`

**Contains:**
- Variables: `tradeStatusLabel`, `scanNowBtn`, `scanCooldownLabel`, `tradeScrollFrame`, `tradeRows`, etc.
- `buildTradeTab(tab)`
- `onScanNow()`
- `receiveTradeStatus()`
- `receiveAllStationsStats()`

**Pattern:**
```lua
-- gcl_console_trade.lua
-- Trade tab UI and callbacks

-- Shared variables for Trade tab (must be accessible to receive callbacks)
local tradeStatusLabel = nil
local scanNowBtn = nil
-- ... etc ...

if onClient() then
    function GclConsole.buildTradeTab(tab)
        -- ... existing code ...
    end
    
    function GclConsole.onScanNow()
        -- ... existing code ...
    end
    
    -- ... other Trade tab functions ...
end
```

---

### Step 3: Create `gcl_console_sector.lua`

**Contains:**
- Variables: `sectorStatusLabel`, `sectorScanBtn`, `sectorCooldownLabel`, `sectorScrollFrame`, `sectorRows`, etc.
- `buildSectorTab(tab)`
- `onScanSector()`
- `receiveSectorDiagnostics()`

**Pattern:** Same as Trade tab.

---

### Step 4: Refactor `gcl_console.lua` (Main Entry)

**Contains:**
- Package path setup
- `include()` statements for sub-modules
- Shared constants (`WINDOW_WIDTH`, `WINDOW_HEIGHT`, etc.)
- `GclConsole = {}` namespace setup
- `initUI()` - creates window and calls buildXxxTab() from included modules
- `initialize()`, `getParentIndex()`
- `updateClient()` - cooldown tick handling
- F9 toggle logic
- `show()`, `hide()`, `toggle()`
- Console tab (simplest, keep inline or extract if desired)

**Main file structure:**
```lua
-- gcl_console.lua
-- GCL Console main entry point

package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")
include("goods")

local CustomTabbedWindow = include("azimuthlib-customtabbedwindow")
local Azimuth = include("azimuthlib-basic")

-- namespace GclConsole
GclConsole = {}

-- Shared constants
local WINDOW_WIDTH = 700
local WINDOW_HEIGHT = 500

-- Include sub-modules (adds to GclConsole namespace)
include("gcl_console_trade")
include("gcl_console_sector")
include("gcl_console_server")

if onClient() then
    function GclConsole.initUI()
        -- Create window
        -- Call GclConsole.buildTradeTab(tradeTab)  -- from included module
        -- Call GclConsole.buildSectorTab(sectorTab) -- from included module
    end
    
    -- ... updateClient, toggle, etc. ...
end
```

---

## Verification Checklist

- [ ] `make test` passes
- [ ] F9 toggle works
- [ ] Trade tab: Scan Now populates data
- [ ] Trade tab: Status column shows OK/IDLE/WARNING/HALTED
- [ ] Sector tab: Scan Sector populates data
- [ ] Sector tab: Shows missing ingredients
- [ ] Cooldowns work on both tabs

---

## Key Technical Notes

### Include Path
Avorion's `include()` searches `data/scripts/lib/` by default. For player scripts, use relative paths or adjust package.path if needed:
```lua
package.path = package.path .. ";data/scripts/player/?.lua"
```

### Variable Scope
Local variables defined in included files are NOT accessible from the main file. Options:
1. **Attach to namespace**: `GclConsole.tradeRows = {}` (accessible everywhere)
2. **Return from module**: `local trade = include("gcl_console_trade"); trade.buildTradeTab()`
3. **Keep UI state in each module**: Each tab manages its own state (recommended)

### Callable Registration
`callable()` must be called **in the same context** where the function is defined. Keep `callable()` calls alongside their functions in the split files.

---

## File Size Targets

| File | Target Lines | Purpose |
|------|-------------|---------|
| `gcl_console.lua` | ~150 | Entry, window, includes |
| `gcl_console_trade.lua` | ~250 | Trade tab UI + callbacks |
| `gcl_console_sector.lua` | ~200 | Sector tab UI + callbacks |
| `gcl_console_server.lua` | ~450 | All server-side logic |

**Total**: ~1,050 lines (down from 1,577 due to reduced boilerplate)
