--[[
	CardVisuals (ModuleScript)
	Location: ReplicatedStorage > CardVisuals

	Draws a card onto any GUI button or frame, so the battle screen, pack
	results, collection and deck builder all show cards the same way.

	Finishes (the shiny versions):
	  Holo      a rainbow sheen over the art, with a band of light sweeping across
	  Textured  Holo, plus a sweep over the whole card and a sparkle pattern
	  3D        Holo, plus the art drifting slightly inside its window (depth)
	            and a soft gold edge
	  Mythic    everything above, plus a rainbow edge that keeps cycling
	The shine only moves on players' screens; cards drawn by the server
	(like the shop's singles case) show it standing still.

	CardVisuals.Draw(target, cardId, options)
	  options.Unit      -- on-board stats { Power, HP, MaxHP, Shield, CanAttack } (battle)
	  options.Finish    -- "Base", "Holo", "Textured", "3D", "Mythic"
	  options.HideCost  -- true to leave off the energy cost
	  options.Dim       -- true to fade the card (can't afford, not owned)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local CardArt = require(ReplicatedStorage:WaitForChild("CardArt"))
local UiAssets = require(ReplicatedStorage:WaitForChild("UiAssets"))
local Fonts = require(ReplicatedStorage:WaitForChild("Fonts"))

local CardVisuals = {}

CardVisuals.FactionColors = {
	Solar = Color3.fromRGB(196, 96, 36),
	Lunar = Color3.fromRGB(96, 124, 190),
	Nebula = Color3.fromRGB(150, 76, 186),
	Void = Color3.fromRGB(62, 50, 104),
	Comet = Color3.fromRGB(40, 150, 170),
	Neutral = Color3.fromRGB(104, 104, 116),
}
CardVisuals.RarityColors = {
	Common = Color3.fromRGB(210, 210, 210),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(190, 100, 255),
	Legendary = Color3.fromRGB(255, 200, 60),
}
CardVisuals.MythicColor = Color3.fromRGB(255, 90, 200)
CardVisuals.FinishNames = {
	Base = "Standard",
	Holo = "Holo",
	Textured = "Textured Holo",
	["3D"] = "3D",
	Mythic = "MYTHIC",
}

local WHITE = Color3.fromRGB(255, 255, 255)
local COST_COLOR = Color3.fromRGB(25, 40, 110)
local COST_RAISED_COLOR = Color3.fromRGB(170, 40, 40)

-- The number for the cost circle, or nil if there shouldn't be one
local function costFor(card, options)
	if options.Cost then
		return options.Cost
	end
	if options.HideCost or card.Type == "Commander" then
		return nil
	end
	return card.EnergyCost
end

local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

-- A text label that shrinks to fit but never gets huge on big cards
local function text(parent, name, position, size, value, maxSize, props)
	local label = make("TextLabel", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextWrapped = true,
		Text = value,
	}, parent)
	if props then
		for key, v in pairs(props) do
			label[key] = v
		end
	end
	Fonts.Style(label)
	make("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 6 }, label)
	return label
end
CardVisuals.Text = text

function CardVisuals.KeywordText(card, unit)
	local parts = {}
	local keywords = card.Keywords or {}
	if keywords.Rush then
		table.insert(parts, "Rush")
	end
	if keywords.Shield and (not unit or unit.Shield) then
		table.insert(parts, "Shield")
	end
	if keywords.Intercept then
		table.insert(parts, "Intercept")
	end
	if keywords.Ignite then
		table.insert(parts, "Ignite " .. keywords.Ignite)
	end
	if keywords.Regen then
		table.insert(parts, "Regen " .. keywords.Regen)
	end
	if keywords.Grow or (unit and unit.Grow and unit.Grow > 0) then
		table.insert(parts, "Grow " .. ((unit and unit.Grow) or keywords.Grow))
	end
	if keywords.Decay then
		table.insert(parts, "Decay " .. keywords.Decay)
	end
	if keywords.Streak or (unit and unit.Streak) then
		table.insert(parts, "Streak")
	end
	local result = table.concat(parts, ", ")
	if card.AbilityText ~= "" then
		result = (result ~= "" and (result .. ". ") or "") .. card.AbilityText
	end
	if card.HPCost then
		result = ("Also costs %d HP."):format(card.HPCost) .. (result ~= "" and (" " .. result) or "")
	end
	if card.Type == "Commander" and card.CommanderAbility then
		result = ("Ability (%d): %s"):format(card.CommanderAbility.EnergyCost, card.CommanderAbility.Text)
	end
	if card.Type == "Celestial" and card.PairsWith then
		result = result .. (result ~= "" and "\n" or "") .. "Pairs with " .. table.concat(card.PairsWith, " + ")
	end
	return result
end

-- The keywords a card (or a unit on the board) has right now, in card-text
-- order: { { Name = "Grow", Amount = 2 }, { Name = "Shield" }, ... }.
-- For a unit, what it has now wins: a Shield it gained shows up, a broken one
-- goes away, and Grow shows its current amount.
local KEYWORD_ORDER = { "Rush", "Shield", "Intercept", "Ignite", "Regen", "Grow", "Decay", "Streak" }
local KEYWORD_HAS_AMOUNT = { Ignite = true, Regen = true, Grow = true, Decay = true }
function CardVisuals.KeywordEntries(card, unit)
	local printed = card.Keywords or {}
	local list = {}
	for _, name in ipairs(KEYWORD_ORDER) do
		local value = printed[name]
		if unit and unit[name] ~= nil then
			value = unit[name]
		end
		if KEYWORD_HAS_AMOUNT[name] then
			if type(value) == "number" and value > 0 then
				table.insert(list, { Name = name, Amount = value })
			end
		elseif value then
			table.insert(list, { Name = name })
		end
	end
	return list
end
-- (older name, still used in a few places)
function CardVisuals.ActiveKeywords(card, unit)
	local names = {}
	for _, entry in ipairs(CardVisuals.KeywordEntries(card, unit)) do
		table.insert(names, entry.Name)
	end
	return names
end

-- What each keyword does (inspect windows and help)
CardVisuals.KeywordInfo = {
	Rush = "Can attack the turn it's played.",
	Shield = "Blocks the next hit completely, then breaks.",
	Ignite = "When played, deals %d damage to the enemy unit across from it.",
	Regen = "Heals %d at the end of each of your turns.",
	Grow = "Gets +%d Power for good at the start of each of your turns.",
	Decay = "At the end of your turn, the enemy unit across takes %d damage.",
	Streak = "Attacks the enemy Commander directly, flying past the unit across (unless that unit has Streak or Intercept).",
	Intercept = "Streak units can't fly past it: they have to fight it.",
}
function CardVisuals.KeywordExplain(entry)
	local info = CardVisuals.KeywordInfo[entry.Name] or ""
	local title = entry.Name .. (entry.Amount and (" " .. entry.Amount) or "")
	return title, (info:find("%%d") and info:format(entry.Amount or 1) or info)
end

-- The card's text without its keywords (those are shown as symbols)
function CardVisuals.AbilityOnlyText(card)
	local result = card.AbilityText or ""
	if card.HPCost then
		result = ("Also costs %d HP."):format(card.HPCost) .. (result ~= "" and (" " .. result) or "")
	end
	if card.Type == "Commander" and card.CommanderAbility then
		result = ("Ability (%d): %s"):format(card.CommanderAbility.EnergyCost, card.CommanderAbility.Text)
	end
	if card.Type == "Celestial" and card.PairsWith then
		result = result .. (result ~= "" and "\n" or "") .. "Pairs with " .. table.concat(card.PairsWith, " + ")
	end
	return result
end

---------------------------------------------------------------------
-- Card details for inspect views (collection, binder): what the card is and
-- what every word on it means, in plain language.
-- CardVisuals.DescribeCard(cardId, options) -> rich-text lines
--   options.Finish   the finish being shown
--   options.Owned    "You own: ..." text (optional)
-- CardVisuals.DrawInfoPanel(parent, cardId, options) draws a panel with them:
--   options.Position, options.Size (scale UDim2s), options.ZIndex
---------------------------------------------------------------------
local TYPE_HELP = {
	Unit = "Units go into one of your 3 lanes. When you end your turn, they attack the lane straight across (an empty lane hits the enemy Commander).",
	Spell = "Spells happen once, then go to your graveyard.",
	Commander = "Your Commander leads your deck (20 HP). Use its ability once per turn. If it reaches 0 HP, you lose.",
	Celestial = "Your Celestial waits face-down in your Star Gate. Summon it into an empty lane; if it's defeated it goes back to the gate and costs 2 more next time.",
	Anomaly = "Anomalies are set face-down and spring on your opponent's turn.",
}

local function esc(value)
	return (tostring(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function CardVisuals.DescribeCard(cardId, options)
	options = options or {}
	local card = CardDatabase.GetCard(cardId)
	local lines = {}
	if not card then
		return lines
	end
	local faction = card.Faction == "Neutral" and "Neutral" or card.Faction
	local head = ("%s %s  |  %s"):format(faction, card.Type, card.Rarity)
	if card.StarCost then
		head = head .. ("  |  %d star%s"):format(card.StarCost, card.StarCost == 1 and "" or "s")
	end
	table.insert(lines, ('<font color="#AAA0C8">%s</font>'):format(esc(head)))
	local cost = {}
	if card.EnergyCost then
		table.insert(cost, ("%d energy"):format(card.EnergyCost))
	end
	if card.HPCost then
		table.insert(cost, ("%d of your Commander's HP"):format(card.HPCost))
	end
	if card.Power and card.Type ~= "Commander" then
		table.insert(lines, ("<b>Power %d  |  Health %d</b>"):format(card.Power, card.HP or 0))
	elseif card.Type == "Commander" then
		table.insert(lines, ("<b>Health %d</b>"):format(card.HP or 20))
	end
	if #cost > 0 then
		table.insert(lines, "<b>Costs:</b> " .. esc(table.concat(cost, " + ")))
	end
	table.insert(lines, "")
	for _, entry in ipairs(CardVisuals.KeywordEntries(card)) do
		local title, info = CardVisuals.KeywordExplain(entry)
		table.insert(lines, ('<b><font color="#FFCD5A">%s</font></b>: %s'):format(esc(title), esc(info)))
	end
	local rest = CardVisuals.AbilityOnlyText(card)
	if rest ~= "" then
		table.insert(lines, esc(rest))
	end
	table.insert(lines, "")
	if TYPE_HELP[card.Type] then
		table.insert(lines, ('<font color="#AAA0C8">%s</font>'):format(esc(TYPE_HELP[card.Type])))
	end
	if card.Rarity == "Legendary" and CardDatabase.IsMainDeckType(card.Type) then
		table.insert(lines, ('<font color="#FFCD5A">%s</font>'):format("Legendary: only 1 copy per deck."))
	end
	if options.Finish or options.Owned then
		table.insert(lines, "")
	end
	if options.Finish then
		table.insert(lines, ('<font color="#AAA0C8">Finish: %s</font>'):format(
			esc(CardVisuals.FinishNames[options.Finish] or options.Finish)))
	end
	if options.Owned then
		table.insert(lines, ('<font color="#AAA0C8">%s</font>'):format(esc(options.Owned)))
	end
	return lines
end

function CardVisuals.DrawInfoPanel(parent, cardId, options)
	options = options or {}
	local card = CardDatabase.GetCard(cardId)
	local z = options.ZIndex or 20
	local panel = make("Frame", {
		Name = "CardInfo",
		Position = options.Position or UDim2.fromScale(0.55, 0.1),
		Size = options.Size or UDim2.fromScale(0.38, 0.72),
		BackgroundColor3 = Color3.fromRGB(20, 16, 40),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ZIndex = z,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, panel)
	make("UIStroke", { Color = Color3.fromRGB(255, 205, 90), Thickness = 1.5, Transparency = 0.4 }, panel)
	require(ReplicatedStorage:WaitForChild("UiTheme")).Panel(panel, { Color = false })
	local title = make("TextLabel", {
		Name = "CardInfoTitle",
		Position = UDim2.fromScale(0.05, 0.03),
		Size = UDim2.fromScale(0.9, 0.09),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextColor3 = Color3.fromRGB(255, 205, 90),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = card and card.Name or "",
		ZIndex = z + 1,
	}, panel)
	make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 30 }, title)
	local body = make("TextLabel", {
		Name = "CardInfoText",
		Position = UDim2.fromScale(0.05, 0.14),
		Size = UDim2.fromScale(0.9, 0.83),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		TextWrapped = true,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = table.concat(CardVisuals.DescribeCard(cardId, options), "\n"),
		ZIndex = z + 1,
	}, panel)
	-- readable on a phone, never huge on a big screen
	make("UITextSizeConstraint", { MinTextSize = 12, MaxTextSize = options.TextSize or 19 }, body)
	return panel
end

---------------------------------------------------------------------
-- On-board status, drawn over the whole card so it reads at a glance:
--   Summoning sickness (can't attack yet): the art dims to a cold blue, a
--     big "Zzz" badge sits on it and a ribbon says "READY NEXT TURN".
--   Shield: a glowing blue bubble around the whole card and a shield badge.
-- art = { x, y, w, h } of the art window (fractions of the card).
---------------------------------------------------------------------
local SHIELD_BLUE = Color3.fromRGB(110, 200, 255)
local function addUnitStatus(face, unit, art)
	if not unit then
		return
	end
	if unit.CanAttack == false then
		-- frozen by an Anomaly looks icy instead of sleepy
		local frozen = unit.Frozen == true
		local dimmer = make("Frame", {
			Name = "SleepDim",
			Position = UDim2.fromScale(art[1], art[2]),
			Size = UDim2.fromScale(art[3], art[4]),
			BackgroundColor3 = frozen and Color3.fromRGB(120, 200, 240) or Color3.fromRGB(20, 30, 70),
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, face)
		make("UICorner", { CornerRadius = UDim.new(0.06, 0) }, dimmer)
		local badge = make("Frame", {
			Name = "SleepBadge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(art[1] + art[3] * 0.78, art[2] + art[4] * 0.58),
			Size = UDim2.fromScale(0.3, 0.214), -- a circle on a 5:7 card
			BackgroundColor3 = Color3.fromRGB(30, 40, 90),
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			ZIndex = 9,
		}, face)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, badge)
		make("UIStroke", { Color = Color3.fromRGB(170, 190, 255), Thickness = 2 }, badge)
		local z = text(badge, "Sleeping", UDim2.fromScale(0.1, 0.15), UDim2.fromScale(0.8, 0.7), frozen and "ICE" or "Zzz", 40, {
			TextColor3 = Color3.fromRGB(200, 215, 255), Font = Enum.Font.GothamBlack })
		z.ZIndex = 10
		local ribbon = make("Frame", {
			Name = "SleepRibbon",
			Position = UDim2.fromScale(art[1], art[2]),
			Size = UDim2.fromScale(art[3], 0.075),
			BackgroundColor3 = Color3.fromRGB(25, 30, 70),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 9,
		}, face)
		local r = text(ribbon, "ReadyText", UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8),
			frozen and "FROZEN: SKIPS ITS NEXT ATTACK" or "READY NEXT TURN", 20,
			{ TextColor3 = Color3.fromRGB(200, 215, 255) })
		r.ZIndex = 10
	end
	if unit.Shield then
		local bubble = make("Frame", {
			Name = "ShieldBubble",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1.06, 1.045),
			BackgroundColor3 = SHIELD_BLUE,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			ZIndex = 11,
		}, face)
		make("UICorner", { CornerRadius = UDim.new(0.09, 0) }, bubble)
		make("UIStroke", { Color = SHIELD_BLUE, Thickness = 4, Transparency = 0.05 }, bubble)
		make("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.55),
				NumberSequenceKeypoint.new(0.5, 0.95),
				NumberSequenceKeypoint.new(1, 0.55),
			}),
		}, bubble)
		local icon = UiAssets.Keywords.Shield
		local badge = make(icon and "ImageLabel" or "Frame", {
			Name = "ShieldBadge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.22, 0.34),
			Size = UDim2.fromScale(0.24, 0.171),
			BackgroundColor3 = SHIELD_BLUE,
			BackgroundTransparency = icon and 1 or 0.2,
			ZIndex = 12,
		}, face)
		if icon then
			badge.Image = icon
			badge.ScaleType = Enum.ScaleType.Fit
		else
			make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, badge)
			text(badge, "ShieldWord", UDim2.fromScale(0.05, 0.3), UDim2.fromScale(0.9, 0.4), "SHIELD", 16).ZIndex = 13
		end
	end
