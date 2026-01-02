local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OpenSkinEvent = ReplicatedStorage:WaitForChild("BindableEvents"):WaitForChild("OpenSkin")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GetPlayerCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetPlayerCache")
local GetDataCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetCache")
local UpdateVehicleSkin = ReplicatedStorage:WaitForChild("Player"):WaitForChild("UpdateVehicleSkin")
local UpdateVehicleColor = ReplicatedStorage:WaitForChild("Player"):WaitForChild("UpdateVehicleColor")
local UpdateGarage = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("UpdateGarage")
local mainGui = playerGui:WaitForChild("SkinGui"):WaitForChild("Window")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))
local GarageSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GarageSoundUtils"))
local RunService = game:GetService("RunService")
-- GUI references
local selectionFrame = mainGui:WaitForChild("Content"):WaitForChild("Body"):WaitForChild("ItemList")
local vehicleTemplate = Utils.findDescendantByName(selectionFrame, "VehicleTemplate")
local picker = mainGui:WaitForChild("Content"):WaitForChild("Picker")
local pickerFrame = picker:WaitForChild("Frame")
local skinOptions = pickerFrame:WaitForChild("SkinOptions")
local colorOptions = pickerFrame:WaitForChild("ColorOptions")
local selectionTemplate = Utils.findDescendantByName(skinOptions, "VehicleTemplate")
local selectCarFrame = picker:WaitForChild("Selected")
local backButton = selectCarFrame:WaitForChild("Back")
local currentTab = "Body"
local getItemOfType
local loadItem
local loadItems
local cache = false
local loaded = false
local swapping = false

vehicleTemplate.Visible = false
selectionTemplate.Visible = false

local selectedVehicle = nil

