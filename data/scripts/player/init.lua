-- GCL Tweaks Player Script Initialization
-- This script runs when a player logs in and adds the console UI script to them
-- NOTE: This runs SERVER-SIDE only, not client-side

package.path = package.path .. ";data/scripts/lib/?.lua"

if onServer() then
    local player = Player()
    player:addScriptOnce("gcl_console.lua")
end
