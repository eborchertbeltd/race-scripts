local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ShowGuiEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowTeleport")
local backToGarage = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("BackToGarage")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ReplicaUtils"))
local RaceSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RaceSoundUtils"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("Teleport"):WaitForChild("Dialog")
local garageButton = Utils.findDescendantByName(mainGui, "Garage")


ShowGuiEvent.OnClientEvent:Connect(function(show)
	mainGui.Visible = show == true
end)


garageButton.MouseButton1Click:Connect(function()
	RaceSoundUtils.PlayButtonPressed()
	-- Create spinner to replace garageButton
	local spinnerFrame = Instance.new("Frame")
	spinnerFrame.Name = "SpinnerFrame"
	spinnerFrame.Size = UDim2.new(1, 0, 1, 0)
	spinnerFrame.Position = UDim2.new(0, 0, 0, 0)
	spinnerFrame.BackgroundTransparency = 1
	spinnerFrame.BorderSizePixel = 0
	spinnerFrame.ZIndex = garageButton.ZIndex + 1

	-- Create the spinning image
	local spinnerImage = Instance.new("ImageLabel")
	spinnerImage.Name = "SpinnerImage"
	spinnerImage.Size = UDim2.new(0, 30, 0, 30)
	spinnerImage.Position = UDim2.new(0.5, -15, 0.5, -15)
	spinnerImage.BackgroundTransparency = 1
	spinnerImage.Image = "rbxassetid://101716378951252"
	spinnerImage.ZIndex = spinnerFrame.ZIndex + 1
	spinnerImage.Parent = spinnerFrame

	-- Create rotation tween
	local rotationTween = TweenService:Create(
		spinnerImage,
		TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{Rotation = 360}
	)

	-- Hide button text and add spinner
	local buttonText = garageButton:FindFirstChild("TextLabel")
	if buttonText then
		buttonText.Visible = false
	end
	spinnerFrame.Parent = garageButton
	garageButton.Active = false
	rotationTween:Play()
	backToGarage:InvokeServer()
end)