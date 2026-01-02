-- LocalScript inside your ScreenGui
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RaceSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RaceSoundUtils"))
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local cam = workspace.CurrentCamera
local MainFrame = playerGui:WaitForChild("RaceGui"):WaitForChild("Frame")
local GUI = MainFrame:WaitForChild("GUI")
local TrackChangeEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):FindFirstChild("TrackChange")
local RaceStatsEvent = ReplicatedStorage:WaitForChild("RemoteEvents"):FindFirstChild("RaceStatsUpdate")
local GetNextRaceInfo = ReplicatedStorage:WaitForChild("RemoteFunctions"):FindFirstChild("GetNextRaceInfo")

-- Buttons (adjust names to your UI)
local btnNext = GUI:WaitForChild("CamNext")
local btnPrev = GUI:WaitForChild("CamPrev")
local btnPlayer = GUI:WaitForChild("Return")
local btnLeader = GUI:WaitForChild("Leader") -- LeaderCam button (optional)
local camButtonsFolder = GUI:FindFirstChild("CamButtons") -- optional

-- Stats frame elements
local StatsFrame = MainFrame:FindFirstChild("Stats")
local statsContent = StatsFrame and StatsFrame:FindFirstChild("Content")
local dataFrame = statsContent and statsContent:FindFirstChild("Data")
local positionsFrame = statsContent and statsContent:FindFirstChild("Positions")
local raceFrame = dataFrame and dataFrame:FindFirstChild("Race")
local lapsFrame = dataFrame and dataFrame:FindFirstChild("Laps")
local position1Frame = positionsFrame and positionsFrame:FindFirstChild("Position1")
local position2Frame = positionsFrame and positionsFrame:FindFirstChild("Position2")
local position3Frame = positionsFrame and positionsFrame:FindFirstChild("Position3")
local position4Frame = positionsFrame and positionsFrame:FindFirstChild("Position4")

-- Helper to find TextLabel in a frame (searches descendants)
local function findTextLabel(frame)
	if not frame then return nil end
	local label = frame:FindFirstChild("TextLabel")
	if label then return label end
	-- Search descendants
	for _, desc in ipairs(frame:GetDescendants()) do
		if desc:IsA("TextLabel") and desc.Name == "TextLabel" then
			return desc
		end
	end
	return nil
end

-- Get TextLabels for each stat frame
local raceLabel = findTextLabel(raceFrame)
local lapsLabel = findTextLabel(lapsFrame)
local position1Label = findTextLabel(position1Frame)
local position2Label = findTextLabel(position2Frame)
local position3Label = findTextLabel(position3Frame)
local position4Label = findTextLabel(position4Frame)

-- Helper to get display name from position data
local function getPositionName(posData)
	if type(posData) == "table" then
		return posData.name or "Unknown"
	elseif type(posData) == "string" then
		return posData
	end
	return ""
end

-- Helper to format position with number prefix: "#1 PlayerName" or "DNF PlayerName"
local function formatPosition(posNum, posData)
	local name = getPositionName(posData)
	if name == "" then
		return ""
	end

	-- Check if this position is a DNF
	if type(posData) == "table" and posData.place == "DNF" then
		return "DNF " .. name
	end

	return "#" .. tostring(posNum) .. " " .. name
end

-- Clear all stats labels
local function clearStatsLabels()
	if raceLabel then raceLabel.Text = "" end
	if lapsLabel then lapsLabel.Text = "" end
	if position1Label then position1Label.Text = "" end
	if position2Label then position2Label.Text = "" end
	if position3Label then position3Label.Text = "" end
	if position4Label then position4Label.Text = "" end
end

-- Track delayed transition to "Next Race" after finished
local finishedTransitionThread = nil

-- Forward declaration for variables used by functions defined before they're fully initialized
local fetchAndDisplayNextRace
local currentTrack = "Oval" -- Default track, will be updated on TrackChange

-- Show "Next Race" state (clears positions and fetches next race info)
local function showNextRaceState()
	if position1Label then position1Label.Text = "" end
	if position2Label then position2Label.Text = "" end
	if position3Label then position3Label.Text = "" end
	if position4Label then position4Label.Text = "" end
	-- Fetch next race info to get the level
	if fetchAndDisplayNextRace then
		fetchAndDisplayNextRace()
	else
		-- Fallback if function not yet defined
		if raceLabel then raceLabel.Text = "Next Race" end
		if lapsLabel then lapsLabel.Text = "" end
	end
