# Changelog

All notable changes to GCL Tweaks will be documented in this file.

## [1.6.0] - 2026-01-05

### Added
- **Fleet Jump Coordination** - New "Fleet" tab for multiplayer destination sync
  - Press F11 to broadcast your galaxy map selection to all other players
  - Press F11 again to accept a pending destination (sets your map coordinates)
  - 15 second timeout for pending destinations
  - HUD notification when destination is received
  - No configuration required - just press F11

## [1.5.0] - 2026-01-04

### Added
- **Sector Tab** - New "Sector" tab for in-sector station diagnostics
  - Detailed view of stations in current sector
  - Cargo fill %, active production lines, missing ingredients
  - Separate 30-second scan cooldown

### Changed
- **Code Refactor** - Split gcl_console.lua into modular files for maintainability:
  - `gcl_console_server.lua` - Server-side trade scanning and data persistence
  - `gcl_console_ui_console.lua` - Console tab UI
  - `gcl_console_ui_trade.lua` - Trade tab UI
  - `gcl_console_ui_sector.lua` - Sector tab UI

### Fixed
- Fixed console window not appearing (reverted from ScriptUI to Hud API)
- Fixed missing tab icons (corrected texture paths)

## [1.4.0] - 2026-01-03

### Added
- **Economy Health Dashboard** - Status column in Trade tab shows station health
  - 🟢 OK: Factory actively producing
  - 🟠 IDLE: 0 active production lines (hover for details)
  - 🟡 WARNING: Delivery chain issues
  - 🔴 HALTED: Production error (when sector loaded)
- Cross-sector detection using currentProductions count heuristic
- Stations with issues now appear in Trade tab even without trade history
- Tooltip on status showing specific issue details

## [1.3.0] - 2026-01-03

### Added
- Tabbed Console Window - Press F9 to toggle Console and Trade tabs
- Trade Tab - Spreadsheet view showing station profits across ALL sectors
- Cross-sector scanning using ShipDatabaseEntry (no sector loading required)
- Automatic scanning every 5 minutes (toggle with /gcl_tweak scantrade)
- Scan Now button with 60-second cooldown to prevent server spam
- New command: /gcl_tweak scantrade [0|1]

### Fixed
- Fixed crash during console initialization (Player() nil during early init)

## [1.2.2] - 2025-12-27

### Added
- Dynamic drop rate tweaking with /gcl_tweak setdroprate
- Persistent server-wide multipliers using AzimuthLib config

## [1.2.0] - 2025-12-21

### Added
- Console window for command output (F9 to toggle)
- Direct RPC for server-to-client communication

## [1.1.0] - 2025-12-21

### Added
- Initial release with showdroptables, isobjectwrecked, setobjectwrecked commands
