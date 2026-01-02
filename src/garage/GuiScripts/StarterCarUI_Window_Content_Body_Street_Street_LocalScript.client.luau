local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ChooseFirstCarEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ChooseFirstCarEvent")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local button = playerGui:WaitForChild("StarterCarUI"):WaitForChild("Window"):WaitForChild("Content"):WaitForChild("Body"):WaitForChild("Street")

local function findParentByName(instance, name)
	local current = instance.Parent
	while current do
		if current.Name == name then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Load thumbnail when script loads
local function loadThumbnail()
	local thumbnail = Utils.findDescendantByName(button, "Thumbnail")
	if thumbnail and thumbnail:IsA("ViewportFrame") then
		local carsFolder = ReplicatedStorage:WaitForChild("Cars")
		local carModel = carsFolder:FindFirstChild("Pulse")
		if carModel then
			local carClone = carModel:Clone()
			carClone.Parent = thumbnail

			local viewportCamera = Instance.new("Camera")
			viewportCamera.Parent = thumbnail

			local thumbnailCFrame = carClone:FindFirstChild("ThumbnailCFrame")
			local thumbnailFOV = carClone:FindFirstChild("ThumbnailFOV")
			if thumbnailCFrame and thumbnailCFrame:IsA("CFrameValue") then
				viewportCamera.CFrame = thumbnailCFrame.Value
				if thumbnailFOV and thumbnailFOV:IsA("NumberValue") then
					viewportCamera.FieldOfView = thumbnailFOV.Value
				else
					viewportCamera.FieldOfView = 10
				end
			end

			thumbnail.CurrentCamera = viewportCamera
		else
			warn("[DragStartScript] Pulse car model not found in ReplicatedStorage.Cars")
		end
	else
		warn("[DragStartScript] Thumbnail ViewportFrame not found")
	end
end

-- Load the thumbnail on startup
loadThumbnail()

button.MouseButton1Click:Connect(function()
	ChooseFirstCarEvent:FireServer("Pulse")
	local window = findParentByName(script, "Window")
	if window and window:IsA("GuiObject") then
		window.Visible = false
	else
		warn("Window frame not found")
	end
end)

