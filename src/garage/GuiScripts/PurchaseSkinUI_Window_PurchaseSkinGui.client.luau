--#GARAGE
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GetPlayerCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetPlayerCache")
local GetDataCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetCache")
local mainGui = playerGui:WaitForChild("PurchaseSkinUI"):WaitForChild("Window")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))
local GarageSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GarageSoundUtils"))

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- RemoteEvent for purchase completion notifications (optional, for UI refresh)
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local SkinPurchased = RemoteEvents:FindFirstChild("SkinPurchased")

-- GUI references
local scrollingFrame = mainGui:WaitForChild("Content"):WaitForChild("Body"):WaitForChild("ItemList")
local purchaseTemplate = Utils.findDescendantByName(scrollingFrame, "PurchaseTemplate")
local cashPurchaseTemplate = Utils.findDescendantByName(scrollingFrame, "CashPurchaseTemplate")

-- RemoteFunction for cash purchase
local purchaseSkinWithCash = ReplicatedStorage:WaitForChild("Player"):WaitForChild("PurchaseSkinWithCash")

-- Hide templates
purchaseTemplate.Visible = false
cashPurchaseTemplate.Visible = false

-- Minimum price threshold (exclude free skins under 80)
local MIN_PRICE_THRESHOLD = 80
local CASH_PRICE = 10000

-- Cache
local playerCache = nil
local allSkins = nil

-- Loading guard to prevent duplicate loads
local isLoading = false

-- Forward declaration for refresh function (used by purchase handlers)
local refreshAfterPurchase

-- Helper: Get owned skin names from player cache
local function getOwnedSkinNames()
	local ownedNames = {}
	if playerCache and playerCache.skins then
		for _, ownedSkin in ipairs(playerCache.skins) do
			local skinName = ownedSkin.vehicle_skin_details and ownedSkin.vehicle_skin_details.name
			if skinName then
				ownedNames[skinName] = true
			end
		end
	end
	return ownedNames
end


-- Premium skins available for direct purchase only
local PREMIUM_SKINS = {
	["Wraith"] = true,
	["Vortex"] = true,
	["Raven"] = true,
}

-- Helper: Get purchasable skins (only Wraith, Vortex, and Raven)
local function getPurchasableSkins()
	local purchasable = {}

	if allSkins then
		for _, skin in ipairs(allSkins) do
			local skinName = skin.name

			-- Only include premium skins (Wraith, Vortex, Raven)
			if skinName and PREMIUM_SKINS[skinName] then
				table.insert(purchasable, skin)
			end
		end
	end

	-- Sort by price from lowest to highest
	table.sort(purchasable, function(a, b)
		return (a.price or 0) < (b.price or 0)
	end)

	return purchasable
end


-- Helper: Get free skins available for cash purchase (price = 0, not owned)
local function getFreePurchasableSkins()
	local ownedNames = getOwnedSkinNames()
	local freeSkins = {}

	if allSkins then
		for _, skin in ipairs(allSkins) do
			local skinName = skin.name
			local price = skin.price or 0

			-- Only include skins that:
			-- 1. Are not already owned
			-- 2. Have price = 0 (free skins)
			if skinName and not ownedNames[skinName] and price == 0 then
				table.insert(freeSkins, skin)
			end
		end
	end

	-- Sort alphabetically
	table.sort(freeSkins, function(a, b)
		return a.name < b.name
	end)

	return freeSkins
end


