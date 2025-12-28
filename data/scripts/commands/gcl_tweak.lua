-- GCL Tweaks Command Module
-- Provides utility commands for debugging and modifying game state
--
-- Usage:
--   /gcl_tweak showdroptables - Print system upgrade drop weights to chat
--   /gcl_tweak isobjectwrecked - Check if selected entity has boarding malus
--   /gcl_tweak setobjectwrecked 0|1 - Clear or set boarding malus on selected entity

package.path = package.path .. ";data/scripts/lib/?.lua"

local UpgradeGenerator = include("upgradegenerator")

-- Command entry point
function execute(sender, commandName, subcommand, ...)
    local args = { ... }

    if not subcommand then
        return showHelp()
    end

    subcommand = string.lower(subcommand)


    if subcommand == "showdroptables" then
        return showDropTables(sender)
    elseif subcommand == "setdroprate" then
        return setDropRate(sender, args[1], args[2])
    elseif subcommand == "isobjectwrecked" then
        return isObjectWrecked(sender)
    elseif subcommand == "setobjectwrecked" then
        return setObjectWrecked(sender, args[1])
    else
        return showHelp()
    end
end

function showHelp()
    local msg = "Usage: /gcl_tweak <subcommand>\n"
    msg = msg .. "  showdroptables - Print system upgrade drop weights to chat\n"
    msg = msg .. "  setdroprate <component> <multiplier> - Set drop chance multiplier\n"
    msg = msg .. "  isobjectwrecked - Check if selected entity has boarding malus\n"
    msg = msg .. "  setobjectwrecked 0|1 - Clear or set boarding malus"
    return 1, "", msg
end

