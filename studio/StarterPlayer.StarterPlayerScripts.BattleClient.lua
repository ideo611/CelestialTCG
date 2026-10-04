--[[
	BattleClient (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > BattleClient

	Draws the battle screen and sends your clicks to the server.
	The board is split in two: your playmat on your half (bottom), your
	opponent's playmat on theirs (top).

	How to play:
	  - Units: click a card in your hand, then one of your empty lanes.
	  - Targeted spells: click the spell, then the unit to hit or buff.
	  - Star Gate (left side): click it, then an empty lane to summon your Celestial.
	    The number in its corner is the current summon cost (red = it went up).
	  - Ability: click it, then one of your Solar units.
	  - End Turn: your units attack the lanes across, then it's their turn.
	  - From round 9 the Cosmic Storm hits both Commanders a little harder each turn.
	  - Sounds: each animation plays a sound. Paste the uploaded sound IDs into
	    SOUND_IDS below. The sound button in the match log turns them on or off.
	  - Animations: each update from the server plays out step by step (cards
	    flying in, attacks, damage numbers), then the board settles. The speed
	    button in the match log switches Normal / Fast / Off.
	  - Best of 1, 3 or 5: picked on the deck screen (against a player you both
	    vote, and the shorter vote wins). The series score shows top right.
	  - Inspect: right-click any card, or press Inspect and then click a card.
	    Clicking a unit on the board (with nothing selected) also inspects it.
	    Shows the card big, with its buffs and where they came from.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local Playmats = require(ReplicatedStorage:WaitForChild("Playmats"))
local remotes = ReplicatedStorage:WaitForChild("BattleRemotes")
local actionRemote = remotes:WaitForChild("BattleAction")
local updateRemote = remotes:WaitForChild("BattleUpdate")

local player = Players.LocalPlayer
local LANES = CardDatabase.Rules.Lanes

local FACTION_COLORS = CardVisuals.FactionColors
local WHITE = Color3.fromRGB(255, 255, 255)
local HIGHLIGHT = Color3.fromRGB(255, 230, 80)
local EMPTY_SLOT = Color3.fromRGB(34, 30, 56)
local PANEL = Color3.fromRGB(24, 20, 42)

---------------------------------------------------------------------
-- Small helpers for building the screen
---------------------------------------------------------------------
local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function label(parent, props)
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.55, -- a soft outline keeps text readable over playmat art
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Size = UDim2.fromScale(1, 1),
	}
	for key, value in pairs(props) do
		defaults[key] = value
	end
	return make("TextLabel", defaults, parent)
end

--[[ Buttons use the "button-plate" image: a silver plate the game tints to
	each button's color. 9-slice keeps the corners exactly as drawn and
	stretches only the straight edges, so one image fits every button size.
	The words are a label on top, so they can change (like "Ability (2)"). ]]
local BUTTON_PLATE = "rbxassetid://134304204813444"
local PLATE_SLICE = Rect.new(96, 96, 1440, 928) -- corners of the 1536 x 1024 plate image
local PLATE_CORNER = 96 -- source pixels in each corner piece
local PLATE_CORNER_SCREEN = 0.016 -- each corner is this much of the screen height

-- Tints (the plate is grey, so these are kept bright)
local TINT = {
	Default = Color3.fromRGB(175, 160, 255),
	Inspect = Color3.fromRGB(110, 215, 235),
	Ability = Color3.fromRGB(185, 150, 255),
	Spark = Color3.fromRGB(120, 190, 255),
	EndTurn = Color3.fromRGB(255, 120, 85),
	Grey = Color3.fromRGB(165, 165, 175),
	Off = Color3.fromRGB(105, 105, 115),
	Yes = Color3.fromRGB(255, 120, 85),
}

local plates = {}
local playClick = nil -- set once the sounds are loaded (further down)

local function button(parent, name, text, position, size, tint)
	local b = make("ImageButton", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Image = BUTTON_PLATE,
		ImageColor3 = tint or TINT.Default,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = PLATE_SLICE,
		SliceScale = 0.15,
		AutoButtonColor = true,
	}, parent)
	make("UICorner", { Name = "PlateCorner", CornerRadius = UDim.new(0, 5) }, b)
	make("TextLabel", {
		Name = "Label",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.6),
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		TextStrokeTransparency = 0.35,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = text,
	}, b)
	make("UITextSizeConstraint", { MaxTextSize = 34 }, b.Label)
	b.Activated:Connect(function()
		if playClick then
			playClick()
		end
	end)
	table.insert(plates, b)
	return b
end

local function setLabel(b, text)
	b.Label.Text = text
end

-- Grey and faded when it can't be used right now
local function setTint(b, tint, usable)
	b.ImageColor3 = usable == false and TINT.Off or tint
	b.Label.TextTransparency = usable == false and 0.35 or 0
end

local function clear(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name ~= "SlotShape" then
			child:Destroy()
		end
	end
end

local function setStroke(object, color, thickness)
	local stroke = object:FindFirstChild("Highlight")
	if not color then
		if stroke then
			stroke:Destroy()
		end
		return
	end
	if not stroke then
		stroke = make("UIStroke", { Name = "Highlight" }, object)
	end
	stroke.Color = color
	stroke.Thickness = thickness or 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
end

---------------------------------------------------------------------
-- Build the screen (once)
---------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "BattleGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	Enabled = false,
}, player:WaitForChild("PlayerGui"))

--[[ Layout (fractions of the screen):
	left      Commander + Star Gate for each side
	center    3 lanes per side (card-shaped slots)
	right     match log and buttons
	bottom    your hand ]]
local CARD_ASPECT = 1060 / 1484
local ENEMY_ROW = { 0.07, 0.255 } -- y, height
local MY_ROW = { 0.405, 0.255 }
local COMMANDER_X = 0.0105 -- left edge of the Commander column (0.115 wide)
local GATE_X = 0.1375      -- left edge of the Star Gate column (0.115 wide)
local LANE_X = { 0.265, 0.425, 0.585 } -- left edge of each lane column
local LANE_W = 0.155
local SPLIT_Y = 0.365 -- where the two playmats meet (between the rows)
local MAT_SHADE = 0.25 -- darkens the mats a little (the zones do most of the work)
-- Zone tiles (the uploaded "zone-tile" image, tinted to each mat's color).
-- The card sits inside the tile's border: these are how much of the tile's
-- width / height the border takes on each side.
local ZONE_TILE = "rbxassetid://91092773801634"
local ZONE_INSET_X = 0.07
local ZONE_INSET_Y = 0.05
local ZONE_EXTRA_Y = ENEMY_ROW[2] * ZONE_INSET_Y / (1 - 2 * ZONE_INSET_Y) -- how far a tile reaches past its card
local DASH_FAINT = 0.45 -- lane dashes: 0 = solid, 1 = invisible
local DASH_COUNT = 5 -- dashes between each pair of opposing lanes

-- The table: two playmats under everything else
local tableFrame = make("Frame", {
	Name = "Table",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(14, 11, 28),
	BorderSizePixel = 0,
	ZIndex = 1,
}, gui)
local enemyMat = make("Frame", {
	Name = "EnemyMat",
	Size = UDim2.fromScale(1, SPLIT_Y),
	BorderSizePixel = 0,
}, tableFrame)
local myMat = make("Frame", {
	Name = "MyMat",
	Position = UDim2.fromScale(0, SPLIT_Y),
	Size = UDim2.fromScale(1, 1 - SPLIT_Y),
	BorderSizePixel = 0,
}, tableFrame)
local centerLine = make("Frame", {
	Name = "CenterLine",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.fromScale(0, SPLIT_Y),
	Size = UDim2.new(1, 0, 0, 3),
	BackgroundColor3 = WHITE,
	BorderSizePixel = 0,
	ZIndex = 2,
}, tableFrame)

--[[ Printed zones, like a real playmat: a framed tile under each card
	spot, a faint dashed line joining each pair of opposing lanes
	(lane 1 fights lane 1), zone labels by the center line, and a tray behind your hand.
	They sit on the table layer, under the cards. ]]
local zoneTiles = { Self = {}, Enemy = {} }
local zoneStrokes = { Self = {}, Enemy = {} } -- the hand tray's edge
local zoneLabels = { Self = {}, Enemy = {} }
local laneDashes = {} -- list of { frame, t } where t = 0 near the enemy, 1 near you

-- A tile a bit bigger than the card box (x, y, w, h), same center
local function zone(name, side, x, y, w, h)
	local tile = make("ImageLabel", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x + w / 2, y + h / 2),
		Size = UDim2.fromScale(w * 2, h / (1 - 2 * ZONE_INSET_Y)), -- the height sets the size
		BackgroundTransparency = 1,
		Image = ZONE_TILE,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 4,
	}, tableFrame)
	make("UIAspectRatioConstraint", {
		AspectRatio = CARD_ASPECT * (1 - 2 * ZONE_INSET_Y) / (1 - 2 * ZONE_INSET_X),
	}, tile)
	table.insert(zoneTiles[side], tile)
	return tile
end

local function zoneLabel(side, text, x, w)
	-- Labels hug the center line: just under the enemy's zones, just over yours
	local enemy = side == "Enemy"
	local l = make("TextLabel", {
		Name = "ZoneLabel",
		AnchorPoint = Vector2.new(0, enemy and 0 or 1),
		Position = enemy and UDim2.fromScale(x, ENEMY_ROW[1] + ENEMY_ROW[2] + ZONE_EXTRA_Y + 0.002)
			or UDim2.fromScale(x, MY_ROW[1] - ZONE_EXTRA_Y - 0.002),
		Size = UDim2.fromScale(w, 0.018),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextTransparency = 0.2,
		TextStrokeTransparency = 0.6,
		Text = text,
		ZIndex = 5,
	}, tableFrame)
	table.insert(zoneLabels[side], l)
end