-- Load a free skin into a cash purchase template
local function loadCashPurchaseItem(item, skin)
	-- Find GUI elements
	local imageFrame = Utils.findDescendantByName(item, "Image")
	local viewportFrame = Utils.findDescendantByName(item, "ViewportFrame")
	local purchaseButton = Utils.findDescendantByName(item, "PurchaseButton")
	local priceLabel = purchaseButton and Utils.findDescendantByName(purchaseButton, "TextLabel")
	local priceLabelStroke = purchaseButton and Utils.findDescendantByName(purchaseButton, "TextLabelS")

	-- Try to find name labels
	local nameFrame = Utils.findDescendantByName(item, "Name")
	local itemLabel = nameFrame and Utils.findDescendantByName(nameFrame, "TextLabel")

	print("[PurchaseSkinGui] Loading cash purchase skin:", skin.name)

	-- Set item name property
	item.Name = skin.name

	-- Set skin name text if labels exist
	if itemLabel then
		itemLabel.Text = skin.name
	end

	-- Set price in button (cash price)
	local priceText = tostring(CASH_PRICE)
	if priceLabel then
		priceLabel.Text = priceText
	end
	if priceLabelStroke then
		priceLabelStroke.Text = priceText
	end

	-- Add thumbnail to ViewportFrame
	if viewportFrame then
		-- Clear existing content
		for _, child in ipairs(viewportFrame:GetChildren()) do
			if not child:IsA("UICorner") and not child:IsA("UIStroke") then
				child:Destroy()
			end
		end

		local carsFolder = ReplicatedStorage:WaitForChild("Cars")
		local carModel = carsFolder:FindFirstChild(skin.name)

		if carModel then
			local carClone = carModel:Clone()
			carClone.Parent = viewportFrame

			local viewportCamera = Instance.new("Camera")
			viewportCamera.Parent = viewportFrame

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
				-- Fallback camera positioning
				if carClone.PrimaryPart then
					local cf = carClone.PrimaryPart.CFrame
					viewportCamera.CFrame = cf * CFrame.new(0, 2, 8) * CFrame.Angles(math.rad(-10), 0, 0)
				else
					viewportCamera.CFrame = CFrame.new(0, 2, 8) * CFrame.Angles(math.rad(-10), 0, 0)
				end
				viewportCamera.FieldOfView = 40
			end

			viewportFrame.CurrentCamera = viewportCamera
		else
			warn("[PurchaseSkinGui] Car model not found:", skin.name)
		end
	end

	-- Connect cash purchase button click handler
	if purchaseButton then
		purchaseButton.Visible = true
		purchaseButton.MouseButton1Click:Connect(function()
			-- Get player's current money
			local playerMoney = tonumber(player:GetAttribute("Money")) or 0

			-- Check if player has enough money (silently ignore if not)
			if playerMoney < CASH_PRICE then
				print("[PurchaseSkinGui] Not enough money for cash purchase. Required:", CASH_PRICE, "Available:", playerMoney)
				return
			end

			GarageSoundUtils.PlayRegister()
			print("[PurchaseSkinGui] Cash purchase clicked - Skin:", skin.name, "ID:", skin.id)

			-- Show spinner on the button
			local spinnerFrame = Instance.new("Frame")
			spinnerFrame.Name = "SpinnerFrame"
			spinnerFrame.Size = UDim2.new(1, 0, 1, 0)
			spinnerFrame.Position = UDim2.new(0, 0, 0, 0)
			spinnerFrame.BackgroundTransparency = 1
			spinnerFrame.BorderSizePixel = 0
			spinnerFrame.ZIndex = purchaseButton.ZIndex + 1

			local spinnerImage = Instance.new("ImageLabel")
			spinnerImage.Name = "SpinnerImage"
			spinnerImage.Size = UDim2.new(0, 24, 0, 24)
			spinnerImage.Position = UDim2.new(0.5, -12, 0.5, -12)
			spinnerImage.BackgroundTransparency = 1
			spinnerImage.Image = "rbxassetid://101716378951252"
			spinnerImage.ZIndex = spinnerFrame.ZIndex + 1
			spinnerImage.Parent = spinnerFrame

			local rotationTween = TweenService:Create(
				spinnerImage,
				TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
				{Rotation = 360}
			)

			-- Hide button text and show spinner
			if priceLabel then priceLabel.Visible = false end
			if priceLabelStroke then priceLabelStroke.Visible = false end
			spinnerFrame.Parent = purchaseButton
			purchaseButton.Active = false
			rotationTween:Play()

			-- Call server to purchase with cash
			local result = purchaseSkinWithCash:InvokeServer(skin.id)

			if result and result.success then
				print("[PurchaseSkinGui] Cash purchase successful!")
				-- Refresh the purchase menu (spinner will be cleaned up with clearItems)
				refreshAfterPurchase("CashPurchase", skin.name)
			else
				warn("[PurchaseSkinGui] Cash purchase failed:", result and result.error or "Unknown error")
				-- Restore button on failure
				rotationTween:Cancel()
				spinnerFrame:Destroy()
				if priceLabel then priceLabel.Visible = true end
				if priceLabelStroke then priceLabelStroke.Visible = true end
				purchaseButton.Active = true
			end
		end)
	end

	item.Visible = true
	return item
