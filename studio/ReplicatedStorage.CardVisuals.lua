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
	if keywords.Ignite then
		table.insert(parts, "Ignite " .. keywords.Ignite)
	end
	if keywords.Regen then
		table.insert(parts, "Regen " .. keywords.Regen)
	end
	local result = table.concat(parts, ", ")
	if card.AbilityText ~= "" then
		result = (result ~= "" and (result .. ". ") or "") .. card.AbilityText
	end
	if card.Type == "Commander" and card.CommanderAbility then
		result = ("Ability (%d): %s"):format(card.CommanderAbility.EnergyCost, card.CommanderAbility.Text)
	end
	if card.Type == "Celestial" and card.PairsWith then
		result = result .. (result ~= "" and "\n" or "") .. "Pairs with " .. table.concat(card.PairsWith, " + ")
	end
	return result
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
	if card.Type == "Unit" or card.Type == "Spell" then
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

	if unit and unit.CanAttack == false then
		text(target, "Sleeping", UDim2.fromScale(0.72, 0.8), UDim2.fromScale(0.25, 0.14), "zzz", 18, {
			Font = Enum.Font.Gotham,
		})
	end
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
}

local PLATE_TEXT = Color3.fromRGB(38, 26, 30) -- dark text on the light plates
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
	-- Holo: a classic holo art box (rainbow foil sliding across the art, plus a glare)
	Holo = { ArtFoil = 0.5, Glare = 0.2 },
	-- Textured: embossed swirls etched across the card, catching the rainbow,
	-- and a rainbow shimmer running around the frame
	Textured = { ArtFoil = 0.68, CardFoil = 0.82, Glare = 0.25, Pattern = "Etched", PatternStrength = 0.62,
		PatternTile = 0.5, FrameShine = "Rainbow" },
	-- 3D: lifted off the table (shadow, gentle bob), deep parallax, gold shimmer on the frame
	["3D"] = { ArtFoil = 0.6, Glare = 0.25, Float = true, Lift = true, FrameShine = "Gold" },
	-- Mythic: secret-rare prismatic lines over the card, colors cycling,
	-- a rainbow aura and sparkles rising off it
	Mythic = { ArtFoil = 0.68, CardFoil = 0.74, Glare = 0.2, Pattern = "Secret", PatternStrength = 0.1,
		PatternTile = 0.3, FrameShine = "Rainbow", CycleColors = true, Aura = true, Particles = 7 },
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

