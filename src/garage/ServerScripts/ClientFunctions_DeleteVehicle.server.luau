local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
local deleteVehicle = ReplicatedStorage:WaitForChild("Player"):WaitForChild("DeleteVehicle")
local PlayerCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Player_PlayerCache"))
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))
local makingCall = {}


deleteVehicle.OnServerInvoke = function(player, vehicleId, slottedNumber)
	-- any game state updates here…
	if not makingCall[vehicleId] then
		makingCall[vehicleId] = true
		local result = ApiService.DeleteVehicle(vehicleId)
		PlayerCache.Clear(player.UserId)
		makingCall[vehicleId] = nil
		Utils.removeCarFromGarage(player, slottedNumber)
		return result
	end
end