-- Dashed lines in the gap between each enemy lane and yours
local GAP_TOP = ENEMY_ROW[1] + ENEMY_ROW[2] + ZONE_EXTRA_Y
local GAP = MY_ROW[1] - ZONE_EXTRA_Y - GAP_TOP
for lane = 1, #LANE_X do
	local line = make("Frame", {
		Name = "LaneDashes_" .. lane,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(LANE_X[lane] + LANE_W / 2, 0, GAP_TOP, 3),
		Size = UDim2.new(0, 3, GAP, -6),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, tableFrame)
	local pieces = DASH_COUNT * 2 - 1
	for i = 1, DASH_COUNT do
		local dash = make("Frame", {
			Name = "Dash_" .. i,
			Position = UDim2.fromScale(0, (i - 1) * 2 / pieces),
			Size = UDim2.fromScale(1, 1 / pieces),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = DASH_FAINT,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, line)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dash)
		table.insert(laneDashes, { dash, (i - 1) / math.max(DASH_COUNT - 1, 1) })
	end
end

for _, side in ipairs({ "Enemy", "Self" }) do
	local row = side == "Enemy" and ENEMY_ROW or MY_ROW
	zone(side .. "CommanderZone", side, COMMANDER_X, row[1], 0.115, row[2])
	zone(side .. "GateZone", side, GATE_X, row[1], 0.115, row[2])
	for lane = 1, #LANE_X do
		zone(("%sLaneZone_%d"):format(side, lane), side, LANE_X[lane], row[1], LANE_W, row[2])
	end
	zoneLabel(side, "COMMANDER", COMMANDER_X, 0.115)
	zoneLabel(side, "STAR GATE", GATE_X, 0.115)
end

local handTray = make("Frame", {
	Name = "HandTray",
	Position = UDim2.fromScale(0.015, 0.73),
	Size = UDim2.fromScale(0.73, 0.265),
	BackgroundColor3 = Color3.fromRGB(8, 6, 16),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	ZIndex = 4,
}, tableFrame)
make("UICorner", { CornerRadius = UDim.new(0.06, 0) }, handTray)
table.insert(zoneStrokes.Self, make("UIStroke", {
	Name = "ZoneEdge",
	Thickness = 1.5,
	Transparency = 0.5,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
}, handTray))

-- Plate corners stay the same share of the screen on any device
local function updatePlates()
	local ok, height = pcall(function()
		return gui.AbsoluteSize.Y
	end)
	if not ok or type(height) ~= "number" or height <= 0 then
		return
	end
	local scale = height * PLATE_CORNER_SCREEN / PLATE_CORNER
	for _, b in ipairs(plates) do
		b.SliceScale = scale
		b.PlateCorner.CornerRadius = UDim.new(0, math.floor(PLATE_CORNER * scale * 0.3))
	end
end

local root = make("Frame", {
	Name = "Root",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 2,
}, gui)

local function showBoard(visible)
	root.Visible = visible
	tableFrame.Visible = visible
end

-- Lane edge colors come from each side's mat
local matAccent = { Self = Color3.fromRGB(120, 110, 200), Enemy = Color3.fromRGB(120, 110, 200) }
local shownMats = {}

local function drawMats(myId, enemyId)
	if shownMats.Self == myId and shownMats.Enemy == enemyId then
		return
	end
	shownMats.Self, shownMats.Enemy = myId, enemyId
	for _, pair in ipairs({ { myMat, myId, "Self" }, { enemyMat, enemyId, "Enemy" } }) do
		local frame, id, side = pair[1], pair[2], pair[3]
		for _, child in ipairs(frame:GetChildren()) do
			child:Destroy()
		end
		local mat = Playmats.Draw(frame, id, MAT_SHADE)
		matAccent[side] = mat.Accent
	end
	for _, child in ipairs(centerLine:GetChildren()) do
		child:Destroy()
	end
	make("UIGradient", {
		Name = "LineGlow",
		Color = ColorSequence.new(matAccent.Enemy, matAccent.Self),
	}, centerLine)
	-- Zones take their side's mat color; lane dashes fade from theirs to yours
	for side, strokes in pairs(zoneStrokes) do
		for _, stroke in ipairs(strokes) do
			stroke.Color = matAccent[side]
		end
		for _, tile in ipairs(zoneTiles[side]) do
			tile.ImageColor3 = matAccent[side]
		end
		for _, l in ipairs(zoneLabels[side]) do
			l.TextColor3 = matAccent[side]
		end
	end
	for _, entry in ipairs(laneDashes) do
		entry[1].BackgroundColor3 = matAccent.Enemy:Lerp(matAccent.Self, entry[2])
	end
end

-- A button shaped like a card, centered in the given box
local slotBase = {} -- [slot] = { X, Y, W, H } resting center and size (screen fractions)

local function cardSlot(name, x, y, w, h)
	local slot = make("TextButton", {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x + w / 2, y + h / 2),
		Size = UDim2.fromScale(w, h),
		BackgroundColor3 = EMPTY_SLOT,
	}, root)
	make("UIAspectRatioConstraint", { Name = "SlotShape", AspectRatio = CARD_ASPECT }, slot)
	slotBase[slot] = { X = x + w / 2, Y = y + h / 2, W = w, H = h }
	return slot
end

local opponentLabel = label(root, {
	Name = "OpponentInfo",
	Position = UDim2.fromScale(0.015, 0.008),
	Size = UDim2.fromScale(0.73, 0.047),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})

local statusLabel = label(root, {
	Name = "Status",
	-- Right above your hand, where your eyes already are
	Position = UDim2.fromScale(0.40, 0.683),
	Size = UDim2.fromScale(0.345, 0.04),
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = HIGHLIGHT,
	TextStrokeTransparency = 0.2,
	Text = "",
})

-- Commanders and Star Gates (left)
local enemyCommander = cardSlot("EnemyCommander", COMMANDER_X, ENEMY_ROW[1], 0.115, ENEMY_ROW[2])
local enemyGate = cardSlot("EnemyStarGate", GATE_X, ENEMY_ROW[1], 0.115, ENEMY_ROW[2])
local myCommander = cardSlot("MyCommander", COMMANDER_X, MY_ROW[1], 0.115, MY_ROW[2])
myCommander.AutoButtonColor = true
local myGate = cardSlot("StarGateButton", GATE_X, MY_ROW[1], 0.115, MY_ROW[2])
myGate.AutoButtonColor = true

-- Lane slots: slots.Enemy[lane] and slots.Self[lane]
local slots = { Enemy = {}, Self = {} }
for _, side in ipairs({ "Enemy", "Self" }) do
	local row = side == "Enemy" and ENEMY_ROW or MY_ROW
	for lane = 1, LANES do
		slots[side][lane] = cardSlot(("Slot_%s_%d"):format(side, lane), LANE_X[lane], row[1], LANE_W, row[2])
	end
end

-- Match log and buttons (right)
local logFrame = make("Frame", {
	Name = "Log",
	Position = UDim2.fromScale(0.76, 0.065),
	Size = UDim2.fromScale(0.225, 0.43),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.2,
	BorderSizePixel = 0,
}, root)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, logFrame)
local logLabel = label(logFrame, {
	Name = "LogText",
	Position = UDim2.fromScale(0.05, 0.02),
	Size = UDim2.fromScale(0.9, 0.96),
	TextScaled = false,
	TextSize = 14,
	TextWrapped = true,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "",
})

local inspectButton = button(root, "InspectButton", "Inspect", UDim2.fromScale(0.76, 0.505), UDim2.fromScale(0.225, 0.055),
	TINT.Inspect)
local abilityButton = button(root, "AbilityButton", "Ability", UDim2.fromScale(0.76, 0.57), UDim2.fromScale(0.225, 0.06),
	TINT.Ability)
local sparkButton = button(root, "SparkButton", "Spark +1", UDim2.fromScale(0.76, 0.64), UDim2.fromScale(0.225, 0.06),
	TINT.Spark)
-- End Turn: the biggest button, glowing on your turn
local endTurnButton = button(root, "EndTurnButton", "End Turn", UDim2.fromScale(0.76, 0.725), UDim2.fromScale(0.225, 0.16),
	TINT.EndTurn)
-- Leave: small and out of the way (top right), and it asks first
local leaveButton = button(root, "LeaveButton", "Leave", UDim2.fromScale(0.885, 0.008), UDim2.fromScale(0.1, 0.047),
	TINT.Grey)

-- Your info line and hand (bottom)
local myLabel = label(root, {
	Name = "MyInfo",
	Position = UDim2.fromScale(0.015, 0.68),
	Size = UDim2.fromScale(0.38, 0.045),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})

local handFrame = make("Frame", {
	Name = "Hand",
	Position = UDim2.fromScale(0.015, 0.735),
	Size = UDim2.fromScale(0.73, 0.26),
	BackgroundTransparency = 1,
}, root)

-- Waiting screen and game over banner
local waitingFrame = make("Frame", {
	Name = "Waiting",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(14, 11, 28),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 5,
}, gui)
local waitingLabel = label(waitingFrame, {
	Name = "WaitingText",
	Position = UDim2.fromScale(0.1, 0.35),
	Size = UDim2.fromScale(0.8, 0.12),
	ZIndex = 5,
	Text = "",
})
local waitingLeave = button(waitingFrame, "WaitingLeaveButton", "Stand up", UDim2.fromScale(0.4, 0.55),
	UDim2.fromScale(0.2, 0.08), TINT.Grey)
waitingLeave.ZIndex = 5

-- Deck picker (shown after you sit down)
local pickerFrame = make("Frame", {
	Name = "DeckPicker",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(14, 11, 28),
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 6,
}, gui)
label(pickerFrame, {
	Name = "PickerTitle",
	Position = UDim2.fromScale(0.1, 0.04),
	Size = UDim2.fromScale(0.8, 0.08),
	ZIndex = 6,
	Text = "Choose your deck",
})

-- Format: best of 1, 3 or 5
local chosenFormat = 1 -- remembered for next time
local formatButtons = {}
for i, bestOf in ipairs({ 1, 3, 5 }) do
	local b = button(pickerFrame, "FormatBo" .. bestOf, "Best of " .. bestOf,
		UDim2.fromScale(0.305 + (i - 1) * 0.135, 0.17), UDim2.fromScale(0.12, 0.06), TINT.Grey)
	b.ZIndex = 6
	formatButtons[bestOf] = b
