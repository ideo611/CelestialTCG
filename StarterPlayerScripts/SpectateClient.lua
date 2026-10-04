--[[
	SpectateClient (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > SpectateClient

	Draws the TVs above the play tables and the full-screen spectator view.
	  - TVs show the live board of their table (only drawn when you're
	    nearby, so far-away TVs cost nothing). Click WATCH on a TV, or stand
	    under it and press F, to watch full screen.
	  - "Live games" (left side, under the binder buttons) lists every
	    match going on in the shop.
	  - The spectator view shows both playmats, the board, both Commanders,
	    how many cards each player holds, the series score and a
	    play-by-play. Click any card to look at it up close.
	  - Sitting down at a table closes the spectator view by itself.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local okMats, Playmats = pcall(function()
	return require(ReplicatedStorage:WaitForChild("Playmats", 10))
end)
if not okMats then
	Playmats = nil
end

local remotes = ReplicatedStorage:WaitForChild("SpectateRemotes")
local tableUpdate = remotes:WaitForChild("TableUpdate")
local request = remotes:WaitForChild("SpectateRequest")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(185, 178, 210)
local GOLD = Color3.fromRGB(240, 205, 120)
local RED = Color3.fromRGB(255, 80, 90)
local PANEL = Color3.fromRGB(34, 30, 52)
local DARK = Color3.fromRGB(12, 11, 20)
local GREY = Color3.fromRGB(80, 80, 92)
local GREEN = Color3.fromRGB(60, 140, 90)
local CARD_ASPECT = 1060 / 1484
local TV_DRAW_DISTANCE = 110 -- studs; TVs further away than this aren't drawn

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function label(parent, name, position, size, text, maxSize, extra)
	local l = make("TextLabel", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextWrapped = true,
	}, parent)
	for key, value in pairs(extra or {}) do
		l[key] = value
	end
	make("UITextSizeConstraint", { MaxTextSize = maxSize or 20, MinTextSize = 6 }, l)
	return l
end

local function button(parent, name, text, position, size, color, maxSize)
	local b = make("TextButton", {
		Name = name,
		Text = text,
		Position = position,
		Size = size,
		BackgroundColor3 = color or PANEL,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		AutoButtonColor = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	make("UITextSizeConstraint", { MaxTextSize = maxSize or 18, MinTextSize = 6 }, b)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, b)
	return b
end

local function corner(parent, radius)
	return make("UICorner", { CornerRadius = radius or UDim.new(0, 8) }, parent)
end

local function clear(parent)
	for _, child in ipairs(parent:GetChildren()) do
		child:Destroy()
	end
end

local function sorted(map)
	local keys = {}
	for key in pairs(map) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function seatOf(snap, key)
	return snap and snap.Seats and snap.Seats[key]
end

local function matchTitle(snap)
	local a, b = seatOf(snap, "Seat1"), seatOf(snap, "Seat2")
	if not (a and b) then
		return "Table " .. tostring(snap and snap.Table or "?")
	end
	return a.Name .. " vs " .. b.Name
end

local function seriesText(snap)
	if not snap.BestOf or snap.BestOf <= 1 then
		return nil
	end
	local a, b = seatOf(snap, "Seat1"), seatOf(snap, "Seat2")
	return ("Best of %d  |  Game %d  |  %d - %d"):format(snap.BestOf, snap.Game or 1, a.Wins or 0, b.Wins or 0)
end

-- A card slot: draws the card (or an empty outline) inside a holder that
-- keeps card proportions. onClick(cardId, finish) is optional.
local function cardSlot(parent, name, position, size, cardId, options, onClick)
	local holder = make("Frame", {
		Name = name,
		Position = position,
		Size = size,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, parent)
	local slot = make(onClick and "TextButton" or "Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, holder)
	if onClick then
		slot.Text = ""
		slot.AutoButtonColor = false
	end
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, slot)
	if cardId and CardDatabase.GetCard(cardId) then
		CardVisuals.Draw(slot, cardId, options or {})
		if onClick then
			slot.Activated:Connect(function()
				onClick(cardId, options and options.Finish)
			end)
		end
	else
		slot.BackgroundColor3 = WHITE
		slot.BackgroundTransparency = 0.94
		corner(slot, UDim.new(0.06, 0))
		make("UIStroke", { Color = WHITE, Transparency = 0.75, Thickness = 1 }, slot)
	end
	return slot
end

local function faceDown(parent, name, position, size, text)
	local holder = make("Frame", {
		Name = name,
		Position = position,
		Size = size,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, parent)
	local slot = make("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, holder)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, slot)
	CardVisuals.DrawFaceDown(slot, text or "")
	return slot
end

local function unitOptions(seat, unit)
	return {
		Unit = { Power = unit.Power, HP = unit.HP, MaxHP = unit.MaxHP, Shield = unit.Shield, CanAttack = false },
		Finish = seat.Finishes and seat.Finishes[unit.CardId] or nil,
		HideCost = true,
	}
end

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local snapshots = {}      -- [table index] = latest snapshot
local watchingIndex = nil -- the table shown full screen
local inMatch = false     -- you're seated at a table yourself
local renderView, renderList, refreshHud
local tvDirty = {}        -- [table index] = true when its TV needs redrawing

local function liveIndexes()
	local list = {}
	for index, snap in pairs(snapshots) do
		if snap.Live then
			table.insert(list, index)
		end
	end
	table.sort(list)
	return list
end

---------------------------------------------------------------------
-- Inspect (click a card in the spectator view)
---------------------------------------------------------------------
local inspectGui = make("ScreenGui", {
	Name = "SpectateInspectGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 12,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
}, playerGui)
local inspectShade = make("TextButton", {
	Name = "Shade",
	Text = "",
	AutoButtonColor = false,
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
}, inspectGui)
inspectShade.Activated:Connect(function()
	inspectGui.Enabled = false
end)

local function inspect(cardId, finish)
	for _, child in ipairs(inspectGui:GetChildren()) do
		if child ~= inspectShade then
			child:Destroy()
		end
	end
	cardSlot(inspectGui, "InspectCard", UDim2.fromScale(0.5, 0.46), UDim2.fromScale(0.5, 0.74), cardId,
		{ Finish = finish })
	local card = CardDatabase.GetCard(cardId)
	local finishName = finish and CardVisuals.FinishNames[finish] or "Standard"
	label(inspectGui, "InspectInfo", UDim2.fromScale(0.2, 0.85), UDim2.fromScale(0.6, 0.05),
		("%s  |  %s  |  %s"):format(card and card.Name or cardId, card and card.Rarity or "", finishName), 22,
		{ TextColor3 = GOLD })
	label(inspectGui, "InspectHint", UDim2.fromScale(0.3, 0.91), UDim2.fromScale(0.4, 0.035),
		"Click anywhere to close", 16, { TextColor3 = MUTED, Font = Enum.Font.Gotham })
	inspectGui.Enabled = true
end

---------------------------------------------------------------------
-- The full-screen spectator view
---------------------------------------------------------------------
local viewGui = make("ScreenGui", {
	Name = "SpectateGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 8,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
}, playerGui)
local viewRoot = make("Frame", {
	Name = "Root",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = DARK,
}, viewGui)

local function stopWatching()
	watchingIndex = nil
	viewGui.Enabled = false
	inspectGui.Enabled = false
	task.spawn(function()
		pcall(function()
			request:InvokeServer("Stop")
		end)
	end)
	refreshHud()
end

local function watch(index)
	if not snapshots[index] then
		return
	end
	watchingIndex = index
	viewGui.Enabled = true
	task.spawn(function()
		pcall(function()
			request:InvokeServer("Watch", index)
		end)
	end)
	renderView()
	refreshHud()
end

local function nextTable()
	local live = liveIndexes()
	if #live == 0 then
		return
	end
	local pick = live[1]
	for _, index in ipairs(live) do
		if watchingIndex and index > watchingIndex then
			pick = index
			break
		end
	end
	watch(pick)
end

-- One player's half of the board. top = true for Seat 2 (drawn upside the line)
local function drawHalf(parent, snap, key, top)
	local seat = seatOf(snap, key)
	local half = make("Frame", {
		Name = key .. "Half",
		Position = UDim2.fromScale(0, top and 0 or 0.5),
		Size = UDim2.fromScale(1, 0.5),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
	}, parent)
	local mat = make("Frame", { Name = "Mat", Size = UDim2.fromScale(1, 1) }, half)
	if Playmats then
		pcall(Playmats.Draw, mat, seat.Mat, 0.35)
	else
		mat.BackgroundColor3 = top and Color3.fromRGB(26, 20, 44) or Color3.fromRGB(16, 22, 44)
	end

	local isTurn = snap.Current == key and not snap.Winner
	local isWinner = snap.Winner == key

	-- Info column: Commander, name, HP, energy, cards in hand
	local infoY = top and 0.17 or 0.04
	local info = make("Frame", {
		Name = "Info",
		Position = UDim2.fromScale(0.01, infoY),
		Size = UDim2.fromScale(0.17, 0.79),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
	}, half)
	corner(info)
	if isTurn or isWinner then
		make("UIStroke", { Color = GOLD, Thickness = 2 }, info)
	end
	label(info, "Name", UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.12), seat.Name, 22,
		{ TextColor3 = (isTurn or isWinner) and GOLD or WHITE })
	cardSlot(info, "Commander", UDim2.fromScale(0.3, 0.5), UDim2.fromScale(0.52, 0.66), seat.Commander,
		{ HideCost = true, Finish = seat.Finishes and seat.Finishes[seat.Commander] or nil }, inspect)
	local hpColor = (seat.HP or 0) <= 5 and RED or WHITE
	label(info, "HP", UDim2.fromScale(0.6, 0.2), UDim2.fromScale(0.38, 0.2), tostring(math.max(0, seat.HP or 0)), 40,
		{ TextColor3 = hpColor })
	label(info, "HPLabel", UDim2.fromScale(0.6, 0.39), UDim2.fromScale(0.38, 0.07), "HP", 14,
		{ TextColor3 = MUTED })
	label(info, "Energy", UDim2.fromScale(0.6, 0.5), UDim2.fromScale(0.38, 0.1),
		("%d/%d"):format(seat.Energy or 0, seat.MaxEnergy or 0), 22, { TextColor3 = Color3.fromRGB(140, 200, 255) })
	label(info, "EnergyLabel", UDim2.fromScale(0.6, 0.6), UDim2.fromScale(0.38, 0.07), "Energy", 14,
		{ TextColor3 = MUTED })
	label(info, "Cards", UDim2.fromScale(0.05, 0.85), UDim2.fromScale(0.9, 0.11),
		("Hand %d  |  Deck %d"):format(seat.Hand or 0, seat.Deck or 0), 16, { TextColor3 = MUTED })

	-- Lanes (closest to the middle line)
	local laneY = top and 0.6 or 0.4
	for lane = 1, 3 do
		local unit = seat.Lanes and seat.Lanes["L" .. lane]
		local x = 0.19 + (lane - 0.5) * (0.47 / 3)
		if unit then
			cardSlot(half, "Lane" .. lane, UDim2.fromScale(x, laneY), UDim2.fromScale(0.15, 0.74), unit.CardId,
				unitOptions(seat, unit), inspect)
		else
			cardSlot(half, "Lane" .. lane, UDim2.fromScale(x, laneY), UDim2.fromScale(0.15, 0.74), nil)
		end
	end

	-- Star Gate: face down until the Celestial is summoned
	local gate = seat.Gate or {}
	local gateY = laneY
	label(half, "GateLabel", UDim2.fromScale(0.68, top and 0.22 or 0.7), UDim2.fromScale(0.1, 0.08), "STAR GATE", 14,
		{ TextColor3 = MUTED })
	if gate.OnBoard then
		local slot = cardSlot(half, "Gate", UDim2.fromScale(0.73, gateY), UDim2.fromScale(0.09, 0.56), nil)
		label(slot, "Empty", UDim2.fromScale(0.05, 0.4), UDim2.fromScale(0.9, 0.2), "Summoned", 14,
			{ TextColor3 = MUTED })
	elseif gate.Revealed and gate.CardId then
		cardSlot(half, "Gate", UDim2.fromScale(0.73, gateY), UDim2.fromScale(0.09, 0.56), gate.CardId,
			{ Finish = seat.Finishes and seat.Finishes[gate.CardId] or nil }, inspect)
	else
		faceDown(half, "Gate", UDim2.fromScale(0.73, gateY), UDim2.fromScale(0.09, 0.56), "?")
	end
	return half
end

renderView = function()
	if not watchingIndex then
		return
	end
	clear(viewRoot)
	local snap = snapshots[watchingIndex]

	if not snap or not snap.Live or not snap.Seats then
		local waiting = make("Frame", { Name = "Waiting", Size = UDim2.fromScale(1, 1), BackgroundColor3 = DARK }, viewRoot)
		label(waiting, "Title", UDim2.fromScale(0.2, 0.36), UDim2.fromScale(0.6, 0.08),
			"Table " .. watchingIndex .. " is open", 40, { TextColor3 = GOLD })
		label(waiting, "Hint", UDim2.fromScale(0.2, 0.45), UDim2.fromScale(0.6, 0.05),
			"The next match here will show up as soon as it starts.", 22, { TextColor3 = MUTED, Font = Enum.Font.Gotham })
		local other = #liveIndexes() > 0
		if other then
			button(waiting, "NextTable", "Watch another table", UDim2.fromScale(0.36, 0.55), UDim2.fromScale(0.13, 0.06), GREEN)
				.Activated:Connect(nextTable)
		end
		button(waiting, "StopWatching", "Stop watching", UDim2.fromScale(other and 0.51 or 0.435, 0.55),
			UDim2.fromScale(0.13, 0.06), GREY).Activated:Connect(stopWatching)
		return
	end

	drawHalf(viewRoot, snap, "Seat2", true)
	drawHalf(viewRoot, snap, "Seat1", false)
	make("Frame", {
		Name = "MiddleLine",
		Position = UDim2.new(0.19, 0, 0.5, -1),
		Size = UDim2.new(0.47, 0, 0, 2),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
	}, viewRoot)

	-- Whose turn, in the middle of the board
	local current = seatOf(snap, snap.Current or "")
	local turnText = snap.Winner and (seatOf(snap, snap.Winner).Name .. " wins!")
		or (current and (current.Name .. "'s turn") or "")
	if not snap.Winner then
		local pill = make("Frame", {
			Name = "TurnPill",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.425, 0.5),
			Size = UDim2.fromScale(0.2, 0.045),
			BackgroundColor3 = PANEL,
		}, viewRoot)
		corner(pill, UDim.new(0.5, 0))
		label(pill, "TurnText", UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.8),
			turnText .. (snap.Turn and ("   (turn " .. snap.Turn .. ")") or ""), 20)
	end

	-- Top bar: what you're watching + buttons
	local bar = make("Frame", {
		Name = "TopBar",
		Position = UDim2.fromScale(0.19, 0),
		Size = UDim2.fromScale(0.6, 0.075),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
	}, viewRoot)
	corner(bar)
	label(bar, "Watching", UDim2.fromScale(0.02, 0.06), UDim2.fromScale(0.58, 0.5),
		("WATCHING TABLE %d   %s"):format(snap.Table, matchTitle(snap)), 20,
		{ TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	label(bar, "Series", UDim2.fromScale(0.02, 0.55), UDim2.fromScale(0.58, 0.38),
		(seriesText(snap) or "Best of 1") .. ("   |   %d watching"):format(snap.Watchers or 0), 15,
		{ TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = MUTED, Font = Enum.Font.Gotham })
	if #liveIndexes() > 1 then
		button(bar, "NextTable", "Next table", UDim2.fromScale(0.62, 0.15), UDim2.fromScale(0.17, 0.7), GREEN)
			.Activated:Connect(nextTable)
	end
	button(bar, "StopWatching", "Stop watching", UDim2.fromScale(0.81, 0.15), UDim2.fromScale(0.17, 0.7), GREY)
		.Activated:Connect(stopWatching)

	-- Play-by-play
	local feed = make("Frame", {
		Name = "PlayByPlay",
		Position = UDim2.fromScale(0.8, 0.09),
		Size = UDim2.fromScale(0.19, 0.82),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
	}, viewRoot)
	corner(feed)
	label(feed, "FeedTitle", UDim2.fromScale(0.06, 0.015), UDim2.fromScale(0.88, 0.05), "PLAY-BY-PLAY", 16,
		{ TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
	local lines = snap.Ticker or {}
	local shown = 0
	for i = #lines, 1, -1 do
		local y = 0.08 + shown * 0.105
		local newest = shown == 0
		label(feed, "Line" .. shown, UDim2.fromScale(0.06, y), UDim2.fromScale(0.88, 0.095), lines[i], 17, {
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Font = newest and Enum.Font.GothamBold or Enum.Font.Gotham,
			TextColor3 = newest and WHITE or MUTED,
		})
		shown = shown + 1
	end

	if snap.Winner then
		local banner = make("Frame", {
			Name = "WinnerBanner",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.425, 0.5),
			Size = UDim2.fromScale(0.42, 0.13),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.2,
		}, viewRoot)
		corner(banner)
		make("UIStroke", { Color = GOLD, Thickness = 2 }, banner)
		label(banner, "WinnerText", UDim2.fromScale(0.05, 0.1), UDim2.fromScale(0.9, 0.55),
			seatOf(snap, snap.Winner).Name .. " wins!", 44, { TextColor3 = GOLD })
		label(banner, "WinnerHint", UDim2.fromScale(0.05, 0.66), UDim2.fromScale(0.9, 0.26),
			"Stay to watch the next game, or press Next table.", 18, { TextColor3 = MUTED, Font = Enum.Font.Gotham })
	end
end

---------------------------------------------------------------------
-- "Live games" button and list
---------------------------------------------------------------------
local hud = make("ScreenGui", { Name = "SpectateButtonGui", ResetOnSpawn = false, DisplayOrder = 1 }, playerGui)
local liveButton = button(hud, "LiveGames", "Live games", UDim2.new(0, 10, 0.45, 146), UDim2.fromOffset(120, 34), RED)
local listFrame = make("Frame", {
	Name = "LiveList",
	Position = UDim2.new(0, 136, 0.45, 146),
	Size = UDim2.fromOffset(330, 60),
	BackgroundColor3 = PANEL,
	Visible = false,
}, hud)
corner(listFrame)

renderList = function()
	clear(listFrame)
	corner(listFrame)
	local live = liveIndexes()
	if #live == 0 then
		listFrame.Size = UDim2.fromOffset(330, 44)
		label(listFrame, "None", UDim2.fromOffset(10, 6), UDim2.new(1, -20, 0, 32), "No matches right now.", 16,
			{ TextColor3 = MUTED, Font = Enum.Font.Gotham })
		return
	end
	listFrame.Size = UDim2.fromOffset(330, 10 + #live * 42)
	for i, index in ipairs(live) do
		local snap = snapshots[index]
		local y = 6 + (i - 1) * 42
		label(listFrame, "Match" .. index, UDim2.fromOffset(10, y), UDim2.new(1, -110, 0, 36),
			("Table %d: %s"):format(index, matchTitle(snap)), 16, { TextXAlignment = Enum.TextXAlignment.Left })
		button(listFrame, "Watch" .. index, "Watch", UDim2.new(1, -92, 0, y + 2), UDim2.fromOffset(82, 32), GREEN)
			.Activated:Connect(function()
				listFrame.Visible = false
				watch(index)
			end)
	end
end

refreshHud = function()
	local count = #liveIndexes()
	liveButton.Text = count > 0 and ("Live games (%d)"):format(count) or "Live games"
	liveButton.BackgroundColor3 = count > 0 and RED or GREY
	hud.Enabled = not inMatch and watchingIndex == nil
	if listFrame.Visible then
		renderList()
	end
end

liveButton.Activated:Connect(function()
	listFrame.Visible = not listFrame.Visible
	if listFrame.Visible then
		renderList()
	end
end)

---------------------------------------------------------------------
-- TVs above the tables
---------------------------------------------------------------------
local tvFolder = workspace:WaitForChild("SpectateTVs")
local tvGuis = {} -- [table index] = { Screen = part, Guis = { SurfaceGui, SurfaceGui }, Drawn = bool }

local function drawTv(container, index)
	clear(container)
	local snap = snapshots[index] or { Table = index, Live = false }
	local live = snap.Live and snap.Seats ~= nil

	-- Header
	local header = make("Frame", {
		Name = "Header",
		Size = UDim2.fromScale(1, 0.13),
		BackgroundColor3 = Color3.fromRGB(26, 22, 42),
		BorderSizePixel = 0,
	}, container)
	label(header, "TableName", UDim2.fromScale(0.02, 0.1), UDim2.fromScale(0.2, 0.8), "TABLE " .. index, 26,
		{ TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	label(header, "Status", UDim2.fromScale(0.23, 0.1), UDim2.fromScale(0.14, 0.8), live and "LIVE" or "OPEN", 24,
		{ TextColor3 = live and RED or MUTED })
	label(header, "Watchers", UDim2.fromScale(0.62, 0.1), UDim2.fromScale(0.36, 0.8),
		(snap.Watchers or 0) > 0 and ((snap.Watchers or 0) .. " watching") or "", 20,
		{ TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = MUTED, Font = Enum.Font.Gotham })

	if not live then
		label(container, "Open", UDim2.fromScale(0.1, 0.36), UDim2.fromScale(0.8, 0.16), "Table open", 48,
			{ TextColor3 = WHITE })
		label(container, "OpenHint", UDim2.fromScale(0.1, 0.54), UDim2.fromScale(0.8, 0.1),
			"Sit down to play a friend, or Practice vs Bot", 24, { TextColor3 = MUTED, Font = Enum.Font.Gotham })
		return
	end

	for _, key in ipairs({ "Seat2", "Seat1" }) do
		local seat = seatOf(snap, key)
		local top = key == "Seat2"
		local y = top and 0.15 or 0.51
		local isTurn = snap.Current == key and not snap.Winner
		local isWinner = snap.Winner == key
		local row = make("Frame", {
			Name = key .. "Row",
			Position = UDim2.fromScale(0, y),
			Size = UDim2.fromScale(1, 0.34),
			BackgroundTransparency = 1,
		}, container)
		label(row, "Name", UDim2.fromScale(0.02, 0.05), UDim2.fromScale(0.27, 0.3), seat.Name, 24, {
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = (isTurn or isWinner) and GOLD or WHITE,
		})
		label(row, "HP", UDim2.fromScale(0.02, 0.36), UDim2.fromScale(0.27, 0.34), math.max(0, seat.HP or 0) .. " HP", 34, {
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = (seat.HP or 0) <= 5 and RED or WHITE,
		})
		label(row, "Hand", UDim2.fromScale(0.02, 0.72), UDim2.fromScale(0.27, 0.22),
			isTurn and ("Their turn  |  Hand " .. (seat.Hand or 0)) or ("Hand " .. (seat.Hand or 0)), 18,
			{ TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = isTurn and GOLD or MUTED, Font = Enum.Font.Gotham })
		for lane = 1, 3 do
			local unit = seat.Lanes and seat.Lanes["L" .. lane]
			local x = 0.32 + (lane - 0.5) * 0.18
			cardSlot(row, "Lane" .. lane, UDim2.fromScale(x, 0.5), UDim2.fromScale(0.16, 0.96),
				unit and unit.CardId, unit and unitOptions(seat, unit) or nil)
		end
		cardSlot(row, "Commander", UDim2.fromScale(0.91, 0.5), UDim2.fromScale(0.13, 0.9), seat.Commander,
			{ HideCost = true, Finish = seat.Finishes and seat.Finishes[seat.Commander] or nil })
	end

	-- Footer: newest play-by-play line and the Watch button
	local footer = make("Frame", {
		Name = "Footer",
		Position = UDim2.fromScale(0, 0.87),
		Size = UDim2.fromScale(1, 0.13),
		BackgroundColor3 = Color3.fromRGB(26, 22, 42),
		BorderSizePixel = 0,
	}, container)
	local lines = snap.Ticker or {}
	local newest = snap.Winner and (seatOf(snap, snap.Winner).Name .. " wins!") or lines[#lines] or ""
	label(footer, "Ticker", UDim2.fromScale(0.02, 0.1), UDim2.fromScale(0.72, 0.8), newest, 22, {
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = snap.Winner and GOLD or WHITE,
		Font = Enum.Font.Gotham,
	})
	local watchButton = button(footer, "Watch", "WATCH", UDim2.fromScale(0.78, 0.12), UDim2.fromScale(0.2, 0.76), RED, 24)
	watchButton.Activated:Connect(function()
		watch(index)
	end)
end

local function tvFor(screen)
	local index = screen:GetAttribute("TableIndex")
	if type(index) ~= "number" then
		return nil
	end
	local tv = tvGuis[index]
	if tv and tv.Screen == screen then
		return tv
	end
	tv = { Screen = screen, Guis = {}, Drawn = false }
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = make("SurfaceGui", {
			Name = ("SpectateTV%d_%s"):format(index, face.Name),
			Adornee = screen,
			Face = face,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
			PixelsPerStud = 60,
			LightInfluence = 0,
			Brightness = 1.2,
			MaxDistance = TV_DRAW_DISTANCE + 20,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			ResetOnSpawn = false,
			ClipsDescendants = true,
		}, playerGui)
		local container = make("Frame", {
			Name = "Board",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = DARK,
			BorderSizePixel = 0,
		}, gui)
		table.insert(tv.Guis, { Gui = gui, Container = container })
	end
	tvGuis[index] = tv
	return tv
end

local function updateTvs()
	local camera = workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	for _, model in ipairs(tvFolder:GetChildren()) do
		local screen = model:FindFirstChild("Screen")
		local tv = screen and tvFor(screen)
		if tv then
			local index = screen:GetAttribute("TableIndex")
			local near = eye and (eye - screen.Position).Magnitude <= TV_DRAW_DISTANCE
			if near and (not tv.Drawn or tvDirty[index]) then
				for _, face in ipairs(tv.Guis) do
					drawTv(face.Container, index)
				end
				tv.Drawn = true
				tvDirty[index] = nil
			elseif not near and tv.Drawn then
				for _, face in ipairs(tv.Guis) do
					clear(face.Container)
				end
				tv.Drawn = false
			end
		end
	end
end

---------------------------------------------------------------------
-- Updates from the server
---------------------------------------------------------------------
local function setSnapshot(snap)
	if type(snap) ~= "table" or type(snap.Table) ~= "number" then
		return
	end
	snapshots[snap.Table] = snap
	tvDirty[snap.Table] = true
	if watchingIndex == snap.Table then
		renderView()
	end
	refreshHud()
end

tableUpdate.OnClientEvent:Connect(function(message)
	if type(message) ~= "table" then
		return
	end
	if message.Kind == "Table" then
		setSnapshot(message.Snapshot)
		updateTvs()
	elseif message.Kind == "OpenWatch" and type(message.Table) == "number" then
		watch(message.Table)
	end
end)

-- Your own match closes the spectator view
task.spawn(function()
	local battleUpdate = ReplicatedStorage:WaitForChild("BattleRemotes"):WaitForChild("BattleUpdate")
	battleUpdate.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.Kind == "Closed" then
			inMatch = false
		elseif payload.Kind == "Match" or payload.Kind == "Waiting" or payload.Kind == "Series" then
			inMatch = true
			if watchingIndex then
				stopWatching()
			end
		end
		refreshHud()
	end)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace then
		if inspectGui.Enabled then
			inspectGui.Enabled = false
		elseif watchingIndex then
			stopWatching()
		end
	end
end)

-- Catch up on matches already going when you join
task.spawn(function()
	local ok, all = pcall(function()
		return request:InvokeServer("All")
	end)
	if ok and type(all) == "table" then
		for _, key in ipairs(sorted(all)) do
			setSnapshot(all[key])
		end
	end
	updateTvs()
end)

refreshHud()
while true do
	updateTvs()
	task.wait(0.5)
end
