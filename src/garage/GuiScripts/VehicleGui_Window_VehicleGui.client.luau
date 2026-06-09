local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local OpenVehicleEvent = ReplicatedStorage:WaitForChild("BindableEvents"):WaitForChild("OpenVehicle")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GetPlayerCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetPlayerCache")
local GetDataCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetCache")
local DeleteVehicle = ReplicatedStorage:WaitForChild("Player"):WaitForChild("DeleteVehicle")
local UpdateCreateVehicle = ReplicatedStorage:WaitForChild("Player"):WaitForChild("UpdateCreateVehicle")
local vehicleGui = playerGui:WaitForChild("VehicleGui")
local mainGui = vehicleGui:WaitForChild("Window")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))
local GarageSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GarageSoundUtils"))
local RunService = game:GetService("RunService")

-- Mobile detection
local function isMobileDevice()
	local touchEnabled = UserInputService.TouchEnabled
	local keyboardEnabled = UserInputService.KeyboardEnabled
	return touchEnabled and not keyboardEnabled
end
-- GUI references
local selectionFrame = mainGui:WaitForChild("Content"):WaitForChild("Body"):WaitForChild("ItemList")
local mainFrame = mainGui:WaitForChild("Content"):WaitForChild("Body"):WaitForChild("Main")
local tabs = mainGui:WaitForChild("Content"):WaitForChild("Body"):WaitForChild("Tabs")
local vehicleTemplate = Utils.findDescendantByName(selectionFrame, "VehicleTemplate")
local inventoryFrame = Utils.findDescendantByName(mainFrame, "Inventory")
local partTemplate = Utils.findDescendantByName(inventoryFrame, "PartTemplate")
local buildCar = Utils.findDescendantByName(selectionFrame, "BuildCar")
local engineTab = Utils.findDescendantByName(tabs, "Engine")
local bodyTab = Utils.findDescendantByName(tabs, "Body")
local exhaustTab = Utils.findDescendantByName(tabs, "Exhaust")
local transmissionTab = Utils.findDescendantByName(tabs, "Transmission")
local tiresTab = Utils.findDescendantByName(tabs, "Tires")
local textInput = Utils.findDescendantByName(mainFrame, "TextBox")

local currentTab = "Body"
local getItemOfType
local loadItem
local cache = false
local loaded = false
local clearInventory
local setInventory
local swapping = false
local tabButtons = {
	Body = false,
	Engine = false,
	Exhaust = false,
	Transmission = false,
	Tire = false
}
vehicleTemplate.Visible = false


local inventoryMap = {
	Blueprints = "BlueprintTemplate",
	Parts = "PartTemplate",
	Materials = "MaterialTemplate",
	Mods = false
}

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

textInput:GetPropertyChangedSignal("Text"):Connect(function()
	vehicle.Name = textInput.Text
	-- You could call ApiService or save to DataStore here
end)


textInput.FocusLost:Connect(function(enterPressed)
	vehicle.Name = textInput.Text
end)


local function clearPart(part)
	for _, child in pairs(Utils.findDescendantByName(mainFrame, part):WaitForChild("Content")) do
		child:Destroy()
	end
end


local function updateCache(oldPart, newPart)
	local inventory = cache.inventory
	if oldPart then
		local part = GetDataCache:InvokeServer("Part", oldPart)
		table.insert(inventory, { quantity = 1, referenced_object = part})
	end
	for key, value in inventory do
		if value and value.category == "PartTemplate" and newPart == value.referenced_object.id then
			key = nil
		end
	end
end


local function getItemById(itemId)
	local data = GetDataCache:InvokeServer("Part", itemId)
	return data
end


-- Part value by level (same as backend)
local PART_VALUES = {
	Common = 200,
	Rare = 500,
	Epic = 1000,
	Legendary = 2000
}

