-- Basic test runner for gcl_tweaks

-- Mock Avorion API
function Player()
    return {
        sendChatMessage = function() end,
        hasScript = function() return false end,
        invokeFunction = function()
            return
                0, ""
        end
    }
end

function Entity() return {} end

function Sector() return {} end

function Server() return { setValue = function() end, getValue = function() end } end

-- Mock include() - returns empty table for any lib
function include(path)
    return {}
end

InventoryItem = {}
ChatMessageType = { Information = 1, Error = 2 }
MalusReason = { None = 0, Boarding = 1, Reconstruction = 2 }
function valid(obj) return obj ~= nil end

-- Helper to print status
local function pass(msg) print("✅ " .. msg) end
local function fail(msg)
    print("❌ " .. msg)
    os.exit(1)
end
local function transformError(err) return err or "unknown error" end

-- Load the script
print("Testing load of data/scripts/commands/gcl_tweak.lua...")
local env = {
    package = package,
    require = require,
    print = print,
    table = table,
    string = string,
    tonumber = tonumber,
    pairs = pairs,
    ipairs = ipairs,
    Player = Player,
    Entity = Entity,
    Sector = Sector,
    Server = Server,
    ChatMessageType = ChatMessageType,
    MalusReason = MalusReason,
    valid = valid,
    include = include
}

-- Load file into environment (Lua 5.4 style)
local chunk, err = loadfile("data/scripts/commands/gcl_tweak.lua", "t", env)
if not chunk then
    fail("Syntax error: " .. transformError(err))
else
    -- In Lua 5.2+, the environment is set during load
    chunk()
    pass("Script loaded successfully")
end

-- Test function existence
if type(env.execute) ~= "function" then
    fail("execute function missing")
else
    pass("execute function found")
end

-- TODO: Add more specific tests if needed

print("\nAll tests passed!")
