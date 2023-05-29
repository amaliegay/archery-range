-- Archery Range by JosephMcKean
local mod = "Archery Range"
local plugin = "Archery Range.esp"

-- Initializing our mod
event.register(tes3.event.initialized, function()
	if not tes3.isModActive(plugin) then return end
	require("JosephMcKean.archeryRange.events")
	mwse.log("[Archery Range: INFO] Initialized!")
end)