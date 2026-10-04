--[[
	UiAssets (ModuleScript)
	Every interface image that isn't card art: card back, pack wrappers,
	currency icons, faction emblems, rarity gems, keyword icons, window
	frame, loading screen, banners and shop decor.

	To swap an image: upload the new one and paste its Asset ID here.
	Set an entry to 0 to fall back to the old drawn look.
]]

local UiAssets = {}

local function id(n)
	if not n or n == 0 then
		return nil
	end
	return "rbxassetid://" .. n
end
UiAssets.Id = id

UiAssets.Logo = id(77126253690698)
UiAssets.Loading = id(90104731234541)
UiAssets.CardBack = id(120192547283511)
UiAssets.PanelFrame = id(86255685203929)
-- the frame image's border thickness, in pixels of the 1024px image
UiAssets.PanelSlice = Rect.new(96, 96, 928, 928)
UiAssets.BinderCover = id(134618557712131)
UiAssets.Victory = id(101327852010684)
UiAssets.Defeat = id(107880539606279)

UiAssets.Currency = {
	Coins = id(78918894803602),
	StarShards = id(80334868228204),
	StarTokens = id(111237890942207),
}

UiAssets.Packs = {
	All = id(97689972403742),
	Solar = id(117479486607944),
	Lunar = id(75657993481245),
	Nebula = id(132011601559799),
	Void = id(99226064354765),
	Comet = id(131296429959260),
}

UiAssets.Emblems = {
	Solar = id(90185717980543),
	Lunar = id(134898050639408),
	Nebula = id(85314487283007),
	Void = id(84947694729168),
	Comet = id(97099426647285),
	Neutral = id(135808612815750),
}

UiAssets.Rarity = {
	Common = id(124813153072511),
	Rare = id(76714474882613),
	Epic = id(87438311607325),
	Legendary = id(139822730430153),
	Mythic = id(79668337410840),
}

UiAssets.Keywords = {
	Shield = id(88035124971349),
	Ignite = id(84473935687727),
	Rush = id(84132011481958),
	Grow = id(86192853327952),
	Decay = id(88463895040415),
	Streak = id(95834750949000),
	Regen = id(107122245495393),
	Intercept = id(139576367955979),
}

-- Holo foil textures (seamless, transparent). 0 = not uploaded yet: the card
-- finishes then use their drawn gradient foil instead.
UiAssets.Holo = {
	Sheen = id(113539671982670),     -- holo-sheen: rainbow foil grain sliding across every foil card's art
	Glare = id(119123662687174),     -- holo-glare: the bright streak of light that sweeps across foil cards
	Etched = id(139189069672778),    -- holo-etched: engraved wave lines over the whole card (Textured)
	Starfield = id(96080316925938), -- holo-starfield: tiny sparkles drifting over the art (3D)
	Galaxy = id(114233551957218),    -- holo-galaxy: swirling cosmic foil over the whole card (Mythic)
	Sparkle = id(134300135406896),   -- holo-sparkle: 4 x 4 sheet of a twinkling glint (Legendary cards, Mythic finish)
	-- each faction's foil pattern over the art of its Holo, Textured and 3D cards
	Faction = {
		Solar = id(95342818773474),  -- holo-solar
		Lunar = id(93768905590510),  -- holo-lunar
		Nebula = id(83578980286649), -- holo-nebula
		Void = id(114284764527776),   -- holo-void
		Comet = id(104361294512515),  -- holo-comet
	},
}

UiAssets.Decor = {
	Mural = id(139694764273713),
	PosterBattles = id(112071268902312),
	PosterFactions = id(89559673383759),
	PosterComet = id(115053144156106),
}

-- Effect sprite sheets: a 4 x 4 grid of animation frames in one image,
-- read left to right, top to bottom. Played by UiAssets.PlayFlipbook.
UiAssets.Vfx = {
	ImpactBurst = id(123946111795519),  -- vfx-impact-burst: hits on units and Commanders
	ShieldUp = id(75984910383933),      -- vfx-shield-up
	ShieldBreak = id(85035840917899),   -- vfx-shield-break
	Heal = id(109523079176511),         -- vfx-heal
	Ignite = id(81917766290905),        -- vfx-ignite
	PowerUp = id(93750372349253),       -- vfx-power-up
	Weaken = id(115298691146477),       -- vfx-weaken
	Grow = id(115220702111342),         -- vfx-grow
	Decay = id(119050122259007),        -- vfx-decay
	Streak = id(74274760479459),        -- vfx-streak
	Destroyed = id(116559877319229),    -- vfx-destroyed
	SpellCast = id(114408763896118),    -- vfx-spell-cast
	SummonPillar = id(80050279943489),  -- vfx-summon-pillar
	Storm = id(92690111977384),         -- vfx-storm
	LegendaryPull = id(137582311055047), -- vfx-legendary-pull
	MythicPull = id(123244432953386),   -- vfx-mythic-pull
	CardReveal = id(136369018275222),   -- vfx-card-reveal

	-- New effect pack (0 = not uploaded yet: the older effect plays instead)
	HitFlash = id(0),        -- VFX_HitFlash: small hits (1-2 damage)
	DamageBurst = id(0),     -- VFX_DamageBurst: big hits (3+ damage)
	CommanderHit = id(0),    -- VFX_CommanderHit: damage to a Commander
	CardLanding = id(0),     -- VFX_CardLanding: a unit landing in its lane
	DestroyBurst = id(0),    -- VFX_DestroyBurst: a unit destroyed
	HealPulse = id(0),       -- VFX_HealPulse: heals
	Fireball = id(0),        -- vfx-solar-fireball: Ignite projectile head (loop)
	FireTrail = id(0),       -- vfx-solar-trail: Ignite projectile trail (single image, not a sheet)
	IgniteImpact = id(0),    -- VFX_Solar_IgniteImpact: where the fireball lands
	SolarImpact = id(0),     -- vfx-solar-impact: hits from Solar units
	LunarImpact = id(0),
	NebulaImpact = id(0),
	VoidImpact = id(0),
	CometImpact = id(0),
}

