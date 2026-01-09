-- NextGui_NextScript.client.luau
-- Displays player vehicles by level with per-track race joining
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- RemoteEvents and RemoteFunctions
local nextEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowNext")
local fetchVehicles = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchVehicles")
local joinRace = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("JoinRace")
local getVehicleTrackAssignments = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("GetVehicleTrackAssignments")
local joinAllTracksRemote = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("JoinAllTracks")

-- Modules
local Utils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ReplicaUtils"))
local RaceSoundUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RaceSoundUtils"))

-- Player references
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local NextGui = playerGui:WaitForChild("NextGui")

-- GUI references
local window = Utils.findDescendantByName(NextGui, "Window")
local content = Utils.findDescendantByName(window, "Content")
local header = Utils.findDescendantByName(content, "Header")
local body = Utils.findDescendantByName(content, "Body")
local headerLine = Utils.findDescendantByName(header, "Line")
local scrollingFrame = Utils.findDescendantByName(body, "ScrollingFrame")

-- Level selector buttons
local leftArrow = Utils.findDescendantByName(headerLine, "Left")
local rightArrow = Utils.findDescendantByName(headerLine, "Right")
local levelButton = Utils.findDescendantByName(headerLine, "Race")
local levelLabel = Utils.findDescendantByName(levelButton, "TextLabel")

-- Templates
local vehicleTemplate = Utils.findDescendantByName(scrollingFrame, "VehicleTemplate")
local noVehicles = Utils.findDescendantByName(scrollingFrame, "NoVehicles")

-- Hide templates initially
if vehicleTemplate then vehicleTemplate.Visible = false end
if noVehicles then noVehicles.Visible = false end

-- State
local currentLevel = "Common"
local levels = {"Common", "Rare", "Epic", "Legendary"}
local levelIndex = 1
local tracks = {"Oval", "Road", "Drag", "Dirt"}
local vehicles = {}
local isRefreshing = false

-- Color scheme from Utils
local levelColors = {
	Common = Color3.fromRGB(6, 123, 202),
	Rare = Color3.fromRGB(79, 213, 2),
	Epic = Color3.fromRGB(186, 50, 226),
	Legendary = Color3.fromRGB(255, 219, 49)
}

-- Entry fees by level (Common is free, others calculated from base)
-- These are approximate - actual fees come from backend
local entryFees = {
	Common = 0,
	Rare = 100,
	Epic = 150,
	Legendary = 200
}

-- Green color for "Free" and price text
local greenColor = Color3.fromRGB(0, 200, 0)


-- Update level display in header
local function updateLevelDisplay()
	if levelLabel then
		levelLabel.Text = currentLevel
		levelLabel.TextColor3 = levelColors[currentLevel] or Color3.fromRGB(255, 255, 255)
	end
end


