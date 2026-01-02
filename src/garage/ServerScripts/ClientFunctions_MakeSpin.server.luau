local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
local postSpin = ReplicatedStorage:WaitForChild("Player"):WaitForChild("MakeSpin")
local PlayerCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Player_PlayerCache"))


postSpin.OnServerInvoke = function(player, spinType)
	-- any game state updates here…
	local result = ApiService.spinWheel(player.UserId, spinType)
	PlayerCache.Clear(player.UserId)
	return result
end