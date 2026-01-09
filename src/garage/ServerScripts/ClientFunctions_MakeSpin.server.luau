local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
local postSpin = ReplicatedStorage:WaitForChild("Player"):WaitForChild("MakeSpin")
local PlayerCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Player_PlayerCache"))

-- Spin costs by type
local SPIN_COSTS = {
	BlueprintTemplate = 100,
	MaterialTemplate = 50,
	PartTemplate = 1000,
}

postSpin.OnServerInvoke = function(player, spinType)
	-- Validate spin type and get cost
	local cost = SPIN_COSTS[spinType]
	if not cost then
		warn("[MakeSpin] Invalid spin type:", spinType)
		return { success = false, error = "Invalid spin type" }
	end

	-- Get player's current money from cache
	local playerData = PlayerCache.Get(player.UserId)
	local playerMoney = playerData and playerData.player and playerData.player.money or 0
	playerMoney = tonumber(playerMoney) or 0

	-- Validate player has enough money
	if playerMoney < cost then
		warn("[MakeSpin] Player", player.Name, "has insufficient funds:", playerMoney, "< required:", cost)
		return { success = false, error = "Insufficient funds" }
	end

	-- Process the spin
	local result = ApiService.spinWheel(player.UserId, spinType)
	PlayerCache.Clear(player.UserId)
	return result
end