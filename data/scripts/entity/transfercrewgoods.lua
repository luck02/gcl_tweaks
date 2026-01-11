-- GCL Tweaks: Override Transfer Crew/Goods Cargo Tab
-- Uses include() injection to replace vanilla cargo tab with enhanced version

-- Save original createCargoTab
local original_createCargoTab = TransferCrewGoods.createCargoTab

-- Override createCargoTab to use our enhanced cargo tab
function TransferCrewGoods.createCargoTab(tabbedWindow)
    include("entity/gcl_cargo_tab")
    GclCargoTab.build(tabbedWindow)
end

-- Hook refreshCargoUI to use our implementation when available
local original_refreshCargoUI = TransferCrewGoods.refreshCargoUI

function TransferCrewGoods.refreshCargoUI(playerShip, ship)
    -- Use our enhanced cargo tab if available
    if GclCargoTab and GclCargoTab.refreshCargoUI then
        GclCargoTab.refreshCargoUI(playerShip, ship)
    else
        original_refreshCargoUI(playerShip, ship)
    end
end
