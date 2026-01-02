local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ShowGuiEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowTeleport")
local backToGarage = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("BackToGarage")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ReplicaUtils"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("Teleport"):WaitForChild("Dialog")
local garageButton = Utils.findDescendantByName(mainGui, "Garage")

 
ShowGuiEvent.OnClientEvent:Connect(function(show)
	mainGui.Visible = show == true
end)


garageButton.MouseButton1Click:Connect(function()
	backToGarage:InvokeServer()
end)