-- If an effect isn't uploaded, play this one instead
local VFX_FALLBACK = {
	HitFlash = "ImpactBurst",
	DamageBurst = "ImpactBurst",
	CommanderHit = "ImpactBurst",
	DestroyBurst = "Destroyed",
	HealPulse = "Heal",
	IgniteImpact = "Ignite",
}

-- The image for an effect (following the fallbacks), or nil
function UiAssets.VfxImage(key)
	local seen = 0
	while key and seen < 4 do
		if UiAssets.Vfx[key] then
			return UiAssets.Vfx[key]
		end
		key = VFX_FALLBACK[key]
		seen = seen + 1
	end
	return nil
end

-- Each faction's hit effect (used when a unit of that faction lands a blow)
UiAssets.FactionImpact = {
	Solar = "SolarImpact",
	Lunar = "LunarImpact",
	Nebula = "NebulaImpact",
	Void = "VoidImpact",
	Comet = "CometImpact",
}

-- Projectiles: a looping head sheet, a trail image stretched behind it, the
-- impact sheet where it lands, and the flight time in seconds
UiAssets.Projectiles = {
	Fireball = { Head = "Fireball", Trail = "FireTrail", Impact = "IgniteImpact", Flight = 0.32 },
}

--[[ Plays a sprite sheet once on screen, then removes it.
	parent   the GUI to draw in
	image    a UiAssets.Vfx entry
	options  Position (UDim2, the effect's center), Size (UDim2; kept square),
	         Duration (seconds, default 0.55), Grid (default 4), Frames (default 16),
	         ZIndex, Color (tint)
	(No rotation: Roblox can't clip a rotated frame, so the next frame would show.)
	Each frame is shown through a window the size of one grid cell, so it
	works whatever resolution Roblox stored the image at. ]]
function UiAssets.PlayFlipbook(parent, image, options)
	if not image or not parent then
		return nil
	end
	options = options or {}
	local grid = options.Grid or 4
	local frames = options.Frames or grid * grid
	local duration = options.Duration or 0.55
	local window = Instance.new("Frame")
	window.Name = "Vfx"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = options.Position or UDim2.fromScale(0.5, 0.5)
	window.Size = options.Size or UDim2.fromScale(0.2, 0.2)
	window.BackgroundTransparency = 1
	window.ClipsDescendants = true
	window.ZIndex = options.ZIndex or 20
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = window
	local sheet = Instance.new("ImageLabel")
	sheet.Name = "Sheet"
	sheet.BackgroundTransparency = 1
	sheet.Image = image
	sheet.ImageColor3 = options.Color or Color3.new(1, 1, 1)
	sheet.ScaleType = Enum.ScaleType.Stretch
	sheet.Size = UDim2.fromScale(grid, grid)
	sheet.ZIndex = window.ZIndex
	sheet.Parent = window
	window.Parent = parent
	task.spawn(function()
		local start = os.clock()
		while window.Parent do
			local frame = math.floor((os.clock() - start) / duration * frames)
			if frame >= frames then
				break
			end
			local col, row = frame % grid, math.floor(frame / grid)
			sheet.Position = UDim2.fromScale(-col, -row)
			task.wait()
		end
		window:Destroy()
	end)
	return window
end

-- Lay the window-frame image over a menu panel (9-slice, so the corners
-- stay sharp at any size). Returns the image, or nil if there's no frame.
function UiAssets.FramePanel(panel, thickness)
	if not UiAssets.PanelFrame then
		return nil
	end
	local stroke = panel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 1
	end
	local t = thickness or 18
	local frame = Instance.new("ImageLabel")
	frame.Name = "PanelFrame"
	frame.BackgroundTransparency = 1
	frame.Image = UiAssets.PanelFrame
	frame.ScaleType = Enum.ScaleType.Slice
	frame.SliceCenter = UiAssets.PanelSlice
	frame.SliceScale = t / 96
	frame.Position = UDim2.fromOffset(-t * 0.45, -t * 0.45)
	frame.Size = UDim2.new(1, t * 0.9, 1, t * 0.9)
	frame.ZIndex = (panel.ZIndex or 1) + 40
	frame.Active = false
	frame.Parent = panel
	return frame
end

-- A small square icon image (emblem, gem, coin...). Returns nil if no image.
function UiAssets.Icon(image, size, position, parent, zIndex)
	if not image then
		return nil
	end
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = image
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Size = size
	icon.Position = position or UDim2.new()
	icon.ZIndex = zIndex or 1
	icon.Parent = parent
	return icon
end

return UiAssets