end
local formatNote = label(pickerFrame, {
	Name = "FormatNote",
	Position = UDim2.fromScale(0.1, 0.235),
	Size = UDim2.fromScale(0.8, 0.035),
	Font = Enum.Font.Gotham,
	ZIndex = 6,
	Text = "",
})
local vsBotPicker = false
local opponentVote = nil

local function refreshFormat()
	for bestOf, b in pairs(formatButtons) do
		setTint(b, bestOf == chosenFormat and TINT.Inspect or TINT.Grey)
		setStroke(b, bestOf == chosenFormat and HIGHLIGHT or nil, 2)
	end
	if vsBotPicker then
		formatNote.Text = "How many games do you want to play?"
	else
		local theirs = opponentVote and ("Opponent voted best of " .. opponentVote .. ".")
			or "Opponent hasn't voted yet."
		formatNote.Text = "Vote for a format. If you disagree, the shorter series is played.  " .. theirs
	end
end
for bestOf, b in pairs(formatButtons) do
	b.Activated:Connect(function()
		chosenFormat = bestOf
		refreshFormat()
	end)
end

local pickerList = make("ScrollingFrame", {
	Name = "PickerList",
	Position = UDim2.fromScale(0.1, 0.285),
	Size = UDim2.fromScale(0.8, 0.52),
	BackgroundTransparency = 1,
	ScrollBarThickness = 8,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 6,
}, pickerFrame)
local pickerLeave = button(pickerFrame, "PickerLeaveButton", "Stand up", UDim2.fromScale(0.4, 0.82),
	UDim2.fromScale(0.2, 0.08), TINT.Grey)
pickerLeave.ZIndex = 6

-- Series score (top right, next to Leave; hidden for a single game)
local seriesLabel = label(root, {
	Name = "SeriesInfo",
	Position = UDim2.fromScale(0.76, 0.008),
	Size = UDim2.fromScale(0.118, 0.047),
	TextColor3 = HIGHLIGHT,
	Visible = false,
	Text = "",
})

local gameOverLabel = label(root, {
	Name = "GameOver",
	Position = UDim2.fromScale(0.13, 0.27),
	Size = UDim2.fromScale(0.62, 0.2),
	BackgroundTransparency = 0.2,
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	ZIndex = 4,
	Visible = false,
	Text = "",
})

-- Inspect overlay: the card big on the left, its details on the right
local inspectFrame = make("TextButton", {
	Name = "Inspect",
	Text = "",
	AutoButtonColor = false,
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.25,
	Visible = false,
	ZIndex = 20,
}, gui)
local inspectCard = make("Frame", {
	Name = "InspectCard",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.3, 0.47),
	Size = UDim2.fromScale(0.3, 0.8),
	BackgroundTransparency = 1,
	ZIndex = 20,
}, inspectFrame)
make("UIAspectRatioConstraint", { Name = "SlotShape", AspectRatio = CARD_ASPECT }, inspectCard)
local inspectPanel = make("Frame", {
	Name = "InspectPanel",
	Position = UDim2.fromScale(0.5, 0.07),
	Size = UDim2.fromScale(0.36, 0.8),
	BackgroundColor3 = PANEL,
	BorderSizePixel = 0,
	ZIndex = 20,
}, inspectFrame)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, inspectPanel)
local inspectTitle = label(inspectPanel, {
	Name = "InspectTitle",
	Position = UDim2.fromScale(0.05, 0.03),
	Size = UDim2.fromScale(0.9, 0.08),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = HIGHLIGHT,
	ZIndex = 21,
	Text = "",
})
local inspectText = label(inspectPanel, {
	Name = "InspectText",
	Position = UDim2.fromScale(0.05, 0.13),
	Size = UDim2.fromScale(0.9, 0.84),
	TextScaled = false,
	TextSize = 18,
	TextWrapped = true,
	RichText = true,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 21,
	Text = "",
})
local inspectClose = button(inspectFrame, "InspectCloseButton", "Close", UDim2.fromScale(0.5, 0.89),
	UDim2.fromScale(0.36, 0.07), TINT.Grey)
inspectClose.ZIndex = 21

---------------------------------------------------------------------
-- Drawing cards (shared look lives in CardVisuals)
---------------------------------------------------------------------
local function drawCard(target, cardId, unit, hideCost, dim, finish)
	CardVisuals.Draw(target, cardId, { Unit = unit, HideCost = hideCost, Dim = dim, Finish = finish })
end

local function drawFaceDown(target, text)
	CardVisuals.DrawFaceDown(target, text)
end

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local current = nil   -- the latest "Match" update from the server
local animating = false -- true while an update's animations are playing

-- Which finish (Holo, 3D...) a card shows. Seats bring the shiniest copy they own.
local lastFinishReport = nil -- turn of the last update, to print the finishes once per game
local animPayload = nil -- while an update animates, its finishes include newly shown cards
local function finishFor(side, cardId)
	local source = animPayload or current
	if not source or not source.Finishes then
		return nil
	end
	local list = side == "Self" and source.Finishes.Mine or source.Finishes.Theirs
	return list and list[cardId]
end

local selected = nil  -- what you clicked first: { Kind = "Hand"/"Celestial"/"Ability", ... }
local logLines = {}
local flashMessage = nil
local inspectMode = false -- true after pressing Inspect: the next card clicked is inspected
local inspecting = nil    -- what the inspect window is showing, so it updates live
local showInspect, refreshInspect

local function cardName(cardId)
	local card = cardId and CardDatabase.GetCard(cardId)
	return card and card.Name or "a card"
end

local function isMyTurn()
	return current ~= nil and current.State.Current == current.Seat and not current.State.Winner and not animating
end

local function send(action)
	actionRemote:FireServer(action)
end

local function addLog(text)
	table.insert(logLines, text)
	while #logLines > 12 do
		table.remove(logLines, 1)
	end
	logLabel.Text = table.concat(logLines, "\n")
end

local function who(seat)
	if seat == current.Seat then
		return "You"
	end
	return current.Names[seat] or "Opponent"
end

local function describe(event)
	local t = event.Type
	if t == "MatchStarted" then
		return who(event.FirstPlayer) .. " go" .. (event.FirstPlayer == current.Seat and "" or "es") .. " first."
	elseif t == "TurnStarted" then
		return ("-- Turn %d: %s --"):format(event.Turn, who(event.Player))
	elseif t == "Draw" then
		if event.Player == current.Seat and event.CardId then
			return "You drew " .. cardName(event.CardId) .. "."
		end
		return nil
	elseif t == "UnitPlayed" then
		return who(event.Player) .. " played " .. cardName(event.CardId) .. "."
	elseif t == "SpellCast" then
		return who(event.Player) .. " cast " .. cardName(event.CardId) .. "."
	elseif t == "CelestialSummoned" then
		return who(event.Player) .. " summoned " .. cardName(event.CardId) .. "!"
	elseif t == "CelestialReturned" then
		return who(event.Player) .. "'s Celestial returned to the Star Gate."
	elseif t == "CommanderDamaged" then
		return ("%s took %d damage."):format(who(event.Player), event.Amount)
	elseif t == "UnitDestroyed" then
		return who(event.Player) .. " lost a unit."
	elseif t == "ShieldBroken" then
		return "A Shield broke."
	elseif t == "ShieldGained" then
		return "A unit gained a Shield."
	elseif t == "UnitHealed" then
		return ("A unit healed %d."):format(event.Amount)
	elseif t == "CommanderHealed" then
		return ("%s healed %d."):format(who(event.Player), event.Amount)
	elseif t == "StormDamage" then
		return ("Cosmic Storm hits %s for %d!"):format(who(event.Player) == "You" and "you" or who(event.Player), event.Amount)
	elseif t == "Ignite" then
		return ("Ignite dealt %d."):format(event.Amount)
	elseif t == "SparkUsed" then
		return who(event.Player) .. " used Spark."
	elseif t == "CommanderAbility" then
		return who(event.Player) .. (event.Player == current.Seat and " used your" or " used their") .. " Commander ability."
	elseif t == "DeckEmpty" then
		return who(event.Player) .. " has no cards left to draw."
	elseif t == "MatchOver" then
		return who(event.Winner) .. (event.Winner == current.Seat and " win!" or " wins.")
	end
	return nil
end

-- What clicking a lane means right now: "Place", "AnyUnit", "FriendlyUnit" or nil
local function targetMode()
	if not selected or not current then
		return nil
	end
	if selected.Kind == "Celestial" then
		return "Place"
	elseif selected.Kind == "Ability" then
		return "FriendlyUnit"
	elseif selected.Kind == "Hand" then
		local card = CardDatabase.GetCard(selected.CardId)
		if card.Type == "Unit" then
			return "Place"
		end
		return card.Effect.Target
	end
	return nil
end

---------------------------------------------------------------------
-- Drawing the whole screen from the latest state
---------------------------------------------------------------------
local render

---------------------------------------------------------------------
-- Inspect: shows one card big, with its buffs listed on the right
---------------------------------------------------------------------
local GOOD = "#8CE68C"
local BAD = "#FF8C8C"
local TEMP = "#FFE650"
local DIMTEXT = "#AAA0C8"

local function esc(text)
	return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function colored(color, text)
	return ('<font color="%s">%s</font>'):format(color, text)
end

-- Same source twice ("Kindle +1" and "Kindle +1") shows once as "+2 from Kindle (x2)"
local function groupBuffs(buffs)
	local groups, order = {}, {}
	for _, buff in ipairs(buffs or {}) do
		local key = buff.Source .. (buff.Temporary and "|temp" or "")
		local group = groups[key]
		if not group then
			group = { Source = buff.Source, Temporary = buff.Temporary, Power = 0, Count = 0 }
			groups[key] = group
			table.insert(order, group)
		end
		group.Power = group.Power + buff.Power
		group.Count = group.Count + 1
	end
	return order
