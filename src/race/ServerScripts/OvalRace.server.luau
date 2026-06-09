-- ServerScriptService/RacePhysics.server.lua
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local CARS_FOLDER = ReplicatedStorage:WaitForChild("Cars")
local WAYPOINTS_FOLDER = workspace:WaitForChild("RaceWaypoints")
local NPCCarsFolder = workspace:FindFirstChild("NPCCars") or Instance.new("Folder")
local startRace = ServerScriptService:WaitForChild("StartOvalRace")
local TriggerNextRace = ServerScriptService:WaitForChild("TriggerNextRace")
local Utils = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Utils"))
local RaceSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RaceSoundUtils"))
local GameApiService = require(ServerScriptService:WaitForChild("GameScripts"):WaitForChild("GameApiService"))
local ServerData = require(ServerScriptService:WaitForChild("GameScripts"):WaitForChild("ServerData"))
local Billboard = require(ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Billboard"))

-- Current race level and number (used for NPC skin selection and stats display)
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

-- Global LeaderCam tracking
local leaderCam = nil
local leaderCamConnection = nil
local leaderCamTask = nil -- Track the LeaderCam task so we can stop it
local activeCars = {} -- Track active cars for leader determination
local leaderCamInitialPosition = nil -- Store the first position of LeaderCam
local raceFinished = false -- Track if any car has finished the race

-- PlayerCam tracking (one per player vehicle in the race)
local playerCams = {} -- {[visibleUserId] = {cam = Part, carId = string, userId = string}}
local playerCamConnection = nil
local playerCamTask = nil


local function findLeaderCam()
	-- Find the existing LeaderCam in the OvalCameras folder
	local ovalCamerasFolder = workspace:FindFirstChild("OvalCameras")
	if ovalCamerasFolder then
		leaderCam = ovalCamerasFolder:FindFirstChild("LeaderCam")
		if leaderCam then
			-- Always record the current CFrame as the initial position (in case it was moved)
			leaderCamInitialPosition = leaderCam.CFrame
		end
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

	-- Return LeaderCam to its initial position
	if leaderCam and leaderCamInitialPosition then
		-- Return to the original CFrame position and orientation
		leaderCam.CFrame = leaderCamInitialPosition
	end
end

-- PlayerCam functions (one camera per player vehicle)
local function createPlayerCams(finishOrderData)
	-- Find the camera folder
	local cameraFolder = workspace:FindFirstChild("OvalCameras")
	if not cameraFolder then
		warn("[OvalRace] OvalCameras folder not found, cannot create PlayerCams")
		return
	end

	-- Clean up any existing PlayerCams first
	for userId, camData in pairs(playerCams) do
		if camData.cam and camData.cam.Parent then
			camData.cam:Destroy()
		end
	end
	playerCams = {}

	-- Create a PlayerCam for each player vehicle
	for _, entry in ipairs(finishOrderData) do
		if type(entry) == "table" and entry.vehicle_id and entry.competitor_type == "vehicle" then
			-- Get the player's Roblox user ID from the vehicle
			local success, vehicle = pcall(function()
				return GameApiService.GetVehicleById(entry.vehicle_id)
			end)

			if success and vehicle and vehicle.player_roblox_id then
				local userId = tostring(vehicle.player_roblox_id)

				-- Create a camera part for this player
				local playerCam = Instance.new("Part")
				playerCam.Name = "PlayerCam_" .. userId
				playerCam.Size = Vector3.new(1, 1, 1)
				playerCam.Transparency = 1
				playerCam.Anchored = true
				playerCam.CanCollide = false
				playerCam.CanQuery = false
				playerCam.CanTouch = false

				-- Position at LeaderCam's initial position until race starts
				if leaderCamInitialPosition then
					playerCam.CFrame = leaderCamInitialPosition
				end

				playerCam.Parent = cameraFolder

				-- Track this PlayerCam
				playerCams[userId] = {
					cam = playerCam,
					carId = nil, -- Will be set when we know which car slot this player is in
					userId = userId,
					vehicleId = entry.vehicle_id
				}

				print("[OvalRace] Created PlayerCam for user:", userId)
			end
		end
	end
end

local function updatePlayerCams()
	if raceFinished then
		return
	end

	-- Update each PlayerCam to follow its player's vehicle
	for userId, camData in pairs(playerCams) do
		if not camData.cam or not camData.cam.Parent then
			continue
		end

		-- Find the car that belongs to this player
		local playerCar = nil
		local playerRoot = nil

		for carId, carData in pairs(activeCars) do
			if carData.car and carData.car.Parent and carData.root and carData.root.Parent then
				-- Check if this car matches the player's vehicle
				local carIdAttr = carData.car:GetAttribute("CarId")
				-- Match by checking finishOrder for vehicle_id
				for i, entry in ipairs(finishOrder) do
					if type(entry) == "table" and entry.vehicle_id == camData.vehicleId then
						-- This entry matches our player's vehicle
						-- Check if carId corresponds to this entry (car1, car2, etc.)
						local expectedCarId = "car" .. tostring(i)
						if carIdAttr == expectedCarId or carId == expectedCarId then
							playerCar = carData.car
							playerRoot = carData.root
							break
						end
					end
				end
				if playerCar then break end
			end
		end

		if playerRoot then
			local carPos = playerRoot.Position
			local carForward = playerRoot.CFrame.LookVector

			-- Position PlayerCam 15 studs in front of the car, 4 studs up (same as LeaderCam)
			local camOffset = carForward * 15 + Vector3.new(0, 4, 0)
			local camPosition = carPos + camOffset

			-- Check if PlayerCam drops significantly below initial position
			if leaderCamInitialPosition and camPosition.Y < (leaderCamInitialPosition.Y - 50) then
				camData.cam.CFrame = leaderCamInitialPosition
			else
				-- Orient PlayerCam to face the car
				local lookDirection = (carPos - camPosition).Unit
				camData.cam.CFrame = CFrame.lookAt(camPosition, camPosition + lookDirection)
			end
		end
	end
end

local function cleanupPlayerCams()
	-- Stop the tracking task
	if playerCamTask then
		task.cancel(playerCamTask)
		playerCamTask = nil
	end

	-- Stop the tracking connection
	if playerCamConnection then
		playerCamConnection:Disconnect()
		playerCamConnection = nil
	end

	-- Destroy all PlayerCam parts
	for userId, camData in pairs(playerCams) do
		if camData.cam and camData.cam.Parent then
			camData.cam:Destroy()
		end
	end
	playerCams = {}
end

local function updateLeaderCam()
	if not leaderCam or not leaderCam.Parent then 
		return 
	end

	-- If race has finished, return to origin and stop tracking
	if raceFinished then
		if leaderCamInitialPosition then
			leaderCam.CFrame = leaderCamInitialPosition
		end
		-- Stop tracking when race is finished
		cleanupLeaderCam()
		return
	end

	-- If no active cars, return to origin and stop tracking
	if not next(activeCars) then
		if leaderCamInitialPosition then
			leaderCam.CFrame = leaderCamInitialPosition
		end
		-- Stop tracking when no cars are active
		cleanupLeaderCam()
		return
	end

	-- Find the car in 1st place using the existing position tracking system
	local firstPlaceCar = nil

	for carId, carData in pairs(activeCars) do
		if carData.car and carData.car.Parent and carData.root and carData.root.Parent then
			-- Use the existing Place attribute to find 1st place
			local place = carData.car:GetAttribute("Place")
			if place == 1 then
				firstPlaceCar = carData
				break
			end
		end
	end

	if firstPlaceCar and firstPlaceCar.root then
		local carPos = firstPlaceCar.root.Position
		local carForward = firstPlaceCar.root.CFrame.LookVector
		local carRight = firstPlaceCar.root.CFrame.RightVector

		-- Position LeaderCam 15 studs in front of the car, 4 studs up (centered)
		local camOffset = carForward * 15 + Vector3.new(0, 4, 0)
		local camPosition = carPos + camOffset

		-- Check if LeaderCam drops significantly below its initial position (underground relative to track)
		-- Using initial position as reference since track may be below world Y=0
		if leaderCamInitialPosition and camPosition.Y < (leaderCamInitialPosition.Y - 50) then
			leaderCam.CFrame = leaderCamInitialPosition
			return
		end

		-- Orient LeaderCam to face the car
		local lookDirection = (carPos - camPosition).Unit
		leaderCam.CFrame = CFrame.lookAt(camPosition, camPosition + lookDirection)
	end
end

local function fadeOutAndDestroy(model, duration)
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


local RaceDirector = {}

-- tune these
RaceDirector.JITTER_AMP    = 0.15
RaceDirector.JITTER_FREQ   = 0.6
RaceDirector.RUBBER_GAIN   = 0.12
RaceDirector.FINAL_LOCK_WP = math.huge
RaceDirector.FINAL_MULTS   = {1.15, 1.05, 0.97, 0.92, 0.9, 0.88}

function RaceDirector:init(waypoints, laps, topSpeedTrack, finishOrder)
	self.laps = laps
	self.top = topSpeedTrack
	self.finishOrder = finishOrder or {}
	self.totalWps = #waypoints
	self.FINAL_LOCK_WP = math.max(2, self.totalWps - 5)
	self.carState = {}
	self.actualFinishOrder = {}
	self.finishedSet = {}
end

function RaceDirector:registerCar(carId, finishRank, seed)
	self.carState[carId] = {
		lap = 1, wpIndex = 1, progress = 0, seed = seed or math.random(1, 10^6),
		finishRank = finishRank, locked = false,
	}
end

function RaceDirector:updateProgress(carId, lap, wpIndex, fracAlongSegment)
	local s = self.carState[carId]; if not s then return end
	s.lap = lap
	s.wpIndex = wpIndex
	local lapFrac = (wpIndex - 1 + (fracAlongSegment or 0)) / self.totalWps
	s.progress = (lap - 1) + lapFrac
end

function RaceDirector:getMultiplier(carId)
	local s = self.carState[carId]; if not s then return 1 end
	local inFinal = (self.laps and s.lap == self.laps) or false
	if inFinal and s.wpIndex >= self.FINAL_LOCK_WP then
		local rank = math.clamp(s.finishRank, 1, #self.FINAL_MULTS)
		return self.FINAL_MULTS[rank]
	end
	local t = os.clock() * self.JITTER_FREQ
	local jitter = (math.noise(t, s.seed) or 0) * self.JITTER_AMP
	local myProg = s.progress
	local better, worse = 0, 0
	for id, other in pairs(self.carState) do
		if id ~= carId then
			if other.progress > myProg then better += 1 else worse += 1 end
		end
	end
	local rb = (worse - better) * self.RUBBER_GAIN
	return math.clamp(1 + jitter + rb, 0.8, 1.25)
end

function RaceDirector:getPlace(carId)
	local s = self.carState[carId]; if not s then return nil end
	local place = 1
	for id, other in pairs(self.carState) do
		if id ~= carId and other.progress > s.progress then
			place += 1
		end
	end
	return place
end

function RaceDirector:markFinished(carId)
	if self.finishedSet[carId] then return end
	self.finishedSet[carId] = true
	local rank = #self.actualFinishOrder + 1
	local entry = {carId = carId, rank = rank, time = os.clock(), place = tostring(rank)}
	table.insert(self.actualFinishOrder, entry)
	print(string.format("[Finish] %s placed #%d", carId, rank))
end

function RaceDirector:markWrecked(carId)
	if self.finishedSet[carId] then return end
	self.finishedSet[carId] = true
	local entry = {carId = carId, rank = #self.actualFinishOrder + 1, time = os.clock(), place = "DNF"}
	table.insert(self.actualFinishOrder, entry)
	print(string.format("[Wrecked] %s marked as DNF", carId))
end

-- Gather waypoints
local waypoints = {}
for _, inst in ipairs(WAYPOINTS_FOLDER:GetChildren()) do
	if inst:IsA("BasePart") or inst:IsA("Attachment") then
		table.insert(waypoints, inst)
	end
end
table.sort(waypoints, function(a, b) return tonumber(a.Name:match("%d+$")) < tonumber(b.Name:match("%d+$")) end)
assert(#waypoints >= 2, "Need at least 2 waypoints")

-- Controllers (AlignOrientation only)
local function attachControllers(model: Model)
	local root = model.PrimaryPart
	root.Massless = false
	root.Anchored = false
	pcall(function() root:SetNetworkOwner(nil) end) -- pcall in case of anchored parts

	local att = Instance.new("Attachment")
	att.Name = "DriveAttachment"
	att.Parent = root

	local ao = Instance.new("AlignOrientation")
	ao.Name = "SteerAO"
	ao.Attachment0 = att
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Responsiveness = 18
	ao.RigidityEnabled = false
	ao.MaxTorque = math.huge
	ao.Parent = root

	return att, ao
end

-- Create director instance by copying RaceDirector methods
local director = {}
for key, value in pairs(RaceDirector) do
	director[key] = value
end

-- AFTER you define NPCCarsFolder:
local NPCCarsFolder = workspace:FindFirstChild("NPCCars") or Instance.new("Folder")
NPCCarsFolder.Name = "NPCCars"
NPCCarsFolder.Parent = workspace  -- ✅ ensure parented

-- Helper function to apply color to car parts (only parts named exactly "Body" or "Wheel")
local function applyCarColor(car, color)
	if not color then return end
	for _, descendant in ipairs(car:GetDescendants()) do
		if (descendant.Name == "Body" or descendant.Name == "Wheel") and descendant:IsA("BasePart") then
			descendant.Color = color
		end
	end
end

-- Helper function to create an NPC car with skin based on race level
local function createNPCCar(carId)
	-- Get all available skins
	local allSkins = ServerData.GetAllSkins()
	if not allSkins or #allSkins == 0 then
		warn("[OvalRace] No skins available, cannot create NPC car")
		return nil
	end

	-- Filter skins for current race level
	local levelSkins = Utils.getSkinsForRaceLevel(allSkins, raceLevel)
	if not levelSkins or #levelSkins == 0 then
		warn("[OvalRace] No skins found for level:", raceLevel)
		return nil
	end

	-- Pick random skin and color
	local skin = Utils.getRandomSkin(levelSkins)
	local colorData = Utils.getRandomNPCColor()

	print("[OvalRace] Creating NPC car with skin:", skin.name, "color:", colorData.name, "for level:", raceLevel)

	-- Find the car model in Cars folder
	local carTemplate = CARS_FOLDER:FindFirstChild(skin.name)
	if not carTemplate then
		warn("[OvalRace] Car model not found for skin:", skin.name)
		return nil
	end

	-- Clone the car
	local car = carTemplate:Clone()
	car.Name = carId

	-- Apply the random color
	applyCarColor(car, colorData.color)

	return car
end

-- Optional passing feature (isolated)
local ENABLE_PASSING = true
local function computePassingOffset(selfCar: Model, selfId: string, rootPos: Vector3, wpPos: Vector3, segDir: Vector3, right: Vector3)
	if not ENABLE_PASSING then return 0 end
	local segUnit = (segDir.Magnitude > 1e-3) and segDir.Unit or Vector3.zAxis
	local lookAhead = 18
	local laneWidth = 3.5
	local lateralThreshold = 3.0
	local selfAlong = (rootPos - wpPos):Dot(segUnit)
	local baseOffset = selfCar:GetAttribute("_baseOffset") or 0
	local passSidePref = selfCar:GetAttribute("_passSide") or 1
	local blocked = false
	for _, other in ipairs(NPCCarsFolder:GetChildren()) do
		if other ~= selfCar and other.PrimaryPart then
			local oPos = other:GetPivot().Position
			local along = (oPos - wpPos):Dot(segUnit)
			local ahead = along - selfAlong
			if ahead > 0 and ahead < lookAhead then
				local lateral = (oPos - rootPos):Dot(right)
				if math.abs(lateral) < lateralThreshold then
					blocked = true
					break
				end
			end
		end
	end
	if blocked then
		local outward = (baseOffset ~= 0) and (baseOffset > 0 and 1 or -1) or passSidePref
		return baseOffset + outward * laneWidth
	else
		return baseOffset
	end
end

local function runCar(carId: string, finishRank: number, topSpeedTrack: number, accel: number, brakeAccel: number, laps: number?, startOffset: Vector3?, startDelay: number?)
	-- Get display name info from finishOrder
	local displayName = (type(finishOrder) == "table" and finishOrder[finishRank]) or carId

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
			car.Name = carId
			-- Apply player's vehicle color if set
			if vehicleData.color and vehicleData.color ~= "" then
				local color = Utils.parseColorString(vehicleData.color)
				if color then
					applyCarColor(car, color)
				end
			end
		else
			warn("[OvalRace] Car model not found for player skin:", skinName, "- using default free skin")
			local fallbackTemplate = CARS_FOLDER:FindFirstChild(getDefaultSkin())
			if fallbackTemplate then
				car = fallbackTemplate:Clone()
				car.Name = carId
			end
		end
	else
		-- NPC vehicle: create with random skin based on race level
		car = createNPCCar(carId)
	end

	if not car then
		warn("[OvalRace] Failed to create car for:", carId)
		return
	end

	car:SetAttribute("CarId", carId)

	-- Ensure the car has a PrimaryPart set
	Utils.ensurePrimaryPart(car)

	-- Scale the car to 0.2
	Utils.scaleModel(car, 0.2)

	-- Find wheel models and their parts (before welding)
	local wheelModels, wheelParts = Utils.findWheelModels(car)

	-- Weld all parts together EXCEPT wheel parts (they'll use constraints)
	Utils.weldModelParts(car, wheelParts)

	car.Parent = workspace

	-- Set up wheel spinning with CylindricalConstraints
	local root = car.PrimaryPart :: BasePart
	local wheelData = Utils.attachWheelsWithHinges(car, wheelModels, root)
	task.wait() -- Give physics a frame to settle

	-- Add car to active tracking
	activeCars[carId] = {car = car, root = root, wheelData = wheelData}

	-- Attach display name billboard
	local nameToDisplay = (type(displayName) == "table" and displayName.name) or tostring(displayName)
	pcall(function()
		Utils.attachNameBillboard(car, nameToDisplay)
	end)

	assert(root, "[OvalRace] Car requires PrimaryPart set")

	-- Set up engine sounds with random engine number (1-4)
	local engineSounds = RaceSoundUtils.setupCarEngineSounds(car)
	if engineSounds then
		-- Start with Rev sound (auto-transitions to Idle)
		RaceSoundUtils.transitionEngineSound(engineSounds, "Rev")
	end

	-- Compute start transform using WP1->WP2
	local wp1 = waypoints[1]
	local wp2 = waypoints[2]
	local p1 = (wp1.CFrame or wp1.WorldCFrame).Position
	local p2 = (wp2.CFrame or wp2.WorldCFrame).Position
	local fwd0 = (p2 - p1).Magnitude > 1e-3 and (p2 - p1).Unit or Vector3.zAxis
	local offset = startOffset or Vector3.new(0, 0, 0)
	local spawnCF = CFrame.new(p1 + fwd0 * 6 + offset, p1 + fwd0 * 12 + offset)
	car:PivotTo(spawnCF)
	-- Persist base lane offset (signed distance along track right)
	local baseOffset = offset:Dot((fwd0:Cross(Vector3.new(0,1,0))).Unit)
	car:SetAttribute("_baseOffset", baseOffset)
	car:SetAttribute("_passSide", (math.random() < 0.5) and -1 or 1) -- outward preference when neutral

	local att, ao = attachControllers(car)

	-- Register with the director
	director:registerCar(carId, finishRank, math.random(1, 10^6))

	-- Follow state
	local wpIndex = 1
	local totalWps = #waypoints
	local remainingLaps = laps -- integer, e.g. 3. (Use >1 to see finishes lock in)
	local targetSpeed = 0
	local currentSpeed = 0
	local delayRemaining = startDelay or 0

	-- Waypoint reach parameters
	local reachRadius = 6
	local slowRadius = 24

	-- Position-based stuck detection (tracks if car moves at least 1 car length in 5 seconds)
	local STUCK_CHECK_INTERVAL = 5.0 -- seconds
	local MIN_PROGRESS_DISTANCE = 4.0 -- studs (~1 car length after 0.2 scale)
	local lastProgressPosition = nil
	local timeSinceProgressCheck = 0

	local function nextIndex(i) return (i % totalWps) + 1 end
	local rcParams = RaycastParams.new()
	rcParams.FilterType = Enum.RaycastFilterType.Exclude
	-- Ignore car, waypoints, NPC cars, and OvalShell (flat barrier parts)
	local ovalShell = workspace:FindFirstChild("Oval") and workspace.Oval:FindFirstChild("OvalShell")
	local filterList = {car, WAYPOINTS_FOLDER, NPCCarsFolder}
	if ovalShell then
		table.insert(filterList, ovalShell)
	end
	rcParams.FilterDescendantsInstances = filterList

	local conn
	local function onHeartbeat(dt)
		if not car.Parent or not root.Parent then
			if conn then conn:Disconnect() end
			return
		end

		local rootCF = car:GetPivot()
		local rootPos = rootCF.Position

		-- WP math
		local wp = waypoints[wpIndex]
		local nextWp = waypoints[nextIndex(wpIndex)]
		local wpPos = (wp.CFrame or wp.WorldCFrame).Position
		local nextPos = (nextWp.CFrame or nextWp.WorldCFrame).Position

		local seg = nextPos - wpPos
		local segLen = seg.Magnitude
		local segDir = (segLen > 1e-3) and (seg / segLen) or rootCF.LookVector

		local rel = rootPos - wpPos
		local t = (segLen > 1e-3) and math.clamp(rel:Dot(segDir) / segLen, 0, 1) or 0
		local alongPos = wpPos + segDir * (t * segLen)

		local dirToAlong = (alongPos - rootPos)
		local distToAlong = dirToAlong.Magnitude
		local aimDir = (distToAlong > 1e-3) and (dirToAlong / distToAlong):Lerp(segDir, 0.35).Unit or segDir

		-- Ground normal using car's local down for better banking detection on oval tracks
		local carUp = rootCF.UpVector
		local rayOrigin = rootPos + carUp * 5
		local rayDir = -carUp * 80
		local rayHit = workspace:Raycast(rayOrigin, rayDir, rcParams)

		-- If local ray misses, try world down as fallback
		if not rayHit then
			rayHit = workspace:Raycast(rootPos + Vector3.new(0, 5, 0), Vector3.new(0, -80, 0), rcParams)
		end

		local up = (rayHit and rayHit.Normal) or Vector3.new(0,1,0)

		-- Smooth ground up to reduce jitter (0.7 for responsive banking on oval tracks)
		local lastUp = (car:GetAttribute("_lastUpX") and Vector3.new(car:GetAttribute("_lastUpX"), car:GetAttribute("_lastUpY"), car:GetAttribute("_lastUpZ"))) or up
		up = lastUp:Lerp(up, 0.7).Unit
		car:SetAttribute("_lastUpX", up.X)
		car:SetAttribute("_lastUpY", up.Y)
		car:SetAttribute("_lastUpZ", up.Z)

		-- During start delay, keep cars oriented straight toward WP2 and stationary
		if delayRemaining > 0 then
			local startForwardOnPlane = fwd0 - fwd0:Dot(up) * up
			local forward = (startForwardOnPlane.Magnitude > 1e-3) and startForwardOnPlane.Unit or fwd0
			local right = forward:Cross(up).Unit
			forward = up:Cross(right).Unit
			ao.CFrame = CFrame.lookAt(rootPos, rootPos + forward, up)
			local vel = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
			local wasDelayed = delayRemaining > 0
			delayRemaining = delayRemaining - dt
			-- Transition to Accelerate when delay ends (race starts)
			if wasDelayed and delayRemaining <= 0 and engineSounds then
				RaceSoundUtils.transitionEngineSound(engineSounds, "Accelerate")
			end
			return
		end

		-- Optional passing: offset aim laterally if blocked by a car ahead
		local provisionalRight
		do
			local tmpForward = aimDir - aimDir:Dot(up) * up
			tmpForward = (tmpForward.Magnitude > 1e-3) and tmpForward.Unit or rootCF.LookVector
			provisionalRight = tmpForward:Cross(up).Unit
		end
		local lateralOffset = computePassingOffset(car, carId, rootPos, wpPos, segDir, provisionalRight)
		if lateralOffset ~= 0 then
			local offsetTarget = alongPos + provisionalRight * lateralOffset
			local toOffset = offsetTarget - rootPos
			local distOff = toOffset.Magnitude
			if distOff > 1e-3 then
				aimDir = (toOffset / distOff):Lerp(segDir, 0.2).Unit
			end
		end

		local fwdOnPlane = aimDir - aimDir:Dot(up) * up
		if fwdOnPlane.Magnitude < 1e-3 then
			fwdOnPlane = segDir - segDir:Dot(up) * up
		end
		-- Smooth forward as well
		local lastFwd = (car:GetAttribute("_lastFwdX") and Vector3.new(car:GetAttribute("_lastFwdX"), car:GetAttribute("_lastFwdY"), car:GetAttribute("_lastFwdZ"))) or (fwdOnPlane.Magnitude > 1e-3 and fwdOnPlane.Unit or rootCF.LookVector)
		local forward = lastFwd:Lerp((fwdOnPlane.Magnitude > 1e-3 and fwdOnPlane.Unit or rootCF.LookVector), 0.25).Unit
		car:SetAttribute("_lastFwdX", forward.X)
		car:SetAttribute("_lastFwdY", forward.Y)
		car:SetAttribute("_lastFwdZ", forward.Z)
		local right = forward:Cross(up).Unit
		forward = up:Cross(right).Unit

		-- Over-rotation visual yaw: +/−10° when turning, straighten after 4 studs of straight travel
		local prevPos = (car:GetAttribute("_ppx") and Vector3.new(car:GetAttribute("_ppx"), car:GetAttribute("_ppy"), car:GetAttribute("_ppz"))) or rootPos
		local ds = (rootPos - prevPos).Magnitude
		car:SetAttribute("_ppx", rootPos.X)
		car:SetAttribute("_ppy", rootPos.Y)
		car:SetAttribute("_ppz", rootPos.Z)

		local straightDist = car:GetAttribute("_straightDist") or 0
		local yawOffset = car:GetAttribute("_yawOffset") or 0

		-- Determine turn angle/sign using horizontal components
		local desiredHoriz = Vector3.new(fwdOnPlane.X, 0, fwdOnPlane.Z).Unit
		local currentHoriz = Vector3.new(forward.X, 0, forward.Z).Unit
		local dotp = math.clamp(currentHoriz:Dot(desiredHoriz), -1, 1)
		local ang = math.acos(dotp)
		local crossY = currentHoriz:Cross(desiredHoriz).Y
		local turnSign = 0
		if math.abs(crossY) > 1e-4 then turnSign = (crossY > 0) and 1 or -1 end

		if ang > math.rad(5) and turnSign ~= 0 then
			yawOffset = -turnSign * math.rad(30)
			straightDist = 0
		else
			straightDist = straightDist + ds
			if straightDist >= 4 then yawOffset = 0 end
		end
		car:SetAttribute("_straightDist", straightDist)
		car:SetAttribute("_yawOffset", yawOffset)

		-- Build display forward rotated around up by yawOffset (visual only)
		local rightHoriz = currentHoriz:Cross(up).Unit
		local displayHoriz = (currentHoriz * math.cos(yawOffset) + rightHoriz * math.sin(yawOffset)).Unit
		-- Reconstruct 3D forward aligned with banked up
		local dispRight = displayHoriz:Cross(up).Unit
		local displayForward = up:Cross(dispRight).Unit

		-- Align orientation to bank without changing position, using displayForward
		ao.CFrame = CFrame.lookAt(rootPos, rootPos + displayForward, up)

		-- Speed target: Detect turn at current waypoint and slow down earlier
		-- Calculate turn angle AT the current waypoint (the turn car is approaching)
		local dist = (wpPos - rootPos).Magnitude

		-- Vector from car to current waypoint, and from current to next waypoint
		local segA = (wpPos - rootPos).Unit
		local segB = (nextPos - wpPos).Unit
		local turnDot = math.clamp(segA:Dot(segB), -1, 1)
		local turnAngle = math.acos(turnDot)
		local isSignificantTurn = turnAngle > math.rad(15)  -- Lowered from 20 to detect turns earlier

		local desired = topSpeedTrack

		-- Prep distance scales with BOTH speed AND turn severity
		-- Sharper turns need significantly more distance to slow down
		local basePrepDist = currentSpeed * 1.2  -- Scale with current speed
		local turnSeverity = turnAngle / math.pi  -- 0 = straight, 1 = hairpin
		local turnBonus = turnSeverity * 50  -- Add up to 50 studs for hairpins
		local prepDist = math.clamp(basePrepDist + turnBonus, 25, 120)  -- Much larger range than fixed 24

		if isSignificantTurn and dist < prepDist then
			local cornerFactor = 1 - turnSeverity  -- 1 = straight, 0 = hairpin
			local cornerCap = math.max(10, topSpeedTrack * (0.3 + 0.7 * cornerFactor))
			-- Ease into the cap as we get closer to the turn
			local ramp = 1 - math.clamp(dist / prepDist, 0, 1)
			local easedCap = cornerCap + (desired - cornerCap) * (1 - ramp)
			desired = math.min(desired, easedCap)
		end
		desired *= director:getMultiplier(carId)

		if currentSpeed < desired then
			currentSpeed = math.min(desired, currentSpeed + accel * dt)
		else
			currentSpeed = math.max(desired, currentSpeed - brakeAccel * dt)
		end

		-- Move with smoothed velocity to prevent bouncing
		local horizForward = Vector3.new(forward.X, 0, forward.Z)
		if horizForward.Magnitude < 1e-3 then
			horizForward = Vector3.new(segDir.X, 0, segDir.Z)
		end
		horizForward = (horizForward.Magnitude > 1e-3) and horizForward.Unit or Vector3.zero

		local vel = root.AssemblyLinearVelocity
		local desiredVel = horizForward * currentSpeed
		local currentHorizVel = Vector3.new(vel.X, 0, vel.Z)

		-- Dynamic smoothness: smooth when on track, aggressive when stuck or far off
		-- Check if car is stuck (actual speed much lower than desired speed)
		local actualSpeed = currentHorizVel.Magnitude
		local speedRatio = (currentSpeed > 5) and (actualSpeed / currentSpeed) or 1.0

		-- Check if car is far from the racing line
		-- We use the difference between aim direction and actual velocity direction
		local actualDir = (actualSpeed > 1) and (currentHorizVel / actualSpeed) or horizForward
		local directionAlignment = actualDir:Dot(horizForward)

		-- Base smoothness: 0.25 for normal racing (smooth cornering)
		-- Increase smoothness when:
		--   1. Car is stuck (speedRatio < 0.7) - needs more aggressive recovery
		--   2. Car is misaligned (directionAlignment < 0.7) - needs to correct direction quickly
		local baseSmoothness = 0.25
		local stuckBonus = (speedRatio < 0.7) and 0.3 or 0  -- Add 0.3 if stuck
		local misalignBonus = (directionAlignment < 0.7) and 0.2 or 0  -- Add 0.2 if misaligned

		local turnSmoothness = math.min(baseSmoothness + stuckBonus + misalignBonus, 0.85)
		local smoothedVel = currentHorizVel:Lerp(desiredVel, turnSmoothness)

		root.AssemblyLinearVelocity = smoothedVel + Vector3.new(0, vel.Y, 0)

		-- Spin wheels based on current speed
		local carData = activeCars[carId]
		if carData and carData.wheelData then
			Utils.spinWheels(carData.wheelData, currentSpeed, dt, root)
		end

		-- Update engine sound based on driving state (slowing for turns, accelerating out)
		RaceSoundUtils.updateEngineSoundForDriving(engineSounds, currentSpeed, desired, topSpeedTrack)

		-- Position-based stuck detection (car must move at least 1 car length every 5 seconds)
		timeSinceProgressCheck = timeSinceProgressCheck + dt

		-- Initialize last position on first check
		if not lastProgressPosition then
			lastProgressPosition = rootPos
		end

		-- Check progress every 5 seconds
		if timeSinceProgressCheck >= STUCK_CHECK_INTERVAL then
			local distanceMoved = (rootPos - lastProgressPosition).Magnitude

			if distanceMoved < MIN_PROGRESS_DISTANCE then
				-- Car hasn't moved enough in 5 seconds - mark as DNF
				print(string.format("[Wrecked] %s only moved %.1f studs in %.1f seconds (min: %.1f), marking as DNF", 
					carId, distanceMoved, STUCK_CHECK_INTERVAL, MIN_PROGRESS_DISTANCE))
				director:markWrecked(carId)
				-- Remove from finishOrder
				for i, carName in ipairs(finishOrder) do
					if carName == carId then
						table.remove(finishOrder, i)
						break
					end
				end
				-- Remove from active tracking
				activeCars[carId] = nil
				-- Clean up engine sounds
				RaceSoundUtils.stopEngineSounds(engineSounds)
				if conn then conn:Disconnect() end
				task.delay(2, function()
					if car then car:Destroy() end
				end)
				return
			end

			-- Reset for next check
			lastProgressPosition = rootPos
			timeSinceProgressCheck = 0
		end

		-- progress
		director:updateProgress(carId, (laps and (laps - (remainingLaps or laps) + 1)) or 1, wpIndex, t)
		-- update live place attribute for debugging/UI
		local place = director:getPlace(carId)
		if place then
			car:SetAttribute("Place", place)
			Utils.updateNameBillboardPosition(car, place)
		end

		-- advance when sufficiently progressed along segment or near waypoint center
		if t >= 0.98 or (wpPos - rootPos).Magnitude <= reachRadius then
			wpIndex = nextIndex(wpIndex)
			director:updateProgress(carId, (laps and (laps - (remainingLaps or laps) + 1)) or 1, wpIndex, 0.0)

			if wpIndex == 1 and remainingLaps ~= nil then
				remainingLaps = remainingLaps - 1
				if remainingLaps <= 0 then
					director:markFinished(carId)
					-- Continue past finish line and fade out
					if not car:GetAttribute("_finished") then
						car:SetAttribute("_finished", true)
						-- Mark race as finished when first car finishes
						raceFinished = true
					end
					-- Remove from active tracking (but keep heartbeat running for coast)
					activeCars[carId] = nil
					-- Let car coast for 1.5 seconds before cleanup
					task.delay(1.5, function()
						-- Clean up engine sounds
						RaceSoundUtils.stopEngineSounds(engineSounds)
						-- Disconnect heartbeat connection for this car
						if conn then conn:Disconnect() end
						-- Start fade out after sounds stop
						task.delay(0.5, function()
							if car and car.Parent then
								fadeOutAndDestroy(car, 2.0)
							end
						end)
					end)
					-- If this was the last finisher, report and trigger next
					if not resultsReported and #director.actualFinishOrder >= #finishOrder then
						resultsReported = true
						local map = { car1 = finishOrder[1], car2 = finishOrder[2], car3 = finishOrder[3], car4 = finishOrder[4] }
						local orderLabels = {}
						for _, entry in ipairs(director.actualFinishOrder) do
							local label = map[entry.carId] or entry.carId
							-- Add place field to the existing object structure
							if type(label) == "table" then
								label.place = entry.place
								table.insert(orderLabels, label)
							else
								-- Fallback for string labels (NPCs)
								table.insert(orderLabels, {
									name = label,
									place = entry.place,
									competitor_type = "npc",
									npc_key = label
								})
							end
						end

						-- Update billboard with final results FIRST (before any blocking calls)
						Utils.updateRaceBillboard("Oval", "finished", orderLabels)
						Billboard.ClearCurrentPositions("Oval")

						-- Fire stats update to clients with final results IMMEDIATELY
						Utils.fireRaceStatsUpdate("Oval", {
							status = "finished",
							raceLevel = raceLevel,
							raceNumber = raceNumber,
							currentLap = laps,
							totalLaps = laps,
							positions = orderLabels
						})

						-- Now do the API update and trigger next race (these can block)
						if raceId then
							pcall(function()
								GameApiService.UpdateRace(raceId, {
									actual_results_json = orderLabels,
									race_ended = Utils.getIsoNow(),
									race_finished = true,
								})
							end)

							-- Clear vehicle cache for players whose vehicles finished the race
							for _, result in ipairs(orderLabels) do
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
									TriggerNextRace:Invoke("Oval")
								end)
							end)
						end

					end
				end
			end
		end
	end
	conn = RunService.Heartbeat:Connect(onHeartbeat)

	-- Return the car object
	return car
end

-- Start a few cars
local laps = 5
local topSpeedTrack = 40
finishOrder = {"car1","car2","car3","car4"}
raceId = nil
resultsReported = false

local function isUuid(str)
	if type(str) ~= "string" then return false end
	return str:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end



director:init(waypoints, laps, topSpeedTrack, finishOrder)

startRace.OnInvoke = function(payload)
	if typeof(payload) == "table" then
		laps = payload.laps or laps
		topSpeedTrack = payload.top_speed or payload.topSpeedTrack or payload.topSpeed or topSpeedTrack
		raceId = payload.race_id or payload.raceId or raceId
		raceLevel = payload.level or "Common" -- Get race level for NPC skin selection
		raceNumber = payload.number or payload.race_number or nil

		print("[OvalRace] Starting race with level:", raceLevel, "number:", raceNumber)

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
						color = veh.color or "",
						competitor_type = "vehicle"
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
	end

	director:init(waypoints, laps, topSpeedTrack, finishOrder)
	resultsReported = false

	-- Clear activeCars for new race
	activeCars = {}

	-- Reset race finished flag for new race
	raceFinished = false

	-- Update billboard to show race starting
	Utils.updateRaceBillboard("Oval", "starting")

	-- Fire stats update to clients with starting positions
	Utils.fireRaceStatsUpdate("Oval", {
		status = "starting",
		raceLevel = raceLevel,
		raceNumber = raceNumber,
		currentLap = 1,
		totalLaps = laps,
		positions = finishOrder -- Show starting lineup
	})

	-- Find the existing LeaderCam
	findLeaderCam()

	-- Create PlayerCams for player vehicles in this race
	createPlayerCams(finishOrder)

	task.spawn(function()
		-- Space cars across the track using right vector from WP1->WP2
		local wp1 = waypoints[1]
		local wp2 = waypoints[2]
		local p1 = (wp1.CFrame or wp1.WorldCFrame).Position
		local p2 = (wp2.CFrame or wp2.WorldCFrame).Position
		local fwd0 = (p2 - p1).Magnitude > 1e-3 and (p2 - p1).Unit or Vector3.zAxis
		local right0 = fwd0:Cross(Vector3.new(0,1,0)).Unit
		local spacing = 1.5
		local startDelay = 3.0

		runCar("car1", 1, topSpeedTrack, 160, 220, laps, right0 * (-1.5 * spacing), startDelay)
		runCar("car2", 2, topSpeedTrack, 150, 220, laps, right0 * (-0.5 * spacing), startDelay)
		runCar("car3", 3, topSpeedTrack, 170, 240, laps, right0 * (0.5 * spacing), startDelay)
		runCar("car4", 4, topSpeedTrack, 155, 230, laps, right0 * (1.5 * spacing), startDelay)

		-- Start LeaderCam and PlayerCam tracking after cars are created and registered (with a small delay)
		-- Cancel any existing tasks first
		if leaderCamTask then
			task.cancel(leaderCamTask)
			leaderCamTask = nil
		end
		if leaderCamConnection then
			leaderCamConnection:Disconnect()
			leaderCamConnection = nil
		end
		if playerCamTask then
			task.cancel(playerCamTask)
			playerCamTask = nil
		end
		if playerCamConnection then
			playerCamConnection:Disconnect()
			playerCamConnection = nil
		end

		leaderCamTask = task.spawn(function()
			task.wait(startDelay + 1.0) -- Wait for cars to be created, registered, and start moving
			leaderCamConnection = RunService.Heartbeat:Connect(updateLeaderCam)
		end)

		playerCamTask = task.spawn(function()
			task.wait(startDelay + 1.0) -- Wait for cars to be created, registered, and start moving
			playerCamConnection = RunService.Heartbeat:Connect(updatePlayerCams)
		end)

		-- Start race progress updates after delay
		task.delay(startDelay + 1, function()
			-- Update billboard to show race in progress
			Utils.updateRaceBillboard("Oval", "in_progress")

			-- Fire initial in_progress stats update with starting positions
			Utils.fireRaceStatsUpdate("Oval", {
				status = "in_progress",
				raceLevel = raceLevel,
				raceNumber = raceNumber,
				currentLap = 1,
				totalLaps = laps,
				positions = finishOrder -- Initial lineup
			})

			-- Periodic updates during race
			local updateInterval = 2.0 -- Update every 2 seconds
			local lastUpdate = 0

			local progressConn
			progressConn = RunService.Heartbeat:Connect(function(dt)
				lastUpdate = lastUpdate + dt
				if lastUpdate >= updateInterval then
					lastUpdate = 0

					-- Build positions: finished cars first, then racing cars by current place, DNF at the end
					local sortedPositions = {}
					local usedCarIds = {}
					local usedFinishRanks = {}
					local dnfCars = {}  -- Track DNF cars separately
					local leadingLap = 1

					-- First, add finished cars in finish order (excluding DNFs)
					for _, entry in ipairs(director.actualFinishOrder) do
						local carState = director.carState[entry.carId]
						local finishRank = carState and carState.finishRank
						if finishRank and finishOrder[finishRank] then
							-- Check if this is a DNF entry
							if entry.place == "DNF" then
								-- Store DNF cars separately to add at the end
								table.insert(dnfCars, finishOrder[finishRank])
							else
								-- Add normal finished cars
								table.insert(sortedPositions, finishOrder[finishRank])
							end
							usedCarIds[entry.carId] = true
							usedFinishRanks[finishRank] = true
						end
					end

					-- Then add racing cars by their current position
					local racingPositions = {}
					for carId, state in pairs(director.carState) do
						if not usedCarIds[carId] then
							local place = director:getPlace(carId)
							local finishRank = state.finishRank
							if place and finishRank then
								racingPositions[place] = {data = finishOrder[finishRank] or carId, rank = finishRank}
								-- Track the leading racing car's lap
								if state.lap and state.lap > leadingLap then
									leadingLap = state.lap
								end
							end
						end
					end

					-- Add racing cars in order after finished cars
					for i = 1, #finishOrder do
						if racingPositions[i] then
							table.insert(sortedPositions, racingPositions[i].data)
							usedFinishRanks[racingPositions[i].rank] = true
						end
					end

					-- Fill in any missing positions from finishOrder
					-- Collect missing cars first, then append them ALL at the end
					local missingCars = {}
					for rank = 1, #finishOrder do
						if not usedFinishRanks[rank] then
							table.insert(missingCars, finishOrder[rank])
						end
					end
					-- Append missing cars at the end (position 4 if 3 cars already placed)
					for _, carData in ipairs(missingCars) do
						table.insert(sortedPositions, carData)
					end

					-- Finally, append DNF cars at the very end
					for _, carData in ipairs(dnfCars) do
						table.insert(sortedPositions, carData)
					end

					-- Update billboard with current positions
					Utils.updateRaceBillboard("Oval", "in_progress", sortedPositions)
					Billboard.UpdateCurrentPositions("Oval", sortedPositions)

					-- Fire stats update to clients
					Utils.fireRaceStatsUpdate("Oval", {
						status = "in_progress",
						raceLevel = raceLevel,
						raceNumber = raceNumber,
						currentLap = leadingLap,
						totalLaps = laps,
						positions = sortedPositions
					})
				end

				-- Stop updates when race is finished
				if resultsReported then
					if progressConn then
						progressConn:Disconnect()
					end
				end
			end)
		end)
	end)
end