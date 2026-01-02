local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OpenCraftingEvent = ReplicatedStorage:WaitForChild("BindableEvents"):WaitForChild("OpenParts")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GetPlayerCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetPlayerCache")
local GetCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetCache")
local mainGui = playerGui:WaitForChild("CraftingUI"):WaitForChild("Window")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))
local GarageSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GarageSoundUtils"))
local craftPart = ReplicatedStorage:WaitForChild("Player"):WaitForChild("CraftPart")
-- GUI references
local leftFrame = Utils.findDescendantByName(mainGui, "Left")
local centerFrame = Utils.findDescendantByName(mainGui, "Center")
local rightFrame = Utils.findDescendantByName(mainGui, "Right")
local blueprintTemplate = Utils.findDescendantByName(leftFrame,"Blueprint")
local blueprintCreate = Utils.findDescendantByName(centerFrame, "Blueprint")
local centerText = Utils.findDescendantByName(centerFrame, "Needed")
local rightPart = Utils.findDescendantByName(rightFrame, "Part")
local rightButton = Utils.findDescendantByName(rightFrame, "Craft")
local RunService = game:GetService("RunService")
local loading = false

local loadItems
local list = leftFrame:FindFirstChildOfClass("UIListLayout")
local pad  = leftFrame:FindFirstChildOfClass("UIPadding")


local function updateCanvas()
	local h = list and list.AbsoluteContentSize.Y or 0
	if pad then
		h += pad.PaddingTop.Offset + pad.PaddingBottom.Offset
	end
	h += 2 -- tiny buffer to avoid rounding cutoffs
	leftFrame.CanvasSize = UDim2.new(0, 0, 0, h)
end


if list then
	list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)
end


-- Clear previous items
local function clearItems()
	blueprintTemplate.Visible = false
	blueprintCreate.Visible = false
	centerText.Visible = false
	rightPart.Visible = false
	rightButton.Visible = false

	-- Find and hide the "None" button
	local noneButton = leftFrame:FindFirstChild("None")
	if noneButton then
		noneButton.Visible = false
	end

	for _, child in pairs(leftFrame:GetChildren()) do
		if child:IsA("TextButton") and child.name ~= "Blueprint" and child.Name ~= "None" then
			child:Destroy()
		end
	end
end


local function refreshAutoCanvas(scroller)
	-- Nudge Roblox to recompute content size
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.None
	game:GetService("RunService").Heartbeat:Wait()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
end


local function getItemOfType(itemType)
	local cache = GetPlayerCache:InvokeServer()
	if not cache then
		warn("No PlayerCache entry found for player:", player.UserId)
		return
	end


	local tabData = cache["inventory"]
	local values = {}
	local materials = {}
	for _, value in tabData do
		if value["category"] == itemType then
			table.insert(values, value)
		end
		if value["category"] == "MaterialTemplate" then
			table.insert(materials, value)
		end
	end
	local materialsMap = {}
	for _, value in materials do
		materialsMap[value.referenced_object.name] = value.quantity
	end
	local hasMaterials = {}
	local noMaterials = {}
	for _, value in values do
		local mat, quantity
		for k,v in value.referenced_object.materials do
			mat = k
			quantity = v
			break
		end
		if materialsMap[mat] and materialsMap[mat] > quantity then
			table.insert(hasMaterials, value)
		else
			table.insert(noMaterials, value)
		end
	end
	return {
		hasMaterials = hasMaterials,
		noMaterials = noMaterials,
		materials = materialsMap
	}
end


local function loadBlueprint(item, entry, notAvailable)
	local quantity = entry.quantity
	local robloxObject = entry.referenced_object
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
	quantityItemLabel.Text = "Qty: " .. quantity
	quantityItemLabelStroke.Text = "Qty: " .. quantity
	item.Visible = true
	return item
end


local function showCreatePart(item, entry, materialMap)
	loadBlueprint(blueprintCreate, entry, false)
	local top = Utils.findDescendantByName(centerText, "Material Needed")
	local topText = Utils.findDescendantByName(top, "TextLabel")
	local mat, quantity
	for k,v in entry.referenced_object.materials do
		mat = k
		quantity = v
		break
	end
	topText.Text = mat .. ": " .. tostring(quantity)
	local bottom = Utils.findDescendantByName(centerText, "Available")
	local bottomText = Utils.findDescendantByName(bottom, "TextLabel")
	local quantity = materialMap[mat] or 0
	bottomText.Text = mat .. ": " .. tostring(quantity)
	centerText.Visible = true
	local part = GetCache:InvokeServer("PartTemplate", entry.referenced_object.part_template_id)
	local partEntry = {
		referenced_object = part,
		quantity = 1
	}
	loadBlueprint(rightPart, partEntry, false)
	rightButton.Visible = true
	rightButton.MouseButton1Click:Connect(function()
		GarageSoundUtils.PlayForge()
		local result = craftPart:InvokeServer(entry.id)
		task.wait(.1)
		loadItems()
	end)
end


local function showNeeded(item, entry, materialMap)
	loadBlueprint(blueprintCreate, entry, false)
	local top = Utils.findDescendantByName(centerText, "Material Needed")
	local topText = Utils.findDescendantByName(top, "TextLabel")
	local mat, quantity
	for k,v in entry.referenced_object.materials do
		mat = k
		quantity = v
		break
	end
	topText.Text = mat .. ": " .. tostring(quantity)
	local bottom = Utils.findDescendantByName(centerText, "Available")
	local bottomText = Utils.findDescendantByName(bottom, "TextLabel")
	local quantity = materialMap[mat] or 0
	bottomText.Text = mat .. ": " .. tostring(quantity)
	centerText.Visible = true
end


loadItems = function()
	clearItems()
	local data = getItemOfType("BlueprintTemplate")
	if not data then
		warn("No data blueprints")
		return
	end

	-- Check if player has any blueprints
	local hasBlueprints = (#data.hasMaterials > 0 or #data.noMaterials > 0)

	if not hasBlueprints then
		-- Show "None" button if player has no blueprints
		local noneButton = leftFrame:FindFirstChild("None")
		if noneButton then
			noneButton.Visible = true
		else
			warn("[CraftingUI] 'None' button not found in leftFrame")
		end
	else
		-- Player has blueprints, create the blueprint buttons
		for _, entry in data.hasMaterials do
			local item = blueprintTemplate:Clone()
			item = loadBlueprint(item, entry, false)
			item.Parent = leftFrame
			item.MouseButton1Click:Connect(function()
				GarageSoundUtils.PlayButtonPressed()
				showCreatePart(item, entry, data.materials)
			end)
		end
		for _, entry in data.noMaterials do
			local item = blueprintTemplate:Clone()
			item = loadBlueprint(item, entry, false)
			item.Parent = leftFrame
			item.MouseButton1Click:Connect(function()
				GarageSoundUtils.PlayButtonPressed()
				showNeeded(item, entry, data.materials)
			end)
		end
	end

	RunService.RenderStepped:Wait()
	local grid = leftFrame:FindFirstChildOfClass("UIListLayout")
	local padding = leftFrame:FindFirstChildOfClass("UIPadding")

	local totalHeight = grid.AbsoluteContentSize.Y
	if padding then
		totalHeight += padding.PaddingTop.Offset
		totalHeight += padding.PaddingBottom.Offset
	end
	updateCanvas()
end


local function firstLoad()
	if not loading then
		loading = true
		loadItems()
		task.wait(.1)
		loading = false
		mainGui.Visible = true
	end
end

OpenCraftingEvent.Event:Connect(firstLoad)