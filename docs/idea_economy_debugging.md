# Avorion Economy Bottleneck Debugging - Feature Idea

> **Status**: Phase 2 COMPLETE (Sector Tab implemented)  
> **Created**: 2026-01-03  
> **Updated**: 2026-01-04  
> **Priority**: Medium  

## Problem Statement

When managing complex economy setups with stations linked via "get from" / "ship to" trade routes, production bottlenecks are difficult to debug because:

1. **Reactive detection**: You only notice problems when a station stops making money
2. **Manual investigation**: Must visit each station individually to check inputs/outputs
3. **Chain tracing**: Bottlenecks cascade through production chains (e.g., missing iron ore → no steel → no ships)
4. **No proactive alerts**: The game doesn't notify you of impending issues before they cause production halts

## Research Findings

### Key Bottleneck Causes

| Cause | Description | Detection Method |
|-------|-------------|------------------|
| **Missing Ingredients** | Factory lacks input materials | `Factory.getNumGoods(ingredient.name) < ingredient.amount` |
| **Full Output Storage** | Products fill cargo bay, halting production | `freeCargoSpace < result.amount * size` |
| **Shuttle Inefficiency** | Cargo shuttles can't keep up with demand | Compare shuttle capacity vs. production rate |
| **Delivery Errors** | "Get from" / "Ship to" links are broken | `deliveredStationsErrors`, `deliveringStationsErrors` |
| **Price Slider Issues** | NPC traders won't buy/sell at current prices | Check stock levels vs. price factor |
| **Production Slot Limits** | All 2-6 production slots are busy | `numProductions >= Factory.maxNumProductions` |

### Available APIs in Factory.lua

```lua
-- Production State
production.ingredients[]     -- Required inputs with {name, amount, optional}
production.results[]         -- Outputs with {name, amount}
production.garbages[]        -- Byproducts with {name, amount}
currentProductions           -- Active production slots
Factory.maxNumProductions    -- Maximum parallel productions (2-6)

-- Stock Levels
Factory.getNumGoods(name)    -- Current stock of a good
Factory.getMaxStock(good)    -- Maximum stock capacity
Entity().freeCargoSpace      -- Available cargo space

-- Financial Stats (via TradingManager)
Factory.trader.stats.moneySpentOnGoods
Factory.trader.stats.moneyGainedFromGoods
Factory.trader.stats.moneyGainedFromTax

-- Error States
newProductionError           -- Current production error string (RUNTIME ONLY - not persisted)
deliveredStationsErrors[]    -- Errors for "ship to" stations
deliveringStationsErrors[]   -- Errors for "get from" stations
```

### Cross-Sector Access Limitation

- `ShipDatabaseEntry:getSecuredScriptValues()` provides financial stats but NOT runtime production state
- `productionError` is a **local variable** in `factory.lua` - NOT exported by `secure()`
- For detailed diagnostics, the sector must be loaded and we must query `factory.lua` directly

## Implementation Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Basic status column in Trade tab | ✅ Complete (v1.4.1) |
| 2 | Dedicated Sector tab with detailed diagnostics | ✅ Complete (v1.5.0) |
| 3 | Proactive alerts for state transitions | 🔲 Future |
| 4 | Supply chain visualization | 🔲 Future |

---

## Phase 1 Implementation Summary (v1.4.1)

### What Was Built
- **Status column** added to Trade tab between Station and Sector
- **Color-coded indicators**: OK (green), IDLE (orange), WARNING (yellow), HALTED (red)
- **Heuristic detection** using `currentProductions` count from secured values
- **Tooltips** show specific issue details on hover
- **Inclusive display**: Stations with issues appear even without trade history

### Technical Details
- Detection via `ShipDatabaseEntry:getSecuredScriptValues()` 
- Factory detection: Looking for `maxNumProductions` field
- IDLE = factory with `currentProductions == 0`
- Cross-sector compatible (no sector loading required)

### Limitation Discovered
`productionError` (the actual error message like "missing ingredients") is NOT persisted to secured values - it's runtime only. Detailed diagnostics require the sector to be loaded.

---

## Phase 2 Implementation Summary (v1.5.0)

### What Was Built
- **New "Sector" tab** added to GCL Console (3rd tab after Console, Trade)
- **Dedicated in-sector diagnostics** with 5 columns:
  - Station | Status | Cargo% | Lines | Missing Ingredients
- **Scan Sector button** with 30-second cooldown
- **Missing ingredients display** shows exactly what's lacking (e.g., "Iron Ore (0/5)")
- **Production lines active** shows "2/4" format

### Technical Approach
Since `productionError` is not available, we **re-derive** the issue by:
1. Calling `station:invokeFunction("factory.lua", "secure")` on in-sector stations
2. Getting `production.ingredients` from the recipe
3. Checking `station:getCargoAmount()` for actual stock levels
4. Calculating shortfall: `have < need` for non-optional ingredients
5. Checking `freeCargoSpace / maxCargoSpace` for cargo fill %

### Key Functions
- `getInSectorDiagnostics()` - Server: Queries all owned factory stations in current sector
- `receiveSectorDiagnostics()` - Client: Populates Sector tab with detailed info
- `buildSectorTab()` - Client: Creates the Sector tab UI

### Files Modified
- `data/scripts/player/gcl_console.lua`
  - Added Sector tab variables and `buildSectorTab()`
  - Added `onScanSector()`, `receiveSectorDiagnostics()` 
  - Added `getInSectorDiagnostics()` server function
  - Trade tab unchanged (status column from Phase 1 intact)

### What's NOT Available
- **Last production time**: Factory.lua doesn't store when production last completed
- **Production cycle ETA**: Could be calculated but would require tracking progress over time

---

## Future Phases

### Phase 3: Proactive Alerts
- Monitor for IDLE→HALTED transitions
- Notification when production stops
- Alert log with timestamps

### Phase 4: Supply Chain Visualizer
- Graph view of production chains
- Nodes = Stations, Edges = "get from"/"ship to" links
- Cascade failure detection
