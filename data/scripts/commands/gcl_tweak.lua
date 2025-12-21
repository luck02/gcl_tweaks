-- GCL Tweaks Command Module
-- Provides utility commands for debugging and modifying game state
--
-- Usage:
--   /gcl_tweak showdroptables - Print system upgrade drop weights to chat
--   /gcl_tweak isobjectwrecked - Check if selected entity has boarding malus
--   /gcl_tweak setobjectwrecked 0|1 - Clear or set boarding malus on selected entity

package.path = package.path .. ";data/scripts/lib/?.lua"

-- Command entry point
function execute(sender, commandName, subcommand, ...)
    local args = { ... }

    if not subcommand then
        return showHelp()
    end

    subcommand = string.lower(subcommand)

    if subcommand == "showdroptables" then
        return showDropTables(sender)
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
    msg = msg .. "  isobjectwrecked - Check if selected entity has boarding malus\n"
    msg = msg .. "  setobjectwrecked 0|1 - Clear or set boarding malus"
    return 1, "", msg
end

-- Show drop tables command
function showDropTables(sender)
    -- Dynamically load the UpgradeGenerator to get the actual weights used by the game/mods
    local UpgradeGenerator = include("upgradegenerator")
    if not UpgradeGenerator then
        return 1, "", "Failed to load UpgradeGenerator"
    end

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

    -- Sort by probability (descending)
    table.sort(dropTable, function(a, b) return a.weight > b.weight end)

    -- Calculate total weight for percentage
    local totalWeight = 0
    for _, entry in ipairs(dropTable) do
        totalWeight = totalWeight + entry.weight
    end

    -- Build output string
    local output = "=== System Upgrade Drop Weights (Dynamic) ===\n"

    for _, entry in ipairs(dropTable) do
        local pct = (entry.weight / totalWeight) * 100
        local distStr = ""
        if entry.dist2 then
            distStr = string.format(" (dist <= %d)", math.sqrt(entry.dist2))
        end
        output = output .. string.format("%.1f%% (%s): %s%s\n", pct, entry.weight, entry.script, distStr)
    end

    output = output .. string.format("\nTotal weight: %.2f", totalWeight)

    local player = Player(sender)
    if player then
        player:sendChatMessage("GCL Tweaks", ChatMessageType.Information, output)
    end

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
  showdroptables      - Print system upgrade drop weights to chat
  isobjectwrecked     - Check if selected entity has boarding malus (wrecked)
  setobjectwrecked 0  - Clear boarding malus, restore durability
  setobjectwrecked 1  - Set boarding malus (marks as wrecked)

Examples:
  /gcl_tweak showdroptables
  /gcl_tweak isobjectwrecked
  /gcl_tweak setobjectwrecked 0]]
end
