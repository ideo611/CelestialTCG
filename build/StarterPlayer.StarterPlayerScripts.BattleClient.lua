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
local UiAssets = require(ReplicatedStorage:WaitForChild("UiAssets"))
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
local PLATE = {} -- (grouped to stay under Luau's 200-local limit)
PLATE.BUTTON_PLATE = "rbxassetid://134304204813444"
PLATE.PLATE_SLICE = Rect.new(96, 96, 1440, 928) -- corners of the 1536 x 1024 plate image
PLATE.PLATE_CORNER = 96 -- source pixels in each corner piece
PLATE.PLATE_CORNER_SCREEN = 0.016 -- each corner is this much of the screen height

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
local playClick, playSoundEarly = nil, nil -- set once the sounds are loaded (further down)

local function button(parent, name, text, position, size, tint)
	local b = make("ImageButton", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Image = PLATE.BUTTON_PLATE,
		ImageColor3 = tint or TINT.Default,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = PLATE.PLATE_SLICE,
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
	make("UITextSizeConstraint", { MaxTextSize = 34, MinTextSize = 10 }, b.Label)
	require(ReplicatedStorage:WaitForChild("Fonts")).Set(b.Label, "Button") -- (no new local: this script is at Luau's limit)
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
local ZONE = {} -- (grouped to stay under Luau's 200-local limit)
ZONE.ZONE_TILE = "rbxassetid://91092773801634"
ZONE.ZONE_INSET_X = 0.07
ZONE.ZONE_INSET_Y = 0.05
ZONE.ZONE_EXTRA_Y = ENEMY_ROW[2] * ZONE.ZONE_INSET_Y / (1 - 2 * ZONE.ZONE_INSET_Y) -- how far a tile reaches past its card
ZONE.DASH_FAINT = 0.45 -- lane dashes: 0 = solid, 1 = invisible
ZONE.DASH_COUNT = 5 -- dashes between each pair of opposing lanes

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
		Size = UDim2.fromScale(w * 2, h / (1 - 2 * ZONE.ZONE_INSET_Y)), -- the height sets the size
		BackgroundTransparency = 1,
		Image = ZONE.ZONE_TILE,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 4,
	}, tableFrame)
	make("UIAspectRatioConstraint", {
		AspectRatio = CARD_ASPECT * (1 - 2 * ZONE.ZONE_INSET_Y) / (1 - 2 * ZONE.ZONE_INSET_X),
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
		Position = enemy and UDim2.fromScale(x, ENEMY_ROW[1] + ENEMY_ROW[2] + ZONE.ZONE_EXTRA_Y + 0.002)
			or UDim2.fromScale(x, MY_ROW[1] - ZONE.ZONE_EXTRA_Y - 0.002),
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
local GAP_TOP = ENEMY_ROW[1] + ENEMY_ROW[2] + ZONE.ZONE_EXTRA_Y
local GAP = MY_ROW[1] - ZONE.ZONE_EXTRA_Y - GAP_TOP
for lane = 1, #LANE_X do
	local line = make("Frame", {
		Name = "LaneDashes_" .. lane,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(LANE_X[lane] + LANE_W / 2, 0, GAP_TOP, 3),
		Size = UDim2.new(0, 3, GAP, -6),
		BackgroundTransparency = 1,
		ZIndex = 3,
	}, tableFrame)
	local pieces = ZONE.DASH_COUNT * 2 - 1
	for i = 1, ZONE.DASH_COUNT do
		local dash = make("Frame", {
			Name = "Dash_" .. i,
			Position = UDim2.fromScale(0, (i - 1) * 2 / pieces),
			Size = UDim2.fromScale(1, 1 / pieces),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = ZONE.DASH_FAINT,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, line)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dash)
		table.insert(laneDashes, { dash, (i - 1) / math.max(ZONE.DASH_COUNT - 1, 1) })
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
	local scale = height * PLATE.PLATE_CORNER_SCREEN / PLATE.PLATE_CORNER
	for _, b in ipairs(plates) do
		b.SliceScale = scale
		b.PlateCorner.CornerRadius = UDim.new(0, math.floor(PLATE.PLATE_CORNER * scale * 0.3))
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
	Size = UDim2.fromScale(0.6, 0.047),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})

local statusLabel = label(root, {
	Name = "Status",
	-- Right above your hand, where your eyes already are
	Position = UDim2.fromScale(0.53, 0.683),
	Size = UDim2.fromScale(0.215, 0.04),
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
UiAssets.FramePanel(logFrame)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, logFrame)
-- (a box the log can't spill out of: the newest lines sit at the bottom and
-- older ones scroll off the top)
local logLabel = label(make("Frame", {
	Name = "LogClip",
	Position = UDim2.fromScale(0.05, 0.03),
	Size = UDim2.fromScale(0.9, 0.82),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
}, logFrame), {
	Name = "LogText",
	Size = UDim2.fromScale(1, 1),
	TextScaled = false,
	TextSize = 14,
	TextWrapped = true,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Bottom,
	Text = "",
})
-- smaller text on short (phone) screens
do
	local function fitLogText()
		local camera = workspace.CurrentCamera
		local h = camera and camera.ViewportSize.Y or 900
		logLabel.TextSize = h > 0 and math.clamp(math.floor(h / 64), 10, 14) or 14
	end
	fitLogText()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitLogText)
	end
end

-- The card you picked from your hand, shown big over the log (so you can read
-- it before choosing where it goes; on a phone the hand cards are small)
local PICK = { CardId = nil } -- (one table: this script is near Luau's 200-local limit)
PICK.Frame = make("Frame", {
	Name = "PickPreview",
	Position = UDim2.fromScale(0.76, 0.065),
	Size = UDim2.fromScale(0.225, 0.43),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 3,
}, root)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, PICK.Frame)

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
	Size = UDim2.fromScale(0.29, 0.045),
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
		UDim2.fromScale(0.1 + (i - 1) * 0.125, 0.17), UDim2.fromScale(0.115, 0.06), TINT.Grey)
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
-- Practice bot difficulty: Easy (default), Normal or Hard
local chosenDifficulty = "Easy"
local difficultyButtons = {}
for i, info in ipairs({ { "Easy", "Easy bot" }, { "Normal", "Normal bot" }, { "Hard", "Hard bot" } }) do
	local b = button(pickerFrame, "Bot" .. info[1], info[2],
		UDim2.fromScale(0.515 + (i - 1) * 0.13, 0.17), UDim2.fromScale(0.12, 0.06), TINT.Grey)
	b.ZIndex = 6
	b.Visible = false
	difficultyButtons[info[1]] = b
end
local opponentVote = nil

local function refreshFormat()
	for bestOf, b in pairs(formatButtons) do
		setTint(b, bestOf == chosenFormat and TINT.Inspect or TINT.Grey)
		setStroke(b, bestOf == chosenFormat and HIGHLIGHT or nil, 2)
	end
	for difficulty, b in pairs(difficultyButtons) do
		b.Visible = vsBotPicker
		b.ImageColor3 = difficulty == chosenDifficulty and (difficulty == "Hard" and TINT.EndTurn or TINT.Inspect)
			or TINT.Grey
		setStroke(b, difficulty == chosenDifficulty and HIGHLIGHT or nil, 2)
	end
	if vsBotPicker then
		formatNote.Text = chosenDifficulty == "Hard"
			and "How many games? Hard bot plans ahead and plays to win."
			or chosenDifficulty == "Normal" and "How many games? Normal bot plays a fair game. Try Hard for a challenge."
			or "How many games? Easy bot is great for learning. Try Normal or Hard when you're ready."
	else
		local theirs = opponentVote and ("Opponent voted best of " .. opponentVote .. ".")
			or "Opponent hasn't voted yet."
		-- the opponent's deck format, once they've picked (a Zenith deck vs an Open deck plays as Open)
		local theirFormat = pickerFrame:GetAttribute("OpponentDeckFormat")
		if theirFormat then
			theirs = theirs .. " Their deck is " .. theirFormat .. "."
		end
		formatNote.Text = "Vote for a format. If you disagree, the shorter series is played.  " .. theirs
	end
end
for bestOf, b in pairs(formatButtons) do
	b.Activated:Connect(function()
		chosenFormat = bestOf
		refreshFormat()
	end)
end
for difficulty, b in pairs(difficultyButtons) do
	b.Activated:Connect(function()
		chosenDifficulty = difficulty
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

-- Victory / Defeat banner above the game-over text
local showResultBanner
do
	local resultBanner = make("ImageLabel", {
		Name = "ResultBanner",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.44, 0.275),
		Size = UDim2.fromScale(0.5, 0.2),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 5,
		Visible = false,
	}, root)
	local shownResult -- "Victory" / "Defeat" while showing, so it only pops in once
	showResultBanner = function(kind)
		local image = kind and UiAssets[kind]
		if not image then
			resultBanner.Visible = false
			shownResult = nil
			return
		end
		resultBanner.Image = image
		resultBanner.Visible = true
		if shownResult ~= kind then
			shownResult = kind
			resultBanner.Size = UDim2.fromScale(0.3, 0.12)
			TweenService:Create(resultBanner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Size = UDim2.fromScale(0.5, 0.2) }):Play()
			-- a short burst of light behind the banner (gold for a win, a cool fade for a loss)
			local won = kind == "Victory"
			local glow = make("Frame", {
				Name = "ResultFlash",
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = won and Color3.fromRGB(255, 215, 120) or Color3.fromRGB(20, 20, 50),
				BackgroundTransparency = won and 0.55 or 0.4,
				BorderSizePixel = 0,
				ZIndex = 4,
			}, root)
			TweenService:Create(glow, TweenInfo.new(won and 0.7 or 1.2), { BackgroundTransparency = 1 }):Play()
			task.delay(1.3, function()
				glow:Destroy()
			end)
			if won then
				UiAssets.PlayFlipbook(root, UiAssets.Vfx.LegendaryPull, {
					Position = UDim2.fromScale(0.44, 0.18),
					Size = UDim2.fromScale(0.42, 0.42),
					Duration = 1.1,
					ZIndex = 4,
				})
				UiAssets.PlayFlipbook(root, UiAssets.Vfx.ImpactBurst, {
					Position = UDim2.fromScale(0.44, 0.18),
					Size = UDim2.fromScale(0.3, 0.3),
					Duration = 0.6,
					ZIndex = 6,
				})
			end
		end
	end
