local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local frame = playerGui:WaitForChild("BaseGui"):WaitForChild("Canvas"):WaitForChild("Money")


-- ✅ Function to update all TextLabels under the frame
local function updateMoneyLabels()
	for _, child in ipairs(frame:GetDescendants()) do
		local money = player:GetAttribute("Money") or 0
		if child:IsA("TextLabel") then
			child.Text = "$" .. math.floor(tostring(money))
		end
	end
end

updateMoneyLabels()

player:GetAttributeChangedSignal("Money"):Connect(updateMoneyLabels)