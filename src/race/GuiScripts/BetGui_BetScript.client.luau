-- BetGui_BetScript.client.luau
-- Displays races for betting, cycles through available races for a track
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- RemoteEvents and RemoteFunctions
local betEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowBet")
local fetchQueueFunc = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchTrackQueue")
local getVehicleNameRF = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("GetVehicleName")
local placeBet = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("PlaceBet")
local fetchBets = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchBets")

-- Modules
local Utils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ReplicaUtils"))
local RaceSoundUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RaceSoundUtils"))

-- Player references
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local BetGui = playerGui:WaitForChild("BetGui")

-- GUI references
local window = Utils.findDescendantByName(BetGui, "Window")
local content = Utils.findDescendantByName(window, "Content")
local header = Utils.findDescendantByName(content, "Header")
local body = Utils.findDescendantByName(content, "Body")
local headerLine = Utils.findDescendantByName(header, "Line")
local scrollingFrame = Utils.findDescendantByName(body, "ScrollingFrame")

-- Track selector buttons
local leftArrow = Utils.findDescendantByName(headerLine, "Left")
local rightArrow = Utils.findDescendantByName(headerLine, "Right")
local trackButton = Utils.findDescendantByName(headerLine, "Race")
local trackLabel = Utils.findDescendantByName(trackButton, "TextLabel")

-- Templates
local raceTemplate = Utils.findDescendantByName(scrollingFrame, "RaceTemplate")
local noScheduledRace = Utils.findDescendantByName(scrollingFrame, "NoScheduledRace")

-- Hide templates initially
if raceTemplate then raceTemplate.Visible = false end
if noScheduledRace then noScheduledRace.Visible = false end

-- State
local tracks = {"Oval", "Road", "Drag", "Dirt"}
local currentTrackIndex = 1
local currentTrack = "Oval"
local races = {}
local playerBets = {}
local isLoading = false

-- Color scheme for levels
local levelColors = {
	Common = Color3.fromRGB(6, 123, 202),
	Rare = Color3.fromRGB(79, 213, 2),
	Epic = Color3.fromRGB(186, 50, 226),
	Legendary = Color3.fromRGB(255, 219, 49)
}

-- Bet amounts by level
local betAmounts = {
	Common = 100,
	Rare = 200,
	Epic = 300,
	Legendary = 500
}


-- Helper to parse NPC pool from race data
local function parseNPCPool(raceData)
	local npcList = {}
	if not raceData or not raceData.npc_pool then return npcList end

	local pool = raceData.npc_pool

	-- If it's already a table, use it directly
	if type(pool) == "table" then
		for key, npcData in pairs(pool) do
			local npcName = (type(npcData) == "table" and npcData.name) or key
			table.insert(npcList, {
				name = npcName,
				id = key, -- "npc-1", "npc-2", etc.
				isNPC = true
			})
		end
	elseif type(pool) == "string" then
		-- Try to decode JSON string
		local HttpService = game:GetService("HttpService")
		local success, decoded = pcall(function()
			return HttpService:JSONDecode(pool)
		end)
		if success and decoded then
			for key, npcData in pairs(decoded) do
				local npcName = (type(npcData) == "table" and npcData.name) or key
				table.insert(npcList, {
					name = npcName,
					id = key,
					isNPC = true
				})
			end
		end
	end

	return npcList
end


-- Get all racers (players + NPCs) for a race
local function getRacers(raceData)
	local racers = {}
	local npcPool = parseNPCPool(raceData)
	local npcIndex = 1

	-- Check vehicle1-4 for player vehicles
	for i = 1, 4 do
		local vehicleId = raceData["vehicle" .. i]
		if vehicleId then
			-- This is a player's vehicle
			local success, playerName = pcall(function()
				return getVehicleNameRF:InvokeServer(vehicleId)
			end)
			table.insert(racers, {
				name = success and playerName or "Unknown",
				id = vehicleId,
				isNPC = false,
				position = i
			})
		else
			-- No player in this slot, use NPC
			if npcIndex <= #npcPool then
				local npc = npcPool[npcIndex]
				npc.position = i
				table.insert(racers, npc)
				npcIndex = npcIndex + 1
			end
		end
	end

	return racers
end


-- Check if player has bet on a specific race
local function hasPlayerBetOnRace(raceId)
	for _, bet in ipairs(playerBets) do
		if bet.race == raceId then
			return true, bet.bet_on -- Returns true and the name they bet on
		end
	end
	return false, nil