-- Setup vehicle thumbnail in a ViewportFrame
local function setupVehicleThumbnail(viewportFrame, vehicle)
	if not viewportFrame then return end

	-- Clear existing content
	for _, child in ipairs(viewportFrame:GetChildren()) do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	-- Get car model from ReplicatedStorage.Cars
	local skinName = vehicle.skin or "Truck_Blue"
	local carsFolder = ReplicatedStorage:FindFirstChild("Cars")
	if not carsFolder then
		warn("[NextScript] Cars folder not found in ReplicatedStorage")
		return
	end

	local carTemplate = carsFolder:FindFirstChild(skinName)
	if not carTemplate then
		carTemplate = carsFolder:FindFirstChild("Truck_Blue")
		if not carTemplate then
			warn("[NextScript] Could not find car template for:", skinName)
			return
		end
	end

	-- Clone the car model into the viewport
	local carClone = carTemplate:Clone()
	carClone.Parent = viewportFrame

	-- Apply custom color if vehicle has one
	if vehicle.color then
		Utils.applyViewportColor(carClone, vehicle.color)
	end

	-- Create camera and position it
	local camera = Instance.new("Camera")
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera

	-- Calculate aspect ratio adjustment for tall viewports
	-- If viewport is taller than wide, we need to increase FOV to show more horizontally
	local viewportSize = viewportFrame.AbsoluteSize
	local aspectRatio = viewportSize.X / math.max(viewportSize.Y, 1)
	local fovMultiplier = 1
	if aspectRatio < 1 then
		-- Viewport is taller than wide - increase FOV to compensate
		fovMultiplier = 1 / aspectRatio
	end

	-- Check for ThumbnailCFrame and ThumbnailFOV values
	local thumbnailCFrame = carClone:FindFirstChild("ThumbnailCFrame")
	local thumbnailFOV = carClone:FindFirstChild("ThumbnailFOV")

	if thumbnailCFrame and thumbnailCFrame:IsA("CFrameValue") then
		camera.CFrame = thumbnailCFrame.Value
		local baseFOV = 10
		if thumbnailFOV and thumbnailFOV:IsA("NumberValue") then
			baseFOV = thumbnailFOV.Value
		end
		-- Apply aspect ratio correction to FOV
		camera.FieldOfView = math.min(baseFOV * fovMultiplier, 70)
	else
		-- Fallback: position camera based on bounding box
		local cf, size = carClone:GetBoundingBox()
		local maxSize = math.max(size.X, size.Y, size.Z)
		local cameraDistance = maxSize * 0.9
		local cameraOffset = Vector3.new(-cameraDistance * 0.7, cameraDistance * 0.4, -cameraDistance * 0.7)
		camera.CFrame = CFrame.lookAt(cf.Position + cameraOffset, cf.Position)
		-- Apply aspect ratio correction to FOV
		camera.FieldOfView = math.min(40 * fovMultiplier, 70)
	end
end


-- Helper to show spinner on a button (creates spinner dynamically like teleport dialog)
local function showButtonSpinner(button, show)
	if not button then return end

	local textLabel = Utils.findDescendantByName(button, "TextLabel")
	local existingSpinner = button:FindFirstChild("SpinnerFrame")

	if show then
		button.Active = false
		if textLabel then textLabel.Visible = false end

		-- Create spinner if it doesn't exist
		if not existingSpinner then
			local spinnerFrame = Instance.new("Frame")
			spinnerFrame.Name = "SpinnerFrame"
			spinnerFrame.Size = UDim2.new(1, 0, 1, 0)
			spinnerFrame.Position = UDim2.new(0, 0, 0, 0)
			spinnerFrame.BackgroundTransparency = 1
			spinnerFrame.BorderSizePixel = 0
			spinnerFrame.ZIndex = button.ZIndex + 1

			local spinnerImage = Instance.new("ImageLabel")
			spinnerImage.Name = "SpinnerImage"
			spinnerImage.Size = UDim2.new(0, 24, 0, 24)
			spinnerImage.Position = UDim2.new(0.5, -12, 0.5, -12)
			spinnerImage.BackgroundTransparency = 1
			spinnerImage.Image = "rbxassetid://101716378951252"
			spinnerImage.ZIndex = spinnerFrame.ZIndex + 1
			spinnerImage.Parent = spinnerFrame

			-- Create rotation tween
			local rotationTween = TweenService:Create(
				spinnerImage,
				TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
				{Rotation = 360}
			)

			spinnerFrame.Parent = button
			rotationTween:Play()
		end
	else
		button.Active = true
		if textLabel then textLabel.Visible = true end

		-- Remove spinner if it exists
		if existingSpinner then
			existingSpinner:Destroy()
		end
	end
end


-- Forward declaration for refreshDisplay
local refreshDisplay


-- Join a vehicle to a specific track
local function joinVehicleToTrack(vehicle, track, button)
	RaceSoundUtils.PlayRev()

	-- Show spinner
	showButtonSpinner(button, true)

	-- Spawn to not block UI
	task.spawn(function()
		local result = joinRace:InvokeServer(vehicle.id, track, currentLevel)

		if result and result.error then
			warn("[NextScript] Failed to join race:", result.error)
		end

		-- Refresh vehicles and display
		vehicles = fetchVehicles:InvokeServer() or {}
		refreshDisplay()
	end)
