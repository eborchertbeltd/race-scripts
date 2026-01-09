--#GARAGE
-- Handles all garage triggers for PlayerGarage1-8: buildVehicleTrigger, SPad, and MPad1-MPad8
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Utils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))

-- Get Garages folder from workspace
local garagesFolder = workspace:WaitForChild("Garages")

-- Remote events
local showBuildCarEv = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowBuildCar")
local showSkinEv = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowSkin")
local showSetCarEv = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowSetCar")
local moneyCollectedEvent = game.ServerScriptService:WaitForChild("SPadMoneyCollected")

-- Track players inside area trigger per garage: [garage][player] = true
local insideArea = {}

-- Track which vehicle pad each player is inside per garage: [garage][player][padName] = true
local insidePad = {}

-- Cooldown tracking for money collection per garage: [garage].spad, [garage].mpad[padName]
local cooldowns = {}
local COOLDOWN = 3  -- seconds


local function getPlayerFromPart(part)
	local char = part:FindFirstAncestorWhichIsA("Model")
	if not char then return nil end
	local plr = Players:GetPlayerFromCharacter(char)
	return plr
end


-- ============================================
-- Setup function for a single garage
-- ============================================
local function setupGarageTriggers(garage)
	-- Initialize tracking for this garage
	insideArea[garage] = {}
	insidePad[garage] = {}
	cooldowns[garage] = {
		spad = 0,
		mpad = {}
	}

	print("[GarageTriggers] Setting up triggers for " .. garage.Name)

	-- ============================================
	-- 1. Build Vehicle Area Trigger
	-- ============================================
	local buildVehicleTrigger = garage:FindFirstChild("buildVehicleTrigger")
	if buildVehicleTrigger then
		buildVehicleTrigger.Touched:Connect(function(hit)
			local plr = getPlayerFromPart(hit)
			if plr and not insideArea[garage][plr] then
				-- Check if player owns this garage before showing buttons
				if not Utils.IsPlayerGarageOwner(plr, buildVehicleTrigger) then
					return
				end

				insideArea[garage][plr] = true
				showBuildCarEv:FireClient(plr, true)
				showSkinEv:FireClient(plr, true)
			end
		end)

		buildVehicleTrigger.TouchEnded:Connect(function(hit)
			local plr = getPlayerFromPart(hit)
			if plr and insideArea[garage][plr] then
				-- Delay briefly to handle teleportation edge cases
				task.delay(0.2, function()
					-- Verify player is actually outside the trigger before hiding
					local character = plr.Character
					if character then
						local hrp = character:FindFirstChild("HumanoidRootPart")
						if hrp then
							-- Check if player is still inside the trigger bounds
							local triggerCF = buildVehicleTrigger.CFrame
							local triggerSize = buildVehicleTrigger.Size
							local relativePos = triggerCF:PointToObjectSpace(hrp.Position)
							local halfSize = triggerSize / 2

							local isInside = math.abs(relativePos.X) <= halfSize.X
								and math.abs(relativePos.Y) <= halfSize.Y
								and math.abs(relativePos.Z) <= halfSize.Z

							if isInside then
								-- Player is still inside, don't hide buttons
								return
							end
						end
					end

					-- Player is actually outside, hide buttons
					if insideArea[garage][plr] then
						insideArea[garage][plr] = nil
						showBuildCarEv:FireClient(plr, false)
						showSkinEv:FireClient(plr, false)
					end
				end)
			end
		end)

		print("[GarageTriggers] Set up buildVehicleTrigger for " .. garage.Name)
	end


	-- ============================================
	-- 2. SPad (Sponsor Money Collection)
	-- ============================================
	local sPad = garage:FindFirstChild("SPad")
	if sPad then
		local spMoney = sPad:WaitForChild("Money")

		-- Initialize SPad labels to empty if garage is unoccupied
		local spMoneyLabel = sPad:FindFirstChild("SPMoney", true)
		local spMoneyStroke = sPad:FindFirstChild("SPMoneyStroke", true)
		local collectLabel = sPad:FindFirstChild("TextLabel", true)
		local collectStroke = sPad:FindFirstChild("TextLabel - Stroke", true)

		-- Check if garage has an owner (check GarageInfo NumberValue)
		local garageInfo = garage:FindFirstChild("GarageInfo")
		local ownerValue = garageInfo and garageInfo:FindFirstChild("OwnerId")
		local hasOwner = ownerValue and ownerValue.Value > 0

		if not hasOwner then
			-- Garage is unoccupied, clear all the labels
			if spMoneyLabel then spMoneyLabel.Text = "" end
			if spMoneyStroke then spMoneyStroke.Text = "" end
			if collectLabel then collectLabel.Text = "" end
			if collectStroke then collectStroke.Text = "" end
		end

		sPad.Touched:Connect(function(hit)
			local plr = getPlayerFromPart(hit)
			if not plr then return end

			-- Check ownership
			if not Utils.IsPlayerGarageOwner(plr, sPad) then
				return
			end

			-- Check cooldown
			local currentTime = tick()
			if currentTime - cooldowns[garage].spad < COOLDOWN then
				return  -- Still on cooldown
			end

			local amount = spMoney.Value
			if amount > 0 then
				-- Fire event to GarageScript with player and amount
				moneyCollectedEvent:Fire(plr, amount)

				-- Clear SPad money
				spMoney.Value = 0

				-- Start cooldown
				cooldowns[garage].spad = currentTime

				-- Update UI
				local spMoneyLbl = sPad:FindFirstChild("SPMoney", true)
				local spMoneyStrk = sPad:FindFirstChild("SPMoneyStroke", true)
				if spMoneyLbl then spMoneyLbl.Text = "$0" end
				if spMoneyStrk then spMoneyStrk.Text = "$0" end
			end
		end)

		print("[GarageTriggers] Set up SPad collection for " .. garage.Name)
	end


	-- ============================================
	-- 3. MPad1-MPad8 (Vehicle Money Collection)
	-- ============================================
	for i = 1, 8 do
		local padName = "MPad" .. tostring(i)
		local mPad = garage:FindFirstChild(padName)

		if mPad then
			local mpMoney = mPad:WaitForChild("Money")
			local billboardGui = mPad:FindFirstChild("BillboardGui")
			local top = billboardGui and billboardGui:FindFirstChild("Top", true)

			-- Initialize cooldown for this pad
			cooldowns[garage].mpad[padName] = 0

			mPad.Touched:Connect(function(hit)
				local plr = getPlayerFromPart(hit)
				if not plr or (top and not top.Visible) then return end

				-- Check ownership
				if not Utils.IsPlayerGarageOwner(plr, mPad) then
					return
				end

				-- Check cooldown
				local currentTime = tick()
				if currentTime - cooldowns[garage].mpad[padName] < COOLDOWN then
					return  -- Still on cooldown
				end

				local amount = mpMoney.Value
				if amount > 0 then
					-- Fire event to GarageScript with player and amount
					moneyCollectedEvent:Fire(plr, amount)

					-- Clear MPad money
					mpMoney.Value = 0

					-- Start cooldown
					cooldowns[garage].mpad[padName] = currentTime

					-- Update UI
					local mpMoneyLabel = mPad:FindFirstChild("MPMoney", true)
					local mpMoneyStroke = mPad:FindFirstChild("MPMoneyStroke", true)
					if mpMoneyLabel then mpMoneyLabel.Text = "$0" end
					if mpMoneyStroke then mpMoneyStroke.Text = "$0" end
				end
			end)

			print("[GarageTriggers] Set up " .. padName .. " collection for " .. garage.Name)
		end
	end


	-- ============================================
	-- 4. Pad1-Pad8 (SetCar UI Triggers)
	-- ============================================
	for i = 1, 8 do
		local padName = "Pad" .. tostring(i)
		local pad = garage:FindFirstChild(padName)

		if pad then
			-- Find the SetVehicleTrigger within the pad
			local trigger = pad:FindFirstChild("SetVehicleTrigger")

			if trigger then
				-- Touched event for this pad's trigger
				trigger.Touched:Connect(function(hit)
					local plr = getPlayerFromPart(hit)
					if plr then
						-- Initialize player's inside table if needed
						if not insidePad[garage][plr] then
							insidePad[garage][plr] = {}
						end

						-- Check if player is not already inside this specific pad
						if not insidePad[garage][plr][padName] then
							-- Check if player owns this garage before showing SetCar UI
							if not Utils.IsPlayerGarageOwner(plr, trigger) then
								return
							end

							insidePad[garage][plr][padName] = true
							showSetCarEv:FireClient(plr, true, padName)
						end
					end
				end)

				-- TouchEnded event for this pad's trigger
				trigger.TouchEnded:Connect(function(hit)
					local plr = getPlayerFromPart(hit)
					if plr and insidePad[garage][plr] and insidePad[garage][plr][padName] then
						insidePad[garage][plr][padName] = nil
						showSetCarEv:FireClient(plr, false, padName)
					end
				end)

				print("[GarageTriggers] Set up SetCar trigger for " .. padName .. " in " .. garage.Name)
			end
		end
	end
