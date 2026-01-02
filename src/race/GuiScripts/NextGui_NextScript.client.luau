local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local nextEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowNext")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CompletedGui = playerGui:WaitForChild("NextGui")
local fetchQueueFunc = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchTrackQueue")
local getVehicleNameRF = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("GetVehicleName")
local fetchVehicles = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchVehicles")
local joinRace = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("JoinRace")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ReplicaUtils"))
local RaceSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RaceSoundUtils"))

local template = Utils.findDescendantByName(CompletedGui, "Template")
local window = Utils.findDescendantByName(CompletedGui, "Window")
local scrollingFrame = Utils.findDescendantByName(window, "RaceFrame")
template.Visible = false
local vehicleFrame = Utils.findDescendantByName(window, "VehicleFrame")
local loading = false
local vehicleTemplate = Utils.findDescendantByName(vehicleFrame, "VehicleTemplate")
local vehicles = fetchVehicles:InvokeServer()
local backButton = Utils.findDescendantByName(window, "Back")
local loadItem
local dialog = Utils.findDescendantByName(vehicleFrame, "Dialog")
-- Note: Dialog is used instead of NoCars when no vehicles are available

-- Track current track for refreshing after race entry
local currentTrack = nil

-- Forward declaration for showNext (defined later in the file)
local showNext

scrollingFrame.Visible = true
backButton.MouseButton1Click:Connect(function()
	RaceSoundUtils.PlayButtonPressed()
	vehicleFrame.Visible = false
	scrollingFrame.Visible = true
	backButton.Visible = false
end)


local function vehicleEnterRace(race, vehicle)
	RaceSoundUtils.PlayRev()
	joinRace:InvokeServer(race.id, vehicle.id)
	vehicleFrame.Visible = false
	scrollingFrame.Visible = true
	backButton.Visible = false

	-- Refresh vehicles
	vehicles = fetchVehicles:InvokeServer()

	-- Clear old race buttons and refetch queue to get updated race data
	if currentTrack then
		for _, child in ipairs(scrollingFrame:GetChildren()) do
			if child:IsA("TextButton") and child ~= template then
				child:Destroy()
			end
		end
		showNext(currentTrack)
	end
end

-- Helper to display vehicle thumbnail in a ViewportFrame
local function setupVehicleThumbnail(viewportFrame, vehicle)
	if not viewportFrame then return end

	-- Clear any existing content
	for _, child in ipairs(viewportFrame:GetChildren()) do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	-- Try to find the vehicle model template by skin name
	local skinName = vehicle.skin or "Truck_Blue"
	local carsFolder = game.ReplicatedStorage:FindFirstChild("Cars")
	if not carsFolder then
		warn("[NextScript] Cars folder not found in ReplicatedStorage")
		return
	end

	local carTemplate = carsFolder:FindFirstChild(skinName)
	if not carTemplate then
		-- Try default if skin not found
		carTemplate = carsFolder:FindFirstChild("Truck_Blue")
		if not carTemplate then
			warn("[NextScript] Could not find car template for:", skinName)
			return
		end
	end

	-- Clone the car model into the viewport
	local carClone = carTemplate:Clone()
	carClone.Parent = viewportFrame

	-- Create a camera for the viewport
	local camera = Instance.new("Camera")
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera

	-- Position the camera to view the car
	-- Get the car's bounding box to frame it properly
	local cf, size = carClone:GetBoundingBox()
	local maxSize = math.max(size.X, size.Y, size.Z)

	-- Position camera at an angle looking at the car (zoomed in 2x)
	-- Negative X and Z to view from the front/side (rotated 180 from original)
	local cameraDistance = maxSize * 0.9
	local cameraOffset = Vector3.new(-cameraDistance * 0.7, cameraDistance * 0.4, -cameraDistance * 0.7)
	camera.CFrame = CFrame.lookAt(cf.Position + cameraOffset, cf.Position)
end


