local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Data_DataCache"))
local GetCache = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetCache")


GetCache.OnServerInvoke = function(_, category, id)
	-- Return all skins if category is "Skins" (no id needed)
	if category == "Skins" then
		return DataCache.GetAllSkins()
	end

	return DataCache.GetObject(category, id) or {}
end