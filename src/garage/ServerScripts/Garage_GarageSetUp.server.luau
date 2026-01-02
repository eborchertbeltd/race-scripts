local Players = game:GetService("Players")
local garagesFolder = workspace:WaitForChild("Garages")
local DEFAULT_SPONSOR_LEVEL = 0.1  -- Fallback if sponsor_level not set
local moneyCollectedEvent = game.ServerScriptService:WaitForChild("SPadMoneyCollected")
local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
local PlayerCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Player_PlayerCache"))
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))

-- Define 8 primary colors for player names
local PRIMARY_COLORS = {
	{name = "Blue", color = Color3.fromRGB(30, 144, 255)},
	{name = "Red", color = Color3.fromRGB(220, 30, 30)},
	{name = "Yellow", color = Color3.fromRGB(255, 215, 0)},
	{name = "Pink", color = Color3.fromRGB(255, 105, 180)},
	{name = "Purple", color = Color3.fromRGB(138, 43, 226)},
	{name = "Green", color = Color3.fromRGB(50, 205, 50)},
	{name = "Orange", color = Color3.fromRGB(255, 140, 0)},
	{name = "Gray", color = Color3.fromRGB(169, 169, 169)},
}

-- Track which colors are available (true = available, false = in use)
local availableColors = {}
for i = 1, #PRIMARY_COLORS do
	availableColors[i] = true
end

-- Track which color each player has
local playerColors = {}

-- Get the next available color
local function getAvailableColor()
	for i, available in ipairs(availableColors) do
		if available then
			return i
		end
	end
	return nil -- All colors in use
end

-- Track which garages are free/assigned
local garageSlots = {}
for _, garage in ipairs(garagesFolder:GetChildren()) do
	-- Only process Model objects, skip scripts and other non-garage objects
	if garage:IsA("Model") then
		garageSlots[garage.Name] = {model = garage, occupied = false, player = nil, }
	end
end

-- Track sponsor level for each player (used by money accumulation task)
local playerSponsorLevels = {}

-- Helper function to get sponsor tier from numeric value
local function getSponsorTier(sponsorLevel)
	if sponsorLevel <= 0.5 then
		return "Common"
	elseif sponsorLevel <= 1.0 then
		return "Rare"
	elseif sponsorLevel <= 1.5 then
		return "Epic"
	else
		return "Legendary"
	end
end

-- Update the sponsor level sign in the garage
local function updateSponsorSign(garage, tier)
	local sign = garage:FindFirstChild("Sign", true)
	if not sign then
		warn("[GarageSetup] Sign not found in garage:", garage.Name)
		return
	end

	local surfaceGui = Utils.findDescendantByName(sign, "Sponsor")
	if not surfaceGui then
		warn("[GarageSetup] Sponsor not found in Sign")
		return
	end

	local sponsorLevelLabel = Utils.findDescendantByName(surfaceGui, "SponsorLevel")
	if not sponsorLevelLabel then
		warn("[GarageSetup] SponsorLevel TextLabel not found in SurfaceGui")
		return
	end

	sponsorLevelLabel.Text = tier
end

-- Check and update sponsor level (called when fetching player data)
local function checkAndUpdateSponsorLevel(player, garage, newLevel)
	local userId = player.UserId
	local oldLevel = playerSponsorLevels[userId]

	-- Update the shared variable (for money accumulation)
	playerSponsorLevels[userId] = newLevel

	-- Check if tier changed
	if oldLevel then
		local oldTier = getSponsorTier(oldLevel)
		local newTier = getSponsorTier(newLevel)
		if oldTier ~= newTier then
			print(player.Name .. " sponsor tier changed from " .. oldTier .. " to " .. newTier)
			updateSponsorSign(garage, newTier)
		end
	else
		-- First time, just set it
		updateSponsorSign(garage, getSponsorTier(newLevel))
	end
end