end

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
UiAssets.FramePanel(inspectPanel)
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
local showInspect, refreshInspect, keywordLines

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
	elseif t == "Mulligan" then
		if (event.Count or 0) == 0 then
			return who(event.Player) .. (event.Player == current.Seat and " kept your hand." or " kept their hand.")
		end
		return ("%s sent back %d card%s and drew new ones."):format(who(event.Player), event.Count,
			event.Count == 1 and "" or "s")
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
		return ("%s took %d damage%s."):format(who(event.Player), event.Amount, event.Streak and " (Streak)" or "")
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
	elseif t == "UnitGrew" then
		return ("A unit grew to %d Power."):format(event.Power)
	elseif t == "GrowGained" then
		return ("A unit now has Grow %d."):format(event.Grow)
	elseif t == "Decay" then
		return ("Decay dealt %d."):format(event.Amount)
	elseif t == "UnitWeakened" then
		return ("A unit lost %d Power."):format(event.Amount)
	elseif t == "StreakGained" then
		return "A unit got Streak this turn."
	elseif t == "UnitReturned" then
		return cardName(event.CardId) .. (event.ToGate and " went back to the Star Gate." or (" went back to " .. (event.Player == current.Seat and "your" or "their") .. " hand."))
	elseif t == "UnitDestroyedByEffect" then
		return nil
	elseif t == "CommanderPaidHP" then
		return ("%s paid %d HP."):format(who(event.Player), event.Amount)
	elseif t == "EnergyGained" then
		return ("%s gained %d energy."):format(who(event.Player), event.Amount)
	elseif t == "SparkUsed" then
		return who(event.Player) .. " used Spark."
	elseif t == "CommanderAbility" then
		return who(event.Player) .. (event.Player == current.Seat and " used your" or " used their") .. " Commander ability."
	elseif t == "AnomalySet" then
		if event.Player == current.Seat and event.CardId then
			return "You set " .. cardName(event.CardId) .. " face-down."
		end
		return who(event.Player) .. " set an Anomaly face-down."
	elseif t == "AnomalyTriggered" then
		return ("%s Anomaly flips: %s!"):format(event.Player == current.Seat and "Your" or (who(event.Player) .. "'s"),
			cardName(event.CardId))
	elseif t == "SpellCancelled" then
		return cardName(event.CardId) .. " was cancelled!"
	elseif t == "DamagePrevented" then
		return ("The attack on %s was stopped."):format(event.Player == current.Seat and "you" or who(event.Player))
	elseif t == "UnitFrozen" then
		return "A unit was frozen: it skips its next attack."
	elseif t == "UnitThawed" then
		return "A frozen unit skipped its attack and thawed."
	elseif t == "CardRecovered" then
		return cardName(event.CardId) .. " went back to " .. (event.Player == current.Seat and "your" or "their") .. " hand."
	elseif t == "DeckEmpty" then
		return who(event.Player) .. " has no cards left to draw."
	elseif t == "MatchOver" then
		return who(event.Winner) .. (event.Winner == current.Seat and " win!" or " wins.")
	end
	return nil
end

-- What clicking a lane means right now: "Place", "AnyUnit", "FriendlyUnit", "EnemyUnit" or nil
local function targetMode()
	if not selected or not current then
		return nil
	end
	if selected.Kind == "Celestial" then
		return "Place"
	elseif selected.Kind == "Ability" then
		local commander = CardDatabase.GetCard(current.State.Players[current.Seat].CommanderId)
		return commander.CommanderAbility.Effect.Target
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

-- Each keyword by name with what it does, then the card's own text
keywordLines = function(card, unit, lines)
	for _, entry in ipairs(CardVisuals.KeywordEntries(card, unit)) do
		local title, info = CardVisuals.KeywordExplain(entry)
		table.insert(lines, ("<b>%s</b>: %s"):format(title, esc(info)))
	end
	local rest = CardVisuals.AbilityOnlyText(card)
	if rest ~= "" then
		table.insert(lines, esc(rest))
	end
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
	if unit.Intercept then
		table.insert(lines, "<b>Intercept</b>: Streak units can't fly past it; they have to fight it")
	end
	if unit.Ignite and unit.Ignite > 0 then
		table.insert(lines, ("<b>Ignite %d</b>: hit the unit across for %d when played"):format(unit.Ignite, unit.Ignite))
	end
	if unit.Regen and unit.Regen > 0 then
		table.insert(lines, ("<b>Regen %d</b>: heals %d at the end of each turn"):format(unit.Regen, unit.Regen))
	end
	if unit.Grow and unit.Grow > 0 then
		table.insert(lines, ("<b>Grow %d</b>: +%d Power for good at the start of each of its owner's turns"):format(unit.Grow, unit.Grow))
	end
	if unit.Decay and unit.Decay > 0 then
		table.insert(lines, ("<b>Decay %d</b>: at the end of its owner's turn, the enemy unit across takes %d"):format(unit.Decay, unit.Decay))
	end
	if unit.Streak then
		table.insert(lines, ("<b>Streak</b>%s: attacks the enemy Commander directly, past the unit across (unless it has Streak or Intercept)")
			:format(unit.StreakThisTurn and " (this turn)" or ""))
	end
	if unit.Frozen then
		table.insert(lines, colored(BAD, "<b>Frozen</b>: skips its next attack, then thaws"))
	elseif side == "Self" then
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
	keywordLines(card, nil, lines)
	table.insert(lines, "")
	table.insert(lines, colored(DIMTEXT, ("Each time it's destroyed it returns here and costs %d more to summon.")
		:format(CardDatabase.Rules.CelestialTax)))
end

local function cardDetails(cardId, lines)
	local card = CardDatabase.GetCard(cardId)
	local typeLine = card.Type
	if CardDatabase.IsMainDeckType(card.Type) then
		typeLine = card.Faction .. " " .. card.Type
	end
	table.insert(lines, colored(DIMTEXT, ("%s  |  %s"):format(typeLine, card.Rarity)))
	if card.Type == "Anomaly" then
		table.insert(lines, "")
		table.insert(lines, ("<b>Anomaly</b>: set it face-down in one of your %d Anomaly slots. It flips up during your opponent's turn the first time this happens: %s."):format(
			CardDatabase.Rules.AnomalySlots, (CardDatabase.AnomalyTriggers[card.Trigger] or "?"):lower()))
	end
	table.insert(lines, "")
	if card.EnergyCost then
		table.insert(lines, ("<b>Cost %d energy</b>"):format(card.EnergyCost))
	end
	if card.Power then
		table.insert(lines, ("<b>Power %d / Health %d</b>"):format(card.Power, card.HP))
	end
	table.insert(lines, "")
	keywordLines(card, nil, lines)
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
		drawOptions.Finish = finishFor(what.Side or "Self", cardId) -- a card in a hand or graveyard
		if what.Note then
			table.insert(lines, colored("#AAA0C8", what.Note))
			table.insert(lines, "")
		end
		cardDetails(cardId, lines)
	end
	-- which finish this copy shows (so you can tell your picks made it into the match)
	table.insert(lines, "")
	table.insert(lines, colored("#AAA0C8",
		"Finish: " .. (CardVisuals.FinishNames[drawOptions.Finish or "Base"] or "Standard")))
	clear(inspectCard)
	CardVisuals.Draw(inspectCard, cardId, drawOptions)
	CardVisuals.MakeHandheld(inspectCard) -- (once; hold the mouse on it to move the light around)
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

