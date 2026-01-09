local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChooseFirstCarEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ChooseFirstCarEvent")
local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
local PlayerCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Player_PlayerCache"))

ChooseFirstCarEvent.OnServerEvent:Connect(function(player, carName)
	if typeof(carName) ~= "string" then return end
	local hasChosenCar = player:GetAttribute("has_chosen_first_car") or false
	if hasChosenCar then
		return
	end
	local result = ApiService.ChooseFirstCar(player, carName)

	if result then
		player:SetAttribute("has_chosen_first_car", true)
		PlayerCache.Clear(player.UserId)
		print(player.Name .. " chose first car:", carName)
	else
		warn("ChooseFirstCar API failed for " .. player.Name)
	end
end)