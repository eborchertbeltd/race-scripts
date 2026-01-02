local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

--[[Hide all ScreenGuis and their main Frames at start
for _, gui in ipairs(playerGui:GetChildren()) do
	if gui:IsA("ScreenGui") then
		gui.Enabled = false   -- hides the entire GUI
	end
end

-- Optional: watch for new GUIs that get added later
playerGui.ChildAdded:Connect(function(child)
	if child:IsA("ScreenGui") then
		child.Enabled = false
	end
end)
]]