---------------------------------------------------------------------
-- Graveyards: every spell cast and unit destroyed, for both sides, so you
-- can look back at what happened. Newest first; click one to inspect it.
---------------------------------------------------------------------
local refreshGraveyard -- (also called from render)
do
	local showing = nil -- "Self" / "Enemy" while the window is open
	local overlay = make("TextButton", {
		Name = "Graveyard",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.3,
		Visible = false,
		ZIndex = 18,
	}, gui)
	local panel = make("Frame", {
		Name = "GraveyardPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromScale(0.78, 0.8),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		ZIndex = 18,
	}, overlay)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
	UiAssets.FramePanel(panel)
	local title = label(panel, {
		Name = "GraveyardTitle",
		Position = UDim2.fromScale(0.03, 0.02),
		Size = UDim2.fromScale(0.94, 0.07),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = HIGHLIGHT,
		ZIndex = 19,
		Text = "",
	})
	local grid = make("ScrollingFrame", {
		Name = "GraveyardCards",
		Position = UDim2.fromScale(0.02, 0.11),
		Size = UDim2.fromScale(0.96, 0.86),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ZIndex = 19,
	}, panel)
	local switch = button(overlay, "GraveyardSwitch", "", UDim2.fromScale(0.11, 0.895), UDim2.fromScale(0.3, 0.065),
		TINT.Inspect)
	switch.ZIndex = 19
	local close = button(overlay, "GraveyardClose", "Close", UDim2.fromScale(0.59, 0.895), UDim2.fromScale(0.3, 0.065),
		TINT.Grey)
	close.ZIndex = 19

	local theirButton = button(root, "TheirGraveyard", "", UDim2.fromScale(0.62, 0.012), UDim2.fromScale(0.125, 0.04),
		TINT.Grey)
	local myButton = button(root, "MyGraveyard", "", UDim2.fromScale(0.31, 0.683), UDim2.fromScale(0.088, 0.038),
		TINT.Grey)

	local function draw()
		if not showing or not current then
			overlay.Visible = false
			return
		end
		local seat = current.Seat
		local who = current.State.Players[showing == "Self" and seat or 3 - seat]
		local list = who.Discard or {}
		local name = showing == "Self" and "Your" or ((current.Names[3 - seat] or "Opponent") .. "'s")
		title.Text = ("%s graveyard: %d card%s, newest first"):format(name, #list, #list == 1 and "" or "s")
		setLabel(switch, showing == "Self" and "Show their graveyard" or "Show your graveyard")
		clear(grid)
		local layout = make("UIGridLayout", {
			CellSize = UDim2.new(0.135, 0, 0.5, 0),
			CellPadding = UDim2.new(0.01, 0, 0, 30),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, grid)
		-- every cell keeps the card shape (a constraint under a grid layout applies to its cells)
		make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, layout)
		if #list == 0 then
			label(grid, { Name = "Empty", Size = UDim2.new(1, 0, 0, 40), ZIndex = 19, TextScaled = false, TextSize = 20,
				Text = "Nothing here yet. Spells and destroyed units go here." })
		end
		for i = #list, 1, -1 do
			local cardId = list[i]
			local cell = make("TextButton", {
				Name = "Grave_" .. i,
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				LayoutOrder = #list - i,
				ZIndex = 19,
			}, grid)
			CardVisuals.Draw(cell, cardId, { Finish = finishFor(showing, cardId) })
			label(cell, { Name = "Order", Position = UDim2.new(0, 0, 1, 2), Size = UDim2.new(1, 0, 0, 22), ZIndex = 19,
				TextScaled = false, TextSize = 16, Text = ("#%d"):format(i) })
			local side = showing
			cell.Activated:Connect(function()
				showInspect({ CardId = cardId, Side = side,
					Note = ("In the graveyard (card #%d of %d to get there)."):format(i, #list) })
			end)
		end
		overlay.Visible = true
	end

	refreshGraveyard = function()
		if not current then
			return
		end
		local seat = current.Seat
		local mine = current.State.Players[seat].Discard or {}
		local theirs = current.State.Players[3 - seat].Discard or {}
		setLabel(theirButton, ("Their graveyard (%d)"):format(#theirs))
		setLabel(myButton, ("Graveyard (%d)"):format(#mine))
		if showing then
			draw()
		end
	end

	local function open(side)
		showing = side
		draw()
		if playSoundEarly then
			playSoundEarly("Graveyard")
		end
	end
	theirButton.Activated:Connect(function() open("Enemy") end)
	myButton.Activated:Connect(function() open("Self") end)
	switch.Activated:Connect(function() open(showing == "Self" and "Enemy" or "Self") end)
	close.Activated:Connect(function()
		showing = nil
		overlay.Visible = false
	end)
	overlay.Activated:Connect(function()
		showing = nil
		overlay.Visible = false
	end)
end

---------------------------------------------------------------------
-- Anomaly slots: small face-down tiles next to each graveyard button.
-- Yours show which Anomaly you set (click to read it); theirs only show
-- that something is there.
---------------------------------------------------------------------
local playEvent = {} -- one animation function per event type (filled in further down)
do
	local VIOLET = Color3.fromRGB(150, 90, 230)
	local chips = { Self = {}, Enemy = {} }
	playEvent._anomalyChips = chips
	for slotNo = 1, CardDatabase.Rules.AnomalySlots do
		local enemyChip = button(root, "EnemyAnomaly" .. slotNo, "", UDim2.fromScale(0.75 + (slotNo - 1) * 0.0625, 0.012),
			UDim2.fromScale(0.058, 0.04), TINT.Grey)
		local myChip = button(root, "MyAnomaly" .. slotNo, "", UDim2.fromScale(0.405 + (slotNo - 1) * 0.0625, 0.683),
			UDim2.fromScale(0.058, 0.038), TINT.Grey)
		-- centered like the card slots (the board resets every slot to its center after animations)
		for _, chip in ipairs({ enemyChip, myChip }) do
			chip.AnchorPoint = Vector2.new(0.5, 0.5)
			chip.Position = chip.Position + UDim2.fromScale(0.029, chip == enemyChip and 0.02 or 0.019)
		end
		chips.Enemy[slotNo] = enemyChip
		chips.Self[slotNo] = myChip
		slotBase[enemyChip] = { X = 0.779 + (slotNo - 1) * 0.0625, Y = 0.032, W = 0.058, H = 0.04 }
		slotBase[myChip] = { X = 0.434 + (slotNo - 1) * 0.0625, Y = 0.702, W = 0.058, H = 0.038 }
		myChip.Activated:Connect(function()
			local list = current and current.State.Players[current.Seat].Anomalies
			local set = list and list[slotNo]
			if set and set.CardId then
				showInspect({ CardId = set.CardId, Side = "Self",
					Note = "Set face-down. It flips up on your opponent's turn when its condition happens." })
			end
		end)
		enemyChip.Activated:Connect(function()
			local list = current and current.State.Players[3 - current.Seat].Anomalies
			if list and list[slotNo] then
				flashMessage = "A face-down Anomaly: it can flip up during your turn. You won't know which until it does."
				render()
			end
		end)
	end

	function playEvent._refreshAnomalies()
		for _, side in ipairs({ "Self", "Enemy" }) do
			local seat = current and (side == "Self" and current.Seat or 3 - current.Seat)
			local list = seat and current.State.Players[seat].Anomalies or {}
			for slotNo, chip in ipairs(chips[side]) do
				local set = list[slotNo]
				chip.Visible = current ~= nil and CardDatabase.Rules.AnomaliesEnabled ~= false
				if set then
					local name = set.CardId and cardName(set.CardId) or "Anomaly ?"
					setLabel(chip, name)
					setTint(chip, TINT.Inspect)
					setStroke(chip, VIOLET, 2)
				else
					setLabel(chip, "Anomaly slot")
					setTint(chip, TINT.Grey, false)
					setStroke(chip, nil)
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Mulligan: at the start of each game you see your opening hand, click the
-- cards you want to send back, and draw that many new ones.
---------------------------------------------------------------------
local refreshMulligan -- (called from render)
do
	local MULLIGAN_SECONDS = 30 -- matches the server's limit
	local picked = {}          -- [hand index] = true
	local shownFor = nil       -- the game (state table) the picks belong to
	local openedAt = 0
	local overlay = make("Frame", {
		Name = "Mulligan",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.25,
		Active = true, -- blocks clicks to the board underneath
		Visible = false,
		ZIndex = 17,
	}, gui)
	local title = label(overlay, {
		Name = "MulliganTitle",
		Position = UDim2.fromScale(0.1, 0.08),
		Size = UDim2.fromScale(0.8, 0.08),
		TextColor3 = HIGHLIGHT,
		ZIndex = 18,
		Text = "Choose your starting hand",
	})
	local hint = label(overlay, {
		Name = "MulliganHint",
		Position = UDim2.fromScale(0.15, 0.17),
		Size = UDim2.fromScale(0.7, 0.045),
		Font = Enum.Font.Gotham,
		ZIndex = 18,
		Text = "",
	})
	local row = make("Frame", {
		Name = "MulliganCards",
		Position = UDim2.fromScale(0.04, 0.26),
		Size = UDim2.fromScale(0.92, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 18,
	}, overlay)
	local confirm = button(overlay, "MulliganConfirm", "Keep this hand", UDim2.fromScale(0.35, 0.82),
		UDim2.fromScale(0.3, 0.08), TINT.EndTurn)
	confirm.ZIndex = 18

	local function count()
		local n = 0
		for _ in pairs(picked) do
			n = n + 1
		end
		return n
	end

	local function draw()
		local me = current.State.Players[current.Seat]
		local hand = me.Hand or {}
		clear(row)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0.012, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, row)
		local width = math.min(0.15, 0.95 / math.max(1, #hand) - 0.012)
		for i, cardId in ipairs(hand) do
			local cell = make("TextButton", {
				Name = "MulliganCard_" .. i,
				Text = "",
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(width, 1),
				LayoutOrder = i,
				ZIndex = 18,
			}, row)
			make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, cell)
			CardVisuals.Draw(cell, cardId, { Finish = finishFor("Self", cardId), Dim = picked[i] == true })
			if picked[i] then
				local tag = label(cell, {
					Name = "SendBack",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.45),
					Size = UDim2.fromScale(1.05, 0.16),
					BackgroundTransparency = 0.1,
					BackgroundColor3 = Color3.fromRGB(150, 30, 40),
					ZIndex = 19,
					Text = "SEND BACK",
				})
				tag.Rotation = -12
			end
			cell.Activated:Connect(function()
				picked[i] = not picked[i] or nil
				draw()
			end)
		end
		local n = count()
		setLabel(confirm, n == 0 and "Keep this hand" or ("Send back %d & draw %d"):format(n, n))
		local left = math.max(0, math.ceil(MULLIGAN_SECONDS - (os.clock() - openedAt)))
		hint.Text = ("Click cards to send them back to your deck; you'll draw that many new ones. (%ds)"):format(left)
	end

	refreshMulligan = function()
		local state = current and current.State
		local me = state and state.Players[current.Seat]
		local open = state and state.Phase == "Mulligan" and me and not me.MulliganDone and not state.Winner
			and not gui:GetAttribute("IntroPlaying") -- (after the Commander intro)
		if not open then
			overlay.Visible = false
			return
		end
		if shownFor ~= state.Players then
			-- a new game's opening hand (or a fresh state): start from no picks
			if not overlay.Visible then
				picked = {}
				openedAt = os.clock()
			end
		end
		shownFor = state.Players
		overlay.Visible = true
		draw()
	end

	confirm.Activated:Connect(function()
		local indexes = {}
		for i in pairs(picked) do
			table.insert(indexes, i)
		end
		table.sort(indexes)
		send({ Kind = "Mulligan", Indexes = indexes })
		if #indexes > 0 and playSoundEarly then
			playSoundEarly("Shuffle")
		end
		overlay.Visible = false
		picked = {}
	end)

	-- keep the countdown ticking
	task.spawn(function()
		while true do
			task.wait(1)
			if overlay.Visible and current then
				local left = math.max(0, math.ceil(MULLIGAN_SECONDS - (os.clock() - openedAt)))
				hint.Text = ("Click cards to send them back to your deck; you'll draw that many new ones. (%ds)")
					:format(left)
			end
		end
	end)
end

local uidSlot = {} -- [unit Uid] = the lane slot showing it
local uidCard = {} -- [unit Uid] = its card id (for faction-colored hits)
-- [unit Uid] = faction of whoever is hitting it in the current attack
-- (or ALREADY_HIT when a projectile has already shown its impact there)
local hitBy = {}
local ALREADY_HIT = "AlreadyHit"
local function factionOfUid(uid)
	local card = uid and uidCard[uid] and CardDatabase.GetCard(uidCard[uid])
	return card and card.Faction or nil
end


function render()
	if not current or animating then
		return
	end
	for uid in pairs(uidSlot) do
		uidSlot[uid] = nil
	end
	table.clear(uidCard)
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
	elseif state.Phase == "Mulligan" then
		statusLabel.Text = me.MulliganDone and "Waiting for your opponent to choose their hand..."
			or "Choose your starting hand."
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
				uidCard[unit.Uid] = unit.CardId
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
				or (mode == "EnemyUnit" and side == "Enemy" and unit)
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
	refreshGraveyard()
	playEvent._refreshAnomalies()
	refreshMulligan()
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
		-- (touch: hold a card to inspect it, like right-click)
		require(ReplicatedStorage:WaitForChild("LongPress")).Attach(cardButton, function()
			showInspect({ CardId = cardId })
		end)
		-- drag the card onto a lane (or, for a spell with no target, up onto the board)
		require(ReplicatedStorage:WaitForChild("CardDrag")).Attach(cardButton, {
			Layer = root,
			CanDrag = function()
				return not inspectMode and isMyTurn() and card.EnergyCost <= me.Energy
					and not require(ReplicatedStorage:WaitForChild("LongPress")).Swallowed()
			end,
			MakeGhost = function(parent)
				drawCard(parent, cardId, nil, false, false, finishFor("Self", cardId))
			end,
			OnStart = function()
				local hint = card.Type == "Unit" and "Drop it on one of your empty lanes."
					or (card.Effect and card.Effect.Target and "Drop it on a unit." or "Drop it on the board.")
				selectThing({ Kind = "Hand", Index = i, CardId = cardId, Hint = hint })
			end,
			OnDrop = function(p)
				if not PICK.DragTracked then -- (once a session: do players find dragging?)
					PICK.DragTracked = true
					pcall(function() ReplicatedStorage.AnalyticsRemotes.Track:FireServer("card_dragged") end)
				end
				local untargeted = (card.Type == "Spell" and not card.Effect.Target) or card.Type == "Anomaly"
				if untargeted then
					if p.Y < handFrame.AbsolutePosition.Y then
						selected = nil
						send({ Kind = "PlayCard", HandIndex = i })
					else
						selectThing(nil)
					end
					return
				end
				if not PICK.DropOnLane(p) then
					selectThing(nil)
				end
			end,
		})
		cardButton.Activated:Connect(function()
			if require(ReplicatedStorage:WaitForChild("LongPress")).Swallowed()
				or require(ReplicatedStorage:WaitForChild("CardDrag")).Swallowed() then
				return
			end
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
			if (card.Type == "Spell" and not card.Effect.Target) or card.Type == "Anomaly" then
				selected = nil
				send({ Kind = "PlayCard", HandIndex = i })
				return
			end
			local hint = card.Type == "Unit" and "Pick one of your empty lanes."
				or (card.Effect.Target == "FriendlyUnit" and "Pick one of your units."
					or (card.Effect.Target == "EnemyUnit" and "Pick an enemy unit." or "Pick a unit to target."))
			selectThing({ Kind = "Hand", Index = i, CardId = cardId, Hint = hint })
		end)
	end

	-- the picked hand card, big
	local pickId = selected and selected.Kind == "Hand" and selected.CardId or nil
	if pickId ~= PICK.CardId then
		PICK.CardId = pickId
		clear(PICK.Frame)
		if pickId then
			local holder = make("Frame", {
				Name = "PickCard",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.94, 0.94),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, PICK.Frame)
			make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, holder)
			CardVisuals.Draw(holder, pickId, { Finish = finishFor("Self", pickId) })
		end
	end
	PICK.Frame.Visible = pickId ~= nil

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
		showResultBanner(won and "Victory" or "Defeat")
		-- the Victory / Defeat art says who won; the text only adds the series score
		if not series or series.BestOf == 1 then
			gameOverLabel.Text = ""
			gameOverLabel.Visible = false
		elseif seriesOver then
			gameOverLabel.Text = ("Series %d - %d"):format(myWins, theirWins)
		else
			gameOverLabel.Text = ("Series %d - %d\nNext game starting..."):format(myWins, theirWins)
		end
	else
		gameOverLabel.Visible = false
		showResultBanner(nil)
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
local soundOn = player:GetAttribute("BattleSound") ~= false
local soundObjects = {}
-- (in a do-block to keep this script under Luau's 200-local limit)
do
	local SOUND_IDS = {
		CardPlay = 99530512612399, -- sfx-card-play
		SpellCast = 118997144378690, -- sfx-spell-cast
		AttackSwing = 113022946458116, -- sfx-attack-swing
		Hit = 72142437878137, -- sfx-hit
		CommanderHit = 93888405596507, -- sfx-commander-hit
		ShieldBreak = 74740292357815, -- sfx-shield-break
		Heal = 111256243010918, -- sfx-heal
		Buff = 117637608554977, -- sfx-buff
		UnitDestroyed = 107945558103139, -- sfx-unit-destroyed
		CelestialSummon = 74958212851560, -- sfx-celestial-summon
		Storm = 100480453851276, -- sfx-storm
		YourTurn = 93351750724443, -- sfx-your-turn
		Victory = 125505262013368, -- sfx-victory
		Defeat = 134623258622195, -- sfx-defeat
		Click = 122156579013227, -- sfx-click
		CardDraw = 135339664520680, -- sfx-card-draw
		Shuffle = 94170282943509, -- sfx-shuffle
		ShieldUp = 79888703218563, -- sfx-shield-up
		Ignite = 117965049353033, -- sfx-ignite
		Grow = 109733746949118, -- sfx-grow
		Weaken = 110703021057839, -- sfx-weaken
		Decay = 93653793862638, -- sfx-decay
		Streak = 132711560274286, -- sfx-streak
		Sleep = 100017322354603, -- sfx-sleep
		Graveyard = 128556282367801, -- (sfx-menu-open until sfx-graveyard is made)
	}
	-- How loud each one plays (0 to 1), to even them out
	local SOUND_VOLUME = {
		CardPlay = 0.55, SpellCast = 0.5, AttackSwing = 0.45, Hit = 0.5, CommanderHit = 0.5,
		ShieldBreak = 0.6, Heal = 0.5, Buff = 0.5, UnitDestroyed = 0.55, CelestialSummon = 0.6,
		Storm = 0.7, YourTurn = 0.45, Victory = 0.45, Defeat = 0.4, Click = 0.35,
		CardDraw = 0.45, Shuffle = 0.5, ShieldUp = 0.5, Ignite = 0.5, Grow = 0.5, Weaken = 0.5,
		Decay = 0.5, Streak = 0.5, Sleep = 0.35, Graveyard = 0.35,
	}
	local soundFolder = Instance.new("Folder")
	soundFolder.Name = "BattleSounds"
	soundFolder.Parent = gui
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
end

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
playSoundEarly = playSound

local fxLayer = make("Frame", {
	Name = "FX",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 15,
}, gui)

-- The other side's plays can be shown slower (or faster) than your own:
-- { name, animation speed multiplier, extra pause after each of their plays }
local OPPONENT_SPEEDS = {
	Slow = { 0.6, 1.4 },
	Normal = { 1, 0.6 },
	Fast = { 1.6, 0 },
}
local opponentSpeed = player:GetAttribute("BattleOpponentSpeed") or "Normal"
local speedFactor = 1 -- set while an opponent's play is animating
local actorOf -- (below)

local function seconds(t)
	return t / math.max(animSpeed * speedFactor, 0.01)
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
-- (more colors live in a table: this script is near Luau's 200-local limit)
local FX_COLORS = { Purple = Color3.fromRGB(190, 120, 255), Teal = Color3.fromRGB(90, 230, 220),
	Orange = Color3.fromRGB(255, 150, 50) }

-- One event's animation. Returns after the part that should finish before the next event.
-- (playEvent is declared above, before the Anomaly slots)

-- Drawing a card: a card back slides out of your deck (right end of your hand),
-- flips over to show what you drew, then drops into your hand. The
-- opponent's draws are a card back sliding into their side at the top.
function playEvent.Draw(e)
	local mine = e.Player == current.Seat
	local holder = make("Frame", {
		Name = "DrawnCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = mine and UDim2.fromScale(0.76, 0.86) or UDim2.fromScale(0.74, 0.03),
		Size = mine and UDim2.fromScale(0.1, 0.2) or UDim2.fromScale(0.035, 0.07),
		BackgroundTransparency = 1,
		ZIndex = 16,
	}, fxLayer)
	local face = make("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 16 }, holder)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, face)
	local scale = make("UIScale", { Scale = 1 }, holder)
	CardVisuals.DrawFaceDown(face, "")
	playSound("CardDraw")
	if not mine or not e.CardId then
		tween(holder, 0.3, { Position = UDim2.fromScale(0.62, 0.03) })
		pause(0.3)
		tween(scale, 0.12, { Scale = 0 })
		pause(0.12)
		holder:Destroy()
		return
	end
	-- out of the deck, toward the middle of your hand
	tween(holder, 0.28, { Position = UDim2.fromScale(0.5, 0.72), Size = UDim2.fromScale(0.14, 0.28) })
	pause(0.28)
	-- flip
	tween(scale, 0.1, { Scale = 0.05 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	pause(0.1)
	clear(face)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, face)
	CardVisuals.Draw(face, e.CardId, { Finish = finishFor("Self", e.CardId) })
	tween(scale, 0.14, { Scale = 1 }, Enum.EasingStyle.Back)
	pause(0.45)
	-- into the hand
	tween(holder, 0.2, { Position = UDim2.fromScale(0.38, 0.88) })
	tween(scale, 0.2, { Scale = 0.4 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	pause(0.2)
	holder:Destroy()
end

function playEvent.UnitPlayed(e)
	playSound("CardPlay")
	local side = sideOfSeat(e.Player)
	local slot = slots[side][e.Lane]
	local fromY = side == "Self" and 0.87 or -0.15
	flyIn(e.CardId, 0.38, fromY, slot, finishFor(side, e.CardId))
	uidSlot[e.Uid] = slot
	uidCard[e.Uid] = e.CardId
	playEvent._fx(slot, "CardLanding", 1.5, { Duration = 0.6 })
	local played = CardDatabase.GetCard(e.CardId)
	if not (played and played.Keywords and played.Keywords.Rush) then
		playSound("Sleep") -- it can't attack yet (the Zzz)
	end
	pause(0.12)
end

function playEvent.CelestialSummoned(e)
	local side = sideOfSeat(e.Player)
	local slot = slots[side][e.Lane]
	local gate = gateSlots[side]
	playSound("CelestialSummon")
	flash(gate, GOLD, 0.8)
	pause(0.25)
	-- the signature moment: the board darkens and the Celestial appears huge
	-- before it lands (about a second at normal speed)
	local dim = make("Frame", {
		Name = "SummonDim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 16,
	}, fxLayer)
	tween(dim, 0.2, { BackgroundTransparency = 0.45 })
	local showcase = make("Frame", {
		Name = "SummonShowcase",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.44, 0.4),
		Size = UDim2.fromScale(0.3, 0.45),
		BackgroundTransparency = 1,
		ZIndex = 18,
	}, fxLayer)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, showcase)
	local showcaseScale = make("UIScale", { Scale = 0.7 }, showcase)
	local function raise()
		for _, d in ipairs(showcase:GetDescendants()) do
			if d:IsA("GuiObject") and not d:GetAttribute("Raised") then
				d:SetAttribute("Raised", true)
				d.ZIndex = d.ZIndex + 18
			end
		end
	end
	-- it rises face down from the Star Gate, then turns over
	CardVisuals.DrawFaceDown(showcase, "")
	raise()
	playEvent._fx(nil, "SummonPillar", 1, { Position = UDim2.fromScale(0.44, 0.4), Size = 0.75, Duration = 0.9, ZIndex = 17 })
	tween(showcaseScale, 0.35, { Scale = 1.05 }, Enum.EasingStyle.Back)
	pause(0.3)
	if animSpeed > 0 then
		CardVisuals.Flip(showcase, function(target)
			CardVisuals.Draw(target, e.CardId, { Finish = finishFor(side, e.CardId) })
			raise()
		end, { Duration = seconds(0.38), Tease = GOLD, TeaseTime = seconds(0.22) })
	else
		CardVisuals.Draw(showcase, e.CardId, { Finish = finishFor(side, e.CardId) })
		raise()
	end
	pause(0.5)
	tween(showcaseScale, 0.2, { Scale = 0.3 })
	tween(dim, 0.25, { BackgroundTransparency = 1 })
	pause(0.18)
	showcase:Destroy()
	cleanup(dim, 0.3)
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
	playEvent._fx(slot, "SummonPillar", 1.9, { Duration = 0.9 })
	flyIn(e.CardId, g.X, g.Y, slot, finishFor(side, e.CardId))
	uidSlot[e.Uid] = slot
	uidCard[e.Uid] = e.CardId
	flash(slot, GOLD, 0.6)
	pause(0.25)
end

function playEvent.SpellCast(e)
	table.clear(hitBy)
	playSound("SpellCast")
	-- the casting circle behind the big spell card
	playEvent._fx(nil, "SpellCast", 1, { Position = UDim2.fromScale(0.5, 0.36), Duration = 0.9, ZIndex = 15 })
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
	table.clear(hitBy)
	hitBy[e.Defender] = factionOfUid(e.Attacker)
	hitBy[e.Attacker] = factionOfUid(e.Defender) -- (the hit back)
	if attacker and defender then
		playSound("AttackSwing")
		lunge(attacker, slotBase[defender].Y, 0.55)
	end
end

-- An effect sprite sheet over a card slot (or at a screen position).
-- size = how big compared with the card's height.
function playEvent._fx(slot, key, size, options)
	options = options or {}
	local base = slot and slotBase[slot]
	if animSpeed <= 0 or (not base and not options.Position) then
		return
	end
	local h = (base and base.H or 0.55) * (size or 1.2)
	if not base and options.Size then
		h = options.Size -- (a screen-position effect: Size is its height as a share of the screen)
	end
	local position = options.Position or (base and UDim2.fromScale(base.X, base.Y))
	local ground = base and not options.Position and UiAssets.GroundedVfx[key]
	if ground then
		-- rises from the card's bottom edge: its ground ring lines up with it
		position = UDim2.fromScale(base.X, base.Y + base.H / 2 - (ground - 0.5) * h)
	end
	UiAssets.PlayFlipbook(fxLayer, UiAssets.VfxImage(key), {
		Position = position,
		Size = UDim2.fromScale(h, h),
		Duration = seconds(options.Duration or 0.55),
		ZIndex = options.ZIndex or 17,
		Color = options.Color,
	})
end

-- The impact on a hit: the attacker's faction impact if it has one,
-- otherwise a quick flash for small hits and a burst for big ones.
-- (Bigger hits make a bigger effect.)
function playEvent._impact(slot, amount, color, faction)
	if faction == ALREADY_HIT then
		return
	end
	local size = math.clamp(1 + (amount or 1) * 0.08, 1.05, 1.6)
	local factionKey = faction and UiAssets.FactionImpact[faction]
	if factionKey and UiAssets.VfxImage(factionKey) then
		playEvent._fx(slot, factionKey, size * 1.1, { Color = color })
	elseif (amount or 1) <= 2 then
		playEvent._fx(slot, "HitFlash", size, { Color = color, Duration = 0.4 })
	else
		playEvent._fx(slot, "DamageBurst", size * 1.1, { Color = color, Duration = 0.6 })
	end
end

-- A projectile flying from one card slot to another: a looping head with a
-- glowing trail stretched behind it, then an impact where it lands.
-- Waits until it lands. kind = an entry of UiAssets.Projectiles.
function playEvent._projectile(fromSlot, toSlot, kind)
	local from, to = slotBase[fromSlot], slotBase[toSlot]
	local spec = UiAssets.Projectiles[kind]
	local headImage = spec and UiAssets.VfxImage(spec.Head)
	if animSpeed <= 0 or not from or not to or not headImage then
		return false
	end
	local area = fxLayer.AbsoluteSize
	local fx, fy = from.X * area.X, from.Y * area.Y
	local tx, ty = to.X * area.X, to.Y * area.Y
	local headSize = to.H * area.Y * 0.55
	local flight = seconds(spec.Flight or 0.3)
	local head = UiAssets.PlayFlipbook(fxLayer, headImage, {
		Position = UDim2.fromOffset(fx, fy),
		Size = UDim2.fromOffset(headSize, headSize),
		Duration = flight,
		ZIndex = 19,
	})
	local trail
	local trailImage = UiAssets.VfxImage(spec.Trail)
	if trailImage then
		trail = Instance.new("ImageLabel")
		trail.Name = "Trail"
		trail.BackgroundTransparency = 1
		trail.Image = trailImage
		trail.ScaleType = Enum.ScaleType.Stretch
		trail.AnchorPoint = Vector2.new(0.5, 0.5)
		trail.ZIndex = 18
		trail.Parent = fxLayer
	end
	local dx, dy = tx - fx, ty - fy
	-- the trail image points up; turn it to point the way the head flies
	local angle = math.deg(math.atan(dx, -dy))
	local width = headSize * 0.5
	local start = os.clock()
	while true do
		local t = math.min((os.clock() - start) / flight, 1)
		local eased = t ^ 1.25 -- picks up a little speed as it flies
		local hx, hy = fx + dx * eased, fy + dy * eased
		if head then
			head.Position = UDim2.fromOffset(hx, hy)
		end
		if trail then
			-- the tail lags behind the head, so the trail stretches as it flies
			local tailT = math.max(0, eased - 0.55)
			local sx, sy = fx + dx * tailT, fy + dy * tailT
			local length = math.max(math.sqrt((hx - sx) ^ 2 + (hy - sy) ^ 2) + width * 0.6, 1)
			trail.Position = UDim2.fromOffset((hx + sx) / 2, (hy + sy) / 2)
			trail.Size = UDim2.fromOffset(width, length)
			trail.Rotation = angle
		end
		if t >= 1 then
			break
		end
		task.wait()
	end
	if head then
		head:Destroy()
	end
	if trail then
		TweenService:Create(trail, TweenInfo.new(seconds(0.15)), { ImageTransparency = 1 }):Play()
		task.delay(seconds(0.16), function()
			trail:Destroy()
		end)
	end
	playEvent._fx(toSlot, spec.Impact, 1.4, { Duration = 0.55 })
	return true
end

function playEvent.UnitDamaged(e)
	local slot = uidSlot[e.Uid]
	if slot then
		-- bigger hits sound deeper
		playSound("Hit", math.clamp(1.15 - (e.Amount or 1) * 0.06, 0.75, 1.15))
		flash(slot, RED, 0.6)
		playEvent._impact(slot, e.Amount, nil, hitBy[e.Uid])
		hitBy[e.Uid] = nil
		shake(slot)
		popText(slot, "-" .. e.Amount, RED, true)
		setShownStats(slot, nil, e.HP, true)
	end
	pause(0.12)
end

-- Ignite: the new unit throws a fireball at the unit across from it
function playEvent.Ignite(e)
	local slot = uidSlot[e.Target]
	local from = uidSlot[e.Uid]
	if slot then
		playSound("Ignite")
		table.clear(hitBy)
		if from and playEvent._projectile(from, slot, "Fireball") then
			hitBy[e.Target] = ALREADY_HIT -- (the damage that follows doesn't need another burst)
		else
			playEvent._fx(slot, "Ignite", 1.3)
		end
		flash(slot, FX_COLORS.Orange, 0.7)
	end
	pause(0.1)
end

function playEvent.ShieldBroken(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("ShieldBreak")
		flash(slot, BLUE, 0.7)
		playEvent._fx(slot, "ShieldBreak", 1.4)
		popText(slot, "Shield broke!", BLUE)
	end
	pause(0.15)
end

function playEvent.ShieldGained(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("ShieldUp")
		flash(slot, BLUE, 0.5)
		playEvent._fx(slot, "ShieldUp", 1.3, { Duration = 0.65 })
		popText(slot, "+Shield", BLUE)
	end
	pause(0.15)
end

function playEvent.UnitHealed(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("Heal")
		flash(slot, GREEN, 0.4)
		playEvent._fx(slot, "HealPulse", 1.3, { Duration = 0.7 })
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
		playEvent._fx(slot, "PowerUp", 1.2)
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


function playEvent.UnitGrew(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("Grow")
		flash(slot, GREEN, 0.45)
		playEvent._fx(slot, "Grow", 1.2)
		popText(slot, "Grow +" .. e.Amount, GREEN)
		setShownStats(slot, e.Power, nil, nil)
	end
	pause(0.15)
end

function playEvent.GrowGained(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("Grow", 1.1)
		flash(slot, GREEN, 0.35)
		popText(slot, "Grow " .. e.Grow, GREEN)
	end
	pause(0.12)
end

function playEvent.Decay(e)
	local slot = uidSlot[e.Target]
	if slot then
		playSound("Decay")
		flash(slot, FX_COLORS.Purple, 0.7)
		playEvent._fx(slot, "Decay", 1.2)
	end
	pause(0.1)
end

function playEvent.UnitWeakened(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("Weaken")
		flash(slot, FX_COLORS.Purple, 0.55)
		playEvent._fx(slot, "Weaken", 1.2)
		popText(slot, "-" .. e.Amount .. " Power", FX_COLORS.Purple)
		setShownStats(slot, e.Power, nil, nil)
	end
	pause(0.15)
end

function playEvent.StreakGained(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("Streak")
		flash(slot, FX_COLORS.Teal, 0.5)
		playEvent._fx(slot, "Streak", 1.3)
		popText(slot, "Streak!", FX_COLORS.Teal)
	end
	pause(0.12)
end

function playEvent.UnitReturned(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("SpellCast", 1.2)
		removeFromSlot(slot, FX_COLORS.Teal)
		uidSlot[e.Uid] = nil
	end
	pause(0.15)
end

function playEvent.CommanderPaidHP(e)
	local side = sideOfSeat(e.Player)
	local target = commanderSlots[side]
	playSound("Hit", 0.8)
	flash(target, FX_COLORS.Purple, 0.6)
	popText(target, "-" .. e.Amount .. " HP", FX_COLORS.Purple, true)
	setShownCommanderHP(side, e.HP, true)
	pause(0.2)
end

function playEvent.EnergyGained(e)
	local side = sideOfSeat(e.Player)
	popText(commanderSlots[side], "+" .. e.Amount .. " energy", BLUE)
	pause(0.15)
end

function playEvent.UnitDestroyed(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playEvent._fx(slot, "DestroyBurst", 1.5, { Duration = 0.65 })
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
	if e.Streak then
		playSound("Streak")
		playEvent._fx(target, "Streak", 1.5)
	end
	if UiAssets.VfxImage("CommanderHit") then
		playEvent._fx(target, "CommanderHit", math.clamp(1.3 + (e.Amount or 1) * 0.06, 1.35, 1.8), { Duration = 0.65 })
	else
		playEvent._impact(target, e.Amount)
	end
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
	playEvent._fx(target, "Storm", 1.5, { Duration = 0.7 })
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
	playEvent._fx(target, "HealPulse", 1.3, { Duration = 0.7 })
	popText(target, "+" .. e.Amount, GREEN, true)
	setShownCommanderHP(side, e.HP, false)
	pause(0.2)
end

-- Sounds for the start of your turn and the end of a game. These play
-- even with animations off, after the update has played out.
-- Anomalies -------------------------------------------------------
function playEvent.AnomalySet(e)
	local chip = playEvent._anomalyChips[sideOfSeat(e.Player)][e.Slot or 1]
	playSound("CardPlay", 0.8)
	if chip then
		setLabel(chip, e.CardId and cardName(e.CardId) or "Anomaly ?")
		setStroke(chip, Color3.fromRGB(150, 90, 230), 2)
		flash(chip, Color3.fromRGB(170, 110, 255), 0.8)
		popText(chip, "Set!", Color3.fromRGB(205, 165, 255))
	end
	pause(0.3)
end

-- A face-down Anomaly flips: a big "ANOMALY!", the card shown in the middle,
-- then it flies at whatever set it off
function playEvent.AnomalyTriggered(e)
	local side = sideOfSeat(e.Player)
	local chip = playEvent._anomalyChips[side][e.Slot or 1]
	playSound("SpellCast", 0.75)
	if chip then
		flash(chip, Color3.fromRGB(200, 140, 255), 0.9)
		setLabel(chip, "Anomaly slot")
		setStroke(chip, nil)
	end
	local banner = make("TextLabel", {
		Name = "AnomalyBanner",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.1),
		Size = UDim2.fromScale(0.3, 0.07),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(215, 170, 255),
		TextStrokeTransparency = 0,
		Text = side == "Self" and "YOUR ANOMALY!" or "ANOMALY!",
		ZIndex = 17,
	}, fxLayer)
	tween(banner, 1.1, { TextTransparency = 1, TextStrokeTransparency = 1 })
	cleanup(banner, 1.2)
	playEvent._fx(nil, "SpellCast", 1, { Position = UDim2.fromScale(0.5, 0.36), Duration = 0.9, ZIndex = 15,
		Color = Color3.fromRGB(190, 130, 255) })
	showSpell(e.CardId, e.Uid and uidSlot[e.Uid] or nil, finishFor(side, e.CardId))
end

function playEvent.SpellCancelled(e)
	playSound("ShieldBreak", 0.8)
	local l = make("TextLabel", {
		Name = "Cancelled",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(0.3, 0.09),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 120, 160),
		TextStrokeTransparency = 0,
		Text = "CANCELLED!",
		ZIndex = 18,
	}, fxLayer)
	tween(l, 0.9, { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.fromScale(0.5, 0.3) })
	cleanup(l, 1)
	pause(0.4)
end

function playEvent.DamagePrevented(e)
	local target = commanderSlots[sideOfSeat(e.Player)]
	playSound("ShieldUp")
	flash(target, BLUE, 0.7)
	popText(target, "Blocked!", BLUE, true)
	pause(0.35)
end

function playEvent.UnitFrozen(e)
	local slot = uidSlot[e.Uid]
	if slot then
		playSound("Weaken", 1.4)
		flash(slot, Color3.fromRGB(170, 230, 255), 0.8)
		popText(slot, "Frozen!", Color3.fromRGB(170, 230, 255), true)
	end
	pause(0.3)
end

function playEvent.UnitThawed(e)
	local slot = uidSlot[e.Uid]
	if slot then
		popText(slot, "Frozen: no attack", Color3.fromRGB(170, 230, 255))
	end
	pause(0.25)
end

function playEvent.CardRecovered(e)
	local target = commanderSlots[sideOfSeat(e.Player)]
	playSound("CardDraw")
	popText(target, "Card back!", GREEN)
	pause(0.25)
end

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
			-- the Commander intro (first game of a match, not the tutorial): both Commanders
			-- big in the middle, the opponent's says their line and flies to its zone, then
			-- yours answers; the opening hand waits until it's over
			local players = payload.State and payload.State.Players
			if players and not payload.Tutorial and (not payload.Series or (payload.Series.Game or 1) == 1)
				and require(ReplicatedStorage:WaitForChild("CommanderIntro")).Enabled then
				local them = players[3 - payload.Seat]
				local me = players[payload.Seat]
				gui:SetAttribute("IntroPlaying", true)
				require(ReplicatedStorage:WaitForChild("CommanderIntro")).Play({
					Parent = root,
					Visual = animSpeed > 0,
					Top = { CommanderId = them and them.CommanderId, Finish = them and finishFor("Enemy", them.CommanderId),
						Slot = enemyCommander },
					Bottom = { CommanderId = me and me.CommanderId, Finish = me and finishFor("Self", me.CommanderId),
						Slot = myCommander },
					OnDone = function()
						gui:SetAttribute("IntroPlaying", false)
						if refreshMulligan then
							refreshMulligan()
						end
					end,
				})
			end
			logLines = {}
			inspectMode = false
			closeInspect()
			confirmFrame.Visible = false
			local series = payload.Series
			if series and series.BestOf > 1 then
				addLog(("== Game %d (best of %d) =="):format(series.Game, series.BestOf))
			end
			if series and series.DeckFormat then
				addLog(series.DeckFormat == "Open" and "== Open format: no star limit =="
					or "== Zenith format: both decks fit the star cap ==")
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
		if not current then
			return -- the table closed while this was playing
		end
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

-- Whose play an update is: the player of its first action
do
	local ACTION_TYPES = { UnitPlayed = true, SpellCast = true, CelestialSummoned = true, CommanderAbility = true,
		SparkUsed = true, TurnEnded = true }
	actorOf = function(payload)
		for _, event in ipairs(payload.Events) do
			if ACTION_TYPES[event.Type] then
				return event.Player
			end
		end
		return nil
	end
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
			local theirs = actorOf(item) == 3 - item.Seat
			local opp = OPPONENT_SPEEDS[opponentSpeed] or OPPONENT_SPEEDS.Normal
			speedFactor = theirs and opp[1] or 1
			local ok, err = xpcall(animateUpdate, debug.traceback, item)
			if theirs and opp[2] > 0 then
				task.wait(opp[2]) -- a beat to take in what they did
			end
			speedFactor = 1
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

-- Settings row at the bottom of the match log: sound, animation speed,
-- and how fast the opponent's plays are shown. Saved with your cards.
;(function() -- (a function, not a do block: the main chunk is near Luau's 200-local limit)
	local OPPONENT_ORDER = { "Slow", "Normal", "Fast" }
	local saveSettings
	do
		local economyRemotes = ReplicatedStorage:WaitForChild("EconomyRemotes", 10)
		local economyRequest = economyRemotes and economyRemotes:WaitForChild("EconomyRequest", 10)
		saveSettings = function()
			player:SetAttribute("BattleAnimSpeed", animSpeed)
			player:SetAttribute("BattleSound", soundOn)
			player:SetAttribute("BattleOpponentSpeed", opponentSpeed)
			if economyRequest then
				task.spawn(function()
					pcall(function()
						economyRequest:InvokeServer("SaveSettings",
							{ AnimSpeed = animSpeed, Sound = soundOn, OpponentSpeed = opponentSpeed })
					end)
				end)
			end
		end
	end

	-- One "Settings" button under the log opens a box with the three
	-- settings as big buttons that show their current value (three tiny
	-- buttons were unreadable on phones).
	local settingsButton = button(root, "SettingsButton", "Settings", UDim2.fromScale(0.76, 0.452),
		UDim2.fromScale(0.225, 0.042), TINT.Grey)
	local settingsFrame = make("TextButton", {
		Name = "SettingsBox",
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.4,
		Visible = false,
		ZIndex = 25,
	}, gui)
	local settingsPanel = make("Frame", {
		Name = "SettingsPanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.42, 0.56),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		ZIndex = 25,
	}, settingsFrame)
	UiAssets.FramePanel(settingsPanel)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, settingsPanel)
	label(settingsPanel, {
		Name = "SettingsTitle",
		Position = UDim2.fromScale(0.08, 0.04),
		Size = UDim2.fromScale(0.84, 0.13),
		ZIndex = 26,
		TextColor3 = GOLD,
		Text = "Battle settings",
	})
	local function row(name, y, tint)
		local b = button(settingsPanel, name, "", UDim2.fromScale(0.08, y), UDim2.fromScale(0.84, 0.15), tint)
		b.ZIndex = 26
		b.Label.ZIndex = 27
		return b
	end
	local soundButton = row("SoundButton", 0.2, TINT.Default)
	local speedButton = row("AnimSpeedButton", 0.38, TINT.Default)
	local opponentButton = row("OpponentSpeedButton", 0.56, TINT.Default)
	local settingsClose = row("SettingsClose", 0.78, TINT.Grey)
	setLabel(settingsClose, "Done")
	settingsButton.Activated:Connect(function()
		settingsFrame.Visible = true
	end)
	settingsClose.Activated:Connect(function()
		settingsFrame.Visible = false
	end)
	settingsFrame.Activated:Connect(function()
		settingsFrame.Visible = false
	end)
	local function refreshSettings()
		setLabel(soundButton, soundOn and "Sound: On" or "Sound: Off")
		for _, sp in ipairs(SPEEDS) do
			if sp[1] == animSpeed then
				setLabel(speedButton, "Animations: " .. sp[2])
			end
		end
		setLabel(opponentButton, "Opponent's turns: " .. opponentSpeed)
	end
	refreshSettings()
	soundButton.Activated:Connect(function()
		soundOn = not soundOn
		refreshSettings()
		saveSettings()
	end)
	speedButton.Activated:Connect(function()
		local index = 1
		for i, sp in ipairs(SPEEDS) do
			if sp[1] == animSpeed then
				index = i
			end
		end
		animSpeed = SPEEDS[index % #SPEEDS + 1][1]
		refreshSettings()
		saveSettings()
	end)
	opponentButton.Activated:Connect(function()
		local index = table.find(OPPONENT_ORDER, opponentSpeed) or 2
		opponentSpeed = OPPONENT_ORDER[index % #OPPONENT_ORDER + 1]
		refreshSettings()
		saveSettings()
	end)
	-- your saved settings arrive from the server once your cards load
	for attribute, apply in pairs({
		BattleAnimSpeed = function(v) if type(v) == "number" then animSpeed = v end end,
		BattleSound = function(v) if type(v) == "boolean" then soundOn = v end end,
		BattleOpponentSpeed = function(v) if OPPONENT_SPEEDS[v] then opponentSpeed = v end end,
	}) do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			apply(player:GetAttribute(attribute))
			refreshSettings()
		end)
	end
end)()

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
		require(ReplicatedStorage:WaitForChild("LongPress")).Attach(slots[side][lane], inspectHere)
		local function slotClick()
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
			if mode == "EnemyUnit" and side ~= "Enemy" then
				flashMessage = "Pick an enemy unit."
				render()
				return
			end
			if mode == "FriendlyUnit" and side ~= "Self" then
				flashMessage = "Pick one of your own units."
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
		end
		-- (a card dropped on this lane acts like a click here)
		PICK.SlotClick = PICK.SlotClick or { Self = {}, Enemy = {} }
		PICK.SlotClick[side][lane] = slotClick
		-- a dragged card or Celestial let go at point p: click the lane under it (true if there was one)
		PICK.DropOnLane = PICK.DropOnLane or function(p)
			for _, s in ipairs({ "Self", "Enemy" }) do
				for l = 1, LANES do
					local slot = slots[s][l]
					local pos, size = slot.AbsolutePosition, slot.AbsoluteSize
					if p.X >= pos.X and p.X <= pos.X + size.X and p.Y >= pos.Y and p.Y <= pos.Y + size.Y then
						PICK.SlotClick[s][l]()
						return true
					end
				end
			end
			return false
		end
		slots[side][lane].Activated:Connect(function()
			if require(ReplicatedStorage:WaitForChild("LongPress")).Swallowed()
				or require(ReplicatedStorage:WaitForChild("CardDrag")).Swallowed() then
				return
			end
			slotClick()
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
-- touch: hold the Star Gates and Commanders to inspect them too
do
	local LongPress = require(ReplicatedStorage:WaitForChild("LongPress"))
	LongPress.Attach(myGate, function() inspectGate("Self") end)
	LongPress.Attach(enemyGate, function() inspectGate("Enemy") end)
	LongPress.Attach(myCommander, function() inspectCommander("Self") end)
	LongPress.Attach(enemyCommander, function() inspectCommander("Enemy") end)
end
enemyGate.MouseButton2Click:Connect(function()
	inspectGate("Enemy")
end)
enemyGate.Activated:Connect(function()
	if require(ReplicatedStorage:WaitForChild("LongPress")).Swallowed() then
		return
	end
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
	if require(ReplicatedStorage:WaitForChild("LongPress")).Swallowed() then
		return
	end
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

-- drag the Star Gate onto a lane to summon (tapping the gate, then the lane, still works)
require(ReplicatedStorage:WaitForChild("CardDrag")).Attach(myGate, {
	Layer = root,
	CanDrag = function()
		local mine = current and current.State.Players[current.Seat]
		local gate = mine and mine.StarGate
		return gate ~= nil and gate.CardId ~= nil and not gate.OnBoard and not inspectMode and isMyTurn()
			and gate.Cost <= mine.Energy
			and not require(ReplicatedStorage:WaitForChild("LongPress")).Swallowed()
	end,
	MakeGhost = function(parent)
		local gateId = current.State.Players[current.Seat].StarGate.CardId
		drawCard(parent, gateId, nil, false, false, finishFor("Self", gateId))
	end,
	OnStart = function()
		selectThing({ Kind = "Celestial", Hint = "Drop your Celestial on an empty lane." })
	end,
	OnDrop = function(p)
		if not PICK.DropOnLane(p) then
			selectThing(nil)
		end
	end,
})
myGate.Activated:Connect(function()
	if require(ReplicatedStorage:WaitForChild("LongPress")).Swallowed()
		or require(ReplicatedStorage:WaitForChild("CardDrag")).Swallowed() then
		return
	end
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
	if require(ReplicatedStorage:WaitForChild("LongPress")).Swallowed() then
		return -- (a long press on your Commander inspects it instead)
	end
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
	local abilityTarget = commander.CommanderAbility.Effect.Target
	if not abilityTarget then
		-- no target needed (like Malakar or Orion): use it right away
		selectThing(nil)
		send({ Kind = "UseAbility" })
		return
	end
	local pick = abilityTarget == "EnemyUnit" and " Pick an enemy unit."
		or (abilityTarget == "FriendlyUnit" and " Pick one of your units." or " Pick a unit.")
	selectThing({ Kind = "Ability", Hint = commander.CommanderAbility.Text .. pick })
end
abilityButton.Activated:Connect(function()
	if not require(ReplicatedStorage:WaitForChild("CardDrag")).Swallowed() then
		onAbilityClicked()
	end
end)
myCommander.Activated:Connect(function()
	if not require(ReplicatedStorage:WaitForChild("CardDrag")).Swallowed() then
		onAbilityClicked()
	end
end)
-- drag the Ability button (or your Commander) onto a unit to use the ability on it
for _, source in ipairs({ abilityButton, myCommander }) do
	require(ReplicatedStorage:WaitForChild("CardDrag")).Attach(source, {
		Layer = root,
		GhostSize = UDim2.fromOffset(100, 140),
		CanDrag = function()
			local mine = current and current.State.Players[current.Seat]
			if not mine or inspectMode or not isMyTurn() or mine.AbilityUsed
				or require(ReplicatedStorage:WaitForChild("LongPress")).Swallowed() then
				return false
			end
			local ability = CardDatabase.GetCard(mine.CommanderId).CommanderAbility
			return ability.Effect.Target ~= nil and ability.EnergyCost <= mine.Energy
		end,
		MakeGhost = function(parent)
			local commanderId = current.State.Players[current.Seat].CommanderId
			drawCard(parent, commanderId, nil, true, false, finishFor("Self", commanderId))
		end,
		OnStart = function()
			local ability = CardDatabase.GetCard(current.State.Players[current.Seat].CommanderId).CommanderAbility
			local target = ability.Effect.Target
			selectThing({ Kind = "Ability", Hint = target == "EnemyUnit" and "Drop it on an enemy unit."
				or (target == "FriendlyUnit" and "Drop it on one of your units." or "Drop it on a unit.") })
		end,
		OnDrop = function(p)
			if not PICK.DropOnLane(p) then
				selectThing(nil)
			end
		end,
	})
end

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
UiAssets.FramePanel(confirmPanel)
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
		if deck.Format then
			label(b, {
				Name = "DeckFormat",
				Position = UDim2.fromScale(0.62, 0.86),
				Size = UDim2.fromScale(0.34, 0.11),
				Font = Enum.Font.GothamBold,
				ZIndex = 7,
				TextColor3 = deck.Format == "Open" and Color3.fromRGB(150, 220, 255) or Color3.fromRGB(255, 220, 110),
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = deck.Format == "Open" and "OPEN" or "ZENITH",
			})
		end
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
			send({ Kind = "ChooseDeck", Deck = deck.Key, BestOf = chosenFormat,
				BotDifficulty = vsBotPicker and chosenDifficulty or nil })
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
		pickerFrame:SetAttribute("OpponentDeckFormat", payload.OpponentDeckFormat)
		refreshFormat()
		showDeckPicker(payload.Decks)
	elseif payload.Kind == "OpponentVote" then
		opponentVote = payload.BestOf
		pickerFrame:SetAttribute("OpponentDeckFormat", payload.DeckFormat)
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
				task.delay(1.5, function() -- after the victory / defeat sound
					require(ReplicatedStorage:WaitForChild("SoundAssets")).Play("Coins")
				end)
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