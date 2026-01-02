local DataCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Data_DataCache"))

local success = DataCache.LoadGameData()
if not success then
	warn("⚠️ Using empty DataCache because API call failed.")
end