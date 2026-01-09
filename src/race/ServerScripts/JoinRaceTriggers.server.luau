--#RACE
-- Handles JoinRace triggers: Common, Rare, Epic, Legendary
-- When player touches GuiTrigger, shows NextGui with the appropriate level
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Get JoinRace folder from workspace
local joinRaceFolder = workspace:WaitForChild("JoinRace")

-- Remote event for showing NextGui
local showNextEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowNext")

-- Track touch counts per player per trigger (how many body parts are touching)
local touchCounts = {}

-- Track if GUI is currently shown for player
local guiShown = {}

-- Delay before hiding GUI after last touch ends (prevents flicker)
local HIDE_DELAY = 0.3


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


-- Setup triggers for each level
local function setupLevelTrigger(levelModel)
	local levelName = levelModel.Name -- "Common", "Rare", "Epic", "Legendary"

	-- Find the GuiTrigger part
	local guiTrigger = levelModel:FindFirstChild("GuiTrigger")
	if not guiTrigger then
		warn("[JoinRaceTriggers] GuiTrigger not found in " .. levelName)
		return
	end

	-- Initialize tracking for this level
	touchCounts[levelName] = {}
	guiShown[levelName] = {}

	-- Touch event - show NextGui
	guiTrigger.Touched:Connect(function(hit)
		local plr = getPlayerFromPart(hit)
		if not plr then return end

		-- Increment touch count
		touchCounts[levelName][plr] = (touchCounts[levelName][plr] or 0) + 1

		-- Show GUI only if not already shown
		if not guiShown[levelName][plr] then
			guiShown[levelName][plr] = true
			showNextEvent:FireClient(plr, true, levelName)
		end
	end)

	-- TouchEnded event - hide NextGui with delay and verification
	guiTrigger.TouchEnded:Connect(function(hit)
		local plr = getPlayerFromPart(hit)
		if not plr then return end

		-- Decrement touch count
		touchCounts[levelName][plr] = math.max(0, (touchCounts[levelName][plr] or 1) - 1)

		-- Only consider hiding if touch count is 0
		if touchCounts[levelName][plr] == 0 and guiShown[levelName][plr] then
			-- Delay and verify player is actually outside
			task.delay(HIDE_DELAY, function()
				-- Double-check: is player still not touching?
				if touchCounts[levelName][plr] == 0 and not isPlayerTouchingTrigger(guiTrigger, plr) then
					if guiShown[levelName][plr] then
						guiShown[levelName][plr] = false
						showNextEvent:FireClient(plr, false, levelName)
					end
				end
			end)
		end
	end)
end


-- Setup all level triggers
local levels = {"Common", "Rare", "Epic", "Legendary"}
for _, levelName in ipairs(levels) do
	local levelModel = joinRaceFolder:FindFirstChild(levelName)
	if levelModel then
		setupLevelTrigger(levelModel)
	else
		warn("[JoinRaceTriggers] Level model not found: " .. levelName)
	end
end


-- Clean up when players leave
Players.PlayerRemoving:Connect(function(plr)
	for levelName, counts in pairs(touchCounts) do
		if counts[plr] then
			counts[plr] = nil
		end
	end
	for levelName, shown in pairs(guiShown) do
		if shown[plr] then
			shown[plr] = nil
		end
	end
end)
