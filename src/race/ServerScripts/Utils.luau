-- Utils.lua
-- Server-side utility functions for the Roblox racing game
--
-- startScrollingText Usage:
-- local control = Utils.startScrollingText(textLabel, 200, 100, { includeStrokeSibling = false })
-- 
-- -- Update text later:
-- control:updateText("New text here")
-- 
-- -- Stop scrolling and clean up:
-- control:stop()
--
-- The function returns a control object that can be used to:
-- - updateText(newText): Change the scrolling text
-- - stop(): Stop scrolling and clean up resources

local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Utils = {}

-- Weak table to store scrolling text controls (prevents memory leaks)
local scrollingTextControls = setmetatable({}, {__mode = "k"})


function Utils.findDescendantByName(parent, name)
	for _, descendant in ipairs(parent:GetDescendants()) do
		if descendant.Name == name then
			return descendant
		end
	end
	return nil
end


function Utils.contains(tbl, val)
	for _, v in ipairs(tbl) do
		if v == val then
			return true
		end
	end
	return false
end


function Utils.split(str, delimiter)
	local result = {}
	for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
		table.insert(result, match)
	end
	return result
end


-- Get player name from Roblox ID, with special handling for test players
-- Test players (negative IDs) are converted to "Player 1", "Player 2", etc.
function Utils.GetPlayerName(robloxId)
	-- Handle Studio test players (negative IDs)
	if robloxId < 0 then
		return "Player " .. math.abs(robloxId)
	end

	local success, result = pcall(function()
		return Players:GetNameFromUserIdAsync(robloxId)
	end)

	if success then
		return result
	else
		warn(string.format("[Utils] Failed to get name for user %d: %s", robloxId, tostring(result)))
		return "Player#" .. robloxId
	end
end


-- Check if a player owns the garage that contains the given pad
-- Returns true if the player's assigned garage matches the pad's parent garage
function Utils.IsPlayerGarageOwner(player, pad)
	if not player or not pad then
		return false
	end

	-- Get the player's assigned garage from their attribute
	local assignedGarage = player:GetAttribute("AssignedGarage")
	if not assignedGarage then
		warn("[Utils] Player " .. player.Name .. " has no assigned garage")
		return false
	end

	-- Find the garage that contains this pad
	local current = pad.Parent
	while current do
		-- Check if this is a garage in the Garages folder
		if current.Parent and current.Parent.Name == "Garages" then
			-- Found the garage, check if it matches the player's assigned garage
			return current.Name == assignedGarage
		end
		current = current.Parent
	end

	warn("[Utils] Could not find garage parent for pad:", pad.Name)
	return false
end


-- Parse a color string like "255,255,255" and return a Color3
function Utils.parseColorString(colorString)
	if not colorString or colorString == "" then
		return nil
	end

	local parts = Utils.split(colorString, ",")
	if #parts ~= 3 then
		warn("[Utils] parseColorString: invalid format, expected 'R,G,B':", colorString)
		return nil
	end

	local r = tonumber(parts[1])
	local g = tonumber(parts[2])
	local b = tonumber(parts[3])

	if not r or not g or not b then
		warn("[Utils] parseColorString: could not parse numbers from:", colorString)
		return nil
	end

	-- Clamp values to 0-255
	r = math.clamp(r, 0, 255)
	g = math.clamp(g, 0, 255)
	b = math.clamp(b, 0, 255)

	return Color3.fromRGB(r, g, b)
end


Utils.colorIconScheme = {
	Common = {
		icon = "rbxassetid://85396582444630",
		bottom = Color3.fromRGB(0, 62, 117),
		top = Color3.fromRGB(6, 123, 202),
		startKey = Color3.fromRGB(0, 83, 157),
		endKey = Color3.fromRGB(0, 105, 176)
	},
	Rare = {
		icon = "rbxassetid://82301679193973",
		bottom = Color3.fromRGB(29, 126, 2),
		top = Color3.fromRGB(79, 213, 2),
		startKey = Color3.fromRGB(51, 172, 41),
		endKey = Color3.fromRGB(66, 192, 24)
	},
	Epic = {
		icon = "rbxassetid://89746368504335",
		bottom = Color3.fromRGB(98, 27, 167),
		top = Color3.fromRGB(186, 50, 226),
		startKey = Color3.fromRGB(133, 26, 193),
		endKey = Color3.fromRGB(157, 42, 218)
	},
	Legendary = {
		icon = "rbxassetid://77146147741356",
		bottom = Color3.fromRGB(236, 116, 0),
		top = Color3.fromRGB(255, 219, 49),
		startKey = Color3.fromRGB(247, 160, 19),
		endKey = Color3.fromRGB(255, 192, 38)
	},
	NotAvailable = {
		bottom = Color3.fromRGB(80, 72, 91),
		top = Color3.fromRGB(135, 127, 148),
		startKey = Color3.fromRGB(98,90,110),
		endKey = Color3.fromRGB(116, 109, 127)
	}
}


function Utils.switchColorIcon(item, level)
	local background = Utils.findDescendantByName(item, "Background")
	local bottom = Utils.findDescendantByName(background, "Bottom")
	bottom.BackgroundColor3 = Utils.colorIconScheme[level]["bottom"]
	local color = Utils.findDescendantByName(background, "Color")
	local top = Utils.findDescendantByName(color, "Top")
	top.BackgroundColor3 = Utils.colorIconScheme[level]["top"]
	local levelItem = Utils.findDescendantByName(item, "Level")
	local imageLevel = Utils.findDescendantByName(levelItem, "ImageLabel")
	if level ~= "NotAvailable" then
		imageLevel.Image = Utils.colorIconScheme[level]["icon"]
	end
	local bottomFrame = Utils.findDescendantByName(color, "Bottom")
	local bottomGradient = Utils.findDescendantByName(bottomFrame, "UIGradient")
	bottomGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Utils.colorIconScheme[level]["startKey"]),
		ColorSequenceKeypoint.new(1, Utils.colorIconScheme[level]["endKey"])
	})
end