-- Calculate total refund for current vehicle
local function calculateVehicleRefund()
	local totalRefund = 0
	local partKeys = {"Body", "Engine", "Exhaust", "Transmission", "Tire"}

	for _, key in ipairs(partKeys) do
		local partId = vehicle[key]
		if partId then
			local partData = getItemById(partId)
			if partData and partData.level then
				local partValue = PART_VALUES[partData.level] or 0
				totalRefund = totalRefund + partValue
			end
		end
	end

	return totalRefund
end


local function setPart(item, part)
	if not swapping then
		swapping = true
		local oldPart = vehicle[currentTab]
		vehicle[currentTab] = part.referenced_object.id
		updateCache(oldPart, part.referenced_object.id)
		local setParent = Utils.findDescendantByName(mainFrame, currentTab):WaitForChild("Content")

		if isMobileDevice() then
			-- On mobile, show just the Level indicator centered
			local levelFrame = Utils.findDescendantByName(item, "Level")
			if levelFrame then
				local levelClone = levelFrame:Clone()
				-- Remove UIGridLayout and UIPadding from the cloned Level frame
				local clonedGrid = levelClone:FindFirstChild("UIGridLayout")
				local clonedPadding = levelClone:FindFirstChild("UIPadding")
				if clonedGrid then clonedGrid:Destroy() end
				if clonedPadding then clonedPadding:Destroy() end

				-- Size and center the Level frame within Content
				levelClone.Size = UDim2.new(0.8, 0, 0.8, 0)
				levelClone.Position = UDim2.new(0.5, 0, 0.5, 0)
				levelClone.AnchorPoint = Vector2.new(0.5, 0.5)

				-- Size the ImageLabel to fill
				local imageLabel = levelClone:FindFirstChild("ImageLabel")
				if imageLabel then
					imageLabel.Size = UDim2.new(1, 0, 1, 0)
					imageLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
					imageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
					imageLabel.ScaleType = Enum.ScaleType.Fit
				end
				levelClone.Visible = true
				levelClone.Parent = setParent
			end
		else
			-- On desktop, show full template
			local picked = item:Clone()
			picked.Visible = true
			picked.Parent = setParent
		end

		clearInventory()
		setInventory()
		swapping = false
	end
end


local function ownedCarSetup()
	local isMobile = isMobileDevice()

	for key, value in vehicle do
		if key ~= "Id" and key ~= "Name" and key ~= "slotted_number" then
			local entry = getItemById(value)
			local setParent = Utils.findDescendantByName(mainFrame, key):WaitForChild("Content")

			if isMobile then
				-- On mobile, show just the Level indicator centered and sized to fill
				local levelFrame = Utils.findDescendantByName(partTemplate, "Level")
				if levelFrame then
					local levelClone = levelFrame:Clone()
					-- Remove UIGridLayout and UIPadding from the cloned Level frame
					local clonedGrid = levelClone:FindFirstChild("UIGridLayout")
					local clonedPadding = levelClone:FindFirstChild("UIPadding")
					if clonedGrid then clonedGrid:Destroy() end
					if clonedPadding then clonedPadding:Destroy() end

					-- Size and center the Level frame within Content
					levelClone.Size = UDim2.new(0.8, 0, 0.8, 0)
					levelClone.Position = UDim2.new(0.5, 0, 0.5, 0)
					levelClone.AnchorPoint = Vector2.new(0.5, 0.5)

					-- Apply the level icon and size the ImageLabel to fill
					local imageLabel = levelClone:FindFirstChild("ImageLabel")
					if imageLabel then
						local level = entry and entry.level or "Common"
						imageLabel.Image = Utils.colorIconScheme[level] and Utils.colorIconScheme[level].icon or ""
						imageLabel.Size = UDim2.new(1, 0, 1, 0)
						imageLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
						imageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
						imageLabel.ScaleType = Enum.ScaleType.Fit
					end
					levelClone.Visible = true
					levelClone.Parent = setParent
				end
			else
				-- On desktop, show the full partTemplate
				local item = partTemplate:Clone()
				loadItem(item, entry, false, true, true)
				item.Visible = true
				item.Parent = setParent
			end
		end
	end
	textInput.Text = vehicle.Name
end