end


-- Load a skin into a purchase template
local function loadPurchaseItem(item, skin)
	-- Find GUI elements
	local imageFrame = Utils.findDescendantByName(item, "Image")
	local viewportFrame = Utils.findDescendantByName(item, "ViewportFrame")
	local purchaseButton = Utils.findDescendantByName(item, "PurchaseButton")
	local priceLabel = purchaseButton and Utils.findDescendantByName(purchaseButton, "TextLabel")
	local priceLabelStroke = purchaseButton and Utils.findDescendantByName(purchaseButton, "TextLabelS")

	-- Try to find name labels (similar to other templates)
	local nameFrame = Utils.findDescendantByName(item, "Name")
	local itemLabel = nameFrame and Utils.findDescendantByName(nameFrame, "TextLabel")

	-- Debug: Log item structure
	print("[PurchaseSkinGui] === Loading skin:", skin.name, "===")
	print("[PurchaseSkinGui] item:", item, "Parent:", item.Parent)
	print("[PurchaseSkinGui] imageFrame:", imageFrame)
	print("[PurchaseSkinGui] viewportFrame:", viewportFrame, viewportFrame and ("Parent: " .. tostring(viewportFrame.Parent)) or "")
	print("[PurchaseSkinGui] nameFrame:", nameFrame)
	print("[PurchaseSkinGui] itemLabel:", itemLabel)
	print("[PurchaseSkinGui] purchaseButton:", purchaseButton)

	-- Set item name property
	item.Name = skin.name

	-- Set skin name text if labels exist
	if itemLabel then
		itemLabel.Text = skin.name
		print("[PurchaseSkinGui] Set itemLabel.Text to:", skin.name)
	else
		print("[PurchaseSkinGui] itemLabel not found!")
	end


	-- Set price in button
	local priceText = tostring(skin.price or 0)
	if priceLabel then
		priceLabel.Text = priceText
	end
	if priceLabelStroke then
		priceLabelStroke.Text = priceText
	end

	-- Add thumbnail to ViewportFrame
	if viewportFrame then
		print("[PurchaseSkinGui] ViewportFrame children before clear:", #viewportFrame:GetChildren())

		-- Clear existing content
		for _, child in ipairs(viewportFrame:GetChildren()) do
			if not child:IsA("UICorner") and not child:IsA("UIStroke") then
				child:Destroy()
			end
		end

		local carsFolder = ReplicatedStorage:WaitForChild("Cars")
		local carModel = carsFolder:FindFirstChild(skin.name)
		print("[PurchaseSkinGui] carModel:", carModel)

		if carModel then
			local carClone = carModel:Clone()
			carClone.Parent = viewportFrame

			local viewportCamera = Instance.new("Camera")
			viewportCamera.Parent = viewportFrame

			local thumbnailCFrame = carClone:FindFirstChild("ThumbnailCFrame")
			local thumbnailFOV = carClone:FindFirstChild("ThumbnailFOV")

			-- Log model position
			local modelPos = carClone.PrimaryPart and carClone.PrimaryPart.Position or Vector3.new(0,0,0)
			print("[PurchaseSkinGui]", skin.name, "- Model position:", modelPos)

			if thumbnailCFrame and thumbnailCFrame:IsA("CFrameValue") then
				viewportCamera.CFrame = thumbnailCFrame.Value
				print("[PurchaseSkinGui]", skin.name, "- Camera CFrame:", thumbnailCFrame.Value.Position)
				if thumbnailFOV and thumbnailFOV:IsA("NumberValue") then
					viewportCamera.FieldOfView = thumbnailFOV.Value
					print("[PurchaseSkinGui]", skin.name, "- FOV:", thumbnailFOV.Value)
				else
					viewportCamera.FieldOfView = 10
				end
			else
				-- Fallback camera positioning
				print("[PurchaseSkinGui]", skin.name, "- Using FALLBACK camera")
				if carClone.PrimaryPart then
					local cf = carClone.PrimaryPart.CFrame
					viewportCamera.CFrame = cf * CFrame.new(0, 2, 8) * CFrame.Angles(math.rad(-10), 0, 0)
					print("[PurchaseSkinGui]", skin.name, "- Fallback camera at:", viewportCamera.CFrame.Position)
				else
					viewportCamera.CFrame = CFrame.new(0, 2, 8) * CFrame.Angles(math.rad(-10), 0, 0)
					print("[PurchaseSkinGui]", skin.name, "- No PrimaryPart, camera at origin offset")
				end
				viewportCamera.FieldOfView = 40
			end

			viewportFrame.CurrentCamera = viewportCamera

			-- Additional viewport debug
			print("[PurchaseSkinGui]", skin.name, "- ViewportFrame size:", viewportFrame.AbsoluteSize)
			print("[PurchaseSkinGui]", skin.name, "- ViewportFrame visible:", viewportFrame.Visible)
		else
			warn("[PurchaseSkinGui] Car model not found:", skin.name)
		end
	else
		warn("[PurchaseSkinGui] ViewportFrame not found in item for:", skin.name)
	end

	-- Connect purchase button click handler
	if purchaseButton then
		purchaseButton.Visible = true
		purchaseButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayRegister()
			print("[PurchaseSkinGui] Purchase clicked - Skin:", skin.name)
			print("[PurchaseSkinGui] ProductId (roblox_asset_id):", skin.roblox_asset_id, "Type:", type(skin.roblox_asset_id))
			print("[PurchaseSkinGui] Full skin data:", skin)

			-- Prompt the Developer Product purchase
			if skin.roblox_asset_id then
				print("[PurchaseSkinGui] Calling PromptProductPurchase with ProductId:", skin.roblox_asset_id)
				local success, err = pcall(function()
					MarketplaceService:PromptProductPurchase(player, skin.roblox_asset_id)
				end)

				if success then
					print("[PurchaseSkinGui] PromptProductPurchase called successfully (prompt may not show in Studio)")
				else
					warn("[PurchaseSkinGui] Failed to prompt purchase:", err)
				end
			else
				warn("[PurchaseSkinGui] Skin has no roblox_asset_id:", skin.name)
			end
		end)
	end

	item.Visible = true
	return item
