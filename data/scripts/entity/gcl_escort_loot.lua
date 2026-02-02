-- GCL Escort Loot Collector
-- Entity script that deploys fighters to collect loot when escorting and not in combat.
--
-- Usage: ship:addScriptOnce("data/scripts/entity/gcl_escort_loot.lua")
--
-- Behavior:
--   - When escorting and NOT in combat: deploys fighters with CollectLoot orders
--   - When combat starts: recalls fighters to Defend
--   - Requires fighters in hangar to function

package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")

-- namespace GclEscortLoot
GclEscortLoot = {}

-- Configuration
local CHECK_INTERVAL = 3.0  -- seconds between state checks
local COMBAT_COOLDOWN = 5.0 -- seconds after combat before resuming loot collection

-- State tracking
local timeSinceCheck = 0
local currentMode = "idle"  -- "idle", "collecting", "defending"
local lastCombatTime = 0
local initialized = false

-- Pirate sayings for loot collection (use %s for ship name, %s for captain's ship name)
local LOOT_SAYINGS = {
    "Arr captain, we're collecting the booty!",
    "Cap'n %s says: Shiny things floatin' about! Dibs!",
    "The crew of %s be scoopin' up treasure fer the mighty %s!",
    "%s reporting: Found some lovely flotsam! Finders keepers, captain!",
    "Oi! %s here, pickin' up scraps while %s does the real work!",
    "By Davy Jones' locker, %s be hooverin' up loot like a space-kraken!",
    "Arrrr I love eating Sad Pandas Booty!!"
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

function GclEscortLoot.initialize()
    if onClient() then return end
    initialized = true
end

function GclEscortLoot.updateServer(timeStep)
    if not initialized then return end

    timeSinceCheck = timeSinceCheck + timeStep
    if timeSinceCheck < CHECK_INTERVAL then return end
    timeSinceCheck = 0

    local entity = Entity()
    if not entity or not valid(entity) then return end

    -- Must have a hangar with fighters
    local hangar = Hangar(entity.id)
    if not hangar or hangar.numFighters == 0 then return end

    -- Must have ShipAI
    local ai = ShipAI(entity.id)
    if not ai then return end

    -- Check if we're in escort or follow mode
    -- AIState.Escort = 2, AIState.Follow = 10
    local isEscortingOrFollowing = (ai.state == 2) or (ai.state == 10)
        or (ai:getEscortTarget() ~= nil) or (ai:getFollowTarget() ~= nil)

    if not isEscortingOrFollowing then
        -- Not escorting/following, stop collecting but don't recall
        -- (player might want fighters deployed for other reasons)
        if currentMode == "collecting" then
            currentMode = "idle"
        end
        return
    end

    -- Check combat state
    local inCombat = ai.isAttackingSomething or ai:isEnemyPresent(false)

    if inCombat then
        lastCombatTime = 0
        if currentMode ~= "defending" then
            GclEscortLoot.setFightersDefend(hangar)
            currentMode = "defending"
        end
    else
        -- Not in combat - check cooldown
        lastCombatTime = lastCombatTime + CHECK_INTERVAL

        if lastCombatTime >= COMBAT_COOLDOWN then
            if currentMode ~= "collecting" then
                GclEscortLoot.deployFightersForLoot(entity, hangar)
                currentMode = "collecting"
            end
        end
    end
end

function GclEscortLoot.deployFightersForLoot(entity, hangar)
    local fc = FighterController(entity.id)
    if not fc then return end

    local squads = {hangar:getSquads()}
    local deployedAny = false

    for _, squadIndex in pairs(squads) do
        local numFighters = hangar:getSquadFighters(squadIndex)
        if numFighters > 0 then
            -- Start fighters if not already deployed
            local deployed = fc:getDeployedFighters(squadIndex)
            local deployedCount = 0
            for _ in pairs(deployed) do deployedCount = deployedCount + 1 end

            -- Deploy remaining fighters
            for i = 0, numFighters - 1 do
                local err = fc:getFighterStartError(squadIndex, i)
                if err == 0 then  -- FighterStartError.NoError
                    fc:startFighter(squadIndex, i)
                    deployedAny = true
                end
            end

            -- Set squad to CollectLoot orders
            fc:setSquadOrders(squadIndex, 8, nil)  -- FighterOrders.CollectLoot = 8
        end
    end

    if deployedAny then
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

function GclEscortLoot.setFightersDefend(hangar)
    local entity = Entity()
    local fc = FighterController(entity.id)
    if not fc then return end

    local squads = {hangar:getSquads()}

    for _, squadIndex in pairs(squads) do
        -- Set squad to Defend orders
        fc:setSquadOrders(squadIndex, 1, nil)  -- FighterOrders.Defend = 1
    end

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

function GclEscortLoot.recallFighters(hangar)
    -- Recall all fighters when no longer escorting
    hangar:collectAllFighters()

    -- local entity = Entity()
    -- local entityName = entity.name or "Ship"
    -- print(string.format("[GCL Escort Loot] %s: No longer escorting, recalling fighters", entityName))
end

-- Allow external query of current mode
function GclEscortLoot.getMode()
    return currentMode
end

-- Allow external control to force a mode change
function GclEscortLoot.setEnabled(enabled)
    if not enabled and currentMode == "collecting" then
        local entity = Entity()
        local hangar = Hangar(entity.id)
        if hangar then
            GclEscortLoot.recallFighters(hangar)
        end
        currentMode = "idle"
    end
end
