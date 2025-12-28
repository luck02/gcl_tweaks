-- GCL Tweaks: UpgradeGenerator Hook
-- This file is automatically loaded when any script includes("upgradegenerator")
-- It wraps the UpgradeGenerator.initialize method to inject persistent drop rate multipliers

if UpgradeGenerator then
    local oldInitialize = UpgradeGenerator.initialize
    UpgradeGenerator.initialize = function(self, ...)
        if oldInitialize then
            oldInitialize(self, ...)
        end

        -- GCL Tweaks: Apply persistent multipliers from Galaxy storage
        -- Only try to load Galaxy settings if Galaxy() is available (server-side)
        if self.scripts and Galaxy then
            local galaxy = Galaxy()
            if galaxy and galaxy.getValue then
                for scriptPath, data in pairs(self.scripts) do
                    local basename = scriptPath:match("([^/]+)$")
                    if basename then
                        local key = "gcl_drop_mult_" .. basename
                        local multiplier = galaxy:getValue(key)

                        if multiplier then
                            data.weight = data.weight * multiplier
                        end
                    end
                end
            end
        end
    end
end