-- Show drop tables command
function showDropTables(sender)
    local generator = UpgradeGenerator()
    if not generator or not generator.scripts then
        return 1, "", "Failed to instantiate UpgradeGenerator"
    end



    local dropTable = {}
    for script, data in pairs(generator.scripts) do
        table.insert(dropTable, {
            script = script:match("([^/]+)$"), -- Get just the filename
            fullPath = script,
            weight = data.weight,
            dist2 = data.dist2ToCenter
        })
    end

    -- Sort alphabetically by script name
    table.sort(dropTable, function(a, b) return a.script < b.script end)

    -- Calculate total weight for percentage
    local totalWeight = 0
    for _, entry in ipairs(dropTable) do
        totalWeight = totalWeight + entry.weight
    end

    -- Build output string and also print to server log
    local fullOutput = "=== System Upgrade Drop Weights (Dynamic) ===\n"

    for _, entry in ipairs(dropTable) do
        local pct = (entry.weight / totalWeight) * 100
        local distStr = ""
        if entry.dist2 then
            distStr = string.format(" (dist <= %d)", math.sqrt(entry.dist2))
        end
        local line = string.format("%.1f%% (%s): %s%s\n", pct, entry.weight, entry.script, distStr)
        fullOutput = fullOutput .. line
    end

    fullOutput = fullOutput .. string.format("\nTotal weight: %.2f (%d modules)", totalWeight, #dropTable)

    -- Print full output to server log for reference
    print("=== GCL TWEAKS DROP TABLES ===")
    print(fullOutput)
    print("=== END DROP TABLES ===")

    -- Send to player (full output - shows in client log)
    local player = Player(sender)
    if player then
        player:sendChatMessage("GCL Tweaks", ChatMessageType.Information, fullOutput)
    end

    return 0, "", ""
end

-- Set drop rate multiplier for a component
function setDropRate(sender, component, multiplier)
    local player = Player(sender)
    if not player then return 1, "", "Player not found" end

    if not component or not multiplier then
        return 1, "",
            "Usage: /gcl_tweak setdroprate <component> <multiplier>\nExample: /gcl_tweak setdroprate autoturret 0.1"
    end

    local multValue = tonumber(multiplier)
    if not multValue or multValue < 0 then
        return 1, "", "Multiplier must be a non-negative number."
    end

    -- Basic sanitation of component name (if user passes 'autotcs.lua' vs 'autotcs', handle both)
    -- The key format expects the basename WITH extension if that's how UpgradeGenerator stores it,
    -- but usually scripts are 'data/scripts/systems/file.lua'.
    -- Our hook uses `scriptPath:match("([^/]+)$")` which means 'file.lua'.
    -- So we should probably allow user to enable strict matching or just ensure they passed the filename.

    -- If user passed "autotcs", start by assuming .lua if missing?
    -- Vanilla files usually have .lua. Let's just trust exactly what they type but warn if it doesn't look like a filename.
    -- Better: let's enforce '.lua' if missing to be helpful?
    -- Most users will type 'civiltcs' not 'civiltcs.lua'.

    if not component:match("%.lua$") then
        component = component .. ".lua"
    end

    local key = "gcl_drop_mult_" .. component
    Server():setValue(key, multValue)

    player:sendChatMessage("GCL Tweaks", ChatMessageType.Information,
        string.format("Set drop multiplier for '%s' to %.2f (Key: %s)", component, multValue, key))
    player:sendChatMessage("GCL Tweaks", ChatMessageType.Information,
        "Run '/gcl_tweak showdroptables' to verify changes.")

    return 0, "", ""
end

-- Check if selected object has boarding malus
function isObjectWrecked(sender)
    local player = Player(sender)
    if not player then
        return 1, "", "Player not found"
    end

    local craft = player.craft
    if not craft then
        return 1, "", "You're not in a ship!"
    end

    -- Get the selected object or use current craft
    local target = craft.selectedObject or craft
    if not target or not valid(target) then
        return 1, "", "No valid target selected. Select an object or use your current ship."
    end

    local factor, reason = target:getMalusFactor()
    local name = target.name or "Unknown"

    local isWrecked = (reason == MalusReason.Boarding)
    local reasonStr = "None"

    if reason == MalusReason.None then
        reasonStr = "None"
    elseif reason == MalusReason.Reconstruction then
        reasonStr = "Reconstruction"
    elseif reason == MalusReason.Boarding then
        reasonStr = "Boarding (WRECKED)"
    elseif reason == MalusReason.RiftTeleport then
        reasonStr = "RiftTeleport"
    else
        reasonStr = "Unknown (" .. tostring(reason) .. ")"
    end

    local msg = string.format("Entity: %s\nMalus Factor: %.2f\nMalus Reason: %s\nWrecked (Boarding): %s",
        name, factor or 1.0, reasonStr, isWrecked and "YES" or "NO")

    player:sendChatMessage("GCL Tweaks", ChatMessageType.Information, msg)

    return 0, "", ""
end

-- Set or clear boarding malus on selected object
function setObjectWrecked(sender, value)
    local player = Player(sender)
    if not player then
        return 1, "", "Player not found"
    end

    local craft = player.craft
    if not craft then
        return 1, "", "You're not in a ship!"
    end

    -- Get the selected object or use current craft
    local target = craft.selectedObject or craft
    if not target or not valid(target) then
        return 1, "", "No valid target selected. Select an object or use your current ship."
    end

    if value == nil then
        return 1, "", "Usage: /gcl_tweak setobjectwrecked 0|1"
    end

    local numValue = tonumber(value)
    if numValue == nil then
        return 1, "", "Invalid value. Use 0 to clear or 1 to set wrecked state."
    end

    local name = target.name or "Unknown"

    if numValue == 0 then
        -- Clear the malus - restore to normal state
        target:setMalusFactor(1.0, MalusReason.None)
        -- Also restore durability to max
        if target.durability and target.maxDurability then
            target.durability = target.maxDurability
        end
        player:sendChatMessage("GCL Tweaks", ChatMessageType.Information,
            string.format("Cleared wrecked state on '%s'. Malus reset to 1.0, durability restored.", name))
    else
        -- Set the boarding malus (typical boarding malus is 0.5)
        target:setMalusFactor(0.5, MalusReason.Boarding)
        player:sendChatMessage("GCL Tweaks", ChatMessageType.Information,
            string.format("Set wrecked state on '%s'. Malus set to 0.5 with Boarding reason.", name))
    end

    return 0, "", ""
end

function getDescription()
    return "GCL Tweaks - Utility commands for debugging and game state modification"
end

function getHelp()
    return [[Usage: /gcl_tweak <subcommand>

Subcommands:
  showdroptables    - Print system upgrade drop weights to chat
  setdroprate       - Set drop chance multiplier for a specific component
  isobjectwrecked   - Check if selected entity has boarding malus (wrecked)
  setobjectwrecked  - Set/Clear boarding malus

Examples:
  /gcl_tweak setdroprate civiltcs 0.1
  /gcl_tweak showdroptables
  /gcl_tweak isobjectwrecked
  /gcl_tweak setobjectwrecked 1
]]
end

function getPermissions()
    -- Return empty table to allow any player to use these commands
    -- If this function didn't exist, commands would be admin-only by default
    return {}
end