end

-- Finds what the inspect window points at in the latest state
local function sideState(side)
	local seat = side == "Self" and current.Seat or 3 - current.Seat
	return current.State.Players[seat]
end

local function findUnit(uid)
	for _, side in ipairs({ "Self", "Enemy" }) do
		for _, unit in ipairs(sideState(side).Lanes) do
			if unit and unit.Uid == uid then
				return unit, side
			end
		end
	end
	return nil
end

local function unitDetails(unit, side, lines)
	local card = CardDatabase.GetCard(unit.CardId)
	table.insert(lines, colored(DIMTEXT, side == "Self" and "Your unit" or "Opponent's unit"))
	table.insert(lines, "")

	-- Power and where it came from
	local powerColor = unit.Power > unit.BasePower and GOOD or (unit.Power < unit.BasePower and BAD or "#FFFFFF")
	table.insert(lines, ("<b>Power %s</b>  %s"):format(colored(powerColor, unit.Power),
		colored(DIMTEXT, "(printed " .. unit.BasePower .. ")")))
	local groups = groupBuffs(unit.Buffs)
	if #groups == 0 then
		table.insert(lines, colored(DIMTEXT, "   No buffs"))
	end
	for _, group in ipairs(groups) do
		local amount = (group.Power >= 0 and "+" or "") .. group.Power
		local line = ("   %s from %s"):format(colored(group.Temporary and TEMP or GOOD, amount), esc(group.Source))
		if group.Count > 1 then
			line = line .. " (x" .. group.Count .. ")"
		end
		if group.Temporary then
			line = line .. " " .. colored(TEMP, "(this turn only)")
		end
		table.insert(lines, line)
	end
	table.insert(lines, "")

	-- Health
	local hurt = unit.HP < unit.MaxHP
	table.insert(lines, ("<b>Health %s / %d</b>  %s"):format(colored(hurt and BAD or GOOD, unit.HP), unit.MaxHP,
		colored(DIMTEXT, "(printed " .. unit.BaseHP .. ")")))
	if hurt then
		table.insert(lines, colored(DIMTEXT, ("   Took %d damage"):format(unit.MaxHP - unit.HP)))
	end
	table.insert(lines, "")

	-- Keywords and status
	if unit.Shield then
		local from = unit.ShieldSource == "Shield keyword" and "its Shield keyword"
			or esc(unit.ShieldSource or "an effect")
		table.insert(lines, ("<b>Shield</b> from %s: blocks the next hit"):format(from))
	end
	if unit.Rush then
		table.insert(lines, "<b>Rush</b>: can attack the turn it's played")
	end
	if unit.Ignite and unit.Ignite > 0 then
		table.insert(lines, ("<b>Ignite %d</b>: hit the unit across for %d when played"):format(unit.Ignite, unit.Ignite))
	end
	if unit.Regen and unit.Regen > 0 then
		table.insert(lines, ("<b>Regen %d</b>: heals %d at the end of each turn"):format(unit.Regen, unit.Regen))
	end
	if side == "Self" then
		table.insert(lines, unit.CanAttack and colored(GOOD, "Ready: attacks when you end your turn")
			or colored(TEMP, "Just arrived: attacks starting next turn"))
	end
	if unit.IsCelestial then
		table.insert(lines, "")
		table.insert(lines, ("<b>Celestial</b>: if destroyed it goes back to the Star Gate, and summoning it again costs %d more.")
			:format(CardDatabase.Rules.CelestialTax))
	end
	if card.AbilityText and card.AbilityText ~= "" then
		table.insert(lines, "")
		table.insert(lines, colored(DIMTEXT, esc(card.AbilityText)))
	end
end

local function commanderDetails(who, side, lines)
	local card = CardDatabase.GetCard(who.CommanderId)
	table.insert(lines, colored(DIMTEXT, side == "Self" and "Your Commander" or "Opponent's Commander"))
	table.insert(lines, "")
	local hurt = who.HP < who.MaxHP
	table.insert(lines, ("<b>Health %s / %d</b>"):format(colored(hurt and BAD or GOOD, who.HP), who.MaxHP))
	table.insert(lines, ("<b>Energy %d / %d</b>"):format(who.Energy, who.MaxEnergy))
	table.insert(lines, "")
	local ability = card.CommanderAbility
	if ability then
		table.insert(lines, ("<b>Ability (%d energy)</b>: %s"):format(ability.EnergyCost, esc(ability.Text)))
		table.insert(lines, who.AbilityUsed and colored(DIMTEXT, "Already used this turn")
			or colored(GOOD, "Ready to use"))
	end
end

local function gateDetails(gate, side, lines)
	local card = CardDatabase.GetCard(gate.CardId)
	table.insert(lines, colored(DIMTEXT, side == "Self" and "Your Celestial (in the Star Gate)" or "Opponent's Celestial (in the Star Gate)"))
	table.insert(lines, "")
	if gate.Cost then
		local raised = gate.Cost > card.EnergyCost
		table.insert(lines, ("<b>Summon cost %s</b>  %s"):format(colored(raised and BAD or GOOD, gate.Cost),
			colored(DIMTEXT, "(printed " .. card.EnergyCost .. ")")))
		if raised then
			table.insert(lines, colored(DIMTEXT, ("   +%d because it came back %d time%s"):format(
				gate.Cost - card.EnergyCost, gate.TimesReturned or 0, (gate.TimesReturned == 1) and "" or "s")))
		end
		table.insert(lines, "")
	end
	table.insert(lines, ("<b>Power %d / Health %d</b>"):format(card.Power, card.HP))
	table.insert(lines, esc(CardVisuals.KeywordText(card)))
	table.insert(lines, "")
	table.insert(lines, colored(DIMTEXT, ("Each time it's destroyed it returns here and costs %d more to summon.")
		:format(CardDatabase.Rules.CelestialTax)))
end

local function cardDetails(cardId, lines)
	local card = CardDatabase.GetCard(cardId)
	local typeLine = card.Type
	if card.Type == "Unit" or card.Type == "Spell" then
		typeLine = card.Faction .. " " .. card.Type
	end
	table.insert(lines, colored(DIMTEXT, ("%s  |  %s"):format(typeLine, card.Rarity)))
	table.insert(lines, "")
	if card.EnergyCost then
		table.insert(lines, ("<b>Cost %d energy</b>"):format(card.EnergyCost))
	end
	if card.Power then
		table.insert(lines, ("<b>Power %d / Health %d</b>"):format(card.Power, card.HP))
	end
	table.insert(lines, "")
	table.insert(lines, esc(CardVisuals.KeywordText(card)))
end

local function closeInspect()
	inspecting = nil
	inspectFrame.Visible = false
end

-- Redraws the inspect window from the latest state (buffs change as the game goes)
function refreshInspect()
	if not inspecting or not current then
		closeInspect()
		return
	end
	local lines = {}
	local cardId, drawOptions = nil, {}
	local what = inspecting
	if what.Kind == "Unit" then
		local unit, side = findUnit(what.Uid)
		if unit then
			cardId = unit.CardId
			drawOptions.Unit = unit
			drawOptions.Finish = finishFor(side, cardId)
			unitDetails(unit, side, lines)
		else
			cardId = what.CardId
			table.insert(lines, colored(BAD, "This unit has left the board."))
			table.insert(lines, "")
			cardDetails(cardId, lines)
		end
	elseif what.Kind == "Commander" then
		local who = sideState(what.Side)
		cardId = who.CommanderId
		drawOptions.Finish = finishFor(what.Side, cardId)
		drawOptions.StatsText = ("%d / %d HP"):format(who.HP, who.MaxHP)
		drawOptions.StatsHurt = who.HP < who.MaxHP
		commanderDetails(who, what.Side, lines)
	elseif what.Kind == "Gate" then
		local gate = sideState(what.Side).StarGate
		if not gate.CardId or gate.OnBoard then
			closeInspect()
			return
		end
		cardId = gate.CardId
		drawOptions.Finish = finishFor(what.Side, cardId)
		drawOptions.Cost = gate.Cost
		drawOptions.CostRaised = gate.Cost ~= nil and gate.Cost > CardDatabase.GetCard(cardId).EnergyCost
		gateDetails(gate, what.Side, lines)
	else
		cardId = what.CardId
		drawOptions.Finish = finishFor("Self", cardId) -- a card in your hand
		cardDetails(cardId, lines)
	end
	-- which finish this copy shows (so you can tell your picks made it into the match)
	table.insert(lines, "")
	table.insert(lines, colored("#AAA0C8",
		"Finish: " .. (CardVisuals.FinishNames[drawOptions.Finish or "Base"] or "Standard")))
	clear(inspectCard)
	CardVisuals.Draw(inspectCard, cardId, drawOptions)
	inspectTitle.Text = CardDatabase.GetCard(cardId).Name
	inspectText.Text = table.concat(lines, "\n")
	inspectFrame.Visible = true
end

-- what: { Kind = "Unit", Uid, CardId } / { Kind = "Commander", Side } / { Kind = "Gate", Side } / { CardId }
function showInspect(what)
	inspectMode = false
	inspecting = what
	refreshInspect()
	render()
end

local function selectThing(thing)
	selected = thing
	flashMessage = nil
	render()
end

local uidSlot = {} -- [unit Uid] = the lane slot showing it

