local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- GUI references
local baseGui = playerGui:WaitForChild("BaseGui")
local canvas = baseGui:WaitForChild("Canvas")
local teleportFrame = canvas:WaitForChild("Teleport")

-- Buttons
local showTeleportBtn = teleportFrame:WaitForChild("ShowTeleport")
local myGarageBtn = teleportFrame:WaitForChild("MyGarage")
local vendingBtn = teleportFrame:WaitForChild("Vending")
local skinsBtn = teleportFrame:WaitForChild("Skins")
local racesBtn = teleportFrame:WaitForChild("Races")

-- Existing teleport dialog for Races
local teleportDialog = playerGui:WaitForChild("Teleport"):WaitForChild("Dialog")
local ShowTeleportEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowTeleport")

-- Teleport destinations (position, rotation)
local SKINS_CFRAME = CFrame.new(8.1, 3.5, -20) * CFrame.Angles(0, 0, 0)
local VENDING_CFRAME = CFrame.new(-11.198, 1.8, -175.743) * CFrame.Angles(0, 0, 0)

-- Menu state
local menuVisible = false
local hideTimer = nil
local AUTO_HIDE_DELAY = 3

-- Sub-buttons to show/hide
local subButtons = {myGarageBtn, vendingBtn, skinsBtn, racesBtn}

-- Initialize: hide sub-buttons
for _, btn in ipairs(subButtons) do
	btn.Visible = false
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

-- Hide the sub-buttons
local function hideMenu()
	cancelHideTimer()
	menuVisible = false
	for _, btn in ipairs(subButtons) do
		btn.Visible = false
	end
end

-- Show the sub-buttons with auto-hide timer
local function showMenu()
	cancelHideTimer()
	menuVisible = true
	for _, btn in ipairs(subButtons) do
		btn.Visible = true
	end

	-- Start auto-hide timer
	hideTimer = task.delay(AUTO_HIDE_DELAY, function()
		hideMenu()
	end)
end

-- Toggle menu visibility
local function toggleMenu()
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

-- Get player's garage center (using SPad position + offset)
local function getMyGarageCFrame()
	local garageName = player:GetAttribute("AssignedGarage")
	if not garageName then
		warn("[TeleportMenu] Player has no AssignedGarage attribute")
		return nil
	end

	local garagesFolder = workspace:FindFirstChild("Garages")
	if not garagesFolder then
		warn("[TeleportMenu] Garages folder not found in workspace")
		return nil
	end

	local garage = garagesFolder:FindFirstChild(garageName)
	if not garage then
		warn("[TeleportMenu] Garage not found:", garageName)
		return nil
	end

	local sPad = garage:FindFirstChild("SPad")
	if not sPad then
		warn("[TeleportMenu] SPad not found in garage:", garageName)
		return nil
	end

	-- Get SPad position and add height offset so player spawns above it
	local sPadPart = sPad:IsA("BasePart") and sPad or sPad:FindFirstChildWhichIsA("BasePart")
	if sPadPart then
		local pos = sPadPart.Position + Vector3.new(0, 3, 0) -- 3 studs above SPad
		return CFrame.new(pos)
	end

	warn("[TeleportMenu] Could not find BasePart in SPad")
	return nil
end

-- Button handlers
showTeleportBtn.MouseButton1Click:Connect(function()
	toggleMenu()
end)

myGarageBtn.MouseButton1Click:Connect(function()
	hideMenu()
	local garageCFrame = getMyGarageCFrame()
	if garageCFrame then
		teleportTo(garageCFrame)
	end
end)

vendingBtn.MouseButton1Click:Connect(function()
	hideMenu()
	teleportTo(VENDING_CFRAME)
end)

skinsBtn.MouseButton1Click:Connect(function()
	hideMenu()
	teleportTo(SKINS_CFRAME)
end)

racesBtn.MouseButton1Click:Connect(function()
	hideMenu()
	-- Show the existing teleport dialog for races
	teleportDialog.Visible = true
end)