end


-- Update track selector display
local function updateTrackSelector()
	if trackLabel then
		trackLabel.Text = currentTrack
		trackLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end


-- Helper to show spinner on a button
local function showButtonSpinner(button, show)
	if not button then return end

	local textLabel = Utils.findDescendantByName(button, "TextLabel")
	local existingSpinner = button:FindFirstChild("SpinnerFrame")

	if show then
		button.Active = false
		if textLabel then textLabel.Visible = false end

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

		if existingSpinner then
			existingSpinner:Destroy()
		end
	end
end


-- Forward declaration
local refreshDisplay


-- Place a bet on a racer
local function placeBetOnRacer(race, racer, button)
	if isLoading then return end

	-- Check if already bet on this race
	local alreadyBet, _ = hasPlayerBetOnRace(race.id)
	if alreadyBet then
		warn("[BetScript] Already bet on this race")
		return
	end

	RaceSoundUtils.PlayRegister()
	showButtonSpinner(button, true)

	task.spawn(function()
		local level = race.level or "Common"
		local amount = betAmounts[level] or 100

		-- For NPCs: pass the name (e.g., "Fast Eddie") - matches actual_results_json npc_name
		-- For vehicles: pass the vehicle UUID - matches actual_results_json vehicle_id
		local betTarget
		if racer.isNPC then
			betTarget = racer.name
		else
			betTarget = racer.id -- vehicle UUID
		end

		local success, result = pcall(function()
			return placeBet:InvokeServer(amount, race.id, betTarget)
		end)

		-- Refresh bets and display
		playerBets = fetchBets:InvokeServer() or {}
		refreshDisplay()
	end)
end


-- Create a racer row from the Template
local function createRacerRow(parentFrame, race, racer, hasBetOnRace, betOnName)
	local template = Utils.findDescendantByName(parentFrame, "Template")
	if not template then
		warn("[BetScript] Template not found in race frame")
		return nil
	end

	local row = template:Clone()
	row.Name = racer.name or "Racer"
	row.Visible = true

	-- Set racer name
	local racerLabel = Utils.findDescendantByName(row, "Racer")
	if racerLabel then
		racerLabel.Text = racer.name or "Unknown"
		-- Color NPCs differently
		if racer.isNPC then
			racerLabel.TextColor3 = Color3.fromRGB(100, 150, 255) -- Blue for NPCs
		else
			racerLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- White for players
		end
	end

	-- Get button references
	local betButton = Utils.findDescendantByName(row, "Bet")
	local joinedButton = Utils.findDescendantByName(row, "Joined")

	-- Check if this is the racer they bet on
	-- For NPCs: bet_on stores name (e.g., "Fast Eddie")
	-- For vehicles: bet_on stores vehicle UUID
	local isBetTarget = false
	if hasBetOnRace and betOnName then
		if racer.isNPC then
			isBetTarget = (betOnName == racer.name)
		else
			isBetTarget = (betOnName == racer.id)
		end
	end

	if isBetTarget then
		-- Show Joined, hide Bet
		if joinedButton then joinedButton.Visible = true end
		if betButton then betButton.Visible = false end
	elseif hasBetOnRace then
		-- Already bet on someone else in this race - hide both buttons
		if joinedButton then joinedButton.Visible = false end
		if betButton then betButton.Visible = false end
	else
		-- Can bet on this racer
		if joinedButton then joinedButton.Visible = false end
		if betButton then
			betButton.Visible = true

			-- Set bet amount text
			local level = race.level or "Common"
			local amount = betAmounts[level] or 100
			local betLabel = Utils.findDescendantByName(betButton, "TextLabel")
			if betLabel then
				betLabel.Text = "$" .. tostring(amount)
			end

			-- Connect click handler
			betButton.MouseButton1Click:Connect(function()
				placeBetOnRacer(race, racer, betButton)
			end)
		end
	end

	row.Parent = parentFrame
	return row
end