setInventory = function(vehicleOwned)
	local inventory = getItemOfType("Parts")

	-- Define level order for sorting
	local levelOrder = {
		Common = 1,
		Rare = 2,
		Epic = 3,
		Legendary = 4
	}

	-- Sort inventory items by level (Common, Rare, Epic, Legendary)
	if inventory then
		table.sort(inventory, function(a, b)
			local orderA = levelOrder[a.referenced_object.level] or 999
			local orderB = levelOrder[b.referenced_object.level] or 999
			return orderA < orderB
		end)
	end

	if vehicleOwned then
		for key, _ in vehicle do
			vehicle[key] = vehicleOwned[key:lower()]
		end
		ownedCarSetup()
	end
	for _, value in inventory do
		if value.referenced_object.category == currentTab and (not vehicle[currentTab] or value.referenced_object.id ~= vehicle[currentTab]) then
			local item = partTemplate:Clone()
			loadItem(item, value, false, true)
			item.MouseButton1Click:Connect(function()
				GarageSoundUtils.PlayRatchet()
				setPart(item, value)
			end)
			item.Visible = true
			item.Parent = inventoryFrame
		end
	end
end


local function switchVehicle(vehicleOwned) 
	selectionFrame.Visible = false
	tabs.Visible = true
	mainFrame.Visible = true
	setInventory(vehicleOwned)
end


-- Clear previous items
local function clearItems()
	tabs.Visible = false
	mainFrame.Visible = false
	selectionFrame.Visible = true
	cache = false
	currentTab = "Body"
	vehicle = {
		Body = false,
		Engine = false,
		Exhaust = false,
		Transmission = false,
		Tire = false,
		Id = false,
		Name = false,
		slotted_number = false
	}

	-- Reset tab highlighting to Body
	for key, value in pairs(tabButtons) do
		if value then
			local result = value:FindFirstChild("TextLabel", true)
			if result then
				if key == "Body" then
					result.TextColor3 = Color3.fromRGB(255, 255, 255)
				else
					result.TextColor3 = Color3.fromRGB(104, 78, 245)
				end
			end
		end
	end

	for key, _ in vehicle do
		if key ~= "Id" and key ~= "Name" and key ~= "slotted_number" then
			local setParent = Utils.findDescendantByName(mainFrame, key):WaitForChild("Content")
			for _, child in pairs(setParent:GetChildren()) do
				child:Destroy()
			end
		end
	end

	-- Clear all vehicle items (except templates)
	for _, child in ipairs(selectionFrame:GetChildren()) do
		if child:IsA("Frame") and child.Visible and child.Name ~= "VehicleTemplate" and child.Name ~= "BuildCar" then
			child:Destroy()
		end
	end
	clearInventory()
end


clearInventory = function()
	for _, child in pairs(inventoryFrame:GetChildren()) do
		if child:IsA("TextButton") and child.Name ~= "PartTemplate" then
			child:Destroy()
		end
	end
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
		local tabData = cache["inventory"]
		local values = {}
		for _, value in tabData do
			if value["category"] == inventoryMap[tabType] then
				table.insert(values, value)
			end
		end
		return values
	end
end


