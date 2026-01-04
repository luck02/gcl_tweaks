# Changelog

All notable changes to GCL Tweaks will be documented in this file.

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
