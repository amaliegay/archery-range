local controller = {}

local logging = require("logging.logger")
local config = require("JosephMcKean.archeryRange.config")

local log = logging.new({ name = "Archery Range", logLevel = config.logLevel })

local target = { ["jsmk_ar_target"] = { [16] = 3, [32] = 2, [64] = 1 } }
local isBow = { [tes3.weaponType.marksmanBow] = true, [tes3.weaponType.marksmanCrossbow] = true }
local arrowPrac = "jsmk_ar_arrow_prac"
local isPracArrow = { [arrowPrac] = true }
local barrelArrows = "jsmk_ar_barrel_arrows"

---@class archeryRange.testLineOfSight.params
---@field reference1 tes3reference
---@field reference2 tes3reference

--- Test if reference 1 has reference 2 in sight
---@param e archeryRange.testLineOfSight.params
---@return boolean
local function testInSight(e)
	local facing1 = e.reference1.facing
	local facing1Vec = tes3vector3.new(math.sin(facing1), math.cos(facing1), 0)
	local position1 = e.reference1.position
	local position2 = e.reference2.position
	local vector12 = position2 - position1
	local angle = facing1Vec:angle(vector12) * (180 / math.pi)
	return angle <= 110
end

---@param reference tes3reference
---@param index integer
---@return table?
local function updataSwitchIndex(reference, index)
	local switchNode = reference.sceneNode:getObjectByName("ArrowSwitch")
	if not switchNode then return { block = true } end
	if switchNode.switchIndex == index then return { block = true } end
	switchNode.switchIndex = index
	reference.modified = true
end

local function equipBow()
	local readiedWeapon = tes3.mobilePlayer.readiedWeapon
	-- if player has a bow equipped, returns
	if readiedWeapon and isBow[readiedWeapon.object.type] then return end
	-- the player doesn't have a bow equipped, find any bow in the inventory
	local bow
	for _, itemStack in pairs(tes3.mobilePlayer.inventory) do
		if isBow[itemStack.object.type] then
			bow = itemStack.object
			break
		end
	end
	if bow then tes3.mobilePlayer:equip({ item = bow, selectWorstCondition = true }) end
end

---@param e mwseTimerCallbackData
local function arrowSpawnTimerCallback(e)
	local barrelRef = e.timer.data.barrelRef
	-- if the player can see the barrel
	if testInSight({ reference1 = tes3.player, reference2 = barrelRef }) then
		-- start another timer
		timer.start({ duration = 1, callback = arrowSpawnTimerCallback, persist = false, data = { barrelRef = barrelRef } })
	else
		-- Set switch node to default (0)
		updataSwitchIndex(barrelRef, 0)
	end
end

---@param e activateEventData
function controller.activate(e)
	-- We only care about the player
	if e.activator ~= tes3.player then return end
	-- We only care about the barrel of arrows
	if e.target.baseObject.id ~= barrelArrows then return end
	-- We only care about when it is not in menu mode
	if tes3ui.menuMode() then return end

	local barrelRef = e.target

	-- Set switch node to activated (1)
	local swithResult = updataSwitchIndex(e.target, 1)
	if swithResult and swithResult.block then return end
	tes3.addItem({ reference = tes3.player, item = arrowPrac, count = 14, playSound = true, showMessage = true })
	equipBow()
	tes3.mobilePlayer:equip({ item = arrowPrac })

	-- start arrow respawn timer
	timer.start({ duration = 1, callback = arrowSpawnTimerCallback, persist = false, data = { barrelRef = barrelRef } })
end

---@param e projectileHitObjectEventData
function controller.projectileHitObject(e)
	---@param id string
	---@param hitDistance number
	local function getPoint(id, hitDistance)
		local targetData = target[id]
		for radius, point in pairs(targetData) do if hitDistance <= radius then return point end end
		return 0
	end

	-- We only care about the player
	if e.firingReference ~= tes3.player then return end
	-- We only care about bows and crossbows 
	if not isBow[e.firingWeapon.type] then return end
	-- We only care about archery targets
	if not target[e.target.baseObject.id] then return end
	-- We only care about practice arrows
	if not isPracArrow[e.mobile.reference.baseObject.id] then return end

	-- Calculate where did the arrow hit
	local hitPoint = e.collisionPoint
	local centerPoint = e.target.position
	local hitDistance = centerPoint:distance(hitPoint)
	local point = getPoint(e.target.baseObject.id, hitDistance)

	tes3.messageBox("You scored %s point!", point)
end

---@param e referenceSceneNodeCreatedEventData
function controller.referenceSceneNodeCreated(e)
	-- We only care about the barrel of arrows
	if e.reference.baseObject.id ~= barrelArrows then return end
	-- Set switch node to default (0)
	updataSwitchIndex(e.reference, 0)
end

return controller
