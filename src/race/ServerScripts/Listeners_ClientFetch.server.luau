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

-- Create GetVehicleTrackAssignments RemoteFunction if it doesn't exist
local remoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local getVehicleTrackAssignments = remoteFunctions:FindFirstChild("GetVehicleTrackAssignments")
if not getVehicleTrackAssignments then
	getVehicleTrackAssignments = Instance.new("RemoteFunction")
	getVehicleTrackAssignments.Name = "GetVehicleTrackAssignments"
	getVehicleTrackAssignments.Parent = remoteFunctions
end

-- Create JoinAllTracks RemoteFunction if it doesn't exist
local joinAllTracks = remoteFunctions:FindFirstChild("JoinAllTracks")
if not joinAllTracks then
	joinAllTracks = Instance.new("RemoteFunction")
	joinAllTracks.Name = "JoinAllTracks"
	joinAllTracks.Parent = remoteFunctions
end

-- Create GetPlayerCache RemoteFunction if it doesn't exist (for InventoryUI)
local getPlayerCache = remoteFunctions:FindFirstChild("GetPlayerCache")
if not getPlayerCache then
	getPlayerCache = Instance.new("RemoteFunction")
	getPlayerCache.Name = "GetPlayerCache"
	getPlayerCache.Parent = remoteFunctions
end

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

	return ServerData.GetPlayerVehicles(player.UserId)
end


getVehicleName.OnServerInvoke = function(player, vehicleId)
	return ServerData.GetVehicleName(vehicleId)
end


-- JoinRace supports two signatures:
-- Legacy: (raceId, vehicleId) - joins a specific race by ID
-- New: (vehicleId, track, level) - finds or creates a race for the track/level
joinRace.OnServerInvoke = function(player, arg1, arg2, arg3)
	local result
	if arg3 then
		-- New signature: (vehicleId, track, level)
		local vehicleId = arg1
		local track = arg2
		local level = arg3
		result = GameServiceApi.JoinRaceByTrack(vehicleId, track, level, SERVER_ID)
	else
		-- Legacy signature: (raceId, vehicleId)
		local raceId = arg1
		local vehicleId = arg2
		result = GameServiceApi.JoinRace(raceId, vehicleId)
	end

	ServerData.ClearRaceQueue(SERVER_ID)
	ServerData.RemovePlayerVehicles(player.UserId)
	local data = GameServiceApi.GetPlayerData(player.UserId)
	player:SetAttribute("Money", data.money)

	-- Trigger immediate billboard update to show the player in the race
	Billboard.UpdateAllTracks()

	return result
end


-- Get which tracks a vehicle is currently queued in
getVehicleTrackAssignments.OnServerInvoke = function(player, vehicleId)
	if not vehicleId then
		warn("[ClientFetch] GetVehicleTrackAssignments: missing vehicleId")
		return nil
	end
	return GameServiceApi.GetVehicleTrackAssignments(vehicleId)
end


-- Join a vehicle to all four tracks at once
joinAllTracks.OnServerInvoke = function(player, vehicleId, level)
	if not vehicleId or not level then
		warn("[ClientFetch] JoinAllTracks: missing vehicleId or level")
		return nil
	end

	local result = GameServiceApi.JoinAllTracks(vehicleId, level, SERVER_ID)

	-- Clear caches and update player money
	ServerData.ClearRaceQueue(SERVER_ID)
	ServerData.RemovePlayerVehicles(player.UserId)
	local data = GameServiceApi.GetPlayerData(player.UserId)
	if data then
		player:SetAttribute("Money", data.money)
	end

	-- Trigger billboard update
	Billboard.UpdateAllTracks()

	return result
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

	-- Teleport the player to the garage
	local success, errorMessage = pcall(function()
		game:GetService("TeleportService"):Teleport(GARAGE_PLACE_ID, player)
	end)

	if success then
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


-- Respond when client invokes GetPlayerCache (for InventoryUI)
getPlayerCache.OnServerInvoke = function(player)
	if not player or not player.UserId then
		warn("[ClientFetch] GetPlayerCache: missing player or UserId")
		return nil
	end

	-- Get vehicles and inventory from API
	local vehicles = ServerData.GetPlayerVehicles(player.UserId)
	local inventory = GameServiceApi.GetPlayerInventory(player.UserId)

	return {
		vehicles = vehicles or {},
		inventory = inventory or {}
	}
end