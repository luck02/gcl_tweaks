# Avorion Economy Bottleneck Debugging - Feature Idea

> **Status**: IMPLEMENTED (Option A Phase 1 complete)  
> **Created**: 2026-01-03  
> **Updated**: 2026-01-03  
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
newProductionError           -- Current production error string
deliveredStationsErrors[]    -- Errors for "ship to" stations
deliveringStationsErrors[]   -- Errors for "get from" stations
```

### Cross-Sector Access Limitation

- `ShipDatabaseEntry:getSecuredScriptValues()` provides financial stats but NOT runtime production state
- For detailed diagnostics, the sector must be loaded

## Proposed Options

### Option A: "Economy Health Check" Dashboard (Recommended)

Add status indicators to existing Trade tab:
- 🟢 **Healthy**: Producing normally
- 🟡 **Warning**: Low inputs OR outputs filling up  
- 🔴 **Halted**: Production stopped

### Option B: "Alert System" with Notifications

Background monitoring with proactive alerts:
- "Production stopped at [Station Name]"
- "Low ingredients at [Station Name]"
- Alert log with timestamps

### Option C: "Supply Chain Visualizer" (Advanced)

Graph view of production chains:
- Nodes = Stations, Edges = Links
- Color-coded by health status
- Cascade failure detection

## UI Mockup (Option A)

```
┌───────────────────────────────────────────────────────────────────────┐
│ GCL Console - Economy Health                                   [X]    │
├───────────────────────────────────────────────────────────────────────┤
│  Economy Status: 3 healthy, 1 warning, 2 halted    [Scan Now]         │
├───────────────────────────────────────────────────────────────────────┤
│ ●  Station Name        │ Sector │ Status  │ Issue                     │
├────────────────────────┼────────┼─────────┼───────────────────────────┤
│ 🔴 Steel Factory       │ 120:-45│ HALTED  │ Missing: Coal (2), Iron   │
│ 🔴 Ship Factory        │ 120:-45│ HALTED  │ Missing: Steel (waiting)  │
│ 🟡 Advanced Alloys     │ 10:15  │ WARNING │ Cargo 92% full            │
│ 🟢 Iron Mine           │ -5:10  │ HEALTHY │ —                         │
└───────────────────────────────────────────────────────────────────────┘
```

## Implementation Phases

| Phase | Description | Effort |
|-------|-------------|--------|
| 1 | Basic status column in existing scan | Low |
| 2 | Ingredient shortfall detection (current sector) | Medium |
| 3 | Cross-sector status estimation (heuristic) | Medium |
| 4 | Supply chain visualization | High |

## Open Questions

1. Which option(s) to implement first?
2. Cross-sector detection: all stations (heuristics) or only current-sector?
3. Alert mechanism: in-console, chat, or both?
4. Supply chain depth: direct links or full chain?