-- Load thumbnail for a vehicle item
local function loadVehicleThumbnail(item, vehicleEntry)
	local thumbnail = Utils.findDescendantByName(item, "Thumbnail")
	if not thumbnail or not thumbnail:IsA("ViewportFrame") then
		warn("[VehicleGui] Thumbnail ViewportFrame not found in vehicle item")
		return
	end

	-- Clear any existing content in the thumbnail
	for _, child in pairs(thumbnail:GetChildren()) do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	-- Get the skin name from the vehicle entry (use "Clean" as default if no skin)
	local skinName = vehicleEntry.skin or "Clean"

	-- Find the car model in ReplicatedStorage
	local carsFolder = ReplicatedStorage:WaitForChild("Cars")
	local carModel = carsFolder:FindFirstChild(skinName)

	if not carModel then
		warn("[VehicleGui] Car model '" .. skinName .. "' not found in ReplicatedStorage.Cars, using Clean as fallback")
		carModel = carsFolder:FindFirstChild("Clean")
	end

	if carModel then
		-- Clone the car model and add it to the viewport
		local carClone = carModel:Clone()
		carClone.Parent = thumbnail

		-- Apply custom color to the thumbnail if vehicle has a color set
		if vehicleEntry.color then
			Utils.applyViewportColor(carClone, vehicleEntry.color)
		end

		-- Create and configure the camera
		local viewportCamera = Instance.new("Camera")
		viewportCamera.Parent = thumbnail

		-- Set camera position from ThumbnailCFrame if it exists
		local thumbnailCFrame = carClone:FindFirstChild("ThumbnailCFrame")
		local thumbnailFOV = carClone:FindFirstChild("ThumbnailFOV")

		if thumbnailCFrame and thumbnailCFrame:IsA("CFrameValue") then
			viewportCamera.CFrame = thumbnailCFrame.Value

			if thumbnailFOV and thumbnailFOV:IsA("NumberValue") then
				viewportCamera.FieldOfView = thumbnailFOV.Value
			else
				viewportCamera.FieldOfView = 10
			end
		else
			-- Default camera position if ThumbnailCFrame doesn't exist
			viewportCamera.FieldOfView = 10
		end

		thumbnail.CurrentCamera = viewportCamera
	else
		warn("[VehicleGui] No car model found for vehicle thumbnail")
	end
end


loadItem = function(item, entry, notAvailable, quantity, notReferenced)
	if quantity then
		local robloxObject
		if notReferenced then
			robloxObject = entry
		else
			robloxObject = entry.referenced_object
		end

		local nameLevel = Utils.split(robloxObject["name"], "-")
		local name = nameLevel[1]
		local level = robloxObject["level"]
		if name == "Transmission" then
			name = "Trans"
		end
		if notAvailable then
			Utils.switchColorIcon(item, "NotAvailable")
		else
			Utils.switchColorIcon(item, level)
		end

		local nameFrame = Utils.findDescendantByName(item, "Name")
		local itemLabel = Utils.findDescendantByName(nameFrame, "ItemLabel")
		local itemLabelStroke = Utils.findDescendantByName(nameFrame, "ItemLabelStroke")
		item.Name = name
		itemLabel.Text = name
		itemLabelStroke.Text = name
		local quantityFrame = Utils.findDescendantByName(item, "Quantity")
		local quantityItemLabel = Utils.findDescendantByName(quantityFrame, "ItemLabel")
		local quantityItemLabelStroke = Utils.findDescendantByName(quantityFrame, "ItemLabelStroke")
		quantityItemLabel.Text = ""
		quantityItemLabelStroke.Text = ""
	else
		-- This is a vehicle entry (not a part)
		local name = entry.name
		local level = entry.level
		Utils.switchColorIcon(item, level)
		local nameFrame = Utils.findDescendantByName(item, "Name")
		local itemLabel = Utils.findDescendantByName(nameFrame, "ItemLabel")
		local itemLabelStroke = Utils.findDescendantByName(nameFrame, "ItemLabelStroke")
		item.Name = name
		itemLabel.Text = name
		itemLabelStroke.Text = name

		-- Load the vehicle thumbnail
		loadVehicleThumbnail(item, entry)
	end
	item.Visible = true
	return item
end


local function loadItems()
	print(tabButtons)
	clearItems()
	mainGui.Visible = true
	local tabData = getItemOfType("Vehicles")
	if not tabData then
		warn("No data for tab:", currentTab)
		return
	end

	-- Define level order for sorting
	local levelOrder = {
		Common = 1,
		Rare = 2,
		Epic = 3,
		Legendary = 4
	}

	-- Sort vehicles by level (Common, Rare, Epic, Legendary)
	table.sort(tabData, function(a, b)
		local orderA = levelOrder[a.level] or 999
		local orderB = levelOrder[b.level] or 999
		return orderA < orderB
	end)

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


