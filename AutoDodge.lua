local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local ENABLED = false
local SHOW_PATH = true

local PLAYER_MINI_RADIUS = 0.25
local PLAYER_RADIUS_MIN = 0.10
local PLAYER_RADIUS_MAX = 0.50
local PLAYER_RADIUS_STEP = 0.05

local PLAN_HORIZON = 1.25
local PLAN_DT = 0.10
local PLAN_STEPS = math.floor(PLAN_HORIZON / PLAN_DT + 0.5)
local EXTRA_ESCAPE_STEPS = 2
local PROJECTILE_SIM_DT = 0.025

local PLAN_INTERVAL_IDLE = 0.055
local PLAN_INTERVAL_ACTIVE = 0.035
local PLAN_INTERVAL_URGENT = 0.018

local INITIAL_DIRECTIONS = 20
local ZERO_RESTART_DIRECTIONS = 12
local ESCAPE_DIRECTIONS = 16
local BEAM_WIDTH = 46
local DENSE_BEAM_WIDTH = 34
local DENSE_THREAT_COUNT = 22

local MIN_PROJECTILE_SPEED = 2.0
local VELOCITY_SMOOTH = 0.58
local TURN_SMOOTH = 0.34
local SPEED_ACCEL_SMOOTH = 0.22
local VERTICAL_ACCEL_SMOOTH = 0.18
local PREDICTION_ERROR_SMOOTH = 0.18
local MAX_SPEED_ACCEL = 6500
local MAX_VERTICAL_ACCEL = 6500
local MAX_TURN_RATE = math.rad(1080)

local PROJECTILE_RADIUS_SCALE = 1.0
local BASE_ERROR_MARGIN = 0.035
local MAX_ERROR_MARGIN = 0.48
local PREDICTION_ERROR_WEIGHT = 0.55
local SPEED_MARGIN_WEIGHT = 0.00045
local TURN_MARGIN_WEIGHT = 0.018

local NETWORK_LEAD_FALLBACK = 0.055
local NETWORK_LEAD_MIN = 0.010
local NETWORK_LEAD_MAX = 0.180

local PLAYER_RESPONSE_TIME = 0.095
local PLAYER_ACTUATION_DELAY = 0.040

local PROACTIVE_CLEARANCE = 0.42
local DENSE_PROACTIVE_CLEARANCE = 0.90
local NEAR_ZONE = 2.60

local HIT_PENALTY = 1000000
local WALL_HIT_PENALTY = 100000000
local NEAR_RISK_WEIGHT = 18
local MOVE_COST_WEIGHT = 0.28
local TURN_COST_WEIGHT = 1.65
local SPEED_CHANGE_COST_WEIGHT = 0.20
local STOP_BONUS = 0.35
local ESCAPE_OPTION_REWARD = 20
local NO_ESCAPE_PENALTY = 2400

local BARRIER_BODY_RADIUS = 1.00
local BARRIER_NEAR_DISTANCE = 3.0
local BARRIER_NEAR_WEIGHT = 12
local BARRIER_RAY_DISTANCE = 14
local BARRIER_RAY_COUNT = 12
local BARRIER_CLOSE_RAY_DISTANCE = 4.0
local BARRIER_CLOSE_RAY_PENALTY = 9

local EnemyProj = nil
local EnemyAddedConnection = nil
local EnemyRemovedConnection = nil
local ProjectileData = {}

local BarrierSet = {}
local BarrierParts = {}

local Controls = nil
local ControlsDisabled = false

local CurrentMove = Vector3.zero
local CurrentPath = nil
local LastPlanTime = 0
local LastThreatCount = 0
local LastProjectileCount = 0
local LastMinClearance = math.huge
local LastImpactTime = math.huge
local LastEscapeOptions = 0
local LastPlanMs = 0
local LastMode = "IDLE"
local LastError = ""

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function rotateY(v, radians)
	local c = math.cos(radians)
	local s = math.sin(radians)
	return Vector3.new(
		v.X * c - v.Z * s,
		0,
		v.X * s + v.Z * c
	)
end

local function clampUnit(v)
	local f = flat(v)
	if f.Magnitude <= 0.0001 then
		return Vector3.zero
	end
	return f.Unit
end

local function signedAngleXZ(a, b)
	local aa = clampUnit(a)
	local bb = clampUnit(b)
	if aa.Magnitude < 0.01 or bb.Magnitude < 0.01 then
		return 0
	end
	local crossY = aa:Cross(bb).Y
	local dot = math.clamp(aa:Dot(bb), -1, 1)
	return math.atan2(crossY, dot)
end

local function getCharacter()
	local character = LocalPlayer.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	return character, humanoid, root
end

task.spawn(function()
	pcall(function()
		local playerScripts = LocalPlayer:WaitForChild("PlayerScripts", 10)
		if not playerScripts then
			return
		end
		local playerModule = playerScripts:WaitForChild("PlayerModule", 10)
		if not playerModule then
			return
		end
		Controls = require(playerModule):GetControls()
	end)
end)

local function disableControls()
	if Controls and not ControlsDisabled then
		pcall(function()
			Controls:Disable()
		end)
		ControlsDisabled = true
	end
end

local function enableControls()
	if Controls and ControlsDisabled then
		pcall(function()
			Controls:Enable()
		end)
		ControlsDisabled = false
	end
end

local function getNetworkLead()
	local lead = NETWORK_LEAD_FALLBACK
	pcall(function()
		local ping = LocalPlayer:GetNetworkPing()
		if type(ping) == "number" and ping > 0 then
			lead = ping
		end
	end)
	return math.clamp(lead, NETWORK_LEAD_MIN, NETWORK_LEAD_MAX)
end

local function getProjectilePart(obj)
	if obj:IsA("BasePart") then
		return obj
	end
	if obj:IsA("Model") and obj.PrimaryPart then
		return obj.PrimaryPart
	end
	return obj:FindFirstChildWhichIsA("BasePart", true)
end