end

-- The plain placeholder look, used for factions that don't have a frame yet
local function drawFlat(target, cardId, options)
	local card = CardDatabase.GetCard(cardId)
	local unit = options.Unit
	local mythic = options.Finish == "Mythic"

	target.BackgroundColor3 = CardVisuals.FactionColors[card.Faction] or CardVisuals.FactionColors.Neutral
	target.BackgroundTransparency = options.Dim and 0.6 or 0
	make("UICorner", { Name = "CardCorner", CornerRadius = UDim.new(0.06, 0) }, target)
	make("UIStroke", {
		Name = "RarityStroke",
		Color = mythic and CardVisuals.MythicColor or (CardVisuals.RarityColors[card.Rarity] or WHITE),
		Thickness = mythic and 3 or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, target)
	if mythic then
		make("UIGradient", {
			Name = "MythicTint",
			Color = ColorSequence.new(Color3.fromRGB(255, 170, 230), Color3.fromRGB(170, 200, 255)),
			Rotation = 45,
		}, target)
	end

	local cost = costFor(card, options)
	local showCost = cost ~= nil
	if showCost then
		text(target, "Cost", UDim2.fromScale(0.03, 0.03), UDim2.fromScale(0.2, 0.14), tostring(cost), 26, {
			BackgroundTransparency = 0,
			BackgroundColor3 = options.CostRaised and COST_RAISED_COLOR or Color3.fromRGB(30, 60, 140),
		})
	end
	local nameX = showCost and 0.25 or 0.04
	text(target, "CardName", UDim2.fromScale(nameX, 0.02), UDim2.fromScale(0.97 - nameX, 0.18), card.Name, 24)

	local typeLine = card.Type
	if CardDatabase.IsMainDeckType(card.Type) then
		typeLine = card.Faction .. " " .. card.Type
	end
	text(target, "TypeLine", UDim2.fromScale(0.05, 0.2), UDim2.fromScale(0.9, 0.08), typeLine, 14, {
		Font = Enum.Font.Gotham,
		TextColor3 = Color3.fromRGB(235, 225, 255),
	})

	text(target, "CardText", UDim2.fromScale(0.06, 0.3), UDim2.fromScale(0.88, 0.45),
		CardVisuals.KeywordText(card, unit), 18, { Font = Enum.Font.Gotham })

	if card.Power then
		local power = unit and unit.Power or card.Power
		local hp = unit and unit.HP or card.HP
		local hurt = unit and unit.HP < unit.MaxHP
		text(target, "Stats", UDim2.fromScale(0.15, 0.78), UDim2.fromScale(0.7, 0.18), ("%d / %d"):format(power, hp), 30, {
			TextColor3 = hurt and Color3.fromRGB(255, 140, 140) or WHITE,
		})
	elseif card.Type == "Commander" then
		text(target, "Stats", UDim2.fromScale(0.15, 0.78), UDim2.fromScale(0.7, 0.18), options.StatsText or (card.HP .. " HP"), 30, {
			TextColor3 = options.StatsHurt and Color3.fromRGB(255, 140, 140) or WHITE,
		})
	end

	addUnitStatus(target, unit, { 0.04, 0.2, 0.92, 0.56 })
end

---------------------------------------------------------------------
-- Layered card: art, then panels, then the frame image, then text.
-- Positions are fractions of the card, measured from the frame images
-- (1060 x 1484, 5:7). All frames share the same layout.
---------------------------------------------------------------------
local LAYOUT = {
	Cost = { 0.070, 0.061, 0.122, 0.085 },      -- x, y, width, height
	Name = { 0.240, 0.075, 0.685, 0.055 },
	CommanderName = { 0.185, 0.076, 0.735, 0.052 },
	Art = { 0.108, 0.146, 0.786, 0.343 },
	FullArt = { 0.108, 0.146, 0.786, 0.712 },   -- Legendary art runs down behind the text box
	Type = { 0.100, 0.518, 0.803, 0.037 },
	TextBox = { 0.107, 0.586, 0.787, 0.272 },
	TextInner = { 0.150, 0.605, 0.700, 0.235 },
	Stats = { 0.370, 0.857, 0.262, 0.060 },     -- a little taller than the plate so numbers read at small sizes
	Stars = { 0.708, 0.895, 0.230, 0.035 },
	Sleep = { 0.640, 0.700, 0.200, 0.060 },
	Gem = { 0.826, 0.513, 0.064, 0.046 },       -- rarity gem at the right end of the type plate
}

local PLATE_TEXT_DARK = Color3.fromRGB(38, 26, 30)     -- dark words on light plates
local PLATE_TEXT_LIGHT = Color3.fromRGB(236, 228, 255)  -- light words on dark plates (Void)
local HURT_ON_LIGHT = Color3.fromRGB(190, 30, 30)
local HURT_ON_DARK = Color3.fromRGB(255, 120, 120)
local PANEL_COLORS = {
	Solar = Color3.fromRGB(58, 22, 10),
	Lunar = Color3.fromRGB(14, 24, 60),
	Nebula = Color3.fromRGB(40, 16, 58),
	Comet = Color3.fromRGB(8, 42, 46),
	Void = Color3.fromRGB(18, 14, 34),
	Neutral = Color3.fromRGB(34, 34, 40),
}
local STAR = utf8.char(0x2605)

local function place(object, key)
	local r = LAYOUT[key]
	object.Position = UDim2.fromScale(r[1], r[2])
	object.Size = UDim2.fromScale(r[3], r[4])
	return object
end

---------------------------------------------------------------------
-- Finish effects
---------------------------------------------------------------------
-- Pattern images. Upload them and paste each Asset ID here
-- (0 = not uploaded yet: the card still gets its foil, just without the pattern).
CardVisuals.EtchedTextureId = 79978724977480 -- etched_texture: embossed swirls (Textured)
CardVisuals.SecretTextureId = 118525143607709 -- secret_texture: fine prismatic lines (Mythic)

-- The glow behind Mythic cards: "Rainbow" (a full rainbow border), "Glow" (a soft
-- pale shimmer that only peeks through the frame's open edges) or "None"
CardVisuals.MythicAura = "None"

-- What each finish adds (numbers are see-through amounts: lower = stronger)
local FINISH_FX = {
	-- Holo: a classic holo art box: a diagonal rainbow sheen over the art, and as
	-- the light sweeps across, a bright band of rainbow leading a white glare
	-- (Prism = how strong that rainbow band is; lower = stronger)
	Holo = { ArtFoil = 0.36, Glare = 0.02, Prism = 0.22 },
	-- Textured: embossed swirls etched across the card, catching the rainbow,
	-- and a rainbow shimmer running around the frame
	Textured = { ArtFoil = 0.55, Prism = 0.3, CardFoil = 0.82, Glare = 0.1, Pattern = "Etched", PatternStrength = 0.5,
		PatternTile = 0.5, FrameShine = "Rainbow" },
	-- 3D: lifted off the table (shadow, gentle bob), deep parallax, gold shimmer on the frame
	["3D"] = { ArtFoil = 0.5, Prism = 0.28, Glare = 0.1, Float = true, Lift = true, FrameShine = "Gold" },
	-- Mythic: the galaxy foil over the whole card (UiAssets.Holo.Galaxy), colors
	-- cycling, a rainbow frame shimmer and glints popping up
	Mythic = { ArtFoil = 0.68, Prism = 0.3, CardFoil = 0.74, Glare = 0.08, FrameShine = "Rainbow", CycleColors = true, Aura = true },
}

-- The foil is a rainbow that repeats exactly every FOIL_PERIOD. It slides by
-- one period and then wraps back, landing on an identical picture, so the
-- loop never jumps. The layers are wider than what shows (FOIL_WIDE) so the
-- ends of the rainbow never come into view.
local FOIL_CYCLES = 4
local FOIL_PERIOD = 1 / FOIL_CYCLES
local FOIL_WIDE = 2.2
local HUES = {
	Color3.fromRGB(255, 90, 170), Color3.fromRGB(255, 210, 90),
	Color3.fromRGB(110, 240, 200), Color3.fromRGB(150, 130, 255),
}

local function rainbow(cycles)
	local keys = {}
	local count = #HUES * cycles
	for i = 0, count do
		table.insert(keys, ColorSequenceKeypoint.new(i / count, HUES[i % #HUES + 1]))
	end
	return ColorSequence.new(keys)
end
local FOIL = rainbow(FOIL_CYCLES)
local RAINBOW = rainbow(1)
local PRISM = rainbow(7) -- (many bands of color, so the flash shows the whole rainbow)
local GOLD_SHEEN = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 225, 130)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 235)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 170, 50)),
})