function Utils.removeCarFromGarage(player, slotNumber)
	local playerGarageName = player:GetAttribute("AssignedGarage")
	local garage = workspace:FindFirstChild(playerGarageName, true)
	local target = garage:FindFirstChild("Pad" .. tostring(slotNumber), true)
	if not target or not target:IsA("BasePart") then return end

	local car = target:FindFirstChild("Car")
	if car then
		car:Destroy()
		local mPad = garage:FindFirstChild("MPad" .. tostring(slotNumber))
		local money = mPad:FindFirstChild("Money")
		if money then
			money.Value = 0
		end
		local billboard = mPad:FindFirstChild("BillboardGui")
		local top = billboard:FindFirstChild("Top")
		local mpMoney = mPad:FindFirstChild("MPMoney", true)
		local mpMoneyStroke = mPad:FindFirstChild("MPMoneyStroke", true)
		local bottom = billboard:FindFirstChild("Bottom")
		top.Visible = false
		bottom.Visible = false
		mpMoney.Text = "$" .. math.floor(money.Value)
		mpMoneyStroke.Text = "$" .. math.floor(money.Value)
	end
end


Utils.getIsoNow = function()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

-- Helper: add a floating name tag to a car using ReplicatedStorage.NameTemplate
Utils.attachNameBillboard = function(carModel: Model, displayName: string)
	local part = carModel.PrimaryPart
	if not part then return end

	-- Store the base name as an attribute for later position updates
	carModel:SetAttribute("BaseName", displayName)

	-- Attachment to anchor the billboard above the car
	local att = part:FindFirstChild("NameBillboardAtt") or Instance.new("Attachment")
	att.Name = "NameBillboardAtt"
	att.Position = Vector3.new(0, 1, 0)
	att.Parent = part

	-- Clone the template BillboardGui
	local template = ReplicatedStorage:FindFirstChild("NameTemplate")
	if not template or not template:IsA("BillboardGui") then return end

	local bb = template:Clone()
	bb.Name = "DriverBillboard"
	bb.Adornee = att
	bb.Parent = carModel

	-- Set both text labels (initial text without position)
	local rootFrame = bb:FindFirstChild("Frame")
	if rootFrame then
		local textFrame = rootFrame:FindFirstChild("Text")
		if textFrame and textFrame:IsA("Frame") then
			local label = textFrame:FindFirstChild("TextLabel")
			local stroke = textFrame:FindFirstChild("TextLabel - Stroke")
			if label and label:IsA("TextLabel") then label.Text = displayName end
			if stroke and stroke:IsA("TextLabel") then stroke.Text = displayName end
		end
	end
end

-- Update the name billboard with the current race position
-- Shows "#1 - PlayerName" format
Utils.updateNameBillboardPosition = function(carModel: Model, place: number)
	if not carModel then return end

	local baseName = carModel:GetAttribute("BaseName")
	if not baseName then return end

	local bb = carModel:FindFirstChild("DriverBillboard")
	if not bb then return end

	-- Format: "#1 - PlayerName"
	local displayText = "#" .. tostring(place) .. " - " .. baseName

	-- Update both text labels
	local rootFrame = bb:FindFirstChild("Frame")
	if rootFrame then
		local textFrame = rootFrame:FindFirstChild("Text")
		if textFrame and textFrame:IsA("Frame") then
			local label = textFrame:FindFirstChild("TextLabel")
			local stroke = textFrame:FindFirstChild("TextLabel - Stroke")
			if label and label:IsA("TextLabel") then label.Text = displayText end
			if stroke and stroke:IsA("TextLabel") then stroke.Text = displayText end
		end
	end
end


