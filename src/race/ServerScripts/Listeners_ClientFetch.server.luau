-- ServerScriptService/GetDataServer.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local fetchTrackQueue = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchTrackQueue")
local fetchVehicles = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchVehicles")
local getVehicleName = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("GetVehicleName")
local placeBet = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("PlaceBet")
local fetchBets = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchBets")
local joinRace = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("JoinRace")
local getNotifications = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("GetNotifications")
local fetchPlayer = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchPlayer")
local backToGarage = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("BackToGarage")
local ToggleMusic = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("ToggleMusic")
local ServerData = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("ServerData"))
local GameServiceApi = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("GameApiService"))
local Billboard = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Billboard"))
local SERVER_ID = game.JobId ~= "" and game.JobId or "local-server"-- You may need to adjust this based on your server configuration


-- Respond when client invokes FetchTrackQueue
fetchTrackQueue.OnServerInvoke = function(player, track)
	return ServerData.GetRaceQueueForTrack(SERVER_ID, track)
end


-- Respond when client invokes FetchVehicles
fetchVehicles.OnServerInvoke = function(player)
	if not player or not player.UserId then
		warn("[ClientFetch] FetchVehicles: missing player or UserId")
		return nil
	end

	print("[ClientFetch] Fetching vehicles for player", player.Name, "(", player.UserId, ")")
	return ServerData.GetPlayerVehicles(player.UserId)
end


getVehicleName.OnServerInvoke = function(player, vehicleId)
	return ServerData.GetVehicleName(vehicleId)
end


joinRace.OnServerInvoke = function(player, raceId, vehicleId)
	GameServiceApi.JoinRace(raceId, vehicleId)
	ServerData.ClearRaceQueue(SERVER_ID)
	ServerData.RemovePlayerVehicles(player.UserId)
	local data = GameServiceApi.GetPlayerData(player.UserId)
	player:SetAttribute("Money", data.money)

	-- Trigger immediate billboard update to show the player in the race
	Billboard.UpdateAllTracks()
	print("[ClientFetch] Triggered billboard update after player joined race")
end


placeBet.OnServerInvoke = function(player, amount, raceId, vehicleId)
	-- Convert amount to number if it's a string
	local numAmount = tonumber(amount) or 0
	GameServiceApi.CreateBet(player.UserId, raceId, vehicleId, numAmount)
end


fetchBets.OnServerInvoke = function(player)
	if not player or not player.UserId then
		warn("[ClientFetch] FetchBets: missing player or UserId")
		return {}
	end

	print("[ClientFetch] Fetching bets for player", player.Name, "(", player.UserId, ")")
	return GameServiceApi.GetPlayerBets(player.UserId) or {}
end


getNotifications.OnServerInvoke = function(player)
	return ServerData.GetPlayerNotifications(player.UserId)
end


fetchPlayer.OnServerInvoke = function(player)
	local data = GameServiceApi.GetPlayerData(player.UserId)
	player:SetAttribute("Money", data.money)
end


-- Respond when client invokes BackToGarage
backToGarage.OnServerInvoke = function(player)
	if not player then
		warn("[ClientFetch] BackToGarage: missing player")
		return false
	end

	-- Placeholder for garage place ID - replace with actual garage place ID
	local GARAGE_PLACE_ID = 87661660273443 -- TODO: Replace with actual garage place ID

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


-- Respond when client invokes ToggleMusic
ToggleMusic.OnServerInvoke = function(player)
	-- Get current player data from cache
	local playerData = ServerData.GetPlayerData(player.UserId)
	-- Handle music attribute properly - false is a valid value
	local currentMusic = playerData.player.music
	if currentMusic == nil then
		currentMusic = true
	end

	-- Toggle the music value
	local newMusicValue = not currentMusic

	-- Update backend
	local result = GameServiceApi.UpdatePlayerMusic(player.UserId, newMusicValue)

	-- Clear the player cache so it will be refreshed on next access
	ServerData.ClearPlayerData(player.UserId)

	-- Return the new music value
	if result and result.success then
		-- Update the player attribute
		player:SetAttribute("Music", result.music)
		return result.music
	else
		return currentMusic -- Return current value if update failed
	end
end