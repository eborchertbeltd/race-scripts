-- ApiService ModuleScript
local HttpService = game:GetService("HttpService")
local ApiService = {}

local API_KEY = "Q4IKL6tkmuvZUnImZZlz6hcX88WwXrgqdUkaEZLY3MM"
local BASE_URL = "https://thegamermatch.com/api/"


-- ✅ Global headers with Api-Key
local headers = {
	["Authorization"] = "Api-Key " .. API_KEY
}


-- ✅ Helper to perform GET request and decode JSON
local function fetchJson(endpoint)
	local success, response = pcall(function()
		return HttpService:GetAsync(BASE_URL .. endpoint, false, headers)
	end)

	if success then
		return HttpService:JSONDecode(response)
	else
		warn("❌ API GET failed for " .. endpoint .. ": " .. tostring(response))
		return nil
	end
end



-- ✅ Helper to perform POST request
local function postRequest(endpoint, data)
	local url = BASE_URL .. endpoint
	local headersWithContent = {
		["Content-Type"] = "application/json",
		["Authorization"] = "Api-Key " .. API_KEY
	}

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "POST",
			Headers = headersWithContent,
			Body = HttpService:JSONEncode(data)
		})
	end)

	if success and response.Success then
		print("[API] POST success:", endpoint)
		return HttpService:JSONDecode(response.Body)
	else
		warn("[API] POST failed:", endpoint, response and response.StatusCode)
		return nil
	end
end


-- ✅ Helper to perform GET request
local function getRequest(endpoint)
	local url = BASE_URL .. endpoint
	local headers = {
		["Authorization"] = "Api-Key " .. API_KEY
	}

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "GET",
			Headers = headers
		})
	end)

	if success and response.Success then
		print("[API] GET success:", endpoint)
		return HttpService:JSONDecode(response.Body)
	else
		warn("[API] GET failed:", endpoint, response and response.StatusCode)
		return nil
	end
end


local function patchRequest(endpoint, data)
	local url = BASE_URL .. endpoint
	local headersWithContent = {
		["Content-Type"] = "application/json",
		["Authorization"] = "Api-Key " .. API_KEY
	}

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "PATCH", -- ⬅ Change here
			Headers = headersWithContent,
			Body = HttpService:JSONEncode(data)
		})
	end)

	if success and response.Success then
		print("[API] PATCH success:", endpoint)
		return HttpService:JSONDecode(response.Body)
	else
		warn("[API] PATCH failed:", endpoint, response and response.StatusCode, response and response.Body)
		return nil
	end
end


-- ✅ Get Player data (matches: player/<roblox_id>/)
function ApiService.GetPlayerData(robloxUserId)
	return fetchJson(string.format("player/%d/", robloxUserId))
end


-- ✅ Retrieve Player Inventory (matches: player/<roblox_id>/inventory/)
function ApiService.GetPlayerInventory(robloxUserId)
	if not robloxUserId then
		warn("[ApiService] Missing robloxUserId")
		return nil
	end
	return fetchJson(string.format("player/%d/inventory/", robloxUserId))
end


-- ✅ Send object acquisition (matches: roblox-objects/)
function ApiService.PostObjectToServer(player, category, object_id, quantity)
	if not player or not player:GetAttribute("GameUserId") then
		warn("Cannot send object to API: missing GameUserId for", player.Name)
		return
	end

	local payload = {
		player = player:GetAttribute("GameUserId"), -- id set when player joined
		category = category .. "Template",                 -- "Blueprint", "Material", "Part"
		object_id = object_id,
		quantity = quantity
	}

	return postRequest("roblox-objects/", payload)
end


function ApiService.PostSponsorAccumulatedUpdate(player, money)
	if not player or not player:GetAttribute("GameUserId") then
		warn("Cannot send object to API: missing GameUserId for", player.Name)
		return
	end
	local payload = {
		sponsor_money_accumulated = math.floor(money * 100 + 0.5) / 100
	}
	local url = "player/" .. player.UserId .."/sponsor-money/"
	return postRequest(url, payload)
end


function ApiService.PostMoneyUpdate(player, money)
	if not player or not player:GetAttribute("GameUserId") then
		warn("Cannot send object to API: missing GameUserId for", player.Name)
		return
	end
	local payload = {
		money = math.floor(money * 100 + 0.5) / 100
	}
	local url = "player/" .. player.UserId .."/money/"
	return postRequest(url, payload)
end


function ApiService.UpdatePlayerMusic(robloxUserId, musicEnabled)
	if not robloxUserId then
		warn("[ApiService] UpdatePlayerMusic: missing robloxUserId")
		return nil
	end
	local payload = {
		music = musicEnabled
	}
	local url = "player/" .. robloxUserId .. "/music/"
	return postRequest(url, payload)
