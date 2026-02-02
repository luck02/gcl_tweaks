-- GCL Tweaks: Hook factory restore to add Diamond output to existing Coal Mines
-- This file is appended after vanilla factory.lua runs

-- Store original getMaxStock function
local originalGetMaxStock = Factory.trader.getMaxStock

-- Override getMaxStock to handle Diamond for coal mines
Factory.trader.getMaxStock = function(self, good)
    local result = originalGetMaxStock(self, good)

    -- If result is 0 and this is Diamond, calculate based on Coal's ratio
    if result == 0 and good.name == "Diamond" then
        -- Check if this factory produces coal (is a coal mine)
        if production and production.results then
            for _, r in pairs(production.results) do
                if r.name == "Coal" then
                    -- Use a reasonable stock size for diamonds (smaller than coal)
                    local maxStock = Entity().maxCargoSpace * 0.1 / good.size
                    if maxStock > 100 then
                        return math.min(50000, round(maxStock / 100) * 100)
                    else
                        return math.floor(maxStock)
                    end
                end
            end
        end
    end

    return result
end

local originalRestore = Factory.restore

function Factory.restore(data)
    -- Call original restore first
    originalRestore(data)

    -- Check if this is a coal mine (produces Coal)
    if production and production.results then
        local isCoalMine = false
        local hasDiamondInResults = false

        for _, result in pairs(production.results) do
            if result.name == "Coal" then
                isCoalMine = true
            end
            if result.name == "Diamond" then
                hasDiamondInResults = true
            end
        end

        -- If it's a coal mine, ensure Diamond is set up properly
        if isCoalMine then
            -- Add Diamond to production.results if not there
            if not hasDiamondInResults then
                table.insert(production.results, {name = "Diamond", amount = 1})
            end

            -- Always check/add Diamond to soldGoods for coal mines
            local diamondGood = goods["Diamond"]:good()
            local alreadySelling = false
            for _, g in pairs(Factory.trader.soldGoods) do
                if g.name == "Diamond" then
                    alreadySelling = true
                    break
                end
            end
            if not alreadySelling then
                table.insert(Factory.trader.soldGoods, diamondGood)
                Factory.trader.numSold = #Factory.trader.soldGoods
            end

            -- Refresh supply types
            Factory.updateOwnSupply()
        end
    end
end