-- Helper function to reload the selected vehicle display after skin/color change
local function reloadSelectedVehicle()
	-- Clear cache to force refetch
	cache = false
	cache = GetPlayerCache:InvokeServer()

	if not cache or not cache.vehicles then
		warn("Failed to refetch cache")
		return
	end

	-- Find the updated vehicle data by id
	local updatedVehicle = nil
	for _, v in ipairs(cache.vehicles) do
		if v.id == selectedVehicle.id then
			updatedVehicle = v
			break
		end
	end

	if not updatedVehicle then
		warn("Could not find vehicle in updated cache:", selectedVehicle.id)
		return
	end

	-- Update selectedVehicle reference
	selectedVehicle = updatedVehicle

	-- Clear existing content in selectCarFrame (keep Back button and layout elements)
	for _, child in ipairs(selectCarFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Clone vehicleTemplate and load with updated vehicle data
	local selectedItem = vehicleTemplate:Clone()
	selectedItem = loadItem(selectedItem, selectedVehicle, false, false)
	selectedItem.Parent = selectCarFrame
end

local vehicle = {
	Body = false,
	Engine = false,
	Exhaust = false,
	Transmission = false,
	Tire = false,
	Id = false,
	Name = false,
	slotted_number = false
}


local function getItemById(itemId) 
	local data = GetDataCache:InvokeServer("Part", itemId)
	return data
end


-- Apply custom color to Body and Wheel parts of a model (for ViewportFrame thumbnails)
local function applyViewportColor(model, colorString)
	if not colorString or colorString == "" then
		return
	end

	local color = Utils.parseColorString(colorString)
	if not color then
		return
	end

	-- Find and color all Body and Wheel parts
	for _, descendant in ipairs(model:GetDescendants()) do
		if (descendant.Name == "Body" or descendant.Name == "Wheel") and descendant:IsA("BasePart") then
			descendant.Color = color
		end
	end
end


-- Color palette for vehicle customization
local colorPalette = {
	{name = "White", color = Color3.fromRGB(255, 255, 255)},
	{name = "Black", color = Color3.fromRGB(25, 25, 25)},
	{name = "Silver", color = Color3.fromRGB(192, 192, 192)},
	{name = "Gray", color = Color3.fromRGB(128, 128, 128)},
	{name = "Red", color = Color3.fromRGB(200, 30, 30)},
	{name = "Dark Red", color = Color3.fromRGB(120, 20, 20)},
	{name = "Orange", color = Color3.fromRGB(255, 140, 0)},
	{name = "Yellow", color = Color3.fromRGB(255, 215, 0)},
	{name = "Lime", color = Color3.fromRGB(50, 205, 50)},
	{name = "Green", color = Color3.fromRGB(34, 139, 34)},
	{name = "Dark Green", color = Color3.fromRGB(0, 100, 0)},
	{name = "Cyan", color = Color3.fromRGB(0, 200, 200)},
	{name = "Light Blue", color = Color3.fromRGB(100, 149, 237)},
	{name = "Blue", color = Color3.fromRGB(30, 90, 200)},
	{name = "Dark Blue", color = Color3.fromRGB(25, 25, 112)},
	{name = "Purple", color = Color3.fromRGB(138, 43, 226)},
	{name = "Pink", color = Color3.fromRGB(255, 105, 180)},
	{name = "Brown", color = Color3.fromRGB(139, 69, 19)},
	-- Additional complementary colors
	{name = "Crimson", color = Color3.fromRGB(220, 20, 60)},
	{name = "Coral", color = Color3.fromRGB(255, 127, 80)},
	{name = "Gold", color = Color3.fromRGB(218, 165, 32)},
	{name = "Amber", color = Color3.fromRGB(255, 191, 0)},
	{name = "Olive", color = Color3.fromRGB(107, 142, 35)},
	{name = "Mint", color = Color3.fromRGB(152, 255, 152)},
	{name = "Teal", color = Color3.fromRGB(0, 128, 128)},
	{name = "Turquoise", color = Color3.fromRGB(64, 224, 208)},
	{name = "Navy", color = Color3.fromRGB(0, 0, 128)},
	{name = "Indigo", color = Color3.fromRGB(75, 0, 130)},
	{name = "Violet", color = Color3.fromRGB(148, 0, 211)},
	{name = "Magenta", color = Color3.fromRGB(255, 0, 255)},
	{name = "Rose", color = Color3.fromRGB(255, 0, 127)},
	{name = "Burgundy", color = Color3.fromRGB(128, 0, 32)},
	{name = "Tan", color = Color3.fromRGB(210, 180, 140)},
	{name = "Beige", color = Color3.fromRGB(245, 245, 220)},
	{name = "Charcoal", color = Color3.fromRGB(54, 69, 79)},
	{name = "Pearl", color = Color3.fromRGB(240, 234, 214)},
}


local function selectColor(colorData)
	if not selectedVehicle then
		warn("No vehicle selected")
		return
	end

	local r, g, b = math.floor(colorData.color.R * 255), math.floor(colorData.color.G * 255), math.floor(colorData.color.B * 255)
	local colorString = r .. "," .. g .. "," .. b

	print("Updating color to:", colorData.name, "(" .. colorString .. ") for vehicle:", selectedVehicle.id)

	local result = UpdateVehicleColor:InvokeServer(selectedVehicle.id, colorString)

	if result and result.success then
		print("Color updated successfully!")
		-- Reload the selected vehicle display with updated data
		reloadSelectedVehicle()
		UpdateGarage:FireServer()
	else
		warn("Failed to update color:", result and result.error or "Unknown error")
	end
end


local function populateColorOptions()
	-- Clear existing color buttons (keep layout elements)
	for _, child in ipairs(colorOptions:GetChildren()) do
		if child:IsA("TextButton") or child:IsA("ImageButton") then
			child:Destroy()
		end
	end

	-- Create color buttons
	for i, colorData in ipairs(colorPalette) do
		local button = Instance.new("TextButton")
		button.Name = colorData.name
		button.Size = UDim2.new(0, 40, 0, 40)
		button.BackgroundColor3 = colorData.color
		button.BorderSizePixel = 2
		button.BorderColor3 = Color3.fromRGB(60, 60, 60)
		button.Text = ""
		button.AutoButtonColor = true
		button.Parent = colorOptions

		-- Add corner rounding
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button

		-- Add hover/selected stroke
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 0
		stroke.Parent = button

		-- Connect click handler
		button.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlaySpray()
			selectColor(colorData)
		end)

		-- Hover effect
		button.MouseEnter:Connect(function()
			stroke.Thickness = 2
		end)

		button.MouseLeave:Connect(function()
			stroke.Thickness = 0
		end)
	end
