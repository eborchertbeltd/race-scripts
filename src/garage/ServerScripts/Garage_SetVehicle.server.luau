local ReplicatedStorage = game:GetService("ReplicatedStorage")

local placeMeshEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SetCar")
local updateGarageEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("UpdateGarage")
local modelsFolder = ReplicatedStorage:WaitForChild("Cars")
local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))
local Players = game:GetService("Players")
local PlayerCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Player_PlayerCache"))
-- tiny safety: limit spam
local lastPlace = {}

-- Track active money timers to prevent duplicates (one timer per vehicle)
local activeTimers = {}

-- Cache the Garages folder
local garagesFolder = workspace:WaitForChild("Garages")

-- Helper function to get player's garage safely
local function getPlayerGarage(player)
	local playerGarageName = player:GetAttribute("AssignedGarage")
	if not playerGarageName then
		warn("[SetVehicle] Player has no AssignedGarage attribute:", player.Name)
		return nil
	end
	return garagesFolder:FindFirstChild(playerGarageName)
end


-- Apply custom color to Body and Wheel parts of a model
local function applyVehicleColor(model, colorString)
	if not colorString or colorString == "" then
		return
	end

	local color = Utils.parseColorString(colorString)
	if not color then
		return
	end

	-- Find and color all Body and Wheel parts (there may be multiple of each)
	for _, descendant in ipairs(model:GetDescendants()) do
		if (descendant.Name == "Body" or descendant.Name == "Wheel") and descendant:IsA("BasePart") then
			descendant.Color = color
		end
	end
end



-- Start the timer to add money
local function startMoneyTimer(player, vehicleId, num)
	-- Stop any existing timer for this vehicle
	if activeTimers[vehicleId] then
		activeTimers[vehicleId] = false
		-- Wait a moment for the old loop to stop
		task.wait(0.1)
	end

	-- Mark this timer as active
	activeTimers[vehicleId] = true

	-- Create or get MoneyValue on the garage
	local data = PlayerCache.Get(player.UserId)
	local vehicle
	for _, item in data["vehicles"] do
		if item.id == vehicleId then
			vehicle = item
			break
		end
	end

	local garage = getPlayerGarage(player)
	if not garage then
		warn("[SetVehicle] startMoneyTimer: Garage not found for player:", player.Name)
		activeTimers[vehicleId] = nil
		return
	end

	local mPad = garage:FindFirstChild("MPad" .. tostring(num))
	local billboard = mPad:FindFirstChild("BillboardGui")
	local top = billboard:FindFirstChild("Top")
	local bottom = billboard:FindFirstChild("Bottom")
	top.Visible = true
	bottom.Visible = true
	local moneyValue = mPad:FindFirstChild("Money")

	if not moneyValue then
		moneyValue = Instance.new("NumberValue")
		moneyValue.Name = "Money"
		moneyValue.Parent = garage:FindFirstChild("SPad")
	end
	moneyValue.Value = vehicle.money_accumulated
	local mpMoney = mPad:FindFirstChild("MPMoney", true)
	local mpMoneyStroke = mPad:FindFirstChild("MPMoneyStroke", true)
	local moneyPerSecond = (vehicle.total_power + vehicle.total_speed) / 700
	-- Run loop while player is in the game
	task.spawn(function()
		task.wait(1.5)
		while top.Visible and activeTimers[vehicleId] do
			moneyValue.Value += moneyPerSecond
			mpMoney.Text = "$" .. math.floor(moneyValue.Value)
			mpMoneyStroke.Text = "$" .. math.floor(moneyValue.Value)
			task.wait(0.5)
		end
		-- Clean up when loop ends
		activeTimers[vehicleId] = nil
	end)
end


