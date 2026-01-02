local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OpenInventoryEvent = ReplicatedStorage:WaitForChild("BindableEvents"):WaitForChild("OpenInventory")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GetPlayerCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetPlayerCache")
local mainGui = playerGui:WaitForChild("InventoryUI"):WaitForChild("Window")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))
local GarageSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GarageSoundUtils"))

-- GUI references
local itemsFrame = mainGui:WaitForChild("Content"):WaitForChild("Body"):WaitForChild("Items"):WaitForChild("Content")
local itemList = itemsFrame:WaitForChild("ItemList")
local vehicleTemplate = itemList:WaitForChild("VehicleTemplate")
local blueprintTemplate = itemList:WaitForChild("BlueprintTemplate")
local materialTemplate = itemList:WaitForChild("MaterialTemplate")
local modsTemplate = itemList:WaitForChild("ModsTemplate")
local partsTemplate = itemList:WaitForChild("PartsTemplate")
local currentTab = "Vehicles"
local RunService = game:GetService("RunService")
local tabButtons = {
	Vehicles = false,
	Blueprints = false,
	Parts = false,
	Materials = false,
	Mods = false
}
vehicleTemplate.Visible = false
materialTemplate.Visible = false
blueprintTemplate.Visible = false
modsTemplate.Visible = false
partsTemplate.Visible = false
local tabTemplates = {
	Vehicles = vehicleTemplate,
	Blueprints = blueprintTemplate,
	Parts = partsTemplate,
	Materials = materialTemplate,
	Mods = modsTemplate
}

local inventoryMap = {
	Blueprints = "BlueprintTemplate",
	Parts = "PartTemplate",
	Materials = "MaterialTemplate",
	Mods = false
}

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
	local values = {}
	for _, value in pairs(tabTemplates) do
		table.insert(values, value)
	end
	for _, child in pairs(itemList:GetChildren()) do
		if child:IsA("Frame") and not Utils.contains(values, child) then
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


local function getItemOfType(tabType)
	local cache = GetPlayerCache:InvokeServer()
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


local function loadItems()
	print(tabButtons)
	clearItems()
	mainGui.Visible = true
	local tabData = getItemOfType(currentTab)
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

	-- Sort items by level (Common, Rare, Epic, Legendary)
	if currentTab == "Vehicles" then
		-- Sort vehicles by level
		table.sort(tabData, function(a, b)
			local orderA = levelOrder[a.level] or 999
			local orderB = levelOrder[b.level] or 999
			return orderA < orderB
		end)
	else
		-- Sort other inventory items by referenced_object.level
		table.sort(tabData, function(a, b)
			local levelA = a.referenced_object and a.referenced_object.level or "Common"
			local levelB = b.referenced_object and b.referenced_object.level or "Common"
			local orderA = levelOrder[levelA] or 999
			local orderB = levelOrder[levelB] or 999
			return orderA < orderB
		end)
	end

	for _, entry in ipairs(tabData) do
		local item = tabTemplates[currentTab]:Clone()
		if currentTab == "Vehicles" then
			item.Name = entry.name or "Item"
			local level = entry.level
			switchColorIcon(item, level)
			local itemLabel = Utils.findDescendantByName(item, "ItemLabel")
			local itemLabelStroke = Utils.findDescendantByName(item, "ItemLabelStroke")
			-- Assign image and labels
			--item.ItemImage.Image = entry.image or "" -- URL or asset ID
			itemLabel.Text = entry.name or "Unnamed"
			itemLabelStroke.Text = entry.name or "Unnamed"

			-- Add thumbnail to ViewportFrame
			local thumbnail = Utils.findDescendantByName(item, "Thumbnail")
			if thumbnail then
				local carsFolder = ReplicatedStorage:WaitForChild("Cars")
				local carModel = carsFolder:FindFirstChild(entry.skin)
				if carModel then
					local carClone = carModel:Clone()
					carClone.Parent = thumbnail

					-- Apply custom color to the thumbnail if vehicle has a color set
					Utils.applyViewportColor(carClone, entry.color)

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
			local quantity = entry["quantity"]
			local robloxObject = entry["referenced_object"]
			local nameLevel = Utils.split(robloxObject["name"], "-")
			local name = nameLevel[1]
			if name == "Transmission" then
				name = "Trans"
			end
			local level = robloxObject["level"]
			switchColorIcon(item, level)
			local nameFrame = Utils.findDescendantByName(item, "Name")
			local itemLabel = Utils.findDescendantByName(nameFrame, "ItemLabel")
			local itemLabelStroke = Utils.findDescendantByName(nameFrame, "ItemLabelStroke")
			item.Name = name
			itemLabel.Text = name
			itemLabelStroke.Text = name
			local quantityFrame = Utils.findDescendantByName(item, "Quantity")
			local quantityItemLabel = Utils.findDescendantByName(quantityFrame, "ItemLabel")
			local quantityItemLabelStroke = Utils.findDescendantByName(quantityFrame, "ItemLabelStroke")
			quantityItemLabel.Text = "Qty: " .. quantity
			quantityItemLabelStroke.Text = "Qty: " .. quantity
			item.Visible = true
			item.Parent = itemList
		end
	end
	RunService.RenderStepped:Wait()
	local grid = itemList:FindFirstChildOfClass("UIGridLayout")
	local padding = itemList:FindFirstChildOfClass("UIPadding")

	local totalHeight = grid.AbsoluteContentSize.Y
	if padding then
		totalHeight += padding.PaddingTop.Offset
		totalHeight += padding.PaddingBottom.Offset
	end

	itemList.CanvasSize = UDim2.new(0, 0, 0, totalHeight)


end


local function switchTab(tabType)
	currentTab = tabType
	for key, value in pairs(tabButtons) do
		if key ~= currentTab then
			value.Parent.BackgroundColor3 = Color3.fromRGB(0, 43, 83)
			local result = value.Parent:FindFirstChild("Unstroke", true)
			result.BackgroundColor3 = Color3.fromRGB(0, 43, 83)
			result = value:FindFirstChild("TextLabel", true)
			result.TextColor3 = Color3.fromRGB(78, 171, 242)
		else
			value.Parent.BackgroundColor3 = Color3.fromRGB(0, 84, 158)
			local result = value.Parent:FindFirstChild("Unstroke", true)
			result.BackgroundColor3 = Color3.fromRGB(0, 84, 158)
			result = value:FindFirstChild("TextLabel", true)
			result.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end
	loadItems()
end


local function firstLoad()
	for key, value in pairs(tabButtons) do
		tabButtons[key] = Utils.findDescendantByName(mainGui, key)
		tabButtons[key].MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			switchTab(key)
		end)
	end
	loadItems()
end


OpenInventoryEvent.Event:Connect(firstLoad)