loadItem = function(item, entry)
	local name = entry.name
	local level = entry.level
	Utils.switchColorIcon(item, level)
	local nameFrame = Utils.findDescendantByName(item, "Name")
	local itemLabel = Utils.findDescendantByName(nameFrame, "ItemLabel")
	local itemLabelStroke = Utils.findDescendantByName(nameFrame, "ItemLabelStroke")
	item.Name = name
	itemLabel.Text = name
	itemLabelStroke.Text = name
	item.Visible = true
	return item
end


local function switchRace(race)
	print("[NextScript] switchRace called for race level:", race.level, "race id:", race.id)

	-- Clear existing vehicle frames (but keep VehicleTemplate, NoCars, and Dialog)
	for _, child in ipairs(vehicleFrame:GetChildren()) do
		if child:IsA("Frame") and child.Visible and child.Name ~= "Dialog" then
			child:Destroy()
		end
	end

	backButton.Visible = true
	scrollingFrame.Visible = false
	vehicleFrame.Visible = true
	dialog.Visible = true -- Show dialog initially, hide if vehicles are found

	-- Check if player already has a vehicle in this race
	local playerVehicleIds = {}
	for _, vehicle in ipairs(vehicles) do
		playerVehicleIds[vehicle.id] = true
	end

	-- Check race queue slots (vehicle1-vehicle4)
	local alreadyEntered = false
	for _, slotKey in ipairs({"vehicle1", "vehicle2", "vehicle3", "vehicle4"}) do
		local vehicleId = race[slotKey]
		if vehicleId and playerVehicleIds[vehicleId] then
			alreadyEntered = true
			print("[NextScript] Player already entered race with vehicle:", vehicleId)
			break
		end
	end

	-- If player already entered, show dialog and return early
	if alreadyEntered then
		dialog.Visible = true
		print("[NextScript] Player already entered this race - showing Dialog")
		return
	end

	local availableCount = 0
	print("[NextScript] Checking", #vehicles, "vehicles for race level:", race.level)

	for _, vehicle in ipairs(vehicles) do
		print("[NextScript] Vehicle:", vehicle.name, "level:", vehicle.level, "racing:", vehicle.racing)
		if not vehicle.racing and vehicle.level == race.level then
			availableCount = availableCount + 1
			dialog.Visible = false
			local vehicleClone = vehicleTemplate:Clone()
			vehicleClone.Visible = true
			loadItem(vehicleClone, vehicle)
			vehicleClone.Name = vehicle.id
			vehicleClone.Parent = vehicleFrame

			-- Set up the vehicle thumbnail in the Image viewport
			local imageViewport = Utils.findDescendantByName(vehicleClone, "Image")
			setupVehicleThumbnail(imageViewport, vehicle)

			local raceButton = Utils.findDescendantByName(vehicleClone, "TextButton")
			raceButton.MouseButton1Click:Connect(function()
				vehicleEnterRace(race, vehicle)
			end)
		end
	end

	print("[NextScript] Found", availableCount, "available vehicles for race level:", race.level)

	-- If no vehicles available, show Dialog frame (not NoCars)
	if availableCount == 0 then
		dialog.Visible = true
		print("[NextScript] Showing Dialog frame - no vehicles available for this race level")
	end
end


showNext = function(track)
	print("[NextScript] showNext called for track:", track)

	if loading then
		print("[NextScript] Already loading, skipping")
		return
	end
	loading = true

	-- Store current track for refreshing after race entry
	currentTrack = track

	print("[NextScript] Fetching track queue...")
	local trackQueue = fetchQueueFunc:InvokeServer(track) or {}
	print("[NextScript] Received", #trackQueue, "races in queue for track:", track)

	local shownCount = 0
	local skippedFinished = 0
	local skippedReady = 0

	for i, each in ipairs(trackQueue) do
		print("[NextScript] Race", i, "- number:", each.number, "level:", each.level, "race_finished:", each.race_finished, "ready:", each.ready)

		if each.race_finished then
			skippedFinished = skippedFinished + 1
		elseif each.ready then
			skippedReady = skippedReady + 1
		end

		if not each.race_finished and not each.ready then
			shownCount = shownCount + 1
			local clone = template:Clone()

			-- compute level safely
			local level = each.level or "common"
			local levelLower = string.lower(level)
			local levelDisplay = string.upper(string.sub(levelLower, 1, 1)) .. string.sub(levelLower, 2)

			-- shorten long labels to avoid spacing issues
			if levelLower == "legendary" then
				levelDisplay = "Leg"
			elseif levelLower == "common" then
				levelDisplay = "Com"
			end

			-- Title label text + color
			local titleLabel = Utils.findDescendantByName(clone, "TitleLabel")
			if titleLabel then
				titleLabel.Text = levelDisplay .. " #" .. (each.number or "?")
				if levelLower == "common" then
					titleLabel.TextColor3 = Color3.fromRGB(6, 123, 202)
				elseif levelLower == "rare" then
					titleLabel.TextColor3 = Color3.fromRGB(79, 213, 2)
				elseif levelLower == "epic" then
					titleLabel.TextColor3 = Color3.fromRGB(186, 50, 226)
				elseif levelLower == "legendary" then
					titleLabel.TextColor3 = Color3.fromRGB(255, 219, 49)
				else
					titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
			end

			-- Build results list (in order vehicle1..vehicle4)
			local sortedResults = {}
			for _, key in ipairs({"vehicle1", "vehicle2", "vehicle3", "vehicle4"}) do
				local id = each[key]
				if id then
					local ok, nameOrErr = pcall(function()
						return getVehicleNameRF:InvokeServer(id)
					end)
					table.insert(sortedResults, ok and nameOrErr or "Unknown")
				end
			end

			-- Fill position labels (Drag shows only First/Second)
			local positions = {"First", "Second", "Third", "Fourth"}
			for posIndex, posName in ipairs(positions) do
				if track ~= "Drag" or posName == "First" or posName == "Second" then
					local posLabel = Utils.findDescendantByName(clone, posName .. "Label")
					if posLabel and posLabel:IsA("TextLabel") then
						local result = sortedResults[posIndex]
						posLabel.Text = result or "Open"
					end
				end
			end
			local prizeLabel = Utils.findDescendantByName(clone, "PrizeLabel")
			prizeLabel.TextColor3 = Color3.fromRGB(0, 200, 0)
			prizeLabel.Text = "Entry $" .. each.entry_fee
			clone.MouseButton1Click:Connect(function()
				RaceSoundUtils.PlayButtonPressed()
				switchRace(each)
			end)
			clone.Parent = scrollingFrame
			clone.Visible = true
		end
	end

	print("[NextScript] Summary - Shown:", shownCount, "Skipped (finished):", skippedFinished, "Skipped (ready):", skippedReady)

	if shownCount == 0 then
		print("[NextScript] WARNING: No races shown! Total in queue:", #trackQueue)
	end

	loading = false
end


nextEvent.OnClientEvent:Connect(function(show, track)
	print("[NextScript] Event received - show:", show, "track:", track)
	window.Visible = show == true
	if window.Visible then
		print("[NextScript] Window visible, resetting view state and clearing old rows")

		-- Reset view state to show race list (not vehicle selection)
		vehicleFrame.Visible = false
		scrollingFrame.Visible = true
		backButton.Visible = false

		-- Refresh vehicles to get latest data
		vehicles = fetchVehicles:InvokeServer()
		print("[NextScript] Refreshed vehicles, now have", #vehicles, "vehicles")

		-- clear old rows first
		local clearedCount = 0
		for _, child in ipairs(scrollingFrame:GetChildren()) do
			if child:IsA("TextButton") and child ~= template then
				child:Destroy()
				clearedCount = clearedCount + 1
			end
		end
		print("[NextScript] Cleared", clearedCount, "old rows")
		showNext(track)
	else
		print("[NextScript] Window hidden")
	end
end)