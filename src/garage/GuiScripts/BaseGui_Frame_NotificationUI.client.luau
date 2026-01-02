local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local NotificationGui = playerGui:WaitForChild("BaseGui"):WaitForChild("Frame")
local fetchQueueFunc = ReplicatedStorage:WaitForChild("Player"):WaitForChild("GetNotifications")
local fetchPlayerFunc = ReplicatedStorage:WaitForChild("Player"):WaitForChild("FetchPlayer")
local Utils = require(game.ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utils"))
local template = Utils.findDescendantByName(NotificationGui, "Template")
local scrollingFrame = Utils.findDescendantByName(NotificationGui, "ScrollingFrame")


-- Function to calculate relative time from ISO date string
local function getRelativeTime(isoDateString)
	if not isoDateString then return "Unknown" end

	local success, dateTime = pcall(function()
		return DateTime.fromIsoDate(isoDateString)
	end)

	if not success then
		warn("[NotificationScript] Failed to parse date:", isoDateString)
		return "Unknown"
	end

	local now = DateTime.now()
	local diffSeconds = now.UnixTimestamp - dateTime.UnixTimestamp

	if diffSeconds < 60 then
		return "Just now"
	elseif diffSeconds < 3600 then -- Less than 1 hour
		local minutes = math.floor(diffSeconds / 60)
		return minutes .. "m ago"
	elseif diffSeconds < 86400 then -- Less than 1 day
		local hours = math.floor(diffSeconds / 3600)
		return hours .. "h ago"
	elseif diffSeconds < 604800 then -- Less than 1 week
		local days = math.floor(diffSeconds / 86400)
		return days .. "d ago"
	else
		local weeks = math.floor(diffSeconds / 604800)
		return weeks .. "w ago"
	end
end


-- Function to clear all existing notifications from the scrolling frame
local function clearNotifications()
	for _, child in pairs(scrollingFrame:GetChildren()) do
		if child.Name == "Notification" then
			child:Destroy()
		end
	end
end


-- Function to parse betting notification and replace roblox_id with player name
local function parseBettingNotification(messageText)
	-- Try to match "You won" pattern first
	-- Format: "You won $X betting on Y in ..."
	local winPattern = "You won (%$[%d%.]+) betting on ([^%s]+) in (.+)"
	local amount, betTarget, raceInfo = string.match(messageText, winPattern)
	local isWinNotification = true

	-- If that didn't match, try "You placed" pattern
	-- Format: "You placed $X on Y to win in ..."
	if not amount then
		local placePattern = "You placed (%$[%d%.]+) on ([^%s]+) to win in (.+)"
		amount, betTarget, raceInfo = string.match(messageText, placePattern)
		isWinNotification = false
	end

	-- If neither pattern matched, return as-is
	if not amount or not betTarget or not raceInfo then
		return messageText
	end

	-- Check if betTarget is a number (roblox_id) or a string (NPC name)
	local robloxId = tonumber(betTarget)

	if robloxId then
		-- It's a roblox_id, try to get the player name
		local success, playerName = pcall(function()
			return Players:GetNameFromUserIdAsync(robloxId)
		end)

		if success and playerName then
			-- Replace roblox_id with player name
			if isWinNotification then
				return string.format("You won %s betting on %s in %s", amount, playerName, raceInfo)
			else
				return string.format("You placed %s on %s to win in %s", amount, playerName, raceInfo)
			end
		else
			-- Couldn't get player name, show generic message without the name
			if isWinNotification then
				return string.format("You won %s in %s", amount, raceInfo)
			else
				return string.format("You placed %s in %s", amount, raceInfo)
			end
		end
	else
		-- It's an NPC name, return as-is
		return messageText
	end
end

-- Function to update the text of a notification element based on its stored data
local function updateNotificationText(notificationElement)
	local notificationData = notificationElement:GetAttribute("NotificationData")
	if not notificationData then return end

	-- Parse the stored JSON data
	local success, data = pcall(function()
		return game:GetService("HttpService"):JSONDecode(notificationData)
	end)
	if not success then return end

	local textLabel = Utils.findDescendantByName(notificationElement, "TextLabel")
	if not textLabel then return end

	-- Recalculate relative time
	local relativeTime = getRelativeTime(data.created_date)
	local messageText = data.text or "No message"

	-- Parse betting notifications to replace roblox_id with player name
	messageText = parseBettingNotification(messageText)

	-- Colors
	local blueColor = "rgb(100, 149, 237)"
	local whiteColor = "rgb(255, 255, 255)"
	local greenColor = "rgb(0, 255, 0)"

	-- Format with updated timestamp
	local messageColor = string.find(messageText, "$", 1, true) and greenColor or whiteColor
	local formattedText = string.format(
		'<font color="%s">[%s]</font> <font color="%s">%s</font>',
		blueColor,
		relativeTime,
		messageColor,
		messageText
	)

	textLabel.Text = formattedText
end

-- Function to create a notification UI element
local function createNotificationElement(notificationData)
	-- Clone the template
	local notificationElement = template:Clone()
	notificationElement.Name = "Notification"
	notificationElement.Visible = true

	-- Store notification data as JSON attribute for later updates
	local success, jsonData = pcall(function()
		return game:GetService("HttpService"):JSONEncode({
			created_date = notificationData.created_date,
			text = notificationData.text
		})
	end)
	if success then
		notificationElement:SetAttribute("NotificationData", jsonData)
	end

	-- Find the TextLabel and set the notification message
	local textLabel = Utils.findDescendantByName(notificationElement, "TextLabel")
	if textLabel then
		-- Enable RichText for inline color formatting
		textLabel.RichText = true

		-- Get relative time and message
		local relativeTime = getRelativeTime(notificationData.created_date)
		local messageText = notificationData.text or "No message"

		-- Parse betting notifications to replace roblox_id with player name
		messageText = parseBettingNotification(messageText)

		-- Colors
		local blueColor = "rgb(100, 149, 237)" -- Cornflower blue for timestamp
		local whiteColor = "rgb(255, 255, 255)" -- White for normal messages
		local greenColor = "rgb(0, 255, 0)" -- Green for money messages

		-- Format with blue timestamp prefix
		local formattedText

		-- Check if message contains $ character and set message color to green
		if string.find(messageText, "$", 1, true) then
			formattedText = string.format(
				'<font color="%s">[%s]</font> <font color="%s">%s</font>',
				blueColor,
				relativeTime,
				greenColor,
				messageText
			)

			-- Call FetchPlayer RemoteFunction when $ is detected
			local success, result = pcall(function()
				return fetchPlayerFunc:InvokeServer()
			end)

			if success then
				print("[NotificationScript] Called FetchPlayer for money notification")
			else
				warn("[NotificationScript] Failed to call FetchPlayer:", result)
			end
		else
			-- Normal message with white text
			formattedText = string.format(
				'<font color="%s">[%s]</font> <font color="%s">%s</font>',
				blueColor,
				relativeTime,
				whiteColor,
				messageText
			)
		end

		textLabel.Text = formattedText
	else
		warn("[NotificationScript] Could not find TextLabel in notification template")
	end

	-- Attach to scrolling frame
	notificationElement.Parent = scrollingFrame

	return notificationElement
end

-- Function to scroll to the bottom of the scrolling frame
local function scrollToBottom()
	-- Use a delayed approach to ensure UI is fully updated
	wait(0.1) -- Wait 100ms for UI to update

	-- Calculate the total content height
	local totalHeight = 0
	local padding = 0

	-- Check for UIListLayout padding
	local uiListLayout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if uiListLayout then
		padding = uiListLayout.Padding.Offset
	end

	for _, child in pairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") and child.Name == "Notification" then
			totalHeight = totalHeight + child.Size.Y.Offset + padding
		end
	end

	print("[NotificationScript] Total height:", totalHeight, "ScrollingFrame size:", scrollingFrame.AbsoluteSize.Y, "Padding:", padding)

	-- Set the canvas size to accommodate all content
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)

	-- Try multiple scroll approaches
	scrollingFrame.CanvasPosition = Vector2.new(0, math.huge)

	-- Alternative approach - wait a bit more and try again
	wait(0.05)
	scrollingFrame.CanvasPosition = Vector2.new(0, totalHeight)
