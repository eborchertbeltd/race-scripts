--#RACE
-- TeleportMenu for Race place
-- Buttons: Race (teleport to closest JoinRace trigger), Bet (closest Bet trigger), Garages (show teleport dialog), Inventory
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RaceSoundUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RaceSoundUtils"))

-- BindableEvent for opening Inventory (create if it doesn't exist)
local bindableEventsFolder = ReplicatedStorage:FindFirstChild("BindableEvents")
if not bindableEventsFolder then
	bindableEventsFolder = Instance.new("Folder")
	bindableEventsFolder.Name = "BindableEvents"
	bindableEventsFolder.Parent = ReplicatedStorage
end

local OpenInventoryEvent = bindableEventsFolder:FindFirstChild("OpenInventory")
if not OpenInventoryEvent then
	OpenInventoryEvent = Instance.new("BindableEvent")
	OpenInventoryEvent.Name = "OpenInventory"
	OpenInventoryEvent.Parent = bindableEventsFolder
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- GUI references
local baseGui = playerGui:WaitForChild("BaseGui")
local canvas = baseGui:WaitForChild("Canvas")
local teleportFrame = canvas:WaitForChild("Teleport")

-- RaceGui reference for closing when teleporting
local raceGui = playerGui:FindFirstChild("RaceGui")
local raceGuiMainFrame = raceGui and raceGui:FindFirstChild("Frame")

-- Close RaceGui and return camera to player before teleporting
local function closeRaceGuiIfOpen()
	-- Hide the RaceGui frame
	if raceGuiMainFrame then
		raceGuiMainFrame.Visible = false
	end
	-- Return camera to player view using global controller
	if _G.CameraController and _G.CameraController.returnToPlayer then
		_G.CameraController.returnToPlayer()
	end
end

-- Buttons
local showTeleportBtn = teleportFrame:WaitForChild("ShowTeleport")
local raceBtn = teleportFrame:WaitForChild("Race")
local betBtn = teleportFrame:WaitForChild("Bet")
local garagesBtn = teleportFrame:WaitForChild("Garages")

-- Existing teleport dialog for going back to Garage
local teleportDialog = playerGui:WaitForChild("Teleport"):WaitForChild("Dialog")

-- Menu state
local menuVisible = false
local hideTimer = nil
local AUTO_HIDE_DELAY = 3

-- Sub-buttons to show/hide (teleport options)
local subButtons = {raceBtn, betBtn, garagesBtn}

-- Inventory button reference (will toggle opposite of subButtons)
local inventoryBtn = teleportFrame:FindFirstChild("InventoryButton")

-- Initialize: hide sub-buttons, show inventory button
for _, btn in ipairs(subButtons) do
	btn.Visible = false
end
if inventoryBtn then
	inventoryBtn.Visible = true
end

-- Cancel any pending hide timer
local function cancelHideTimer()
	if hideTimer then
		pcall(function()
			task.cancel(hideTimer)
		end)
		hideTimer = nil
	end
end

-- Hide the sub-buttons (and show inventory button)
local function hideMenu()
	cancelHideTimer()
	menuVisible = false
	for _, btn in ipairs(subButtons) do
		btn.Visible = false
	end
	-- Show inventory button when teleport options are hidden
	if inventoryBtn then
		inventoryBtn.Visible = true
	end
end

-- Show the sub-buttons with auto-hide timer (and hide inventory button)
local function showMenu()
	cancelHideTimer()
	menuVisible = true
	for _, btn in ipairs(subButtons) do
		btn.Visible = true
	end
	-- Hide inventory button when teleport options are shown
	if inventoryBtn then
		inventoryBtn.Visible = false
	end

	-- Start auto-hide timer
	hideTimer = task.delay(AUTO_HIDE_DELAY, function()
		hideMenu()
	end)
end

-- Toggle menu visibility
local function toggleMenu()
	RaceSoundUtils.PlayButtonPressed()
	if menuVisible then
		hideMenu()
	else
		showMenu()
	end
end

-- Teleport player to a CFrame
local function teleportTo(cframe)
	local character = player.Character
	if character then
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			humanoidRootPart.CFrame = cframe
		end
	end
end

-- Get player's current position
local function getPlayerPosition()
	local character = player.Character
	if not character then return nil end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart then
		return humanoidRootPart.Position
	end

	local head = character:FindFirstChild("Head")
	if head then
		return head.Position
	end

	return nil
end

-- Find the closest GuiTrigger in a folder
-- folderPath: the parent folder (e.g., workspace.JoinRace or workspace.Bet)
-- Returns: CFrame of the closest trigger (slightly above it)
local function findClosestGuiTrigger(folder)
	local playerPos = getPlayerPosition()
	if not playerPos then
		return nil
	end

	local closestTrigger = nil
	local closestDistance = math.huge

	-- Iterate through all children of the folder
	for _, child in ipairs(folder:GetChildren()) do
		local guiTrigger = child:FindFirstChild("GuiTrigger")
		if guiTrigger and guiTrigger:IsA("BasePart") then
			local triggerPos = guiTrigger.Position
			local distance = (playerPos - triggerPos).Magnitude
			if distance < closestDistance then
				closestDistance = distance
				closestTrigger = guiTrigger
			end
		end
	end

	if closestTrigger then
		-- Return position slightly above the trigger center
		local triggerPos = closestTrigger.Position + Vector3.new(0, 3, 0)
		return CFrame.new(triggerPos)
	end

	return nil
end

-- Button handlers
showTeleportBtn.MouseButton1Click:Connect(function()
	toggleMenu()
end)

raceBtn.MouseButton1Click:Connect(function()
	RaceSoundUtils.PlayButtonPressed()
	hideMenu()

	-- Find closest JoinRace trigger
	local joinRaceFolder = workspace:FindFirstChild("JoinRace")
	if joinRaceFolder then
		local targetCFrame = findClosestGuiTrigger(joinRaceFolder)
		if targetCFrame then
			closeRaceGuiIfOpen()
			teleportTo(targetCFrame)
		else
			warn("[TeleportMenu] No GuiTrigger found in JoinRace folder")
		end
	else
		warn("[TeleportMenu] JoinRace folder not found in workspace")
	end
end)

betBtn.MouseButton1Click:Connect(function()
	RaceSoundUtils.PlayButtonPressed()
	hideMenu()

	-- Find closest Bet trigger
	local betFolder = workspace:FindFirstChild("Bet")
	if betFolder then
		local targetCFrame = findClosestGuiTrigger(betFolder)
		if targetCFrame then
			closeRaceGuiIfOpen()
			teleportTo(targetCFrame)
		else
			warn("[TeleportMenu] No GuiTrigger found in Bet folder")
		end
	else
		warn("[TeleportMenu] Bet folder not found in workspace")
	end
end)

garagesBtn.MouseButton1Click:Connect(function()
	RaceSoundUtils.PlayButtonPressed()
	hideMenu()
	closeRaceGuiIfOpen()
	-- Show the existing teleport dialog for going back to Garage
	teleportDialog.Visible = true
end)

-- Inventory button click handler
if inventoryBtn then
	inventoryBtn.MouseButton1Click:Connect(function()
		RaceSoundUtils.PlayButtonPressed()
		hideMenu()
		OpenInventoryEvent:Fire()
	end)
end

print("[TeleportMenu] Race place teleport menu initialized")
