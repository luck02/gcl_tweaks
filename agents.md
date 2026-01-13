# agents.md

This file provides guidance to AI coding assistants when working with code in this repository.

## Project Overview

**GCL Tweaks** is an Avorion mod that provides utility commands for server admins and players to debug/modify game state.
Current features:
- Drop table inspection (`/gcl_tweak showdroptables`)
- Wrecked status management (`/gcl_tweak isobjectwrecked`, `/gcl_tweak setobjectwrecked`)

## Mod Structure

- `modinfo.lua`: Mod metadata (ID: `gcl_tweaks`, version: `1.0.0`)
- `data/scripts/commands/gcl_tweak.lua`: Main command implementation
- `run_tests.lua`: Test runner
- `Makefile`: Development and release automation workflows

## Development Workflow

### File Organization
- Command scripts go in `data/scripts/commands/`
- Shared libraries (if any) in `data/scripts/lib/`

### Testing
Use the Makefile to run tests:
```bash
make test
```
This executes `lua run_tests.lua`, which mocks the Avorion API to verify script syntax and basic execution logic.

### Release Workflow (Makefile)

Use the Makefile for all git operations:

```bash
# Run tests
make test

# Create a feature branch and PR for review
git checkout -b feature/my-feature
# ... make changes ...
make pr      # Creates PR for review

# Release a new version
make release          # Patch version (1.0.0 -> 1.0.1)
make release-minor    # Minor version (1.0.0 -> 1.1.0)
make release-major    # Major version (1.0.0 -> 2.0.0)
```

**Release Process:**
1. Rename `## [NEXT]` to `## [X.Y.Z] - YYYY-MM-DD` in `CHANGELOG.md`
2. Run `make release` (bumps version in `modinfo.lua`, runs tests, commits, pushes)
3. GitHub Actions automatically:
   - Creates a GitHub release with changelog
   - Deploys to Steam Workshop

### Changelog Practices

All changes must be documented in `CHANGELOG.md` following these rules:

1. **New changes go in `## [NEXT]`** - Never modify released version entries
2. **Before release**, manually rename `[NEXT]` to the new version with date
3. **Format**: Use `### Added`, `### Changed`, `### Fixed`, `### Removed` subsections
4. **Keep entries concise** - One line per change, use sub-bullets for details

Example:
```markdown
## [NEXT]

### Changed
- Changed target highlight keybind from **G** to **V** (conflicts with torpedoes)

## [1.7.1] - 2026-01-11
...
```

## Steam Workshop Deployment

The repository uses GitHub Actions for automated Steam Workshop deployment.

### Required Secrets
- `STEAM_USERNAME` - Steam account **login name**
- `STEAM_PASSWORD` - Steam account password
- `STEAM_TOTP_SECRET` - Shared secret for TOTP (if Steam Guard enabled)

### Troubleshooting
- **Local Testing**: Always run `make test` before pushing.
- **Steam Auth**: Deployment failures are often due to Steam Guard. Check the GitHub Actions logs.

## Critical Modding Guidelines

### Modifying Library Files (Include Injection)

**Key Concept**: Avorion's `include()` loads vanilla files first, then **appends** mod files in load order as if they were a single combined file. This allows minimal overrides.

**NEVER copy entire vanilla files** - they will break on game updates. Instead:

1.  **Create a minimal extension file** at the same path in your mod (e.g., `data/scripts/lib/galaxy.lua`)
2.  Your code is appended after vanilla code runs, so you can capture and override functions

#### Pattern: Override Global Functions
```lua
-- Store original function (already defined by vanilla)
local originalFunction = SomeGlobalFunction

-- Override with your modification
function SomeGlobalFunction(x, y)
    local result = originalFunction(x, y)
    return result + 1  -- Your modification
end

-- Update table exports if needed
if SomeTable then
    SomeTable.SomeFunction = SomeGlobalFunction
end
```

#### Pattern: Hook Namespace Methods
```lua
-- Capture original method
local oldInitialize = UpgradeGenerator.initialize

-- Redefine with wrapper
function UpgradeGenerator:initialize(...)
    if oldInitialize then oldInitialize(self, ...) end
    -- Your custom logic here
end
```

#### Key Rules
- **Use `include()`** not `require()` - ensures mods load correctly
- **Local Access**: Your code runs in same chunk, can access vanilla `local` variables
- **Minimal files**: Only include the functions you're overriding

Ref: https://avorion.fandom.com/wiki/Writing_your_own_Mod#Using_include()