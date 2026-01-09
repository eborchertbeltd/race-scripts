-- ServerScriptService/RaceCoordinator.lua
-- Core race runner: manages race queue and starts races
-- Common races are only created automatically when the queue is empty for a track
-- Other levels (Rare, Epic, Legendary) are created on-demand when players join
-- While no players are joining, a loop of Common races runs continuously

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("GameApiService"))
local ServerData = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("ServerData"))

-- Identify this server
local SERVER_ID = game.JobId ~= "" and game.JobId or "local-server"

-- BindableFunctions to start races (wired elsewhere)
local StartDragRace = game.ServerScriptService:WaitForChild("StartDragRace")
local StartOvalRace = game.ServerScriptService:WaitForChild("StartOvalRace")
local StartDirtRace = game.ServerScriptService:WaitForChild("StartDirtRace")
local StartRoadRace = game.ServerScriptService:WaitForChild("StartRoadRace")
local TriggerNextRace = game.ServerScriptService:WaitForChild("TriggerNextRace")

-- Tracks will be discovered from the API via ServerData

-- Only Common races are auto-created; other levels created on-demand when players join
local DEFAULT_LEVEL = "Common"

-- Delay between races (seconds after last race ends before next starts)
local SECONDS_BETWEEN_RACES = 3

-- Check if there's ANY pending race for a track (any level)
local function hasPendingForTrack(pendingList, trackId)
	for _, r in ipairs(pendingList) do
		if tostring(r.track) == tostring(trackId) and r.ready == false then
			return true
		end
	end
	return false
end

-- Only create a Common race if the queue is completely empty for this track
local function ensureQueuedIfEmpty(trackId, pendingList)
	if hasPendingForTrack(pendingList, trackId) then return false end
	local created = ApiService.CreateRaceQueue(trackId, SERVER_ID, DEFAULT_LEVEL)
	if not created then
		warn(string.format("[RaceCoordinator] Failed to create Common race for track=%s", tostring(trackId)))
		return false
	end
	return true
end


local function tickOnce()
	-- get pending (ready=false) races
	local pending = ServerData.GetPendingRaces(SERVER_ID)
	local tracksByName = ServerData.LoadTracks() or {}
	-- Only create Common races if a track's queue is completely empty
	for name, track in pairs(tracksByName) do
		if track and track.id then
			ensureQueuedIfEmpty(track.id, pending)
		end
	end
	ServerData.ClearRaceQueue()
end

-- Start the next race for a given track name
function startNextRace(trackName)
	if not trackName or trackName == "" then
		warn("[RaceCoordinator] startNextRace missing trackName")
		return
	end
	local track = ServerData.GetTrackByName(trackName)
	if not track or not track.id then
		warn("[RaceCoordinator] Track not found:", trackName)
		return
	end
	local nextRace = ServerData.GetNextRace(SERVER_ID, trackName)
	if not nextRace then
		warn("[RaceCoordinator] No pending race for track:", trackName)
		return
	end
	-- 1) Mark ready=true to compute predictions
	local updated = ApiService.UpdateRace(nextRace.id, { ready = true })
	if not updated then
		warn("[RaceCoordinator] Failed to update race ready=true:", nextRace.id)
		return
	end

	-- 2) Create the next Common race immediately so billboard shows "Next"
	-- This race will be ready=false and appear in the Next section
	ServerData.ClearRaceQueue(SERVER_ID)
	local pending = ServerData.GetPendingRaces(SERVER_ID)
	local created = ensureQueuedIfEmpty(track.id, pending)
	if created then
		print("[RaceCoordinator] Created next Common race for", trackName, "after starting current race")
		ServerData.ClearRaceQueue(SERVER_ID)
	end
	-- 3) Choose bindable by track name
	local bindable
	if trackName == "Drag" then
		bindable = StartDragRace
	elseif trackName == "Oval" then
		bindable = StartOvalRace
	elseif trackName == "Dirt" then
		bindable = StartDirtRace
	elseif trackName == "Road" then
		bindable = StartRoadRace
	else
		warn("[RaceCoordinator] Unknown track bindable for:", trackName)
		return
	end
	-- 4) Compute top speed based on level
	local lvl = updated.level or nextRace.level or "Common"
	local topSpeedMap = {
		Common = track.top_speed_common,
		Rare = track.top_speed_rare,
		Epic = track.top_speed_epic,
		Legendary = track.top_speed_legendary,
	}
	local topSpeed = topSpeedMap[lvl] or track.top_speed_common or 0
	local laps = track.laps or 1
	local expectedOrder = updated.predicted_results_json or {}
	-- 5) Invoke bindable with parameters
	local payload = {
		track = trackName,
		level = lvl,
		number = updated.number,
		top_speed = topSpeed,
		laps = laps,
		runner = updated.id,
		expected_order = expectedOrder,
		race_id = updated.id,
	}

	-- Spawn the race in the background and don't wait for it
	task.spawn(function()
		local success, result = pcall(function()
			return bindable:Invoke(payload)
		end)

		if not success then
			warn("[RaceCoordinator]", trackName, "race invoke failed:", result)
		end
	end)

	-- 6) Set race_started timestamp
	local isoNow = os.date("!%Y-%m-%dT%H:%M:%SZ")
	ApiService.UpdateRace(updated.id, { race_started = isoNow })
	-- 7) Clear cached queue so next tick refreshes
	ServerData.ClearRaceQueue(SERVER_ID)
end

-- TriggerNextRace bindable: waits 3 seconds then starts next race for that track
local function triggerNextRace(trackName)
	if not trackName or trackName == "" then
		warn("[RaceCoordinator] triggerNextRace missing trackName")
		return
	end
	-- Wait fixed delay before starting next race
	task.wait(SECONDS_BETWEEN_RACES)

	-- Check if queue is empty for this track - if so, create a Common race
	local track = ServerData.GetTrackByName(trackName)
	if track and track.id then
		ServerData.ClearRaceQueue(SERVER_ID)  -- Refresh cache
		local pending = ServerData.GetPendingRaces(SERVER_ID)
		local created = ensureQueuedIfEmpty(track.id, pending)
		if created then
			-- Clear cache again so startNextRace sees the newly created race
			ServerData.ClearRaceQueue(SERVER_ID)
		end
	end

	startNextRace(trackName)
end

TriggerNextRace.OnInvoke = function(trackName)
	return triggerNextRace(trackName)
end

-- Initial check
tickOnce()

-- One-shot kickoff: wait 10s, then start one race per track
task.spawn(function()
	task.wait(10)
	local tracksByName = ServerData.LoadTracks() or {}

	local trackCount = 0
	for name, track in pairs(tracksByName) do
		trackCount = trackCount + 1
	end

	if trackCount == 0 then
		warn("[RaceCoordinator] No tracks found! Cannot start races.")
		return
	end

	for name, track in pairs(tracksByName) do
		if track and track.id then
			startNextRace(name)
		else
			warn("[RaceCoordinator] Track missing id:", name)
		end
	end
end)