-- ✅ Helper to find a random empty garage
local function getAvailableGarage()
	-- Collect all available garages
	local availableGarages = {}
	for name, info in pairs(garageSlots) do
		if not info.occupied then
			table.insert(availableGarages, info)
		end
	end

	-- Return nil if no garages available
	if #availableGarages == 0 then
		return nil
	end

	-- Pick a random garage from available ones
	local randomIndex = math.random(1, #availableGarages)
	return availableGarages[randomIndex]
end


-- Start the timer to add money
local function startMoneyTimer(player, garage)
	-- Create or get MoneyValue on the garage
	local data = ApiService.GetPlayerData(player.UserId)

	-- Use WaitForChild to ensure SPad exists (with timeout)
	local sPad = garage["model"]:WaitForChild("SPad", 5)

	-- Check if SPad exists before trying to access it
	if not sPad then
		warn("[GarageSetUp] SPad not found in garage model for player:", player.Name, "after 5 second timeout")
		return
	end

	local moneyValue = sPad:FindFirstChild("Money")

	if not moneyValue then
		moneyValue = Instance.new("NumberValue")
		moneyValue.Name = "Money"
		moneyValue.Parent = garage["model"]:FindFirstChild("SPad")
	end
	moneyValue.Value = data.sponsor_money_accumulated

	-- Get sponsor_level from API data
	local sponsorLevel = data.sponsor_level or DEFAULT_SPONSOR_LEVEL

	-- Check and update sponsor level (updates shared variable and sign)
	checkAndUpdateSponsorLevel(player, garage["model"], sponsorLevel)

	local spMoney = sPad:FindFirstChild("SPMoney", true)
	local spMoneyStroke = sPad:FindFirstChild("SPMoneyStroke", true)
	local collectLabel = sPad:FindFirstChild("TextLabel", true)
	local collectStroke = sPad:FindFirstChild("TextLabel - Stroke", true)

	-- Set "Collect" labels when player occupies garage
	if collectLabel then collectLabel.Text = "Collect" end
	if collectStroke then collectStroke.Text = "Collect" end

	-- Run loop while player is in the game
	task.spawn(function()
		while player.Parent do
			-- Use shared sponsor level (allows dynamic updates)
			local currentSponsorLevel = playerSponsorLevels[player.UserId] or DEFAULT_SPONSOR_LEVEL
			moneyValue.Value += currentSponsorLevel
			spMoney.Text = "$" .. math.floor(moneyValue.Value)
			spMoneyStroke.Text = "$" .. math.floor(moneyValue.Value)
			task.wait(1)
		end
	end)
end


-- ✅ Assign garage when player joins7
Players.PlayerAdded:Connect(function(player)
	local slot = getAvailableGarage()
	if slot then
		slot.occupied = true
		slot.player = player
		local ownerLabel = slot["model"]:FindFirstChild("HangarName", true) -- 'true' searches descendants
		if ownerLabel and ownerLabel:IsA("TextLabel") then
			ownerLabel.Text = player.Name
			-- Get next available color
			local colorIndex = getAvailableColor()
			if colorIndex then
				-- Mark color as in use
				availableColors[colorIndex] = false
				playerColors[player.UserId] = colorIndex
				-- Set the color
				ownerLabel.TextColor3 = PRIMARY_COLORS[colorIndex].color
				print(player.Name .. " assigned color: " .. PRIMARY_COLORS[colorIndex].name)
			else
				-- Fallback to white if all colors are in use
				ownerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				warn("All colors in use for " .. player.Name .. ", using white")
			end
		end
		player:SetAttribute("AssignedGarage", slot.model.Name)
		print(player.Name .. " assigned to " .. slot.model.Name)
		startMoneyTimer(player, slot)
	else
		warn("No garages available for " .. player.Name)
	end
end)


-- ✅ Free garage when player leaves
Players.PlayerRemoving:Connect(function(player)
	for name, info in pairs(garageSlots) do
		if info.player == player then
			local playerGarageName = player:GetAttribute("AssignedGarage")
			local garage = workspace:FindFirstChild(playerGarageName, true)
			if not garage then
				warn("[GarageSetUp] Garage not found for player:", player.Name, "garage name:", playerGarageName)
				return
			end
			local sPad = garage:FindFirstChild("SPad")
			if not sPad then
				warn("[GarageSetUp] SPad not found in garage for leaving player:", player.Name)
				return
			end
			local moneyValue = sPad:FindFirstChild("Money")
			if moneyValue then
				ApiService.PostSponsorAccumulatedUpdate(player, moneyValue.Value)
				moneyValue.Value = 0
			end
			local data = PlayerCache.Get(player.UserId)
			local ownerLabel = garage:FindFirstChild("HangarName", true)
			if ownerLabel and ownerLabel:IsA("TextLabel") then
				ownerLabel.Text = "EMPTY"
				-- Reset color back to white
				ownerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
			-- Free up the player's color
			local colorIndex = playerColors[player.UserId]
			if colorIndex then
				availableColors[colorIndex] = true
				playerColors[player.UserId] = nil
				print(player.Name .. " freed color: " .. PRIMARY_COLORS[colorIndex].name)
			end
			info.occupied = false
			info.player = nil
			-- Clean up sponsor level tracking
			playerSponsorLevels[player.UserId] = nil
			print(player.Name .. " left, freed " .. name)
			for i =1, 8 do
				local mpad = garage:FindFirstChild("MPad" .. tostring(i))
				local mMoney = mpad:FindFirstChild("Money", true)
				if mMoney then
					if mMoney.Value > 0 then
						for _, vehicle in data["vehicles"] do
							if vehicle.slotted_number == i then
								ApiService.PatchVehicleMoney(vehicle.id, mMoney.Value)
							end
						end
					end
					mMoney.Value = 0
				end
				local pad = garage:FindFirstChild("Pad" .. tostring(i))
				local car = pad:FindFirstChildWhichIsA("MeshPart")
				if car then
					car:Destroy()
				end
				-- Clear the billboard for this pad
				Utils.clearCarSignBillboard(garage, i)
			end
		end
	end
end)


-- ✅ When an SPad reports collected money
moneyCollectedEvent.Event:Connect(function(player, amount)
	local data = ApiService.GetPlayerData(player.UserId)
	local newMoney = data.money + amount
	player:SetAttribute("Money", newMoney)
	ApiService.PostMoneyUpdate(player, newMoney)

	print(player.Name .. " collected " .. amount .. " and now has " .. newMoney)
end)