local function clearMoney(player, num, vehicleId)
	-- Stop the timer for this vehicle
	if vehicleId and activeTimers[vehicleId] then
		activeTimers[vehicleId] = false
		activeTimers[vehicleId] = nil
	end

	local data = ApiService.GetPlayerData(player.UserId)
	local garage = getPlayerGarage(player)
	if not garage then
		warn("[SetVehicle] clearMoney: Garage not found for player:", player.Name)
		return
	end
	local mPad = garage:FindFirstChild("MPad" .. tostring(num))
	local money = mPad:FindFirstChild("Money")
	if money then
		money.Value = 0
	end
	local billboard = mPad:FindFirstChild("BillboardGui")
	local top = billboard:FindFirstChild("Top")
	local mpMoney = mPad:FindFirstChild("MPMoney", true)
	local mpMoneyStroke = mPad:FindFirstChild("MPMoneyStroke", true)
	local bottom = billboard:FindFirstChild("Bottom")
	top.Visible = false
	bottom.Visible = false
	mpMoney.Text = "$" .. math.floor(money.Value)
	mpMoneyStroke.Text = "$" .. math.floor(money.Value)
end


local function placeRelative(player, modelName, targetName, num, remove, colorString)
	print("[SetVehicle] placeRelative called:", player.Name, "model:", modelName, "target:", targetName, "num:", num, "remove:", remove)

	local garage = getPlayerGarage(player)
	if not garage then
		warn("[SetVehicle] placeRelative: Garage not found for player:", player.Name)
		return
	end

	local target = garage:FindFirstChild(targetName, true)
	if not target then
		warn("[SetVehicle] Target pad not found:", targetName, "in garage:", garage.Name)
		return
	end

	if not target:IsA("BasePart") then
		warn("[SetVehicle] Target is not a BasePart:", targetName, "type:", target.ClassName)
		return
	end

	if remove then
		print("[SetVehicle] Removing vehicle from pad:", num)
		-- Remove all Models and MeshParts (same as placing logic)
		local removedCount = 0
		for _, child in ipairs(target:GetChildren()) do
			if child:IsA("Model") or child:IsA("MeshPart") then
				print("[SetVehicle] Removing child:", child.Name, "type:", child.ClassName)
				child:Destroy()
				removedCount = removedCount + 1
			end
		end
		print("[SetVehicle] Removed", removedCount, "vehicle(s) from pad", num)
		-- Clear the billboard when removing vehicle
		Utils.clearCarSignBillboard(garage, num)
	else
		print("[SetVehicle] Placing vehicle on pad:", num)
		-- Remove any existing vehicle from the target first
		local removedCount = 0
		for _, child in ipairs(target:GetChildren()) do
			if child:IsA("Model") or child:IsA("MeshPart") then
				print("[SetVehicle] Clearing existing child:", child.Name, "type:", child.ClassName)
				child:Destroy()
				removedCount = removedCount + 1
			end
		end
		if removedCount > 0 then
			print("[SetVehicle] Cleared", removedCount, "existing vehicle(s)")
		end

		local template = modelsFolder:FindFirstChild(modelName)
		if not template then
			warn("[SetVehicle] Vehicle template not found in ReplicatedStorage.Cars:", modelName)
			return
		end

		print("[SetVehicle] Found template:", template.Name, "type:", template.ClassName)
		local clone = template:Clone()
		clone.Parent = target
		print("[SetVehicle] Cloned vehicle, parent set to:", target.Name)

		local turn = 0
		if num > 4 then
			turn = 180
		end
		-- Compute the desired CFrame and position the model
		local baseCF = target.CFrame
		clone:PivotTo(baseCF * CFrame.new(0, 1, 0) * CFrame.Angles(0, math.rad(turn), 0))
		print("[SetVehicle] Vehicle positioned at pad", num, "with rotation:", turn)

		-- Apply custom color if specified
		if colorString and colorString ~= "" then
			print("[SetVehicle] Applying color:", colorString)
			applyVehicleColor(clone, colorString)
		end

		print("[SetVehicle] Vehicle successfully placed:", clone.Name)
		return clone
	end
end