-- Utils.startScrollingText(textLabel: TextLabel, speedPx: number, gapPx: number, opts: table?)
-- opts = {
--   forceSurfacePixelsPerStud = number?   -- e.g. 50; only applied to SurfaceGui if provided
--   includeStrokeSibling = true|false     -- clone sibling named "TextLabel - Stroke" if present (default true)
-- }
Utils.startScrollingText = function(textLabel: TextLabel, speedPx: number, gapPx: number, opts: table?)
	assert(textLabel and textLabel:IsA("TextLabel"), "startScrollingText: pass a TextLabel")
	opts = opts or {}
	if opts.includeStrokeSibling == nil then opts.includeStrokeSibling = true end

	-- Check if this TextLabel already has scrolling text active
	local existingControl = scrollingTextControls[textLabel]
	if existingControl then
		-- Return existing control if already initialized
		return existingControl
	end

	local container = textLabel.Parent
	if not (container and container:IsA("GuiObject")) then
		warn("startScrollingText: TextLabel must be inside a Frame/GuiObject container")
		return nil
	end
	container.ClipsDescendants = true

	-- Optional SurfaceGui PPS (only if caller asks)
	local surf = textLabel:FindFirstAncestorWhichIsA("SurfaceGui")
	if surf and opts.forceSurfacePixelsPerStud then
		surf.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surf.PixelsPerStud = opts.forceSurfacePixelsPerStud
	end

	-- Try to find a separate stroke sibling
	local strokeSibling: TextLabel? = nil
	if opts.includeStrokeSibling then
		for _, sib in ipairs(container:GetChildren()) do
			if sib ~= textLabel and sib:IsA("TextLabel") and sib.Name:lower():find("stroke") then
				strokeSibling = sib
				break
			end
		end
	end

	-- Build groups
	local function mkGroup(name: string): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = container
		return f
	end

	local function cloneInto(parent: Instance, src: TextLabel): TextLabel
		local l = src:Clone()
		l.Parent = parent
		return l
	end

	local groupA = mkGroup("ScrollGroupA")
	local groupB = mkGroup("ScrollGroupB")
	local labelA = cloneInto(groupA, textLabel)
	local labelB = cloneInto(groupB, textLabel)
	local strokeA = strokeSibling and cloneInto(groupA, strokeSibling) or nil
	local strokeB = strokeSibling and cloneInto(groupB, strokeSibling) or nil

	-- Hide originals
	textLabel.Visible = false
	if strokeSibling then strokeSibling.Visible = false end

	-- Ensure properties that affect width
	for _, l in ipairs({labelA, labelB, strokeA, strokeB}) do
		if l then
			l.BackgroundTransparency = 1
			l.TextWrapped = false
			-- We’ll size by pixels explicitly:
			l.Size = UDim2.fromOffset(0, 0)
			l.AutomaticSize = Enum.AutomaticSize.None
			l.TextTruncate = Enum.TextTruncate.None
		end
	end

	local function syncStyles(dst: TextLabel?, src: TextLabel?)
		if not (dst and src) then return end
		dst.Text = src.Text
		dst.Font = src.Font
		dst.FontFace = src.FontFace
		dst.TextSize = src.TextSize
		dst.TextScaled = src.TextScaled
		dst.TextColor3 = src.TextColor3
		dst.RichText = src.RichText
		dst.TextTransparency = src.TextTransparency
		dst.TextStrokeTransparency = src.TextStrokeTransparency
		dst.TextStrokeColor3 = src.TextStrokeColor3
	end

	local function placeStack(group: Frame, lbl: TextLabel?, stroke: TextLabel?)
		if not lbl then return end
		-- Label on top, stroke behind (or vice-versa—match your template)
		lbl.ZIndex = (group.ZIndex or 1) + 1
		if stroke then stroke.ZIndex = lbl.ZIndex - 1 end
		-- Center vertically in the group
		lbl.AnchorPoint = Vector2.new(0, 0.5)
		lbl.Position = UDim2.fromScale(0, 0.5)
		if stroke then
			stroke.AnchorPoint = Vector2.new(0, 0.5)
			stroke.Position = UDim2.fromScale(0, 0.5)
		end
	end

	-- Wait until we have real sizes (prevents 1-letter width)
	local function waitForLayout()
		local tries = 0
		while (container.AbsoluteSize.X < 2 or container.AbsoluteSize.Y < 2) and tries < 60 do
			tries += 1
			RunService.Heartbeat:Wait()
		end
		-- Also give TextBounds a frame to compute
		RunService.Heartbeat:Wait()
	end
	waitForLayout()

	local textWidth, cycle, x = 0, 0, 0

	-- helper: robust width measurement that works with/without TextScaled
	local function measureTextPixels(lbl: TextLabel): number
		-- Use TextService for determinism; adjust size if TextScaled
		local effectiveSize = lbl.TextScaled and math.max(8, math.floor(lbl.AbsoluteSize.Y * 0.8)) or lbl.TextSize
		local bounds = TextService:GetTextSize(
			lbl.Text, effectiveSize, lbl.Font, Vector2.new(10^6, lbl.AbsoluteSize.Y > 0 and lbl.AbsoluteSize.Y or 100)
		)
		-- If RichText is on, TextService ignores tags; TextBounds can be used as a correction after a frame:
		if lbl.RichText then
			RunService.Stepped:Wait()
			bounds = Vector2.new(math.max(bounds.X, lbl.TextBounds.X), bounds.Y)
		end
		return math.max(1, bounds.X)
	end

	local function layout()
		-- Keep styles in sync
		labelB.Text = labelA.Text
		labelB.Font = labelA.Font
		labelB.FontFace = labelA.FontFace
		labelB.TextSize = labelA.TextSize
		labelB.TextScaled = labelA.TextScaled
		labelB.TextColor3 = labelA.TextColor3
		labelA.TextWrapped = false
		labelB.TextWrapped = false

		if strokeA and strokeB then
			strokeA.Text = strokeA.Text -- no-op, but keeps parity with A/B
			strokeB.Text = strokeA.Text
			strokeA.TextScaled = labelA.TextScaled
			strokeB.TextScaled = labelA.TextScaled
		end

		-- Wait one frame so AbsoluteSize/TextBounds are valid
		RunService.Heartbeat:Wait()

		-- Measure text width
		local w = measureTextPixels(labelA)
		local maskH = math.max(1, container.AbsoluteSize.Y)
		local containerW = math.max(1, container.AbsoluteSize.X)

		-- Size the labels and stacks by pixels
		labelA.Size = UDim2.fromOffset(w, maskH)
		labelB.Size = UDim2.fromOffset(w, maskH)
		if strokeA then strokeA.Size = UDim2.fromOffset(w, maskH) end
		if strokeB then strokeB.Size = UDim2.fromOffset(w, maskH) end

		-- The distance between copies must be AT LEAST the text width.
		-- If the text is shorter than the mask, space by the mask so it exits fully before re-entering.
		local spacing = math.max(w, containerW) + math.max(gapPx or 0, 8)

		-- Group frames move; labels stay at (0, center)
		groupA.Size = UDim2.fromOffset(w, maskH)
		groupB.Size = UDim2.fromOffset(w, maskH)
		groupA.Position = UDim2.fromOffset(0, 0)
		groupB.Position = UDim2.fromOffset(spacing, 0)

		-- Stack label + stroke centered vertically in each group
		local function centerStack(lbl: TextLabel?, strk: TextLabel?)
			if not lbl then return end
			lbl.AnchorPoint = Vector2.new(0, 0.5)
			lbl.Position = UDim2.fromScale(0, 0.5)
			if strk then
				strk.AnchorPoint = Vector2.new(0, 0.5)
				strk.Position = UDim2.fromScale(0, 0.5)
				strk.ZIndex = (lbl.ZIndex or 1) - 1
			end
		end
		centerStack(labelA, strokeA)
		centerStack(labelB, strokeB)

		-- These drive the scroll loop
		textWidth = w
		cycle = spacing
		x = 0
	end

	layout()

	-- Scroll loop
	local hbConn = RunService.Heartbeat:Connect(function(dt)
		if cycle <= 0 then return end
		x = (x + speedPx * dt) % cycle
		groupA.Position = UDim2.fromOffset(-x, 0)
		groupB.Position = UDim2.fromOffset(-x + cycle, 0)
	end)

	-- Re-layout when needed
	local function hook(inst: Instance, prop: string)
		if inst and inst.GetPropertyChangedSignal then
			inst:GetPropertyChangedSignal(prop):Connect(layout)
		end
	end
	for _, p in ipairs({"AbsoluteSize"}) do hook(container, p) end
	for _, p in ipairs({"Text", "TextSize", "TextScaled", "Font", "FontFace"}) do hook(textLabel, p) end
	if strokeSibling then
		for _, p in ipairs({"Text", "TextSize", "TextScaled", "Font", "FontFace"}) do hook(strokeSibling, p) end
	end

	-- Create control object for updating text
	local control = {
		textLabel = textLabel,
		labelA = labelA,
		labelB = labelB,
		strokeA = strokeA,
		strokeB = strokeB,
		strokeSibling = strokeSibling,
		layout = layout,
		hbConn = hbConn,

		-- Method to update text
		updateText = function(self, newText)
			if not self.textLabel or not self.labelA or not self.labelB then
				warn("ScrollingText control: TextLabel or labels no longer exist")
				return false
			end

			-- Update the original TextLabel
			self.textLabel.Text = newText

			-- Also update stroke sibling if it exists
			if self.strokeSibling then
				self.strokeSibling.Text = newText
			end

			-- Directly update the cloned labels
			self.labelA.Text = newText
			self.labelB.Text = newText

			-- Update stroke clones if they exist
			if self.strokeA then
				self.strokeA.Text = newText
			end
			if self.strokeB then
				self.strokeB.Text = newText
			end

			-- Force a layout update to recalculate scrolling with new text
			if self.layout then
				self.layout()
			end

			return true
		end,

		-- Method to stop scrolling
		stop = function(self)
			if self.hbConn then
				self.hbConn:Disconnect()
				self.hbConn = nil
			end

			-- Clean up created elements
			if self.labelA and self.labelA.Parent then
				self.labelA.Parent:Destroy()
			end
			if self.labelB and self.labelB.Parent then
				self.labelB.Parent:Destroy()
			end

			-- Show original TextLabel again
			if self.textLabel then
				self.textLabel.Visible = true
			end
			if self.strokeSibling then
				self.strokeSibling.Visible = true
			end

			-- Remove the control from the weak table
			if self.textLabel then
				scrollingTextControls[self.textLabel] = nil
			end
		end
	}

	-- Store control reference in the weak table
	scrollingTextControls[textLabel] = control

	return control
