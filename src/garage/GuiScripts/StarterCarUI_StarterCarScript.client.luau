local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ShowGuiEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowStarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("StarterCarUI")
local gui = mainGui:WaitForChild("Window")

ShowGuiEvent.OnClientEvent:Connect(function()
	gui.Visible = true
end)