placeMeshEvent.OnServerEvent:Connect(function(player, modelName, targetName, vehicleId, unslot)
	print("[SetVehicle] placeMeshEvent triggered by:", player.Name)
	print("[SetVehicle] Parameters - modelName:", modelName, "targetName:", targetName, "vehicleId:", vehicleId, "unslot:", unslot)

	local num = tonumber(targetName:match("%d+$"))
	print("[SetVehicle] Extracted pad number:", num)

	if unslot then
		print("[SetVehicle] UNSLOT operation - Removing vehicle", vehicleId, "from pad", num)
		ApiService.PatchVehicleSlotted(vehicleId, false, 1)
		ApiService.PatchVehicleMoney(vehicleId, 0.00)
		placeRelative(player, modelName, targetName, num, true)
		PlayerCache.Clear(player.UserId)
		clearMoney(player, num, vehicleId)
		print("[SetVehicle] Unslot complete")
		return
	end

	print("[SetVehicle] SLOT operation - Placing vehicle", vehicleId, "on pad", num)
	startMoneyTimer(player, vehicleId, num)

	-- simple debounce per player
	local t = os.clock()
	if lastPlace[player] and t - lastPlace[player] < 0.25 then
		warn("[SetVehicle] Debounce triggered - ignoring rapid placement")
		return
	end
	lastPlace[player] = t

	local data = PlayerCache.Get(player.UserId)
	print("[SetVehicle] Retrieved player cache, vehicles count:", #data["vehicles"])

	-- Find the vehicle's color and data from cache
	local vehicleColor = nil
	local vehicleData = nil
	for _, value in data["vehicles"] do
		if value.slotted and value.slotted_number == num then
			print("[SetVehicle] Unslotting existing vehicle at pad", num, "- vehicle ID:", value.id)
			ApiService.PatchVehicleSlotted(value.id, false, 1)
		end
		if value.id == vehicleId then
			vehicleColor = value.color
			vehicleData = value
			print("[SetVehicle] Found vehicle data - skin:", value.skin, "color:", vehicleColor)
		end
	end

	ApiService.PatchVehicleSlotted(vehicleId, true, num)
	print("[SetVehicle] Patched vehicle", vehicleId, "as slotted to pad", num)

	-- Validate we found the vehicle data
	if not vehicleData then
		warn("[SetVehicle] Vehicle data not found in cache for vehicleId:", vehicleId)
		return
	end

	-- Use the skin from the database, not the client parameter
	local skinName = vehicleData.skin
	if not skinName or skinName == "" then
		warn("[SetVehicle] Vehicle has no skin assigned, vehicleId:", vehicleId)
		return
	end

	-- validate args
	if type(targetName) ~= "string" then
		warn("[SetVehicle] Invalid parameter - targetName not string")
		return
	end

	print("[SetVehicle] Calling placeRelative with skin from database:", skinName)
	placeRelative(player, skinName, targetName, num, false, vehicleColor)

	-- Update the billboard with vehicle stats
	if vehicleData then
		local garage = getPlayerGarage(player)
		if garage then
			print("[SetVehicle] Updating billboard for pad", num)
			Utils.updateCarSignBillboard(garage, num, vehicleData)
		else
			warn("[SetVehicle] Garage not found for billboard update for player:", player.Name)
		end
	else
		warn("[SetVehicle] No vehicle data found for billboard update")
	end

	PlayerCache.Clear(player.UserId)
	print("[SetVehicle] Slot operation complete")
end)


updateGarageEvent.OnServerEvent:Connect(function(player)
	local data = PlayerCache.Get(player.UserId)
	local garage = getPlayerGarage(player)

	for _, result in data["vehicles"] do
		if result.slotted then
			placeRelative(player, result.skin, "Pad" .. tostring(result.slotted_number), result.slotted_number, false, result.color)
			startMoneyTimer(player, result.id, result.slotted_number)
			-- Update billboard for this vehicle
			if garage then
				Utils.updateCarSignBillboard(garage, result.slotted_number, result)
			end
		end
	end
end)


Players.PlayerAdded:Connect(function(player)
	local data = PlayerCache.Get(player.UserId)
	local garage = getPlayerGarage(player)

	for _, result in data["vehicles"] do
		if result.slotted then
			placeRelative(player, result.skin, "Pad" .. tostring(result.slotted_number), result.slotted_number, false, result.color)
			startMoneyTimer(player, result.id, result.slotted_number)
			-- Update billboard for this vehicle
			if garage then
				Utils.updateCarSignBillboard(garage, result.slotted_number, result)
			end
		end
	end
end)

