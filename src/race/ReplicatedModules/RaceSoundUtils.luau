-- RaceSoundUtils.lua
-- Engine sound utilities for the Race place
-- Handles all race car engine sounds with spatial audio and state management

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local RaceSoundUtils = {}

-- ============================================
-- UI Sound Effects
-- ============================================

-- Create the button pressed sound
local buttonPressedSound = Instance.new("Sound")
buttonPressedSound.Name = "ButtonPressed"
buttonPressedSound.SoundId = "rbxassetid://88816831870314"
buttonPressedSound.Volume = 0.5
buttonPressedSound.Parent = SoundService

-- Create the register sound
local registerSound = Instance.new("Sound")
registerSound.Name = "Register"
registerSound.SoundId = "rbxassetid://76498161542076"
registerSound.Volume = 0.5
registerSound.Parent = SoundService

-- Create the rev sound
local revSound = Instance.new("Sound")
revSound.Name = "Rev"
revSound.SoundId = "rbxassetid://137866045440631"
revSound.Volume = 0.5
revSound.Parent = SoundService


-- Play the button pressed sound
function RaceSoundUtils.PlayButtonPressed()
	if buttonPressedSound then
		buttonPressedSound:Play()
	end
end

-- Play the register sound
function RaceSoundUtils.PlayRegister()
	if registerSound then
		registerSound:Play()
	end
end

-- Play the rev sound
function RaceSoundUtils.PlayRev()
	if revSound then
		revSound:Play()
	end
end

-- ============================================
-- Engine Sound Utilities
-- ============================================

-- Engine sounds organized by type and engine number (1-4)
-- Each car gets assigned a random engine number and uses matching sounds
RaceSoundUtils.ENGINE_SOUNDS = {
	Rev = {
		[1] = "rbxassetid://138754748798049",
		[2] = "rbxassetid://133555141395947",
		[3] = "rbxassetid://77077155902852",
		[4] = "rbxassetid://79568467288413",
	},
	Idle = {
		[1] = "rbxassetid://99754880349953",
		[2] = "rbxassetid://107991104883446",
		[3] = "rbxassetid://87118623736662",
		[4] = "rbxassetid://72332366205349",
	},
	Accelerate = {
		[1] = "rbxassetid://132609130504421",
		[2] = "rbxassetid://83120239130232",
		[3] = "rbxassetid://118020802777477",
		[4] = "rbxassetid://118857249176824",
	},
	SlowDown = {
		[1] = "rbxassetid://75678905822201",
		[2] = "rbxassetid://81491143529166",
		[3] = "rbxassetid://84707263990830",
		[4] = "rbxassetid://79778887452222",
	},
	Racing = {
		[1] = "rbxassetid://140294258215934",
		[2] = "rbxassetid://130504324921683",
		[3] = "rbxassetid://70400623752207",
		[4] = "rbxassetid://76321341081604",
	},
}

-- Crossfade duration in seconds
local CROSSFADE_DURATION = 0.5

-- Engine sound volume (reduced by 20% from 0.5 to 0.4)
local ENGINE_SOUND_VOLUME = 0.1

-- Loop point: play 75% of sound before looping/transitioning (last 25% is empty)
local SOUND_LOOP_POINT = 0.75

-- Racing sound: play third quarter (start at 50%, loop back at 75%)
local RACING_START_POINT = 0.50
local RACING_END_POINT = 0.75

-- Get a random engine number (1-4)
function RaceSoundUtils.getRandomEngineNumber()
	return math.random(1, 4)
end

-- Get engine sound ID by type and engine number
function RaceSoundUtils.getEngineSoundId(soundType, engineNumber)
	local typeTable = RaceSoundUtils.ENGINE_SOUNDS[soundType]
	if not typeTable then
		warn("[RaceSoundUtils] Unknown engine sound type:", soundType)
		return nil
	end
	local soundId = typeTable[engineNumber]
	if not soundId then
		warn("[RaceSoundUtils] Unknown engine number:", engineNumber, "for type:", soundType)
		return nil
	end
	return soundId
end

-- Create a sound object with spatial audio settings
-- All sounds use Looped = false since we handle looping manually at 75%
local function createSpatialSound(parent, soundId, name)
	if not parent then
		warn("[RaceSoundUtils] createSpatialSound: parent is nil for", name)
		return nil
	end
	if not soundId then
		warn("[RaceSoundUtils] createSpatialSound: soundId is nil for", name)
		return nil
	end

	local success, sound = pcall(function()
		local s = Instance.new("Sound")
		s.Name = name
		s.SoundId = soundId
		s.Volume = 0 -- Start at 0, will fade in
		s.Looped = false -- We handle looping manually
		s.RollOffMode = Enum.RollOffMode.Linear
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = 75
		s.Parent = parent
		return s
	end)

	if not success then
		warn("[RaceSoundUtils] Failed to create sound:", name, "error:", sound)
		return nil
	end

	return sound
