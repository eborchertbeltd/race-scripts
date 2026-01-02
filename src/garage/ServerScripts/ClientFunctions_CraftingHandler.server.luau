local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local requestCraftEvent = Instance.new("RemoteEvent")
requestCraftEvent.Name = "RequestCraftItem"
requestCraftEvent.Parent = ReplicatedStorage

local openUIEvent = Instance.new("RemoteEvent")
openUIEvent.Name = "OpenCraftingUI"
openUIEvent.Parent = ReplicatedStorage


-- ✅ Handle crafting requests
requestCraftEvent.OnServerEvent:Connect(function(player, bpId)
	local bpFolder = player:FindFirstChild("BlueprintInventory")
	local matFolder = player:FindFirstChild("MaterialInventory")

	if not bpFolder or not matFolder then return end

	local bpData
	if not bpData then return end

	-- ✅ Check player owns this blueprint
	local hasBlueprint
	for _, bp in ipairs(bpFolder:GetChildren()) do
		if bp.Value == bpId then hasBlueprint = bp; break end
	end
	if not hasBlueprint then return end

	-- ✅ Check materials
	for mat, reqAmount in pairs(bpData.Requires) do
		if (matFolder:GetAttribute(mat) or 0) < reqAmount then
			warn(player.Name .. " does not have enough " .. mat)
			return
		end
	end

	-- ✅ Deduct materials
	for mat, reqAmount in pairs(bpData.Requires) do
		matFolder:SetAttribute(mat, (matFolder:GetAttribute(mat) or 0) - reqAmount)
	end

	-- ✅ Remove one blueprint
	hasBlueprint:Destroy()

	-- ✅ Give crafted item
	local crafted = Instance.new("StringValue")
	crafted.Value = bpId .. "_Item"
	crafted.Name = "CraftedItem"
	crafted.Parent = bpFolder -- store in player inventory (or handle differently)

	print(player.Name .. " crafted " .. bpData.Name)
end)

