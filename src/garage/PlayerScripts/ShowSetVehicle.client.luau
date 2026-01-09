-- StarterPlayerScripts/AreaIconClient.local.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ev = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowSetCar")
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("BaseGui"):WaitForChild("Canvas"):WaitForChild("Bottom"):WaitForChild("SetVehicleButton") -- ScreenGui
gui.Visible = false

ev.OnClientEvent:Connect(function(show, padName)
	gui.Visible = show == true
	gui:SetAttribute("padTrigger", padName)
end)