end

-- Set up all engine sounds for a car
-- Returns a table with sound objects and state info
function RaceSoundUtils.setupCarEngineSounds(car, engineNumber)
	if not car then
		warn("[RaceSoundUtils] Cannot setup engine sounds: car is nil")
		return nil
	end

	local root = car.PrimaryPart
	if not root then
		warn("[RaceSoundUtils] Cannot setup engine sounds: car has no PrimaryPart, car:", car.Name)
		return nil
	end

	engineNumber = engineNumber or RaceSoundUtils.getRandomEngineNumber()
	print("[RaceSoundUtils] Setting up engine sounds for car:", car.Name, "with engine number:", engineNumber)

	local sounds = {
		engineNumber = engineNumber,
		currentState = nil,
		sounds = {},
		connections = {},
		loopConnection = nil, -- For monitoring sound position
		-- Dual Racing sounds for seamless crossfade looping
		racingSounds = {},
		activeRacingIndex = 1,
	}

	-- Create all sound objects (none are set to loop - we handle it manually)
	local soundTypes = {"Rev", "Idle", "Accelerate", "SlowDown", "Racing"}
	local failedSounds = {}

	for _, soundType in ipairs(soundTypes) do
		local soundId = RaceSoundUtils.getEngineSoundId(soundType, engineNumber)
		local sound = createSpatialSound(root, soundId, "Engine" .. soundType)
		if sound then
			sounds.sounds[soundType] = sound
		else
			table.insert(failedSounds, soundType)
			warn("[RaceSoundUtils] Failed to create", soundType, "sound for car:", car.Name)
		end
	end

	-- Create two Racing sounds for seamless crossfade looping
	local racingId = RaceSoundUtils.getEngineSoundId("Racing", engineNumber)
	sounds.racingSounds[1] = createSpatialSound(root, racingId, "EngineRacing1")
	sounds.racingSounds[2] = createSpatialSound(root, racingId, "EngineRacing2")

	if not sounds.racingSounds[1] or not sounds.racingSounds[2] then
		warn("[RaceSoundUtils] Failed to create Racing crossfade sounds for car:", car.Name)
	end

	-- Check if we successfully created sounds
	if #failedSounds > 0 then
		warn("[RaceSoundUtils] Car", car.Name, "missing sounds:", table.concat(failedSounds, ", "))
	else
		print("[RaceSoundUtils] Successfully created all sounds for car:", car.Name)
	end

	return sounds
end

-- Crossfade from current sound to new sound
local function crossfadeTo(sounds, toState, onComplete)
	if not sounds or not sounds.sounds then return end

	-- For Racing, we use dual sounds - handled separately
	if toState == "Racing" then
		-- Fade out all other sounds
		for state, sound in pairs(sounds.sounds) do
			if sound.IsPlaying then
				local fadeOut = TweenService:Create(sound, TweenInfo.new(CROSSFADE_DURATION), {Volume = 0})
				fadeOut:Play()
				fadeOut.Completed:Connect(function()
					sound:Stop()
				end)
			end
		end
		-- Also fade out any playing racing sounds
		for _, racingSound in ipairs(sounds.racingSounds) do
			if racingSound.IsPlaying then
				local fadeOut = TweenService:Create(racingSound, TweenInfo.new(CROSSFADE_DURATION), {Volume = 0})
				fadeOut:Play()
				fadeOut.Completed:Connect(function()
					racingSound:Stop()
				end)
			end
		end

		-- Start the first racing sound
		sounds.activeRacingIndex = 1
		local racingSound = sounds.racingSounds[1]
		local timeLength = racingSound.TimeLength
		if timeLength > 0 then
			racingSound.TimePosition = timeLength * RACING_START_POINT
		else
			racingSound.TimePosition = 0
		end
		racingSound.Volume = 0
		racingSound:Play()
		local fadeIn = TweenService:Create(racingSound, TweenInfo.new(CROSSFADE_DURATION), {Volume = ENGINE_SOUND_VOLUME})
		fadeIn:Play()

		sounds.currentState = toState
		if onComplete then
			fadeIn.Completed:Connect(onComplete)
		end
		return
	end

	local toSound = sounds.sounds[toState]
	if not toSound then
		warn("[RaceSoundUtils] Unknown sound state:", toState)
		return
	end

	-- Fade out all currently playing sounds
	for state, sound in pairs(sounds.sounds) do
		if sound.IsPlaying and state ~= toState then
			local fadeOut = TweenService:Create(sound, TweenInfo.new(CROSSFADE_DURATION), {Volume = 0})
			fadeOut:Play()
			fadeOut.Completed:Connect(function()
				sound:Stop()
			end)
		end
	end
	-- Also fade out any playing racing sounds
	for _, racingSound in ipairs(sounds.racingSounds or {}) do
		if racingSound.IsPlaying then
			local fadeOut = TweenService:Create(racingSound, TweenInfo.new(CROSSFADE_DURATION), {Volume = 0})
			fadeOut:Play()
			fadeOut.Completed:Connect(function()
				racingSound:Stop()
			end)
		end
	end

	-- Start and fade in the new sound
	toSound.TimePosition = 0
	toSound.Volume = 0
	toSound:Play()
	local fadeIn = TweenService:Create(toSound, TweenInfo.new(CROSSFADE_DURATION), {Volume = ENGINE_SOUND_VOLUME})
	fadeIn:Play()

	sounds.currentState = toState

	-- If there's a completion callback
	if onComplete then
		fadeIn.Completed:Connect(onComplete)
	end