end


-- ============================================
-- Set up all garages (PlayerGarage1-8)
-- ============================================
for _, garage in pairs(garagesFolder:GetChildren()) do
	if garage:IsA("Model") and garage.Name:match("^PlayerGarage%d+$") then
		setupGarageTriggers(garage)
	end
end

print("[GarageTriggers] All garages initialized")


-- ============================================
-- Clean up when players leave
-- ============================================
Players.PlayerRemoving:Connect(function(plr)
	-- Clean up player from all garages
	for garage, _ in pairs(insideArea) do
		if insideArea[garage][plr] then
			insideArea[garage][plr] = nil
		end
	end
	for garage, _ in pairs(insidePad) do
		if insidePad[garage][plr] then
			insidePad[garage][plr] = nil
		end
	end

	-- Clear SPad labels for any garage owned by this player
	for _, garage in pairs(garagesFolder:GetChildren()) do
		if garage:IsA("Model") and garage.Name:match("^PlayerGarage%d+$") then
			local garageInfo = garage:FindFirstChild("GarageInfo")
			local ownerValue = garageInfo and garageInfo:FindFirstChild("OwnerId")

			-- Check if this garage was owned by the disconnecting player
			if ownerValue and ownerValue.Value == plr.UserId then
				local sPad = garage:FindFirstChild("SPad")
				if sPad then
					local spMoneyLabel = sPad:FindFirstChild("SPMoney", true)
					local spMoneyStroke = sPad:FindFirstChild("SPMoneyStroke", true)
					local collectLabel = sPad:FindFirstChild("TextLabel", true)
					local collectStroke = sPad:FindFirstChild("TextLabel - Stroke", true)
					if spMoneyLabel then spMoneyLabel.Text = "" end
					if spMoneyStroke then spMoneyStroke.Text = "" end
					if collectLabel then collectLabel.Text = "" end
					if collectStroke then collectStroke.Text = "" end
				end
			end
		end
	end
end)
