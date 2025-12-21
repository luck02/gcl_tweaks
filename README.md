# GCL Tweaks

**GCL Tweaks** is an Avorion mod that provides utility commands for server admins and players to debug and modify game state.

## Features

- **Drop Table Inspection**: View system upgrade drop weights.
- **Wrecked Status Management**: Check close "wrecked" (boarding malus) status on entities.
- **Status Modification**: Set or clear the "wrecked" status on selected objects.

## Installation

Subscribe to the mod on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3628589261).

To install manually:
1. Clone this repository into your local Avorion mods directory (e.g., `~/.avorion/mods/`).
2. Enable the mod in the in-game settings.

## Usage

Commands are accessed via the `/gcl_tweak` chat command.

### `showdroptables`
Prints the current system upgrade drop weights to the chat window.
```
/gcl_tweak showdroptables
```

### `isobjectwrecked`
Checks if the currently selected entity has the "wrecked" (boarding malus) status.
```
/gcl_tweak isobjectwrecked
```

### `setobjectwrecked`
Sets or clears the "wrecked" status on the currently selected entity.
- `0` to clear the status.
- `1` to set the status.
```
/gcl_tweak setobjectwrecked 1
```

## Development

This project uses a `Makefile` to streamline development tasks.

### Prerequisites
- Lua (for running tests)
- `git`
- `zip` (for packaging, handled by CI)

### Commands

**Run Tests**
Execute the test runner to verify script logic.
```bash
make test
```

**Create Pull Request**
Push the current feature branch and open a PR.
```bash
make pr
```

**Release**
Bump the version in `modinfo.lua`, run tests, commit, push, and trigger the deployment pipeline.
```bash
make release       # Patch release (e.g., 1.0.0 -> 1.0.1)
make release-minor # Minor release (e.g., 1.0.0 -> 1.1.0)
make release-major # Major release (e.g., 1.0.0 -> 2.0.0)
```

## License

[MIT License](LICENSE) (or specify your license)
