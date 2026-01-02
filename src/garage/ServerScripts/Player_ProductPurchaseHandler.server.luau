-- ProductPurchaseHandler.lua
-- Server script to handle Developer Product purchases (ProcessReceipt)
-- Place this in ServerScriptService.Player

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ApiService = require(ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
local ServerData = require(ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Data_DataCache"))
local PlayerCache = require(ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Player_PlayerCache"))

-- Cache of product ID -> skin data for quick lookups
local productToSkinMap = {}

-- Build the product to skin mapping from API data
local function buildProductMap()
	local skins = ServerData.GetAllSkins()
	if not skins then
		warn("[ProductPurchaseHandler] Failed to get skins for product mapping")
		return
	end

	for _, skin in ipairs(skins) do
		if skin.roblox_asset_id then
			productToSkinMap[skin.roblox_asset_id] = {
				id = skin.id,
				name = skin.name,
				price = skin.price
			}
			print("[ProductPurchaseHandler] Mapped ProductId", skin.roblox_asset_id, "->", skin.name)
		end
	end

	print("[ProductPurchaseHandler] Product map built with", #skins, "skins")
end

-- Handle the purchase receipt
local function processReceipt(receiptInfo)
	-- receiptInfo contains:
	-- PlayerId - the player who made the purchase
	-- ProductId - the Developer Product ID purchased
	-- PurchaseId - unique identifier for this purchase

	local playerId = receiptInfo.PlayerId
	local productId = receiptInfo.ProductId

	print("[ProductPurchaseHandler] Processing purchase - Player:", playerId, "Product:", productId)

	-- Get the player
	local player = Players:GetPlayerByUserId(playerId)
	if not player then
		warn("[ProductPurchaseHandler] Player not in game:", playerId)
		-- Return NotProcessedYet so it can be processed when they rejoin
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Look up the skin from our map
	local skinData = productToSkinMap[productId]
	if not skinData then
		-- Rebuild the map in case new skins were added
		ServerData.ClearSkins()
		buildProductMap()
		skinData = productToSkinMap[productId]
	end

	if not skinData then
		warn("[ProductPurchaseHandler] Unknown product ID:", productId)
		-- Grant anyway to avoid charging without delivery - this shouldn't happen in production
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	print("[ProductPurchaseHandler] Granting skin:", skinData.name, "to player:", playerId)

	-- Grant the skin via API
	local result = ApiService.GrantPlayerVehicleSkin(playerId, skinData.id)

	if result then
		print("[ProductPurchaseHandler] Successfully granted skin:", skinData.name, "to player:", playerId)

		-- Clear the player's cache so they get fresh data with the new skin
		PlayerCache.Clear(playerId)
		print("[ProductPurchaseHandler] Cleared PlayerCache for:", playerId)

		-- Fire an event to notify the client (so they can refresh their UI)
		local RemoteEvents = game.ReplicatedStorage:FindFirstChild("RemoteEvents")
		local SkinPurchased = RemoteEvents and RemoteEvents:FindFirstChild("SkinPurchased")
		if SkinPurchased then
			SkinPurchased:FireClient(player, skinData.name)
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	else
		warn("[ProductPurchaseHandler] Failed to grant skin:", skinData.name, "to player:", playerId)
		-- Return NotProcessedYet so Roblox will retry later
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

-- Initialize
local function initialize()
	-- Build the product mapping
	buildProductMap()

	-- Set up the receipt processor
	MarketplaceService.ProcessReceipt = processReceipt

	print("[ProductPurchaseHandler] Initialized and ready to process purchases")
end

-- Wait a moment for other services to initialize, then start
task.spawn(function()
	task.wait(2)
	initialize()
end)