local function getProjectileCenterOffset(obj, part)
	if obj:IsA("Model") then
		local ok, cf = pcall(function()
			local boxCf = obj:GetBoundingBox()
			return boxCf
		end)
		if ok and cf then
			return part.CFrame:PointToObjectSpace(cf.Position)
		end
	end
	return Vector3.zero
end

local function getProjectileCenter(data)
	if not data.Part or not data.Part.Parent then
		return data.LastPosition
	end
	return data.Part.CFrame:PointToWorldSpace(data.CenterOffset)
end

local function getProjectileRadius(obj, part)
	local radius = math.max(part.Size.X, part.Size.Y, part.Size.Z) * 0.5
	if obj:IsA("Model") then
		local ok, _, size = pcall(function()
			return obj:GetBoundingBox()
		end)
		if ok and size then
			radius = math.max(
				radius,
				math.max(size.X, size.Y, size.Z) * 0.5
			)
		end
	end
	return radius * PROJECTILE_RADIUS_SCALE
end

local function addProjectile(obj)
	task.defer(function()
		local part = getProjectilePart(obj)
		if not part then
			task.wait(0.02)
			part = getProjectilePart(obj)
		end
		if not part or not obj.Parent then
			return
		end

		local centerOffset = getProjectileCenterOffset(obj, part)
		local center = part.CFrame:PointToWorldSpace(centerOffset)
		local initialVelocity = part.AssemblyLinearVelocity
		local initialFlat = flat(initialVelocity)

		ProjectileData[obj] = {
			Object = obj,
			Part = part,
			CenterOffset = centerOffset,
			Radius = getProjectileRadius(obj, part),
			LastPosition = center,
			PreviousPosition = center,
			Velocity = initialVelocity,
			RawVelocity = initialVelocity,
			LastRawVelocity = initialVelocity,
			SpeedAccel = 0,
			VerticalAccel = 0,
			TurnRate = 0,
			PredictionError = 0,
			PredictedNext = nil,
			Samples = 0,
			Ready = initialFlat.Magnitude >= MIN_PROJECTILE_SPEED
		}
	end)
end

local function removeProjectile(obj)
	ProjectileData[obj] = nil
end

local function clearProjectileConnections()
	if EnemyAddedConnection then
		EnemyAddedConnection:Disconnect()
		EnemyAddedConnection = nil
	end
	if EnemyRemovedConnection then
		EnemyRemovedConnection:Disconnect()
		EnemyRemovedConnection = nil
	end
end

local function findEnemyProj()
	local core = workspace:FindFirstChild("Core__Game")
	if not core then
		return nil
	end
	return core:FindFirstChild("EnemyProj")
end

local function bindEnemyProj(folder)
	if EnemyProj == folder then
		return
	end

	clearProjectileConnections()
	table.clear(ProjectileData)
	EnemyProj = folder

	if not EnemyProj then
		return
	end

	for _, obj in ipairs(EnemyProj:GetChildren()) do
		addProjectile(obj)
	end

	EnemyAddedConnection = EnemyProj.ChildAdded:Connect(addProjectile)
	EnemyRemovedConnection = EnemyProj.ChildRemoved:Connect(removeProjectile)
end

local function isActualBarrier(obj)
	return obj:IsA("BasePart") and string.lower(obj.Name) == "barrier"
end