end


-- Billboard control cache (weak table to prevent memory leaks)
local billboardControls = setmetatable({}, {__mode = "k"})

-- Track last positions to avoid unnecessary updates
local lastPositions = {}

-- Get or create the RaceStatsUpdate RemoteEvent
local function getRaceStatsEvent()
	local remoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
	if not remoteEvents then
		remoteEvents = Instance.new("Folder")
		remoteEvents.Name = "RemoteEvents"
		remoteEvents.Parent = ReplicatedStorage
	end

	local event = remoteEvents:FindFirstChild("RaceStatsUpdate")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "RaceStatsUpdate"
		event.Parent = remoteEvents
	end
	return event
end

-- Fire race stats update to all clients
-- Called by race scripts to update the client-side Stats GUI
Utils.fireRaceStatsUpdate = function(trackName, data)
	local event = getRaceStatsEvent()
	if event then
		event:FireAllClients(trackName, data)
	end
end

-- Utility function to update race billboard
Utils.updateRaceBillboard = function(trackName, status, positions)
	-- Find the billboard for this track
	local conventionFolder = workspace:FindFirstChild("Convention")
	if not conventionFolder then
		warn("[Utils] Convention folder not found in workspace")
		return
	end

	local trackFolder = conventionFolder:FindFirstChild(trackName)
	if not trackFolder then
		warn("[Utils] Track folder not found:", trackName)
		return
	end

	local model = trackFolder:FindFirstChild("Model")
	if not model then
		warn("[Utils] Model not found for track:", trackName)
		return
	end

	local scrollPart = model:FindFirstChild("Scroll")
	if not scrollPart then
		warn("[Utils] Scroll part not found for track:", trackName)
		return
	end

	local surfaceGui = scrollPart:FindFirstChild("SurfaceGui")
	if not surfaceGui then
		warn("[Utils] SurfaceGui not found for track:", trackName)
		return
	end

	local frame = surfaceGui:FindFirstChild("Frame")
	if not frame then
		warn("[Utils] Frame not found for track:", trackName)
		return
	end

	local textFrame = frame:FindFirstChild("Text")
	if not textFrame then
		warn("[Utils] Text frame not found for track:", trackName)
		return
	end

	local textLabel = textFrame:FindFirstChild("TextLabel")
	if not textLabel then
		warn("[Utils] TextLabel not found for track:", trackName)
		return
	end

	-- Check if positions have changed (only for in_progress status)
	if status == "in_progress" and positions then
		local key = trackName .. "_positions"
		local lastPos = lastPositions[key]

		-- Check if positions are the same
		if lastPos then
			local same = true
			if #lastPos == #positions then
				for i = 1, #positions do
					local currentName = positions[i].name or positions[i]
					local lastName = lastPos[i].name or lastPos[i]
					if currentName ~= lastName then
						same = false
						break
					end
				end
			else
				same = false
			end

			-- If positions haven't changed, don't update
			if same then
				return
			end
		end

		-- Store current positions for next comparison
		lastPositions[key] = {}
		for i, pos in ipairs(positions) do
			lastPositions[key][i] = pos
		end
	end

	-- Get or create scrolling text control
	local control = billboardControls[textLabel]
	if not control then
		control = Utils.startScrollingText(textLabel, 150, 50, { includeStrokeSibling = false })
		if control then
			billboardControls[textLabel] = control
		end
	end

	-- Helper function to get proper ordinal suffix
	local function getOrdinalSuffix(num)
		if num == 1 then return "st"
		elseif num == 2 then return "nd"
		elseif num == 3 then return "rd"
		else return "th"
		end
	end

	-- Build the message based on status
	local message = ""
	if status == "starting" then
		message = "Race Starting Soon!!"
	elseif status == "in_progress" then
		message = "Race in progress: "
		if positions and #positions > 0 then
			for i, position in ipairs(positions) do
				if i > 1 then message = message .. ", " end
				message = message .. i .. getOrdinalSuffix(i) .. " " .. (position.name or position or "Unknown")
			end
		else
			message = message .. "Positions updating..."
		end
	elseif status == "finished" then
		message = "Race Over "
		if positions and #positions > 0 then
			for i, position in ipairs(positions) do
				if i > 1 then message = message .. ", " end
				message = message .. i .. getOrdinalSuffix(i) .. " " .. (position.name or position or "Unknown")
			end
		else
			message = message .. "Results pending..."
		end
	else
		message = "Race Status: " .. tostring(status)
	end

	-- Update the scrolling text
	if control then
		control:updateText(message)
	else
		-- Fallback to direct text update
		textLabel.Text = message
	end