end


local function selectSkin(modelName)
	if not selectedVehicle then
		warn("No vehicle selected")
		return
	end

	print("Updating skin to:", modelName, "for vehicle:", selectedVehicle.id)

	local result = UpdateVehicleSkin:InvokeServer(selectedVehicle.id, modelName)

	if result and result.success then
		print("Skin updated successfully!")
		-- Reload the selected vehicle display with updated data
		reloadSelectedVehicle()
		UpdateGarage:FireServer()
	else
		warn("Failed to update skin:", result and result.error or "Unknown error")
	end
end


local function loadSkinOption(item, modelName)
	-- Set the name labels
	local nameFrame = Utils.findDescendantByName(item, "Name")
	local itemLabel = Utils.findDescendantByName(nameFrame, "ItemLabel")
	local itemLabelStroke = Utils.findDescendantByName(nameFrame, "ItemLabelStroke")
	item.Name = modelName
	itemLabel.Text = modelName
	itemLabelStroke.Text = modelName

	-- Add thumbnail to ViewportFrame using model name
	local itemImage = Utils.findDescendantByName(item, "ViewportFrame")
	if itemImage then
		local carsFolder = ReplicatedStorage:WaitForChild("Cars")
		local carModel = carsFolder:FindFirstChild(modelName)
		if carModel then
			local carClone = carModel:Clone()
			carClone.Parent = itemImage

			local viewportCamera = Instance.new("Camera")
			viewportCamera.Parent = itemImage

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

			itemImage.CurrentCamera = viewportCamera
		end
	end

	item.Visible = true
	return item
end


