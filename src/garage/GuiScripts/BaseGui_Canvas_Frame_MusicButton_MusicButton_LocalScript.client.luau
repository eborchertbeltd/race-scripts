local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local GarageSoundUtils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GarageSoundUtils"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local button = playerGui:WaitForChild("BaseGui"):WaitForChild("Canvas"):WaitForChild("Frame"):WaitForChild("MusicButton")
local ToggleMusic = ReplicatedStorage:WaitForChild("Player"):WaitForChild("ToggleMusic")

local debounceTime = 1 -- 1 second debounce
local lastClickTime = 0

-- Image asset IDs
local MUSIC_OFF_IMAGE = "rbxassetid://121225646349750"
local MUSIC_ON_IMAGE = "rbxassetid://106381655762539"

-- Create the background music (looping) - only created once on client
local backgroundMusic = Instance.new("Sound")
backgroundMusic.Name = "GarageBackgroundMusic"
backgroundMusic.SoundId = "rbxassetid://91541881604773"
backgroundMusic.Volume = 0.1
backgroundMusic.Looped = true
backgroundMusic.Parent = SoundService

-- Function to update button image based on music state
local function updateButtonImage(musicEnabled)
	if musicEnabled then
		button.Image = MUSIC_ON_IMAGE
	else
		button.Image = MUSIC_OFF_IMAGE
	end
end

-- Function to update music state based on preference
local function updateMusicState(musicEnabled)
	-- Default to true if nil
	if musicEnabled == nil then
		musicEnabled = true
	end

	-- Update button image
	updateButtonImage(musicEnabled)

	-- Update music playback
	if musicEnabled then
		if not backgroundMusic.IsPlaying then
			backgroundMusic:Play()
			print("[MusicButton] Started background music (player preference: enabled)")
		end
	else
		if backgroundMusic.IsPlaying then
			backgroundMusic:Stop()
			print("[MusicButton] Stopped background music (player preference: disabled)")
		end
	end
end

-- Listen for Music attribute changes and update immediately
if player then
	-- Initial setup - don't start music until we know the preference
	local initialMusic = player:GetAttribute("Music")
	if initialMusic ~= nil then
		-- Attribute already set, use it immediately
		updateMusicState(initialMusic)
	else
		-- Wait for attribute to be set, but don't timeout and default to true
		-- Instead, listen for the attribute change
		local connection
		connection = player:GetAttributeChangedSignal("Music"):Connect(function()
			local musicEnabled = player:GetAttribute("Music")
			if musicEnabled ~= nil then
				updateMusicState(musicEnabled)
				connection:Disconnect() -- Only need this once for initial setup
			end
		end)

		-- Also check periodically in case we missed the signal
		task.spawn(function()
			local startTime = tick()
			local timeout = 10 -- 10 second timeout
			while player:GetAttribute("Music") == nil and (tick() - startTime) < timeout do
				task.wait(0.5)
			end

			local musicEnabled = player:GetAttribute("Music")
			if musicEnabled ~= nil then
				updateMusicState(musicEnabled)
				if connection then
					connection:Disconnect()
				end
			else
				-- Timeout expired, default to true
				warn("[MusicButton] Music attribute not set after 10 seconds, defaulting to enabled")
				updateMusicState(true)
				if connection then
					connection:Disconnect()
				end
			end
		end)
	end
end

button.MouseButton1Click:Connect(function()
	-- Check debounce
	local currentTime = tick()
	if currentTime - lastClickTime < debounceTime then
		return
	end
	lastClickTime = currentTime

	-- Play button sound
	GarageSoundUtils.PlayButtonPressed()

	-- Toggle music in backend and get updated value
	local success, newMusicValue = pcall(function()
		return ToggleMusic:InvokeServer()
	end)

	if success then
		print("[MusicButton] Music toggled to:", newMusicValue)
		-- Update button image based on new state
		updateButtonImage(newMusicValue)

		-- Toggle the background music playback based on new value
		if newMusicValue then
			backgroundMusic:Play()
		else
			backgroundMusic:Stop()
		end
	else
		warn("[MusicButton] Failed to toggle music:", newMusicValue)
	end
end)

