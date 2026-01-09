local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))

-- Get the ImageLabel
local player = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local materialUI = player:WaitForChild("PlayerGui"):WaitForChild("BlueprintUI")
local imageLabel = Utils.findDescendantByName(materialUI, "Wheel")
local purchaseButton = Utils.findDescendantByName(materialUI, "Purchase")
local spinning = false
local makeSpin = ReplicatedStorage:WaitForChild("Player"):WaitForChild("MakeSpin")
local rolled = Utils.findDescendantByName(materialUI, "Rolled")

-- Create the spin sound
local spinSound = Instance.new("Sound")
spinSound.SoundId = "rbxassetid://127293612026255"
spinSound.Volume = 0.5  -- Adjust volume as needed (0-1)
spinSound.Parent = SoundService

-- Create the wheel stop sound
local stopSound = Instance.new("Sound")
stopSound.SoundId = "rbxassetid://121925340930845"
stopSound.Volume = 0.5  -- Adjust volume as needed (0-1)
stopSound.Parent = SoundService



local function showAndFade(frame, showTime, fadeTime)
	-- Make sure it starts fully visible
	frame.Visible = true

	-- Wait before fading
	task.wait(showTime)

	-- Create and play the fade tween
	local fadeTween = TweenService:Create(frame, TweenInfo.new(fadeTime), { BackgroundTransparency = 1 })
	fadeTween:Play()

	-- When the fade is done, hide the frame
	fadeTween.Completed:Connect(function()
		frame.Visible = false
	end)
end

-- Example usage:
-- Show frame for 1 second, fade for 0.5 seconds

function SpinWheel(wheel, spins)
	local rotations = {
		Common = 270,
		Rare = 124,
		Epic = 46,
		Legendary = 9
	}
	local result = makeSpin:InvokeServer("BlueprintTemplate")
	local targetRotation = rotations[result.item_details.level]
	wheel.Rotation = 0
	spins = spins or 6           -- tweak for more/less drama
	local decelTime = 1.5        -- seconds; all done in this one tween

	-- Normalize inputs
	targetRotation = ((targetRotation % 360) + 360) % 360
	local start = wheel.Rotation
	-- Compute an end angle that equals targetRotation modulo 360,
	-- while spinning forward `spins` full turns.
	local endAngle = (math.floor(start / 360) * 360) + (spins * 360) + targetRotation

	-- Ensure we always move forward at least one full spin
	if endAngle <= start then
		endAngle = endAngle + 360
	end

	local tween = TweenService:Create(
		wheel,
		TweenInfo.new(decelTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Rotation = endAngle }
	)

	tween:Play()

	return result
end


function showReward(result)
	Utils.switchColorIcon(rolled, result.item_details.level)
	local name = Utils.findDescendantByName(rolled, "Name")
	local quantity = Utils.findDescendantByName(rolled, "Quantity")
	local nameItemLabel = Utils.findDescendantByName(name, "ItemLabel")
	local nameItemLabelStroke = Utils.findDescendantByName(name, "ItemLabelStroke")
	local quantityItemLabel = Utils.findDescendantByName(quantity, "ItemLabel")
	local quantityItemLabelStroke = Utils.findDescendantByName(quantity, "ItemLabelStroke")
	local itemName = Utils.split(result.item_details.name, "-")
	nameItemLabel.Text = itemName[1]
	nameItemLabelStroke.Text = itemName[1]
	quantityItemLabel.Text = "Qty: " .. result.quantity_added
	quantityItemLabelStroke.Text = "Qty: " .. result.quantity_added
	showAndFade(rolled, 1, 1)
end


local BLUEPRINT_SPIN_COST = 100

purchaseButton.MouseButton1Click:Connect(function()
	local playerMoney = tonumber(player:GetAttribute("Money")) or 0
	if not spinning and playerMoney >= BLUEPRINT_SPIN_COST then
		spinning = true
		-- Play the spin sound
		spinSound:Play()
		local result = SpinWheel(imageLabel, 6)
		task.wait(1.5)
		-- Play the stop sound when wheel finishes
		stopSound:Play()
		player:SetAttribute("Money", result.remaining_money)
		showReward(result)
		spinning = false
	end
end)
-- Example usage:
-- local wheel = script.Parent -- your ImageLabel
-- SpinWheel(wheel, 270) -- stop at 270 degrees