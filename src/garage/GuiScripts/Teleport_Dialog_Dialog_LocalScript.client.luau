local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ShowGuiEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowTeleport")
local toRaces = ReplicatedStorage:WaitForChild("Player"):WaitForChild("ToRaces")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("Teleport"):WaitForChild("Dialog")
local raceButton = Utils.findDescendantByName(mainGui, "Race")
local GarageSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GarageSoundUtils"))

 
ShowGuiEvent.OnClientEvent:Connect(function(show)
	mainGui.Visible = show == true
end)


raceButton.MouseButton1Click:Connect(function()
	GarageSoundUtils.PlayButtonPressed()
	-- Create spinner to replace raceButton
	local spinnerFrame = Instance.new("Frame")
	spinnerFrame.Name = "SpinnerFrame"
	spinnerFrame.Size = UDim2.new(1, 0, 1, 0)
	spinnerFrame.Position = UDim2.new(0, 0, 0, 0)
	spinnerFrame.BorderSizePixel = 0
	spinnerFrame.ZIndex = raceButton.ZIndex + 1

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
	local buttonText = raceButton:FindFirstChild("TextLabel")
	if buttonText then
		buttonText.Visible = false
	end
	spinnerFrame.Parent = raceButton
	raceButton.Active = false
	rotationTween:Play()
	toRaces:InvokeServer()
end)