end

-- Update stats display based on race data
local function updateStatsDisplay(data)
	if not data then
		clearStatsLabels()
		return
	end

	local status = data.status or "waiting"
	local raceLevel = data.raceLevel or "Common"
	local raceNumber = data.raceNumber
	local currentLap = data.currentLap
	local totalLaps = data.totalLaps
	local positions = data.positions or {}

	-- Cancel any pending transition to "Next Race" when we get a new update
	if finishedTransitionThread then
		task.cancel(finishedTransitionThread)
		finishedTransitionThread = nil
	end

	-- Update Race label
	if raceLabel then
		if status == "waiting" then
			raceLabel.Text = "Next Race"
		else
			-- Show level and number in format: "Common - #3432"
			local numStr = raceNumber and ("#" .. tostring(raceNumber)) or ""
			raceLabel.Text = raceLevel .. (numStr ~= "" and " - " .. numStr or "")
		end
	end

	-- Update Laps label
	if lapsLabel then
		if status == "waiting" then
			-- Show the race level in the laps frame when waiting
			lapsLabel.Text = raceLevel or ""
		elseif status == "starting" then
			-- Clear laps when a new race is starting
			lapsLabel.Text = ""
		elseif currentLap and totalLaps then
			lapsLabel.Text = tostring(currentLap) .. "/" .. tostring(totalLaps)
		end
	end

	-- Update Position labels
	if status == "waiting" then
		-- Clear positions when waiting for next race
		if position1Label then position1Label.Text = "" end
		if position2Label then position2Label.Text = "" end
		if position3Label then position3Label.Text = "" end
		if position4Label then position4Label.Text = "" end
	else
		-- Show positions with "#N" prefix during starting/in_progress/finished
		if position1Label then position1Label.Text = formatPosition(1, positions[1]) end
		if position2Label then position2Label.Text = formatPosition(2, positions[2]) end
		if position3Label then position3Label.Text = formatPosition(3, positions[3]) end
		if position4Label then position4Label.Text = formatPosition(4, positions[4]) end
	end

	-- If race finished, schedule transition to "Next Race" after 5 seconds
	if status == "finished" then
		finishedTransitionThread = task.delay(5, function()
			finishedTransitionThread = nil
			showNextRaceState()
		end)
	end
end

-- Fetch and display next race info for current track
fetchAndDisplayNextRace = function()
	if not GetNextRaceInfo or not currentTrack then
		return
	end

	local success, raceInfo = pcall(function()
		return GetNextRaceInfo:InvokeServer(currentTrack)
	end)

	if success and raceInfo then
		updateStatsDisplay({
			status = raceInfo.status or "waiting",
			raceLevel = raceInfo.raceLevel,
			raceNumber = raceInfo.raceNumber,
			currentLap = nil,
			totalLaps = raceInfo.totalLaps,
			positions = {}
		})
	else
		-- No race info available - still show "Next Race" waiting state
		if raceLabel then raceLabel.Text = "Next Race" end
		if lapsLabel then lapsLabel.Text = "" end
		if position1Label then position1Label.Text = "" end
		if position2Label then position2Label.Text = "" end
		if position3Label then position3Label.Text = "" end
		if position4Label then position4Label.Text = "" end
	end
end