end


-- Show "Nothing Available" state
local function showNothingAvailable()
	local item = purchaseTemplate:Clone()
	item.Name = "NothingAvailable"

	-- Find GUI elements
	local imageFrame = Utils.findDescendantByName(item, "Image")
	local textLabel = imageFrame and Utils.findDescendantByName(imageFrame, "Text")
	local purchaseButton = Utils.findDescendantByName(item, "PurchaseButton")
	local viewportFrame = imageFrame and imageFrame:FindFirstChildWhichIsA("ViewportFrame")

	-- Hide the purchase button
	if purchaseButton then
		purchaseButton.Visible = false
	end

	-- Hide viewport
	if viewportFrame then
		viewportFrame.Visible = false
	end

	-- Show the "Nothing Available" text
	if textLabel then
		textLabel.Text = "Nothing Available"
		textLabel.Visible = true
	end

	item.Visible = true
	item.Parent = scrollingFrame
end


-- Clear existing items (except templates and layout elements)
local function clearItems()
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		-- Keep templates and UI layout/constraint elements
		local isTemplate = (child.Name == "PurchaseTemplate" or child.Name == "CashPurchaseTemplate")
		local isUIElement = child:IsA("UIGridLayout") or child:IsA("UIListLayout") or
		                    child:IsA("UIPadding") or child:IsA("UICorner") or
		                    child:IsA("UIStroke") or child:IsA("UIAspectRatioConstraint")

		-- Destroy everything else (including both visible and invisible items)
		if not isTemplate and not isUIElement then
			child:Destroy()
		end
	end
