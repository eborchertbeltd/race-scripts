local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	-- ✅ Create BlueprintInventory if missing
	if not player:FindFirstChild("BlueprintInventory") then
		local bpFolder = Instance.new("Folder")
		bpFolder.Name = "BlueprintInventory"
		bpFolder.Parent = player
	end

	-- ✅ Create MaterialInventory if missing
	if not player:FindFirstChild("MaterialInventory") then
		local matFolder = Instance.new("Folder")
		matFolder.Name = "MaterialInventory"
		matFolder.Parent = player
	end
end)