local function rebuildBarrierParts()
	local list = {}
	for part in pairs(BarrierSet) do
		if part and part.Parent then
			list[#list + 1] = part
		end
	end
	BarrierParts = list
end

local function scanBarriers()
	table.clear(BarrierSet)
	for _, obj in ipairs(workspace:GetDescendants()) do
		if isActualBarrier(obj) then
			BarrierSet[obj] = true
		end
	end
	rebuildBarrierParts()
end

scanBarriers()

workspace.DescendantAdded:Connect(function(obj)
	if isActualBarrier(obj) then
		BarrierSet[obj] = true
		rebuildBarrierParts()
	end
end)

workspace.DescendantRemoving:Connect(function(obj)
	if BarrierSet[obj] then
		BarrierSet[obj] = nil
		rebuildBarrierParts()
	end
end)

local function segmentMinDistance(relativeA, relativeB)
	local d = relativeB - relativeA
	local denom = d:Dot(d)
	if denom <= 1e-8 then
		return relativeA.Magnitude
	end
	local t = math.clamp(-relativeA:Dot(d) / denom, 0, 1)
	return (relativeA + d * t).Magnitude
end

local function pointBarrierDistance2D(part, worldPoint)
	local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
	local hx = part.Size.X * 0.5
	local hz = part.Size.Z * 0.5
	local dx = math.max(math.abs(localPoint.X) - hx, 0)
	local dz = math.max(math.abs(localPoint.Z) - hz, 0)
	return math.sqrt(dx * dx + dz * dz)
end

local function segmentIntersectsExpandedBarrier(part, worldA, worldB, expansion)
	local a = part.CFrame:PointToObjectSpace(worldA)
	local b = part.CFrame:PointToObjectSpace(worldB)
	local dx = b.X - a.X
	local dz = b.Z - a.Z
	local hx = part.Size.X * 0.5 + expansion
	local hz = part.Size.Z * 0.5 + expansion
	local tMin = 0
	local tMax = 1

	local function axis(origin, delta, half)
		if math.abs(delta) < 1e-8 then
			return math.abs(origin) <= half
		end
		local t1 = (-half - origin) / delta
		local t2 = (half - origin) / delta
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		tMin = math.max(tMin, t1)
		tMax = math.min(tMax, t2)
		return tMin <= tMax
	end

	if not axis(a.X, dx, hx) then
		return false
	end
	if not axis(a.Z, dz, hz) then
		return false
	end
	return tMax >= 0 and tMin <= 1
end

local function pathHitsBarrier(a, b)
	for _, barrier in ipairs(BarrierParts) do
		if barrier and barrier.Parent then
			if segmentIntersectsExpandedBarrier(
				barrier,
				a,
				b,
				BARRIER_BODY_RADIUS
			) then
				return true
			end
		end
	end
	return false
end

local function nearestBarrierDistance(position)
	local best = math.huge
	for _, barrier in ipairs(BarrierParts) do
		if barrier and barrier.Parent then
			local d = pointBarrierDistance2D(barrier, position)
			if d < best then
				best = d
			end
		end
	end
	return best
end

local function rayBarrierDistance2D(part, origin, direction, maxDistance)
	local localOrigin = part.CFrame:PointToObjectSpace(origin)
	local localDirection = part.CFrame:VectorToObjectSpace(direction)
	local hx = part.Size.X * 0.5 + BARRIER_BODY_RADIUS
	local hz = part.Size.Z * 0.5 + BARRIER_BODY_RADIUS
	local tMin = 0
	local tMax = maxDistance

	local function axis(o, d, half)
		if math.abs(d) < 1e-8 then
			return math.abs(o) <= half
		end
		local t1 = (-half - o) / d
		local t2 = (half - o) / d
		if t1 > t2 then
			t1, t2 = t2, t1
		end
		tMin = math.max(tMin, t1)
		tMax = math.min(tMax, t2)
		return tMin <= tMax
	end

	if not axis(localOrigin.X, localDirection.X, hx) then
		return nil
	end
	if not axis(localOrigin.Z, localDirection.Z, hz) then
		return nil
	end
	if tMax < 0 or tMin > maxDistance then
		return nil
	end
	return math.max(0, tMin)
end

local function barrierOpenness(position)
	if #BarrierParts == 0 then
		return BARRIER_RAY_DISTANCE, BARRIER_RAY_DISTANCE, 0
	end

	local total = 0
	local minimum = BARRIER_RAY_DISTANCE
	local closeRays = 0

	for i = 0, BARRIER_RAY_COUNT - 1 do
		local angle = i * math.pi * 2 / BARRIER_RAY_COUNT
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local nearest = BARRIER_RAY_DISTANCE

		for _, barrier in ipairs(BarrierParts) do
			if barrier and barrier.Parent then
				local d = rayBarrierDistance2D(
					barrier,
					position,
					direction,
					BARRIER_RAY_DISTANCE
				)
				if d and d < nearest then
					nearest = d
				end
			end
		end

		total += nearest
		minimum = math.min(minimum, nearest)
		if nearest <= BARRIER_CLOSE_RAY_DISTANCE then
			closeRays += 1
		end
	end

	return total / BARRIER_RAY_COUNT, minimum, closeRays
end

local function predictTrackerNext(data, dt)
	local flatVelocity = flat(data.Velocity)
	local speed = flatVelocity.Magnitude
	local direction = speed > 0.01 and flatVelocity.Unit or Vector3.zero
	if direction.Magnitude > 0.01 and math.abs(data.TurnRate) > 0.001 then
		direction = rotateY(direction, data.TurnRate * dt)
	end
	speed = math.max(0, speed + data.SpeedAccel * dt)
	local vy = data.Velocity.Y + data.VerticalAccel * dt
	local predictedVelocity = direction * speed + Vector3.new(0, vy, 0)
	return data.LastPosition + predictedVelocity * dt
end

RunService.Heartbeat:Connect(function(dt)
	if not EnemyProj or not EnemyProj.Parent then
		local folder = findEnemyProj()
		if folder ~= EnemyProj then
			bindEnemyProj(folder)
		end
	end

	if dt <= 0 or dt > 0.25 then
		return
	end

	local count = 0

	for obj, data in pairs(ProjectileData) do
		if not obj.Parent then
			ProjectileData[obj] = nil
			continue
		end

		local part = data.Part
		if not part or not part.Parent then
			part = getProjectilePart(obj)
			if not part then
				ProjectileData[obj] = nil
				continue
			end
			data.Part = part
			data.CenterOffset = getProjectileCenterOffset(obj, part)
			data.Radius = getProjectileRadius(obj, part)
			data.LastPosition = part.CFrame:PointToWorldSpace(data.CenterOffset)
			data.PreviousPosition = data.LastPosition
			data.Samples = 0
			data.Ready = false
			continue
		end

		count += 1

		local position = getProjectileCenter(data)

		if data.PredictedNext then
			local error = (position - data.PredictedNext).Magnitude
			data.PredictionError +=
				(error - data.PredictionError) * PREDICTION_ERROR_SMOOTH
		end

		local rawVelocity = (position - data.LastPosition) / dt
		local oldRaw = data.RawVelocity
		local oldFlat = flat(oldRaw)
		local newFlat = flat(rawVelocity)
		local oldSpeed = oldFlat.Magnitude
		local newSpeed = newFlat.Magnitude

		if oldSpeed >= MIN_PROJECTILE_SPEED and newSpeed >= MIN_PROJECTILE_SPEED then
			local rawTurn = signedAngleXZ(oldFlat, newFlat) / dt
			rawTurn = math.clamp(rawTurn, -MAX_TURN_RATE, MAX_TURN_RATE)
			data.TurnRate +=
				(rawTurn - data.TurnRate) * TURN_SMOOTH

			local rawSpeedAccel = (newSpeed - oldSpeed) / dt
			rawSpeedAccel = math.clamp(
				rawSpeedAccel,
				-MAX_SPEED_ACCEL,
				MAX_SPEED_ACCEL
			)
			data.SpeedAccel +=
				(rawSpeedAccel - data.SpeedAccel) * SPEED_ACCEL_SMOOTH
		end

		local rawVerticalAccel = (rawVelocity.Y - oldRaw.Y) / dt
		rawVerticalAccel = math.clamp(
			rawVerticalAccel,
			-MAX_VERTICAL_ACCEL,
			MAX_VERTICAL_ACCEL
		)
		data.VerticalAccel +=
			(rawVerticalAccel - data.VerticalAccel) * VERTICAL_ACCEL_SMOOTH

		if data.Samples == 0 then
			data.Velocity = rawVelocity
		else
			data.Velocity =
				data.Velocity:Lerp(rawVelocity, VELOCITY_SMOOTH)
		end

		data.PreviousPosition = data.LastPosition
		data.LastPosition = position
		data.LastRawVelocity = data.RawVelocity
		data.RawVelocity = rawVelocity
		data.Samples += 1
		data.Ready =
			data.Samples >= 2
			and flat(data.Velocity).Magnitude >= MIN_PROJECTILE_SPEED

		data.PredictedNext = predictTrackerNext(data, dt)
	end

	LastProjectileCount = count
end)

task.spawn(function()
	while true do
		local folder = findEnemyProj()
		if folder ~= EnemyProj then
			bindEnemyProj(folder)
		end
		task.wait(0.35)
	end
end)

local function simulateProjectilePositions(data, networkLead)
	local totalSteps = PLAN_STEPS + EXTRA_ESCAPE_STEPS
	local positions = table.create(totalSteps + 1)

	local position = getProjectileCenter(data)
	local flatVelocity = flat(data.Velocity)
	local speed = flatVelocity.Magnitude
	local direction =
		speed > 0.01
		and flatVelocity.Unit
		or Vector3.new(0, 0, -1)

	local vy = data.Velocity.Y
	local speedAccel = data.SpeedAccel
	local verticalAccel = data.VerticalAccel
	local turnRate = data.TurnRate
	local currentTime = 0

	local function advanceTo(targetTime)
		while currentTime + 1e-6 < targetTime do
			local step = math.min(
				PROJECTILE_SIM_DT,
				targetTime - currentTime
			)

			if math.abs(turnRate) > 0.001 then
				direction = rotateY(direction, turnRate * step)
				if direction.Magnitude > 0.01 then
					direction = direction.Unit
				end
			end

			speed = math.max(0, speed + speedAccel * step)
			vy += verticalAccel * step

			local velocity =
				direction * speed
				+ Vector3.new(0, vy, 0)

			position += velocity * step
			currentTime += step
		end
	end

	for i = 0, totalSteps do
		local targetTime = networkLead + i * PLAN_DT
		advanceTo(targetTime)
		positions[i + 1] = position
	end

	return positions
end

local function buildThreatSnapshot(root, humanoid)
	local threats = {}
	local networkLead = getNetworkLead()
	local maxReach =
		humanoid.WalkSpeed * PLAN_HORIZON
		+ flat(root.AssemblyLinearVelocity).Magnitude * 0.15

	for _, data in pairs(ProjectileData) do
		if data.Ready
			and data.Part
			and data.Part.Parent
			and flat(data.Velocity).Magnitude >= MIN_PROJECTILE_SPEED
		then
			local positions =
				simulateProjectilePositions(data, networkLead)

			local radius = data.Radius or 0
			local speed = flat(data.Velocity).Magnitude

			local errorMargin = math.clamp(
				BASE_ERROR_MARGIN
					+ (data.PredictionError or 0)
						* PREDICTION_ERROR_WEIGHT
					+ speed * SPEED_MARGIN_WEIGHT
					+ math.abs(data.TurnRate or 0)
						* TURN_MARGIN_WEIGHT,
				BASE_ERROR_MARGIN,
				MAX_ERROR_MARGIN
			)

			local dangerRadius =
				radius
				+ PLAYER_MINI_RADIUS
				+ errorMargin

			local stationaryMin = math.huge
			local previousRelative = nil

			for i = 1, PLAN_STEPS + 1 do
				local relative = positions[i] - root.Position
				local d = relative.Magnitude
				stationaryMin = math.min(stationaryMin, d)

				if previousRelative then
					stationaryMin = math.min(
						stationaryMin,
						segmentMinDistance(previousRelative, relative)
					)
				end

				previousRelative = relative
			end

			if stationaryMin <= dangerRadius + maxReach + NEAR_ZONE + 1.0 then
				threats[#threats + 1] = {
					Data = data,
					Positions = positions,
					DangerRadius = dangerRadius,
					ErrorMargin = errorMargin,
					Speed = speed
				}
			end
		end
	end

	LastThreatCount = #threats
	return threats
end

local function simulatePlayerStep(position, velocity, inputDirection, walkSpeed, dt, firstStep)
	local target = inputDirection * walkSpeed
	local newPosition = position
	local newVelocity = velocity
	local remaining = dt

	if firstStep and PLAYER_ACTUATION_DELAY > 0 then
		local delay = math.min(PLAYER_ACTUATION_DELAY, remaining)
		newPosition += newVelocity * delay
		remaining -= delay
	end

	if remaining > 0 then
		local alpha =
			1 - math.exp(-remaining / math.max(PLAYER_RESPONSE_TIME, 0.001))
		local targetVelocity =
			newVelocity:Lerp(target, alpha)
		local averageVelocity =
			(newVelocity + targetVelocity) * 0.5
		newPosition += averageVelocity * remaining
		newVelocity = targetVelocity
	end

	return newPosition, newVelocity
end

local function evaluateThreatSegment(
	oldPlayerPosition,
	newPlayerPosition,
	stepIndex,
	threats
)
	local risk = 0
	local hits = 0
	local minClearance = math.huge

	for _, threat in ipairs(threats) do
		local oldProjectile = threat.Positions[stepIndex]
		local newProjectile = threat.Positions[stepIndex + 1]

		local relativeA = oldProjectile - oldPlayerPosition
		local relativeB = newProjectile - newPlayerPosition
		local distance = segmentMinDistance(relativeA, relativeB)
		local clearance = distance - threat.DangerRadius

		if clearance < minClearance then
			minClearance = clearance
		end

		if clearance <= 0 then
			hits += 1
			local penetration =
				math.min(-clearance, threat.DangerRadius + 1)
			risk +=
				HIT_PENALTY
				+ penetration * 8000
				+ threat.Speed * 4
		elseif clearance < NEAR_ZONE then
			local near = 1 - clearance / NEAR_ZONE
			local timeFactor =
				1.0
				+ (1 - math.clamp(
					(stepIndex - 1) / PLAN_STEPS,
					0,
					1
				)) * 0.8
			risk +=
				near * near
				* NEAR_RISK_WEIGHT
				* timeFactor
		end
	end

	return risk, hits, minClearance
end

local function evaluateBarrierSegment(oldPosition, newPosition)
	if pathHitsBarrier(oldPosition, newPosition) then
		return WALL_HIT_PENALTY, true, 0
	end

	local clearance = nearestBarrierDistance(newPosition)
	local risk = 0

	if clearance < BARRIER_NEAR_DISTANCE then
		local near =
			1 - math.clamp(
				clearance / BARRIER_NEAR_DISTANCE,
				0,
				1
			)
		risk =
			near * near
			* BARRIER_NEAR_WEIGHT
	end

	return risk, false, clearance
end

local function makeAbsoluteDirections(count)
	local list = table.create(count + 1)
	for i = 0, count - 1 do
		local angle = i * math.pi * 2 / count
		list[#list + 1] =
			Vector3.new(math.cos(angle), 0, math.sin(angle))
	end
	list[#list + 1] = Vector3.zero
	return list
end

local InitialDirectionList = makeAbsoluteDirections(INITIAL_DIRECTIONS)
local ZeroRestartDirectionList =
	makeAbsoluteDirections(ZERO_RESTART_DIRECTIONS)
local EscapeDirectionList = makeAbsoluteDirections(ESCAPE_DIRECTIONS)

local SteeringAngles = {
	0,
	math.rad(-22.5),
	math.rad(22.5),
	math.rad(-45),
	math.rad(45),
	math.rad(-90),
	math.rad(90),
	math.rad(180)
}

local function getNextInputs(previousDirection, depth)
	if depth == 1 then
		return InitialDirectionList
	end

	if previousDirection.Magnitude < 0.01 then
		return ZeroRestartDirectionList
	end

	local list = table.create(#SteeringAngles + 1)
	local unit = previousDirection.Unit

	for _, angle in ipairs(SteeringAngles) do
		list[#list + 1] = rotateY(unit, angle)
	end

	list[#list + 1] = Vector3.zero
	return list
end

local function nodeSort(a, b)
	if a.WallHits ~= b.WallHits then
		return a.WallHits < b.WallHits
	end
	if a.Hits ~= b.Hits then
		return a.Hits < b.Hits
	end
	if math.abs(a.Cost - b.Cost) > 0.001 then
		return a.Cost < b.Cost
	end
	return a.MinClearance > b.MinClearance
end

local function evaluateBaseline(root, humanoid, threats)
	local position = root.Position
	local velocity = flat(root.AssemblyLinearVelocity)
	local minClearance = math.huge
	local hits = 0
	local earliestImpact = math.huge
	local inputDirection = Vector3.zero

	for stepIndex = 1, PLAN_STEPS do
		local newPosition, newVelocity =
			simulatePlayerStep(
				position,
				velocity,
				inputDirection,
				humanoid.WalkSpeed,
				PLAN_DT,
				stepIndex == 1
			)

		local _, stepHits, stepClearance =
			evaluateThreatSegment(
				position,
				newPosition,
				stepIndex,
				threats
			)

		hits += stepHits
		minClearance = math.min(minClearance, stepClearance)

		if stepHits > 0 and earliestImpact == math.huge then
			earliestImpact = stepIndex * PLAN_DT
		end

		position = newPosition
		velocity = newVelocity
	end

	return {
		Hits = hits,
		MinClearance = minClearance,
		EarliestImpact = earliestImpact
	}
end

local function countEscapeOptions(node, humanoid, threats)
	local count = 0
	local stepIndex = PLAN_STEPS + 1

	for _, inputDirection in ipairs(EscapeDirectionList) do
		local newPosition, newVelocity =
			simulatePlayerStep(
				node.Pos,
				node.Vel,
				inputDirection,
				humanoid.WalkSpeed,
				PLAN_DT,
				false
			)

		if not pathHitsBarrier(node.Pos, newPosition) then
			local _, hits =
				evaluateThreatSegment(
					node.Pos,
					newPosition,
					stepIndex,
					threats
				)

			if hits == 0 then
				local secondPosition =
					select(
						1,
						simulatePlayerStep(
							newPosition,
							newVelocity,
							inputDirection,
							humanoid.WalkSpeed,
							PLAN_DT,
							false
						)
					)

				if not pathHitsBarrier(
					newPosition,
					secondPosition
				) then
					local _, secondHits =
						evaluateThreatSegment(
							newPosition,
							secondPosition,
							stepIndex + 1,
							threats
						)

					if secondHits == 0 then
						count += 1
					end
				end
			end
		end
	end

	return count
end

local function reconstructPath(node)
	local reverse = {}
	local cursor = node

	while cursor and cursor.Depth and cursor.Depth > 0 do
		reverse[#reverse + 1] = cursor.Pos
		cursor = cursor.Parent
	end

	local path = {}
	for i = #reverse, 1, -1 do
		path[#path + 1] = reverse[i]
	end
	return path
end

local function planPath(root, humanoid, threats)
	local beamWidth =
		#threats >= DENSE_THREAT_COUNT
		and DENSE_BEAM_WIDTH
		or BEAM_WIDTH

	local rootVelocity = flat(root.AssemblyLinearVelocity)

	local beam = {
		{
			Pos = root.Position,
			Vel = rootVelocity,
			Dir = Vector3.zero,
			FirstDir = Vector3.zero,
			Cost = 0,
			Hits = 0,
			WallHits = 0,
			MinClearance = math.huge,
			Depth = 0,
			Parent = nil
		}
	}

	for depth = 1, PLAN_STEPS do
		local nextBeam = {}

		for _, node in ipairs(beam) do
			local inputs = getNextInputs(node.Dir, depth)

			for _, inputDirection in ipairs(inputs) do
				local direction = clampUnit(inputDirection)

				local newPosition, newVelocity =
					simulatePlayerStep(
						node.Pos,
						node.Vel,
						direction,
						humanoid.WalkSpeed,
						PLAN_DT,
						depth == 1
					)

				local threatRisk, stepHits, stepClearance =
					evaluateThreatSegment(
						node.Pos,
						newPosition,
						depth,
						threats
					)

				local barrierRisk, wallHit =
					evaluateBarrierSegment(
						node.Pos,
						newPosition
					)

				local moveDistance =
					(flat(newPosition - node.Pos)).Magnitude

				local turnCost = 0
				if node.Dir.Magnitude > 0.01
					and direction.Magnitude > 0.01
				then
					local dot =
						math.clamp(
							node.Dir.Unit:Dot(direction.Unit),
							-1,
							1
						)
					turnCost =
						(1 - dot)
						* TURN_COST_WEIGHT
				elseif node.Dir.Magnitude > 0.01
					and direction.Magnitude <= 0.01
				then
					turnCost = TURN_COST_WEIGHT * 0.28
				end

				if depth == 1
					and CurrentMove.Magnitude > 0.01
					and direction.Magnitude > 0.01
				then
					local dot =
						math.clamp(
							CurrentMove.Unit:Dot(direction.Unit),
							-1,
							1
						)
					turnCost +=
						(1 - dot)
						* TURN_COST_WEIGHT
						* 1.7
				end

				local speedChange =
					math.abs(
						newVelocity.Magnitude
						- node.Vel.Magnitude
					)

				local moveCost =
					moveDistance * MOVE_COST_WEIGHT
					+ speedChange * SPEED_CHANGE_COST_WEIGHT
					+ turnCost

				if direction.Magnitude <= 0.01 then
					moveCost -= STOP_BONUS
				end

				local newNode = {
					Pos = newPosition,
					Vel = newVelocity,
					Dir = direction,
					FirstDir =
						depth == 1
						and direction
						or node.FirstDir,
					Cost =
						node.Cost
						+ threatRisk
						+ barrierRisk
						+ moveCost,
					Hits = node.Hits + stepHits,
					WallHits =
						node.WallHits
						+ (wallHit and 1 or 0),
					MinClearance =
						math.min(
							node.MinClearance,
							stepClearance
						),
					Depth = depth,
					Parent = node
				}

				nextBeam[#nextBeam + 1] = newNode
			end
		end

		table.sort(nextBeam, nodeSort)

		beam = {}
		local keep = math.min(beamWidth, #nextBeam)
		for i = 1, keep do
			beam[i] = nextBeam[i]
		end

		if #beam == 0 then
			return nil
		end
	end

	local finalistCount = math.min(#beam, math.max(12, math.floor(beamWidth * 0.65)))
	local finalists = {}

	for i = 1, finalistCount do
		local node = beam[i]
		local escapeOptions =
			countEscapeOptions(node, humanoid, threats)

		local averageOpen, minimumOpen, closeRays =
			barrierOpenness(node.Pos)

		local trapCost = 0

		if escapeOptions == 0 then
			trapCost += NO_ESCAPE_PENALTY
		else
			trapCost -= escapeOptions * ESCAPE_OPTION_REWARD
		end

		trapCost +=
			math.max(0, 4.0 - minimumOpen) * 18
			+ closeRays * BARRIER_CLOSE_RAY_PENALTY
			+ math.max(0, 7.0 - averageOpen) * 1.8

		finalists[#finalists + 1] = {
			Node = node,
			FinalCost = node.Cost + trapCost,
			EscapeOptions = escapeOptions
		}
	end

	table.sort(finalists, function(a, b)
		if a.Node.WallHits ~= b.Node.WallHits then
			return a.Node.WallHits < b.Node.WallHits
		end
		if a.Node.Hits ~= b.Node.Hits then
			return a.Node.Hits < b.Node.Hits
		end
		if math.abs(a.FinalCost - b.FinalCost) > 0.001 then
			return a.FinalCost < b.FinalCost
		end
		return a.Node.MinClearance > b.Node.MinClearance
	end)

	local best = finalists[1]
	if not best then
		return nil
	end

	return {
		Direction = best.Node.FirstDir,
		Path = reconstructPath(best.Node),
		Hits = best.Node.Hits,
		WallHits = best.Node.WallHits,
		MinClearance = best.Node.MinClearance,
		EscapeOptions = best.EscapeOptions,
		Cost = best.FinalCost
	}
end

local DebugFolder = workspace:FindFirstChild("AutoDodge_Debug")
if DebugFolder then
	DebugFolder:Destroy()
end

DebugFolder = Instance.new("Folder")
DebugFolder.Name = "AutoDodge_Debug"
DebugFolder.Parent = workspace

local PathParts = {}

local function clearPathVisual()
	for _, part in ipairs(PathParts) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	table.clear(PathParts)
end

local function updatePathVisual(path)
	clearPathVisual()

	if not SHOW_PATH or not path then
		return
	end

	for i, position in ipairs(path) do
		if i % 1 == 0 then
			local part = Instance.new("Part")
			part.Name = "P" .. tostring(i)
			part.Shape = Enum.PartType.Ball
			part.Size = Vector3.new(0.34, 0.34, 0.34)
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			part.Material = Enum.Material.Neon
			part.Transparency = 0.18
			part.Position = position + Vector3.new(0, 0.25, 0)
			part.Parent = DebugFolder
			PathParts[#PathParts + 1] = part
		end
	end
end

local oldGui = PlayerGui:FindFirstChild("AutoDodgeUI")
if oldGui then
	oldGui:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "AutoDodgeUI"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = false
Gui.DisplayOrder = 999999
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(260, 278)
Main.Position = UDim2.new(0.5, -130, 0.62, 0)
Main.BackgroundColor3 = Color3.fromRGB(24, 24, 29)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = Gui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 13)
MainCorner.Parent = Main

local Stroke = Instance.new("UIStroke")
Stroke.Color = Color3.fromRGB(75, 75, 88)
Stroke.Thickness = 1
Stroke.Parent = Main

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -20, 0, 28)
Title.Position = UDim2.fromOffset(10, 5)
Title.BackgroundTransparency = 1
Title.Text = "AUTO DODGE"
Title.TextColor3 = Color3.fromRGB(240, 240, 245)
Title.TextSize = 17
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local Status = Instance.new("TextLabel")
Status.Size = UDim2.new(1, -20, 0, 20)
Status.Position = UDim2.fromOffset(10, 34)
Status.BackgroundTransparency = 1
Status.Text = "EnemyProj 대기 중..."
Status.TextColor3 = Color3.fromRGB(230, 190, 80)
Status.TextSize = 12
Status.Font = Enum.Font.Gotham
Status.TextXAlignment = Enum.TextXAlignment.Left
Status.Parent = Main

local Info = Instance.new("TextLabel")
Info.Size = UDim2.new(1, -20, 0, 66)
Info.Position = UDim2.fromOffset(10, 55)
Info.BackgroundTransparency = 1
Info.Text = "Projectile 0 / Threat 0"
Info.TextColor3 = Color3.fromRGB(165, 165, 178)
Info.TextSize = 11
Info.Font = Enum.Font.Code
Info.TextXAlignment = Enum.TextXAlignment.Left
Info.TextYAlignment = Enum.TextYAlignment.Top
Info.Parent = Main

local Toggle = Instance.new("TextButton")
Toggle.Size = UDim2.new(1, -20, 0, 38)
Toggle.Position = UDim2.fromOffset(10, 124)
Toggle.BackgroundColor3 = Color3.fromRGB(58, 58, 66)
Toggle.BorderSizePixel = 0
Toggle.Text = "OFF"
Toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
Toggle.TextSize = 15
Toggle.Font = Enum.Font.GothamBold
Toggle.Parent = Main

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 9)
ToggleCorner.Parent = Toggle

local RadiusLabel = Instance.new("TextLabel")
RadiusLabel.Size = UDim2.new(1, -84, 0, 34)
RadiusLabel.Position = UDim2.fromOffset(42, 169)
RadiusLabel.BackgroundColor3 = Color3.fromRGB(43, 43, 50)
RadiusLabel.BorderSizePixel = 0
RadiusLabel.TextColor3 = Color3.fromRGB(235, 235, 240)
RadiusLabel.TextSize = 13
RadiusLabel.Font = Enum.Font.GothamBold
RadiusLabel.Parent = Main

local RadiusCorner = Instance.new("UICorner")
RadiusCorner.CornerRadius = UDim.new(0, 8)
RadiusCorner.Parent = RadiusLabel

local Minus = Instance.new("TextButton")
Minus.Size = UDim2.fromOffset(28, 34)
Minus.Position = UDim2.fromOffset(10, 169)
Minus.BackgroundColor3 = Color3.fromRGB(58, 58, 66)
Minus.BorderSizePixel = 0
Minus.Text = "-"
Minus.TextColor3 = Color3.fromRGB(255, 255, 255)
Minus.TextSize = 18
Minus.Font = Enum.Font.GothamBold
Minus.Parent = Main

local MinusCorner = Instance.new("UICorner")
MinusCorner.CornerRadius = UDim.new(0, 8)
MinusCorner.Parent = Minus

local Plus = Instance.new("TextButton")
Plus.Size = UDim2.fromOffset(28, 34)
Plus.Position = UDim2.new(1, -38, 0, 169)
Plus.BackgroundColor3 = Color3.fromRGB(58, 58, 66)
Plus.BorderSizePixel = 0
Plus.Text = "+"
Plus.TextColor3 = Color3.fromRGB(255, 255, 255)
Plus.TextSize = 18
Plus.Font = Enum.Font.GothamBold
Plus.Parent = Main

local PlusCorner = Instance.new("UICorner")
PlusCorner.CornerRadius = UDim.new(0, 8)
PlusCorner.Parent = Plus

local PathToggle = Instance.new("TextButton")
PathToggle.Size = UDim2.new(1, -20, 0, 34)
PathToggle.Position = UDim2.fromOffset(10, 210)
PathToggle.BackgroundColor3 = Color3.fromRGB(72, 82, 100)
PathToggle.BorderSizePixel = 0
PathToggle.Text = "PATH 표시 ON"
PathToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
PathToggle.TextSize = 13
PathToggle.Font = Enum.Font.GothamBold
PathToggle.Parent = Main

local PathCorner = Instance.new("UICorner")
PathCorner.CornerRadius = UDim.new(0, 8)
PathCorner.Parent = PathToggle

local Footer = Instance.new("TextLabel")
Footer.Size = UDim2.new(1, -20, 0, 24)
Footer.Position = UDim2.fromOffset(10, 249)
Footer.BackgroundTransparency = 1
Footer.Text = "MPC BEAM / 미래 탈출경로 평가"
Footer.TextColor3 = Color3.fromRGB(120, 120, 135)
Footer.TextSize = 10
Footer.Font = Enum.Font.Gotham
Footer.TextXAlignment = Enum.TextXAlignment.Left
Footer.Parent = Main

local dragging = false
local dragStart = nil
local startPosition = nil
local dragInput = nil

Main.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
	then
		dragging = true
		dragStart = input.Position
		startPosition = Main.Position

		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

Main.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch
	then
		dragInput = input
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging
		or input ~= dragInput
		or not dragStart
		or not startPosition
	then
		return
	end

	local delta = input.Position - dragStart
	Main.Position = UDim2.new(
		startPosition.X.Scale,
		startPosition.X.Offset + delta.X,
		startPosition.Y.Scale,
		startPosition.Y.Offset + delta.Y
	)
end)

local function refreshRadiusLabel()
	RadiusLabel.Text =
		string.format("Player Mini Radius  %.2f", PLAYER_MINI_RADIUS)
end

refreshRadiusLabel()

Minus.Activated:Connect(function()
	PLAYER_MINI_RADIUS =
		math.max(
			PLAYER_RADIUS_MIN,
			math.floor(
				(PLAYER_MINI_RADIUS - PLAYER_RADIUS_STEP)
				/ PLAYER_RADIUS_STEP
				+ 0.5
			) * PLAYER_RADIUS_STEP
		)
	refreshRadiusLabel()
end)

Plus.Activated:Connect(function()
	PLAYER_MINI_RADIUS =
		math.min(
			PLAYER_RADIUS_MAX,
			math.floor(
				(PLAYER_MINI_RADIUS + PLAYER_RADIUS_STEP)
				/ PLAYER_RADIUS_STEP
				+ 0.5
			) * PLAYER_RADIUS_STEP
		)
	refreshRadiusLabel()
end)

PathToggle.Activated:Connect(function()
	SHOW_PATH = not SHOW_PATH

	if SHOW_PATH then
		PathToggle.Text = "PATH 표시 ON"
		PathToggle.BackgroundColor3 =
			Color3.fromRGB(72, 82, 100)
		updatePathVisual(CurrentPath)
	else
		PathToggle.Text = "PATH 표시 OFF"
		PathToggle.BackgroundColor3 =
			Color3.fromRGB(58, 58, 66)
		clearPathVisual()
	end
end)

Toggle.Activated:Connect(function()
	ENABLED = not ENABLED

	if ENABLED then
		Toggle.Text = "ON"
		Toggle.BackgroundColor3 =
			Color3.fromRGB(50, 145, 80)
		disableControls()
	else
		Toggle.Text = "OFF"
		Toggle.BackgroundColor3 =
			Color3.fromRGB(58, 58, 66)
		CurrentMove = Vector3.zero
		CurrentPath = nil
		clearPathVisual()
		enableControls()

		local _, humanoid = getCharacter()
		if humanoid then
			humanoid:Move(Vector3.zero, false)
		end
	end
end)

local function formatImpact(value)
	if value == math.huge then
		return "-"
	end
	return string.format("%.2f", value)
end

local function formatClearance(value)
	if value == math.huge then
		return "-"
	end
	return string.format("%.2f", value)
end

local function getPlanInterval()
	if LastImpactTime ~= math.huge
		and LastImpactTime <= 0.32
	then
		return PLAN_INTERVAL_URGENT
	end

	if LastThreatCount > 0 then
		return PLAN_INTERVAL_ACTIVE
	end

	return PLAN_INTERVAL_IDLE
end

local planning = false

local function decisionStep()
	if not ENABLED or planning then
		return
	end

	local character, humanoid, root = getCharacter()
	if not character then
		CurrentMove = Vector3.zero
		CurrentPath = nil
		enableControls()
		return
	end

	disableControls()

	local now = os.clock()
	if now - LastPlanTime < getPlanInterval() then
		humanoid:Move(CurrentMove, false)
		return
	end

	LastPlanTime = now
	planning = true

	local started = os.clock()

	local ok, err = pcall(function()
		local threats = buildThreatSnapshot(root, humanoid)

		if #threats == 0 then
			CurrentMove = Vector3.zero
			CurrentPath = nil
			LastMinClearance = math.huge
			LastImpactTime = math.huge
			LastEscapeOptions = 0
			LastMode = "IDLE"
			clearPathVisual()
			humanoid:Move(Vector3.zero, false)
			return
		end

		local baseline = evaluateBaseline(root, humanoid, threats)
		LastMinClearance = baseline.MinClearance
		LastImpactTime = baseline.EarliestImpact

		local needPlan =
			baseline.Hits > 0
			or baseline.MinClearance <= PROACTIVE_CLEARANCE
			or (
				#threats >= DENSE_THREAT_COUNT
				and baseline.MinClearance
					<= DENSE_PROACTIVE_CLEARANCE
			)

		if not needPlan then
			CurrentMove = Vector3.zero
			CurrentPath = nil
			LastEscapeOptions = 0
			LastMode = "HOLD"
			clearPathVisual()
			humanoid:Move(Vector3.zero, false)
			return
		end

		local plan = planPath(root, humanoid, threats)

		if not plan then
			CurrentMove = Vector3.zero
			CurrentPath = nil
			LastEscapeOptions = 0
			LastMode = "NO PLAN"
			clearPathVisual()
			humanoid:Move(Vector3.zero, false)
			return
		end

		CurrentMove = plan.Direction
		CurrentPath = plan.Path
		LastMinClearance = plan.MinClearance
		LastEscapeOptions = plan.EscapeOptions

		if plan.Hits > 0 then
			LastMode = "RESCUE"
		elseif CurrentMove.Magnitude <= 0.01 then
			LastMode = "STOP"
		elseif #threats >= DENSE_THREAT_COUNT then
			LastMode = "DENSE"
		else
			LastMode = "DODGE"
		end

		updatePathVisual(CurrentPath)
		humanoid:Move(CurrentMove, false)
	end)

	LastPlanMs = (os.clock() - started) * 1000

	if not ok then
		LastError = tostring(err)
		LastMode = "ERROR"
	else
		LastError = ""
	end

	planning = false
end

RunService:BindToRenderStep(
	"AutoDodgePlanner",
	Enum.RenderPriority.Last.Value,
	function()
		if ENABLED then
			decisionStep()

			local _, humanoid = getCharacter()
			if humanoid then
				disableControls()
				humanoid:Move(CurrentMove, false)
			end
		else
			enableControls()
		end
	end
)

task.spawn(function()
	while Gui.Parent do
		if EnemyProj and EnemyProj.Parent then
			Status.Text =
				ENABLED
				and ("실행중 / " .. LastMode)
				or "준비됨"
			Status.TextColor3 =
				ENABLED
				and Color3.fromRGB(110, 225, 145)
				or Color3.fromRGB(165, 165, 175)
		else
			Status.Text = "EnemyProj 대기 중..."
			Status.TextColor3 =
				Color3.fromRGB(230, 190, 80)
		end

		Info.Text =
			"Projectile "
			.. tostring(LastProjectileCount)
			.. " / Threat "
			.. tostring(LastThreatCount)
			.. "\nImpact "
			.. formatImpact(LastImpactTime)
			.. " / Clear "
			.. formatClearance(LastMinClearance)
			.. "\nEscape "
			.. tostring(LastEscapeOptions)
			.. " / Plan "
			.. string.format("%.1fms", LastPlanMs)
			.. (
				LastError ~= ""
				and ("\n" .. string.sub(LastError, 1, 42))
				or ""
			)

		task.wait(0.10)
	end
end)

LocalPlayer.CharacterAdded:Connect(function()
	CurrentMove = Vector3.zero
	CurrentPath = nil
	LastImpactTime = math.huge
	LastMinClearance = math.huge
	LastEscapeOptions = 0
	clearPathVisual()
	task.wait(0.5)
	if ENABLED then
		disableControls()
	end
end)

bindEnemyProj(findEnemyProj())
