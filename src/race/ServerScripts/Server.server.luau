-- ServerScriptService/Server.lua
-- Main server script that handles player connections and disconnections

local Players = game:GetService("Players")
local ServerData = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("ServerData"))
local GameServiceApi = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("GameApiService"))

-- Handle player connection
local function onPlayerAdded(player)
	print("[Server] Player", player.Name, "(", player.UserId, ") is connecting")

	-- Fetch player data from API
	local data = GameServiceApi.GetPlayerData(player.UserId)

	if not data then
		warn("[Server] Failed to get player data for", player.Name)
		return
	end

	-- Set player attributes
	player:SetAttribute("Money", data.money)

	-- Handle music attribute properly - false is a valid value
	if data.music ~= nil then
		player:SetAttribute("Music", data.music)
	else
		player:SetAttribute("Music", true)
	end

	print("[Server] Set attributes for player", player.Name, "- Money:", data.money, "Music:", data.music)
end

-- Handle player disconnection
local function onPlayerRemoving(player)
	if player and player.UserId then
		print("[Server] Player", player.Name, "(", player.UserId, ") is disconnecting")

		-- Remove player's vehicles from storage
		ServerData.RemovePlayerVehicles(player.UserId)

		print("[Server] Cleaned up storage for player", player.Name)
	end
end

-- Connect player events
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

print("[Server] Server script loaded - listening for player connections and disconnections")