end


-- Load all purchasable skins
local function loadItems()
	-- Prevent concurrent loads
	if isLoading then
		return
	end
	isLoading = true

	-- Always clear caches and items first
	playerCache = nil
	allSkins = nil
	clearItems()

	-- Fetch player cache and all skins
	playerCache = GetPlayerCache:InvokeServer()
	local rawSkins = GetDataCache:InvokeServer("Skins")

	if not rawSkins then
		warn("Failed to fetch all skins")
		showNothingAvailable()
		isLoading = false
		return
	end

	-- Deduplicate skins by name
	local seenNames = {}
	allSkins = {}
	for _, skin in ipairs(rawSkins) do
		if skin.name and not seenNames[skin.name] then
			seenNames[skin.name] = true
			table.insert(allSkins, skin)
		end
	end

	-- Get purchasable skins (sorted by price low to high)
	local purchasableSkins = getPurchasableSkins()

	-- Check if there's anything to display
	if #purchasableSkins == 0 then
		showNothingAvailable()
	else
		-- Create Robux purchase items
		print("[PurchaseSkinGui] Creating", #purchasableSkins, "Robux purchase items")
		for i, skin in ipairs(purchasableSkins) do
			print("[PurchaseSkinGui] Cloning template for skin #" .. i .. ":", skin.name)
			local item = purchaseTemplate:Clone()
			loadPurchaseItem(item, skin)
			item.Parent = scrollingFrame
		end

		print("[PurchaseSkinGui] ScrollingFrame children count:", #scrollingFrame:GetChildren())
	end

	-- Update canvas size for scrolling
	RunService.RenderStepped:Wait()
	local grid = scrollingFrame:FindFirstChildOfClass("UIGridLayout")
	local padding = scrollingFrame:FindFirstChildOfClass("UIPadding")

	if grid then
		local totalHeight = grid.AbsoluteContentSize.Y
		if padding then
			totalHeight += padding.PaddingTop.Offset
			totalHeight += padding.PaddingBottom.Offset
		end
		scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)
	end

	isLoading = false
end


-- First load handler
local function onVisibilityChanged()
	if mainGui.Visible then
		loadItems()
	end
end


-- Monitor mainGui.Visible for changes
mainGui:GetPropertyChangedSignal("Visible"):Connect(onVisibilityChanged)

-- Helper to refresh after purchase
function refreshAfterPurchase(source, identifier)
	print("[PurchaseSkinGui] Refreshing after purchase from:", source, identifier or "")

	-- Wait for server to process
	task.wait(1)

	-- Reload if still visible (loadItems clears caches internally)
	if mainGui.Visible then
		isLoading = false  -- Reset guard to allow refresh
		loadItems()
	end
end

-- Listen for successful skin purchases to refresh the UI
if SkinPurchased then
	SkinPurchased.OnClientEvent:Connect(function(skinName)
		print("[PurchaseSkinGui] SkinPurchased event received:", skinName)
		refreshAfterPurchase("SkinPurchased", skinName)
	end)
else
	warn("[PurchaseSkinGui] SkinPurchased RemoteEvent not found in ReplicatedStorage")
end

-- Also listen for MarketplaceService purchase completion as a backup
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
	if userId == player.UserId and isPurchased then
		print("[PurchaseSkinGui] PromptProductPurchaseFinished - ProductId:", productId, "isPurchased:", isPurchased)
		refreshAfterPurchase("MarketplaceService", productId)
	end
end)
