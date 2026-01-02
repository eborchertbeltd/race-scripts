-- GarageSoundUtils.lua
-- Client-side sound utilities for the Garage place
-- Keeps garage sounds separate from race place sounds

local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local GarageSoundUtils = {}

-- Create the button pressed sound once (shared across all buttons)
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

-- Create the forge sound
local forgeSound = Instance.new("Sound")
forgeSound.Name = "Forge"
forgeSound.SoundId = "rbxassetid://92407978921916"
forgeSound.Volume = 0.5
forgeSound.Parent = SoundService

-- Create the spray sound
local spraySound = Instance.new("Sound")
spraySound.Name = "Spray"
spraySound.SoundId = "rbxassetid://92494386680216"
spraySound.Volume = 0.5
spraySound.Parent = SoundService

-- Create the tightening sound
local tighteningSound = Instance.new("Sound")
tighteningSound.Name = "Tightening"
tighteningSound.SoundId = "rbxassetid://122387980841656"
tighteningSound.Volume = 0.5
tighteningSound.Parent = SoundService

-- Create the ratchet sound
local ratchetSound = Instance.new("Sound")
ratchetSound.Name = "Ratchet"
ratchetSound.SoundId = "rbxassetid://87424185165128"
ratchetSound.Volume = 0.5
ratchetSound.Parent = SoundService

-- Create the brake sound
local brakeSound = Instance.new("Sound")
brakeSound.Name = "Brake"
brakeSound.SoundId = "rbxassetid://113855279548092"
brakeSound.Volume = 0.5
brakeSound.Parent = SoundService

-- Create the rev sound
local revSound = Instance.new("Sound")
revSound.Name = "Rev"
revSound.SoundId = "rbxassetid://137866045440631"
revSound.Volume = 0.5
revSound.Parent = SoundService


-- Play the button pressed sound
function GarageSoundUtils.PlayButtonPressed()
	if buttonPressedSound then
		buttonPressedSound:Play()
	end
end

-- Play the register sound
function GarageSoundUtils.PlayRegister()
	if registerSound then
		registerSound:Play()
	end
end

-- Play the forge sound
function GarageSoundUtils.PlayForge()
	if forgeSound then
		forgeSound:Play()
	end
end

-- Play the spray sound
function GarageSoundUtils.PlaySpray()
	if spraySound then
		spraySound:Play()
	end
end

-- Play the tightening sound
function GarageSoundUtils.PlayTightening()
	if tighteningSound then
		tighteningSound:Play()
	end
end

-- Play the ratchet sound
function GarageSoundUtils.PlayRatchet()
	if ratchetSound then
		ratchetSound:Play()
	end
end

-- Play the brake sound
function GarageSoundUtils.PlayBrake()
	if brakeSound then
		brakeSound:Play()
	end
end

-- Play the rev sound
function GarageSoundUtils.PlayRev()
	if revSound then
		revSound:Play()
	end
end

return GarageSoundUtils