-- See-through except a bright stripe in the middle
local function bandTransparency(peak)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, peak),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end
-- Foil strength, rising and falling with the same repeat as the colors
local function foilTransparency(strength)
	local keys = {}
	local steps = FOIL_CYCLES * 2
	for i = 0, steps do
		table.insert(keys, NumberSequenceKeypoint.new(i / steps, i % 2 == 0 and math.min(strength + 0.18, 1) or strength))
	end
	return NumberSequence.new(keys)
end

-- Everything that moves is updated by one loop (players' screens only).
-- A normal (strong) table: Roblox can drop a GUI object from a weak table while
-- it's still on screen, which froze the holo/glare between redraws. Entries are
-- removed instead when the object is destroyed or has been off-screen a while.
local animated = {} -- [object] = { Kind, Phase, Added, ... }
local lastSweep = 0
local loopRunning = false
local GLARE_CYCLE, GLARE_SWEEP = 3.4, 2.8 -- seconds per glare, seconds it takes to cross (slow, so the light reads the etchings)

local function glareOffset(t, phase)
	local u = ((t + phase) % GLARE_CYCLE) / GLARE_SWEEP
	if u > 1 then
		return Vector2.new(1.6, 0) -- resting off the card (the jump back happens out of sight)
	end
	u = u * u * (3 - 2 * u)
	return Vector2.new(-1.3 + 2.6 * u, 0)
end

local function step()
	local t = os.clock()
	-- every 2 seconds, forget objects that left the screen without being destroyed
	-- (a grace period lets a card be drawn first and put on screen just after)
	local sweep = t - lastSweep > 2
	if sweep then
		lastSweep = t
	end
	for object, info in pairs(animated) do
		if object.Parent == nil
			or (sweep and t - info.Added > 2 and not object:IsDescendantOf(game)) then
			animated[object] = nil
		elseif info.Kind == "Glare" then
			object.Offset = (info.Manual and Vector2.new(info.Manual, 0) or glareOffset(t, info.Phase))
				+ Vector2.new(info.Lead or 0, 0) -- (the rainbow band trails just behind the light)
		elseif info.Kind == "Foil" then
			-- slides exactly one repeat, then wraps to an identical picture
			local shift = ((t * info.Speed + info.Phase) % FOIL_PERIOD) - FOIL_PERIOD / 2
			object.Offset = Vector2.new(shift, 0)
		elseif info.Kind == "GlareImage" then
			-- the uploaded glare streak, on the same timing as the drawn glare
			-- (or held where the player is pointing: CardVisuals.MakeHandheld)
			object.Position = UDim2.fromScale(0.5 + (info.Manual or glareOffset(t, info.Phase).X), 0.5)
		elseif info.Kind == "Twinkle" then
			-- one glint from the sparkle sheet: grows, flashes, fades, then pops up somewhere new
			local u = t * info.Speed + info.Phase
			local cycle = math.floor(u)
			local frame = math.floor((u - cycle) * 16)
			object.Position = UDim2.fromScale(-(frame % 4), -math.floor(frame / 4))
			if info.Cycle ~= cycle and object.Parent then
				info.Cycle = cycle
				local function hash(n)
					local v = math.sin(n * 12.9898 + (info.X or 1) * 78.233) * 43758.5453
					return v - math.floor(v)
				end
				object.Parent.Position = UDim2.fromScale(0.08 + 0.84 * hash(cycle), 0.08 + 0.84 * hash(cycle + 0.5))
			end
		elseif info.Kind == "Slide" then
			-- a tiled texture sliding sideways by exactly one tile, then wrapping
			object.Position = UDim2.fromScale(-((t * info.Speed + info.Phase) % info.Tile), 0)
		elseif info.Kind == "Spin" then
			object.Rotation = (t * info.Speed + info.Phase * 40) % 360
		elseif info.Kind == "Float" then
			object.Position = UDim2.fromScale(0.5 + 0.045 * math.sin(t * 0.9 + info.Phase),
				0.5 + 0.035 * math.cos(t * 0.7 + info.Phase))
		elseif info.Kind == "Bob" then
			object.Position = UDim2.fromScale(0.5, 0.5 - 0.012 * (1 + math.sin(t * 1.6 + info.Phase)))
		elseif info.Kind == "Shadow" then
			-- the card rises, so its shadow slides further out from under it
			local lift = 0.012 * (1 + math.sin(t * 1.6 + info.Phase))
			object.Position = UDim2.fromScale(0.53 + lift * 1.5, 0.53 + lift * 2.5)
		elseif info.Kind == "Particle" then
			-- rises from the bottom of the card and fades, then starts again
			local u = ((t * 0.35 + info.Phase) % 1)
			object.Position = UDim2.fromScale(info.X + 0.04 * math.sin(t * 2 + info.Phase * 6), 0.95 - u * 0.95)
			object.BackgroundTransparency = 0.1 + 0.9 * math.abs(u * 2 - 1)
			object.Rotation = 45 + t * 90
		end
	end
end

local function animate(object, kind, phase, extra)
	local info = { Kind = kind, Phase = phase, Added = os.clock() }
	for k, v in pairs(extra or {}) do
		info[k] = v
	end
	if not RunService:IsClient() then
		-- drawn by the server (the shop's displays): remember the motion on the
		-- object, and each player's screen animates it (CardVisuals.AnimateWorld)
		object:SetAttribute("CardAnim", kind)
		object:SetAttribute("CardAnimPhase", phase)
		if info.Speed then
			object:SetAttribute("CardAnimSpeed", info.Speed)
		end
		if info.X then
			object:SetAttribute("CardAnimX", info.X)
		end
		if info.Tile then
			object:SetAttribute("CardAnimTile", info.Tile)
		end
		if info.Lead then
			object:SetAttribute("CardAnimLead", info.Lead)
		end
		return
	end
	animated[object] = info
	if not loopRunning then
		loopRunning = true
		RunService.RenderStepped:Connect(step)
	end
end

-- Players' screens: animate the server-drawn cards inside root (and any added later)
function CardVisuals.AnimateWorld(root)
	local function register(object)
		local kind = object:GetAttribute("CardAnim")
		if kind and not animated[object] then
			animate(object, kind, object:GetAttribute("CardAnimPhase") or 0, {
				Speed = object:GetAttribute("CardAnimSpeed"),
				X = object:GetAttribute("CardAnimX"),
				Tile = object:GetAttribute("CardAnimTile"),
				Lead = object:GetAttribute("CardAnimLead"),
			})
		end
	end
	for _, object in ipairs(root:GetDescendants()) do
		register(object)
	end
	root.DescendantAdded:Connect(register)
end

-- A see-through layer with a gradient. wide = stretch it past both sides
-- (for the sliding foil, so the rainbow's ends never show).
local function gradientLayer(parent, name, zIndex, color, transparency, rotation, wide)
	local layer = make("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(wide and FOIL_WIDE or 1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, parent)
	local gradient = make("UIGradient", {
		Name = "Shine",
		Color = color,
		Transparency = transparency,
		Rotation = rotation,
	}, layer)
	return layer, gradient
end

-- A clipped area of the card that whole-card effects stay inside. With a
-- corner radius it's a CanvasGroup, which (unlike a plain Frame) clips its
-- contents to rounded corners, so nothing pokes out past a curved frame.
local function clipArea(face, name, rect, zIndex, corner)
	local area = make(corner and "CanvasGroup" or "Frame", {
		Name = name,
		Position = UDim2.fromScale(rect[1], rect[2]),
		Size = UDim2.fromScale(rect[3], rect[4]),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = zIndex,
	}, face)
	if corner then
		make("UICorner", { CornerRadius = UDim.new(corner, 0) }, area)
	end
	return area
end

local CARD_ASPECT = 1060 / 1484
-- The inside of a normal card (art window down to the bottom of the text box):
-- whole-card foil stays in here, so it never shows past the frame's edges
CardVisuals.InnerRect = { 0.108, 0.146, 0.786, 0.712 }

-- An uploaded holo texture (UiAssets.Holo), tiled in squares and sliding
-- sideways over holder. w, h = holder's size as fractions of the card face.
-- lit = an etched pattern (the white line art): it stays still, faintly visible,
-- and a rainbow light sweeps across it in time with the glare, lighting the lines up.
CardVisuals.EtchBase = 0.6 -- how faint an etching is away from the light (1 = invisible)
-- a still rainbow tint over foil art (even without the sliding foil), so a foil
-- card looks foil at a glance: added to the finish's ArtFoil transparency
CardVisuals.StaticFoilFade = 0.3
-- false = no rainbow foil sliding across the card: the glare lighting up the
-- etched patterns carries the shine instead
CardVisuals.MovingFoil = false
-- lit = true lights the pattern in rainbow colors; lit = "white" keeps the
-- image's own colors (the galaxy). base = how faint it is away from the light.
local function foilTexture(holder, image, w, h, transparency, phase, zIndex, speed, lit, base)
	if not image or w <= 0 or h <= 0 then
		return nil
	end
	local tile = h / (w * CARD_ASPECT) -- one square tile's width, as a share of the holder's width
	local sheen = make("ImageLabel", {
		Name = lit and "HoloPattern" or "HoloTexture",
		BackgroundTransparency = 1,
		Image = image,
		ImageTransparency = transparency,
		ScaleType = Enum.ScaleType.Tile,
		Size = UDim2.fromScale(1 + tile, 1),
		TileSize = UDim2.fromScale(tile / (1 + tile), 1),
		ZIndex = zIndex,
	}, holder)
	if lit then
		-- still etching (exactly the holder's size, so the light band lines up with the
		-- glare); the light is a see-through band in a gradient that rides the glare
		sheen.Size = UDim2.fromScale(1, 1)
		sheen.TileSize = UDim2.fromScale(tile, 1)
		base = base or CardVisuals.EtchBase
		local light = make("UIGradient", {
			Name = "EtchLight",
			Color = lit == "white" and ColorSequence.new(Color3.fromRGB(255, 255, 255)) or FOIL,
			Rotation = 25,
			-- (a wide band, so the light catches lots of lines at once)
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, base),
				NumberSequenceKeypoint.new(0.22, base),
				NumberSequenceKeypoint.new(0.4, 0.1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.6, 0.1),
				NumberSequenceKeypoint.new(0.78, base),
				NumberSequenceKeypoint.new(1, base),
			}),
		}, sheen)
		light.Offset = Vector2.new(1.6, 0)
		animate(light, "Glare", phase)
	else
		animate(sheen, "Slide", phase, { Speed = speed or 0.05, Tile = tile })
	end
	return sheen
end

local function holoImage(key)
	return UiAssets.Holo and UiAssets.Holo[key]
end

-- Glints from the sparkle sheet that pop up around the card (Legendary cards
-- and the Mythic finish)
CardVisuals.TwinkleSize = 0.17 -- glint size as a share of the card's foil area
local function addTwinkles(face, rect, count, zIndex)
	local sheet = holoImage("Sparkle")
	if not sheet then
		return
	end
	local area = make("Frame", {
		Name = "TwinkleArea",
		Position = UDim2.fromScale(rect[1], rect[2]),
		Size = UDim2.fromScale(rect[3], rect[4]),
		BackgroundTransparency = 1,
		ZIndex = zIndex,
	}, face)
	for i = 1, count do
		local window = make("Frame", {
			Name = "Glint",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(CardVisuals.TwinkleSize, CardVisuals.TwinkleSize),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = zIndex,
		}, area)
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, window)
		local frames = make("ImageLabel", {
			Name = "Sheet",
			Size = UDim2.fromScale(4, 4),
			BackgroundTransparency = 1,
			Image = sheet,
			ZIndex = zIndex,
		}, window)
		animate(frames, "Twinkle", math.random() + i / count, { Speed = 0.45 + 0.1 * i, X = i * 3.7 + math.random() })
	end
