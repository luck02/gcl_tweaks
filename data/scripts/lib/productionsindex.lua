-- GCL Tweaks: Modify Coal Mine to also produce Diamonds
-- This file is appended after vanilla productionsindex.lua runs

for _, production in pairs(productions) do
    -- Find the Coal Mine entry (produces Coal, uses ${good} Mine template)
    if production.results and #production.results == 1 and production.results[1].name == "Coal" then
        -- Add Diamond as a secondary output (1 per cycle)
        table.insert(production.results, {name = "Diamond", amount = 1})
        break
    end
end
