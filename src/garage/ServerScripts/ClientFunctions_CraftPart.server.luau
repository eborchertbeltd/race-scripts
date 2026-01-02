local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
local postSpin = ReplicatedStorage:WaitForChild("Player"):WaitForChild("CraftPart")
local PlayerCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Player_PlayerCache"))

local madeCall = {}
postSpin.OnServerInvoke = function(player, robloxObjectId)
	-- any game state updates here…
	if not madeCall[player.UserId] then
		madeCall[player.UserId] = true
		local result = ApiService.craftItem(player.UserId, robloxObjectId)
		PlayerCache.Clear(player.UserId)
		madeCall[player.UserId] = nil
		return result
	end
end