end


function ApiService.PatchVehicleSlotted(vehicleId, slottedValue, num)

	local payload = {
		slotted = slottedValue,
		slotted_number = num
	}
	print(payload)
	local url = "vehicles/" .. vehicleId .. "/"
	return patchRequest(url, payload)
end


function ApiService.PatchVehicleMoney(vehicleId, accumulatedMoney)

	local payload = {
		money_accumulated = math.floor(accumulatedMoney * 100 + 0.5) / 100
	}
	print(payload)
	local url = "vehicles/" .. vehicleId .. "/"
	return patchRequest(url, payload)
end


function ApiService.spinWheel(playerId, spinType)
	local payload = {
		type = spinType,
		player_id = playerId
	}
	return postRequest("random-spin/", payload)
end


function ApiService.craftItem(playerId, itemId)
	local payload = {
		roblox_object_id = itemId,
		user_id = playerId
	}
	return postRequest("construct-part/", payload)
end


-- ✅ Load all template data (matches: blueprint-templates/, material-templates/, part-templates/)
function ApiService.LoadGameData()
	local blueprints = fetchJson("blueprint-templates/") or {}
	local materials = fetchJson("material-templates/") or {}
	local parts = fetchJson("part-templates/") or {}
	print(string.format("✅ Loaded %d blueprints, %d materials, %d parts.", #blueprints, #materials, #parts))
	return {blueprints, materials, parts}
end


-- ✅ Choose first car for player
function ApiService.ChooseFirstCar(player, carName)
	if not player or not carName or not player:GetAttribute("GameUserId") then
		warn("Missing required data for choosing first car")
		return nil
	end

	local payload = {
		name = carName,
		roblox_id = player.UserId
	}
	print(payload)
	return postRequest("choose-first-car/", payload)
end


function ApiService.GetPlayerVehicles(robloxUserId)
	if not robloxUserId then
		warn("[ApiService] Missing robloxUserId")
		return nil
	end
	return fetchJson(string.format("vehicles/player/%d/", robloxUserId))
end


function ApiService.GetFullInventory(robloxUserId)
	if not robloxUserId then
		warn("[ApiService] Missing robloxUserId for full inventory fetch")
		return nil
	end

	return fetchJson(string.format("player/%d/inventory/", robloxUserId))
end


function ApiService.DeleteVehicle(vehicleId)
	if not vehicleId then
		warn("[ApiService] Missing vehicleId for delete")
		return nil
	end

	local url = BASE_URL .. "vehicles/" .. vehicleId .. "/"
	local headersWithContent = {
		["Content-Type"] = "application/json",
		["Authorization"] = "Api-Key " .. API_KEY
	}

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "DELETE",
			Headers = headersWithContent
		})
	end)

	if success and response.Success then
		if response.StatusCode == 200 then
			print("[API] DELETE success:", vehicleId)
			return HttpService:JSONDecode(response.Body)
		elseif response.StatusCode == 404 then
			warn("[API] Vehicle not found:", vehicleId)
			return nil
		else
			warn("[API] DELETE unexpected status:", response.StatusCode, response.Body)
			return nil
		end
	else
		warn("[API] DELETE failed:", vehicleId, response and response.StatusCode, response and response.Body)
		return nil
	end
end


function ApiService.CreateVehicle(playerId, partsDict)
	if not playerId or type(partsDict) ~= "table" then
		warn("[ApiService] CreateVehicle: missing playerId or parts table")
		return nil
	end

	local payload = {
		player_id    = playerId,
		name         = partsDict.Name,
		engine       = partsDict.Engine,
		exhaust      = partsDict.Exhaust,
		tire         = partsDict.Tire,
		transmission = partsDict.Transmission,
		body         = partsDict.Body,
	}

	return postRequest("vehicle/create/", payload)
end


function ApiService.UpdateVehicle(vehicleId, partsDict)
	if not vehicleId or type(partsDict) ~= "table" then
		warn("[ApiService] UpdateVehicle: missing vehicleId or parts table")
		return nil
	end

	-- Build partial payload from whatever keys are provided
	local payload = {}

	-- Optional name change
	if partsDict.Name ~= nil then payload.name = partsDict.Name end

	-- Map capitalized keys -> API fields
	if partsDict.Engine       ~= nil then payload.engine       = partsDict.Engine end
	if partsDict.Exhaust      ~= nil then payload.exhaust      = partsDict.Exhaust end
	if partsDict.Tire         ~= nil then payload.tire         = partsDict.Tire end
	if partsDict.Transmission ~= nil then payload.transmission = partsDict.Transmission end
	if partsDict.Body         ~= nil then payload.body         = partsDict.Body end

	if next(payload) == nil then
		warn("[ApiService] UpdateVehicle: nothing to update")
		return nil
	end

	local url = string.format("vehicle/%s/update/", tostring(vehicleId))
	return patchRequest(url, payload)
