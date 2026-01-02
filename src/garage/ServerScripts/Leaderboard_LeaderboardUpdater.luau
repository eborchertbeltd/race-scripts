-- LeaderboardUpdater.lua
-- Generic script to update leaderboard billboards with data from the API
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))

local LeaderboardUpdater = {}

-- Configuration for each leaderboard type
local LEADERBOARD_CONFIG = {
	LeaderboardWon = {
		api_key = "most_races_won",
		heading = "Most Races Won",
		stat_name = "total_races_won",
		suffix = "Wins"
	},
	LeaderboardLost = {
		api_key = "most_races_lost",
		heading = "Most Races Lost",
		stat_name = "total_races_lost",
		suffix = "Losses"
	},
	LeaderboardRichest = {
		api_key = "richest_players",
		heading = "Richest Players",
		stat_name = "money",
		suffix = "",
		format_money = true
	},
	LeaderboardMoneyWon = {
		api_key = "most_money_won",
		heading = "Most Money Won",
		stat_name = "total_money_won",
		suffix = "",
		format_money = true
	},
	LeaderboardPlayTime = {
		api_key = "most_time_played",
		heading = "Most Time Played",
		stat_name = "total_play_time",
		suffix = "",
		format_time = true
	},
	LeaderboardSponsor = {
		api_key = "highest_sponsor_level",
		heading = "Highest Sponsor Level",
		stat_name = "sponsor_level",
		suffix = "",
		format_percentage = true,
		max_value = 2.0  -- Max sponsor level is 2
	}
}

-- Cache for last successful leaderboard data
local leaderboardCache = {}

-- Random colors for positions 2-10
local randomColors = {
	Color3.fromRGB(255, 100, 100),  -- Red
	Color3.fromRGB(100, 150, 255),  -- Blue
	Color3.fromRGB(255, 200, 100),  -- Orange
	Color3.fromRGB(255, 100, 255),  -- Magenta
	Color3.fromRGB(100, 255, 200),  -- Cyan
	Color3.fromRGB(255, 255, 100),  -- Yellow
	Color3.fromRGB(200, 100, 255),  -- Purple
	Color3.fromRGB(100, 255, 100),  -- Light Green
	Color3.fromRGB(255, 150, 200),  -- Pink
}

-- Get color for a position
local function getPositionColor(position)
	if position == 1 then
		-- First place is green
		return Color3.fromRGB(0, 255, 0)
	else
		-- Other positions get random colors
		local colorIndex = ((position - 2) % #randomColors) + 1
		return randomColors[colorIndex]
	end
end

-- Format time in seconds to readable format (e.g., "2h 30m")
local function formatTime(seconds)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm", minutes)
	else
		return string.format("%ds", seconds)
	end
end

-- Format value as percentage (e.g., "75%")
local function formatPercentage(value, maxValue)
	local percentage = (value / maxValue) * 100
	return string.format("%.0f%%", percentage)
end

-- Format money value (e.g., "$1,234.56")
local function formatMoney(amount)
	local formatted = string.format("%.2f", amount)
	-- Add commas for thousands
	formatted = formatted:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	-- Remove leading comma if present
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return "$" .. formatted
end

-- Get player username from roblox_id using Roblox API
local function getPlayerName(robloxId)
	local success, result = pcall(function()
		return Players:GetNameFromUserIdAsync(robloxId)
	end)

	if success then
		return result
	else
		return "Player#" .. robloxId
	end
end

-- Fetch leaderboard data from API
local function fetchLeaderboardData()
	local API_KEY = "Q4IKL6tkmuvZUnImZZlz6hcX88WwXrgqdUkaEZLY3MM"
	local BASE_URL = "https://thegamermatch.com/api/"
	local endpoint = "leaderboards/"

	local headers = {
		["Authorization"] = "Api-Key " .. API_KEY
	}

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = BASE_URL .. endpoint,
			Method = "GET",
			Headers = headers
		})
	end)

	if success and response.Success then
		local data = HttpService:JSONDecode(response.Body)
		if data.success then
			return data.leaderboards
		end
	end
	return nil
