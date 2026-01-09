local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OpenSetCarEvent = ReplicatedStorage:WaitForChild("BindableEvents"):WaitForChild("OpenSetCar")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GetPlayerCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetPlayerCache")
local mainGui = playerGui:WaitForChild("SetCar"):WaitForChild("Window")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))
local GarageSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GarageSoundUtils"))
local RunService = game:GetService("RunService")

-- GUI references
local itemsFrame = mainGui:WaitForChild("Content"):WaitForChild("Body")
local itemList = itemsFrame:WaitForChild("ItemList")
local vehicleTemplate = itemList:WaitForChild("VehicleTemplate")
local cancel = itemList:WaitForChild("Cancel")

-- Hide templates
vehicleTemplate.Visible = false
cancel.Visible = true

local colorIconScheme = {
	Common = {
		icon = "rbxassetid://85396582444630",
		bottom = Color3.fromRGB(0, 62, 117),
		top = Color3.fromRGB(6, 123, 202),
		startKey = Color3.fromRGB(0, 83, 157),
		endKey = Color3.fromRGB(0, 105, 176)
	},
	Rare = {
		icon = "rbxassetid://82301679193973",
		bottom = Color3.fromRGB(29, 126, 2),
		top = Color3.fromRGB(79, 213, 2),
		startKey = Color3.fromRGB(51, 172, 41),
		endKey = Color3.fromRGB(66, 192, 24)
	},
	Epic = {
		icon = "rbxassetid://89746368504335",
		bottom = Color3.fromRGB(98, 27, 167),
		top = Color3.fromRGB(186, 50, 226),
		startKey = Color3.fromRGB(133, 26, 193),
		endKey = Color3.fromRGB(157, 42, 218)
	},
	Legendary = {
		icon = "rbxassetid://77146147741356",
		bottom = Color3.fromRGB(236, 116, 0),
		top = Color3.fromRGB(255, 219, 49),
		startKey = Color3.fromRGB(247, 160, 19),
		endKey = Color3.fromRGB(255, 192, 38)
	}
}


-- Clear previous items
local function clearItems()
	for _, child in pairs(itemList:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "VehicleTemplate" and child.Name ~= "Cancel" then
			child:Destroy()
		end
	end
end


local function switchColorIcon(item, level)
	local background = Utils.findDescendantByName(item, "Background")
	local bottom = Utils.findDescendantByName(background, "Bottom")
	bottom.BackgroundColor3 = colorIconScheme[level]["bottom"]
	local color = Utils.findDescendantByName(background, "Color")
	local top = Utils.findDescendantByName(color, "Top")
	top.BackgroundColor3 = colorIconScheme[level]["top"]
	local levelItem = Utils.findDescendantByName(item, "Level")
	local imageLevel = Utils.findDescendantByName(levelItem, "ImageLabel")
	imageLevel.Image = colorIconScheme[level]["icon"]
	local bottomFrame = Utils.findDescendantByName(color, "Bottom")
	local bottomGradient = Utils.findDescendantByName(bottomFrame, "UIGradient")
	bottomGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, colorIconScheme[level]["startKey"]),
		ColorSequenceKeypoint.new(1, colorIconScheme[level]["endKey"])
	})
end


local function getVehicles()
	local cache = GetPlayerCache:InvokeServer()
	if not cache then
		warn("No PlayerCache entry found for player:", player.UserId)
		return
	end

	local vehicles = cache["vehicles"]
	if not vehicles or type(vehicles) ~= "table" then
		warn("No vehicles data found in cache")
		return
	end

	return vehicles
end


local function setCar(key, vehicleId, unslot)
	local placeMeshEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SetCar")
	placeMeshEvent:FireServer("Car", key, vehicleId, unslot)
	mainGui.Visible = false
end


local function loadItems(key)
	cancel.Visible = true
	clearItems()

	local slot = tonumber(key:match("%d+$"))
	local vehicles = getVehicles()
	if not vehicles then
		warn("No vehicles data")
		return
	end

	local currentlySlotted = false
	local unslotId = ""

	for _, vehicle in ipairs(vehicles) do
		if not vehicle.slotted then
			local item = vehicleTemplate:Clone()
			item.Name = vehicle.name or "Vehicle"
			item:SetAttribute("vehicleId", vehicle.id)

			-- Set up the click handler
			local button = Utils.findDescendantByName(item, "TextButton")
			button.MouseButton1Click:Connect(function()
				GarageSoundUtils.PlayRev()
				setCar(key, vehicle.id, false)
			end)

			-- Apply color scheme based on level
			local level = vehicle.level
			switchColorIcon(item, level)

			-- Set the name labels
			local itemLabel = Utils.findDescendantByName(item, "ItemLabel")
			local itemLabelStroke = Utils.findDescendantByName(item, "ItemLabelStroke")
			itemLabel.Text = vehicle.name or "Unnamed"
			itemLabelStroke.Text = vehicle.name or "Unnamed"

			-- Add thumbnail to ViewportFrame
			local thumbnail = Utils.findDescendantByName(item, "Thumbnail")
			if thumbnail then
				local carsFolder = ReplicatedStorage:WaitForChild("Cars")
				local carModel = carsFolder:FindFirstChild(vehicle.skin)
				if carModel then
					local carClone = carModel:Clone()
					carClone.Parent = thumbnail

					-- Apply custom color to the thumbnail if vehicle has a color set
					Utils.applyViewportColor(carClone, vehicle.color)

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
				end
			end

			item.Visible = true
			item.Parent = itemList
		else
			-- Check if this vehicle is slotted in the current pad
			if vehicle.slotted_number == slot then
				currentlySlotted = true
				unslotId = vehicle.id
			end
		end
	end

	-- Handle cancel button for unslotting
	if not currentlySlotted then
		cancel.Visible = false
	else
		local button = Utils.findDescendantByName(cancel, "TextButton")
		button.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayBrake()
			setCar(key, unslotId, true)
		end)
	end

	-- Adjust canvas size to fit all items
	RunService.RenderStepped:Wait()
	local grid = itemList:FindFirstChildOfClass("UIGridLayout")
	local padding = itemList:FindFirstChildOfClass("UIPadding")

	local totalHeight = grid.AbsoluteContentSize.Y
	if padding then
		totalHeight += padding.PaddingTop.Offset
		totalHeight += padding.PaddingBottom.Offset
	end

	itemList.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
	mainGui.Visible = true
end


local function firstLoad(spad)
	loadItems(spad)
end


OpenSetCarEvent.Event:Connect(firstLoad)