-- Everything that moves is updated by one loop (players' screens only)
local animated = setmetatable({}, { __mode = "k" }) -- [object] = { Kind, Phase, ... }
local loopRunning = false
local GLARE_CYCLE, GLARE_SWEEP = 3.2, 1.0 -- seconds per glare, seconds it takes to cross

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
	for object, info in pairs(animated) do
		if object.Parent == nil then
			animated[object] = nil
		elseif info.Kind == "Glare" then
			object.Offset = glareOffset(t, info.Phase)
		elseif info.Kind == "Foil" then
			-- slides exactly one repeat, then wraps to an identical picture
			local shift = ((t * info.Speed + info.Phase) % FOIL_PERIOD) - FOIL_PERIOD / 2
			object.Offset = Vector2.new(shift, 0)
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
	local info = { Kind = kind, Phase = phase }
	for k, v in pairs(extra or {}) do
		info[k] = v
	end
	animated[object] = info
	if not loopRunning and RunService:IsClient() then
		loopRunning = true
		RunService.RenderStepped:Connect(step)
	end
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

--[[ Adds the finish's effects to a drawn card face.
	artHolder  what holds the art (the foil over the art goes in here)
	frameImage the card's frame image (a tinted copy makes the frame shine)
	inner      the area whole-card foil stays inside { x, y, w, h }
	corner     round that area's corners by this much (full-art frames) ]]
local function addFinish(face, artHolder, finish, frameImage, inner, corner)
	local fx = FINISH_FX[finish]
	if not fx then
		return
	end
	local phase = math.random() * GLARE_CYCLE
	local moving = RunService:IsClient()
	inner = inner or CardVisuals.InnerRect

	-- Rainbow foil over the art, and a bright glare sweeping across it
	artHolder.ClipsDescendants = true
	local _, artFoil = gradientLayer(artHolder, "HoloFoil", 1, FOIL, foilTransparency(fx.ArtFoil), 0, true)
	local _, glare = gradientLayer(artHolder, "HoloBand", 1, ColorSequence.new(Color3.fromRGB(255, 255, 255)),
		bandTransparency(fx.Glare), 25)
	glare.Offset = Vector2.new(1.6, 0)
	if moving then
		animate(artFoil, "Foil", phase, { Speed = 0.05 })
		animate(glare, "Glare", phase)
	end

	-- Foil over the inside of the card (art, bars, text box), under the text
	if fx.CardFoil then
		-- under the frame, so the frame trims it along its exact shape
		local area = clipArea(face, "CardFoilArea", inner, 4, corner)
		local _, cardFoil = gradientLayer(area, "CardShine", 4, FOIL, foilTransparency(fx.CardFoil), 0, true)
		local _, cardGlare = gradientLayer(area, "CardGlare", 4, ColorSequence.new(Color3.fromRGB(255, 255, 255)),
			bandTransparency(math.min(fx.Glare + 0.15, 1)), 25)
		cardGlare.Offset = Vector2.new(1.6, 0)
		if moving then
			animate(cardFoil, "Foil", phase + 0.05, { Speed = fx.CycleColors and 0.14 or 0.04 })
			animate(cardGlare, "Glare", phase + 0.1)
		end
	end

	-- The pattern in the foil: etched swirls (Textured) or prismatic lines
	-- (Mythic), tinted by the sliding rainbow
	local patternId = fx.Pattern == "Etched" and CardVisuals.EtchedTextureId
		or fx.Pattern == "Secret" and CardVisuals.SecretTextureId or 0
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
		if RunService:IsClient() then
			animate(art, "Float", math.random() * 6)
		end
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

	-- 4. Text on top
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
		TextColor3 = PLATE_TEXT,
	})
	local typeLine = card.Type
	if card.Type == "Unit" or card.Type == "Spell" then
		typeLine = card.Faction .. " " .. card.Type
	end
	faceText("TypeLine", "Type", typeLine, 20, { TextColor3 = PLATE_TEXT })
	faceText("CardText", "TextInner", CardVisuals.KeywordText(card, unit), 24, { Font = Enum.Font.Gotham })

	if card.Power then
		local power = unit and unit.Power or card.Power
		local hp = unit and unit.HP or card.HP
		local hurt = unit and unit.HP < unit.MaxHP
		faceText("Stats", "Stats", ("%d / %d"):format(power, hp), 30, {
			TextColor3 = hurt and Color3.fromRGB(190, 30, 30) or PLATE_TEXT,
		})
	elseif card.Type == "Commander" then
		faceText("Stats", "Stats", options.StatsText or (card.HP .. " HP"), 30, {
			TextColor3 = options.StatsHurt and Color3.fromRGB(190, 30, 30) or PLATE_TEXT,
		})
	end
	if card.StarCost and card.Type ~= "Commander" then
		faceText("Stars", "Stars", string.rep(STAR, card.StarCost), 22, {
			TextColor3 = Color3.fromRGB(215, 150, 20),
		})
	end
	if unit and unit.CanAttack == false then
		faceText("Sleeping", "Sleep", "zzz", 22, { Font = Enum.Font.Gotham })
	end

	addFinish(face, artHolder, options.Finish, frameImage)
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
	if unit and unit.CanAttack == false then
		local zzz = text(face, "Sleeping", UDim2.fromScale(0.64, 0.7), UDim2.fromScale(0.2, 0.06), "zzz", 22,
			{ Font = Enum.Font.Gotham })
		zzz.ZIndex = 7
	end

	-- the foil covers the art area, under the frame (the frame trims its edges)
	addFinish(face, window, "Mythic", frameImage, FULL.Art, FULL.Corner)
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

return CardVisuals