end

-- Function to update notifications
local function updateNotifications()
	-- Call the GetNotifications function
	local success, notifications = pcall(function()
		return fetchQueueFunc:InvokeServer()
	end)

	if success and notifications then
		print("[NotificationScript] Received", #notifications, "notifications")

		-- Clear existing notifications
		clearNotifications()

		-- Create new notification elements in reverse order
		for i = #notifications, 1, -1 do
			createNotificationElement(notifications[i])
		end

		-- Scroll to bottom
		scrollToBottom()
	else
		if not success then
			warn("[NotificationScript] Error calling GetNotifications:", notifications)
		else
			-- No notifications or no changes (returned nil)
			-- print("[NotificationScript] No notification changes")
		end
	end
end

-- Start the 5-second loop
local lastUpdateTime = 0
local UPDATE_INTERVAL = 5 -- seconds

local function onHeartbeat()
	local currentTime = tick()
	if currentTime - lastUpdateTime >= UPDATE_INTERVAL then
		lastUpdateTime = currentTime
		updateNotifications()
	end
end

-- Connect to RunService.Heartbeat for the loop
RunService.Heartbeat:Connect(onHeartbeat)

-- Initial update
updateNotifications()

print("[NotificationScript] Started notification polling every 5 seconds")

-- Function to update all notification timestamps
local function updateAllTimestamps()
	for _, child in pairs(scrollingFrame:GetChildren()) do
		if child.Name == "Notification" then
			updateNotificationText(child)
		end
	end
end

-- Start the 60-second timestamp update loop
local lastTimestampUpdate = 0
local TIMESTAMP_UPDATE_INTERVAL = 60 -- seconds

local function onTimestampUpdate()
	local currentTime = tick()
	if currentTime - lastTimestampUpdate >= TIMESTAMP_UPDATE_INTERVAL then
		lastTimestampUpdate = currentTime
		updateAllTimestamps()
	end
end

-- Connect timestamp updater to Heartbeat
RunService.Heartbeat:Connect(onTimestampUpdate)

print("[NotificationScript] Started timestamp updates every 60 seconds")
