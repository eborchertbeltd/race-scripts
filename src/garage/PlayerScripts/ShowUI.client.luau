-- StarterPlayerScripts/AreaIconClient.local.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ev = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowMaterialUI")
local blueprintEv = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowBlueprintUI");
local partEv = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowPartUI")
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("MaterialUI"):WaitForChild("Window")
local blueprintGui = player:WaitForChild("PlayerGui"):WaitForChild("BlueprintUI"):WaitForChild("Window")
local partGui = player:WaitForChild("PlayerGui"):WaitForChild("PartUI"):WaitForChild("Window")
local craftingUI = player:WaitForChild("PlayerGui"):WaitForChild("CraftingUI"):WaitForChild("Window")
local craftingEV = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowCraftingUI")
local showBuildCar = player:WaitForChild("PlayerGui"):WaitForChild("BaseGui"):WaitForChild("Canvas"):WaitForChild("Frame"):WaitForChild("VehicleSetup")
local showBuildEV = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowBuildCar")
local showSkinUI = player:WaitForChild("PlayerGui"):WaitForChild("BaseGui"):WaitForChild("Canvas"):WaitForChild("Frame"):WaitForChild("SetSkin")
local showSkinEV = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowSkin")
local purchaseSkinUI = player:WaitForChild("PlayerGui"):WaitForChild("PurchaseSkinUI"):WaitForChild("Window")
local showPurchaseSkinUI = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowPurchaseSkinUI")
local showPartUI = player:WaitForChild("PlayerGui"):WaitForChild("BaseGui"):WaitForChild("Canvas"):WaitForChild("Frame"):WaitForChild("PartsButton")
gui.Visible = false
blueprintGui.Visible = false
partGui.Visible = false
craftingUI.Visible = false
showBuildCar.Visible = false
showSkinUI.Visible = false
showPartUI.Visible = false

ev.OnClientEvent:Connect(function(show, _)
	gui.Visible = show == true
end)


blueprintEv.OnClientEvent:Connect(function(show, _)
	blueprintGui.Visible = show == true
end)


partEv.OnClientEvent:Connect(function(show, _)
	partGui.Visible = show == true
end)


craftingEV.OnClientEvent:Connect(function(show, _)
	craftingUI.Visible = show == true
end)


showBuildEV.OnClientEvent:Connect(function(show, _)
	showBuildCar.Visible = show == true
	showPartUI.Visible = show == true
end)

showSkinEV.OnClientEvent:Connect(function(show, _)
	showSkinUI.Visible = show == true
end)

showPurchaseSkinUI.OnClientEvent:Connect(function(show, _)
	purchaseSkinUI.Visible = show == true
end)