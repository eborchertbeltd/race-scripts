-- Billboard.lua
-- Updates billboard text based on race queue data

local ServerScriptService = game:GetService("ServerScriptService")
local ServerData = require(ServerScriptService:WaitForChild("GameScripts"):WaitForChild("ServerData"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Utils = require(game.ServerScriptService:WaitForChild("GameScripts"):WaitForChild("Utils"))
-- Wait 5 seconds before starting
task.wait(5)

-- Server ID for this server
local SERVER_ID = game.JobId ~= "" and game.JobId or "local-server"-- You may need to adjust this based on your server configuration

-- Store live race positions for each track (updated by race scripts)
local liveRacePositions = {}

-- Helper function to generate a consistent random color for a player name (module level)
local function getPlayerColorGlobal(name)
	local hash = 0
	for i = 1, #name do
		hash = hash + string.byte(name, i)
	end
	local r = ((hash * 37) % 156) + 100
	local g = ((hash * 73) % 156) + 100
	local b = ((hash * 127) % 156) + 100
	return Color3.fromRGB(r, g, b)
end


local function updateFromRaceQueue(trackName, raceQueue)
	--print("[Billboard] Updating race queue display for track:", trackName)

	-- Helper function to set title text with color based on race level
	local function setTitleWithColor(titleTextLabel, raceData)
		if not titleTextLabel or not raceData then return end

		local level = raceData.level or "common"
		local levelLower = string.lower(level)
		local levelDisplay = string.upper(string.sub(levelLower, 1, 1)) .. string.sub(levelLower, 2)

		-- Shorten levels for display to avoid spacing issues
		if levelLower == "legendary" then
			levelDisplay = "Leg"
		elseif levelLower == "common" then
			levelDisplay = "Com"
		end

		-- Set text with level before number
		titleTextLabel.Text = levelDisplay .. " #" .. (raceData.number or "?")

		-- Set color based on race level
		if levelLower == "common" then
			titleTextLabel.TextColor3 = Color3.fromRGB(6, 123, 202)
		elseif levelLower == "rare" then
			titleTextLabel.TextColor3 = Color3.fromRGB(79, 213, 2)
		elseif levelLower == "epic" then
			titleTextLabel.TextColor3 = Color3.fromRGB(186, 50, 226)
		elseif levelLower == "legendary" then
			titleTextLabel.TextColor3 = Color3.fromRGB(255, 219, 49)
		else
			-- Default color for unknown levels
			titleTextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
	end

	-- Helper function to parse NPC pool from a race
	local function parseNPCPool(raceData)
		local npcPool = {}
		if raceData and raceData.npc_pool then
			local parsed = raceData.npc_pool

			-- If it's already a table, use it directly
			if type(parsed) == "table" then
				-- Extract NPC names from the pool (e.g., "Fast Eddie" instead of "npc-1")
				for key, npcData in pairs(parsed) do
					local npcName = (type(npcData) == "table" and npcData.name) or key
					table.insert(npcPool, npcName)
				end
			elseif type(parsed) == "string" then
				-- If it's a string, try to decode it
				local success, decoded = pcall(function()
					return game:GetService("HttpService"):JSONDecode(parsed)
				end)
				if success and decoded then
					-- Extract NPC names from the decoded pool
					for key, npcData in pairs(decoded) do
						local npcName = (type(npcData) == "table" and npcData.name) or key
						table.insert(npcPool, npcName)
					end
				end
			end
		end
		return npcPool
	end

	-- Get the Convention folder and track subfolder
	local conventionFolder = workspace:FindFirstChild("Convention")
	if not conventionFolder then
		warn("[Billboard] Convention folder not found in workspace")
		return
	end

	local trackFolder = conventionFolder:FindFirstChild(trackName)
	if not trackFolder then
		warn("[Billboard] Track folder not found:", trackName)
		return
	end

	-- Find the Scores model
	local scoresModel = trackFolder:FindFirstChild("Scores")
	if not scoresModel then
		warn("[Billboard] Scores model not found for track:", trackName)
		return
	end

	-- Helper function to get a part by name pattern
	local function getPartByNamePattern(model, pattern)
		for _, child in ipairs(model:GetChildren()) do
			if child:IsA("BasePart") and child.Name:match(pattern) then
				return child
			end
		end
		return nil
	end

	-- Helper function to generate a consistent random color for a player name
	local function getPlayerColor(name)
		-- Use a simple hash of the name to generate a consistent color
		local hash = 0
		for i = 1, #name do
			hash = hash + string.byte(name, i)
		end

		-- Generate vibrant colors (avoid too dark or too light)
		local r = ((hash * 37) % 156) + 100  -- 100-255
		local g = ((hash * 73) % 156) + 100  -- 100-255
		local b = ((hash * 127) % 156) + 100 -- 100-255

		return Color3.fromRGB(r, g, b)
	end

	-- Helper function to get driver names for a race
	local function getDriverNames(raceData, npcPool)
		local names = {}
		local isNPC = {}  -- Track which names are NPCs
		local npcIndex = 1

		-- Helper function to get next NPC name
		local function getNextNPCName()
			if npcPool and npcIndex <= #npcPool then
				local name = npcPool[npcIndex]
				npcIndex = npcIndex + 1
				return name, true  -- Return name and NPC flag
			end
			return "TBD", true
		end

		-- Get names for each position
		for i = 1, 4 do
			local vehicleId = raceData["vehicle" .. i]
			if vehicleId then
				local playerName = ServerData.GetVehicleName(vehicleId)
				if playerName then
					names[i] = playerName
					isNPC[i] = false  -- It's a player
				else
					local npcName, npc = getNextNPCName()
					names[i] = npcName
					isNPC[i] = npc
				end
			else
				local npcName, npc = getNextNPCName()
				names[i] = npcName
				isNPC[i] = npc
			end
		end

		return names, isNPC
	end

	-- Helper function to clear a score part (set all text to empty)
	local function clearScorePart(part)
		if not part then return end

		local surfaceGui = part:FindFirstChild("SurfaceGui")
		if not surfaceGui then return end

		local frame = surfaceGui:FindFirstChild("Frame")
		if not frame then return end

		-- Get the title and position frames
		local titleFrame = frame:FindFirstChild("Title")
		local firstFrame = frame:FindFirstChild("First")
		local secondFrame = frame:FindFirstChild("Second")
		local thirdFrame = frame:FindFirstChild("Third")
		local fourthFrame = frame:FindFirstChild("Fourth")

		if not (titleFrame and firstFrame and secondFrame and thirdFrame and fourthFrame) then
			warn("[Billboard] Missing position frames in score part:", part.Name)
			return
		end

		-- Helper function to clear a position frame
		local function clearPositionFrame(posFrame)
			local textFrame = posFrame:FindFirstChild("Text")
			if not textFrame then return end

			local textLabel = textFrame:FindFirstChild("TextLabel")
			if not textLabel then return end

			textLabel.Text = ""
		end

		-- Clear title
		local titleTextFrame = titleFrame:FindFirstChild("Text")
		if titleTextFrame then
			local titleTextLabel = titleTextFrame:FindFirstChild("TextLabel")
			if titleTextLabel then
				titleTextLabel.Text = ""
			end
		end

		-- Clear position frames
		clearPositionFrame(firstFrame)
		clearPositionFrame(secondFrame)
		clearPositionFrame(thirdFrame)
		clearPositionFrame(fourthFrame)
	end

	-- Helper function to update a score part
	local function updateScorePart(part, raceData, npcPool, isDragRace)
		if not part then return end

		local surfaceGui = part:FindFirstChild("SurfaceGui")
		if not surfaceGui then return end

		local frame = surfaceGui:FindFirstChild("Frame")
		if not frame then return end

		-- Get the title and position frames
		local titleFrame = frame:FindFirstChild("Title")
		local firstFrame = frame:FindFirstChild("First")
		local secondFrame = frame:FindFirstChild("Second")
		local thirdFrame = frame:FindFirstChild("Third")
		local fourthFrame = frame:FindFirstChild("Fourth")

		if not (titleFrame and firstFrame and secondFrame and thirdFrame and fourthFrame) then
			warn("[Billboard] Missing position frames in score part:", part.Name)
			return
		end

		-- Helper function to update a position frame
		local function updatePositionFrame(posFrame, position, name, isNPCFlag)
			local textFrame = posFrame:FindFirstChild("Text")
			if not textFrame then return end

			local textLabel = textFrame:FindFirstChild("TextLabel")
			if not textLabel then return end

			textLabel.Text = position .. " " .. (name or "TBD")

			-- Set color based on whether it's an NPC or player
			if isNPCFlag then
				-- NPCs are blue
				textLabel.TextColor3 = Color3.fromRGB(100, 150, 255)
			else
				-- Players get random colors based on their name
				textLabel.TextColor3 = getPlayerColor(name or "TBD")
			end
		end

		-- Helper function to clear a position frame
		local function clearPositionFrame(posFrame)
			local textFrame = posFrame:FindFirstChild("Text")
			if not textFrame then return end

			local textLabel = textFrame:FindFirstChild("TextLabel")
			if not textLabel then return end

			textLabel.Text = ""
		end

		-- Update title with race number and color
		local titleTextFrame = titleFrame:FindFirstChild("Text")
		if titleTextFrame then
			local titleTextLabel = titleTextFrame:FindFirstChild("TextLabel")
			if titleTextLabel then
				setTitleWithColor(titleTextLabel, raceData)
			end
		end

		-- Get driver names and NPC flags
		local driverNames, driverIsNPC = getDriverNames(raceData, npcPool)

		-- Update position frames
		updatePositionFrame(firstFrame, "1", driverNames[1], driverIsNPC[1])
		updatePositionFrame(secondFrame, "2", driverNames[2], driverIsNPC[2])

		-- For drag races, clear 3rd and 4th positions in current and next sections
		if isDragRace then
			clearPositionFrame(thirdFrame)
			clearPositionFrame(fourthFrame)
		else
			updatePositionFrame(thirdFrame, "3", driverNames[3], driverIsNPC[3])
			updatePositionFrame(fourthFrame, "4", driverNames[4], driverIsNPC[4])
		end
	end

	-- Categorize races
	local nextRaces = {}
	local currentRace = nil
	local finishedRaces = {}

	for _, race in ipairs(raceQueue) do
		local ready = race.ready or false
		local raceFinished = race.race_finished or false

		if ready and raceFinished then
			-- Both true = finished
			table.insert(finishedRaces, race)
		elseif ready and not raceFinished then
			-- Ready true, race_finished false = in progress
			currentRace = race
		elseif not ready and not raceFinished then
			-- Both false = queued
			table.insert(nextRaces, race)
		end
		-- If ready is false and race_finished is true, that's an invalid state, so we ignore it
	end

	--print(string.format("[Billboard] Categorized races - Next: %d, Current: %s, Finished: %d", 
	--	#nextRaces, currentRace and currentRace.number or "none", #finishedRaces))

	-- Sort next races by number
	table.sort(nextRaces, function(a, b)
		return (tonumber(a.number) or 0) < (tonumber(b.number) or 0)
	end)

	-- Sort finished races by race number (most recent first)
	table.sort(finishedRaces, function(a, b)
		local numA = tonumber(a.number) or 0
		local numB = tonumber(b.number) or 0
		return numA > numB
	end)

	--print("[Billboard] Finished races order (most recent first):")
	--for i, race in ipairs(finishedRaces) do
	--	print(string.format("[Billboard]   %d: Race #%s", i, race.number or "?"))
	--end

	-- Update Next races (Next1-Next5)
	for i = 1, 5 do
		local nextPart = getPartByNamePattern(scoresModel, "^Next" .. i .. "$")
		if nextPart then
			if nextRaces[i] then
				local npcPool = parseNPCPool(nextRaces[i])
				updateScorePart(nextPart, nextRaces[i], npcPool, trackName == "Drag")
			else
				-- Clear the part if no race
				clearScorePart(nextPart)
			end
		end
	end

	-- Update Current race (Current1) - use live positions if available
	local currentPart = getPartByNamePattern(scoresModel, "^Current1$")
	if currentPart then
		if currentRace then
			-- Check for live positions from race script
			local livePositions = liveRacePositions[trackName]
			if livePositions and #livePositions > 0 then
				-- Use live sorted positions
				local surfaceGui = currentPart:FindFirstChild("SurfaceGui")
				if surfaceGui then
					local frame = surfaceGui:FindFirstChild("Frame")
					if frame then
						-- Update title
						local titleFrame = frame:FindFirstChild("Title")
						if titleFrame then
							local titleTextFrame = titleFrame:FindFirstChild("Text")
							if titleTextFrame then
								local titleTextLabel = titleTextFrame:FindFirstChild("TextLabel")
								if titleTextLabel then
									setTitleWithColor(titleTextLabel, currentRace)
								end
							end
						end

						-- Update positions with live data
						local positions = {"First", "Second", "Third", "Fourth"}
						local positionCount = (trackName == "Drag") and 2 or 4

						for i, posName in ipairs(positions) do
							local posFrame = frame:FindFirstChild(posName)
							if posFrame then
								local textFrame = posFrame:FindFirstChild("Text")
								if textFrame then
									local textLabel = textFrame:FindFirstChild("TextLabel")
									if textLabel then
										if i <= positionCount and livePositions[i] then
											local posData = livePositions[i]
											local name = "TBD"
											local isNPC = false

											if type(posData) == "table" then
												name = posData.name or "TBD"
												isNPC = (posData.competitor_type == "npc")
											elseif type(posData) == "string" then
												name = posData
												isNPC = string.sub(name, 1, 4) == "npc-"
											end

											textLabel.Text = tostring(i) .. " " .. name
											if isNPC then
												textLabel.TextColor3 = Color3.fromRGB(100, 150, 255)
											else
												textLabel.TextColor3 = getPlayerColorGlobal(name)
											end
										else
											textLabel.Text = ""
										end
									end
								end
							end
						end
					end
				end
			else
				-- Fall back to vehicle slot order
				local npcPool = parseNPCPool(currentRace)
				updateScorePart(currentPart, currentRace, npcPool, trackName == "Drag")
			end
		else
			-- Clear the part if no current race
			clearScorePart(currentPart)
		end
	end

	-- Update Finished races (Finished7-Finished1, most recent first)
	for i = 7, 1, -1 do
		local finishedPart = getPartByNamePattern(scoresModel, "^Finished" .. i .. "$")
		if finishedPart then
			local raceData = finishedRaces[i]
			if raceData then
				-- For finished races, use actual_results_json if available
				if raceData.actual_results_json and #raceData.actual_results_json >= 2 then
					--print(string.format("[Billboard] Race #%s has %d actual results:", 
					--raceData.number or "?", #raceData.actual_results_json))
					--for i, result in ipairs(raceData.actual_results_json) do
					--	if type(result) == "table" then
					--		print(string.format("[Billboard]   Position %d: %s (object format)", i, result.name or "unknown"))
					--	elseif type(result) == "string" then
					--		print(string.format("[Billboard]   Position %d: %s (string format)", i, result))
					--	else
					--		print(string.format("[Billboard]   Position %d: %s (unknown format)", i, tostring(result)))
					--	end
					--end
					-- Update with actual results
					local titleTextFrame = finishedPart:FindFirstChild("SurfaceGui"):FindFirstChild("Frame"):FindFirstChild("Title"):FindFirstChild("Text")
					if titleTextFrame then
						local titleTextLabel = titleTextFrame:FindFirstChild("TextLabel")
						if titleTextLabel then
							setTitleWithColor(titleTextLabel, raceData)
						end
					end

					-- Sort results by place (DNF goes to the end)
					local sortedResults = {}
					for _, result in ipairs(raceData.actual_results_json) do
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

					-- Update positions with sorted results
					local frame = finishedPart:FindFirstChild("SurfaceGui"):FindFirstChild("Frame")
					local positions = {"First", "Second", "Third", "Fourth"}
					for posIndex, posName in ipairs(positions) do
						local posFrame = frame:FindFirstChild(posName)
						if posFrame then
							local textFrame = posFrame:FindFirstChild("Text")
							if textFrame then
								local textLabel = textFrame:FindFirstChild("TextLabel")
								if textLabel then
									local resultData = sortedResults[posIndex]
									if resultData then
										local resultName = "TBD"
										local isNPCResult = false

										if type(resultData) == "table" and resultData.name then
											-- Object format: {name: "Fast Eddie", competitor_type: "npc", ...}
											resultName = resultData.name
											-- Check competitor_type to determine if NPC
											isNPCResult = (resultData.competitor_type == "npc")
										elseif type(resultData) == "string" then
											-- String format: "npc-1" (legacy format - assume NPC if starts with "npc-")
											resultName = resultData
											isNPCResult = string.sub(resultName, 1, 4) == "npc-"
										end

										-- Display format: "place name" or "DNF name"
										local placeText = resultData.place or tostring(posIndex)
										textLabel.Text = placeText .. " " .. resultName

										-- Set color based on whether it's an NPC or player
										if isNPCResult then
											-- NPCs are blue
											textLabel.TextColor3 = Color3.fromRGB(100, 150, 255)
										else
											-- Players get random colors based on their name
											textLabel.TextColor3 = getPlayerColor(resultName)
										end
									else
										-- Clear positions that don't have results
										textLabel.Text = ""
									end
								end
							end
						end
					end
				else
					-- Fallback to vehicle data
					local npcPool = parseNPCPool(raceData)
					updateScorePart(finishedPart, raceData, npcPool, trackName == "Drag")
				end
			else
				-- Clear the part if no finished race
				clearScorePart(finishedPart)
			end
		end
	end

	--print("[Billboard] Race queue update completed for track:", trackName)
end    
-- Function to update billboard for a specific track
local function updateBillboardForTrack(trackName)
	--print("[Billboard] Updating billboard for track:", trackName)

	-- Get the Convention folder and track subfolder
	local conventionFolder = workspace:FindFirstChild("Convention")
	if not conventionFolder then
		warn("[Billboard] Convention folder not found in workspace")
		return
	end

	local trackFolder = conventionFolder:FindFirstChild(trackName)
	if not trackFolder then
		warn("[Billboard] Track folder not found:", trackName)
		return
	end

	-- Find the Billboard part
	local billboardPart = trackFolder:FindFirstChild("Billboard")
	if not billboardPart then
		warn("[Billboard] Billboard part not found for track:", trackName)
		return
	end

	-- Navigate to the TextLabel
	local surfaceGui = billboardPart:FindFirstChild("SurfaceGui")
	if not surfaceGui then
		warn("[Billboard] SurfaceGui not found in Billboard part")
		return
	end

	local frame = surfaceGui:FindFirstChild("Frame")
	if not frame then
		warn("[Billboard] Frame not found in SurfaceGui")
		return
	end

	local textFrame = frame:FindFirstChild("Text")
	if not textFrame then
		warn("[Billboard] Text frame not found")
		return
	end

	local textLabel = textFrame:FindFirstChild("TextLabel")
	if not textLabel then
		warn("[Billboard] TextLabel not found")
		return
	end

	-- Get race queue data for this track
	local raceQueue = ServerData.GetRaceQueueForTrack(SERVER_ID, trackName)

	if not raceQueue or #raceQueue == 0 then
		--print("[Billboard] No race queue data for track:", trackName)
		-- Set default text when no races are queued
		return
	end

	-- Get the first race in the queue (most recent/upcoming)
	local nextRace = raceQueue[1]
	if not nextRace then
		warn("[Billboard] No race data found in queue for track:", trackName)
		return
	end

	-- Get the track data to access billboard_text
	local trackData = ServerData.GetTrackByName(trackName)

	if not trackData then
		warn("[Billboard] No track data found for:", trackName)
		return
	end

	-- Update the text label with the billboard_text from the track
	local billboardText = trackData.billboard_text

	-- Get or create scrolling text control
	local scrollingControl = Utils.startScrollingText(textLabel, 200, 100, { includeStrokeSibling = false })

	-- Update the text using the control
	if scrollingControl then
		scrollingControl:updateText(billboardText)
	else
		-- Fallback to direct text update if control creation failed
		textLabel.Text = billboardText
	end

	--print("[Billboard] Updated billboard for", trackName, "with text:", billboardText)
end

-- Main loop
local function runUpdateCycle()
	task.spawn(function()
		--print("[Billboard] Starting update cycle")

		-- Clear cache to force fresh API call
		ServerData.ClearRaceQueue(SERVER_ID)

		-- Define all tracks
		local tracks = {"Oval", "Road", "Dirt", "Drag"}

		-- Update each track
		for _, trackName in ipairs(tracks) do
			--print("[Billboard] Processing track:", trackName)

			-- Get race queue data for this track
			local raceQueue = ServerData.GetRaceQueueForTrack(SERVER_ID, trackName)

			-- Debug: Print track info
			local track = ServerData.GetTrackByName(trackName)
			--print("[Billboard] Track info for '" .. trackName .. "':", track and track.id or "not found")

			-- Debug: Print race count and check actual_results_json
			--print(string.format("[Billboard] Got %d races for %s track", #raceQueue, trackName))
			--for i, race in ipairs(raceQueue) do
			--	if race.actual_results_json then
			--		print(string.format("[Billboard] Race %s actual_results_json length: %d", 
			--			race.number or "?", #race.actual_results_json))
			--		print(string.format("[Billboard] Race %s actual_results_json: %s", 
			--			race.number or "?", tostring(race.actual_results_json)))
			--	end
			--end

			-- Update the race queue display for this track
			updateFromRaceQueue(trackName, raceQueue)
		end

		-- Update the billboard text
		--print("[Billboard] Update cycle completed, waiting 5 seconds before next cycle")
		task.wait(5)

		-- Recursively call the next cycle
		runUpdateCycle()
	end)
end
updateBillboardForTrack("Oval")
updateBillboardForTrack("Road")
updateBillboardForTrack("Dirt")
updateBillboardForTrack("Drag")
-- Start the update cycle
runUpdateCycle()

-- Export function for other scripts to trigger one-off billboard updates
local Billboard = {}

-- Function to trigger a one-off billboard update for a specific track
function Billboard.UpdateTrack(trackName)
	if not trackName or type(trackName) ~= "string" then
		warn("[Billboard] UpdateTrack: trackName must be a string")
		return false
	end

	-- Validate track name
	local validTracks = {"Oval", "Road", "Dirt", "Drag"}
	local isValidTrack = false
	for _, validTrack in ipairs(validTracks) do
		if trackName == validTrack then
			isValidTrack = true
			break
		end
	end

	if not isValidTrack then
		warn("[Billboard] UpdateTrack: Invalid track name '" .. trackName .. "'. Valid tracks: " .. table.concat(validTracks, ", "))
		return false
	end

	print("[Billboard] Triggering one-off update for track:", trackName)

	-- Clear cache to force fresh API call for this track
	ServerData.ClearRaceQueue(SERVER_ID)

	-- Get fresh race queue data for this track
	local raceQueue = ServerData.GetRaceQueueForTrack(SERVER_ID, trackName)

	-- Update the race queue display for this track
	updateFromRaceQueue(trackName, raceQueue)

	-- Update the billboard for this track
	updateBillboardForTrack(trackName)

	print("[Billboard] One-off update completed for track:", trackName)
	return true
end

-- Function to trigger one-off updates for all tracks
function Billboard.UpdateAllTracks()
	print("[Billboard] Triggering one-off update for all tracks")

	-- Clear cache to force fresh API call
	ServerData.ClearRaceQueue(SERVER_ID)

	-- Define all tracks
	local tracks = {"Oval", "Road", "Dirt", "Drag"}

	-- Update each track
	for _, trackName in ipairs(tracks) do
		-- Get race queue data for this track
		local raceQueue = ServerData.GetRaceQueueForTrack(SERVER_ID, trackName)

		-- Update the race queue display for this track
		updateFromRaceQueue(trackName, raceQueue)

		-- Update the billboard for this track
		updateBillboardForTrack(trackName)
	end

	print("[Billboard] One-off update completed for all tracks")
	return true
end

-- Function to update Current section with live race positions
-- Called by race scripts during the race to show current standings
function Billboard.UpdateCurrentPositions(trackName, positions)
	if not trackName or type(trackName) ~= "string" then
		return false
	end

	-- Validate track name
	local validTracks = {"Oval", "Road", "Dirt", "Drag"}
	local isValidTrack = false
	for _, validTrack in ipairs(validTracks) do
		if trackName == validTrack then
			isValidTrack = true
			break
		end
	end

	if not isValidTrack then
		return false
	end

	-- Store the live positions
	liveRacePositions[trackName] = positions

	-- Trigger an update of the race queue display (which will use live positions for Current1)
	local raceQueue = ServerData.GetRaceQueueForTrack(SERVER_ID, trackName)
	updateFromRaceQueue(trackName, raceQueue)

	return true
end

-- Function to clear live positions when race ends
function Billboard.ClearCurrentPositions(trackName)
	if trackName then
		liveRacePositions[trackName] = nil
	end
end

-- Export the Billboard module for other scripts to use
return Billboard