end

-- ============================================
-- NPC Vehicle Skin and Color Utilities
-- ============================================

-- Predefined color palette for NPC vehicles (different from player colors in SkinGui)
Utils.NPC_COLOR_PALETTE = {
	{name = "Midnight Blue", color = Color3.fromRGB(25, 25, 112)},
	{name = "Forest Green", color = Color3.fromRGB(34, 139, 34)},
	{name = "Burgundy", color = Color3.fromRGB(128, 0, 32)},
	{name = "Slate Gray", color = Color3.fromRGB(112, 128, 144)},
	{name = "Burnt Orange", color = Color3.fromRGB(204, 85, 0)},
	{name = "Deep Purple", color = Color3.fromRGB(75, 0, 130)},
	{name = "Teal", color = Color3.fromRGB(0, 128, 128)},
	{name = "Maroon", color = Color3.fromRGB(128, 0, 0)},
	{name = "Olive", color = Color3.fromRGB(128, 128, 0)},
	{name = "Charcoal", color = Color3.fromRGB(54, 69, 79)},
	{name = "Navy", color = Color3.fromRGB(0, 0, 128)},
	{name = "Copper", color = Color3.fromRGB(184, 115, 51)},
	{name = "Steel Blue", color = Color3.fromRGB(70, 130, 180)},
	{name = "Dark Cyan", color = Color3.fromRGB(0, 139, 139)},
	{name = "Chocolate", color = Color3.fromRGB(123, 63, 0)},
}

-- Filter skins by price range (inclusive)
function Utils.filterSkinsByPrice(skins, minPrice, maxPrice)
	if not skins then return {} end

	local filtered = {}
	for _, skin in ipairs(skins) do
		local price = skin.price or 0
		local passesMin = (minPrice == nil) or (price >= minPrice)
		local passesMax = (maxPrice == nil) or (price <= maxPrice)
		if passesMin and passesMax then
			table.insert(filtered, skin)
		end
	end
	return filtered
end

-- Get appropriate skins for a race level
-- Common: price < 80 (free tier)
-- Rare: price < 200 (free + tier I)
-- Epic: price >= 80 AND price <= 200 (tier I + tier II, no free)
-- Legendary: price >= 400 (tier III)
function Utils.getSkinsForRaceLevel(skins, level)
	if not skins or not level then return {} end

	if level == "Common" then
		return Utils.filterSkinsByPrice(skins, nil, 79)
	elseif level == "Rare" then
		return Utils.filterSkinsByPrice(skins, nil, 199)
	elseif level == "Epic" then
		return Utils.filterSkinsByPrice(skins, 80, 200)
	elseif level == "Legendary" then
		return Utils.filterSkinsByPrice(skins, 400, nil)
	else
		-- Default to common if unknown level
		warn("[Utils] Unknown race level:", level, "- defaulting to Common")
		return Utils.filterSkinsByPrice(skins, nil, 79)
	end
end

