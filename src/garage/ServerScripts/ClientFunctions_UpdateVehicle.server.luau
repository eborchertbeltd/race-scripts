local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ApiService = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("API_GameApiService"))
local updateCreateVehicle = ReplicatedStorage:WaitForChild("Player"):WaitForChild("UpdateCreateVehicle")
local PlayerCache = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Player_PlayerCache"))
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))

-- Cache the Garages folder
local garagesFolder = workspace:WaitForChild("Garages")

-- Helper function to get player's garage safely
local function getPlayerGarage(player)
	local playerGarageName = player:GetAttribute("AssignedGarage")
	if not playerGarageName then
		warn("[UpdateVehicle] Player has no AssignedGarage attribute:", player.Name)
		return nil
	end
	return garagesFolder:FindFirstChild(playerGarageName)
end

local updateVehicle = {}
updateCreateVehicle.OnServerInvoke = function(player, partsDict)
	if not updateVehicle[player.UserId] then
		updateVehicle[player.UserId] = true
		if partsDict.Id then
			-- Updating an existing vehicle
			local result = ApiService.UpdateVehicle(partsDict.Id, partsDict)
			PlayerCache.Clear(player.UserId)

			-- If vehicle is slotted, update its billboard
			if partsDict.slotted_number then
				local garage = getPlayerGarage(player)
				if garage then
					-- Get fresh vehicle data from cache
					local data = PlayerCache.Get(player.UserId)
					if data and data.vehicles then
						-- Find the updated vehicle in the cache
						for _, vehicle in ipairs(data.vehicles) do
							if vehicle.id == partsDict.Id then
								print("[UpdateVehicle] Updating billboard for slotted vehicle at pad", partsDict.slotted_number)
								Utils.updateCarSignBillboard(garage, partsDict.slotted_number, vehicle)
								break
							end
						end
					end
				else
					warn("[UpdateVehicle] Garage not found for player:", player.Name)
				end
			end

			updateVehicle[player.UserId] = nil
			return result
		else
			-- Creating a new vehicle
			local result = ApiService.CreateVehicle(player.UserId, partsDict)
			PlayerCache.Clear(player.UserId)
			updateVehicle[player.UserId] = nil
			return result
		end
	end
end