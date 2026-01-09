-- ServerScriptService/DragRace.server.lua
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Utils = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Utils"))
local RaceSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RaceSoundUtils"))
local GameApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("GameApiService"))
local ServerData = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("ServerData"))
local Billboard = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Billboard"))
local CARS_FOLDER = ReplicatedStorage:WaitForChild("Cars")
local DRAG_WP = workspace:WaitForChild("DragWaypoints")
local startRace = game.ServerScriptService:WaitForChild("StartDragRace")
local TriggerNextRace = game.ServerScriptService:WaitForChild("TriggerNextRace")

-- Current race level (used for NPC skin selection)
local raceLevel = "Common"
local raceNumber = nil

-- Get default free skin (cached)
local defaultFreeSkin = nil
local function getDefaultSkin()
	if not defaultFreeSkin then
		local allSkins = ServerData.GetAllSkins()
		defaultFreeSkin = Utils.getDefaultFreeSkin(allSkins) or "M2" -- Ultimate fallback
	end
	return defaultFreeSkin
end

local function getLaneWaypoints(prefix: string)
	-- Check if DRAG_WP exists
	if not DRAG_WP then
		error("[DragRace] DRAG_WP folder not found!")
	end
	-- Expect names like CarA1..4 and CarB1..4
	local list = {}
	for _, inst in ipairs(DRAG_WP:GetChildren()) do
		if inst:IsA("BasePart") or inst:IsA("Attachment") then
			local name = inst.Name
			if name:sub(1, #prefix) == prefix then
				local num = tonumber(name:match("(%d+)$"))
				if num then
					table.insert(list, {num = num, node = inst})
				end
			end
		end
	end
	table.sort(list, function(a, b) return a.num < b.num end)
	local out = {}
	for _, rec in ipairs(list) do
		table.insert(out, rec.node)
	end
	print("[DragRace] Found", #out, "waypoints for", prefix)
	assert(#out >= 4, prefix .. " needs at least 4 waypoints (1=start, 2=staging, 3=trap start, 4=fade end)")
	return out[1], out[2], out[3], out[4]
end

local function attachAO(primary: BasePart)
	local att = Instance.new("Attachment")
	att.Name = "DriveAttachment"
	att.Parent = primary

	local ao = Instance.new("AlignOrientation")
	ao.Name = "SteerAO"
	ao.Attachment0 = att
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Responsiveness = 18
	ao.RigidityEnabled = false
	ao.MaxTorque = math.huge
	ao.Parent = primary

	return att, ao
end

local function fadeOutAndDestroy(model: Model, duration: number)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local tween = TweenService:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Transparency = 1})
			tween:Play()
		end
	end
	task.delay(duration + 0.1, function()
		if model and model.Parent then
			model:Destroy()
		end
	end)
end

-- Global LeaderCam tracking
local leaderCam = nil
local leaderCamConnection = nil
local leaderCamTask = nil -- Track the LeaderCam task so we can stop it
local activeCars = {} -- Track active cars for leader determination
local leaderCamInitialPosition = nil -- Store the first position of LeaderCam

-- PlayerCam tracking (one per player vehicle in the race)
local playerCams = {} -- {[visibleUserId] = {cam = Part, carId = string, userId = string}}
local playerCamConnection = nil
local playerCamTask = nil

local function findLeaderCam()
	-- Find the existing LeaderCam in the DragCameras folder
	local dragCamerasFolder = workspace:FindFirstChild("DragCameras")
	if dragCamerasFolder then
		leaderCam = dragCamerasFolder:FindFirstChild("LeaderCam")
		if leaderCam then
			-- Always record the current CFrame as the initial position (in case it was moved)
			leaderCamInitialPosition = leaderCam.CFrame
		end
	end
end

local function updateLeaderCam()
	if not leaderCam or not leaderCam.Parent then return end

	-- Find the car that's furthest along the track and calculate positions
	local leadingCar = nil
	local leadingProgress = -math.huge
	local carProgressList = {}

	for lanePrefix, carData in pairs(activeCars) do
		if carData.car and carData.car.Parent and carData.root and carData.root.Parent then
			-- Calculate progress along the track (distance from start to current position)
			-- For drag races, we'll use X-axis as the main direction (track runs along negative X)
			-- Negate so that more negative X = higher progress
			local progress = -carData.root.Position.X
			table.insert(carProgressList, {car = carData.car, progress = progress})
			if progress > leadingProgress then
				leadingProgress = progress
				leadingCar = carData
			end
		end
	end

	-- Sort by progress descending and update name billboards with positions
	table.sort(carProgressList, function(a, b) return a.progress > b.progress end)
	for place, entry in ipairs(carProgressList) do
		Utils.updateNameBillboardPosition(entry.car, place)
	end

	if leadingCar and leadingCar.root then
		local carPos = leadingCar.root.Position
		local carForward = leadingCar.root.CFrame.LookVector
		local carRight = leadingCar.root.CFrame.RightVector

		-- Position LeaderCam 15 studs in front of the car, 2 studs up, 3 studs to the right
		local camOffset = carForward * 15 + carRight * 3 + Vector3.new(0, 2, 0)
		local camPosition = carPos + camOffset

		-- Check if LeaderCam drops significantly below its initial position (underground relative to track)
		-- Using initial position as reference since track may be below world Y=0
		if leaderCamInitialPosition and camPosition.Y < (leaderCamInitialPosition.Y - 50) then
			leaderCam.CFrame = leaderCamInitialPosition
			return
		end

		-- Orient LeaderCam to face the car
		leaderCam.CFrame = CFrame.lookAt(camPosition, carPos)
	end
end

local function cleanupLeaderCam()
	-- Stop the tracking task first
	if leaderCamTask then
		task.cancel(leaderCamTask)
		leaderCamTask = nil
	end

	-- Stop the tracking connection
	if leaderCamConnection then
		leaderCamConnection:Disconnect()
		leaderCamConnection = nil
	end

	-- Clear active cars so updateLeaderCam won't try to follow them
	activeCars = {}

	-- Return LeaderCam to its initial position
	if leaderCam and leaderCamInitialPosition then
		-- Return to the original CFrame position and orientation
		leaderCam.CFrame = leaderCamInitialPosition
	end
end

-- PlayerCam functions (one camera per player vehicle)
local function createPlayerCams(finishOrderData)
	local cameraFolder = workspace:FindFirstChild("DragCameras")
	if not cameraFolder then
		warn("[DragRace] DragCameras folder not found, cannot create PlayerCams")
		return
	end

	for userId, camData in pairs(playerCams) do
		if camData.cam and camData.cam.Parent then
			camData.cam:Destroy()
		end
	end
	playerCams = {}

	for _, entry in ipairs(finishOrderData) do
		if type(entry) == "table" and entry.vehicle_id and entry.competitor_type == "vehicle" then
			local success, vehicle = pcall(function()
				return GameApiService.GetVehicleById(entry.vehicle_id)
			end)

			if success and vehicle and vehicle.player_roblox_id then
				local oderId = tostring(vehicle.player_roblox_id)

				local playerCam = Instance.new("Part")
				playerCam.Name = "PlayerCam_" .. oderId
				playerCam.Size = Vector3.new(1, 1, 1)
				playerCam.Transparency = 1
				playerCam.Anchored = true
				playerCam.CanCollide = false
				playerCam.CanQuery = false
				playerCam.CanTouch = false

				if leaderCamInitialPosition then
					playerCam.CFrame = leaderCamInitialPosition
				end

				playerCam.Parent = cameraFolder

				playerCams[oderId] = {
					cam = playerCam,
					carId = nil,
					oderId = oderId,
					vehicleId = entry.vehicle_id
				}

				print("[DragRace] Created PlayerCam for user:", oderId)
			end
		end
	end
end

local function updatePlayerCams()
	for oderId, camData in pairs(playerCams) do
		if not camData.cam or not camData.cam.Parent then
			continue
		end

		local playerRoot = nil

		-- Drag race uses CarA and CarB lane prefixes
		for lanePrefix, carData in pairs(activeCars) do
			if carData.car and carData.car.Parent and carData.root and carData.root.Parent then
				-- Check if this car matches the player's vehicle
				for i, entry in ipairs(finishOrder) do
					if type(entry) == "table" and entry.vehicle_id == camData.vehicleId then
						local expectedLane = (i == 1) and "CarA" or "CarB"
						if lanePrefix == expectedLane then
							playerRoot = carData.root
							break
						end
					end
				end
				if playerRoot then break end
			end
		end

		if playerRoot then
			local carPos = playerRoot.Position
			local carForward = playerRoot.CFrame.LookVector
			local carRight = playerRoot.CFrame.RightVector

			-- Same offset as LeaderCam for drag
			local camOffset = carForward * 15 + carRight * 3 + Vector3.new(0, 2, 0)
			local camPosition = carPos + camOffset

			if leaderCamInitialPosition and camPosition.Y < (leaderCamInitialPosition.Y - 50) then
				camData.cam.CFrame = leaderCamInitialPosition
			else
				camData.cam.CFrame = CFrame.lookAt(camPosition, carPos)
			end
		end
	end
end

local function cleanupPlayerCams()
	if playerCamTask then
		task.cancel(playerCamTask)
		playerCamTask = nil
	end

	if playerCamConnection then
		playerCamConnection:Disconnect()
		playerCamConnection = nil
	end

	for oderId, camData in pairs(playerCams) do
		if camData.cam and camData.cam.Parent then
			camData.cam:Destroy()
		end
	end
	playerCams = {}
end

-- Helper function to apply color to all Body and Wheel parts of a car model
local function applyCarColor(car, color)
	if not color then return end
	for _, descendant in ipairs(car:GetDescendants()) do
		if (descendant.Name == "Body" or descendant.Name == "Wheel") and descendant:IsA("BasePart") then
			descendant.Color = color
		end
	end
end

-- Helper function to ensure a car model has a PrimaryPart set
local function ensurePrimaryPart(car)
	if car.PrimaryPart then return end

	-- Try to find a suitable PrimaryPart
	-- Priority: Root (manually set), then Body, then any BasePart
	local rootPart = nil
	local bodyPart = nil
	local anyPart = nil

	for _, descendant in ipairs(car:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant.Name == "Root" and not rootPart then
				rootPart = descendant
			elseif descendant.Name == "Body" and not bodyPart then
				bodyPart = descendant
			end
			if not anyPart then
				anyPart = descendant
			end
		end
	end

	local primaryPart = rootPart or bodyPart or anyPart
	if primaryPart then
		car.PrimaryPart = primaryPart
		print("[DragRace] Set PrimaryPart to:", primaryPart.Name, "for car:", car.Name)
	else
		warn("[DragRace] Could not find any BasePart to set as PrimaryPart for:", car.Name)
	end
end

-- Helper function to weld all parts in a model to the PrimaryPart
local function weldModelParts(car)
	local rootPart = car.PrimaryPart
	if not rootPart then
		warn("[DragRace] Cannot weld parts: no PrimaryPart set for", car.Name)
		return
	end

	local weldCount = 0
	for _, descendant in ipairs(car:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= rootPart then
			-- Create a WeldConstraint to hold parts together
			local weld = Instance.new("WeldConstraint")
			weld.Name = "AutoWeld_" .. descendant.Name
			weld.Part0 = rootPart
			weld.Part1 = descendant
			weld.Parent = rootPart

			-- Make sure the part isn't anchored (so it moves with the root)
			descendant.Anchored = false
			weldCount = weldCount + 1
		end
	end

	print("[DragRace] Welded", weldCount, "parts to PrimaryPart for:", car.Name)
end

-- Helper function to scale a model to a target scale factor
local function scaleModel(car, scaleFactor)
	-- Use Model:ScaleTo if available (newer Roblox API)
	if car.ScaleTo then
		local currentScale = car:GetScale()
		car:ScaleTo(scaleFactor)
		print("[DragRace] Scaled model", car.Name, "from", currentScale, "to", scaleFactor)
		return
	end

	-- Fallback: manually scale each part
	local rootPart = car.PrimaryPart
	if not rootPart then
		warn("[DragRace] Cannot scale: no PrimaryPart for", car.Name)
		return
	end

	local rootPos = rootPart.Position

	for _, descendant in ipairs(car:GetDescendants()) do
		if descendant:IsA("BasePart") then
			-- Scale the size
			descendant.Size = descendant.Size * scaleFactor

			-- Scale the position relative to root
			local offset = descendant.Position - rootPos
			descendant.Position = rootPos + (offset * scaleFactor)
		end
	end

	print("[DragRace] Manually scaled model", car.Name, "by factor", scaleFactor)
end

-- Helper function to create an NPC car with skin based on race level
local function createNPCCar(lanePrefix)
	-- Get all available skins
	local allSkins = ServerData.GetAllSkins()
	if not allSkins or #allSkins == 0 then
		warn("[DragRace] No skins available, cannot create NPC car")
		return nil
	end

	-- Filter skins for current race level
	local levelSkins = Utils.getSkinsForRaceLevel(allSkins, raceLevel)
	if #levelSkins == 0 then
		warn("[DragRace] No skins found for level:", raceLevel)
		return nil
	end

	-- Pick random skin and color
	local skin = Utils.getRandomSkin(levelSkins)
	local colorData = Utils.getRandomNPCColor()

	print("[DragRace] Creating NPC car with skin:", skin.name, "color:", colorData.name, "for level:", raceLevel)

	-- Find the car model in Cars folder
	local carTemplate = CARS_FOLDER:FindFirstChild(skin.name)
	if not carTemplate then
		warn("[DragRace] Car model not found for skin:", skin.name)
		return nil
	end

	-- Clone the car
	local car = carTemplate:Clone()
	car.Name = lanePrefix .. "_Car"

	-- Apply random color
	applyCarColor(car, colorData.color)

	return car
end

local function runLane(lanePrefix: string, topSpeed: number, barrier, displayName: string)
	-- Waypoints
	local wp1, wp2, wp3, wp4 = getLaneWaypoints(lanePrefix)
	local p1 = (wp1.CFrame or wp1.WorldCFrame).Position
	local p2 = (wp2.CFrame or wp2.WorldCFrame).Position
	local p3 = (wp3.CFrame or wp3.WorldCFrame).Position
	local p4 = (wp4.CFrame or wp4.WorldCFrame).Position

	-- Determine if this is an NPC or player vehicle and create appropriate car
	local car
	local isPlayerVehicle = type(displayName) == "table" and displayName.vehicle_id

	if isPlayerVehicle then
		-- Player vehicle: load car based on their vehicle's skin
		local vehicleData = displayName
		local skinName = vehicleData.skin or getDefaultSkin() -- Default to first free skin
		local carTemplate = CARS_FOLDER:FindFirstChild(skinName)
		if carTemplate then
			car = carTemplate:Clone()
			car.Name = lanePrefix .. "_Car"
			-- Apply player's vehicle color if set
			if vehicleData.color and vehicleData.color ~= "" then
				local color = Utils.parseColorString(vehicleData.color)
				if color then
					applyCarColor(car, color)
				end
			end
		else
			warn("[DragRace] Car model not found for player skin:", skinName, "- using default free skin")
			local fallbackTemplate = CARS_FOLDER:FindFirstChild(getDefaultSkin())
			if fallbackTemplate then
				car = fallbackTemplate:Clone()
				car.Name = lanePrefix .. "_Car"
			end
		end
	else
		-- NPC vehicle: create with random skin based on race level
		car = createNPCCar(lanePrefix)
	end

	if not car then
		warn("[DragRace] Failed to create car for lane:", lanePrefix)
		return
	end

	-- Ensure the car has a PrimaryPart set
	ensurePrimaryPart(car)

	-- Scale the car to 0.2
	scaleModel(car, 0.2)

	-- Find wheel models and their parts (before welding)
	local wheelModels, wheelParts = Utils.findWheelModels(car)

	-- Weld all parts together EXCEPT wheel parts (they'll use hinges)
	weldModelParts(car, wheelParts)

	car.Parent = workspace

	-- Now attach wheels with HingeConstraints (must be done after parenting)
	local wheelHinges = Utils.attachWheelsWithHinges(car, wheelModels, car.PrimaryPart)

	-- Wait a frame for physics to settle after creating hinges
	RunService.Heartbeat:Wait()

	-- Add car to active tracking
	local root = car.PrimaryPart :: BasePart
	activeCars[lanePrefix] = {car = car, root = root}
	local nameToDisplay = (type(displayName) == "table" and displayName.name) or tostring(displayName or lanePrefix)
	pcall(function()
		Utils.attachNameBillboard(car, nameToDisplay)
	end)
	assert(root, "Car model requires PrimaryPart")

	-- Set up engine sounds with random engine number (1-4)
	local engineSounds = RaceSoundUtils.setupCarEngineSounds(car)
	if engineSounds then
		-- Start with Rev sound (auto-transitions to Idle)
		RaceSoundUtils.transitionEngineSound(engineSounds, "Rev")
	end
	root.Massless = false
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	-- Make non-wheel parts massless to keep center of mass low and prevent tipping
	for _, part in ipairs(car:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "Wheel" then
			part.Massless = true
		end
	end

	-- Collect car data for race results
	local carData = {
		name = nameToDisplay,
		competitor_type = "npc",
		npc_key = nameToDisplay,
		power = topSpeed,
		speed = topSpeed,
		weight = 235, -- Default weight for NPC cars
		durability = 23, -- Default durability for NPC cars
		score = 0 -- Will be set from predicted data
	}

	-- Check if this is a player vehicle (displayName is a table with vehicle_id)
	if type(displayName) == "table" and displayName.vehicle_id then
		carData.competitor_type = "vehicle"
		carData.vehicle_id = displayName.vehicle_id
		carData.npc_key = nil -- Remove npc_key for player vehicles

		-- Use the predicted data from the race payload
		carData.power = displayName.power or topSpeed
		carData.speed = displayName.speed or topSpeed
		carData.weight = displayName.weight or 235
		carData.durability = displayName.durability or 23
		carData.score = displayName.score or 0 -- Use predicted score as base

		-- Also try to get actual vehicle stats from API as backup
		local success, vehicleData = pcall(function()
			return GameApiService.GetVehicleById(displayName.vehicle_id)
		end)

		if success and vehicleData then
			-- Use API data if predicted data is missing
			carData.power = carData.power or vehicleData.power or topSpeed
			carData.speed = carData.speed or vehicleData.speed or topSpeed
			carData.weight = carData.weight or vehicleData.weight or 235
			carData.durability = carData.durability or vehicleData.durability or 23
		end
	else
		-- For NPCs, use the predicted score from displayName if it's a table with score
		if type(displayName) == "table" and displayName.score then
			carData.score = displayName.score
			-- Also use other predicted stats if available
			carData.power = displayName.power or topSpeed
			carData.speed = displayName.speed or topSpeed
			carData.weight = displayName.weight or 235
			carData.durability = displayName.durability or 23
		end
	end

	-- stickier, less bouncy chassis for stability
	root.CustomPhysicalProperties = PhysicalProperties.new(3.0, 0.8, 0.0, 1.0, 1.0)

	local function lookCF(pos: Vector3, target: Vector3)
		return CFrame.lookAt(pos, target, Vector3.yAxis)
	end

	-- Stage 1: place at WP1 facing WP2
	local fwd12 = (p2 - p1).Magnitude > 1e-3 and (p2 - p1).Unit or Vector3.zAxis
	car:PivotTo(lookCF(p1, p1 + fwd12))
	local _, ao = attachAO(root)
	ao.CFrame = lookCF(p1, p1 + fwd12)
	root.AssemblyLinearVelocity = Vector3.zero

	-- Yaw oscillation for 3 seconds at WP1 (±15° swing) with subtle wheel spin
	local swingRad = math.rad(15)
	local freq = 0.5 -- Hz
	local elapsed = 0
	while elapsed < 3 do
		local dt = RunService.Heartbeat:Wait()
		local yaw = swingRad * math.sin(elapsed * 2 * math.pi * freq)
		ao.CFrame = lookCF(p1, p1 + fwd12) * CFrame.Angles(0, yaw, 0)
		root.AssemblyLinearVelocity = Vector3.zero
		-- Subtle wheel spin during staging (like revving)
		Utils.spinWheels(wheelHinges, 20, dt, root)
		elapsed += dt
	end

	-- Move to WP2 and align straight (staging)
	-- Roll slowly from WP1 to WP2 instead of snapping
	local rollSpeed = 25
	while true do
		local dt = RunService.Heartbeat:Wait()
		local pos = root.Position
		local toP2 = p2 - pos
		local dist = toP2.Magnitude
		if dist <= 1.0 then break end
		local dirToP2 = (dist > 1e-3) and toP2.Unit or fwd12
		ao.CFrame = lookCF(pos, pos + dirToP2)
		local horiz = Vector3.new(dirToP2.X, 0, dirToP2.Z)
		local approachSpeed = 0
		if horiz.Magnitude > 1e-3 then
			local velY = root.AssemblyLinearVelocity.Y
			approachSpeed = math.min(rollSpeed, math.max(10, dist * 3))
			root.AssemblyLinearVelocity = horiz.Unit * approachSpeed + Vector3.new(0, velY, 0)
		end
		-- Spin wheels based on roll speed
		Utils.spinWheels(wheelHinges, approachSpeed, dt, root)
	end
	-- Stop wheels when stopped at staging (no movement)
	Utils.spinWheels(wheelHinges, 0, 0, root)
	-- Snap to exact staging pose at WP2 and face toward WP3
	fwd12 = (p3 - p2).Magnitude > 1e-3 and (p3 - p2).Unit or fwd12
	car:PivotTo(lookCF(p2, p2 + fwd12))
	ao.CFrame = lookCF(p2, p2 + fwd12)
	root.AssemblyLinearVelocity = Vector3.zero

	-- Signal ready and synchronize both lanes; leave WP2 at same time after 5s pause
	barrier.ready += 1
	if barrier.ready == 2 then
		task.delay(5, function()
			barrier.go = true
			barrier.event:Fire()
		end)
	end
	if not barrier.go then barrier.event.Event:Wait() end

	-- Race is starting! Transition engine sound to Accelerate (auto-transitions to Racing)
	if engineSounds then
		RaceSoundUtils.transitionEngineSound(engineSounds, "Accelerate")
	end

	-- Acceleration phase: v reaches topSpeed at WP3
	local runDir = (p3 - p2)
	local runDist = runDir.Magnitude
	local forward = runDist > 1e-3 and runDir.Unit or fwd12
	ao.CFrame = lookCF(root.Position, root.Position + forward)

	local a = (topSpeed * topSpeed) / math.max(0.5, (2 * runDist)) -- v^2 = 2as
	local currentSpeed = 0
	local fadeActive = false
	local parts = nil
	local dir34 = (p4 - p3)
	local dist34 = math.max(1e-3, dir34.Magnitude)
	local dir34Unit = dir34 / dist34

	-- Idle-removal tracking
	local finishedRecorded = false
	local lastPos = root.Position
	local lastMoveTime = os.clock()
	local raceStarted = true -- we're past the barrier sync here

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not car.Parent or not root.Parent then
			if conn then conn:Disconnect() end
			return
		end

		-- Align toward lane direction each frame; keep vertical physics
		local pos = root.Position
		local toEnd3 = p3 - pos
		local toEnd4 = p4 - pos
		local distTo3 = toEnd3.Magnitude

		ao.CFrame = lookCF(pos, pos + forward)

		-- Accelerate toward topSpeed until WP3
		currentSpeed = math.min(topSpeed, currentSpeed + a * dt)

		-- Move horizontally only; preserve gravity
		local horizFwd = Vector3.new(forward.X, 0, forward.Z).Unit
		local vel = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = horizFwd * currentSpeed + Vector3.new(0, vel.Y, 0)

		-- Spin wheels based on current speed
		Utils.spinWheels(wheelHinges, currentSpeed, dt, root)

		-- Idle-removal: if no significant movement for 5s after start, remove and mark last
		local moved = (pos - lastPos).Magnitude
		if moved > 0.5 then
			lastMoveTime = os.clock()
			lastPos = pos
		end
		if raceStarted and not finishedRecorded and (os.clock() - lastMoveTime) > 5 then
			finishedRecorded = true
			-- For drag races, keep predicted score even for DNF (shouldn't happen in normal drag races)
			carData.score = carData.score or 1000
			if barrier and barrier.finishList then
				table.insert(barrier.finishList, {car = lanePrefix, status = "DNF", reason = "Idle 5s", t = os.clock(), data = carData})
			end
			-- Remove from active tracking
			activeCars[lanePrefix] = nil
			-- Clean up engine sounds
			RaceSoundUtils.stopEngineSounds(engineSounds)
			if conn then conn:Disconnect() end
			car:Destroy()
			return
		end

		-- Start fading after passing WP3; complete by WP4
		local along34 = (pos - p3):Dot(dir34Unit)
		if along34 >= 0 then
			if not fadeActive then
				fadeActive = true
				parts = {}
				for _, d in ipairs(car:GetDescendants()) do
					if d:IsA("BasePart") then table.insert(parts, d) end
				end
			end
			-- Slow the car to a quarter of top speed during fade so it doesn't disappear instantly
			local targetFadeSpeed = math.max(topSpeed * 0.25, 15)
			if currentSpeed > targetFadeSpeed then
				currentSpeed = targetFadeSpeed
			end
			local frac = math.clamp(along34 / dist34, 0, 1)
			-- Use linear fade for visibility across the segment
			local easeFrac = frac
			for _, bp in ipairs(parts) do
				bp.Transparency = easeFrac
				bp.CanCollide = false
			end
			if frac >= 1 then
				if not finishedRecorded then
					finishedRecorded = true
					-- For drag races, actual results should match predicted results exactly
					local finishTime = os.clock()
					-- Keep the original predicted score (no adjustments needed for drag races)
					carData.score = carData.score or 1000
					if barrier and barrier.finishList then
						table.insert(barrier.finishList, {car = lanePrefix, status = "Finished", t = finishTime, data = carData})
					end
				end
				-- Remove from active tracking
				activeCars[lanePrefix] = nil
				-- Clean up engine sounds
				RaceSoundUtils.stopEngineSounds(engineSounds)
				if conn then conn:Disconnect() end
				car:Destroy()
				return
			end
		end
	end)
end

-- Shared state from payload and start function (top-level)
local topSpeedTrack = 90
finishOrder = {"CarA","CarB"}
raceId = nil

local function isUuid(str)
	if type(str) ~= "string" then return false end
	return str:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end



startRace.OnInvoke = function(payload)
	if typeof(payload) == "table" then
		topSpeedTrack = payload.top_speed or payload.topSpeed or payload.topSpeedTrack or topSpeedTrack
		raceId = payload.race_id or payload.raceId or raceId
		raceLevel = payload.level or "Common" -- Get race level for NPC skin selection
		raceNumber = payload.number or payload.race_number or nil

		print("[DragRace] Starting race with level:", raceLevel, "number:", raceNumber)

		local incomingOrder = payload.expected_order or payload.finish_order or payload.finishOrder or finishOrder
		local resolved = {}
		for _, entry in ipairs(incomingOrder or {}) do
			if isUuid(entry.vehicle_id) then
				local okVeh, veh = pcall(function()
					return GameApiService.GetVehicleById(entry.vehicle_id)
				end)
				if okVeh and veh and veh.player_roblox_id then
					local robloxId = veh.player_roblox_id
					local playerName = Utils.GetPlayerName(robloxId)
					-- Preserve the vehicle data but add the player name, skin, and color
					local vehicleEntry = {
						vehicle_id = entry.vehicle_id,
						name = playerName or entry.name or "Unknown Player",
						power = veh.power or entry.power,
						speed = veh.speed or entry.speed,
						weight = veh.weight or entry.weight,
						durability = veh.durability or entry.durability,
						score = entry.score,
						skin = veh.skin or getDefaultSkin(),
						color = veh.color or ""
					}
					table.insert(resolved, vehicleEntry)
				else
					table.insert(resolved, entry)
				end
			else
				table.insert(resolved, entry)
			end
		end
		if #resolved > 0 then finishOrder = resolved end
		-- Drag race only supports two lanes; ignore extras
		if #(finishOrder or {}) > 2 then
			finishOrder = { finishOrder[1], finishOrder[2] }
		end

		-- Sort finishOrder by predicted scores (higher score = better car = should win)
		table.sort(finishOrder, function(a, b)
			local scoreA = a.score or 0
			local scoreB = b.score or 0
			return scoreA > scoreB -- Higher score comes first (wins)
		end)

		-- Randomly assign winner and loser to lanes (don't always put winner in CarA)
		if math.random() < 0.5 then
			-- Swap lanes: put winner in CarB, loser in CarA
			finishOrder[1], finishOrder[2] = finishOrder[2], finishOrder[1]
		end
	end

	local barrier = {ready = 0, go = false, event = Instance.new("BindableEvent"), finishList = {}}

	-- Update billboard to show race starting
	Utils.updateRaceBillboard("Drag", "starting")

	-- Fire stats update to clients with starting positions (Drag has no laps)
	Utils.fireRaceStatsUpdate("Drag", {
		status = "starting",
		raceLevel = raceLevel,
		raceNumber = raceNumber,
		currentLap = nil,
		totalLaps = nil,
		positions = finishOrder -- Show starting lineup
	})

	-- Find the existing LeaderCam
	findLeaderCam()

	-- Create PlayerCams for player vehicles in this race
	createPlayerCams(finishOrder)

	-- Calculate different speeds based on predicted performance
	local car1Speed = topSpeedTrack
	local car2Speed = topSpeedTrack

	if finishOrder[1] and finishOrder[2] then
		local score1 = finishOrder[1].score or 1000
		local score2 = finishOrder[2].score or 1000

		-- Create speed difference based on score difference
		local scoreDiff = math.abs(score1 - score2)
		local speedDiff = math.min(scoreDiff / 1000, 20) -- Max 20 speed difference

		if score1 > score2 then
			-- Car1 (better score) gets higher speed
			car1Speed = topSpeedTrack + speedDiff
			car2Speed = topSpeedTrack - speedDiff
		else
			-- Car2 (better score) gets higher speed
			car1Speed = topSpeedTrack - speedDiff
			car2Speed = topSpeedTrack + speedDiff
		end
	end

	task.spawn(function()
		runLane("CarB", car2Speed, barrier, finishOrder[2] or "CarB")
	end)
	task.spawn(function()
		runLane("CarA", car1Speed, barrier, finishOrder[1] or "CarA")
	end)

	-- Start LeaderCam and PlayerCam tracking after cars are created (with a small delay)
	leaderCamTask = task.spawn(function()
		task.wait(0.5) -- Wait for cars to be created
		leaderCamConnection = RunService.Heartbeat:Connect(updateLeaderCam)
	end)

	playerCamTask = task.spawn(function()
		task.wait(0.5) -- Wait for cars to be created
		playerCamConnection = RunService.Heartbeat:Connect(updatePlayerCams)
	end)

	-- Start race progress updates after barrier sync
	task.delay(6, function() -- 5 second barrier + 1 second buffer
		-- Update billboard to show race in progress
		Utils.updateRaceBillboard("Drag", "in_progress")

		-- For drag races, we can show the two cars racing
		local positions = {finishOrder[1] or "CarA", finishOrder[2] or "CarB"}

		-- Fire stats update to clients
		Utils.fireRaceStatsUpdate("Drag", {
			status = "in_progress",
			raceLevel = raceLevel,
			raceNumber = raceNumber,
			currentLap = nil,
			totalLaps = nil,
			positions = positions
		})
		Utils.updateRaceBillboard("Drag", "in_progress", positions)
		Billboard.UpdateCurrentPositions("Drag", positions)
	end)

	task.spawn(function()
		while #barrier.finishList < 2 do
			RunService.Heartbeat:Wait()
		end

		-- Build detailed race results instead of just finish order
		local detailedResults = {}
		local labelFor = {
			CarA = finishOrder[1] or "CarA",
			CarB = finishOrder[2] or "CarB",
		}

		-- Sort by score (higher score = better place)
		table.sort(barrier.finishList, function(a, b)
			local scoreA = (a.data and a.data.score) or 0
			local scoreB = (b.data and b.data.score) or 0

			if a.status == "Finished" and b.status == "Finished" then
				return scoreA > scoreB -- Higher score is better
			elseif a.status == "Finished" then
				return true -- Finished cars come before DNF
			elseif b.status == "Finished" then
				return false
			else
				return scoreA > scoreB -- Among DNF cars, sort by score
			end
		end)

		-- Build detailed results with car data
		for place, rec in ipairs(barrier.finishList) do
			local resultData = rec.data or {}
			resultData.place = place
			table.insert(detailedResults, resultData)
		end

		-- Update billboard with final results FIRST (before any blocking calls)
		local orderLabels = {}
		for _, rec in ipairs(barrier.finishList) do
			table.insert(orderLabels, labelFor[rec.car] or rec.car)
		end
		Utils.updateRaceBillboard("Drag", "finished", orderLabels)
		Billboard.ClearCurrentPositions("Drag")

		-- Fire stats update to clients with final results IMMEDIATELY
		Utils.fireRaceStatsUpdate("Drag", {
			status = "finished",
			raceLevel = raceLevel,
			raceNumber = raceNumber,
			currentLap = nil,
			totalLaps = nil,
			positions = orderLabels
		})

		-- Now do the API update and trigger next race (these can block)
		if raceId then
			-- Debug: Log the detailed results before sending
			print("[DragRace] Sending actual_results_json with", #detailedResults, "results:")
			for i, result in ipairs(detailedResults) do
				print(string.format("[DragRace]   Result %d: name=%s, competitor_type=%s, vehicle_id=%s, place=%s",
					i, tostring(result.name), tostring(result.competitor_type), tostring(result.vehicle_id), tostring(result.place)))
			end

			pcall(function()
				GameApiService.UpdateRace(raceId, {
					actual_results_json = detailedResults,
					race_ended = Utils.getIsoNow(),
					race_finished = true,
				})
			end)

			-- Clear vehicle cache for players whose vehicles finished the race
			for _, result in ipairs(detailedResults) do
				if type(result) == "table" and result.competitor_type == "vehicle" and result.vehicle_id then
					pcall(function()
						local vehicle = GameApiService.GetVehicleById(result.vehicle_id)
						if vehicle and vehicle.player_roblox_id then
							ServerData.RemovePlayerVehicles(vehicle.player_roblox_id)
						end
					end)
				end
			end

			cleanupLeaderCam()
			cleanupPlayerCams()
			-- Use task.spawn so TriggerNextRace doesn't block
			task.spawn(function()
				pcall(function()
					TriggerNextRace:Invoke("Drag")
				end)
			end)
		end
	end)

	return "started"
end