end


-- Join a vehicle to all tracks using the batch endpoint
local function joinVehicleToAllTracks(vehicle, button)
	RaceSoundUtils.PlayRev()

	-- Show spinner
	showButtonSpinner(button, true)

	-- Spawn to not block UI
	task.spawn(function()
		local result = joinAllTracksRemote:InvokeServer(vehicle.id, currentLevel)

		if result and result.error then
			warn("[NextScript] Failed to join all tracks:", result.error)
		end

		-- Refresh vehicles and display
		vehicles = fetchVehicles:InvokeServer() or {}
		refreshDisplay()
	end)
end


-- Format button text with price in green
local function formatPriceText(baseText, price)
	if price == 0 then
		return baseText .. " - Free"
	else
		return baseText .. " - $" .. tostring(price)
	end
end


-- Create a track row from the Template
local function createTrackRow(racesFrame, vehicle, track, isJoined, entryFee)
	local template = Utils.findDescendantByName(racesFrame, "Template")
	if not template then
		warn("[NextScript] Template not found in Races frame")
		return nil
	end

	local row = template:Clone()
	row.Name = track
	row.Visible = true

	-- Set track name with level color
	local trackLabel = Utils.findDescendantByName(row, "Track")
	if trackLabel then
		trackLabel.Text = track
		trackLabel.TextColor3 = levelColors[currentLevel] or Color3.fromRGB(255, 255, 255)
	end

	-- Get button references
	local joinedButton = Utils.findDescendantByName(row, "Joined")
	local joinButton = Utils.findDescendantByName(row, "Join")

	if isJoined then
		-- Show Joined, hide Join
		if joinedButton then joinedButton.Visible = true end
		if joinButton then joinButton.Visible = false end
	else
		-- Show Join, hide Joined
		if joinedButton then joinedButton.Visible = false end
		if joinButton then
			joinButton.Visible = true

			-- Format join button text
			local joinLabel = Utils.findDescendantByName(joinButton, "TextLabel")
			if joinLabel then
				joinLabel.Text = formatPriceText("Join", entryFee)
			end

			-- Connect click handler
			joinButton.MouseButton1Click:Connect(function()
				joinVehicleToTrack(vehicle, track, joinButton)
			end)
		end
	end

	row.Parent = racesFrame
	return row
end


-- Load a vehicle into the template
local function loadVehicle(vehicle, trackAssignments)
	if not vehicleTemplate then
		warn("[NextScript] VehicleTemplate not found")
		return nil
	end

	local clone = vehicleTemplate:Clone()
	clone.Name = vehicle.id or vehicle.name
	clone.Visible = true

	-- Find Content frame
	local contentFrame = Utils.findDescendantByName(clone, "Content")
	if not contentFrame then
		contentFrame = clone -- Fallback if no Content frame
	end

	-- Set vehicle name with level color
	local topFrame = Utils.findDescendantByName(contentFrame, "Top")
	if topFrame then
		local nameLabel = Utils.findDescendantByName(topFrame, "Name")
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = vehicle.name or "Unknown"
			nameLabel.TextColor3 = levelColors[currentLevel] or Color3.fromRGB(255, 255, 255)
		elseif nameLabel then
			local textLabel = Utils.findDescendantByName(nameLabel, "TextLabel")
			if textLabel then
				textLabel.Text = vehicle.name or "Unknown"
				textLabel.TextColor3 = levelColors[currentLevel] or Color3.fromRGB(255, 255, 255)
			end
		end
	end

	-- Setup thumbnail
	local thumbnail = Utils.findDescendantByName(contentFrame, "Thumbnail")
	if thumbnail then
		setupVehicleThumbnail(thumbnail, vehicle)
	end

	-- Get entry fee for current level
	local entryFee = entryFees[currentLevel] or 0

	-- Setup "Join All" button - search entire clone for "JoinAll"
	local joinAllButton = Utils.findDescendantByName(clone, "JoinAll")

	if joinAllButton then
		-- Ensure button is active and interactable
		joinAllButton.Active = true
		if joinAllButton:IsA("GuiButton") then
			joinAllButton.AutoButtonColor = true
		end

		local joinAllLabel = Utils.findDescendantByName(joinAllButton, "TextLabel")
		if joinAllLabel then
			joinAllLabel.Text = "Join All"
		end

		joinAllButton.MouseButton1Click:Connect(function()
			joinVehicleToAllTracks(vehicle, joinAllButton)
		end)
	else
		warn("[NextScript] JoinAll button not found in vehicle template")
	end

	-- Setup track rows
	local racesFrame = Utils.findDescendantByName(contentFrame, "Races")
	if racesFrame then
		-- Hide the template
		local raceTemplate = Utils.findDescendantByName(racesFrame, "Template")
		if raceTemplate then
			raceTemplate.Visible = false
		end

		-- Create a row for each track
		for _, track in ipairs(tracks) do
			local isJoined = trackAssignments and trackAssignments[track] ~= nil
			createTrackRow(racesFrame, vehicle, track, isJoined, entryFee)
		end
	end

	clone.Parent = scrollingFrame
	return clone