function render()
	if not current or animating then
		return
	end
	for uid in pairs(uidSlot) do
		uidSlot[uid] = nil
	end
	-- Undo anything an animation left moved, shrunk or tilted
	for slot, base in pairs(slotBase) do
		slot.Position = UDim2.fromScale(base.X, base.Y)
		slot.Size = UDim2.fromScale(base.W, base.H)
		slot.Rotation = 0
	end
	local state = current.State
	local seat = current.Seat
	local me = state.Players[seat]
	local enemy = state.Players[3 - seat]
	local enemySeat = 3 - seat

	-- A selection only makes sense while it's still valid
	if selected and selected.Kind == "Hand" and me.Hand[selected.Index] ~= selected.CardId then
		selected = nil
	end
	if not isMyTurn() then
		selected = nil
	end

	opponentLabel.Text = ("%s  |  %s  |  HP %d  |  Energy %d/%d  |  Hand %d  |  Deck %d"):format(
		current.Names[enemySeat] or "Opponent", cardName(enemy.CommanderId), enemy.HP,
		enemy.Energy, enemy.MaxEnergy, enemy.HandCount, enemy.DeckCount)
	local round = math.ceil(state.Turn / 2)
	local stormStart = CardDatabase.Rules.StormStartRound
	local stormText = ""
	if stormStart then
		if round >= stormStart then
			stormText = "  |  COSMIC STORM"
		elseif stormStart - round <= 3 then
			stormText = ("  |  Storm in %d"):format(stormStart - round)
		end
	end
	myLabel.Text = ("You  |  HP %d  |  Energy %d/%d  |  Deck %d  |  Round %d%s"):format(
		me.HP, me.Energy, me.MaxEnergy, me.DeckCount, round, stormText)

	-- Status line
	if flashMessage then
		statusLabel.Text = flashMessage
	elseif state.Winner then
		statusLabel.Text = "Match over"
	elseif selected then
		statusLabel.Text = selected.Hint or ""
	elseif isMyTurn() then
		statusLabel.Text = "Your turn: play cards, then End Turn."
	else
		statusLabel.Text = (current.Names[state.Current] or "Opponent") .. " is taking their turn..."
	end

	-- Lanes
	local mode = targetMode()
	for _, side in ipairs({ "Enemy", "Self" }) do
		local owner = side == "Self" and me or enemy
		for lane = 1, LANES do
			local slot = slots[side][lane]
			clear(slot)
			local unit = owner.Lanes[lane]
			if unit then
				uidSlot[unit.Uid] = slot
				drawCard(slot, unit.CardId, unit, false, false, finishFor(side, unit.CardId))
			else
				-- An empty lane: a see-through card outline in the mat's color
				slot.BackgroundColor3 = EMPTY_SLOT
				slot.BackgroundTransparency = 1 -- the printed zone underneath shows through
				make("UICorner", { CornerRadius = UDim.new(0.06, 0) }, slot)
				label(slot, {
					Name = "Empty",
					Position = UDim2.fromScale(0.1, 0.4),
					Size = UDim2.fromScale(0.8, 0.2),
					Font = Enum.Font.Gotham,
					TextColor3 = matAccent[side],
					TextTransparency = 0.3,
					Text = "Lane " .. lane,
				})
			end
			local valid = (mode == "Place" and side == "Self" and not unit)
				or (mode == "AnyUnit" and unit)
				or (mode == "FriendlyUnit" and side == "Self" and unit)
			if valid then
				setStroke(slot, HIGHLIGHT, 3)
			else
				setStroke(slot, nil)
			end
		end
	end

	-- Commanders (current HP shown on the card)
	local function drawCommander(slot, player, side)
		clear(slot)
		CardVisuals.Draw(slot, player.CommanderId, {
			Finish = finishFor(side, player.CommanderId),
			StatsText = ("%d / %d HP"):format(player.HP, player.MaxHP),
			StatsHurt = player.HP < player.MaxHP,
		})
	end
	drawCommander(enemyCommander, enemy, "Enemy")
	drawCommander(myCommander, me, "Self")
	-- Big HP badge in the corner of each Commander: the number that decides the match
	for _, pair in ipairs({ { enemyCommander, enemy }, { myCommander, me } }) do
		local slot, who = pair[1], pair[2]
		local hurt = who.HP < who.MaxHP
		local badge = label(slot, {
			Name = "HPBadge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.86, 0.3),
			Size = UDim2.fromScale(0.34, 0.2),
			BackgroundTransparency = 0,
			BackgroundColor3 = hurt and Color3.fromRGB(170, 30, 40) or Color3.fromRGB(40, 120, 60),
			ZIndex = 10,
			Text = tostring(who.HP),
		})
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, badge)
		make("UIStroke", { Color = WHITE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, badge)
	end
	setStroke(myCommander, (selected and selected.Kind == "Ability") and HIGHLIGHT or nil, 4)

	-- Star Gates
	-- The cost circle shows what summoning costs right now (it goes up each
	-- time the Celestial is sent back), red once it's above the printed cost.
	local function drawGate(slot, gate, canAfford, side)
		clear(slot)
		if gate.OnBoard then
			drawFaceDown(slot, "Celestial on the board")
		elseif gate.CardId then
			local card = CardDatabase.GetCard(gate.CardId)
			CardVisuals.Draw(slot, gate.CardId, {
				Finish = finishFor(side, gate.CardId),
				Cost = gate.Cost,
				CostRaised = gate.Cost ~= nil and gate.Cost > card.EnergyCost,
				Dim = canAfford == false,
			})
		else
			drawFaceDown(slot, "Face-down Celestial")
		end
	end
	drawGate(enemyGate, enemy.StarGate, nil, "Enemy")
	drawGate(myGate, me.StarGate, me.StarGate.Cost <= me.Energy or not isMyTurn(), "Self")
	setStroke(myGate, (selected and selected.Kind == "Celestial") and HIGHLIGHT or nil, 4)

	-- Buttons
	local commander = CardDatabase.GetCard(me.CommanderId)
	setLabel(abilityButton, ("Ability (%d)"):format(commander.CommanderAbility.EnergyCost))
	setTint(abilityButton, TINT.Ability, isMyTurn() and not me.AbilityUsed
		and me.Energy >= commander.CommanderAbility.EnergyCost)
	setStroke(abilityButton, (selected and selected.Kind == "Ability") and HIGHLIGHT or nil, 3)
	sparkButton.Visible = me.HasSpark == true
	setStroke(inspectButton, inspectMode and HIGHLIGHT or nil, 3)
	setLabel(inspectButton, inspectMode and "Click a card..." or "Inspect")
	if inspecting then
		refreshInspect()
	end
	setTint(endTurnButton, TINT.EndTurn, isMyTurn())
	setStroke(endTurnButton, isMyTurn() and Color3.fromRGB(255, 200, 120) or nil, 3)
	setLabel(endTurnButton, isMyTurn() and "End Turn" or "Their Turn")

	-- Hand: card-shaped, centered, shrinking to fit when it gets big
	clear(handFrame)
	local count = #me.Hand
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.006, 0),
	}, handFrame)
	local width = math.min(0.155, 0.98 / math.max(count, 1) - 0.006)
	for i, cardId in ipairs(me.Hand) do
		local card = CardDatabase.GetCard(cardId)
		local cardButton = make("TextButton", {
			Name = "HandCard_" .. i,
			Text = "",
			LayoutOrder = i,
			AutoButtonColor = true,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(width, 1),
		}, handFrame)
		make("UIAspectRatioConstraint", { Name = "SlotShape", AspectRatio = CARD_ASPECT }, cardButton)
		drawCard(cardButton, cardId, nil, false, card.EnergyCost > me.Energy, finishFor("Self", cardId))
		if card.EnergyCost > me.Energy then
			cardButton.BackgroundTransparency = math.max(cardButton.BackgroundTransparency, 0.5)
		end
		if selected and selected.Kind == "Hand" and selected.Index == i then
			setStroke(cardButton, HIGHLIGHT, 4)
		end
		cardButton.MouseButton2Click:Connect(function()
			showInspect({ CardId = cardId })
		end)
		cardButton.Activated:Connect(function()
			if inspectMode then
				showInspect({ CardId = cardId })
				return
			end
			if not isMyTurn() then
				flashMessage = "Wait for your turn."
				render()
				return
			end
			if selected and selected.Kind == "Hand" and selected.Index == i then
				selectThing(nil)
				return
			end
			if card.Type == "Spell" and not card.Effect.Target then
				selected = nil
				send({ Kind = "PlayCard", HandIndex = i })
				return
			end
			local hint = card.Type == "Unit" and "Pick one of your empty lanes."
				or (card.Effect.Target == "FriendlyUnit" and "Pick one of your units." or "Pick a unit to target.")
			selectThing({ Kind = "Hand", Index = i, CardId = cardId, Hint = hint })
		end)
	end

	-- Game over banner
	-- Series score. Right when a game ends the server may not have counted
	-- it yet, so count it here if needed.
	local series = current.Series
	local myWins, theirWins, seriesOver = 0, 0, true
	if series then
		myWins, theirWins = series.Wins[seat], series.Wins[3 - seat]
		if state.Winner and myWins + theirWins < series.Game then
			if state.Winner == seat then
				myWins = myWins + 1
			else
				theirWins = theirWins + 1
			end
		end
		local needed = (series.BestOf + 1) // 2
		seriesOver = myWins >= needed or theirWins >= needed
	end
	seriesLabel.Visible = series ~= nil and series.BestOf > 1
	if seriesLabel.Visible then
		seriesLabel.Text = ("Bo%d  %d - %d"):format(series.BestOf, myWins, theirWins)
	end

	if state.Winner then
		gameOverLabel.Visible = true
		local won = state.Winner == seat
		if not series or series.BestOf == 1 then
			gameOverLabel.Text = won and "You win!" or "You lose"
		elseif seriesOver then
			gameOverLabel.Text = (won and "You win the series %d - %d!" or "You lose the series %d - %d")
				:format(myWins, theirWins)
		else
			gameOverLabel.Text = ("%s game %d\nSeries: you %d - %d them\nNext game starting..."):format(
				won and "You win" or "You lose", series.Game, myWins, theirWins)
		end
	else
		gameOverLabel.Visible = false
	end
end

---------------------------------------------------------------------
-- Animations
-- Each update from the server is a list of events. They play one by one
-- on the board as it was, then the board is redrawn from the new state.
---------------------------------------------------------------------
local SPEEDS = { { 1, "Normal" }, { 2, "Fast" }, { 0, "Off" } }
local animSpeed = player:GetAttribute("BattleAnimSpeed") or 1
local confirmFrame -- the "Leave the match?" box (built further down)
local updateQueue = {} -- match updates (and small jobs like reward messages) waiting their turn
local queueRunning = false
local queueGeneration = 0 -- goes up when the table closes, so leftover updates are dropped

