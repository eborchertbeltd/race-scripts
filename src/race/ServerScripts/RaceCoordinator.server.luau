-- ServerScriptService/RaceCoordinator.lua
-- Core race runner: ensures there is always a queued race per level and ticks every 60s

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

local LEVELS = {"Common","Rare","Epic","Legendary"}

local function hasPendingForTrackLevel(pendingList, trackId, level)
	for _, r in ipairs(pendingList) do
		if r.level == level and tostring(r.track) == tostring(trackId) and r.ready == false then
			return true
		end
	end
	return false
end

local function ensureQueuedForTrackLevel(trackId, level, pendingList)
	if hasPendingForTrackLevel(pendingList, trackId, level) then return end
	local created = ApiService.CreateRaceQueue(trackId, SERVER_ID, level)
	if created then
		print(string.format("[RaceCoordinator] Created race queue track=%s level=%s (server=%s)", tostring(trackId), level, SERVER_ID))
	else
		warn(string.format("[RaceCoordinator] Failed to create race queue for track=%s level=%s", tostring(trackId), level))
	end
end


local function tickOnce()
	-- get pending (ready=false) races
	local pending = ServerData.GetPendingRaces(SERVER_ID)
	local tracksByName = ServerData.LoadTracks() or {}
	for _, lvl in ipairs(LEVELS) do
		for name, track in pairs(tracksByName) do
			if track and track.id then
				ensureQueuedForTrackLevel(track.id, lvl, pending)
			end
		end
	end
	ServerData.ClearRaceQueue()
end

-- Start the next race for a given track name
function startNextRace(trackName)
	print("[RaceCoordinator] startNextRace called for:", trackName)
	if not trackName or trackName == "" then
		warn("[RaceCoordinator] startNextRace missing trackName")
		return
	end
	local track = ServerData.GetTrackByName(trackName)
	print("[RaceCoordinator] GetTrackByName result:", track and track.id or "nil")
	if not track or not track.id then
		warn("[RaceCoordinator] Track not found:", trackName)
		return
	end
	print("[RaceCoordinator] Getting next race for server:", SERVER_ID, "track:", trackName)
	local nextRace = ServerData.GetNextRace(SERVER_ID, trackName)
	print("[RaceCoordinator] GetNextRace result:", nextRace and nextRace.id or "nil", "number:", nextRace and nextRace.number or "nil")
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
	-- 2) Choose bindable by track name
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
	-- 3) Compute top speed based on level
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
	-- 4) Invoke bindable with parameters
	-- Consumers should agree on payload shape; we'll pass a table
	local payload = {
		track = trackName,
		level = lvl,
		number = updated.number,  -- Include race number for UI display
		top_speed = topSpeed,
		laps = laps,
		runner = updated.id,
		expected_order = expectedOrder,
		race_id = updated.id,
	}

	print("[RaceCoordinator] About to invoke", trackName, "race with payload:", payload)
	local ok
	-- Fire and forget - don't wait for race to complete
	print("[RaceCoordinator] Starting", trackName, "race invoke (fire and forget)...")

	-- Spawn the race in the background and don't wait for it
	task.spawn(function()
		local success, result = pcall(function()
			return bindable:Invoke(payload)
		end)

		if success then
			print("[RaceCoordinator]", trackName, "race invoke completed with result:", result)
		else
			warn("[RaceCoordinator]", trackName, "race invoke failed:", result)
		end
	end)

	-- Immediately continue without waiting
	success = true
	result = "Started in background"
	if not success then
		warn("[RaceCoordinator] Bindable invoke failed:", result)
	end
	-- 5) Set race_started timestamp
	local isoNow = os.date("!%Y-%m-%dT%H:%M:%SZ")
	ApiService.UpdateRace(updated.id, { race_started = isoNow })
	-- 6) Create replacement race for this track/level
	ApiService.CreateRaceQueue(track.id, SERVER_ID, lvl)
	-- 7) Clear cached queue so next tick refreshes
	ServerData.ClearRaceQueue(SERVER_ID)
end

-- TriggerNextRace bindable: waits track.seconds_between then starts next race for that track
local function triggerNextRace(trackName)
	if not trackName or trackName == "" then
		warn("[RaceCoordinator] triggerNextRace missing trackName")
		return
	end
	local track = ServerData.GetTrackByName(trackName)
	if not track then
		warn("[RaceCoordinator] triggerNextRace track not found:", trackName)
		return
	end
	local waitSeconds = tonumber(track.seconds_between) or 0
	if waitSeconds > 0 then
		task.wait(waitSeconds)
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
	print("[RaceCoordinator] Waiting 10 seconds before initial race kickoff...")
	task.wait(10)
	print("[RaceCoordinator] 10-second wait complete, loading tracks...")
	local tracksByName = ServerData.LoadTracks() or {}
	print("[RaceCoordinator] Loaded tracks:", tracksByName and "success" or "nil")

	-- Debug: print what tracks we got
	local trackCount = 0
	for name, track in pairs(tracksByName) do
		trackCount = trackCount + 1
		print("[RaceCoordinator] Found track:", name, "id:", track and track.id or "nil")
	end
	print("[RaceCoordinator] Total tracks found:", trackCount)

	if trackCount == 0 then
		warn("[RaceCoordinator] No tracks found! Cannot start races.")
		return
	end

	for name, track in pairs(tracksByName) do
		if track and track.id then
			print("[RaceCoordinator] Starting race for track:", name)
			startNextRace(name)
		else
			warn("[RaceCoordinator] Track missing id:", name)
		end
	end
	print("[RaceCoordinator] Initial race kickoff complete")
end)