end


-- Main refresh function
function refreshDisplay()
	if not scrollingFrame then
		warn("[NextScript] ScrollingFrame not found")
		return
	end

	-- Clear existing vehicle clones (keep templates)
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= vehicleTemplate and child ~= noVehicles then
			child:Destroy()
		end
	end

	-- Update level display in header
	updateLevelDisplay()

	-- Filter vehicles by current level
	local levelVehicles = {}
	for _, vehicle in ipairs(vehicles) do
		if vehicle.level == currentLevel then
			table.insert(levelVehicles, vehicle)
		end
	end

	-- Show NoVehicles or populate list
	if #levelVehicles == 0 then
		if noVehicles then
			noVehicles.Visible = true
		end
	else
		if noVehicles then
			noVehicles.Visible = false
		end

		for _, vehicle in ipairs(levelVehicles) do
			-- Get track assignments for this vehicle
			local assignments = getVehicleTrackAssignments:InvokeServer(vehicle.id)
			local assignmentsMap = assignments and assignments.assignments or {}
			loadVehicle(vehicle, assignmentsMap)
		end

		-- Adjust canvas size after loading
		RunService.RenderStepped:Wait()
		local listLayout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
		local gridLayout = scrollingFrame:FindFirstChildOfClass("UIGridLayout")
		local layout = listLayout or gridLayout

		if layout then
			local padding = scrollingFrame:FindFirstChildOfClass("UIPadding")
			local totalHeight = layout.AbsoluteContentSize.Y
			if padding then
				totalHeight = totalHeight + padding.PaddingTop.Offset + padding.PaddingBottom.Offset
			end
			scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
		end
	end
end


-- Cycle level left
local function cycleLeft()
	RaceSoundUtils.PlayButtonPressed()
	levelIndex = levelIndex - 1
	if levelIndex < 1 then
		levelIndex = #levels
	end
	currentLevel = levels[levelIndex]
	refreshDisplay()
end


-- Cycle level right
local function cycleRight()
	RaceSoundUtils.PlayButtonPressed()
	levelIndex = levelIndex + 1
	if levelIndex > #levels then
		levelIndex = 1
	end
	currentLevel = levels[levelIndex]
	refreshDisplay()
end


-- Connect level selector buttons
if leftArrow then
	leftArrow.MouseButton1Click:Connect(cycleLeft)
end

if rightArrow then
	rightArrow.MouseButton1Click:Connect(cycleRight)
end


-- Main event handler
-- Receives: show (boolean), level (string, optional)
nextEvent.OnClientEvent:Connect(function(show, level)
	if window then
		window.Visible = show == true
	end

	if show then
		-- Set level if provided
		if level and type(level) == "string" then
			for i, l in ipairs(levels) do
				if l == level then
					currentLevel = level
					levelIndex = i
					break
				end
			end
		end

		-- Refresh vehicles from server
		vehicles = fetchVehicles:InvokeServer() or {}

		-- Refresh display
		refreshDisplay()
	end
end)
