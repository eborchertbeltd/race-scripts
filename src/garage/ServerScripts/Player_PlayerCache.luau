-- ModuleScript: PlayerCache
local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
local cache = {}

local PlayerCache = {}

function PlayerCache.Set(userId, data)
	cache[userId] = data
end

function PlayerCache.Get(userId)
	local results = cache[userId]
	if results == nil then
		cache[userId] = {player = {}, vehicles = {}, inventory = {}, skins = {}}
		cache[userId]["player"] = ApiService.GetPlayerData(userId)
		cache[userId]["vehicles"] = ApiService.GetPlayerVehicles(userId)
		cache[userId]["inventory"] = ApiService.GetFullInventory(userId)
		cache[userId]["skins"] = ApiService.GetPlayerVehicleSkins(userId)
		print(cache[userId])
	end
	return cache[userId]
end

function PlayerCache.Clear(userId)
	cache[userId] = nil
end

function PlayerCache.ClearAll()
	cache = {}
end

return PlayerCache