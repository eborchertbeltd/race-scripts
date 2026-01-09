--#RACE
-- Server handler for CameraButton - receives requests from client and fires TrackChange event
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Get or create the RemoteFunction for camera button requests
local remoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")
local requestTrackChange = remoteFunctions:FindFirstChild("RequestTrackChange")
if not requestTrackChange then
	requestTrackChange = Instance.new("RemoteFunction")
	requestTrackChange.Name = "RequestTrackChange"
	requestTrackChange.Parent = remoteFunctions
end

-- Get the TrackChange event
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local trackChangeEvent = remoteEvents:FindFirstChild("TrackChange")
if not trackChangeEvent then
	trackChangeEvent = Instance.new("RemoteEvent")
	trackChangeEvent.Name = "TrackChange"
	trackChangeEvent.Parent = remoteEvents
end

-- Handle requests from clients
requestTrackChange.OnServerInvoke = function(player, entering, trackName)
	if type(entering) ~= "boolean" then
		warn("[CameraButtonHandler] Invalid entering parameter:", entering)
		return false
	end

	if type(trackName) ~= "string" then
		warn("[CameraButtonHandler] Invalid trackName parameter:", trackName)
		return false
	end

	-- Validate track name
	local validTracks = {Oval = true, Road = true, Drag = true, Dirt = true}
	if not validTracks[trackName] then
		warn("[CameraButtonHandler] Invalid track name:", trackName)
		return false
	end

	-- Fire TrackChange event to the requesting player
	trackChangeEvent:FireClient(player, entering, trackName)
	print("[CameraButtonHandler] Fired TrackChange to", player.Name, "entering:", entering, "track:", trackName)
	return true
end

print("[CameraButtonHandler] Server handler loaded")