local function switchTab(tabType)
	clearInventory()
	currentTab = tabType
	for key, value in pairs(tabButtons) do
		if key ~= currentTab then
			local result = value.Parent:FindFirstChild("TextLabel - Stroke", true)
			result = value:FindFirstChild("TextLabel", true)
			result.TextColor3 = Color3.fromRGB(104, 78, 245)
		else
			local result = value.Parent:FindFirstChild("TextLabel - Stroke", true)
			result = value:FindFirstChild("TextLabel", true)
			result.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end
	setInventory()
end


local function deleteVehicle()
	if vehicle.Id then
		local result = DeleteVehicle:InvokeServer(vehicle.Id, vehicle.slotted_number)
		-- Update player's money attribute with new balance from server
		if result and result.new_balance then
			player:SetAttribute("Money", tonumber(result.new_balance))
		end
		loadItems()
	end
end

-- Show sell confirmation dialog
local function showSellConfirmation()
	local confirmFrame = vehicleGui:FindFirstChild("Confirm")
	if not confirmFrame then
		warn("[VehicleGui] Confirm frame not found")
		return
	end

	-- Calculate refund amount
	local refundAmount = calculateVehicleRefund()

	-- Find and set the message
	local messageLabel = confirmFrame:FindFirstChild("Message", true)
	if messageLabel then
		-- Create message with green money text using RichText
		messageLabel.RichText = true
		messageLabel.Text = string.format(
			'Are you sure you want to sell this vehicle for <font color="#00FF00">$%d</font>?',
			refundAmount
		)
	else
		warn("[VehicleGui] Message label not found in Confirm frame")
	end

	-- Show the confirmation dialog
	confirmFrame.Visible = true
end

-- Hide sell confirmation dialog
local function hideSellConfirmation()
	local confirmFrame = vehicleGui:FindFirstChild("Confirm")
	if confirmFrame then
		confirmFrame.Visible = false
	end
end


local function saveVehicle()
	local complete = true
	if not vehicle.Name then
		vehicle.Name = textInput.Text
	end
	for key, value in vehicle do
		if key ~= "Id" and key ~= "slotted_number" and not value then
			complete = false
		end
	end
	if complete then
		UpdateCreateVehicle:InvokeServer(vehicle)
		loadItems()
	end	
end


local function firstLoad()
	if not loaded then
		for key, value in pairs(tabButtons) do
			tabButtons[key] = Utils.findDescendantByName(tabs, key)
			tabButtons[key].MouseButton1Click:Connect(function()
				GarageSoundUtils.PlayButtonPressed()
				switchTab(key)
			end)
		end
		local buildNew = Utils.findDescendantByName(buildCar, "TextButton")
		buildNew.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			switchVehicle()
		end)
		local deleteButton = Utils.findDescendantByName(mainFrame, "Delete")
		deleteButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			showSellConfirmation()
		end)

		-- Confirmation dialog buttons
		local confirmFrame = vehicleGui:FindFirstChild("Confirm")
		if confirmFrame then
			-- Initially hide the confirmation dialog
			confirmFrame.Visible = false

			local cancelButton = Utils.findDescendantByName(confirmFrame, "Cancel")
			if cancelButton then
				cancelButton.MouseButton1Click:Connect(function()
					GarageSoundUtils.PlayButtonPressed()
					hideSellConfirmation()
				end)
			end

			local sellButton = Utils.findDescendantByName(confirmFrame, "Sell")
			if sellButton then
				sellButton.MouseButton1Click:Connect(function()
					GarageSoundUtils.PlayButtonPressed()
					hideSellConfirmation()
					deleteVehicle()
				end)
			end
		end
		local saveButton = Utils.findDescendantByName(mainFrame, "Save")
		saveButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			saveVehicle()
		end)
		local backButton = Utils.findDescendantByName(mainFrame, "Back")
		backButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			loadItems()
		end)
	end
	loadItems()
	mainGui.Visible = true
end


OpenVehicleEvent.Event:Connect(firstLoad)