end


-- ✅ Get Player Notifications: get notifications for a player
function ApiService.GetPlayerNotifications(playerRobloxId, filters)
	if not playerRobloxId then
		warn("[ApiService] GetPlayerNotifications: missing playerRobloxId")
		return nil
	end

	-- Build query parameters
	local queryParams = {
		"player_roblox_id=" .. tostring(playerRobloxId)
	}

	-- Add optional filters
	if filters then
		if filters.category then
			table.insert(queryParams, "category=" .. tostring(filters.category))
		end
		if filters.read ~= nil then
			table.insert(queryParams, "read=" .. tostring(filters.read))
		end
		if filters.priority then
			table.insert(queryParams, "priority=" .. tostring(filters.priority))
		end
		if filters.limit then
			table.insert(queryParams, "limit=" .. tostring(filters.limit))
		end
	end

	local queryString = table.concat(queryParams, "&")
	local result = fetchJson("notifications/?" .. queryString)
	return result
end

-- ✅ Mark Notification as Read: mark a notification as read
function ApiService.MarkNotificationRead(notificationId)
	if not notificationId then
		warn("[ApiService] MarkNotificationRead: missing notificationId")
		return nil
	end

	return patchRequest(string.format("notifications/%s/mark-read/", tostring(notificationId)), {})
end

-- ✅ Mark Multiple Notifications as Read: mark multiple notifications as read
function ApiService.MarkMultipleNotificationsRead(notificationIds)
	if not notificationIds or type(notificationIds) ~= "table" or #notificationIds == 0 then
		warn("[ApiService] MarkMultipleNotificationsRead: missing or invalid notificationIds")
		return nil
	end

	local payload = {
		notification_ids = notificationIds
	}

	return postRequest("notifications/mark-multiple-read/", payload)
end

-- ✅ Delete Notification: delete a notification
function ApiService.DeleteNotification(notificationId)
	if not notificationId then
		warn("[ApiService] DeleteNotification: missing notificationId")
		return nil
	end

	local url = BASE_URL .. "notifications/" .. tostring(notificationId) .. "/delete/"
	local headersWithContent = {
		["Content-Type"] = "application/json",
		["Authorization"] = "Api-Key " .. API_KEY
	}

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = url,
			Method = "DELETE",
			Headers = headersWithContent
		})
	end)

	if success and response.Success then
		if response.StatusCode == 200 then
			print("[API] DELETE notification success:", notificationId)
			return HttpService:JSONDecode(response.Body)
		elseif response.StatusCode == 404 then
			warn("[API] Notification not found:", notificationId)
			return nil
		else
			warn("[API] DELETE notification unexpected status:", response.StatusCode, response.Body)
			return nil
		end
	else
		warn("[API] DELETE notification failed:", notificationId, response and response.StatusCode, response and response.Body)
		return nil
	end
end


-- ✅ RaceQueue: get queue summary for a server
function ApiService.GetRaceQueue(serverId)
	if not serverId then
		warn("[ApiService] Missing serverId for race queue fetch")
		return nil
	end
	return fetchJson(string.format("race-queue/%s/summary/", serverId))
end


-- ✅ RaceQueue: create queue entry (track_id, server_id, optional level)
function ApiService.CreateRaceQueue(trackId, serverId, level)
	if not trackId or not serverId then
		warn("[ApiService] Missing trackId/serverId for race queue create")
		return nil
	end
	local payload = {
		track_id = tostring(trackId),
		server_id = tostring(serverId),
		level = level or "Common",
	}
	return postRequest("race-queue/create/", payload)
end


-- ✅ Race: update fields on a race (vehicles, times, places, finished flag)
function ApiService.UpdateRace(raceId, fields)
	if not raceId or type(fields) ~= "table" then
		warn("[ApiService] UpdateRace: missing raceId or fields table")
		return nil
	end
	local url = string.format("race/%s/update/", tostring(raceId))
	return patchRequest(url, fields)
end


-- ✅ Track: get by name
function ApiService.GetTrackByName(trackName)
	if not trackName or trackName == "" then
		warn("[ApiService] GetTrackByName: missing trackName")
		return nil
	end
	local encoded = HttpService:UrlEncode(trackName)
	return fetchJson(string.format("track/%s/", encoded))
end


-- ✅ Track: list all tracks
function ApiService.GetTracks()
	return fetchJson("tracks/")
end


-- ✅ Vehicle: get by id
function ApiService.GetVehicleById(vehicleId)
	if not vehicleId then
		warn("[ApiService] GetVehicleById: missing id")
		return nil
	end
	return fetchJson(string.format("vehicle/%s/", tostring(vehicleId)))
end