end

-- Update a specific leaderboard billboard
local function updateLeaderboard(modelName)
	local config = LEADERBOARD_CONFIG[modelName]
	if not config then
		return
	end

	-- Find the leaderboard model in workspace
	local leaderboardModel = workspace:FindFirstChild(modelName, true)
	if not leaderboardModel then
		return
	end

	-- Find the SurfaceGui
	local surfaceGui = leaderboardModel:FindFirstChild("Leaderboard", true)
	if not surfaceGui or not surfaceGui:IsA("SurfaceGui") then
		return
	end

	-- Fetch leaderboard data
	local leaderboards = fetchLeaderboardData()
	if not leaderboards then
		return
	end

	-- Cache the data for this leaderboard
	leaderboardCache[modelName] = leaderboards

	-- Get the specific leaderboard data
	local data = leaderboards[config.api_key]
	if not data then
		return
	end

	print(string.format("[Leaderboard] Updating %s with %d entries", modelName, #data))

	-- Update heading
	local headingFrame = surfaceGui:FindFirstChild("Heading")
	if headingFrame then
		local headingText = headingFrame:FindFirstChild("Text")
		if headingText then
			local headingLabel = headingText:FindFirstChild("TextLabel")
			if headingLabel then
				headingLabel.Text = config.heading
			end
		end
	end

	-- Update positions 1-10
	for i = 1, 10 do
		local positionFrame = surfaceGui:FindFirstChild("Position" .. i)
		if positionFrame then
			local textFrame = positionFrame:FindFirstChild("Text")
			if textFrame then
				local textLabel = textFrame:FindFirstChild("TextLabel")
				if textLabel then
					if data[i] then
						-- Get player data
						local entry = data[i]
						local robloxId = entry.roblox_id
						local statValue = entry[config.stat_name]

						-- Get player name
						local playerName = getPlayerName(robloxId)

						-- Format the stat value
						local formattedValue
						if config.format_money then
							formattedValue = formatMoney(statValue)
						elseif config.format_time then
							formattedValue = formatTime(statValue)
						elseif config.format_percentage then
							formattedValue = formatPercentage(statValue, config.max_value)
						elseif config.suffix ~= "" then
							formattedValue = string.format("%d %s", statValue, config.suffix)
						else
							formattedValue = tostring(statValue)
						end

						-- Set the text with rank
						textLabel.Text = string.format("#%d %s - %s", i, playerName, formattedValue)

						-- Set the color based on position
						textLabel.TextColor3 = getPositionColor(i)
					else
						-- No data for this position
						textLabel.Text = "---"
						textLabel.TextColor3 = Color3.fromRGB(150, 150, 150)  -- Gray for empty slots
					end
				end
			end
		end
	end

	print(string.format("[Leaderboard] Successfully updated %s", modelName))
end

-- Start updating a leaderboard on a 5-minute interval
function LeaderboardUpdater.Start(modelName)
	print(string.format("[Leaderboard] Starting updater for %s", modelName))

	-- Initial update
	updateLeaderboard(modelName)

	-- Update every 5 minutes (300 seconds)
	task.spawn(function()
		while true do
			task.wait(300)
			updateLeaderboard(modelName)
		end
	end)
end

-- Manually update a leaderboard (useful for testing)
function LeaderboardUpdater.Update(modelName)
	updateLeaderboard(modelName)
end

-- Update all configured leaderboards
function LeaderboardUpdater.UpdateAll()
	for modelName, _ in pairs(LEADERBOARD_CONFIG) do
		updateLeaderboard(modelName)
	end
end

-- Start all configured leaderboards
function LeaderboardUpdater.StartAll()
	for modelName, _ in pairs(LEADERBOARD_CONFIG) do
		LeaderboardUpdater.Start(modelName)
	end
end

return LeaderboardUpdater