end

-- Start monitoring a sound to loop or transition at 75% of its length
-- Racing sound uses dual-sound crossfade for seamless looping
local function startSoundMonitor(sounds, soundState, shouldLoop, onReachLoopPoint)
	-- Stop any existing loop connection
	if sounds.loopConnection then
		sounds.loopConnection:Disconnect()
		sounds.loopConnection = nil
	end

	-- Racing uses dual-sound crossfade system
	local isRacing = (soundState == "Racing")

	if isRacing then
		-- Track if we've already triggered the crossfade
		local hasTriggered = false

		sounds.loopConnection = RunService.Heartbeat:Connect(function()
			-- Get the currently active racing sound
			local activeIndex = sounds.activeRacingIndex or 1
			local activeSound = sounds.racingSounds[activeIndex]

			if not activeSound or not activeSound.Parent or not activeSound.IsPlaying then
				return
			end

			local timeLength = activeSound.TimeLength
			if timeLength <= 0 then return end

			local loopTime = timeLength * RACING_END_POINT
			local startTime = timeLength * RACING_START_POINT

			if activeSound.TimePosition >= loopTime and not hasTriggered then
				hasTriggered = true

				-- Crossfade to the other racing sound
				local nextIndex = (activeIndex == 1) and 2 or 1
				local nextSound = sounds.racingSounds[nextIndex]

				-- Start the next sound at the start point
				nextSound.TimePosition = startTime
				nextSound.Volume = 0
				nextSound:Play()

				-- Crossfade: fade out active, fade in next
				local fadeOut = TweenService:Create(activeSound, TweenInfo.new(CROSSFADE_DURATION), {Volume = 0})
				local fadeIn = TweenService:Create(nextSound, TweenInfo.new(CROSSFADE_DURATION), {Volume = ENGINE_SOUND_VOLUME})
				fadeOut:Play()
				fadeIn:Play()

				fadeOut.Completed:Connect(function()
					activeSound:Stop()
				end)

				-- Update active index
				sounds.activeRacingIndex = nextIndex

				-- Reset trigger after crossfade completes
				task.delay(CROSSFADE_DURATION + 0.1, function()
					hasTriggered = false
				end)
			end
		end)
		return
	end

	-- Non-racing sounds use the original system
	local sound = sounds.sounds[soundState]
	if not sound then return end

	-- Track if we've already triggered the loop point action
	local hasTriggered = false

	sounds.loopConnection = RunService.Heartbeat:Connect(function()
		if not sound or not sound.Parent or not sound.IsPlaying then
			return
		end

		-- Wait for TimeLength to be loaded (it's 0 until sound loads)
		local timeLength = sound.TimeLength
		if timeLength <= 0 then return end

		local loopTime = timeLength * SOUND_LOOP_POINT

		if sound.TimePosition >= loopTime and not hasTriggered then
			hasTriggered = true

			if shouldLoop then
				-- Loop: restart from beginning
				sound.TimePosition = 0
				hasTriggered = false -- Reset so it can trigger again
			elseif onReachLoopPoint then
				-- Transition: call the callback
				onReachLoopPoint()
			end
		end

		-- Reset trigger flag when sound restarts (for looping)
		local midPoint = loopTime * 0.5
		if sound.TimePosition < midPoint then
			hasTriggered = false
		end
	end)
end

-- Transition engine sound to a new state
-- Handles the state machine: Rev -> Idle -> Accelerate -> Racing
-- All sounds play only 75% of their length before looping or transitioning
function RaceSoundUtils.transitionEngineSound(sounds, toState)
	if not sounds or not sounds.sounds then return end

	-- Clean up old connections
	for _, conn in pairs(sounds.connections) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	sounds.connections = {}

	-- Stop loop monitor
	if sounds.loopConnection then
		sounds.loopConnection:Disconnect()
		sounds.loopConnection = nil
	end

	if toState == "Rev" then
		-- Rev plays 75%, then transitions to Idle
		crossfadeTo(sounds, "Rev")
		startSoundMonitor(sounds, "Rev", false, function()
			crossfadeTo(sounds, "Idle")
			-- Start Idle loop monitor
			startSoundMonitor(sounds, "Idle", true, nil)
		end)

	elseif toState == "Idle" then
		-- Idle loops at 75%
		crossfadeTo(sounds, "Idle")
		startSoundMonitor(sounds, "Idle", true, nil)

	elseif toState == "Accelerate" then
		-- Accelerate plays 75%, then transitions to Racing
		crossfadeTo(sounds, "Accelerate")
		startSoundMonitor(sounds, "Accelerate", false, function()
			crossfadeTo(sounds, "Racing")
			-- Start Racing loop monitor
			startSoundMonitor(sounds, "Racing", true, nil)
		end)

	elseif toState == "Racing" then
		-- Racing loops at 75%
		crossfadeTo(sounds, "Racing")
		startSoundMonitor(sounds, "Racing", true, nil)

	elseif toState == "SlowDown" then
		-- SlowDown plays 75% (for future use - could loop or transition)
		crossfadeTo(sounds, "SlowDown")
		startSoundMonitor(sounds, "SlowDown", true, nil)

	else
		warn("[RaceSoundUtils] Unknown engine sound state:", toState)
	end
end

-- Thresholds for dynamic sound transitions
local MIN_STATE_DURATION = 0.8 -- Minimum time in a state before switching (prevents rapid flipping)

-- Update engine sound based on driving state (for races with turns)
-- Call this each frame with current speed data
-- Only manages transitions between Racing, SlowDown, and Accelerate states
function RaceSoundUtils.updateEngineSoundForDriving(sounds, currentSpeed, desiredSpeed, topSpeed)
	if not sounds then return end

	-- Get the current sound state
	local currentState = sounds.currentState

	-- Only manage driving states (Racing, SlowDown, Accelerate)
	-- Skip if still in Rev or Idle (pre-race phase)
	if currentState ~= "Racing" and currentState ~= "SlowDown" and currentState ~= "Accelerate" then
		return
	end

	-- Initialize tracking data if needed
	if not sounds.drivingState then
		sounds.drivingState = {
			lastChangeTime = os.clock(),
		}
	end

	local state = sounds.drivingState
	local now = os.clock()
	local timeSinceChange = now - state.lastChangeTime

	-- Don't allow state changes too frequently
	if timeSinceChange < MIN_STATE_DURATION then
		return
	end

	-- Determine what state we should be in based on speed
	local targetState = currentState

	if currentState == "Racing" then
		-- From Racing: switch to SlowDown if we're braking hard
		-- (current speed is higher than desired, meaning we need to slow down)
		if currentSpeed > desiredSpeed + 8 then
			targetState = "SlowDown"
		end

	elseif currentState == "SlowDown" then
		-- From SlowDown: switch to Accelerate when we've slowed enough and start speeding up
		if currentSpeed <= desiredSpeed + 3 then
			targetState = "Accelerate"
		end

	elseif currentState == "Accelerate" then
		-- From Accelerate: switch to Racing when near top speed
		-- (Accelerate may also auto-transition to Racing via the sound monitor)
		if currentSpeed >= topSpeed * 0.85 then
			targetState = "Racing"
		end
	end

	-- Apply state change if needed
	if targetState ~= currentState then
		state.lastChangeTime = now
		RaceSoundUtils.transitionEngineSound(sounds, targetState)
	end
end

-- Stop all engine sounds and clean up
function RaceSoundUtils.stopEngineSounds(sounds)
	if not sounds then return end

	-- Stop loop monitor
	if sounds.loopConnection then
		sounds.loopConnection:Disconnect()
		sounds.loopConnection = nil
	end

	-- Disconnect all connections
	for _, conn in pairs(sounds.connections or {}) do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
	sounds.connections = {}

	-- Stop and destroy all sounds
	for _, sound in pairs(sounds.sounds or {}) do
		if sound then
			sound:Stop()
			sound:Destroy()
		end
	end
	sounds.sounds = {}

	-- Stop and destroy dual racing sounds
	for _, sound in ipairs(sounds.racingSounds or {}) do
		if sound then
			sound:Stop()
			sound:Destroy()
		end
	end
	sounds.racingSounds = {}

	sounds.currentState = nil
end

return RaceSoundUtils