-- ✅ Join Race: join a race with a vehicle
function ApiService.JoinRace(raceId, vehicleId)
	if not raceId or not vehicleId then
		warn("[ApiService] JoinRace: missing raceId or vehicleId")
		return nil
	end

	local payload = {
		race_id = tostring(raceId),
		vehicle_id = tostring(vehicleId)
	}

	return postRequest("race/join/", payload)
end


-- ✅ Create Bet: place a bet on a race
function ApiService.CreateBet(playerRobloxId, raceId, betOn, amount)
	if not playerRobloxId or not raceId or not betOn then
		warn("[ApiService] CreateBet: missing required parameters")
		return nil
	end

	local payload = {
		player_roblox_id = tostring(playerRobloxId),
		race_id = tostring(raceId),
		bet_on = tostring(betOn),
		amount = amount or 0
	}

	return postRequest("bets/create/", payload)
end


-- ✅ Get Player Bets: get all bets for a player
function ApiService.GetPlayerBets(playerRobloxId)
	if not playerRobloxId then
		warn("[ApiService] GetPlayerBets: missing playerRobloxId")
		return nil
	end

	return fetchJson(string.format("bets/?player_roblox_id=%s", tostring(playerRobloxId)))
end


-- ✅ Get Race Bets: get all bets for a specific race
function ApiService.GetRaceBets(raceId)
	if not raceId then
		warn("[ApiService] GetRaceBets: missing raceId")
		return nil
	end

	return fetchJson(string.format("race/%s/bets/", tostring(raceId)))
end


-- ✅ Get Bet: get a specific bet by ID
function ApiService.GetBet(betId, playerRobloxId)
	if not betId or not playerRobloxId then
		warn("[ApiService] GetBet: missing betId or playerRobloxId")
		return nil
	end

	return fetchJson(string.format("bets/%s/?player_roblox_id=%s", tostring(betId), tostring(playerRobloxId)))
end


-- ✅ Delete Bet: delete a bet by ID
function ApiService.DeleteBet(betId, playerRobloxId)
	if not betId or not playerRobloxId then
		warn("[ApiService] DeleteBet: missing betId or playerRobloxId")
		return nil
	end

	local payload = {
		player_roblox_id = tostring(playerRobloxId)
	}

	return postRequest(string.format("bets/%s/delete/", tostring(betId)), payload)
end


-- ✅ Update Vehicle Skin: change a vehicle's skin
function ApiService.UpdateVehicleSkin(vehicleId, skinName)
	if not vehicleId or not skinName then
		warn("[ApiService] UpdateVehicleSkin: missing vehicleId or skinName")
		return nil
	end

	local payload = {
		vehicle_id = tostring(vehicleId),
		skin = skinName
	}

	return postRequest("vehicle/update-skin/", payload)
end

-- ✅ Update Vehicle Color: change a vehicle's color
function ApiService.UpdateVehicleColor(vehicleId, color)
	if not vehicleId then
		warn("[ApiService] UpdateVehicleColor: missing vehicleId")
		return nil
	end

	local payload = {
		vehicle_id = tostring(vehicleId),
		color = color or ""
	}

	return postRequest("vehicle/update-color/", payload)
end

-- ✅ Get Player Vehicle Skins: fetch all skins owned by a player
function ApiService.GetPlayerVehicleSkins(robloxId)
	if not robloxId then
		warn("[ApiService] GetPlayerVehicleSkins: missing robloxId")
		return nil
	end

	return getRequest("player-vehicle-skins/?player_roblox_id=" .. tostring(robloxId))
end

-- ✅ Get All Vehicle Skins: fetch all available vehicle skins (catalog)
function ApiService.GetAllVehicleSkins()
	return getRequest("vehicle-skins/")
end

-- ✅ Grant Player Vehicle Skin: grant ownership of a skin after purchase
function ApiService.GrantPlayerVehicleSkin(robloxId, vehicleSkinId)
	if not robloxId or not vehicleSkinId then
		warn("[ApiService] GrantPlayerVehicleSkin: missing robloxId or vehicleSkinId")
		return nil
	end

	local payload = {
		player_roblox_id = tonumber(robloxId),
		vehicle_skin_id = tostring(vehicleSkinId)
	}

	return postRequest("player-vehicle-skins/create/", payload)
end

-- ✅ Update Player Play Time: increment total play time by given seconds
function ApiService.UpdatePlayerPlayTime(robloxUserId, playTimeSeconds)
	if not robloxUserId then
		warn("[ApiService] UpdatePlayerPlayTime: missing robloxUserId")
		return nil
	end

	local payload = {
		play_time_seconds = math.floor(playTimeSeconds)
	}

	local url = string.format("player/%d/play-time/", robloxUserId)
	return postRequest(url, payload)
end

return ApiService