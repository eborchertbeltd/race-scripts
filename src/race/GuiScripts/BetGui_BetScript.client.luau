local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local betEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowBet")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CompletedGui = playerGui:WaitForChild("BetGui")
local fetchQueueFunc = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchTrackQueue")
local getVehicleNameRF = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("GetVehicleName")
local fetchVehicles = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchVehicles")
local placeBet = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("PlaceBet")
local fetchBets = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchBets")
local joinRace = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("JoinRace")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ReplicaUtils"))
local RaceSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RaceSoundUtils"))

local window = Utils.findDescendantByName(CompletedGui, "Window")
local scrollingFrame = Utils.findDescendantByName(window, "RaceFrame")
local betButton = Utils.findDescendantByName(scrollingFrame, "BetButton")
local loading = false


local function showBet(track)
	if loading then return end
	loading = true

	local trackQueue = fetchQueueFunc:InvokeServer(track) or {}

	-- Fetch player's current bets
	local playerBets = fetchBets:InvokeServer() or {}
	local playerBetRaceIds = {}
	for _, bet in ipairs(playerBets) do
		if bet.race then
			playerBetRaceIds[bet.race] = true
			print("[BetScript] Player has existing bet on race:", bet.race_id)
		end
	end

	for _, each in ipairs(trackQueue) do
		-- Skip races where player already has a bet
		if not playerBetRaceIds[each.id] and not each.race_finished and not each.ready then
			local clone = betButton:Clone()

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
			local titleLabel = Utils.findDescendantByName(clone, "RaceLevel")
			local noRace = Utils.findDescendantByName(clone, "NoRace")
			local betAmount = "100"
			if titleLabel then
				titleLabel.Text = levelDisplay .. " #" .. (each.number or "?")
				if levelLower == "common" then
					titleLabel.TextColor3 = Color3.fromRGB(6, 123, 202)
				elseif levelLower == "rare" then
					titleLabel.TextColor3 = Color3.fromRGB(79, 213, 2)
					betAmount = "200"
				elseif levelLower == "epic" then
					titleLabel.TextColor3 = Color3.fromRGB(186, 50, 226)
					betAmount = "300"
				elseif levelLower == "legendary" then
					titleLabel.TextColor3 = Color3.fromRGB(255, 219, 49)
					betAmount = "500"
				else
					titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
			end

			-- Build results list (in order vehicle1..vehicle4)
			-- NOTE: This only shows actual players (not NPCs) because we only iterate vehicle1-4 fields,
			-- which are FK references to real Vehicle records. NPCs are stored in results JSON, not here.
			local sortedResults = {}
			for _, key in ipairs({"vehicle1", "vehicle2", "vehicle3", "vehicle4"}) do
				local id = each[key]
				if id then
					local ok, nameOrErr = pcall(function()
						return getVehicleNameRF:InvokeServer(id)
					end)
					table.insert(sortedResults, {ok and nameOrErr or "Unknown", id})
				end
			end

			-- Fill position labels (Drag shows only First/Second)
			local positions = {"First", "Second", "Third", "Fourth"}
			local found = false
			for posIndex, posName in ipairs(positions) do
				if sortedResults[posIndex] then
					if not found then
						found = true
						noRace.Visible = false
					end
					local template  = Utils.findDescendantByName(clone, "Template")
					local betTemplate = template:Clone()
					local textName = Utils.findDescendantByName(betTemplate, "Name")
					textName.Text = sortedResults[posIndex][1] or "N/A"
					local betButton = Utils.findDescendantByName(betTemplate, "TextButton")
					betButton.MouseButton1Click:Connect(function()
						RaceSoundUtils.PlayRegister()
						placeBet:InvokeServer(betAmount, each.id, sortedResults[posIndex][2])
						clone.Visible = false
					end)
					local amount = Utils.findDescendantByName(betTemplate, "TextLabel")
					amount.Text = betAmount
					local amountStroke = Utils.findDescendantByName(betTemplate, "TextLabelStroke")
					amountStroke.Text = betAmount
					betTemplate.Parent = clone
					betTemplate.Visible = true
				end
			end
			clone.Parent = scrollingFrame
			clone.Visible = true
		end
	end

	loading = false
end


betEvent.OnClientEvent:Connect(function(show, track)
	window.Visible = show == true
	if window.Visible then
		-- Clear old bet buttons (keep betButton template and UI elements)
		for _, child in ipairs(scrollingFrame:GetChildren()) do
			local isTemplate = (child == betButton)
			local isUIElement = child:IsA("UIGridLayout") or child:IsA("UIListLayout") or
				child:IsA("UIPadding") or child:IsA("UICorner") or
				child:IsA("UIStroke")

			-- Destroy everything else (including both visible and invisible items)
			if not isTemplate and not isUIElement then
				child:Destroy()
			end
		end
		showBet(track)
	end
end)