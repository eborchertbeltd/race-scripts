local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Player_PlayerCache"))
local GetPlayerCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetPlayerCache")


GetPlayerCache.OnServerInvoke = function(player)
	return PlayerCache.Get(player.UserId) or {}
end