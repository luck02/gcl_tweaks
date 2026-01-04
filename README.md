# GCL Tweaks

**GCL Tweaks** is an Avorion mod that provides utility commands for server admins and players to debug and modify game state, plus a Trade Statistics dashboard.

## Features

- **Tabbed Console Window**: Press **F9** to toggle a dedicated console with two tabs:
  - **Console Tab**: Displays command output in a scrollable list
  - **Trade Tab**: Spreadsheet view of station trade statistics across all sectors
- **Drop Table Inspection**: View and modify system upgrade drop weights
- **Wrecked Status Management**: Check and modify "wrecked" (boarding malus) status on entities
- **Cross-Sector Trade Scanning**: Monitor owned station profits without loading sectors

## Installation

Subscribe to the mod on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3628589261).

To install manually:
1. Clone this repository into your local Avorion mods directory (e.g., `~/.avorion/mods/`)
2. Enable the mod in the in-game settings

## Usage

### Console Window

Press **F9** to toggle the console window. The Trade tab shows a spreadsheet of your stations with:
- Station name and sector coordinates
- Revenue, costs, and profit (color-coded)
- Totals row at the bottom

Use the **Scan Now** button for manual refresh (60-second cooldown to prevent server spam).

### Commands

Commands are accessed via the `/gcl_tweak` chat command.

#### `showdroptables`
Prints the current system upgrade drop weights.
```
/gcl_tweak showdroptables
```

#### `setdroprate <component> <multiplier>`
Adjust drop rates with persistent server-wide multipliers.
```
/gcl_tweak setdroprate civiltcs.lua 0.1
```

#### `isobjectwrecked`
Checks if the currently selected entity has the "wrecked" (boarding malus) status.
```
/gcl_tweak isobjectwrecked
```

#### `setobjectwrecked 0|1`
Sets or clears the "wrecked" status on the currently selected entity.
```
/gcl_tweak setobjectwrecked 1
```

#### `scantrade [0|1]`
Toggle automatic cross-sector trade scanning (default: on, runs every 5 minutes).
```
/gcl_tweak scantrade       # Show current status
/gcl_tweak scantrade 0     # Disable automatic scanning
/gcl_tweak scantrade 1     # Enable automatic scanning
```

## Development

This project uses a `Makefile` to streamline development tasks.

### Prerequisites
- Lua (for running tests)
- `git`
- `zip` (for packaging, handled by CI)

### Commands

**Run Tests**
```bash
make test
```

**Release**
Bump the version in `modinfo.lua`, run tests, commit, push, and trigger the deployment pipeline.
```bash
make release       # Patch release (e.g., 1.0.0 -> 1.0.1)
make release-minor # Minor release (e.g., 1.0.0 -> 1.1.0)
make release-major # Major release (e.g., 1.0.0 -> 2.0.0)
```

## Dependencies

- **AzimuthLib** (optional): Used for tabbed window UI and config persistence. Falls back gracefully if not installed.

## License

[MIT License](LICENSE)
