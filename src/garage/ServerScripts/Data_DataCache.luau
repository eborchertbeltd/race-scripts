local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
-- DataCache Module
local DataCache = {}
local _cache = {
	Blueprints = {},
	Materials = {},
	Parts = {},
	Skins = {},
	playerNotifications = {}
}

-- ✅ Set all cached data
function DataCache.SetData(blueprints, materials, parts)
	_cache.Blueprints = blueprints or {}
	_cache.Materials = materials or {}
	_cache.Parts = parts or {}
end

-- ✅ Load and cache all vehicle skins
function DataCache.LoadSkins()
	local skins = ApiService.GetAllVehicleSkins()
	if type(skins) == "table" then
		_cache.Skins = skins
		print("[DataCache] Loaded", #skins, "vehicle skins")
	else
		warn("[DataCache] LoadSkins failed: API returned non-table")
		_cache.Skins = {}
	end
	return _cache.Skins
end

-- ✅ Get all cached skins
function DataCache.GetAllSkins()
	if not _cache.Skins or #_cache.Skins == 0 then
		return DataCache.LoadSkins()
	end
	return _cache.Skins
end

-- ✅ Get a skin by name
function DataCache.GetSkinByName(name)
	local skins = DataCache.GetAllSkins()
	for _, skin in ipairs(skins) do
		if skin.name == name then
			return skin
		end
	end
	return nil
end

-- ✅ Retrieve an object by category and id
function DataCache.GetObject(category, id)
	local list
	if category == "Blueprint" or category == "BlueprintTemplate" then
		list = _cache.Blueprints
	elseif category == "Material" or category == "MaterialTemplate" then
		list = _cache.Materials
	elseif category == "Part" or category == "PartTemplate" then
		list = _cache.Parts
	elseif category == "Skin" or category == "VehicleSkin" then
		list = DataCache.GetAllSkins()
	else
		warn("Unknown category:", category)
		return nil
	end

	for _, obj in ipairs(list) do
		if tostring(obj.id) == tostring(id) then
			return obj
		end
	end

	return nil -- not found
end


-- Notification storage functions
function DataCache.StorePlayerNotifications(playerUserId, notifications)
	if not playerUserId or not notifications then
		warn("[DataCache] StorePlayerNotifications: missing playerUserId or notifications")
		return false
	end

	_cache.playerNotifications[playerUserId] = {
		notifications = notifications,
		lastUpdated = tick()
	}

	print("[DataCache] Stored", #notifications, "notifications for player", playerUserId)
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
function DataCache.GetPlayerNotifications(playerUserId)
	if not playerUserId then
		warn("[DataCache] GetPlayerNotifications: missing playerUserId")
		return nil
	end

	-- Fetch fresh notifications from API
	print("[DataCache] Fetching notifications from API for player", playerUserId)
	local newNotifications = ApiService.GetPlayerNotifications(playerUserId)

	if not newNotifications then
		warn("[DataCache] Failed to fetch notifications from API for player", playerUserId)
		return nil
	end

	-- Get previously cached notifications
	local cached = _cache.playerNotifications[playerUserId]
	local oldNotifications = cached and cached.notifications or nil

	-- Check if notifications have changed
	local hasChanges = notificationsChanged(oldNotifications, newNotifications)

	-- Always update the cache with the new notifications
	DataCache.StorePlayerNotifications(playerUserId, newNotifications)

	-- Return the full list only if there were changes, otherwise return nil
	if hasChanges then
		print("[DataCache] Notifications changed for player", playerUserId, "- returning", #newNotifications, "notifications")
		return newNotifications
	else
		print("[DataCache] No notification changes for player", playerUserId)
		return nil
	end
end

function DataCache.RemovePlayerNotifications(playerUserId)
	if not playerUserId then
		warn("[DataCache] RemovePlayerNotifications: missing playerUserId")
		return false
	end

	if _cache.playerNotifications[playerUserId] then
		_cache.playerNotifications[playerUserId] = nil
		print("[DataCache] Removed notifications from storage for player", playerUserId)
		return true
	end

	return false
end


function DataCache.LoadGameData()
	local game_data = ApiService.LoadGameData()
	DataCache.SetData(game_data[1], game_data[2], game_data[3])
	return true
end


function DataCache.ClearAllPlayerNotifications()
	_cache.playerNotifications = {}
	print("[DataCache] Cleared all player notifications from storage")
end


return DataCache