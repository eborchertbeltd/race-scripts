-- ServerScriptService/ServerData.lua
-- Cache for RaceQueue data with helpers to clear and get the next race to run

local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("GameApiService"))
local Utils = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Utils"))

local ServerData = {}

local _cache = {
	queues = {}, -- [serverId] = summary table from API (queued, in_progress, completed_recent)
	vehicleNames = {}, -- [vehicleId] = playerName
	playerVehicles = {}, -- [playerUserId] = {vehicles = {...}, lastUpdated = timestamp}
	playerNotifications = {}, -- [playerUserId] = {notifications = {...}, lastUpdated = timestamp}
	skins = nil, -- All available vehicle skins from API
	playerData = {} -- [playerUserId] = {player = {}, vehicles = {}, inventory = {}, skins = {}}
}

-- Vehicle storage functions
function ServerData.StorePlayerVehicles(playerUserId, vehicles)
	if not playerUserId or not vehicles then
		warn("[ServerData] StorePlayerVehicles: missing playerUserId or vehicles")
		return false
	end

	_cache.playerVehicles[playerUserId] = {
		vehicles = vehicles,
		lastUpdated = tick()
	}

	print("[ServerData] Stored", #vehicles, "vehicles for player", playerUserId)
	return true
end

function ServerData.GetPlayerVehicles(playerUserId)
	if not playerUserId then
		warn("[ServerData] GetPlayerVehicles: missing playerUserId")
		return nil
	end

	-- Check if we have cached vehicles
	local cached = _cache.playerVehicles[playerUserId]
	if cached then
		return cached.vehicles
	end

	-- Fetch from API if not in cache
	print("[ServerData] Fetching vehicles from API for player", playerUserId)
	local vehicles = ApiService.GetPlayerVehicles(playerUserId)
	if vehicles then
		-- Store in cache for future use
		ServerData.StorePlayerVehicles(playerUserId, vehicles)
		return vehicles
	else
		warn("[ServerData] Failed to fetch vehicles from API for player", playerUserId)
		return nil
	end
end

function ServerData.RemovePlayerVehicles(playerUserId)
	if not playerUserId then
		warn("[ServerData] RemovePlayerVehicles: missing playerUserId")
		return false
	end

	if _cache.playerVehicles[playerUserId] then
		_cache.playerVehicles[playerUserId] = nil
		print("[ServerData] Removed vehicles from storage for player", playerUserId)
		return true
	end

	return false
end

function ServerData.ClearAllPlayerVehicles()
	_cache.playerVehicles = {}
	print("[ServerData] Cleared all player vehicles from storage")
end

-- Get cached RaceQueue summary for a server, fetch from API if not present
function ServerData.GetRaceQueue(serverId)
	if not serverId then
		warn("[ServerData] GetRaceQueue missing serverId")
		return nil
	end
	if _cache.queues[serverId] then
		return _cache.queues[serverId]
	end
	local data = ApiService.GetRaceQueue(serverId)
	if data then
		-- Debug: Print raw API response
		print("[ServerData] Raw API response for server", serverId, ":")
		print("[ServerData] Data type:", type(data))
		if type(data) == "table" then
			print("[ServerData] Data keys:")
			for key, value in pairs(data) do
				if type(value) == "table" then
					print(string.format("[ServerData]   %s: table with %d items", key, #value))
					-- Print first few items to see structure
					for i = 1, math.min(3, #value) do
						local item = value[i]
						if type(item) == "table" then
							print(string.format("[ServerData]     Item %d: number=%s, track=%s, ready=%s, race_finished=%s", 
								i, tostring(item.number), tostring(item.track), tostring(item.ready), tostring(item.race_finished)))
						end
					end
				else
					print(string.format("[ServerData]   %s: %s", key, tostring(value)))
				end
			end
		else
			print("[ServerData] Data is not a table:", tostring(data))
		end

		_cache.queues[serverId] = data
	else
		warn("[ServerData] GetRaceQueue API returned nil for server ", serverId)
	end
	return _cache.queues[serverId]
end

-- Clear cached queue data (all servers or a specific server)
function ServerData.ClearRaceQueue(serverId)
	if serverId then
		_cache.queues[serverId] = nil
	else
		_cache.queues = {}
	end
end

-- Return the next race to run based on the lowest number among queued/in_progress
function ServerData.GetNextRace(serverId, trackName)
	local summary = ServerData.GetRaceQueue(serverId)
	if not summary then return nil end

	local targetTrackId = nil
	if trackName then
		local tr = ServerData.GetTrackByName(trackName)
		if tr and tr.id then targetTrackId = tostring(tr.id) end
	end

	local candidates = {}
	local function add(list)
		if list then
			for _, r in ipairs(list) do
				if not targetTrackId or tostring(r.track) == targetTrackId then
					table.insert(candidates, r)
				end
			end
		end
	end

	-- Prefer any in-progress first (still the lowest number sorting decides), then queued
	add(summary.in_progress)
	add(summary.queued)

	if #candidates == 0 then return nil end

	table.sort(candidates, function(a, b)
		local na = tonumber(a.number) or math.huge
		local nb = tonumber(b.number) or math.huge
		return na < nb
	end)

	return candidates[1]
end

-- Pending races (ready=false) from queued + in_progress
function ServerData.GetPendingRaces(serverId)
	local summary = ServerData.GetRaceQueue(serverId)
	if not summary then return {} end
	local pending = {}
	local function add(list)
		if list then
			for _, r in ipairs(list) do
				if r.ready == false then
					table.insert(pending, r)
				end
			end
		end
	end
	add(summary.in_progress)
	add(summary.queued)
	return pending
end

-- Get entire race queue for a specific track
function ServerData.GetRaceQueueForTrack(serverId, trackName)
	if not serverId then
		warn("[ServerData] GetRaceQueueForTrack missing serverId")
		return {}
	end
	if not trackName then
		warn("[ServerData] GetRaceQueueForTrack missing trackName")
		return {}
	end

	local summary = ServerData.GetRaceQueue(serverId)
	if not summary then return {} end

	-- Debug: Print what the API returned
	print("[ServerData] API summary returned:")
	print("[ServerData] queued count:", summary.queued and #summary.queued or 0)
	print("[ServerData] in_progress count:", summary.in_progress and #summary.in_progress or 0)
	print("[ServerData] completed_recent count:", summary.completed_recent and #summary.completed_recent or 0)

	-- Get track ID for filtering
	local track = ServerData.GetTrackByName(trackName)
	if not track or not track.id then
		warn("[ServerData] GetRaceQueueForTrack: Track not found:", trackName)
		return {}
	end

	local trackId = tostring(track.id)
	local trackRaces = {}

	-- Helper function to add races from a list
	local function addRacesFromList(list)
		if list then
			print("[ServerData] Processing list with", #list, "races for track", trackName, "(ID:", trackId, ")")
			for _, race in ipairs(list) do
				local raceTrackId = tostring(race.track)
				print("[ServerData] Race", race.number, "track ID:", raceTrackId, "matches:", raceTrackId == trackId)
				if raceTrackId == trackId then
					table.insert(trackRaces, race)
				end
			end
		end
	end

	-- Add races from queued, in_progress, and completed_recent lists
	addRacesFromList(summary.queued)
	addRacesFromList(summary.in_progress)
	addRacesFromList(summary.completed_recent)

	-- Sort by race number
	table.sort(trackRaces, function(a, b)
		local na = tonumber(a.number) or math.huge
		local nb = tonumber(b.number) or math.huge
		return na < nb
	end)

	return trackRaces
end

-- Tracks caching by name
local _tracksByName = nil

function ServerData.LoadTracks()
	local tracks = ApiService.GetTracks()
	if type(tracks) ~= "table" then
		warn("[ServerData] LoadTracks failed: no data")
		return nil
	end
	local byName = {}
	for _, t in ipairs(tracks) do
		if t.name then
			byName[t.name] = t
		end
	end
	_tracksByName = byName
	return _tracksByName
end

function ServerData.GetTrackByName(name)
	if not _tracksByName then
		ServerData.LoadTracks()
	end
	return _tracksByName and _tracksByName[name] or nil
end

function ServerData.GetAllTracks()
	if not _tracksByName then
		ServerData.LoadTracks()
	end
	if not _tracksByName then return nil end

	-- Convert back to array format
	local tracks = {}
	for _, track in pairs(_tracksByName) do
		table.insert(tracks, track)
	end
	return tracks
end

-- Get vehicle name by ID, with caching
function ServerData.GetVehicleName(vehicleId)
	if not vehicleId then return nil end

	-- Check cache first
	if _cache.vehicleNames[vehicleId] then
		return _cache.vehicleNames[vehicleId]
	end

	-- Try to get vehicle data from API
	local success, vehicle = pcall(function()
		return ApiService.GetVehicleById(vehicleId)
	end)

	if not success or not vehicle then
		return nil
	end

	-- Try to get player name
	local playerName = nil
	if vehicle.player_roblox_id then
		playerName = Utils.GetPlayerName(vehicle.player_roblox_id)
	end

	-- Cache the result (even if nil, to avoid repeated API calls)
	_cache.vehicleNames[vehicleId] = playerName
	return playerName
end

-- Notification storage functions
function ServerData.StorePlayerNotifications(playerUserId, notifications)
	if not playerUserId or not notifications then
		warn("[ServerData] StorePlayerNotifications: missing playerUserId or notifications")
		return false
	end

	_cache.playerNotifications[playerUserId] = {
		notifications = notifications,
		lastUpdated = tick()
	}

	print("[ServerData] Stored", #notifications, "notifications for player", playerUserId)
	return true
end

-- Helper function to compare two notification lists for changes
local function notificationsChanged(oldNotifications, newNotifications)
	if not oldNotifications or not newNotifications then
		return true -- If either is nil, consider it changed
	end

	if #oldNotifications ~= #newNotifications then
		return true -- Different number of notifications
	end

	-- Create a set of notification IDs from the old list for quick lookup
	local oldIds = {}
	for _, notification in ipairs(oldNotifications) do
		if notification.id then
			oldIds[notification.id] = true
		end
	end

	-- Check if all new notifications exist in the old list
	for _, notification in ipairs(newNotifications) do
		if not notification.id or not oldIds[notification.id] then
			return true -- New notification found
		end
	end

	return false -- No changes detected
end

-- Get player notifications with change detection
function ServerData.GetPlayerNotifications(playerUserId)
	if not playerUserId then
		warn("[ServerData] GetPlayerNotifications: missing playerUserId")
		return nil
	end

	-- Fetch fresh notifications from API
	print("[ServerData] Fetching notifications from API for player", playerUserId)
	local newNotifications = ApiService.GetPlayerNotifications(playerUserId)

	if not newNotifications then
		warn("[ServerData] Failed to fetch notifications from API for player", playerUserId)
		return nil
	end

	-- Get previously cached notifications
	local cached = _cache.playerNotifications[playerUserId]
	local oldNotifications = cached and cached.notifications or nil

	-- Check if notifications have changed
	local hasChanges = notificationsChanged(oldNotifications, newNotifications)

	-- Always update the cache with the new notifications
	ServerData.StorePlayerNotifications(playerUserId, newNotifications)

	-- Return the full list only if there were changes, otherwise return nil
	if hasChanges then
		ServerData.RemovePlayerVehicles(playerUserId)

		print("[ServerData] Notifications changed for player", playerUserId, "- returning", #newNotifications, "notifications")
		return newNotifications
	else
		print("[ServerData] No notification changes for player", playerUserId)
		return nil
	end
end

function ServerData.RemovePlayerNotifications(playerUserId)
	if not playerUserId then
		warn("[ServerData] RemovePlayerNotifications: missing playerUserId")
		return false
	end

	if _cache.playerNotifications[playerUserId] then
		_cache.playerNotifications[playerUserId] = nil
		print("[ServerData] Removed notifications from storage for player", playerUserId)
		return true
	end

	return false
end

function ServerData.ClearAllPlayerNotifications()
	_cache.playerNotifications = {}
	print("[ServerData] Cleared all player notifications from storage")
end

-- Vehicle Skins caching
function ServerData.GetAllSkins()
	-- Return cached skins if available
	if _cache.skins then
		return _cache.skins
	end

	-- Fetch from API
	print("[ServerData] Fetching all vehicle skins from API")
	local skins = ApiService.GetAllVehicleSkins()
	if skins then
		_cache.skins = skins
		print("[ServerData] Cached", #skins, "vehicle skins")
		return skins
	else
		warn("[ServerData] Failed to fetch vehicle skins from API")
		return nil
	end
end

function ServerData.GetSkinByName(name)
	local skins = ServerData.GetAllSkins()
	if not skins then return nil end

	for _, skin in ipairs(skins) do
		if skin.name == name then
			return skin
		end
	end
	return nil
end

function ServerData.ClearSkins()
	_cache.skins = nil
	print("[ServerData] Cleared vehicle skins from cache")
end

-- Player data storage functions (similar to PlayerCache)
function ServerData.SetPlayerData(userId, data)
	_cache.playerData[userId] = data
end

function ServerData.GetPlayerData(userId)
	local results = _cache.playerData[userId]
	if results == nil then
		_cache.playerData[userId] = {player = {}, vehicles = {}, inventory = {}, skins = {}}
		_cache.playerData[userId]["player"] = ApiService.GetPlayerData(userId)
		_cache.playerData[userId]["vehicles"] = ApiService.GetPlayerVehicles(userId)
		_cache.playerData[userId]["inventory"] = ApiService.GetFullInventory(userId)
		_cache.playerData[userId]["skins"] = ApiService.GetPlayerVehicleSkins(userId)
		print("[ServerData] Loaded player data for userId:", userId)
	end
	return _cache.playerData[userId]
end

function ServerData.ClearPlayerData(userId)
	_cache.playerData[userId] = nil
	print("[ServerData] Cleared player data for userId:", userId)
end

function ServerData.ClearAllPlayerData()
	_cache.playerData = {}
	print("[ServerData] Cleared all player data from storage")
end

return ServerData


