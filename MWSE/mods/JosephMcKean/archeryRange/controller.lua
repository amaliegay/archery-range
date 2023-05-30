local controller = {}

local logging = require("logging.logger")
local config = require("JosephMcKean.archeryRange.config")

local log = logging.new({ name = "Archery Range", logLevel = config.logLevel })

local target = { ["jsmk_ar_target"] = { [1] = { radius = 3.49, point = 3 }, [2] = { radius = 14.76, point = 2 }, [3] = { radius = 25.98, point = 1 } } }
local isBow = { [tes3.weaponType.marksmanBow] = true }
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

---@class archeryRange.updataSwitchIndex.returns
---@field block boolean?

---@param reference tes3reference
---@param index integer
---@return archeryRange.updataSwitchIndex.returns?
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
	local bow ---@type string
	for _, itemStack in pairs(tes3.mobilePlayer.inventory) do
		if isBow[itemStack.object.type] then
			bow = itemStack.object.id
			break
		end
	end
	if bow then tes3.mobilePlayer:equip({ item = bow, selectWorstCondition = true }) end
end

---@param e mwseTimerCallbackData
local function arrowSpawnTimerCallback(e)
	local barrelRef = e.timer.data.barrelRef ---@type tes3reference
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
	local swithResult = updataSwitchIndex(barrelRef, 1)
	if swithResult and swithResult.block then return end
	tes3.addItem({ reference = tes3.player, item = arrowPrac, count = 14, playSound = true, showMessage = true })
	equipBow()
	tes3.mobilePlayer:equip({ item = arrowPrac })

	-- start arrow respawn timer
	timer.start({ duration = 1, callback = arrowSpawnTimerCallback, persist = false, data = { barrelRef = barrelRef } })

	-- Check for ownership.
	local hasOwnershipAccess = tes3.hasOwnershipAccess({ target = barrelRef })

	-- Check for crime
	if not hasOwnershipAccess then tes3.triggerCrime({ type = tes3.crimeType.theft, victim = barrelRef.itemData.owner, value = 14 }) end
end

---@param e projectileHitObjectEventData
function controller.projectileHitObject(e)
	---@param point1 tes3vector3
	---@param point2 tes3vector3
	---@return number
	local function getDistance(point1, point2) return math.sqrt(math.pow(point1.y - point2.y, 2) + math.pow(point1.z - point2.z, 2)) end
	---@param id string
	---@param hitDistance number
	local function getPoint(id, hitDistance)
		local targetData = target[id]
		for _, data in ipairs(targetData) do if hitDistance <= data.radius then return data.point end end
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

	-- Calculate where did the arrow hit on the target

	-- Target
	-- The point of the target `P_t`
	local targetPos = e.target.position
	log:trace("targetPos = %s", targetPos)
	local targetOrientation = e.target.orientation
	local unitVector = tes3vector3.new(0, 1, 0)
	local rotationMatrix = tes3matrix33.new()
	rotationMatrix:fromEulerXYZ(targetOrientation.x, targetOrientation.y, targetOrientation.z)
	-- The orthogonal of the target plane `\vec{n}`
	local targetOrthogonal = rotationMatrix * unitVector
	log:trace("targetOrthogonal = %s", targetOrthogonal)

	-- Arrow
	-- The point of the arrow `P_a`
	local arrowPos = e.collisionPoint
	log:trace("arrowPos = %s", arrowPos)
	log:trace("targetPos - arrowPos = %s", targetPos - arrowPos)
	log:trace("targetOrthogonal:dot(targetPos - arrowPos) = %s", targetOrthogonal:dot(targetPos - arrowPos))
	local arrowVelocity = e.mobile.velocity
	log:trace("arrowVelocity = %s", arrowVelocity)
	log:trace("targetOrthogonal:dot(arrowVelocity) = %s", targetOrthogonal:dot(arrowVelocity))

	-- We want to find the point of intersection of the plane of the target and the line of the arrow
	--
	-- The equation of the plane is `\vec{n} \cdot (P - P_t) = 0`, where `P` is a point on the plane
	--
	-- The equation of the line is `P = P_a + v * t`, where `P` is a point on the line and `t` is a real number
	--
	-- Solution:
	-- 
	-- If `P_0` denotes the point of the intersection, then we must have 
	-- 
	-- `\vec{n} \cdot (P_0 - P_t) = 0`
	-- 
	-- `P_0 = P_a + v * t`
	-- 
	-- Substituting the latter equation into the equation of the plan gives
	-- 
	-- `(\vec{n} \cdot v) t_0 = \vec{n} \cdot (P_t - P_a)`, for some number `t_0`
	local t0 = targetOrthogonal:dot(targetPos - arrowPos) / targetOrthogonal:dot(arrowVelocity)
	log:trace("t0 = %s", t0)
	-- From the equation for the line, we then obtain `P`
	local intersectionPos = arrowPos + arrowVelocity * t0
	log:trace("intersectionPos = %s", intersectionPos)

	local hitDistance = getDistance(intersectionPos, targetPos)
	local point = getPoint(e.target.baseObject.id, hitDistance)
	log:debug("hitDistance = %s, point = %s", hitDistance, point)

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
