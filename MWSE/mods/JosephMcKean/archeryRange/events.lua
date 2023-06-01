-- This is where we define all our events.
local controller = require("JosephMcKean.archeryRange.controller")

event.register(tes3.event.activate, controller.activate)
event.register(tes3.event.loaded, controller.loaded)
event.register(tes3.event.projectileHitObject, controller.projectileHitObject)
event.register(tes3.event.referenceSceneNodeCreated, controller.referenceSceneNodeCreated)
