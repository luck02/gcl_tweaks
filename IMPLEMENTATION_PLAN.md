# GCL Tweaks - Implementation Plan

## Overview

**GCL Tweaks** is a command-based utility mod for Avorion. It provides server-side admin/debugging commands to inspect and modify game states that are otherwise difficult to access.

## Features

### 1. Drop Table Inspection
Inspect the current weightings for system upgrade drops.
- **Command:** `/gcl_tweak showdroptables`
- **Functionality:** Prints a formatted list of drop weights and probabilities to the chat window.

### 2. Wrecked Status Management
Inspect and modify the "Boarding Malus" state of entities. This is useful for fixing ships that are permanently stuck in a "wrecked" state (unrepairable at minimal HP) due to bugs or incomplete boarding operations.
- **Command:** `/gcl_tweak isobjectwrecked`
    - Checks if the selected entity has `MalusReason.Boarding`.
- **Command:** `/gcl_tweak setobjectwrecked <0|1>`
    - `0`: Clears the malus and restores durability to max (fixes the ship).
    - `1`: Applies the malus (breaks the ship/marks as wrecked).

## Technical Architecture

### File Structure
```
gcl_tweaks/
├── modinfo.lua                  # Mod metadata
├── data/scripts/
│   └── commands/
│       └── gcl_tweak.lua        # Main command logic
├── .github/
│   └── workflows/
│       └── steam-deploy.yml     # CI/CD Pipeline
└── Makefile                     # Local development tasks
```

### Components

#### `data/scripts/commands/gcl_tweak.lua`
The core script. Implements the `execute` function required by Avorion's command system.
- Parsers subcommands.
- Interacts with `Player()`, `Entity()`, and `Sector()` APIs.
- Uses `MalusReason` enum for checking status.

## Verification Plan

### Manual Testing
1.  **Drop Tables**: Run `/gcl_tweak showdroptables`. Verify output appears in chat and percentages sum to 100%.
2.  **Check Wrecked**: Select a normal ship. Run `/gcl_tweak isobjectwrecked`. Should report "NO".
3.  **Set Wrecked**: Run `/gcl_tweak setobjectwrecked 1`. Verify ship reports `MalusReason.Boarding`.
4.  **Fix Wrecked**: Run `/gcl_tweak setobjectwrecked 0`. Verify ship is restored and malus is cleared.

### Deployment Verification
- Verify `modinfo.lua` has correct version.
- Verify GitHub Actions pipeline runs successfully on push.
- Verify Steam Workshop item updates correctly.