-- Load a race into the template
local function loadRace(race)
	if not raceTemplate then
		warn("[BetScript] RaceTemplate not found")
		return nil
	end

	local clone = raceTemplate:Clone()
	clone.Name = "Race_" .. (race.number or "unknown")
	clone.Visible = true

	-- Find Content frame
	local contentFrame = Utils.findDescendantByName(clone, "Content")
	if not contentFrame then
		contentFrame = clone
	end

	-- Set race name with level color (e.g., "Epic - #5049")
	local nameLabel = Utils.findDescendantByName(contentFrame, "Name")
	if nameLabel then
		local level = race.level or "Common"
		local levelLower = string.lower(level)
		local levelDisplay = string.upper(string.sub(levelLower, 1, 1)) .. string.sub(levelLower, 2)
		local displayText = levelDisplay .. " - #" .. (race.number or "?")

		if nameLabel:IsA("TextLabel") then
			nameLabel.Text = displayText
			nameLabel.TextColor3 = levelColors[level] or Color3.fromRGB(255, 255, 255)
		else
			local textLabel = Utils.findDescendantByName(nameLabel, "TextLabel")
			if textLabel then
				textLabel.Text = displayText
				textLabel.TextColor3 = levelColors[level] or Color3.fromRGB(255, 255, 255)
			end
		end
	end

	-- Check if player has bet on this race
	local hasBetOnRace, betOnName = hasPlayerBetOnRace(race.id)

	-- Get racers (players + NPCs)
	local racers = getRacers(race)

	-- Find the racers container (could be Races frame or similar)
	local racersFrame = Utils.findDescendantByName(contentFrame, "Races") or contentFrame

	-- Hide the template
	local racerTemplate = Utils.findDescendantByName(racersFrame, "Template")
	if racerTemplate then
		racerTemplate.Visible = false
	end

	-- Create rows for each racer
	for _, racer in ipairs(racers) do
		createRacerRow(racersFrame, race, racer, hasBetOnRace, betOnName)
	end

	clone.Parent = scrollingFrame
	return clone
end


-- Main refresh function
function refreshDisplay()
	if not scrollingFrame then
		warn("[BetScript] ScrollingFrame not found")
		return
	end

	-- Clear existing race clones (keep templates)
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= raceTemplate and child ~= noScheduledRace then
			child:Destroy()
		end
	end

	-- Update track selector
	updateTrackSelector()

	-- Show all races or NoScheduledRace
	if #races == 0 then
		if noScheduledRace then
			noScheduledRace.Visible = true
		end
	else
		if noScheduledRace then
			noScheduledRace.Visible = false
		end

		-- Load ALL races for this track
		for _, race in ipairs(races) do
			loadRace(race)
		end

		-- Adjust canvas size
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


-- Fetch races for current track
local function fetchRaces()
	isLoading = true

	-- Fetch track queue
	local trackQueue = fetchQueueFunc:InvokeServer(currentTrack) or {}

	-- Filter to only queued races (ready=false, race_finished=false)
	races = {}
	for _, race in ipairs(trackQueue) do
		if not race.ready and not race.race_finished then
			table.insert(races, race)
		end
	end

	-- Sort by race number
	table.sort(races, function(a, b)
		local numA = tonumber(a.number) or 0
		local numB = tonumber(b.number) or 0
		return numA < numB
	end)

	-- Reset to first race
	currentRaceIndex = 1

	-- Fetch player's current bets
	playerBets = fetchBets:InvokeServer() or {}

	isLoading = false
end


-- Cycle track left
local function cycleLeft()
	RaceSoundUtils.PlayButtonPressed()
	currentTrackIndex = currentTrackIndex - 1
	if currentTrackIndex < 1 then
		currentTrackIndex = #tracks
	end
	currentTrack = tracks[currentTrackIndex]
	fetchRaces()
	refreshDisplay()
end


-- Cycle track right
local function cycleRight()
	RaceSoundUtils.PlayButtonPressed()
	currentTrackIndex = currentTrackIndex + 1
	if currentTrackIndex > #tracks then
		currentTrackIndex = 1
	end
	currentTrack = tracks[currentTrackIndex]
	fetchRaces()
	refreshDisplay()
end


-- Connect track selector buttons
if leftArrow then
	leftArrow.MouseButton1Click:Connect(cycleLeft)
end

if rightArrow then
	rightArrow.MouseButton1Click:Connect(cycleRight)
end


-- Main event handler
-- Receives: show (boolean), track (string)
betEvent.OnClientEvent:Connect(function(show, track)
	if window then
		window.Visible = show == true
	end

	if show then
		-- Set track and find its index
		if track and type(track) == "string" then
			currentTrack = track
			for i, t in ipairs(tracks) do
				if t == track then
					currentTrackIndex = i
					break
				end
			end
		end

		-- Fetch races and refresh
		fetchRaces()
		refreshDisplay()
	end
end)
