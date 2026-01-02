-- InitLeaderboards.lua
-- Place this script in ServerScriptService to start leaderboard updates
-- This script initializes and starts all leaderboard updaters

local LeaderboardUpdater = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Leaderboard_LeaderboardUpdater"))

print("[InitLeaderboards] Starting leaderboard system...")

-- Start all leaderboards
LeaderboardUpdater.Start("LeaderboardWon")          -- Most Races Won
LeaderboardUpdater.Start("LeaderboardLost")         -- Most Races Lost
LeaderboardUpdater.Start("LeaderboardRichest")      -- Richest Players
LeaderboardUpdater.Start("LeaderboardMoneyWon")     -- Most Money Won
LeaderboardUpdater.Start("LeaderboardPlayTime")     -- Most Time Played
LeaderboardUpdater.Start("LeaderboardSponsor")      -- Highest Sponsor Level

print("[InitLeaderboards] Leaderboard system initialized")

-- Optional: Create a remote function for manual updates (useful for testing)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UpdateLeaderboardEvent = Instance.new("RemoteEvent")
UpdateLeaderboardEvent.Name = "UpdateLeaderboard"
UpdateLeaderboardEvent.Parent = ReplicatedStorage

UpdateLeaderboardEvent.OnServerEvent:Connect(function(player, modelName)
	-- Only allow admins to manually update (optional security)
	if player:GetRankInGroup(0) >= 255 then -- Adjust as needed
		print(string.format("[InitLeaderboards] Manual update requested by %s for %s", player.Name, modelName or "all"))
		if modelName then
			LeaderboardUpdater.Update(modelName)
		else
			LeaderboardUpdater.UpdateAll()
		end
	end
end)
