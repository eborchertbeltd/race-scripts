-- StarterPlayerScripts/RaceSoundHandler.lua
-- Client-side script for preloading race sounds
-- Sounds are created server-side and attached to cars, but preloading on client improves performance
local ContentProvider = game:GetService("ContentProvider")

-- Engine sounds to preload (same IDs used in Utils.lua on server)
local ENGINE_SOUNDS = {
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

-- Preload all sounds on client startup so they play instantly when server creates them
task.spawn(function()
	local assetsToPreload = {}

	for soundType, numbers in pairs(ENGINE_SOUNDS) do
		for num, soundId in pairs(numbers) do
			table.insert(assetsToPreload, soundId)
		end
	end

	ContentProvider:PreloadAsync(assetsToPreload)
	print("[RaceSoundHandler] Preloaded", #assetsToPreload, "engine sounds")
end)

print("[RaceSoundHandler] Sound preloader initialized")
