local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local completedEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowComplete")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CompletedGui = playerGui:WaitForChild("CompletedGui")
local fetchQueueFunc = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("FetchTrackQueue")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ReplicaUtils"))
local template = Utils.findDescendantByName(CompletedGui, "Template")
local window = Utils.findDescendantByName(CompletedGui, "Window")
local scrollingFrame = Utils.findDescendantByName(CompletedGui, "ScrollingFrame")
template.Visible = false

local loading = false
local function showCompleted(track)
	if not loading then
		loading = true
		local trackQueue = fetchQueueFunc:InvokeServer(track)
		for _, each in trackQueue do
			if each.race_finished then
				local clone = template:Clone()
				local levelLower = string.lower(each.level)
				local level = each.level or "common"
				local levelDisplay = string.upper(string.sub(levelLower, 1, 1)) .. string.sub(levelLower, 2)

				-- Shorten levels for display to avoid spacings issues
				if levelLower == "legendary" then
					levelDisplay = "Leg"
				elseif levelLower == "common" then
					levelDisplay = "Com"
				end

				-- Set text with level before number
				
				local titleLabel = Utils.findDescendantByName(clone, "TitleLabel")
				titleLabel.Text = levelDisplay .. " #" .. (each.number or "?")
				if levelLower == "common" then
					titleLabel.TextColor3 = Color3.fromRGB(6, 123, 202)
				elseif levelLower == "rare" then
					titleLabel.TextColor3 = Color3.fromRGB(79, 213, 2)
				elseif levelLower == "epic" then
					titleLabel.TextColor3 = Color3.fromRGB(186, 50, 226)
				elseif levelLower == "legendary" then
					titleLabel.TextColor3 = Color3.fromRGB(255, 219, 49)
				else
					-- Default color for unknown levels
					titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
				
				-- Sort results by place (DNF goes to the end)
				local sortedResults = {}
				for _, result in ipairs(each.actual_results_json) do
					table.insert(sortedResults, result)
				end
				table.sort(sortedResults, function(a, b)
					local placeA = a.place or "999"
					local placeB = b.place or "999"
					-- DNF goes to the end
					if placeA == "DNF" and placeB ~= "DNF" then return false end
					if placeA ~= "DNF" and placeB == "DNF" then return true end
					if placeA == "DNF" and placeB == "DNF" then return false end
					-- Numeric places are sorted normally
					return tonumber(placeA) < tonumber(placeB)
				end)
				local positions = {"First", "Second", "Third", "Fourth"}
				for posIndex, posName in ipairs(positions) do
					if track ~= "Drag" or posName == "First" or posName == "Second" then 
						local posFrame = Utils.findDescendantByName(clone, posName .. "Label")
						local result = sortedResults[posIndex]
						if track == "Drag" then
							posFrame.Text = tostring(posIndex) .. " " .. result.name
						else
							posFrame.Text = result.place .. " " .. result.name
						end
					end
				end
				clone.Parent = scrollingFrame
				clone.Visible = true
			end
		end
		loading = false
	end
end


completedEvent.OnClientEvent:Connect(function(show, track)
	window.Visible = show == true
	if window.Visible then
		showCompleted(track)
	else
		for _, child in pairs(scrollingFrame:GetChildren()) do
			if child:IsA("Frame") and child.Visible then
				child:Destroy()
			end
		end
	end
end)