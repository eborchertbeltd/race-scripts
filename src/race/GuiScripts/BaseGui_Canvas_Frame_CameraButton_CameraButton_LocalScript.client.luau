local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RaceSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RaceSoundUtils"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local button = playerGui:WaitForChild("BaseGui"):WaitForChild("Canvas"):WaitForChild("Frame"):WaitForChild("CameraButton")
local RequestTrackChange = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("RequestTrackChange")

local debounceTime = 0.5 -- 0.5 second debounce
local lastClickTime = 0

-- Track if RaceGui is currently shown
local isRaceGuiShown = false
local currentTrackShown = nil

-- Track names to check
local TRACKS = {"Oval", "Road", "Drag", "Dirt"}

-- Function to get player's current position
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

-- Function to find the billboard position for a track
local function getBillboardPosition(trackName)
	local conventionFolder = workspace:FindFirstChild("Convention")
	if not conventionFolder then
		return nil
	end

	local trackFolder = conventionFolder:FindFirstChild(trackName)
	if not trackFolder then
		return nil
	end

	local billboard = trackFolder:FindFirstChild("Billboard")
	if billboard then
		-- Billboard could be a Model or BasePart
		if billboard:IsA("BasePart") then
			return billboard.Position
		elseif billboard:IsA("Model") then
			local primaryPart = billboard.PrimaryPart
			if primaryPart then
				return primaryPart.Position
			end
			-- Fallback: find first BasePart
			for _, child in ipairs(billboard:GetDescendants()) do
				if child:IsA("BasePart") then
					return child.Position
				end
			end
		end
	end

	return nil
end

-- Function to find the closest track based on player distance to billboards
local function findClosestTrack()
	local playerPos = getPlayerPosition()
	if not playerPos then
		return TRACKS[1] -- Default to Oval if can't get player position
	end

	local closestTrack = nil
	local closestDistance = math.huge

	for _, trackName in ipairs(TRACKS) do
		local billboardPos = getBillboardPosition(trackName)
		if billboardPos then
			local distance = (playerPos - billboardPos).Magnitude
			if distance < closestDistance then
				closestDistance = distance
				closestTrack = trackName
			end
		end
	end

	-- Default to Oval if no billboards found
	return closestTrack or TRACKS[1]
end

-- Handle button click
button.MouseButton1Click:Connect(function()
	-- Check debounce
	local currentTime = tick()
	if currentTime - lastClickTime < debounceTime then
		return
	end
	lastClickTime = currentTime

	-- Play button sound
	RaceSoundUtils.PlayButtonPressed()

	if isRaceGuiShown then
		-- Hide the RaceGui
		local success = pcall(function()
			RequestTrackChange:InvokeServer(false, currentTrackShown or "Oval")
		end)
		isRaceGuiShown = false
		currentTrackShown = nil
		print("[CameraButton] Hiding RaceGui")
	else
		-- Find closest track and show RaceGui
		local closestTrack = findClosestTrack()
		local success = pcall(function()
			RequestTrackChange:InvokeServer(true, closestTrack)
		end)
		if success then
			isRaceGuiShown = true
			currentTrackShown = closestTrack
			print("[CameraButton] Showing RaceGui for track:", closestTrack)
		else
			warn("[CameraButton] Failed to request track change")
		end
	end
end)

print("[CameraButton] Script loaded")