-- Pick a random skin from a list of skins
function Utils.getRandomSkin(skins)
	if not skins or #skins == 0 then
		return nil
	end
	return skins[math.random(1, #skins)]
end

-- Pick a random color from the NPC color palette
function Utils.getRandomNPCColor()
	local palette = Utils.NPC_COLOR_PALETTE
	return palette[math.random(1, #palette)]
end

-- Get the first free skin (price < 80) as a fallback default
function Utils.getDefaultFreeSkin(skins)
	if not skins then return nil end

	for _, skin in ipairs(skins) do
		local price = skin.price or 0
		if price < 80 then
			return skin.name
		end
	end
	return nil
end

-- ============================================
-- Model Setup Utilities (welding, scaling, PrimaryPart)
-- ============================================

-- Ensure a model has a PrimaryPart set (finds Root, Body, or first BasePart)
function Utils.ensurePrimaryPart(model)
	if model.PrimaryPart then return end

	local rootPart = nil
	local bodyPart = nil
	local anyPart = nil

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if descendant.Name == "Root" and not rootPart then
				rootPart = descendant
			elseif descendant.Name == "Body" and not bodyPart then
				bodyPart = descendant
			end
			if not anyPart then
				anyPart = descendant
			end
		end
	end

	local primaryPart = rootPart or bodyPart or anyPart
	if primaryPart then
		model.PrimaryPart = primaryPart
	else
		warn("[Utils] Could not find any BasePart to set as PrimaryPart for:", model.Name)
	end
end

-- Weld all parts in a model to the PrimaryPart so they move together
-- excludeParts: optional set of parts to skip (e.g., wheel parts that use hinges)
function Utils.weldModelParts(model, excludeParts)
	local rootPart = model.PrimaryPart
	if not rootPart then
		warn("[Utils] Cannot weld parts: no PrimaryPart set for", model.Name)
		return
	end

	excludeParts = excludeParts or {}

	local weldCount = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= rootPart and not excludeParts[descendant] then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "AutoWeld_" .. descendant.Name
			weld.Part0 = rootPart
			weld.Part1 = descendant
			weld.Parent = rootPart

			descendant.Anchored = false
			weldCount = weldCount + 1
		end
	end

end

-- Find all wheel models in a car (looks for meshes with "tire" in name, excludes steering wheels)
-- Returns both the wheel models and a set of all parts inside them (for weld exclusion)
function Utils.findWheelModels(car)
	local wheelModels = {}
	local wheelParts = {} -- Set of parts inside wheel models (to exclude from welding)
	local foundModels = {} -- to avoid duplicates

	for _, descendant in ipairs(car:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local nameLower = descendant.Name:lower()
			-- Look for "tire" specifically, or "wheel" but NOT "steering"
			local isTire = nameLower:find("tire")
			local isWheel = nameLower:find("wheel") and not nameLower:find("steering")

			if isTire or isWheel then
				local parent = descendant.Parent
				if parent:IsA("Model") and not foundModels[parent] then
					foundModels[parent] = true
					table.insert(wheelModels, parent)
					-- Mark all parts in this wheel model
					for _, part in ipairs(parent:GetDescendants()) do
						if part:IsA("BasePart") then
							wheelParts[part] = true
						end
					end
				end
			end
		end
	end

	return wheelModels, wheelParts
end

-- Attach wheels to the car using CylindricalConstraints for proper physics attachment
-- Returns a table of wheel data for controlling wheel spin
function Utils.attachWheelsWithHinges(car, wheels, rootPart)
	local wheelData = {}

	-- FIRST: Build a set of all wheel parts for quick lookup
	local wheelPartSet = {}
	for _, wheelModel in ipairs(wheels) do
		for _, part in ipairs(wheelModel:GetDescendants()) do
			if part:IsA("BasePart") then
				wheelPartSet[part] = true
			end
		end
	end

	-- SECOND: Search ENTIRE car for welds that connect TO any wheel part
	-- These welds might be stored in body, not in wheel models
	local removedFromCar = 0
	for _, descendant in ipairs(car:GetDescendants()) do
		if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") or descendant:IsA("Motor6D") or descendant:IsA("ManualWeld") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			-- If either end of this weld connects to a wheel part, destroy it
			if wheelPartSet[part0] or wheelPartSet[part1] then
				descendant:Destroy()
				removedFromCar = removedFromCar + 1
			end
		end
	end

	for _, wheelModel in ipairs(wheels) do

		-- Remove any existing welds/constraints from this wheel model
		local removedCount = 0
		for _, descendant in ipairs(wheelModel:GetDescendants()) do
			if descendant:IsA("WeldConstraint") or descendant:IsA("Weld") or descendant:IsA("Motor6D") or descendant:IsA("ManualWeld") or descendant:IsA("Constraint") then
				descendant:Destroy()
				removedCount = removedCount + 1
			end
		end

		-- Find the main wheel/tire part
		local wheelPart = nil
		for _, part in ipairs(wheelModel:GetDescendants()) do
			if part:IsA("BasePart") then
				local nameLower = part.Name:lower()
				if nameLower:find("tire") or (nameLower:find("wheel") and not nameLower:find("steering")) then
					wheelPart = part
					break
				end
			end
		end

		if not wheelPart then
			wheelPart = wheelModel:FindFirstChildWhichIsA("BasePart", true)
		end

		if wheelPart then

			-- Skip checks
			local skipWheel = false
			if wheelModel == car then
				warn("[Utils] Skipping wheel - it's the car model itself!")
				skipWheel = true
			end

			if not skipWheel then
				for _, part in ipairs(wheelModel:GetDescendants()) do
					if part == rootPart then
						warn("[Utils] Skipping wheel - it contains the root part!")
						skipWheel = true
						break
					end
				end
			end

			if not skipWheel then
				-- First, weld all parts within this wheel model together to the main wheel part
				local allWheelParts = {}
				for _, part in ipairs(wheelModel:GetDescendants()) do
					if part:IsA("BasePart") and part ~= rootPart then
						local nameLower = part.Name:lower()
						local isBodyPart = nameLower:find("body") or nameLower:find("root") or nameLower:find("chassis") or nameLower:find("frame")
						if isBodyPart then
							warn("[Utils] SKIPPING body-like part in wheel model:", part.Name, "in", wheelModel.Name)
						else
							-- Make wheel parts unanchored so constraints work
							part.Anchored = false
							part.CanCollide = false
							part.Massless = true -- Massless so they don't affect physics much

							-- Weld non-main parts to the main wheel part
							if part ~= wheelPart then
								local weld = Instance.new("WeldConstraint")
								weld.Part0 = wheelPart
								weld.Part1 = part
								weld.Parent = wheelModel
							end

							table.insert(allWheelParts, part)
						end
					end
				end

				-- Create attachment on root part (at wheel position)
				local wheelOffset = rootPart.CFrame:ToObjectSpace(wheelPart.CFrame)

				local rootAttachment = Instance.new("Attachment")
				rootAttachment.Name = "WheelAttachment_" .. wheelModel.Name
				rootAttachment.CFrame = wheelOffset
				rootAttachment.Parent = rootPart

				-- Create attachment on wheel part (at its center)
				local wheelAttachment = Instance.new("Attachment")
				wheelAttachment.Name = "AxleAttachment"
				wheelAttachment.CFrame = CFrame.new() -- At wheel center
				wheelAttachment.Parent = wheelPart

				-- Create CylindricalConstraint to attach wheel to body
				-- This allows rotation around one axis (the axle) while keeping position fixed
				local constraint = Instance.new("CylindricalConstraint")
				constraint.Name = "WheelAxle_" .. wheelModel.Name
				constraint.Attachment0 = rootAttachment
				constraint.Attachment1 = wheelAttachment

				-- Lock linear motion (wheel stays in place relative to body)
				constraint.LimitsEnabled = true
				constraint.LowerLimit = 0
				constraint.UpperLimit = 0

				-- Enable angular motor for spinning
				constraint.AngularActuatorType = Enum.ActuatorType.Motor
				constraint.MotorMaxAngularAcceleration = 10000
				constraint.MotorMaxTorque = 10000
				constraint.AngularVelocity = 0 -- Will be set during race

				constraint.Parent = wheelModel

				-- Determine spin direction based on which side of the car this wheel is on
				-- Get wheel position in car's local coordinate system
				local wheelLocalPos = rootPart.CFrame:PointToObjectSpace(wheelPart.Position)
				-- If local X is positive, wheel is on one side; if negative, other side
				-- Left and right wheels need opposite spin directions
				local spinDirection = wheelLocalPos.X > 0 and 1 or -1

				table.insert(wheelData, {
					model = wheelModel,
					mainPart = wheelPart,
					allParts = allWheelParts,
					constraint = constraint,
					spinDirection = spinDirection,
					currentAngle = 0
				})

			end
		end
	end

	return wheelData
end

-- Spin wheels using CylindricalConstraint motor
-- wheelData: table from attachWheelsWithHinges
-- speed: linear velocity (studs/sec), positive = forward
-- dt: delta time (optional, not used with constraints)
-- rootPart: the car's root part (not used with constraints)
local WHEEL_ANGULAR_VELOCITY_FACTOR = 3.0 -- Convert linear speed to angular velocity (radians/sec per stud/sec)
function Utils.spinWheels(wheelData, speed, dt, rootPart)
	if not wheelData or #wheelData == 0 then return end

	-- Convert linear speed to angular velocity
	local angularVelocity = speed * WHEEL_ANGULAR_VELOCITY_FACTOR


	for _, data in ipairs(wheelData) do
		if data.constraint then
			-- Set the constraint's angular velocity, adjusted for wheel side
			-- Left and right wheels spin opposite directions to both appear "forward"
			local direction = data.spinDirection or 1
			data.constraint.AngularVelocity = angularVelocity * direction
		end
	end
end

-- ============================================
-- Model Scaling Utilities
-- ============================================

-- Scale a model to a target scale factor
function Utils.scaleModel(model, scaleFactor)
	-- Use Model:ScaleTo if available (newer Roblox API)
	if model.ScaleTo then
		local currentScale = model:GetScale()
		model:ScaleTo(scaleFactor)
		return
	end

	-- Fallback: manually scale each part
	local rootPart = model.PrimaryPart
	if not rootPart then
		warn("[Utils] Cannot scale: no PrimaryPart for", model.Name)
		return
	end

	local rootPos = rootPart.Position

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Size = descendant.Size * scaleFactor
			local offset = descendant.Position - rootPos
			descendant.Position = rootPos + (offset * scaleFactor)
		end
	end

end

-- ============================================
-- Car Sign Billboard Utilities
-- ============================================

-- Update the CarSign billboard with vehicle stats
-- vehicleData should include: name, level, total_speed, total_power, total_acceleration, total_weight
function Utils.updateCarSignBillboard(garage, padNumber, vehicleData)
	if not garage or not padNumber or not vehicleData then
		warn("[Utils] updateCarSignBillboard: missing required parameters")
		return
	end

	-- Find the CarSign for this pad number
	local carSign = garage:FindFirstChild("CarSign" .. tostring(padNumber), true)
	if not carSign then
		warn("[Utils] CarSign" .. tostring(padNumber) .. " not found in garage:", garage.Name)
		return
	end

	-- Find the SurfaceGui named "Vehicle"
	local surfaceGui = Utils.findDescendantByName(carSign, "Vehicle")
	if not surfaceGui then
		warn("[Utils] Vehicle SurfaceGui not found in CarSign" .. tostring(padNumber))
		return
	end

	-- Helper function to update a stat bar with progress indicator and text
	local function updateStatBar(frameName, percentValue, percentText)
		local statFrame = surfaceGui:FindFirstChild(frameName)
		if statFrame then
			local progressFrame = statFrame:FindFirstChild("Progress")
			if progressFrame then
				-- Update bar size
				local bar = Utils.findDescendantByName(progressFrame, "Bar")
				if bar then
					bar.Size = UDim2.new(percentValue, 0, bar.Size.Y.Scale, bar.Size.Y.Offset)
				end
				-- Update text labels
				local textLabel = Utils.findDescendantByName(progressFrame, "TextLabel")
				if textLabel then
					textLabel.Text = percentText
				end
				local textStroke = Utils.findDescendantByName(progressFrame, "TextLabel - Stroke")
				if textStroke then
					textStroke.Text = percentText
				end
			end
			statFrame.Visible = true
		end
	end

	-- Update Name
	local nameFrame = surfaceGui:FindFirstChild("Name")
	if nameFrame then
		local nameLabel = Utils.findDescendantByName(nameFrame, "TextLabel")
		if nameLabel then
			nameLabel.Text = vehicleData.name or ""
		end
		nameFrame.Visible = true
	end

	-- Update Level
	local levelFrame = surfaceGui:FindFirstChild("Level")
	if levelFrame then
		local levelLabel = Utils.findDescendantByName(levelFrame, "TextLabel")
		if levelLabel then
			levelLabel.Text = vehicleData.level or "Common"
		end
		levelFrame.Visible = true
	end

	-- Update Speed bar
	local speedPercent = math.clamp((vehicleData.total_speed or 0) / 1000, 0, 1)
	local speedPercentText = math.floor((vehicleData.total_speed or 0) / 10) .. "/100"
	updateStatBar("Speed", speedPercent, speedPercentText)

	-- Update Power bar
	local powerPercent = math.clamp((vehicleData.total_power or 0) / 1000, 0, 1)
	local powerPercentText = math.floor((vehicleData.total_power or 0) / 10) .. "/100"
	updateStatBar("Power", powerPercent, powerPercentText)

	-- Update Acceleration bar
	local accelPercent = math.clamp((vehicleData.total_acceleration or 0) / 1000, 0, 1)
	local accelPercentText = math.floor((vehicleData.total_acceleration or 0) / 10) .. "/100"
	updateStatBar("Acceleration", accelPercent, accelPercentText)

	-- Update Weight bar (inverse - lower weight is better)
	-- Weight ranges: 205 (best/lightest) to 280 (worst/heaviest)
	local MIN_WEIGHT = 205
	local MAX_WEIGHT = 280
	local currentWeight = vehicleData.total_weight or MAX_WEIGHT
	local weightPercent = math.clamp((MAX_WEIGHT - currentWeight) / (MAX_WEIGHT - MIN_WEIGHT), 0, 1)
	local weightPercentValue = math.floor(((MAX_WEIGHT - currentWeight) / (MAX_WEIGHT - MIN_WEIGHT)) * 100)
	local weightPercentText = weightPercentValue .. "/100"
	updateStatBar("Weight", weightPercent, weightPercentText)
end

-- Clear the CarSign billboard (hide all frames)
function Utils.clearCarSignBillboard(garage, padNumber)
	if not garage or not padNumber then
		warn("[Utils] clearCarSignBillboard: missing required parameters")
		return
	end

	-- Find the CarSign for this pad number
	local carSign = garage:FindFirstChild("CarSign" .. tostring(padNumber), true)
	if not carSign then
		-- It's okay if the CarSign doesn't exist (might not be set up yet)
		return
	end

	-- Find the SurfaceGui named "Vehicle"
	local surfaceGui = Utils.findDescendantByName(carSign, "Vehicle")
	if not surfaceGui then
		return
	end

	-- Hide all frames
	local frames = {"Name", "Level", "Speed", "Power", "Acceleration", "Weight"}
	for _, frameName in ipairs(frames) do
		local frame = surfaceGui:FindFirstChild(frameName)
		if frame then
			frame.Visible = false
		end
	end
end

-- Apply custom color to Body and Wheel parts of a model (for ViewportFrame thumbnails)
function Utils.applyViewportColor(model, colorString)
	if not colorString or colorString == "" then
		return
	end

	local color = Utils.parseColorString(colorString)
	if not color then
		return
	end

	-- Find and color all Body and Wheel parts
	for _, descendant in ipairs(model:GetDescendants()) do
		if (descendant.Name == "Body" or descendant.Name == "Wheel") and descendant:IsA("BasePart") then
			descendant.Color = color
		end
	end
end

-- ============================================
-- Vehicle Name Generator
-- Total combinations: 1,092 unique racing-themed names
-- ============================================

Utils.VehicleNameGenerator = {}

-- Pattern 1: Speed Adjective + Powerful Noun (18 × 18 = 324)
local speedAdjectives = {
	"Blazing", "Swift", "Rapid", "Turbo", "Sonic", "Lightning",
	"Nitro", "Hyper", "Ultra", "Mega", "Quantum", "Atomic",
	"Cosmic", "Stellar", "Primal", "Apex", "Savage", "Extreme"
}

local powerfulNouns = {
	"Phoenix", "Thunder", "Vortex", "Falcon", "Tempest", "Fury",
	"Phantom", "Nova", "Dragon", "Storm", "Bolt", "Titan",
	"Reaper", "Shadow", "Wraith", "Demon", "Specter", "Beast"
}

-- Pattern 2: Fast Animal + Racing Action (16 × 16 = 256)
local fastAnimals = {
	"Cheetah", "Falcon", "Viper", "Cobra", "Hawk", "Jaguar",
	"Panther", "Eagle", "Raptor", "Stallion", "Leopard", "Wolf",
	"Tiger", "Lynx", "Mongoose", "Roadrunner"
}

local racingActions = {
	"Sprint", "Drift", "Rush", "Blitz", "Surge", "Boost",
	"Charge", "Turbo", "Flash", "Strike", "Dash", "Burn",
	"Nitro", "Launch", "Overdrive", "Redline"
}

-- Pattern 3: Metal/Material + Speed Term (16 × 16 = 256)
local metals = {
	"Steel", "Chrome", "Carbon", "Titanium", "Alloy", "Iron",
	"Plasma", "Neon", "Silver", "Gold", "Cobalt", "Mercury",
	"Uranium", "Diamond", "Crystal", "Obsidian"
}

local speedTerms = {
	"Velocity", "Flash", "Surge", "Rush", "Blitz", "Streak",
	"Bolt", "Thrust", "Pulse", "Wave", "Force", "Impact",
	"Momentum", "Acceleration", "Drive", "Power"
}

-- Pattern 4: Racing Term + Natural Phenomenon (16 × 16 = 256)
local racingTerms = {
	"Drift", "Turbo", "Nitro", "Apex", "Burnout", "Slipstream",
	"Redline", "Overdrive", "Boost", "Torque", "Piston", "Throttle",
	"Clutch", "Gearshift", "Downforce", "Traction"
}

local naturalPhenomena = {
	"Storm", "Blaze", "Eclipse", "Cyclone", "Inferno", "Tornado",
	"Comet", "Thunder", "Lightning", "Hurricane", "Meteor", "Tsunami",
	"Avalanche", "Earthquake", "Supernova", "Wildfire"
}

-- Generate a random racing-themed vehicle name
-- pattern: "adjective_noun" | "animal_action" | "metal_speed" | "racing_phenomenon" | "random"
function Utils.VehicleNameGenerator.Generate(pattern)
	pattern = pattern or "random"

	if pattern == "random" then
		-- Pick a random pattern
		local patterns = {"adjective_noun", "animal_action", "metal_speed", "racing_phenomenon"}
		pattern = patterns[math.random(#patterns)]
	end

	if pattern == "adjective_noun" then
		local adj = speedAdjectives[math.random(#speedAdjectives)]
		local noun = powerfulNouns[math.random(#powerfulNouns)]
		return adj .. " " .. noun
	elseif pattern == "animal_action" then
		local animal = fastAnimals[math.random(#fastAnimals)]
		local action = racingActions[math.random(#racingActions)]
		return animal .. " " .. action
	elseif pattern == "metal_speed" then
		local metal = metals[math.random(#metals)]
		local speed = speedTerms[math.random(#speedTerms)]
		return metal .. " " .. speed
	elseif pattern == "racing_phenomenon" then
		local racing = racingTerms[math.random(#racingTerms)]
		local phenomenon = naturalPhenomena[math.random(#naturalPhenomena)]
		return racing .. " " .. phenomenon
	else
		-- Fallback to adjective_noun
		local adj = speedAdjectives[math.random(#speedAdjectives)]
		local noun = powerfulNouns[math.random(#powerfulNouns)]
		return adj .. " " .. noun
	end
end

return Utils