end

--[[ Adds the finish's effects to a drawn card face.
	artHolder  what holds the art (the foil over the art goes in here)
	frameImage the card's frame image (a tinted copy makes the frame shine)
	inner      the area whole-card foil stays inside { x, y, w, h }
	corner     round that area's corners by this much (full-art frames) ]]
local function addFinish(face, artHolder, finish, frameImage, inner, corner, card)
	local fx = FINISH_FX[finish]
	if not fx then
		return
	end
	local phase = math.random() * GLARE_CYCLE
	local moving = true -- (the server records the motion; players' screens play it)
	inner = inner or CardVisuals.InnerRect

	-- Rainbow foil over the art, and a bright glare sweeping across it
	artHolder.ClipsDescendants = true
	local _, artFoil = gradientLayer(artHolder, "HoloFoil", 1, FOIL, foilTransparency(fx.ArtFoil), 25, true)
	-- a rainbow band riding along with the glare (the holo "flash")
	if fx.Prism then
		local p = fx.Prism
		local _, prism = gradientLayer(artHolder, "HoloPrism", 1, PRISM, NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.34, 1),
			NumberSequenceKeypoint.new(0.44, math.min(1, p + 0.25)),
			NumberSequenceKeypoint.new(0.5, p),
			NumberSequenceKeypoint.new(0.56, math.min(1, p + 0.25)),
			NumberSequenceKeypoint.new(0.66, 1),
			NumberSequenceKeypoint.new(1, 1),
		}), 25)
		prism.Offset = Vector2.new(1.6, 0)
		animate(prism, "Glare", phase, { Lead = -0.14 })
	end
	local _, glare = gradientLayer(artHolder, "HoloBand", 1, ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		bandTransparency(fx.Glare), 25)
	glare.Offset = Vector2.new(1.6, 0)
	if moving then
		animate(glare, "Glare", phase)
	end
	local artSize = artHolder.Size
	local aw, ah = artSize.X.Scale, artSize.Y.Scale
	if CardVisuals.MovingFoil then
		animate(artFoil, "Foil", phase, { Speed = 0.05 })
		-- the uploaded foil grain, when there is one: it carries the color, so the
		-- drawn rainbow underneath steps back
		if foilTexture(artHolder, holoImage("Sheen"), aw, ah, fx.ArtFoil, phase, 1) then
			artFoil.Transparency = foilTransparency(math.min(0.92, fx.ArtFoil + 0.25))
		end
	else
		-- held still: a gentle rainbow sheen over the art
		artFoil.Transparency = foilTransparency(math.min(0.95, fx.ArtFoil + CardVisuals.StaticFoilFade))
	end
	-- the uploaded glare streak replaces the drawn one
	local glareImage = holoImage("Glare")
	if glareImage then
		glare.Transparency = NumberSequence.new(1)
		local streak = make("ImageLabel", {
			Name = "HoloGlare",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(2.1, 0.5),
			Size = UDim2.fromScale(1.2, 1.2),
			BackgroundTransparency = 1,
			Image = glareImage,
			ImageTransparency = math.min(0.9, fx.Glare + 0.05),
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 1,
		}, artHolder)
		animate(streak, "GlareImage", phase)
	end
	-- the card's faction pattern in the foil (not on Mythic, which has its galaxy)
	local factionPattern = card and UiAssets.Holo and UiAssets.Holo.Faction and UiAssets.Holo.Faction[card.Faction]
	if factionPattern and finish ~= "Mythic" then
		foilTexture(artHolder, factionPattern, aw, ah, 0.05, phase, 1, 0, true, finish == "Holo" and 0.5 or nil)
	end
	-- 3D: tiny sparkles over the art, flaring up as the light passes
	if finish == "3D" then
		foilTexture(artHolder, holoImage("Starfield"), aw, ah, 0.1, phase, 1, 0, "white", 0.6)
	end

	-- Foil over the inside of the card (art, bars, text box), under the text
	if fx.CardFoil then
		-- under the frame, so the frame trims it along its exact shape
		local area = clipArea(face, "CardFoilArea", inner, 4, corner)
		local _, cardFoil = gradientLayer(area, "CardShine", 4, FOIL, foilTransparency(fx.CardFoil), 0, true)
		local _, cardGlare = gradientLayer(area, "CardGlare", 4, ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			bandTransparency(math.min(fx.Glare + 0.15, 1)), 25)
		cardGlare.Offset = Vector2.new(1.6, 0)
		if CardVisuals.MovingFoil then
			if foilTexture(area, holoImage("Sheen"), inner[3], inner[4], math.min(0.95, fx.CardFoil + 0.08), phase + 0.3, 4, 0.04) then
				cardFoil.Transparency = foilTransparency(math.min(0.95, fx.CardFoil + 0.1))
			end
			animate(cardFoil, "Foil", phase + 0.05, { Speed = fx.CycleColors and 0.14 or 0.04 })
		else
			cardFoil.Transparency = NumberSequence.new(1)
		end
		-- Mythic: the galaxy foil over the whole card, held still and lit up by the
		-- glare like the etchings (keeping its own colors, a little more visible at rest)
		if finish == "Mythic" then
			foilTexture(area, holoImage("Galaxy"), inner[3], inner[4], 0.2, phase + 0.1, 4, 0, "white", 0.72)
		end
		if moving then
			animate(cardGlare, "Glare", phase + 0.1)
		end
	end

	-- The pattern in the foil: etched swirls (Textured) or prismatic lines
	-- (Mythic), tinted by the sliding rainbow
	local patternId = fx.Pattern == "Etched" and CardVisuals.EtchedTextureId
		or fx.Pattern == "Secret" and CardVisuals.SecretTextureId or 0
	-- the new etched lines replace the old swirl texture once uploaded
	local newEtched = fx.Pattern == "Etched" and holoImage("Etched")
	if newEtched then
		local area = clipArea(face, "PatternArea", inner, 4, corner)
		foilTexture(area, newEtched, inner[3], inner[4], 0.06, phase + 0.1, 4, 0, true)
		patternId = 0
	end
	if patternId ~= 0 then
		local area = clipArea(face, "PatternArea", inner, 4, corner)
		-- square tiles: work out the tile height from the area's real shape
		local areaAspect = (inner[3] * CARD_ASPECT) / inner[4]
		local pattern = make("ImageLabel", {
			Name = "FoilPattern",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(FOIL_WIDE, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://" .. patternId,
			ImageTransparency = fx.PatternStrength,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromScale(fx.PatternTile / FOIL_WIDE, fx.PatternTile * areaAspect),
			ZIndex = 4,
		}, area)
		local tint = make("UIGradient", {
			Name = "Shine",
			Color = FOIL,
			Transparency = foilTransparency(0),
			Rotation = 0,
		}, pattern)
		if moving then
			animate(tint, "Foil", phase, { Speed = fx.CycleColors and 0.16 or 0.05 })
		end
	end

	-- Glints popping up around Legendary cards and every Mythic
	if card and (card.Rarity == "Legendary" or finish == "Mythic") then
		addTwinkles(face, inner, finish == "Mythic" and 4 or 2, 6)
	end

	-- A shimmer running around the frame itself: a tinted copy of the frame
	-- image, so it follows the frame's exact shape (cut corners and all)
	if fx.FrameShine and frameImage then
		local shine = make("ImageLabel", {
			Name = "FrameShine",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = frameImage,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 6,
		}, face)
		local sweep = make("UIGradient", {
			Name = "Shine",
			Color = fx.FrameShine == "Gold" and GOLD_SHEEN or RAINBOW,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 1),
				NumberSequenceKeypoint.new(0.5, 0.15),
				NumberSequenceKeypoint.new(0.7, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Rotation = 0,
		}, shine)
		if moving then
			-- turning all the way around loops perfectly
			animate(sweep, "Spin", phase, { Speed = fx.CycleColors and 140 or 70 })
		end
	end

	-- Lifted off the table: a drop shadow under the card and a gentle bob
	if fx.Lift then
		local shadow = make("Frame", {
			Name = "LiftShadow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.53, 0.53),
			Size = UDim2.fromScale(0.9, 0.93),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 1, -- behind the art and frame, so only the part sticking out shows
		}, face)
		make("UICorner", { CornerRadius = UDim.new(0.06, 0) }, shadow)
		if moving then
			animate(face, "Bob", phase)
			animate(shadow, "Shadow", phase)
		end
	end

	-- Mythic: a glow behind the card (see CardVisuals.MythicAura), and sparkles rising off it
	local auraStyle = CardVisuals.MythicAura
	if fx.Aura and auraStyle ~= "None" then
		local soft = auraStyle == "Glow"
		local aura = make("Frame", {
			Name = "FinishAura",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			-- the soft glow sits just inside the card, so only the frame's gaps show it
			Size = soft and UDim2.fromScale(0.93, 0.95) or UDim2.fromScale(1.03, 1.02),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = soft and 0.35 or 0.3,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, face)
		make("UICorner", { CornerRadius = UDim.new(0.07, 0) }, aura)
		local colors = RAINBOW
		if soft then
			-- pale pearl tones instead of a full rainbow
			colors = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 245, 225)),
				ColorSequenceKeypoint.new(0.33, Color3.fromRGB(225, 235, 255)),
				ColorSequenceKeypoint.new(0.66, Color3.fromRGB(250, 225, 245)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 245, 225)),
			})
		end
		local spin = make("UIGradient", { Name = "AuraColors", Color = colors, Rotation = 0 }, aura)
		if moving then
			animate(spin, "Spin", phase, { Speed = soft and 45 or 120 })
		end
	end
	for i = 1, fx.Particles or 0 do
		local spark = make("Frame", {
			Name = "Sparkle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.1 + 0.8 * (i / (fx.Particles + 1)), 0.9),
			Size = UDim2.fromScale(0.045, 0.032),
			BackgroundColor3 = i % 2 == 0 and Color3.fromRGB(255, 240, 180) or Color3.fromRGB(200, 240, 255),
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Rotation = 45,
			ZIndex = 8,
		}, face)
		make("UIAspectRatioConstraint", { AspectRatio = 1 }, spark)
		if moving then
			animate(spark, "Particle", (i * 0.37) % 1, { X = 0.1 + 0.8 * (i / (fx.Particles + 1)) })
		end
	end
