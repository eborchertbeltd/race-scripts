-- MobileUISwitch: Show mobile UI for tablet/mobile users, hide desktop UI
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GarageSoundUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GarageSoundUtils"))

-- Lock screen orientation to landscape on mobile
if UserInputService.TouchEnabled then
	local StarterGui = game:GetService("StarterGui")
	StarterGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
end

-- Events
local showBuildEV = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowBuildCar")
local showSetCarEV = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("ShowSetCar")

-- BindableEvents for opening UIs
local OpenInventoryEvent = ReplicatedStorage:WaitForChild("BindableEvents"):WaitForChild("OpenInventory")
local OpenPartsEvent = ReplicatedStorage:WaitForChild("BindableEvents"):WaitForChild("OpenParts")
local OpenCarEvent = ReplicatedStorage:WaitForChild("BindableEvents"):WaitForChild("OpenVehicle")
local OpenSkinEvent = ReplicatedStorage:WaitForChild("BindableEvents"):WaitForChild("OpenSkin")
local OpenSetCarEvent = ReplicatedStorage:WaitForChild("BindableEvents"):WaitForChild("OpenSetCar")

-- Music toggle
local ToggleMusic = ReplicatedStorage:WaitForChild("Player"):WaitForChild("ToggleMusic")

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
		local bottom = baseCanvas:FindFirstChild("Bottom")
		local teleport = baseCanvas:FindFirstChild("Teleport")

		if frame then frame.Visible = false end
		if bottom then bottom.Visible = false end
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

	local mobileBaseGui = playerGui:WaitForChild("MobileBaseGui")
	local mobileCanvas = mobileBaseGui:WaitForChild("Canvas")
	local mobileFrame = mobileCanvas:WaitForChild("Frame")
	local mobileMenu = mobileCanvas:WaitForChild("MobileMenu")

	-- Buttons
	local optionsButton = mobileFrame:WaitForChild("OptionsButton")
	local toolsButton = mobileFrame:WaitForChild("ToolsButton")
	local mobileTeleport = mobileCanvas:WaitForChild("Teleport")
	local showTeleportButton = mobileTeleport:WaitForChild("ShowTeleport")

	-- Menus
	local optionsMenu = mobileMenu:WaitForChild("Options")
	local toolsMenu = mobileMenu:WaitForChild("Tools")
	local fastTravelMenu = mobileMenu:WaitForChild("FastTravel")

	-- Teleport dialog (for Races button)
	local teleportDialog = playerGui:WaitForChild("Teleport"):WaitForChild("Dialog")

	-- Initialize: hide menus and tools button
	optionsMenu.Visible = false
	toolsMenu.Visible = false
	fastTravelMenu.Visible = false
	toolsButton.Visible = false

	-- Helper to close all menus (including teleport dialog)
	local function closeAllMenus()
		optionsMenu.Visible = false
		toolsMenu.Visible = false
		fastTravelMenu.Visible = false
		teleportDialog.Visible = false
	end

	-- Toggle Options menu (closes others if open)
	optionsButton.MouseButton1Click:Connect(function()
		GarageSoundUtils.PlayButtonPressed()
		if optionsMenu.Visible then
			optionsMenu.Visible = false
		else
			closeAllMenus()
			optionsMenu.Visible = true
		end
	end)

	-- Toggle Tools menu (closes others if open)
	toolsButton.MouseButton1Click:Connect(function()
		GarageSoundUtils.PlayButtonPressed()
		if toolsMenu.Visible then
			toolsMenu.Visible = false
		else
			closeAllMenus()
			toolsMenu.Visible = true
		end
	end)

	-- Toggle FastTravel menu (closes others if open)
	showTeleportButton.MouseButton1Click:Connect(function()
		GarageSoundUtils.PlayButtonPressed()
		if fastTravelMenu.Visible then
			fastTravelMenu.Visible = false
		else
			closeAllMenus()
			fastTravelMenu.Visible = true
		end
	end)

	-- Show/hide ToolsButton based on whether player is in garage
	showBuildEV.OnClientEvent:Connect(function(show, _)
		toolsButton.Visible = show == true
		-- Hide tools menu when leaving garage
		if not show then
			toolsMenu.Visible = false
		end
	end)

	-- Close buttons for menus
	local optionsCloseFrame = optionsMenu:FindFirstChild("Close", true)
	local toolsCloseFrame = toolsMenu:FindFirstChild("Close", true)
	local fastTravelCloseFrame = fastTravelMenu:FindFirstChild("Close", true)

	if optionsCloseFrame then
		local optionsCloseBtn = optionsCloseFrame:FindFirstChild("ImageButton")
		if optionsCloseBtn then
			optionsCloseBtn.MouseButton1Click:Connect(function()
				GarageSoundUtils.PlayButtonPressed()
				optionsMenu.Visible = false
			end)
		end
	end

	if toolsCloseFrame then
		local toolsCloseBtn = toolsCloseFrame:FindFirstChild("ImageButton")
		if toolsCloseBtn then
			toolsCloseBtn.MouseButton1Click:Connect(function()
				GarageSoundUtils.PlayButtonPressed()
				toolsMenu.Visible = false
			end)
		end
	end

	if fastTravelCloseFrame then
		local fastTravelCloseBtn = fastTravelCloseFrame:FindFirstChild("ImageButton")
		if fastTravelCloseBtn then
			fastTravelCloseBtn.MouseButton1Click:Connect(function()
				GarageSoundUtils.PlayButtonPressed()
				fastTravelMenu.Visible = false
			end)
		end
	end

	-- Options menu buttons
	local inventoryButton = optionsMenu:FindFirstChild("InventoryButton", true)
	local musicButton = optionsMenu:FindFirstChild("MusicButton", true)

	if inventoryButton then
		inventoryButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			optionsMenu.Visible = false
			OpenInventoryEvent:Fire()
		end)
	end

	if musicButton then
		local SoundService = game:GetService("SoundService")

		-- Image asset IDs for music button
		local MUSIC_OFF_IMAGE = "rbxassetid://121225646349750"
		local MUSIC_ON_IMAGE = "rbxassetid://106381655762539"
		local musicDebounceTime = 1
		local musicLastClickTime = 0

		-- Create background music if it doesn't exist (desktop script may not run on mobile)
		local backgroundMusic = SoundService:FindFirstChild("GarageBackgroundMusic")
		if not backgroundMusic then
			backgroundMusic = Instance.new("Sound")
			backgroundMusic.Name = "GarageBackgroundMusic"
			backgroundMusic.SoundId = "rbxassetid://91541881604773"
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

			GarageSoundUtils.PlayButtonPressed()

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

	-- Tools menu buttons
	local partsButton = toolsMenu:FindFirstChild("PartsButton", true)
	local setSkinButton = toolsMenu:FindFirstChild("SetSkin", true)
	local vehicleSetupButton = toolsMenu:FindFirstChild("VehicleSetup", true)

	if partsButton then
		partsButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			toolsMenu.Visible = false
			OpenPartsEvent:Fire()
		end)
	end

	if setSkinButton then
		setSkinButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			toolsMenu.Visible = false
			OpenSkinEvent:Fire()
		end)
	end

	if vehicleSetupButton then
		vehicleSetupButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			toolsMenu.Visible = false
			OpenCarEvent:Fire()
		end)
	end

	-- FastTravel menu buttons
	local myGarageButton = fastTravelMenu:FindFirstChild("MyGarage", true)
	local racesButton = fastTravelMenu:FindFirstChild("Races", true)
	local skinsButton = fastTravelMenu:FindFirstChild("Skins", true)
	local vendingButton = fastTravelMenu:FindFirstChild("Vending", true)

	-- Teleport destinations (same as desktop)
	local SKINS_CFRAME = CFrame.new(8.1, 3.5, -20) * CFrame.Angles(0, 0, 0)
	local VENDING_CFRAME = CFrame.new(-11.198, 1.8, -175.743) * CFrame.Angles(0, 0, 0)

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

	-- Get player's garage center (using SPad position + offset)
	local function getMyGarageCFrame()
		local garageName = player:GetAttribute("AssignedGarage")
		if not garageName then
			return nil
		end

		local garagesFolder = workspace:FindFirstChild("Garages")
		if not garagesFolder then
			return nil
		end

		local garage = garagesFolder:FindFirstChild(garageName)
		if not garage then
			return nil
		end

		local sPad = garage:FindFirstChild("SPad")
		if not sPad then
			return nil
		end

		local sPadPart = sPad:IsA("BasePart") and sPad or sPad:FindFirstChildWhichIsA("BasePart")
		if sPadPart then
			local pos = sPadPart.Position + Vector3.new(0, 3, 0)
			return CFrame.new(pos)
		end

		return nil
	end

	if myGarageButton then
		myGarageButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			fastTravelMenu.Visible = false
			local garageCFrame = getMyGarageCFrame()
			if garageCFrame then
				teleportTo(garageCFrame)
			end
		end)
	end

	if racesButton then
		racesButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			fastTravelMenu.Visible = false
			teleportDialog.Visible = true
		end)
	end

	if skinsButton then
		skinsButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			fastTravelMenu.Visible = false
			teleportTo(SKINS_CFRAME)
		end)
	end

	if vendingButton then
		vendingButton.MouseButton1Click:Connect(function()
			GarageSoundUtils.PlayButtonPressed()
			fastTravelMenu.Visible = false
			teleportTo(VENDING_CFRAME)
		end)
	end

	-- Mobile SetVehicleButton (in Bottom frame)
	local mobileBottom = mobileCanvas:FindFirstChild("Bottom")
	if mobileBottom then
		local mobileSetVehicleBtn = mobileBottom:FindFirstChild("SetVehicleButton")
		if mobileSetVehicleBtn then
			-- Initially hidden
			mobileSetVehicleBtn.Visible = false

			-- Listen for ShowSetCar event to show/hide and store padName
			showSetCarEV.OnClientEvent:Connect(function(show, padName)
				mobileSetVehicleBtn.Visible = show == true
				mobileSetVehicleBtn:SetAttribute("padTrigger", padName)
			end)

			-- Click handler to open SetCar UI
			mobileSetVehicleBtn.MouseButton1Click:Connect(function()
				GarageSoundUtils.PlayButtonPressed()
				local padName = mobileSetVehicleBtn:GetAttribute("padTrigger")
				OpenSetCarEvent:Fire(padName)
			end)
		end
	end
end