local function switchVehicle(vehicleOwned) 
	selectedVehicle = vehicleOwned
	selectionFrame.Visible = false
	picker.Visible = true

	-- Clear existing content in selectCarFrame (keep Back button and layout elements)
	for _, child in ipairs(selectCarFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Clone vehicleTemplate and load with selected vehicle data
	local selectedItem = vehicleTemplate:Clone()
	selectedItem = loadItem(selectedItem, vehicleOwned, false, false)
	selectedItem.Parent = selectCarFrame

	-- Clear existing content in skinOptions
	for _, child in ipairs(skinOptions:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UIGridLayout")  and child.Visible then
			child:Destroy()
		end
	end

	-- Build list of available skins (owned skins only)
	local skinModels = {}
	local addedSkins = {}

	-- Add owned skins from cache
	if cache and cache.skins then
		for _, ownedSkin in ipairs(cache.skins) do
			-- vehicle_skin_details contains the full skin data including name
			local skinName = ownedSkin.vehicle_skin_details and ownedSkin.vehicle_skin_details.name
			if skinName and not addedSkins[skinName] then
				table.insert(skinModels, skinName)
				addedSkins[skinName] = true
				print("[SkinGui] Added owned skin:", skinName)
			end
		end
	end

	-- Log if no skins found
	if #skinModels == 0 then
		warn("[SkinGui] Player has no owned skins in cache")
	end

	-- Create skin option buttons
	for _, modelName in ipairs(skinModels) do
		local skinItem = selectionTemplate:Clone()
		skinItem = loadSkinOption(skinItem, modelName)

		local button = Utils.findDescendantByName(skinItem, "TextButton")
		button.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayTightening()
			selectSkin(modelName)
		end)

		skinItem.Parent = skinOptions
	end

	-- Update canvas size for skinOptions after adding items
	RunService.RenderStepped:Wait()
	local grid = skinOptions:FindFirstChildOfClass("UIGridLayout")
	local padding = skinOptions:FindFirstChildOfClass("UIPadding")
	if grid then
		local totalHeight = grid.AbsoluteContentSize.Y
		if padding then
			totalHeight += padding.PaddingTop.Offset
			totalHeight += padding.PaddingBottom.Offset
		end
		skinOptions.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
	end

	-- Populate color options
	populateColorOptions()
end


getItemOfType = function(tabType)
	if not cache then
		cache = GetPlayerCache:InvokeServer()
	end
	if not cache then
		warn("No PlayerCache entry found for player:", player.UserId)
		return
	end
	print(cache)
	if tabType == 'Vehicles' then
		local tabData = cache["vehicles"]
		if not tabData or type(tabData) ~= "table" then
			warn("No data for tab:", currentTab)
			return
		end
		return tabData
	else
		--local tabData = cache["inventory"]
		--local values = {}
		--for _, value in tabData do
		--	if value["category"] == inventoryMap[tabType] then
		--		table.insert(values, value)
		--	end
		--end
		--return values
	end
end


loadItem = function(item, entry, notAvailable, notReferenced)
	local name = entry.name
	local level = entry.level
	Utils.switchColorIcon(item, level)
	local nameFrame = Utils.findDescendantByName(item, "Name")
	local itemLabel = Utils.findDescendantByName(nameFrame, "ItemLabel")
	local itemLabelStroke = Utils.findDescendantByName(nameFrame, "ItemLabelStroke")
	local itemImage = Utils.findDescendantByName(item, "ViewportFrame")
	item.Name = name
	itemLabel.Text = name
	itemLabelStroke.Text = name

	-- Add thumbnail to ViewportFrame using model name
	if itemImage then
		local carsFolder = ReplicatedStorage:WaitForChild("Cars")
		local carModel = carsFolder:FindFirstChild(entry.skin)
		if carModel then
			local carClone = carModel:Clone()
			carClone.Parent = itemImage

			-- Apply custom color to the thumbnail if vehicle has a color set
			applyViewportColor(carClone, entry.color)

			local viewportCamera = Instance.new("Camera")
			viewportCamera.Parent = itemImage

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

			itemImage.CurrentCamera = viewportCamera
		end
	end
	item.Visible = true
	return item
end


loadItems = function()
	mainGui.Visible = true

	-- Clear existing vehicle items (but keep the invisible template)
	for _, child in ipairs(selectionFrame:GetChildren()) do
		if child:IsA("Frame") and child.Visible then
			child:Destroy()
		end
	end

	local tabData = getItemOfType("Vehicles")
	if not tabData then
		warn("No data for tab:", currentTab)
		return
	end

	for _, entry in ipairs(tabData) do
		local item = vehicleTemplate:Clone()
		item = loadItem(item, entry, false, false)
		local button = Utils.findDescendantByName(item, "TextButton")
		button.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			switchVehicle(entry)
		end)
		item.Parent = selectionFrame
	end
	RunService.RenderStepped:Wait()
	local grid = selectionFrame:FindFirstChildOfClass("UIGridLayout")
	local padding = selectionFrame:FindFirstChildOfClass("UIPadding")

	local totalHeight = grid.AbsoluteContentSize.Y
	if padding then
		totalHeight += padding.PaddingTop.Offset
		totalHeight += padding.PaddingBottom.Offset
	end
	selectionFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
end


local function firstLoad()
	loadItems()
	mainGui.Visible = true
	selectionFrame.Visible = true
	picker.Visible = false
end


-- Back button handler - return to vehicle selection menu
backButton.MouseButton1Click:Connect(function()
	GarageSoundUtils.PlayButtonPressed()
	selectedVehicle = nil
	picker.Visible = false
	selectionFrame.Visible = true
	-- Reload items to show any updates
	loadItems()
end)


OpenSkinEvent.Event:Connect(firstLoad)