---------------------------------------------------------------------
-- Sounds: upload the files from the "sounds" folder, then paste each
-- Asset ID here. 0 = not uploaded yet (stays silent).
---------------------------------------------------------------------
local SOUND_IDS = {
	CardPlay = 76825551217291, -- card_play.ogg
	SpellCast = 118712746471155, -- spell_cast.ogg
	AttackSwing = 80568989003440, -- attack_swing.ogg
	Hit = 130450370015546, -- hit.ogg
	CommanderHit = 137530799827877, -- commander_hit.ogg
	ShieldBreak = 109682621104838, -- shield_break.ogg
	Heal = 110734613231631, -- heal.ogg
	Buff = 127038314194435, -- buff.ogg
	UnitDestroyed = 88708482448673, -- unit_destroyed.ogg
	CelestialSummon = 80850753535949, -- celestial_summon.ogg
	Storm = 84919099028183, -- storm.ogg
	YourTurn = 71226751734567, -- your_turn.ogg
	Victory = 101578556264839, -- victory.ogg
	Defeat = 96987209399521, -- defeat.ogg
	Click = 108485405671310, -- click.ogg
}
-- How loud each one plays (0 to 1), to even them out
local SOUND_VOLUME = {
	CardPlay = 0.55, SpellCast = 0.5, AttackSwing = 0.45, Hit = 0.5, CommanderHit = 0.5,
	ShieldBreak = 0.6, Heal = 0.5, Buff = 0.5, UnitDestroyed = 0.55, CelestialSummon = 0.6,
	Storm = 0.7, YourTurn = 0.45, Victory = 0.45, Defeat = 0.4, Click = 0.35,
}
local soundOn = player:GetAttribute("BattleSound") ~= false
local soundFolder = Instance.new("Folder")
soundFolder.Name = "BattleSounds"
soundFolder.Parent = gui
local soundObjects = {}
for name, id in pairs(SOUND_IDS) do
	if id ~= 0 then
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = "rbxassetid://" .. id
		sound.Volume = SOUND_VOLUME[name] or 0.5
		sound.Parent = soundFolder
		soundObjects[name] = sound
	end
end

-- pitch: 1 = normal, below 1 = deeper (big hits), above 1 = higher
local function playSound(name, pitch)
	local sound = soundObjects[name]
	if not soundOn or not sound then
		return
	end
	sound.PlaybackSpeed = pitch or 1
	sound:Play()
end

playClick = function()
	playSound("Click")
end

local fxLayer = make("Frame", {
	Name = "FX",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 15,
}, gui)

local function seconds(t)
	return t / math.max(animSpeed, 0.01)
end

local function tween(object, t, props, style, direction)
	local info = TweenInfo.new(seconds(t), style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local tw = TweenService:Create(object, info, props)
	tw:Play()
	return tw
end

local function pause(t)
	task.wait(seconds(t))
end

local function sideOfSeat(seatNumber)
	return seatNumber == current.Seat and "Self" or "Enemy"
end

local commanderSlots = { Self = myCommander, Enemy = enemyCommander }
local gateSlots = { Self = myGate, Enemy = enemyGate }

-- Removes an effect object after its animation
local function cleanup(object, after)
	task.delay(seconds(after), function()
		object:Destroy()
	end)
end

-- A number or word that floats up from a slot and fades
local function popText(slot, value, color, big)
	local base = slotBase[slot]
	if not base then
		return
	end
	local l = make("TextLabel", {
		Name = "PopText",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(base.X, base.Y),
		Size = UDim2.fromScale(big and 0.12 or 0.09, big and 0.08 or 0.06),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = color,
		TextStrokeTransparency = 0,
		Text = value,
		ZIndex = 16,
	}, fxLayer)
	tween(l, 0.8, { Position = UDim2.fromScale(base.X, base.Y - 0.07), TextTransparency = 1, TextStrokeTransparency = 1 })
	cleanup(l, 0.85)
end

-- A colored flash over a slot
local function flash(slot, color, strength)
	local f = make("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 1 - (strength or 0.55),
		BorderSizePixel = 0,
		ZIndex = 20,
	}, slot)
	make("UICorner", { CornerRadius = UDim.new(0.06, 0) }, f)
	tween(f, 0.35, { BackgroundTransparency = 1 })
	cleanup(f, 0.4)
end

-- A quick side-to-side shake
local function shake(slot)
	local base = slotBase[slot]
	if not base then
		return
	end
	task.spawn(function()
		for _, dx in ipairs({ 0.006, -0.006, 0.004, -0.003, 0 }) do
			tween(slot, 0.04, { Position = UDim2.fromScale(base.X + dx, base.Y) })
			pause(0.04)
		end
	end)
end

