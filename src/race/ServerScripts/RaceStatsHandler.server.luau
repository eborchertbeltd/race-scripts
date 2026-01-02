-- RaceStatsHandler.lua
-- Server-side script to handle GetNextRaceInfo RemoteFunction
-- Place in ServerScriptService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerData = require(ServerScriptService:WaitForChild("GameScripts"):WaitForChild("ServerData"))

-- Server ID
local SERVER_ID = game.JobId ~= "" and game.JobId or "local-server"

-- Get or create RemoteEvents folder
local function getRemoteEventsFolder()
	local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RemoteEvents"
		folder.Parent = ReplicatedStorage
	end
	return folder
end

-- Get or create RemoteFunctions folder
local function getRemoteFunctionsFolder()
	local folder = ReplicatedStorage:FindFirstChild("RemoteFunctions")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RemoteFunctions"
		folder.Parent = ReplicatedStorage
	end
	return folder
end

-- Create GetNextRaceInfo RemoteFunction
local remoteFunctions = getRemoteFunctionsFolder()
local getNextRaceInfo = remoteFunctions:FindFirstChild("GetNextRaceInfo")
if not getNextRaceInfo then
	getNextRaceInfo = Instance.new("RemoteFunction")
	getNextRaceInfo.Name = "GetNextRaceInfo"
	getNextRaceInfo.Parent = remoteFunctions
end

-- Handle GetNextRaceInfo requests
getNextRaceInfo.OnServerInvoke = function(player, trackName)
	if not trackName or type(trackName) ~= "string" then
		return nil
	end

	-- Validate track name
	local validTracks = {Oval = true, Road = true, Dirt = true, Drag = true}
	if not validTracks[trackName] then
		return nil
	end

	-- Get race queue for this track
	local raceQueue = ServerData.GetRaceQueueForTrack(SERVER_ID, trackName)

	if not raceQueue or #raceQueue == 0 then
		return nil
	end

	-- Find the next race that hasn't started yet (ready = false, race_finished = false)
	-- Or the current race in progress (ready = true, race_finished = false)
	local nextRace = nil
	local currentRace = nil

	for _, race in ipairs(raceQueue) do
		local ready = race.ready or false
		local raceFinished = race.race_finished or false

		if ready and not raceFinished then
			-- Race is in progress
			currentRace = race
			break
		elseif not ready and not raceFinished then
			-- Race is queued
			if not nextRace then
				nextRace = race
			end
		end
	end

	-- Prefer current race over next race
	local raceToReturn = currentRace or nextRace

	if not raceToReturn then
		return nil
	end

	return {
		raceLevel = raceToReturn.level or "Common",
		raceNumber = raceToReturn.number,
		status = currentRace and "in_progress" or "waiting",
		totalLaps = raceToReturn.laps or (trackName == "Drag" and nil or 5)
	}
end

print("[RaceStatsHandler] GetNextRaceInfo RemoteFunction initialized")