end

-- A centered row of keyword symbols, each with its number (Grow 2 = symbol + "2").
-- x0 / width / y / rowH are fractions of the card.
local function drawKeywordRow(face, entries, x0, width, y, rowH, dim)
	local w = rowH * 1484 / 1060 -- a square icon: the card is 1.4 times taller than wide
	local numW = w * 0.7
	local cellWs, total = {}, 0
	for i, entry in ipairs(entries) do
		cellWs[i] = w + (entry.Amount and numW or 0)
		total = total + cellWs[i] + (i > 1 and 0.012 or 0)
	end
	local fit = math.min(1, width / math.max(total, 0.001)) -- shrink to fit if there are many
	local x = x0 + (width - total * fit) / 2
	local h = rowH * fit
	for i, entry in ipairs(entries) do
		local cell = make("Frame", {
			Name = "Keyword_" .. entry.Name,
			Position = UDim2.fromScale(x, y + (rowH - h) / 2),
			Size = UDim2.fromScale(cellWs[i] * fit, h),
			BackgroundTransparency = 1,
			ZIndex = 7,
		}, face)
		local iconFrac = w / cellWs[i]
		local image = UiAssets.Keywords[entry.Name]
		if image then
			make("ImageLabel", {
				Name = "Icon",
				Size = UDim2.fromScale(iconFrac, 1),
				BackgroundTransparency = 1,
				Image = image,
				ImageTransparency = dim,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 7,
			}, cell)
		else
			text(cell, "Icon", UDim2.new(), UDim2.fromScale(iconFrac, 1), entry.Name:sub(1, 1), 30,
				{ Font = Enum.Font.GothamBlack, ZIndex = 7 })
		end
		if entry.Amount then
			text(cell, "Amount", UDim2.fromScale(iconFrac, 0), UDim2.fromScale(1 - iconFrac, 1), tostring(entry.Amount), 40, {
				Font = Enum.Font.GothamBlack,
				TextTransparency = dim,
				TextStrokeTransparency = 0.4,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 7,
			})
		end
		x = x + (cellWs[i] + 0.012) * fit
	end
