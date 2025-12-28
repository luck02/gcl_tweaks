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
1. `make release` bumps the version in `modinfo.lua`
2. Runs tests (`make test`)
3. Commits and pushes to main
4. GitHub Actions automatically:
   - Creates a GitHub release with changelog
   - Deploys to Steam Workshop

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
When extending vanilla library files (e.g. `upgradegenerator.lua`) that end with a `return` statement:

1.  **Do NOT** perform a full file override (copy-paste) unless absolutely necessary.
2.  **Use `include()` injection**. Avorion's `include()` mechanism effectively concatenates mod files *before* the `return` statement of the vanilla file.
3.  **Local Access**: Because your code is injected into the same chunk, you can access `local` variables defined in the vanilla file (like `UpgradeGenerator`).
4.  **Hook Pattern**:
    ```lua
    -- Capture original function
    local oldInitialize = UpgradeGenerator.initialize
    -- Redefine with wrapper
    function UpgradeGenerator:initialize(...)
        if oldInitialize then oldInitialize(self, ...) end
        -- Your custom logic here
    end
    ```
5.  **Use `include()`** instead of `require()` ensures correct mod loading behavior.

Ref: https://avorion.fandom.com/wiki/Writing_your_own_Mod#Using_include()