--#RACE
-- Handles Bet triggers: BetDirt, BetRoad, BetDrag, BetOval
-- When player touches GuiTrigger, shows BetGui with the appropriate track
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Get Bet folder from workspace
local betFolder = workspace:WaitForChild("Bet")

-- Remote event for showing BetGui
local showBetEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowBet")

-- Track touch counts per player per trigger (how many body parts are touching)
local touchCounts = {}

-- Track if GUI is currently shown for player
local guiShown = {}

-- Delay before hiding GUI after last touch ends (prevents flicker)
local HIDE_DELAY = 0.3

-- Map trigger names to track names
local triggerToTrack = {
	BetDirt = "Dirt",
	BetRoad = "Road",
	BetDrag = "Drag",
	BetOval = "Oval"
}


local function getPlayerFromPart(part)
	local char = part:FindFirstAncestorWhichIsA("Model")
	if not char then return nil end
	local plr = Players:GetPlayerFromCharacter(char)
	return plr
end


-- Check if any part of player is still touching the trigger
local function isPlayerTouchingTrigger(trigger, player)
	local char = player.Character
	if not char then return false end

	local touchingParts = trigger:GetTouchingParts()
	for _, part in ipairs(touchingParts) do
		if part:IsDescendantOf(char) then
			return true
		end
	end
	return false
end


-- Setup triggers for each track
local function setupTrackTrigger(triggerModel)
	local triggerName = triggerModel.Name -- "BetDirt", "BetRoad", etc.
	local trackName = triggerToTrack[triggerName]

	if not trackName then
		warn("[BetTriggers] Unknown trigger name: " .. triggerName)
		return
	end

	-- Find the GuiTrigger part
	local guiTrigger = triggerModel:FindFirstChild("GuiTrigger")
	if not guiTrigger then
		warn("[BetTriggers] GuiTrigger not found in " .. triggerName)
		return
	end

	-- Initialize tracking for this trigger
	touchCounts[triggerName] = {}
	guiShown[triggerName] = {}

	-- Touch event - show BetGui
	guiTrigger.Touched:Connect(function(hit)
		local plr = getPlayerFromPart(hit)
		if not plr then return end

		-- Increment touch count
		touchCounts[triggerName][plr] = (touchCounts[triggerName][plr] or 0) + 1

		-- Show GUI only if not already shown
		if not guiShown[triggerName][plr] then
			guiShown[triggerName][plr] = true
			showBetEvent:FireClient(plr, true, trackName)
		end
	end)

	-- TouchEnded event - hide BetGui with delay and verification
	guiTrigger.TouchEnded:Connect(function(hit)
		local plr = getPlayerFromPart(hit)
		if not plr then return end

		-- Decrement touch count
		touchCounts[triggerName][plr] = math.max(0, (touchCounts[triggerName][plr] or 1) - 1)

		-- Only consider hiding if touch count is 0
		if touchCounts[triggerName][plr] == 0 and guiShown[triggerName][plr] then
			-- Delay and verify player is actually outside
			task.delay(HIDE_DELAY, function()
				-- Double-check: is player still not touching?
				if touchCounts[triggerName][plr] == 0 and not isPlayerTouchingTrigger(guiTrigger, plr) then
					if guiShown[triggerName][plr] then
						guiShown[triggerName][plr] = false
						showBetEvent:FireClient(plr, false, trackName)
					end
				end
			end)
		end
	end)

	print("[BetTriggers] Setup trigger for", triggerName, "->", trackName)
end


-- Setup all track triggers
local triggers = {"BetDirt", "BetRoad", "BetDrag", "BetOval"}
for _, triggerName in ipairs(triggers) do
	local triggerModel = betFolder:FindFirstChild(triggerName)
	if triggerModel then
		setupTrackTrigger(triggerModel)
	else
		warn("[BetTriggers] Trigger model not found: " .. triggerName)
	end
end


-- Clean up when players leave
Players.PlayerRemoving:Connect(function(plr)
	for triggerName, counts in pairs(touchCounts) do
		if counts[plr] then
			counts[plr] = nil
		end
	end
	for triggerName, shown in pairs(guiShown) do
		if shown[plr] then
			shown[plr] = nil
		end
	end
end)