-- Moves a slot toward another point and back (an attack)
local function lunge(slot, towardY, amount)
	local base = slotBase[slot]
	if not base then
		return
	end
	local y = base.Y + (towardY - base.Y) * amount
	tween(slot, 0.13, { Position = UDim2.fromScale(base.X, y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	pause(0.13)
	task.spawn(function()
		pause(0.08)
		tween(slot, 0.2, { Position = UDim2.fromScale(base.X, base.Y) }, Enum.EasingStyle.Back)
	end)
end

-- Updates the number on a card's stat plate ("Power / HP") while animating
local function setShownStats(slot, power, hp, hurt)
	local stats = slot:FindFirstChild("Stats", true)
	if not stats then
		return
	end
	local shownPower, shownHp = stats.Text:match("^(%-?%d+) / (%-?%d+)$")
	if not shownPower then
		return
	end
	stats.Text = ("%s / %s"):format(power or shownPower, hp or shownHp)
	if hurt ~= nil then
		stats.TextColor3 = hurt and Color3.fromRGB(190, 30, 30) or Color3.fromRGB(38, 26, 30)
	end
end

local function setShownCommanderHP(side, hp, hurt)
	local badge = commanderSlots[side]:FindFirstChild("HPBadge")
	if badge then
		badge.Text = tostring(hp)
		badge.BackgroundColor3 = hurt and Color3.fromRGB(170, 30, 40) or Color3.fromRGB(40, 120, 60)
	end
end

-- A card flying from a point to a slot, then drawn in that slot
local function flyIn(cardId, fromX, fromY, slot, finish)
	local base = slotBase[slot]
	local card = make("Frame", {
		Name = "FlyingCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(fromX, fromY),
		Size = UDim2.fromScale(base.W, base.H),
		BackgroundTransparency = 1,
		ZIndex = 16,
	}, fxLayer)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, card)
	CardVisuals.Draw(card, cardId, { Finish = finish })
	tween(card, 0.3, { Position = UDim2.fromScale(base.X, base.Y) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	pause(0.3)
	card:Destroy()
	clear(slot)
	CardVisuals.Draw(slot, cardId, { Finish = finish })
	-- land with a little bounce
	slot.Size = UDim2.fromScale(base.W * 1.1, base.H * 1.1)
	tween(slot, 0.18, { Size = UDim2.fromScale(base.W, base.H) }, Enum.EasingStyle.Back)
end

-- A spell card shown big in the middle, then shrinking away toward its target
local function showSpell(cardId, targetSlot, finish)
	local shown = make("Frame", {
		Name = "SpellCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(0.06, 0.1),
		BackgroundTransparency = 1,
		ZIndex = 16,
	}, fxLayer)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, shown)
	CardVisuals.Draw(shown, cardId, { Finish = finish })
	tween(shown, 0.18, { Size = UDim2.fromScale(0.2, 0.4) }, Enum.EasingStyle.Back)
	pause(0.55)
	local base = targetSlot and slotBase[targetSlot]
	local to = base and UDim2.fromScale(base.X, base.Y) or UDim2.fromScale(0.5, 0.36)
	tween(shown, 0.2, { Size = UDim2.fromScale(0, 0), Position = to }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	pause(0.2)
	shown:Destroy()
end

-- Target = { Side, Lane } is relative to whoever cast it
local function targetSlotFor(casterSeat, target)
	if type(target) ~= "table" or not target.Lane then
		return nil
	end
	local side = target.Side
	if casterSeat ~= current.Seat then
		side = side == "Self" and "Enemy" or "Self"
	end
	return slots[side] and slots[side][target.Lane]
end

local RED = Color3.fromRGB(255, 80, 80)
local GREEN = Color3.fromRGB(110, 235, 120)
local BLUE = Color3.fromRGB(120, 190, 255)
local GOLD = Color3.fromRGB(255, 210, 90)
local ORANGE = Color3.fromRGB(255, 150, 50)

-- One event's animation. Returns after the part that should finish before the next event.
local playEvent = {}

function playEvent.UnitPlayed(e)
	playSound("CardPlay")
	local side = sideOfSeat(e.Player)
	local slot = slots[side][e.Lane]
	local fromY = side == "Self" and 0.87 or -0.15
	flyIn(e.CardId, 0.38, fromY, slot, finishFor(side, e.CardId))
	uidSlot[e.Uid] = slot
	pause(0.12)
end

function playEvent.CelestialSummoned(e)
	local side = sideOfSeat(e.Player)
	local slot = slots[side][e.Lane]
	local gate = gateSlots[side]
	playSound("CelestialSummon")
	flash(gate, GOLD, 0.8)
	pause(0.25)
	local white = make("Frame", {
		Name = "SummonFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 245, 220),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 17,
	}, fxLayer)
	tween(white, 0.45, { BackgroundTransparency = 1 })
	cleanup(white, 0.5)
	local g = slotBase[gate]
	flyIn(e.CardId, g.X, g.Y, slot, finishFor(side, e.CardId))
	uidSlot[e.Uid] = slot
	flash(slot, GOLD, 0.6)
	pause(0.25)
end

function playEvent.SpellCast(e)
	playSound("SpellCast")
	showSpell(e.CardId, targetSlotFor(e.Player, e.Target), finishFor(sideOfSeat(e.Player), e.CardId))
end

function playEvent.CommanderAbility(e)
	local side = sideOfSeat(e.Player)
	playSound("Buff", 0.9)
	flash(commanderSlots[side], GOLD, 0.7)
	popText(commanderSlots[side], "Ability!", GOLD)
	pause(0.35)
end

function playEvent.Attack(e)
	local attacker, defender = uidSlot[e.Attacker], uidSlot[e.Defender]
	if attacker and defender then
		playSound("AttackSwing")
		lunge(attacker, slotBase[defender].Y, 0.55)
	end
end

function playEvent.UnitDamaged(e)
	local slot = uidSlot[e.Uid]
	if slot then
		-- bigger hits sound deeper
		playSound("Hit", math.clamp(1.15 - (e.Amount or 1) * 0.06, 0.75, 1.15))
		flash(slot, RED, 0.6)
		shake(slot)
		popText(slot, "-" .. e.Amount, RED, true)
		setShownStats(slot, nil, e.HP, true)
	end
	pause(0.12)
end

function playEvent.Ignite(e)
	local slot = uidSlot[e.Target]
	if slot then
		playSound("Hit", 1.25)
		flash(slot, ORANGE, 0.7)
	end
	pause(0.1)
end

function playEvent.ShieldBroken(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("ShieldBreak")
		flash(slot, BLUE, 0.7)
		popText(slot, "Shield broke!", BLUE)
	end
	pause(0.15)
end

function playEvent.ShieldGained(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("Buff", 1.15)
		flash(slot, BLUE, 0.5)
		popText(slot, "+Shield", BLUE)
	end
	pause(0.15)
end

function playEvent.UnitHealed(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("Heal")
		flash(slot, GREEN, 0.4)
		popText(slot, "+" .. e.Amount, GREEN, true)
		setShownStats(slot, nil, e.HP, nil)
	end
	pause(0.12)
end

function playEvent.UnitBuffed(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("Buff")
		flash(slot, GOLD, 0.45)
		popText(slot, "Power " .. e.Power, GOLD)
		setShownStats(slot, e.Power, nil, nil)
	end
	pause(0.15)
end

local function removeFromSlot(slot, color, text)
	playSound("UnitDestroyed")
	local base = slotBase[slot]
	flash(slot, color, 0.7)
	if text then
		popText(slot, text, color)
	end
	tween(slot, 0.32, { Size = UDim2.fromScale(base.W * 0.15, base.H * 0.15), Rotation = 25 },
	Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	pause(0.34)
	clear(slot)
	slot.Size = UDim2.fromScale(base.W, base.H)
	slot.Rotation = 0
end

function playEvent.UnitDestroyed(e)
	local slot = uidSlot[e.Uid]
	if slot then
		removeFromSlot(slot, RED)
		uidSlot[e.Uid] = nil
	end
end

function playEvent.CelestialReturned(e)
	local slot = uidSlot[e.Uid]
	if slot then
		removeFromSlot(slot, GOLD, "Back to the Star Gate")
		uidSlot[e.Uid] = nil
	end
end

function playEvent.CommanderDamaged(e)
	local side = sideOfSeat(e.Player)
	local target = commanderSlots[side]
	local attacker = e.Attacker and uidSlot[e.Attacker]
	if attacker then
		-- charge up the lane toward the other side
		local towardY = side == "Self" and 0.95 or -0.1
		playSound("AttackSwing")
		lunge(attacker, towardY, 0.3)
	end
	playSound("CommanderHit")
	flash(target, RED, 0.65)
	shake(target)
	popText(target, "-" .. e.Amount, RED, true)
	setShownCommanderHP(side, e.HP, true)
	pause(0.25)
end

function playEvent.StormDamage(e)
	local side = sideOfSeat(e.Player)
	local target = commanderSlots[side]
	playSound("Storm")
	flash(target, Color3.fromRGB(190, 120, 255), 0.7)
	shake(target)
	popText(target, "Storm -" .. e.Amount, Color3.fromRGB(210, 160, 255), true)
	setShownCommanderHP(side, e.HP, true)
	pause(0.35)
end

function playEvent.CommanderHealed(e)
	local side = sideOfSeat(e.Player)
	local target = commanderSlots[side]
	playSound("Heal")
	flash(target, GREEN, 0.5)
	popText(target, "+" .. e.Amount, GREEN, true)
	setShownCommanderHP(side, e.HP, false)
	pause(0.2)
end

-- Sounds for the start of your turn and the end of a game. These play
-- even with animations off, after the update has played out.
local function playSummarySounds(payload)
	for _, event in ipairs(payload.Events) do
		if event.Type == "MatchOver" then
			playSound(event.Winner == payload.Seat and "Victory" or "Defeat")
			return
		end
	end
	for _, event in ipairs(payload.Events) do
		if event.Type == "TurnStarted" and event.Player == payload.Seat then
			playSound("YourTurn")
		end
	end
end

-- Should this update animate, or just snap into place?
local function shouldAnimate(payload)
	if animSpeed <= 0 or not current or current.Seat ~= payload.Seat then
		return false
	end
	for _, event in ipairs(payload.Events) do
		if event.Type == "MatchStarted" then
			return false -- a new game: just deal it out
		end
	end
	return true
end

-- Shows a new state: log lines (unless already logged while animating), mats, the board
local function applyUpdate(payload, alreadyLogged)
	gui.Enabled = true
	showBoard(true)
	waitingFrame.Visible = false
	pickerFrame.Visible = false
	current = payload
	flashMessage = nil
	local mats = payload.Mats or {}
	drawMats(mats[payload.Seat] or Playmats.DefaultId, mats[3 - payload.Seat] or Playmats.DefaultId)
	for _, event in ipairs(payload.Events) do
		if event.Type == "MatchStarted" then
			logLines = {}
			inspectMode = false
			closeInspect()
			confirmFrame.Visible = false
			local series = payload.Series
			if series and series.BestOf > 1 then
				addLog(("== Game %d (best of %d) =="):format(series.Game, series.BestOf))
			end
		end
		if not alreadyLogged then
			local text = describe(event)
			if text then
				addLog(text)
			end
		end
	end
	render()
end

local function animateUpdate(payload)
	selected = nil
	animPayload = payload
	for _, event in ipairs(payload.Events) do
		local text = describe(event)
		if text then
			addLog(text)
		end
		local play = playEvent[event.Type]
		if play then
			play(event)
		end
	end
	pause(0.15)
end

local function runQueue()
	queueRunning = true
	while #updateQueue > 0 do
		local item = table.remove(updateQueue, 1)
		local generation = queueGeneration
		if type(item) == "function" then
			item()
		elseif shouldAnimate(item) then
			animating = true
			local ok, err = pcall(animateUpdate, item)
			animating = false
			animPayload = nil
			if not ok then
				warn("BattleClient: animation failed: " .. tostring(err))
			end
			if generation == queueGeneration then -- skip it if the table closed meanwhile
				applyUpdate(item, ok)
				playSummarySounds(item)
			end
		else
			applyUpdate(item, false)
			playSummarySounds(item)
		end
	end
	queueRunning = false
end

local function queueUpdate(payload)
	if not queueRunning and not shouldAnimate(payload) then
		applyUpdate(payload, false) -- nothing waiting and nothing to animate: show it now
		playSummarySounds(payload)
		return
	end
	table.insert(updateQueue, payload)
	if not queueRunning then
		task.spawn(runQueue)
	end
end

-- Sound on/off (bottom of the match log, left of the speed button)
local soundButton = button(root, "SoundButton", "", UDim2.fromScale(0.805, 0.452), UDim2.fromScale(0.085, 0.036),
	TINT.Grey)
local function refreshSoundButton()
	setLabel(soundButton, soundOn and "Sound: On" or "Sound: Off")
end
refreshSoundButton()
soundButton.Activated:Connect(function()
	soundOn = not soundOn
	player:SetAttribute("BattleSound", soundOn)
	refreshSoundButton()
end)

-- Speed button (bottom right of the match log)
local speedButton = button(root, "AnimSpeedButton", "", UDim2.fromScale(0.895, 0.452), UDim2.fromScale(0.085, 0.036),
	TINT.Grey)
local function refreshSpeed()
	for _, s in ipairs(SPEEDS) do
		if s[1] == animSpeed then
			setLabel(speedButton, "Speed: " .. s[2])
		end
	end
end
refreshSpeed()
speedButton.Activated:Connect(function()
	local index = 1
	for i, s in ipairs(SPEEDS) do
		if s[1] == animSpeed then
			index = i
		end
	end
	animSpeed = SPEEDS[index % #SPEEDS + 1][1]
	player:SetAttribute("BattleAnimSpeed", animSpeed)
	refreshSpeed()
end)

---------------------------------------------------------------------
-- Clicks
---------------------------------------------------------------------
for _, side in ipairs({ "Enemy", "Self" }) do
	for lane = 1, LANES do
		local function unitHere()
			if not current then
				return nil
			end
			return sideState(side).Lanes[lane] or nil
		end
		local function inspectHere()
			local unit = unitHere()
			if unit then
				showInspect({ Kind = "Unit", Uid = unit.Uid, CardId = unit.CardId })
				return true
			end
			return false
		end
		slots[side][lane].MouseButton2Click:Connect(inspectHere)
		slots[side][lane].Activated:Connect(function()
			if inspectMode then
				if not inspectHere() then
					inspectMode = false
					render()
				end
				return
			end
			-- Nothing selected: clicking a unit shows its details
			if not selected or not isMyTurn() then
				inspectHere()
				return
			end
			local target = { Side = side, Lane = lane }
			local mode = targetMode()
			if mode == "Place" and side ~= "Self" then
				flashMessage = "That goes in one of your own lanes."
				render()
				return
			end
			if selected.Kind == "Hand" then
				if mode == "Place" then
					send({ Kind = "PlayCard", HandIndex = selected.Index, Lane = lane })
				else
					send({ Kind = "PlayCard", HandIndex = selected.Index, Target = target })
				end
			elseif selected.Kind == "Celestial" then
				send({ Kind = "SummonCelestial", Lane = lane })
			elseif selected.Kind == "Ability" then
				send({ Kind = "UseAbility", Target = target })
			end
			selectThing(nil)
		end)
	end
end

local function inspectGate(side)
	local gate = current and sideState(side).StarGate
	if gate and gate.CardId and not gate.OnBoard then
		showInspect({ Kind = "Gate", Side = side })
		return true
	end
	return false
end

local function inspectCommander(side)
	if current then
		showInspect({ Kind = "Commander", Side = side })
	end
end

myGate.MouseButton2Click:Connect(function()
	inspectGate("Self")
end)
enemyGate.MouseButton2Click:Connect(function()
	inspectGate("Enemy")
end)
enemyGate.Activated:Connect(function()
	if not inspectGate("Enemy") and inspectMode then
		inspectMode = false
		render()
	end
end)
myCommander.MouseButton2Click:Connect(function()
	inspectCommander("Self")
end)
enemyCommander.MouseButton2Click:Connect(function()
	inspectCommander("Enemy")
end)
enemyCommander.Activated:Connect(function()
	inspectCommander("Enemy")
end)

inspectButton.Activated:Connect(function()
	if not current then
		return
	end
	inspectMode = not inspectMode
	render()
end)
inspectFrame.Activated:Connect(closeInspect)
inspectClose.Activated:Connect(closeInspect)

myGate.Activated:Connect(function()
	if inspectMode then
		if not inspectGate("Self") then
			inspectMode = false
			render()
		end
		return
	end
	if not isMyTurn() then
		return
	end
	if current.State.Players[current.Seat].StarGate.OnBoard then
		flashMessage = "Your Celestial is already on the board."
		render()
		return
	end
	if selected and selected.Kind == "Celestial" then
		selectThing(nil)
	else
		selectThing({ Kind = "Celestial", Hint = "Pick an empty lane for your Celestial." })
	end
end)

local function onAbilityClicked()
	if inspectMode then
		inspectCommander("Self")
		return
	end
	if not isMyTurn() then
		return
	end
	if selected and selected.Kind == "Ability" then
		selectThing(nil)
		return
	end
	local commander = CardDatabase.GetCard(current.State.Players[current.Seat].CommanderId)
	selectThing({ Kind = "Ability", Hint = commander.CommanderAbility.Text .. " Pick the unit." })
end
abilityButton.Activated:Connect(onAbilityClicked)
myCommander.Activated:Connect(onAbilityClicked)

sparkButton.Activated:Connect(function()
	if isMyTurn() then
		send({ Kind = "UseSpark" })
	end
end)

endTurnButton.Activated:Connect(function()
	if isMyTurn() then
		selected = nil
		send({ Kind = "EndTurn" })
	end
end)

-- Leaving mid-match forfeits, so ask first
confirmFrame = make("TextButton", {
	Name = "LeaveConfirm",
	Text = "",
	AutoButtonColor = false,
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.35,
	Visible = false,
	ZIndex = 25,
}, gui)
local confirmPanel = make("Frame", {
	Name = "ConfirmPanel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.36, 0.26),
	BackgroundColor3 = PANEL,
	BorderSizePixel = 0,
	ZIndex = 25,
}, confirmFrame)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, confirmPanel)
local confirmText = label(confirmPanel, {
	Name = "ConfirmText",
	Position = UDim2.fromScale(0.08, 0.1),
	Size = UDim2.fromScale(0.84, 0.42),
	TextWrapped = true,
	ZIndex = 26,
	Text = "Leave the match?\nYou'll forfeit and your opponent wins.",
})
local confirmYes = button(confirmPanel, "LeaveConfirmYes", "Leave", UDim2.fromScale(0.08, 0.62), UDim2.fromScale(0.39, 0.26),
	TINT.Yes)
local confirmNo = button(confirmPanel, "LeaveConfirmNo", "Keep playing", UDim2.fromScale(0.53, 0.62),
	UDim2.fromScale(0.39, 0.26), TINT.Inspect)

leaveButton.Activated:Connect(function()
	local series = current and current.Series
	local midSeries = series ~= nil and not series.Over and series.BestOf > 1
	if current and (not current.State.Winner or midSeries) then
		confirmText.Text = midSeries and "Leave the match?\nYou'll forfeit the whole series."
			or "Leave the match?\nYou'll forfeit and your opponent wins."
		confirmFrame.Visible = true
	else
		send({ Kind = "Leave" }) -- the match is over: nothing to forfeit
	end
end)
confirmYes.Activated:Connect(function()
	confirmFrame.Visible = false
	send({ Kind = "Leave" })
end)
confirmNo.Activated:Connect(function()
	confirmFrame.Visible = false
end)
confirmFrame.Activated:Connect(function()
	confirmFrame.Visible = false
end)

updatePlates()
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updatePlates)

waitingLeave.Activated:Connect(function()
	send({ Kind = "Leave" })
end)

pickerLeave.Activated:Connect(function()
	send({ Kind = "Leave" })
end)

local pickerError = label(pickerFrame, {
	Name = "PickerError",
	Position = UDim2.fromScale(0.1, 0.125),
	Size = UDim2.fromScale(0.8, 0.035),
	ZIndex = 6,
	TextColor3 = Color3.fromRGB(255, 140, 140),
	Text = "",
})

local function showDeckPicker(decks)
	clear(pickerList)
	pickerError.Text = ""
	local grid = make("UIGridLayout", {
		CellSize = UDim2.new(0.31, 0, 0, 170),
		CellPadding = UDim2.new(0.02, 0, 0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, pickerList)
	if #decks == 0 then
		pickerError.Text = "You don't have a deck yet. Visit the Card Shop to claim your free starter deck!"
	end
	for i, deck in ipairs(decks) do
		local b = make("TextButton", {
			Name = "Deck_" .. deck.Key,
			Text = "",
			LayoutOrder = i,
			AutoButtonColor = deck.Legal,
			BackgroundColor3 = FACTION_COLORS[deck.Faction] or FACTION_COLORS.Neutral,
			BackgroundTransparency = deck.Legal and 0 or 0.6,
			ZIndex = 6,
		}, pickerList)
		make("UICorner", { CornerRadius = UDim.new(0.05, 0) }, b)
		label(b, {
			Name = "DeckName",
			Position = UDim2.fromScale(0.05, 0.04),
			Size = UDim2.fromScale(0.9, 0.2),
			ZIndex = 6,
			Text = deck.Name,
		})
		label(b, {
			Name = "DeckInfo",
			Position = UDim2.fromScale(0.07, 0.28),
			Size = UDim2.fromScale(0.86, 0.66),
			Font = Enum.Font.Gotham,
			TextWrapped = true,
			ZIndex = 6,
			TextColor3 = deck.Legal and WHITE or Color3.fromRGB(255, 190, 190),
			Text = ("%s\n\nCommander: %s\nCelestial: %s"):format(deck.Description, deck.Commander, deck.Celestial),
		})
		b.Activated:Connect(function()
			if not deck.Legal then
				pickerError.Text = deck.Name .. " isn't ready yet: " .. deck.Description
				return
			end
			send({ Kind = "ChooseDeck", Deck = deck.Key, BestOf = chosenFormat })
		end)
	end
end

---------------------------------------------------------------------
-- Updates from the server
---------------------------------------------------------------------
updateRemote.OnClientEvent:Connect(function(payload)
	if payload.Kind == "ChooseDeck" then
		gui.Enabled = true
		showBoard(false)
		waitingFrame.Visible = false
		pickerFrame.Visible = true
		vsBotPicker = payload.VsBot == true
		opponentVote = payload.OpponentVote
		refreshFormat()
		showDeckPicker(payload.Decks)
	elseif payload.Kind == "OpponentVote" then
		opponentVote = payload.BestOf
		refreshFormat()
	elseif payload.Kind == "Waiting" then
		gui.Enabled = true
		showBoard(false)
		pickerFrame.Visible = false
		waitingFrame.Visible = true
		waitingLabel.Text = payload.Message
	elseif payload.Kind == "Match" then
		-- once per game: list the finishes the server sent (shows in Studio's Output window)
		if payload.Finishes and payload.State and payload.State.Turn ~= lastFinishReport then
			if not lastFinishReport or payload.State.Turn < lastFinishReport then
				local counts, total = {}, 0
				for _, finish in pairs(payload.Finishes.Mine or {}) do
					counts[finish] = (counts[finish] or 0) + 1
					total = total + 1
				end
				local parts = {}
				for finish, n in pairs(counts) do
					table.insert(parts, ("%s x%d"):format(finish, n))
				end
				print(("[Battle] Your deck's finishes this game: %s"):format(total > 0 and table.concat(parts, ", ")
					or "all Standard (you don't own shiny copies of these cards, or picked Standard)"))
			end
			lastFinishReport = payload.State.Turn
		end
		queueUpdate(payload)
	elseif payload.Kind == "Reward" then
		local function showReward()
			if payload.Coins > 0 then
				addLog(("You earned %d coins."):format(payload.Coins))
			else
				addLog("No coins this time (daily limit reached, or the match was very short).")
			end
		end
		if queueRunning then
			table.insert(updateQueue, showReward) -- after the game-ending animation
		else
			showReward()
		end
	elseif payload.Kind == "DeckError" then
		pickerError.Text = payload.Message
	elseif payload.Kind == "Error" then
		flashMessage = payload.Message
		if animating then
			statusLabel.Text = payload.Message
		else
			render()
		end
	elseif payload.Kind == "Closed" then
		for i = #updateQueue, 1, -1 do
			table.remove(updateQueue, i)
		end
		queueGeneration = queueGeneration + 1
		gui.Enabled = false
		pickerFrame.Visible = false
		waitingFrame.Visible = false
		current = nil
		selected = nil
		confirmFrame.Visible = false
		inspectMode = false
		closeInspect()
		logLines = {}
		logLabel.Text = ""
	end
end)