end

local function drawLayered(target, cardId, options, frameImage)
	local card = CardDatabase.GetCard(cardId)
	local unit = options.Unit
	local dim = options.Dim and 0.55 or 0
	local fullArt = card.Rarity == "Legendary"

	target.BackgroundTransparency = 1

	-- The card keeps its 5:7 shape inside whatever box it's drawn in
	local face = make("Frame", {
		Name = "CardFace",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, target)
	make("UIAspectRatioConstraint", { AspectRatio = 1060 / 1484 }, face)

	-- 1. Art (a faction-colored placeholder until the card has art)
	local artImage = CardArt.ArtFor(cardId)
	local fx = FINISH_FX[options.Finish]
	local floating = fx and fx.Float
	local artHolder
	local art = make("ImageLabel", {
		Name = "Art",
		BackgroundColor3 = CardVisuals.FactionColors[card.Faction] or CardVisuals.FactionColors.Neutral,
		BackgroundTransparency = artImage and 1 or dim,
		Image = artImage or "",
		ImageTransparency = dim,
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 2,
	}, face)
	if floating then
		-- 3D: the art sits in a window slightly bigger than it shows, and drifts
		artHolder = place(make("Frame", {
			Name = "ArtWindow",
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 2,
		}, face), fullArt and "FullArt" or "Art")
		art.Parent = artHolder
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.Position = UDim2.fromScale(0.5, 0.5)
		art.Size = UDim2.fromScale(1.1, 1.1)
		animate(art, "Float", math.random() * 6)
	else
		place(art, fullArt and "FullArt" or "Art")
		artHolder = art
	end

	-- 2. Text box panel (see-through on full-art cards so the art shows)
	local panel = place(make("Frame", {
		Name = "TextPanel",
		BackgroundColor3 = PANEL_COLORS[card.Faction] or PANEL_COLORS.Neutral,
		BackgroundTransparency = fullArt and 0.28 or 0,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, face), "TextBox")
	make("UICorner", { CornerRadius = UDim.new(0.12, 0) }, panel)

	local cost = costFor(card, options)
	local showCost = cost ~= nil
	if showCost then
		local disk = place(make("Frame", {
			Name = "CostDisk",
			BackgroundColor3 = options.CostRaised and COST_RAISED_COLOR or COST_COLOR,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, face), "Cost")
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, disk)
	end

	-- 3. The frame image
	make("ImageLabel", {
		Name = "Frame",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = frameImage,
		ImageTransparency = dim,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 5,
	}, face)

	-- 4. Text on top (light words on frames with dark plates, like Void's)
	local darkPlates = CardArt.HasDarkPlates(frameImage)
	local PLATE_TEXT = darkPlates and PLATE_TEXT_LIGHT or PLATE_TEXT_DARK
	local HURT = darkPlates and HURT_ON_DARK or HURT_ON_LIGHT
	local plateStroke = darkPlates and { TextStrokeTransparency = 0.55, TextStrokeColor3 = Color3.new(0, 0, 0) } or {}
	local function faceText(name, key, value, maxSize, props)
		local l = text(face, name, UDim2.new(), UDim2.new(), value, maxSize, props)
		place(l, key)
		l.ZIndex = 7
		l.TextTransparency = dim
		return l
	end

	if showCost then
		faceText("Cost", "Cost", tostring(cost), 40)
	end
	faceText("CardName", card.Type == "Commander" and "CommanderName" or "Name", card.Name, 30, {
		TextColor3 = PLATE_TEXT, TextStrokeTransparency = plateStroke.TextStrokeTransparency or 1,
	})
	local typeLine = card.Type
	if CardDatabase.IsMainDeckType(card.Type) then
		typeLine = card.Faction .. " " .. card.Type
	end
	faceText("TypeLine", "Type", typeLine, 20, { TextColor3 = PLATE_TEXT, TextStrokeTransparency = plateStroke.TextStrokeTransparency or 1 })
	-- Keywords as symbols with their numbers (Grow 2 = the Grow symbol and "2"),
	-- then the rest of the card's text underneath
	local entries = CardVisuals.KeywordEntries(card, unit)
	local rest = CardVisuals.AbilityOnlyText(card)
	if #entries == 0 then
		faceText("CardText", "TextInner", rest, 24, { Font = Enum.Font.Gotham })
	else
		local box = LAYOUT.TextInner
		local alone = rest == ""
		local rowH = alone and 0.09 or 0.058
		local rowY = alone and (box[2] + (box[4] - rowH) / 2) or (box[2] + 0.004)
		drawKeywordRow(face, entries, box[1], box[3], rowY, rowH, dim)
		if not alone then
			local l = text(face, "CardText", UDim2.fromScale(box[1], rowY + rowH + 0.006),
				UDim2.fromScale(box[3], box[2] + box[4] - (rowY + rowH + 0.006)), rest, 24, { Font = Enum.Font.Gotham })
			l.ZIndex = 7
			l.TextTransparency = dim
		end
	end

	if card.Power then
		local power = unit and unit.Power or card.Power
		local hp = unit and unit.HP or card.HP
		local hurt = unit and unit.HP < unit.MaxHP
		faceText("Stats", "Stats", ("%d / %d"):format(power, hp), 30, {
			TextColor3 = hurt and HURT or PLATE_TEXT,
			TextStrokeTransparency = plateStroke.TextStrokeTransparency or 1,
		})
	elseif card.Type == "Commander" then
		faceText("Stats", "Stats", options.StatsText or (card.HP .. " HP"), 30, {
			TextColor3 = options.StatsHurt and HURT or PLATE_TEXT,
			TextStrokeTransparency = plateStroke.TextStrokeTransparency or 1,
		})
	end
	if card.StarCost and card.Type ~= "Commander" then
		faceText("Stars", "Stars", string.rep(STAR, card.StarCost), 22, {
			TextColor3 = Color3.fromRGB(215, 150, 20),
		})
	end
	addUnitStatus(face, unit, LAYOUT.Art)

	-- rarity gem on the type plate
	local gemImage = UiAssets.Rarity[options.Finish == "Mythic" and "Mythic" or card.Rarity]
	if gemImage and card.Type ~= "Commander" then
		local gem = place(make("ImageLabel", {
			Name = "RarityGem",
			BackgroundTransparency = 1,
			Image = gemImage,
			ImageTransparency = dim,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 7,
		}, face), "Gem")
		gem.Name = "RarityGem"
	end
	addFinish(face, artHolder, options.Finish, frameImage, nil, nil, card)
end

---------------------------------------------------------------------
-- Full-art Mythic (Commanders and Celestials): the art fills the whole
-- frame, with no name or text plates. Only the numbers the game needs
-- are shown: a cost badge in the corner (Celestials), and Power / HP (or HP)
-- on a small plate when the card is on the battle board.
---------------------------------------------------------------------
local FULL = {
	Art = { 0.075, 0.07, 0.85, 0.875 },   -- fits inside the frame's opening
	Corner = 0.1,                         -- rounded so nothing shows past the frame
	Cost = { 0.115, 0.085 },              -- center of the cost badge (top-left corner)
	CostSize = { 0.17, 0.1214 },          -- a circle on a 5:7 card
	Plate = { 0.31, 0.80, 0.38, 0.065 },
}

local function drawMythicFullArt(target, cardId, options, frameImage)
	local card = CardDatabase.GetCard(cardId)
	local unit = options.Unit
	local dim = options.Dim and 0.55 or 0
	target.BackgroundTransparency = 1

	local face = make("Frame", {
		Name = "CardFace",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, target)
	make("UIAspectRatioConstraint", { AspectRatio = 1060 / 1484 }, face)

	-- The art sits in a rounded window that fits inside the frame's opening
	-- (the frame's top-left corner is cut in, so a square would poke out)
	local artImage = CardArt.ArtFor(cardId)
	local window = clipArea(face, "ArtMask", FULL.Art, 2, FULL.Corner)
	local art = make("ImageLabel", {
		Name = "Art",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = CardVisuals.FactionColors[card.Faction] or CardVisuals.FactionColors.Neutral,
		BackgroundTransparency = artImage and 1 or dim,
		Image = artImage or "",
		ImageTransparency = dim,
		ScaleType = Enum.ScaleType.Crop,
		ZIndex = 2,
	}, window)

	make("ImageLabel", {
		Name = "Frame",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = frameImage,
		ImageTransparency = dim,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 5,
	}, face)

	-- Cost badge for Celestials (Commanders have no cost, so none)
	local cost = costFor(card, options)
	if cost then
		local disk = make("Frame", {
			Name = "CostDisk",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(FULL.Cost[1], FULL.Cost[2]),
			Size = UDim2.fromScale(FULL.CostSize[1], FULL.CostSize[2]),
			BackgroundColor3 = options.CostRaised and COST_RAISED_COLOR or Color3.fromRGB(25, 30, 70),
			BackgroundTransparency = dim,
			BorderSizePixel = 0,
			ZIndex = 7,
		}, face)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, disk)
		make("UIStroke", { Color = Color3.fromRGB(255, 205, 90), Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, disk)
		local l = text(disk, "Cost", UDim2.fromScale(0.15, 0.15), UDim2.fromScale(0.7, 0.7), tostring(cost), 40)
		l.ZIndex = 8
		l.TextStrokeTransparency = 0.4
		l.TextTransparency = dim
	end

	-- Numbers only when they matter in a match: Power / HP for a Celestial on
	-- the board, HP for a Commander
	local statsText
	if unit and card.Power then
		statsText = ("%d / %d"):format(unit.Power, unit.HP)
	elseif options.StatsText then
		statsText = options.StatsText
	end
	if statsText then
		local p = FULL.Plate
		local plate = make("Frame", {
			Name = "StatPlate",
			Position = UDim2.fromScale(p[1], p[2]),
			Size = UDim2.fromScale(p[3], p[4]),
			BackgroundColor3 = Color3.fromRGB(30, 14, 8),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 7,
		}, face)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, plate)
		make("UIStroke", { Color = Color3.fromRGB(255, 200, 90), Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, plate)
		local hurt = (unit and unit.HP < unit.MaxHP) or options.StatsHurt
		local stats = text(plate, "Stats", UDim2.fromScale(0.08, 0.1), UDim2.fromScale(0.84, 0.8), statsText, 30, {
			TextColor3 = hurt and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(255, 240, 210),
		})
		stats.ZIndex = 8
	end
	addUnitStatus(face, unit, FULL.Art)
	-- no text box on full art: keyword symbols sit low on the art
	local entries = CardVisuals.KeywordEntries(card, unit)
	if #entries > 0 then
		drawKeywordRow(face, entries, FULL.Art[1] + 0.03, FULL.Art[3] - 0.06, 0.72, 0.06, dim)
	end

	-- the foil covers the art area, under the frame (the frame trims its edges)
	addFinish(face, window, "Mythic", frameImage, FULL.Art, FULL.Corner, CardDatabase.GetCard(cardId))
end

function CardVisuals.Draw(target, cardId, options)
	options = options or {}
	local card = CardDatabase.GetCard(cardId)
	local mythicFrame = card and options.Finish == "Mythic" and CardArt.MythicFrameFor(card)
	if mythicFrame then
		drawMythicFullArt(target, cardId, options, mythicFrame)
		return
	end
	local frameImage = card and CardArt.FrameFor(card)
	if frameImage then
		drawLayered(target, cardId, options, frameImage)
	else
		drawFlat(target, cardId, options)
	end
end

-- A face-down card (the opponent's hidden Celestial)
function CardVisuals.DrawFaceDown(target, label)
	if UiAssets.CardBack then
		target.BackgroundTransparency = 1
		local face = make("ImageLabel", {
			Name = "CardBack",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(14, 12, 40),
			BackgroundTransparency = 0,
			Image = UiAssets.CardBack,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 2,
		}, target)
		make("UIAspectRatioConstraint", { AspectRatio = 1060 / 1484 }, face)
		make("UICorner", { Name = "CardCorner", CornerRadius = UDim.new(0.06, 0) }, face)
		make("UIStroke", {
			Name = "RarityStroke",
			Color = Color3.fromRGB(205, 165, 80),
			Thickness = 2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, face)
		-- "?" needs no label: the back says it all
		if label and label ~= "" and label ~= "?" then
			local band = make("Frame", {
				Name = "LabelBand",
				Position = UDim2.fromScale(0, 0.74),
				Size = UDim2.fromScale(1, 0.16),
				BackgroundColor3 = Color3.fromRGB(10, 8, 26),
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, face)
			local l = text(band, "FaceDown", UDim2.fromScale(0.06, 0.1), UDim2.fromScale(0.88, 0.8), label, 22)
			l.ZIndex = 4
		end
		return
	end
	target.BackgroundColor3 = Color3.fromRGB(20, 26, 70)
	target.BackgroundTransparency = 0
	make("UICorner", { Name = "CardCorner", CornerRadius = UDim.new(0.06, 0) }, target)
	make("UIStroke", {
		Name = "RarityStroke",
		Color = Color3.fromRGB(140, 160, 255),
		Thickness = 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, target)
	text(target, "FaceDown", UDim2.fromScale(0.1, 0.3), UDim2.fromScale(0.8, 0.4), label, 22)
end


---------------------------------------------------------------------
-- Card flip: turns the card drawn in target over to show a new face.
--   drawFront(target)  draws the new face (target is cleared first)
--   options:
--     Duration  seconds for the whole turn (default 0.42)
--     Tease     a Color3: before turning, the card glows that color and
--               trembles (for big pulls), for TeaseTime seconds (default 0.6)
--     Shine     false = no white flash across the new face
--     OnShown   called the moment the new face appears
-- Waits until the flip is done (use task.spawn to flip several at once).
-- The card narrows to an edge (lifting a little, like it's picked up), the
-- face swaps, and it widens back out.
---------------------------------------------------------------------
local TweenService = game:GetService("TweenService")

local function faceIn(target)
	return target:FindFirstChild("CardFace") or target:FindFirstChild("CardBack")
end

local function play(object, t, props, style, direction)
	local tw = TweenService:Create(object, TweenInfo.new(t, style or Enum.EasingStyle.Quad,
		direction or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- Swaps the face's keep-the-shape constraint for a fixed pixel size, so the
-- face can be squeezed sideways. Returns the size and a function that undoes it.
local function unlockShape(face)
	local size = face.AbsoluteSize
	local constraint = face:FindFirstChildOfClass("UIAspectRatioConstraint")
	if constraint then
		constraint.Parent = nil
	end
	return size, function()
		if face.Parent then
			face.Size = UDim2.fromScale(1, 1)
			if constraint then
				constraint.Parent = face
			end
		end
	end
end

function CardVisuals.Flip(target, drawFront, options)
	options = options or {}
	local duration = options.Duration or 0.42
	local half = duration / 2
	local face = faceIn(target)
	if not face or not RunService:IsClient() or duration <= 0 then
		target:ClearAllChildren()
		drawFront(target)
		if options.OnShown then
			options.OnShown()
		end
		return
	end

	-- 1. Tease: the back glows and trembles before a big pull turns over
	if options.Tease then
		local glow = make("UIStroke", {
			Name = "TeaseGlow",
			Color = options.Tease,
			Thickness = 1,
			Transparency = 0.1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, face)
		local existing = face:FindFirstChild("RarityStroke")
		if existing then
			existing.Enabled = false
		end
		local teaseTime = options.TeaseTime or 0.6
		play(glow, teaseTime, { Thickness = 7 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
		local started = os.clock()
		local basePos = face.Position
		while os.clock() - started < teaseTime do
			local k = (os.clock() - started) / teaseTime -- trembles harder as it builds
			face.Rotation = math.sin(os.clock() * 55) * 2.5 * k
			face.Position = basePos + UDim2.fromOffset(math.sin(os.clock() * 41) * 2 * k, 0)
			task.wait()
		end
		face.Rotation = 0
		face.Position = basePos
	end

	-- 2. Narrow to an edge
	local size = unlockShape(face)
	local w, h = size.X, size.Y
	face.Size = UDim2.fromOffset(w, h)
	play(face, half, { Size = UDim2.fromOffset(0, h * 1.08) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.wait(half)

	-- 3. Swap the face (only the card itself: target's own scale/shape stay)
	face:Destroy()
	drawFront(target)
	local front = faceIn(target)
	if options.OnShown then
		options.OnShown()
	end
	if not front then
		return
	end
	local _, restore = unlockShape(front)
	front.Size = UDim2.fromOffset(0, h * 1.08)

	-- 4. Widen back out, with a white shine across the new face
	play(front, half, { Size = UDim2.fromOffset(w, h) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if options.Shine ~= false then
		local shine = make("Frame", {
			Name = "FlipShine",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(255, 250, 235),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			ZIndex = 30,
		}, front)
		local topZ = 0
		for _, d in ipairs(front:GetDescendants()) do
			if d:IsA("GuiObject") and d ~= shine then
				topZ = math.max(topZ, d.ZIndex)
			end
		end
		shine.ZIndex = topZ + 1
		make("UICorner", { CornerRadius = UDim.new(0.06, 0) }, shine)
		play(shine, half * 1.6, { BackgroundTransparency = 1 })
		task.delay(half * 1.7, function()
			shine:Destroy()
		end)
	end
	task.wait(half)
	restore()
end


---------------------------------------------------------------------
-- Hold a card to look at its foil: while the left mouse button (or a finger)
-- is held down on holder, the card lifts a little and leans toward the
-- cursor, and the glare follows the cursor instead of sweeping on its own, so
-- you light up the etchings yourself. Let go and it settles back.
-- (Roblox can't tilt a card in 3D on screen without breaking its clipping, so
-- the "tilt" is a small lift and lean.) Call once per holder; it keeps working
-- for whatever card is drawn into it later.
---------------------------------------------------------------------
local TAN_GLARE = math.tan(math.rad(25)) -- the glare bands lean 25 degrees

-- Points every glare on the card in root at a screen position (nil = let them sweep again)
function CardVisuals.SetLight(root, screenPos)
	for _, d in ipairs(root:GetDescendants()) do
		local info = animated[d]
		if info and (info.Kind == "Glare" or info.Kind == "GlareImage") then
			if not screenPos then
				info.Manual = nil
			else
				local box = d.Parent
				local size = box and box.AbsoluteSize
				if size and size.X > 0 then
					local center = box.AbsolutePosition + size / 2
					local dx, dy = screenPos.X - center.X, screenPos.Y - center.Y
					info.Manual = (dx + dy * TAN_GLARE) / size.X
				end
			end
		end
	end
end

function CardVisuals.MakeHandheld(holder)
	if not RunService:IsClient() or holder:GetAttribute("Handheld") then
		return
	end
	holder:SetAttribute("Handheld", true)
	local UserInputService = game:GetService("UserInputService")
	-- (found again each time: a view that clears the card also clears this)
	local function setScale(value)
		local scale = holder:FindFirstChild("HoldScale") or make("UIScale", { Name = "HoldScale" }, holder)
		scale.Scale = value
	end
	local held, basePos = nil, nil

	local function inside(pos)
		local p, size = holder.AbsolutePosition, holder.AbsoluteSize
		return pos.X >= p.X and pos.X <= p.X + size.X and pos.Y >= p.Y and pos.Y <= p.Y + size.Y
	end
	local function update(pos)
		CardVisuals.SetLight(holder, pos)
		-- lean a little toward the cursor
		local size = holder.AbsoluteSize
		if size.X > 0 and basePos then
			local center = holder.AbsolutePosition + size / 2
			local fx = math.clamp((pos.X - center.X) / size.X, -0.5, 0.5)
			local fy = math.clamp((pos.Y - center.Y) / size.Y, -0.5, 0.5)
			holder.Position = basePos + UDim2.fromOffset(fx * size.X * 0.05, fy * size.Y * 0.05)
		end
	end
	local function release()
		if not held then
			return
		end
		held = nil
		CardVisuals.SetLight(holder, nil)
		setScale(1)
		if basePos then
			holder.Position = basePos
		end
	end

	local connections = {}
	table.insert(connections, UserInputService.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if (kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch)
			and holder.Visible and holder.Parent and inside(input.Position) then
			held = input
			basePos = holder.Position
			setScale(1.06)
			update(input.Position)
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if held and (input.UserInputType == Enum.UserInputType.MouseMovement
			or (input.UserInputType == Enum.UserInputType.Touch and input == held)) then
			update(input.Position)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if held and (input.UserInputType == Enum.UserInputType.MouseButton1
			or (input.UserInputType == Enum.UserInputType.Touch and input == held)) then
			release()
		end
	end))
	holder.AncestryChanged:Connect(function()
		if not holder.Parent then
			-- closed (destroyed): stop listening
			release()
			for _, c in ipairs(connections) do
				c:Disconnect()
			end
		end
	end)
end

return CardVisuals