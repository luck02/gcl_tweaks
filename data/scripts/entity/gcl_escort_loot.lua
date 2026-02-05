-- GCL Escort Loot Collector
-- Entity script that auto-collects loot when escorting.
--
-- Usage: ship:addScriptOnce("data/scripts/entity/gcl_escort_loot.lua")
--
-- Behavior:
--   - Every 10 seconds, collects up to 10 loot items directly to ship
--   - Works during combat and peace (no need to wait for combat to end)
--   - Fighters set to defend during combat, collect loot when peaceful
--   - 5% chance of pirate flavor text on each collection
--   - Requires fighters in hangar to function

package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")

-- namespace GclEscortLoot
GclEscortLoot = {}

-- Configuration
local LOOT_COLLECT_INTERVAL = 10.0  -- seconds between loot collection runs
local LOOT_COLLECT_MAX = 10  -- max items to collect per run
local COMBAT_COOLDOWN = 5.0 -- seconds after combat before resuming free loot collection
local FLAVOR_TEXT_CHANCE = 0.05  -- 5% chance of flavor text

-- State tracking
local currentMode = "idle"  -- "idle", "collecting", "defending"
local lastCombatTime = 0
local initialized = false
local timeSinceCollect = 0 -- timer for loot collection runs

-- Pirate sayings for loot collection (use %s for ship name, %s for captain's ship name)
local LOOT_SAYINGS = {
    "Arr captain, we're collecting the booty!",
    "Cap'n %s says: Shiny things floatin' about! Dibs!",
    "The crew of %s be scoopin' up treasure fer the mighty %s!",
    "%s reporting: Found some lovely flotsam! Finders keepers, captain!",
    "Oi! %s here, pickin' up scraps while %s does the real work!",
    "By Davy Jones' locker, %s be hooverin' up loot like a space-kraken!",
    "Yaar, I hear Stuffy Panda eats bootay!!!"
}

-- Pirate sayings for combat (use %s for ship name, %s for captain's ship name)
local COMBAT_SAYINGS = {
    "Avast! Enemy sighted! Man the cannons, ye scallywags!",
    "%s to %s: We got company! Time to earn our grog!",
    "YARR! %s be switchin' from lootin' to shootin'!",
    "Cap'n of %s screams: Defend the %s or it's the plank fer all of us!",
    "%s here! Stow the loot, ready the guns! Nobody touches our captain's ship!",
    "Battle stations on %s! May Neptune have mercy, 'cause we won't!"
}

-- Get a random saying with ship names injected
local function getRandomSaying(sayings, escortName, masterName)
    local saying = sayings[math.random(#sayings)]
    -- Count %s occurrences to know how many args to pass
    local _, count = saying:gsub("%%s", "")
    if count == 0 then
        return saying
    elseif count == 1 then
        return string.format(saying, escortName)
    else
        return string.format(saying, escortName, masterName)
    end
end

function GclEscortLoot.getUpdateInterval()
    return 1.0
end

-- Collect up to maxItems loot from sector, return count collected
function GclEscortLoot.collectLoot(entity, sector, maxItems)
    local loots = {sector:getEntitiesByType(EntityType.Loot)}
    local collected = 0

    local cargoBay = CargoBay(entity)
    local faction = Faction(entity.factionIndex)
    local inventory = nil

    print(string.format("[GCL Debug] collectLoot called: entity=%s, maxItems=%d, lootCount=%d",
        entity.name or "?", maxItems, #loots))
    print(string.format("[GCL Debug] cargoBay=%s, faction=%s",
        tostring(cargoBay ~= nil), tostring(faction ~= nil)))

    -- Get inventory for items (turrets, upgrades)
    if faction and faction.isPlayer then
        local player = Player(entity.factionIndex)
        if player then inventory = player:getInventory() end
        print("[GCL Debug] Got player inventory")
    elseif faction and faction.isAlliance then
        local alliance = Alliance(entity.factionIndex)
        if alliance then inventory = alliance:getInventory() end
        print("[GCL Debug] Got alliance inventory")
    end

    for idx, loot in pairs(loots) do
        if collected >= maxItems then
            print(string.format("[GCL Debug] Hit maxItems limit (%d), stopping", maxItems))
            break
        end
        if not valid(loot) then
            print(string.format("[GCL Debug] Loot #%d invalid, skipping", idx))
            goto continue
        end

        -- Check components
        local hasCargo = loot:hasComponent(ComponentType.CargoLoot)
        local hasMoney = loot:hasComponent(ComponentType.MoneyLoot)
        local hasResource = loot:hasComponent(ComponentType.ResourceLoot)
        local hasTurret = loot:hasComponent(ComponentType.TurretLoot)
        local hasUpgrade = loot:hasComponent(ComponentType.SystemUpgradeLoot)
        local isCollectable = loot:isCollectable(entity)

        print(string.format("[GCL Debug] Loot #%d: cargo=%s, money=%s, resource=%s, turret=%s, upgrade=%s, collectable=%s",
            idx, tostring(hasCargo), tostring(hasMoney), tostring(hasResource),
            tostring(hasTurret), tostring(hasUpgrade), tostring(isCollectable)))

        if not isCollectable then
            print(string.format("[GCL Debug] Loot #%d not collectable, skipping", idx))
            goto continue
        end

        local success = false

        -- Handle based on loot component type
        if hasCargo and cargoBay then
            local numCargos = loot.numCargos or 0
            print(string.format("[GCL Debug] CargoLoot: numCargos=%d", numCargos))
            for i = 0, numCargos - 1 do
                local good, amount = loot:getCargo(i)
                print(string.format("[GCL Debug] getCargo(%d): good=%s, amount=%s",
                    i, tostring(good), tostring(amount)))
                if good then
                    local added = cargoBay:add(good, amount)
                    print(string.format("[GCL Debug] cargoBay:add returned %s", tostring(added)))
                    success = true
                end
            end
        elseif hasMoney and faction then
            local money = loot:getMoneyLootAmount() or 0
            print(string.format("[GCL Debug] MoneyLoot: amount=%d", money))
            if money > 0 then
                faction:receive(money)
                print("[GCL Debug] faction:receive(money) called")
                success = true
            end
        elseif hasResource and faction then
            local material, amount = loot:getResourceLootAmount()
            print(string.format("[GCL Debug] ResourceLoot: material=%s, amount=%s",
                tostring(material), tostring(amount)))
            if material and amount and amount > 0 then
                faction:receive(material, amount)
                print("[GCL Debug] faction:receive(material, amount) called")
                success = true
            end
        elseif hasTurret and inventory then
            print("[GCL Debug] TurretLoot: looking for actual turret (not template)")

            -- Explore loot entity for turret-related properties
            local tryLootProps = {"turret", "inventoryTurret", "sellableTurret", "item"}
            for _, prop in ipairs(tryLootProps) do
                local pok, val = pcall(function() return loot[prop] end)
                if pok and val ~= nil then
                    print(string.format("[GCL Debug] loot.%s = %s (type=%s)", prop, tostring(val), type(val)))
                end
            end

            -- Try to get turret via different component types
            local pok1, invTurret = pcall(function() return InventoryTurret(loot.id) end)
            print(string.format("[GCL Debug] InventoryTurret(loot.id): ok=%s, result=%s", tostring(pok1), tostring(invTurret)))
            if pok1 and invTurret then
                -- Check properties on InventoryTurret
                local tryProps = {"turret", "template", "item"}
                for _, prop in ipairs(tryProps) do
                    local pok2, val = pcall(function() return invTurret[prop] end)
                    if pok2 and val ~= nil then
                        print(string.format("[GCL Debug] InventoryTurret.%s = %s (type=%s)", prop, tostring(val), type(val)))
                    end
                end
                local pok3, result = pcall(function() return inventory:add(invTurret) end)
                print(string.format("[GCL Debug] inventory:add(InventoryTurret(loot.id)): ok=%s, result=%s", tostring(pok3), tostring(result)))
                if pok3 then success = true end
            end

            -- Try SellableInventoryItem
            if not success then
                local pok4, sellable = pcall(function() return SellableInventoryItem(loot.id) end)
                print(string.format("[GCL Debug] SellableInventoryItem(loot.id): ok=%s, result=%s", tostring(pok4), tostring(sellable)))
                if pok4 and sellable then
                    local item = sellable.item
                    print(string.format("[GCL Debug] SellableInventoryItem.item = %s (type=%s)", tostring(item), type(item)))
                    if item then
                        local pok5, result = pcall(function() return inventory:add(item) end)
                        print(string.format("[GCL Debug] inventory:add(SellableInventoryItem.item): ok=%s, result=%s", tostring(pok5), tostring(result)))
                        if pok5 then success = true end
                    end
                end
            end

            -- Check if there's a Turrets component (plural)
            if not success then
                local pok6, turrets = pcall(function() return Turrets(loot.id) end)
                print(string.format("[GCL Debug] Turrets(loot.id): ok=%s, result=%s", tostring(pok6), tostring(turrets)))
            end

            if not success then
                print("[GCL Debug] TurretLoot: skipping (no known collection method)")
            end
        elseif hasUpgrade and inventory then
            print("[GCL Debug] SystemUpgradeLoot: using .upgrade property")
            local upgradeLoot = SystemUpgradeLoot(loot.id)
            if upgradeLoot then
                local u = upgradeLoot.upgrade
                print(string.format("[GCL Debug] upgradeLoot.upgrade = %s (type=%s)", tostring(u), type(u)))
                if u then
                    local pok, err = pcall(function() inventory:add(u) end)
                    print(string.format("[GCL Debug] inventory:add(upgrade): ok=%s, err=%s", tostring(pok), tostring(err)))
                    if pok then success = true end
                end
            end
        else
            print(string.format("[GCL Debug] Loot #%d: no handler matched (cargoBay=%s, inventory=%s)",
                idx, tostring(cargoBay ~= nil), tostring(inventory ~= nil)))
        end

        if success then
            print(string.format("[GCL Debug] Deleting loot #%d", idx))
            sector:deleteEntity(loot)
            collected = collected + 1
        else
            print(string.format("[GCL Debug] Loot #%d: success=false, not deleting", idx))
        end

        ::continue::
    end

    print(string.format("[GCL Debug] collectLoot finished: collected=%d", collected))
    return collected
end

function GclEscortLoot.initialize()
    if onClient() then
        print("[GCL Debug] initialize called on client, skipping")
        return
    end
    initialized = true
    timeSinceCollect = LOOT_COLLECT_INTERVAL  -- Ready to collect immediately
    local entity = Entity()
    print(string.format("[GCL Debug] === INITIALIZED for %s ===", entity.name or "unknown ship"))
    print(string.format("[GCL Debug] factionIndex=%s, entityId=%s",
        tostring(entity.factionIndex), tostring(entity.id)))
end

-- Debug timer for periodic status logging
local debugTimer = 0

function GclEscortLoot.updateServer(timeStep)
    if not initialized then return end

    local entity = Entity()
    if not entity or not valid(entity) then return end

    -- Must have ShipAI
    local ai = ShipAI(entity.id)
    if not ai then return end

    -- Get hangar (optional - only needed for fighter orders)
    local hangar = Hangar(entity.id)

    -- Check if we're in escort or follow mode
    local escortTarget = ai:getEscortTarget()
    local followTarget = ai:getFollowTarget()
    local isEscortingOrFollowing = (ai.state == 2) or (ai.state == 10)
        or (escortTarget ~= nil) or (followTarget ~= nil)

    -- Periodic debug status (every 5 seconds)
    debugTimer = debugTimer + timeStep
    if debugTimer >= 5.0 then
        debugTimer = 0
        local sector = Sector()
        local lootCount = sector and #{sector:getEntitiesByType(EntityType.Loot)} or 0
        print(string.format("[GCL Debug] === STATUS: %s ===", entity.name or "Ship"))
        print(string.format("[GCL Debug] ai.state=%d, escortTarget=%s, followTarget=%s, isEscorting=%s",
            ai.state, tostring(escortTarget), tostring(followTarget), tostring(isEscortingOrFollowing)))
        print(string.format("[GCL Debug] mode=%s, inCombat=%s, lootInSector=%d, timeSinceCollect=%.1f",
            currentMode, tostring(ai.isAttackingSomething), lootCount, timeSinceCollect))
        print(string.format("[GCL Debug] hangar=%s, lastCombatTime=%.1f",
            tostring(hangar ~= nil), lastCombatTime))
    end

    if not isEscortingOrFollowing then
        if currentMode ~= "idle" then
            print(string.format("[GCL Debug] %s: Not escorting, switching to idle", entity.name or "Ship"))
        end
        currentMode = "idle"
        return
    end

    -- Check combat state - only defend when ship is actively attacking
    -- (isEnemyPresent is too broad and causes permanent "defending" mode)
    local inCombat = ai.isAttackingSomething

    -- Update collection timer
    timeSinceCollect = timeSinceCollect + timeStep

    -- Every LOOT_COLLECT_INTERVAL seconds, collect up to LOOT_COLLECT_MAX items
    if timeSinceCollect >= LOOT_COLLECT_INTERVAL then
        timeSinceCollect = 0

        local sector = Sector()
        if sector then
            local lootCount = #{sector:getEntitiesByType(EntityType.Loot)}
            print(string.format("[GCL Debug] %s: Collection tick - %d loot in sector",
                entity.name or "Ship", lootCount))

            local collected = GclEscortLoot.collectLoot(entity, sector, LOOT_COLLECT_MAX)

            if collected > 0 then
                print(string.format("escort auto collect: %s picked up %d items",
                    entity.name or "Ship", collected))

                -- 5% chance of flavor text
                if math.random() < FLAVOR_TEXT_CHANCE then
                    local saying = getRandomSaying(LOOT_SAYINGS, entity.name or "Ship", "the fleet")
                    sector:broadcastChatMessage(entity.name or "Ship", 0, saying)
                end
            else
                print(string.format("[GCL Debug] %s: Collection tick - nothing collected", entity.name or "Ship"))
            end
        end
    end

    -- Fighter management disabled for now - focusing on programmatic collection
    -- TODO: Re-enable once programmatic collection is verified working
    --[[
    -- Manage fighter orders based on combat state
    if inCombat then
        lastCombatTime = 0
        if currentMode ~= "defending" then
            print(string.format("[GCL Debug] %s: Combat detected, switching to defending", entity.name or "Ship"))
            GclEscortLoot.setFightersDefend(hangar, true)
            currentMode = "defending"
        end
    else
        lastCombatTime = lastCombatTime + timeStep
        if lastCombatTime >= COMBAT_COOLDOWN and currentMode ~= "collecting" then
            print(string.format("[GCL Debug] %s: Combat cooldown elapsed, switching to collecting", entity.name or "Ship"))
            GclEscortLoot.deployFightersForLoot(entity, hangar)
            currentMode = "collecting"
        end
    end
    --]]

    -- For now, just track mode for status display
    if currentMode ~= "collecting" then
        currentMode = "collecting"
    end
end

function GclEscortLoot.deployFightersForLoot(entity, hangar, silent)
    print(string.format("[GCL Debug] deployFightersForLoot called for %s", entity.name or "Ship"))

    if not hangar then
        print("[GCL Debug] No hangar, cannot deploy fighters")
        return
    end

    local fc = FighterController(entity.id)
    if not fc then
        print("[GCL Debug] No FighterController, cannot deploy fighters")
        return
    end

    local squads = {hangar:getSquads()}
    local deployedAny = false

    print(string.format("[GCL Debug] Found %d squads", #squads))

    for _, squadIndex in pairs(squads) do
        local numFighters = hangar:getSquadFighters(squadIndex)
        print(string.format("[GCL Debug] Squad %d has %d fighters", squadIndex, numFighters))
        if numFighters > 0 then
            -- Deploy fighters
            for i = 0, numFighters - 1 do
                local err = fc:getFighterStartError(squadIndex, i)
                if err == 0 then  -- FighterStartError.NoError
                    fc:startFighter(squadIndex, i)
                    deployedAny = true
                    print(string.format("[GCL Debug] Started fighter %d in squad %d", i, squadIndex))
                else
                    print(string.format("[GCL Debug] Fighter %d in squad %d start error: %d", i, squadIndex, err))
                end
            end

            -- Set squad to CollectLoot orders (use Uuid() for no specific target)
            fc:setSquadOrders(squadIndex, 8, Uuid())  -- FighterOrders.CollectLoot = 8
            print(string.format("[GCL Debug] Set squad %d to CollectLoot orders", squadIndex))
        end
    end

    print(string.format("[GCL Debug] deployFightersForLoot finished, deployedAny=%s", tostring(deployedAny)))

    -- Only broadcast chat message if not silent (avoid spam during combat bursts)
    if deployedAny and not silent then
        local entityName = entity.name or "Ship"
        -- Get the master ship's name (the ship we're escorting)
        local masterName = "the flagship"
        local ai = ShipAI(entity.id)
        if ai then
            local targetId = ai:getEscortTarget() or ai:getFollowTarget()
            if targetId then
                local sector = Sector()
                if sector then
                    local masterShip = sector:getEntity(targetId)
                    if masterShip and masterShip.name then
                        masterName = masterShip.name
                    end
                end
            end
        end

        -- Notify players in sector with a random piratey message
        local sector = Sector()
        if sector then
            local saying = getRandomSaying(LOOT_SAYINGS, entityName, masterName)
            sector:broadcastChatMessage(entityName, 0, saying)
        end
    end
end

function GclEscortLoot.setFightersDefend(hangar, silent)
    local entity = Entity()
    print(string.format("[GCL Debug] setFightersDefend called for %s", entity.name or "Ship"))

    if not hangar then
        print("[GCL Debug] No hangar, cannot set defend")
        return
    end

    local fc = FighterController(entity.id)
    if not fc then
        print("[GCL Debug] No FighterController, cannot set defend")
        return
    end

    local squads = {hangar:getSquads()}
    print(string.format("[GCL Debug] Setting %d squads to Defend", #squads))

    for _, squadIndex in pairs(squads) do
        -- Set squad to Defend orders
        fc:setSquadOrders(squadIndex, 1, entity.id)  -- FighterOrders.Defend = 1
        print(string.format("[GCL Debug] Set squad %d to Defend orders", squadIndex))
    end

    -- Only broadcast if not silent (avoid spam during combat mode switches)
    if not silent then
        -- Get the master ship's name (the ship we're escorting)
        local entityName = entity.name or "Ship"
        local masterName = "the flagship"
        local ai = ShipAI(entity.id)
        if ai then
            local targetId = ai:getEscortTarget() or ai:getFollowTarget()
            if targetId then
                local sector = Sector()
                if sector then
                    local masterShip = sector:getEntity(targetId)
                    if masterShip and masterShip.name then
                        masterName = masterShip.name
                    end
                end
            end
        end

        -- Notify players in sector with a random piratey battle cry
        local sector = Sector()
        if sector then
            local saying = getRandomSaying(COMBAT_SAYINGS, entityName, masterName)
            sector:broadcastChatMessage(entityName, 0, saying)
        end
    end
end

function GclEscortLoot.recallFighters(hangar)
    local entity = Entity()
    print(string.format("[GCL Debug] recallFighters called for %s", entity.name or "Ship"))

    if not hangar then
        print("[GCL Debug] No hangar, cannot recall fighters")
        return
    end

    -- Recall all fighters when no longer escorting
    hangar:collectAllFighters()
    print("[GCL Debug] collectAllFighters called")
end

-- Allow external query of current mode
function GclEscortLoot.getMode()
    print(string.format("[GCL Debug] getMode called, returning %s", currentMode))
    return currentMode
end

-- Allow external control to force a mode change
function GclEscortLoot.setEnabled(enabled)
    local entity = Entity()
    print(string.format("[GCL Debug] setEnabled(%s) called for %s, currentMode=%s",
        tostring(enabled), entity.name or "Ship", currentMode))

    if not enabled and currentMode == "collecting" then
        local hangar = Hangar(entity.id)
        if hangar then
            GclEscortLoot.recallFighters(hangar)
        end
        currentMode = "idle"
        print("[GCL Debug] Switched to idle mode")
    end
end