-- Track folder mapping for LeaderCam placement (LeaderCam is in each track's camera folder)
local TRACKS = {
	["Oval"] = "OvalCameras",
	["Dirt"] = "DirtCameras", 
	["Road"] = "RoadCameras",
	["Drag"] = "DragCameras"
}

-- Camera folder mapping by track name (for regular track cameras)
local CAMERA_FOLDERS = {
	["Oval"] = "OvalCameras",
	["Dirt"] = "DirtCameras", 
	["Road"] = "RoadCameras",
	["Drag"] = "DragCameras"
}

-- Current track and camera state
-- currentTrack is already declared at the top of the file
local trackCams = {}
local views = { {kind = "player"} } -- Always start with player view

-- LeaderCam tracking
local leaderCamTrackingConnection = nil
local isLeaderCamMode = false

-- Function to load cameras for a specific track
local function loadCamerasForTrack(trackName: string)
	local folderName = CAMERA_FOLDERS[trackName]
	if not folderName then
		warn("Unknown track: " .. trackName)
		return false
	end

	local folder = workspace:FindFirstChild(folderName)
	if not folder then
		warn("Camera folder not found: " .. folderName)
		return false
	end

	-- Clear existing track cameras
	trackCams = {}

	-- Collect camera parts from the new folder
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") then
			table.insert(trackCams, p)
		end
	end
	table.sort(trackCams, function(a,b)
		local na = tonumber((a.Name:match("%d+$"))) or 0
		local nb = tonumber((b.Name:match("%d+$"))) or 0
		return na < nb
	end)

	currentTrack = trackName
	print("[UICam] Loaded " .. #trackCams .. " cameras for track: " .. trackName)
	return true
end

-- Function to rebuild the views array
local function rebuildViews()
	views = { {kind = "player"} } -- Always start with player view
	for _, part in ipairs(trackCams) do
		table.insert(views, {kind = "track", part = part})
	end
	print("[UICam] Rebuilt views - Total cameras: " .. #views .. " (1 player + " .. (#views - 1) .. " track cameras)")
	if #views == 1 then
		warn("[UICam] No camera parts found for track " .. currentTrack .. " (will only cycle player view).")
	end
end

-- Initialize with default track (but don't fail if no cameras found)
local function initializeTrackCameras()
	local success = loadCamerasForTrack(currentTrack)
	if not success then
		print("[UICam] Warning: Could not load cameras for track " .. currentTrack .. ", continuing with player view only")
	end
	rebuildViews()
end

-- Initialize views with just player view - track cameras will be added on TrackChange
views = { {kind = "player"} }
print("[UICam] Script starting with player view only - track cameras will load on TrackChange event")
print("[UICam] Initial views count: " .. #views)

-- Helpers
local function getHumanoid(char: Model?)
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid")
end

local function setPlayerView()
	local char = player.Character or player.CharacterAdded:Wait()
	local hum = getHumanoid(char)

	-- Use Custom camera type with humanoid subject for proper following
	cam.CameraType = Enum.CameraType.Custom
	cam.CameraSubject = nil -- Clear any existing subject first

	if hum then
		cam.CameraSubject = hum
		print("[UICam] Set camera subject to humanoid")
	else
		-- Fallback to head if no humanoid yet
		local head = char:FindFirstChild("Head")
		if head then 
			cam.CameraSubject = head
			print("[UICam] Set camera subject to head (fallback)")
		else
			print("[UICam] Warning: No humanoid or head found for camera subject")
		end
	end

	-- Don't set CFrame - let Roblox's camera system handle positioning with Custom + Humanoid
	print("[UICam] Player view set - using Custom camera with humanoid subject for following")
end

local function shotCFrame(camPart: BasePart): CFrame
	local lookAt = camPart:FindFirstChild("LookAt")
	if lookAt and lookAt:IsA("Attachment") then
		return CFrame.lookAt(camPart.Position, lookAt.WorldPosition)
	end
	return camPart.CFrame
end

local function moveToCamera(camPart: BasePart, timeSec: number)
	-- Take over the camera for a track shot
	cam.CameraType = Enum.CameraType.Scriptable
	local target = shotCFrame(camPart)
	local tween = TweenService:Create(
		cam,
		TweenInfo.new(timeSec, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ CFrame = target }
	)
	tween:Play()
end

-- Function to stop LeaderCam tracking
local function stopLeaderCamTracking()
	if leaderCamTrackingConnection then
		leaderCamTrackingConnection:Disconnect()
		leaderCamTrackingConnection = nil
		print("[UICam] Stopped LeaderCam tracking")
	end
end

-- Index helpers
local currentIndex = 1 -- start on player view by default
local function clampIndex(i: number)
	local n = #views
	return ((i - 1) % n) + 1
end

local function gotoIndex(i: number)
	if #views == 0 then
		print("[UICam] Warning: No views available to switch to")
		return
	end

	-- Stop LeaderCam tracking when switching to any other view
	stopLeaderCamTracking()
	isLeaderCamMode = false

	currentIndex = clampIndex(i)
	local v = views[currentIndex]
	print("[UICam] gotoIndex(" .. i .. ") -> currentIndex: " .. currentIndex .. ", kind: " .. v.kind .. " (Total views: " .. #views .. ")")
	if v.kind == "player" then
		setPlayerView()
	else
		moveToCamera(v.part, 0.4)
	end
end

-- Internal camera navigation functions (no sound)
local function nextCam() gotoIndex(currentIndex + 1) end
local function prevCam() gotoIndex(currentIndex - 1) end

-- Button wrappers that play sound
local function nextCamWithSound()
	RaceSoundUtils.PlayButtonPressed()
	nextCam()
end

local function prevCamWithSound()
	RaceSoundUtils.PlayButtonPressed()
	prevCam()
end

-- Function to return camera to player view
local function returnToPlayer()
	print("[UICam] Returning to player view")
	currentIndex = 1
	isLeaderCamMode = false
	stopLeaderCamTracking()
	-- Add error handling around setPlayerView call
	pcall(function()
		setPlayerView()
	end)
end

-- Wrapper for button click that plays sound
local function returnToPlayerWithSound()
	RaceSoundUtils.PlayButtonPressed()
	returnToPlayer()
end





-- Function to switch to LeaderCam view with continuous tracking
local function switchToLeaderCam()
	print("[UICam] Switching to LeaderCam view")

	-- Stop any existing tracking
	stopLeaderCamTracking()

	-- Look for LeaderCam in the current track's camera folder using TRACKS mapping
	local cameraFolderName = TRACKS[currentTrack]
	local leaderCam = nil

	if cameraFolderName then
		local cameraFolder = workspace:FindFirstChild(cameraFolderName)
		if cameraFolder then
			leaderCam = cameraFolder:FindFirstChild("LeaderCam")
		end
	end

	-- Fallback: also check root workspace
	if not leaderCam then
		leaderCam = workspace:FindFirstChild("LeaderCam")
	end

	if not leaderCam then
		print("[UICam] Warning: LeaderCam not found - returning to player view")
		returnToPlayer()
		return
	end

	-- Check if LeaderCam is still valid (hasn't been destroyed)
	if not leaderCam.Parent then
		print("[UICam] Warning: LeaderCam has been destroyed - returning to player view")
		returnToPlayer()
		return
	end

	-- Take over the camera for LeaderCam shot
	cam.CameraType = Enum.CameraType.Scriptable
	isLeaderCamMode = true

	-- Start continuous tracking of the LeaderCam
	leaderCamTrackingConnection = game:GetService("RunService").Heartbeat:Connect(function()
		if not leaderCam or not leaderCam.Parent then
			print("[UICam] LeaderCam destroyed during tracking - returning to player view")
			returnToPlayer()
			return
		end

		-- Update camera position to follow LeaderCam
		cam.CFrame = leaderCam.CFrame
	end)

	print("[UICam] Camera switched to LeaderCam with continuous tracking")
end

-- Wrapper for button click that plays sound
local function switchToLeaderCamWithSound()
	RaceSoundUtils.PlayButtonPressed()
	switchToLeaderCam()
end

-- Hook up UI
if btnNext then btnNext.MouseButton1Click:Connect(nextCamWithSound) end
if btnPrev then btnPrev.MouseButton1Click:Connect(prevCamWithSound) end
if btnPlayer then btnPlayer.MouseButton1Click:Connect(returnToPlayerWithSound) end
if btnLeader then btnLeader.MouseButton1Click:Connect(switchToLeaderCamWithSound) end

-- Optional: direct-select buttons (supports player slot too if you set CamIndex=1)
if camButtonsFolder then
	for _, b in ipairs(camButtonsFolder:GetChildren()) do
		if b:IsA("TextButton") or b:IsA("ImageButton") then
			local idx = b:GetAttribute("CamIndex") or tonumber((b.Name:match("%d+")))
			if idx then
				b.MouseButton1Click:Connect(function()
					RaceSoundUtils.PlayButtonPressed()
					gotoIndex(idx)
				end)
			end
		end
	end
end

-- Re-assert camera on spawn: if current is player view, restore Custom subject
local function onCharacterAdded()
	task.wait() -- let default camera init
	if views[currentIndex] and views[currentIndex].kind == "player" then
		pcall(function()
			setPlayerView()
		end)
	else
		-- Still on a track cam—keep control
		cam.CameraType = Enum.CameraType.Scriptable
		local v = views[currentIndex]
		if v and v.kind == "track" then
			cam.CFrame = shotCFrame(v.part)
		end
	end
end

-- Always start with player view when script loads
local function initializeCamera()
	-- Reset camera to player control first
	cam.CameraType = Enum.CameraType.Custom
	cam.CameraSubject = nil -- Clear any existing subject first

	if player.Character then
		local hum = getHumanoid(player.Character)
		if hum then
			cam.CameraSubject = hum
			print("[UICam] Camera initialized to player control - subject set to humanoid")
		else
			print("[UICam] Warning: No humanoid found for camera subject")
		end
	else
		print("[UICam] Warning: No character found for camera subject")
	end

	-- Use Custom + Humanoid for proper following behavior
	print("[UICam] Camera initialized - using Custom camera with humanoid subject")
end

-- Initialize camera immediately
print("[UICam] About to initialize camera...")
initializeCamera()
print("[UICam] Camera initialization completed")


-- Only connect to character events after initialization
if player.Character then onCharacterAdded() end
player.CharacterAdded:Connect(onCharacterAdded)
print("[UICam] Character event handlers connected")


TrackChangeEvent.OnClientEvent:Connect(function(entering: boolean, newTrackName: string)
	print("[UICam] TrackChange event received: entering=" .. tostring(entering) .. ", track=" .. newTrackName)
	if entering then
		MainFrame.Visible = true
		if StatsFrame then StatsFrame.Visible = true end
		-- Load cameras for the new track
		if loadCamerasForTrack(newTrackName) then
			rebuildViews()
			-- Reset to player view when entering a new track
			currentIndex = 1
			gotoIndex(1)
		end
		-- Fetch and display next race info for this track
		task.spawn(fetchAndDisplayNextRace)
	else
		MainFrame.Visible = false
		if StatsFrame then StatsFrame.Visible = false end
		clearStatsLabels()
		-- Return to player view when leaving a track
		returnToPlayer()
	end
end)
print("[UICam] TrackChange event handler connected")


-- Start on player view (index 1) - wait for character to be ready
print("[UICam] Setting up initial player view...")
task.spawn(function()
	-- Wait for character to be ready
	if not player.Character then
		player.CharacterAdded:Wait()
	end
	task.wait(1) -- Give a moment for character to fully load
	print("[UICam] Starting on player view")
	print("[UICam] Available views at startup: " .. #views)
	-- Just set player view directly without going through gotoIndex to avoid any camera switching
	pcall(function()
		setPlayerView()
	end)
end)

-- Cleanup function to reset camera when script is removed
local function cleanupCamera()
	-- Stop LeaderCam tracking if active
	stopLeaderCamTracking()

	cam.CameraType = Enum.CameraType.Custom
	cam.CameraSubject = nil -- Clear any existing subject first

	if player.Character then
		local hum = getHumanoid(player.Character)
		if hum then
			cam.CameraSubject = hum
		end
	end

	-- Use Custom + Humanoid for proper following behavior
	print("[UICam] Camera cleaned up - returned to player control with Custom + Humanoid")
end

-- Connect cleanup to script removal
script.AncestryChanged:Connect(function()
	if not script.Parent then
		cleanupCamera()
	end
end)

-- Also cleanup on player leaving
player.AncestryChanged:Connect(function()
	if not player.Parent then
		cleanupCamera()
	end
end)

-- Expose functions globally for other scripts to use
_G.CameraController = _G.CameraController or {}
_G.CameraController.returnToPlayer = returnToPlayer
_G.CameraController.nextCam = nextCam
_G.CameraController.prevCam = prevCam
_G.CameraController.gotoIndex = gotoIndex
_G.CameraController.switchToLeaderCam = switchToLeaderCam

-- Listen for race stats updates from the server
if RaceStatsEvent then
	RaceStatsEvent.OnClientEvent:Connect(function(trackName, data)
		-- Only update if this is for the current track we're viewing
		if trackName == currentTrack then
			updateStatsDisplay(data)
		end
	end)
end

print("[UICam] CameraGui script fully loaded and ready")