local Players = game:GetService("Players")
local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ShowGuiEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowStarterGui")
local fetchPlayer = ReplicatedStorage:WaitForChild("Player"):WaitForChild("FetchPlayer")
local UpdateVehicleSkin = ReplicatedStorage:WaitForChild("Player"):WaitForChild("UpdateVehicleSkin")
local UpdateVehicleColor = ReplicatedStorage:WaitForChild("Player"):WaitForChild("UpdateVehicleColor")
local ToggleMusic = ReplicatedStorage:WaitForChild("Player"):WaitForChild("ToggleMusic")
local getNotifications = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetNotifications")
local toRaces = ReplicatedStorage:WaitForChild("Player"):WaitForChild("ToRaces")
local PlayerCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Player_PlayerCache"))
local ServerData = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Data_DataCache"))

-- Track player session times for play time tracking
local playerJoinTimes = {}


getNotifications.OnServerInvoke = function(player)
	return ServerData.GetPlayerNotifications(player.UserId)
end


fetchPlayer.OnServerInvoke = function(player)
	local data = ApiService.GetPlayerData(player.UserId)
	player:SetAttribute("Money", data.money)
end


UpdateVehicleSkin.OnServerInvoke = function(player, vehicleId, skinName)
	local result = ApiService.UpdateVehicleSkin(vehicleId, skinName)
	PlayerCache.Clear(player.UserId)
	return result
end


UpdateVehicleColor.OnServerInvoke = function(player, vehicleId, color)
	local result = ApiService.UpdateVehicleColor(vehicleId, color)
	PlayerCache.Clear(player.UserId)
	return result
end


ToggleMusic.OnServerInvoke = function(player)
	-- Get current player data from cache
	local playerData = PlayerCache.Get(player.UserId)
	-- Handle music attribute properly - false is a valid value
	local currentMusic = playerData.player.music
	if currentMusic == nil then
		currentMusic = true
	end

	-- Toggle the music value
	local newMusicValue = not currentMusic

	-- Update backend
	local result = ApiService.UpdatePlayerMusic(player.UserId, newMusicValue)

	-- Clear the player cache so it will be refreshed on next access
	PlayerCache.Clear(player.UserId)

	-- Return the new music value
	if result and result.success then
		-- Update the player attribute
		player:SetAttribute("Music", result.music)
		return result.music
	else
		return currentMusic -- Return current value if update failed
	end
end


-- Respond when client invokes BackToGarage
toRaces.OnServerInvoke = function(player)
	if not player then
		warn("[ClientFetch] BackToGarage: missing player")
		return false
	end

	-- Placeholder for garage place ID - replace with actual garage place ID
	local GARAGE_PLACE_ID = 78232942736747 -- TODO: Replace with actual garage place ID

	print("[ClientFetch] Teleporting player", player.Name, "back to garage (Place ID:", GARAGE_PLACE_ID, ")")

	-- Teleport the player to the garage
	local success, errorMessage = pcall(function()
		game:GetService("TeleportService"):Teleport(GARAGE_PLACE_ID, player)
	end)

	if success then
		print("[ClientFetch] Successfully initiated teleport for player", player.Name)
		return true
	else
		warn("[ClientFetch] Failed to teleport player", player.Name, ":", errorMessage)
		return false
	end
end


Players.PlayerAdded:Connect(function(player)
	-- Track join time for play time tracking
	playerJoinTimes[player.UserId] = os.time()

	-- Call API
	local data = ApiService.GetPlayerData(player.UserId)

	local function showPlayerGui(player)
		ShowGuiEvent:FireClient(player)
	end

	-- If no response, optionally kick to prevent unverified players
	if not data then
		player:Kick("Unable to verify account. Try again later.")
		return
	end

	-- Check status fields
	if data.banned == true or data.active == false then
		player:Kick("You are banned or not active.")
		return
	end

	-- Store API values as attributes on the player
	player:SetAttribute("GameUserId", data.id)
	player:SetAttribute("Money", data.money)
	player:SetAttribute("has_chosen_first_car", data.has_chose_first_car)
	-- Handle music attribute properly - false is a valid value
	if data.music ~= nil then
		player:SetAttribute("Music", data.music)
	else
		player:SetAttribute("Music", true)
	end
	if not data.has_chosen_first_car then
		showPlayerGui(player)
	end
	local vehicles = ApiService.GetPlayerVehicles(player.UserId)
	print(vehicles)
	print(PlayerCache.Get(player.UserId))
	print(player.Name .. " authenticated. ID: " .. data.id .. " Money: " .. data.money)
end)


-- Track play time when player leaves
Players.PlayerRemoving:Connect(function(player)
	local joinTime = playerJoinTimes[player.UserId]
	if joinTime then
		local sessionTime = os.time() - joinTime
		print(string.format("[PlayTime] %s played for %d seconds", player.Name, sessionTime))

		-- Send play time to API
		local success = ApiService.UpdatePlayerPlayTime(player.UserId, sessionTime)
		if success then
			print(string.format("[PlayTime] Successfully updated play time for %s", player.Name))
		else
			warn(string.format("[PlayTime] Failed to update play time for %s", player.Name))
		end

		-- Clean up join time record
		playerJoinTimes[player.UserId] = nil
	end
end)


-- Background task: clear cache and update play time periodically
task.spawn(function()
	while true do
		task.wait(300) -- wait 5 minutes (300 seconds)

		-- Update play time for all active players
		for _, player in ipairs(Players:GetPlayers()) do
			local joinTime = playerJoinTimes[player.UserId]
			if joinTime then
				local sessionTime = os.time() - joinTime
				print(string.format("[PlayTime] Periodic update for %s: %d seconds", player.Name, sessionTime))

				-- Send play time to API
				local success = ApiService.UpdatePlayerPlayTime(player.UserId, sessionTime)
				if success then
					-- Reset join time after successful update
					playerJoinTimes[player.UserId] = os.time()
				else
					warn(string.format("[PlayTime] Failed periodic update for %s", player.Name))
				end
			end
		end
	end
end)

-- Background task: clear player cache periodically
while true do
	task.wait(60) -- wait 60 seconds
	PlayerCache.ClearAll()
	print("[PlayerCache] Cleared all cached player data.")
end


