-- MobileUISwitch: Show mobile UI for tablet/mobile users, hide desktop UI
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RaceSoundUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RaceSoundUtils"))

-- Lock screen orientation to landscape on mobile
if UserInputService.TouchEnabled then
	local StarterGui = game:GetService("StarterGui")
	StarterGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
end

-- Remote functions
local RequestTrackChange = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("RequestTrackChange")
local ToggleMusic = ReplicatedStorage:WaitForChild("RemoteFunctions"):WaitForChild("ToggleMusic")

-- BindableEvent for opening Inventory (create if it doesn't exist)
local bindableEventsFolder = ReplicatedStorage:FindFirstChild("BindableEvents")
if not bindableEventsFolder then
	bindableEventsFolder = Instance.new("Folder")
	bindableEventsFolder.Name = "BindableEvents"
	bindableEventsFolder.Parent = ReplicatedStorage
end

local OpenInventoryEvent = bindableEventsFolder:FindFirstChild("OpenInventory")
if not OpenInventoryEvent then
	OpenInventoryEvent = Instance.new("BindableEvent")
	OpenInventoryEvent.Name = "OpenInventory"
	OpenInventoryEvent.Parent = bindableEventsFolder
end

-- Screen size threshold (width in pixels) to treat as mobile
local SMALL_SCREEN_THRESHOLD = 1024

-- Wait for camera to be ready
local camera = workspace:WaitForChild("Camera")
while not camera.ViewportSize or camera.ViewportSize.X == 0 do
	task.wait()
end

-- Check if device has touch as primary input (mobile/tablet)
local function isTouchDevice()
	local touchEnabled = UserInputService.TouchEnabled
	local keyboardEnabled = UserInputService.KeyboardEnabled
	-- Touch enabled is the primary indicator of mobile
	-- Only exclude if keyboard is present (desktop with touchscreen)
	return touchEnabled and not keyboardEnabled
end

-- Check if screen is small enough to be treated as mobile
local function isSmallScreen()
	local viewportSize = camera.ViewportSize
	return viewportSize.X <= SMALL_SCREEN_THRESHOLD
end

-- Determine if we should use mobile UI
local function shouldUseMobileUI()
	return isTouchDevice() or isSmallScreen()
end

-- Apply the appropriate UI visibility
local function applyUIMode()
	local baseGui = playerGui:WaitForChild("BaseGui")
	local baseCanvas = baseGui:WaitForChild("Canvas")
	local mobileBaseGui = playerGui:WaitForChild("MobileBaseGui")
	local mobileCanvas = mobileBaseGui:WaitForChild("Canvas")

	if shouldUseMobileUI() then
		-- Hide desktop UI elements
		local frame = baseCanvas:FindFirstChild("Frame")
		local teleport = baseCanvas:FindFirstChild("Teleport")

		if frame then frame.Visible = false end
		if teleport then teleport.Visible = false end

		-- Show mobile UI
		mobileCanvas.Visible = true
	else
		-- Desktop mode: ensure mobile UI is hidden
		mobileCanvas.Visible = false
	end
end

-- Run once at player load
applyUIMode()

-- Mobile menu button handling (only relevant if using mobile UI)
if shouldUseMobileUI() then
	-- Adjust BaseGui -> Frame height for mobile (100 instead of 130)
	local baseGuiForResize = playerGui:WaitForChild("BaseGui")
	local baseFrame = baseGuiForResize:WaitForChild("Frame")
	if baseFrame then
		baseFrame.Size = UDim2.new(baseFrame.Size.X.Scale, baseFrame.Size.X.Offset, baseFrame.Size.Y.Scale, 100)
	end

	-- Adjust RaceGui -> Frame -> Frame height for mobile (80 instead of 100)
	local raceGuiForResize = playerGui:WaitForChild("RaceGui")
	local raceMainFrame = raceGuiForResize:WaitForChild("Frame")
	local raceInnerFrame = raceMainFrame:FindFirstChild("Frame")
	if raceInnerFrame then
		raceInnerFrame.Size = UDim2.new(raceInnerFrame.Size.X.Scale, raceInnerFrame.Size.X.Offset, raceInnerFrame.Size.Y.Scale, 80)
	end

	local mobileBaseGui = playerGui:WaitForChild("MobileBaseGui")
	local mobileCanvas = mobileBaseGui:WaitForChild("Canvas")
	local mobileFrame = mobileCanvas:WaitForChild("Frame")
	local mobileMenu = mobileCanvas:WaitForChild("MobileMenu")
	local mobileTeleport = mobileCanvas:WaitForChild("Teleport")

	-- Buttons in Frame
	local cameraButton = mobileFrame:WaitForChild("CameraButton")
	local optionsButton = mobileFrame:WaitForChild("OptionsButton")

	-- ShowTeleport button
	local showTeleportButton = mobileTeleport:WaitForChild("ShowTeleport")

	-- Menus
	local optionsMenu = mobileMenu:WaitForChild("Options")
	local fastTravelMenu = mobileMenu:WaitForChild("FastTravel")

	-- Teleport dialog (for Garages button)
	local teleportDialog = playerGui:WaitForChild("Teleport"):WaitForChild("Dialog")

	-- RaceGui reference for camera button
	local raceGui = playerGui:FindFirstChild("RaceGui")
	local raceGuiMainFrame = raceGui and raceGui:FindFirstChild("Frame")

	-- Track if RaceGui is currently shown (for camera button)
	local isRaceGuiShown = false
	local currentTrackShown = nil
	local TRACKS = {"Oval", "Road", "Drag", "Dirt"}

	-- Initialize: hide menus
	optionsMenu.Visible = false
	fastTravelMenu.Visible = false

	-- Helper to close all menus (including teleport dialog)
	local function closeAllMenus()
		optionsMenu.Visible = false
		fastTravelMenu.Visible = false
		teleportDialog.Visible = false
	end

	-- Close RaceGui and return camera to player before teleporting
	local function closeRaceGuiIfOpen()
		if raceGuiMainFrame then
			raceGuiMainFrame.Visible = false
		end
		if _G.CameraController and _G.CameraController.returnToPlayer then
			_G.CameraController.returnToPlayer()
		end
		isRaceGuiShown = false
		currentTrackShown = nil
	end

	-- Get player's current position
	local function getPlayerPosition()
		local character = player.Character
		if not character then return nil end
		local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart then
			return humanoidRootPart.Position
		end
		local head = character:FindFirstChild("Head")
		if head then
			return head.Position
		end
		return nil
	end

	-- Find the billboard position for a track
	local function getBillboardPosition(trackName)
		local conventionFolder = workspace:FindFirstChild("Convention")
		if not conventionFolder then return nil end
		local trackFolder = conventionFolder:FindFirstChild(trackName)
		if not trackFolder then return nil end
		local billboard = trackFolder:FindFirstChild("Billboard")
		if billboard then
			if billboard:IsA("BasePart") then
				return billboard.Position
			elseif billboard:IsA("Model") then
				local primaryPart = billboard.PrimaryPart
				if primaryPart then
					return primaryPart.Position
				end
				for _, child in ipairs(billboard:GetDescendants()) do
					if child:IsA("BasePart") then
						return child.Position
					end
				end
			end
		end
		return nil
	end

	-- Find the closest track based on player distance to billboards
	local function findClosestTrack()
		local playerPos = getPlayerPosition()
		if not playerPos then
			return TRACKS[1]
		end
		local closestTrack = nil
		local closestDistance = math.huge
		for _, trackName in ipairs(TRACKS) do
			local billboardPos = getBillboardPosition(trackName)
			if billboardPos then
				local distance = (playerPos - billboardPos).Magnitude
				if distance < closestDistance then
					closestDistance = distance
					closestTrack = trackName
				end
			end
		end
		return closestTrack or TRACKS[1]
	end

	-- Teleport player to a CFrame
	local function teleportTo(cframe)
		local character = player.Character
		if character then
			local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
			if humanoidRootPart then
				humanoidRootPart.CFrame = cframe
			end
		end
	end

	-- Find the closest GuiTrigger in a folder
	local function findClosestGuiTrigger(folder)
		local playerPos = getPlayerPosition()
		if not playerPos then return nil end
		local closestTrigger = nil
		local closestDistance = math.huge
		for _, child in ipairs(folder:GetChildren()) do
			local guiTrigger = child:FindFirstChild("GuiTrigger")
			if guiTrigger and guiTrigger:IsA("BasePart") then
				local triggerPos = guiTrigger.Position
				local distance = (playerPos - triggerPos).Magnitude
				if distance < closestDistance then
					closestDistance = distance
					closestTrigger = guiTrigger
				end
			end
		end
		if closestTrigger then
			local triggerPos = closestTrigger.Position + Vector3.new(0, 3, 0)
			return CFrame.new(triggerPos)
		end
		return nil
	end

	-- CameraButton: Toggle RaceGui
	local cameraDebounceTime = 0.5
	local cameraLastClickTime = 0

	cameraButton.MouseButton1Click:Connect(function()
		local currentTime = tick()
		if currentTime - cameraLastClickTime < cameraDebounceTime then
			return
		end
		cameraLastClickTime = currentTime

		RaceSoundUtils.PlayButtonPressed()
		closeAllMenus()

		if isRaceGuiShown then
			local success = pcall(function()
				RequestTrackChange:InvokeServer(false, currentTrackShown or "Oval")
			end)
			isRaceGuiShown = false
			currentTrackShown = nil
		else
			local closestTrack = findClosestTrack()
			local success = pcall(function()
				RequestTrackChange:InvokeServer(true, closestTrack)
			end)
			if success then
				isRaceGuiShown = true
				currentTrackShown = closestTrack
			end
		end
	end)

	-- Toggle Options menu (closes others if open)
	optionsButton.MouseButton1Click:Connect(function()
		RaceSoundUtils.PlayButtonPressed()
		if optionsMenu.Visible then
			optionsMenu.Visible = false
		else
			closeAllMenus()
			optionsMenu.Visible = true
		end
	end)

	-- Toggle FastTravel menu (closes others if open)
	showTeleportButton.MouseButton1Click:Connect(function()
		RaceSoundUtils.PlayButtonPressed()
		if fastTravelMenu.Visible then
			fastTravelMenu.Visible = false
		else
			closeAllMenus()
			fastTravelMenu.Visible = true
		end
	end)

	-- Close buttons for menus
	local optionsCloseFrame = optionsMenu:FindFirstChild("Close", true)
	local fastTravelCloseFrame = fastTravelMenu:FindFirstChild("Close", true)

	if optionsCloseFrame then
		local optionsCloseBtn = optionsCloseFrame:FindFirstChild("ImageButton")
		if optionsCloseBtn then
			optionsCloseBtn.MouseButton1Click:Connect(function()
				RaceSoundUtils.PlayButtonPressed()
				optionsMenu.Visible = false
			end)
		end
	end

	if fastTravelCloseFrame then
		local fastTravelCloseBtn = fastTravelCloseFrame:FindFirstChild("ImageButton")
		if fastTravelCloseBtn then
			fastTravelCloseBtn.MouseButton1Click:Connect(function()
				RaceSoundUtils.PlayButtonPressed()
				fastTravelMenu.Visible = false
			end)
		end
	end

	-- Options menu buttons
	local inventoryButton = optionsMenu:FindFirstChild("InventoryButton", true)
	local musicButton = optionsMenu:FindFirstChild("MusicButton", true)

	if inventoryButton then
		inventoryButton.MouseButton1Click:Connect(function()
			RaceSoundUtils.PlayButtonPressed()
			optionsMenu.Visible = false
			OpenInventoryEvent:Fire()
		end)
	end

	if musicButton then
		-- Image asset IDs for music button
		local MUSIC_OFF_IMAGE = "rbxassetid://121225646349750"
		local MUSIC_ON_IMAGE = "rbxassetid://106381655762539"
		local musicDebounceTime = 1
		local musicLastClickTime = 0

		-- Create background music if it doesn't exist (desktop script may not run on mobile)
		local backgroundMusic = SoundService:FindFirstChild("RaceBackgroundMusic")
		if not backgroundMusic then
			backgroundMusic = Instance.new("Sound")
			backgroundMusic.Name = "RaceBackgroundMusic"
			backgroundMusic.SoundId = "rbxassetid://120806766960630"
			backgroundMusic.Volume = 0.1
			backgroundMusic.Looped = true
			backgroundMusic.Parent = SoundService
		end

		-- Update mobile music button image based on state
		local function updateMobileMusicButtonImage(musicEnabled)
			if musicEnabled then
				musicButton.Image = MUSIC_ON_IMAGE
			else
				musicButton.Image = MUSIC_OFF_IMAGE
			end
		end

		-- Update music playback state
		local function updateMusicPlayback(musicEnabled)
			if musicEnabled then
				if not backgroundMusic.IsPlaying then
					backgroundMusic:Play()
				end
			else
				if backgroundMusic.IsPlaying then
					backgroundMusic:Stop()
				end
			end
		end

		-- Initialize button image and music based on current Music attribute
		local initialMusic = player:GetAttribute("Music")
		if initialMusic ~= nil then
			updateMobileMusicButtonImage(initialMusic)
			updateMusicPlayback(initialMusic)
		else
			-- Default to on until we know the state
			updateMobileMusicButtonImage(true)
		end

		-- Listen for Music attribute changes to keep image and playback in sync
		player:GetAttributeChangedSignal("Music"):Connect(function()
			local musicEnabled = player:GetAttribute("Music")
			if musicEnabled ~= nil then
				updateMobileMusicButtonImage(musicEnabled)
				updateMusicPlayback(musicEnabled)
			end
		end)

		musicButton.MouseButton1Click:Connect(function()
			-- Check debounce
			local currentTime = tick()
			if currentTime - musicLastClickTime < musicDebounceTime then
				return
			end
			musicLastClickTime = currentTime

			RaceSoundUtils.PlayButtonPressed()

			-- Toggle music and update image/playback
			local success, newMusicValue = pcall(function()
				return ToggleMusic:InvokeServer()
			end)

			if success then
				updateMobileMusicButtonImage(newMusicValue)
				updateMusicPlayback(newMusicValue)
			end
		end)
	end

	-- FastTravel menu buttons
	local betButton = fastTravelMenu:FindFirstChild("Bet", true)
	local garagesButton = fastTravelMenu:FindFirstChild("Garages", true)
	local raceButton = fastTravelMenu:FindFirstChild("Race", true)

	if betButton then
		betButton.MouseButton1Click:Connect(function()
			RaceSoundUtils.PlayButtonPressed()
			fastTravelMenu.Visible = false

			-- Find closest Bet trigger
			local betFolder = workspace:FindFirstChild("Bet")
			if betFolder then
				local targetCFrame = findClosestGuiTrigger(betFolder)
				if targetCFrame then
					closeRaceGuiIfOpen()
					teleportTo(targetCFrame)
				end
			end
		end)
	end

	if garagesButton then
		garagesButton.MouseButton1Click:Connect(function()
			RaceSoundUtils.PlayButtonPressed()
			fastTravelMenu.Visible = false
			closeRaceGuiIfOpen()
			-- Show the teleport dialog for going back to Garage
			teleportDialog.Visible = true
		end)
	end

	if raceButton then
		raceButton.MouseButton1Click:Connect(function()
			RaceSoundUtils.PlayButtonPressed()
			fastTravelMenu.Visible = false

			-- Find closest JoinRace trigger
			local joinRaceFolder = workspace:FindFirstChild("JoinRace")
			if joinRaceFolder then
				local targetCFrame = findClosestGuiTrigger(joinRaceFolder)
				if targetCFrame then
					closeRaceGuiIfOpen()
					teleportTo(targetCFrame)
				end
			end
		end)
	end

	-- ============================================
	-- Mobile RaceGui Camera Controls
	-- ============================================

	-- Wait for RaceGui to exist
	local raceGuiForMobile = playerGui:WaitForChild("RaceGui")
	local raceGuiMainFrameForMobile = raceGuiForMobile:WaitForChild("Frame")

	-- Find GUI and MobileGUI at the same level inside Frame
	local desktopGUI = raceGuiMainFrameForMobile:FindFirstChild("GUI")
	local mobileGUI = raceGuiMainFrameForMobile:FindFirstChild("MobileGUI")

	if desktopGUI and mobileGUI then
		-- Hide desktop GUI and show mobile GUI
		desktopGUI.Visible = false
		mobileGUI.Visible = true

		-- Find Left/Right buttons and Cam label in MobileGUI
		local leftButton = mobileGUI:FindFirstChild("Left", true)
		local rightButton = mobileGUI:FindFirstChild("Right", true)
		local camLabel = mobileGUI:FindFirstChild("Cam", true)

		-- Function to update the camera label
		local function updateCamLabel()
			if camLabel and _G.CameraController and _G.CameraController.getCurrentCameraName then
				local cameraName = _G.CameraController.getCurrentCameraName()
				camLabel.Text = cameraName
			end
		end

		-- Connect Left button (previous camera)
		if leftButton then
			leftButton.MouseButton1Click:Connect(function()
				RaceSoundUtils.PlayButtonPressed()
				if _G.CameraController and _G.CameraController.prevCam then
					_G.CameraController.prevCam()
					-- Small delay to let camera state update
					task.wait(0.05)
					updateCamLabel()
				end
			end)
		end

		-- Connect Right button (next camera)
		if rightButton then
			rightButton.MouseButton1Click:Connect(function()
				RaceSoundUtils.PlayButtonPressed()
				if _G.CameraController and _G.CameraController.nextCam then
					_G.CameraController.nextCam()
					-- Small delay to let camera state update
					task.wait(0.05)
					updateCamLabel()
				end
			end)
		end

		-- Update label when RaceGui becomes visible (track change)
		raceGuiMainFrameForMobile:GetPropertyChangedSignal("Visible"):Connect(function()
			if raceGuiMainFrameForMobile.Visible then
				-- Delay to let camera system initialize for the track
				task.wait(0.1)
				updateCamLabel()
			end
		end)

		-- Initial update if already visible
		if raceGuiMainFrameForMobile.Visible then
			task.spawn(function()
				task.wait(0.1)
				updateCamLabel()
			end)
		end

		print("[MobileUISwitch] Mobile RaceGui camera controls initialized")
	else
		if not desktopGUI then
			print("[MobileUISwitch] Desktop GUI not found in RaceGui.Frame")
		end
		if not mobileGUI then
			print("[MobileUISwitch] MobileGUI not found in RaceGui.Frame")
		end
	end
end
