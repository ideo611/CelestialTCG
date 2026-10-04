--[[
	PackVisuals (ModuleScript)
	Location: ReplicatedStorage > PackVisuals

	Draws a booster pack: foil wrapper in the faction's colors, crimped ends,
	a window showing one card's art, and the pack name. Used by the shop
	screen (pick-a-pack) and by the pack displays inside the shop building.

	PackVisuals.Draw(target, packTypeId, frontCardId, { Shine = true })
	  target       any GuiObject; the pack fills it (tall pack shape)
	  frontCardId  the card whose art is on the front (nil = no art)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CardArt = require(ReplicatedStorage:WaitForChild("CardArt"))
local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local UiAssets = require(ReplicatedStorage:WaitForChild("UiAssets"))

local PackVisuals = {}

PackVisuals.Aspect = UiAssets.Packs.All and (2 / 3) or 0.64 -- width / height of a pack

-- Wrapper colors per pack: { light, base, dark }
local WRAPPERS = {
	Solar = { Color3.fromRGB(255, 214, 120), Color3.fromRGB(226, 120, 30), Color3.fromRGB(120, 40, 10) },
	Lunar = { Color3.fromRGB(200, 225, 255), Color3.fromRGB(60, 110, 200), Color3.fromRGB(16, 30, 80) },
	Nebula = { Color3.fromRGB(255, 180, 240), Color3.fromRGB(150, 70, 190), Color3.fromRGB(50, 16, 80) },
	Void = { Color3.fromRGB(200, 180, 255), Color3.fromRGB(70, 50, 140), Color3.fromRGB(10, 6, 30) },
	Comet = { Color3.fromRGB(190, 255, 245), Color3.fromRGB(30, 160, 170), Color3.fromRGB(6, 50, 60) },
	All = { Color3.fromRGB(255, 236, 170), Color3.fromRGB(110, 70, 170), Color3.fromRGB(30, 16, 60) },
}
PackVisuals.Wrappers = WRAPPERS

local WHITE = Color3.fromRGB(255, 255, 255)

local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function text(parent, name, position, size, value, maxSize, props)
	local label = make("TextLabel", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Text = value,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		ZIndex = 4,
	}, parent)
	for key, v in pairs(props or {}) do
		label[key] = v
	end
	make("UITextSizeConstraint", { MaxTextSize = maxSize or 40, MinTextSize = 6 }, label)
	return label
end

-- Moving sheen across all drawn packs (one loop for every pack on screen)
local shines = {}
local shineStarted = false
local function startShine()
	if shineStarted then
		return
	end
	shineStarted = true
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for i = #shines, 1, -1 do
			local entry = shines[i]
			if not entry.Gradient.Parent or not entry.Gradient:IsDescendantOf(game) then
				table.remove(shines, i)
			else
				-- sweep across every 3.2 s, with a pause between sweeps
				local phase = ((t + entry.Phase) % 3.2) / 3.2
				entry.Gradient.Offset = Vector2.new(-1.2 + phase * 2.4, 0)
			end
		end
	end)
end

-- Crimped end of the wrapper: a dark strip with ridges
local function crimp(parent, name, y, colors)
	local strip = make("Frame", {
		Name = name,
		Position = UDim2.fromScale(0, y),
		Size = UDim2.fromScale(1, 0.07),
		BackgroundColor3 = colors[3],
		BorderSizePixel = 0,
		ZIndex = 3,
	}, parent)
	make("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, colors[2]),
			ColorSequenceKeypoint.new(0.5, colors[1]),
			ColorSequenceKeypoint.new(1, colors[2]),
		}),
		Rotation = 0,
	}, strip)
	for i = 0, 15 do
		make("Frame", {
			Name = "Ridge",
			Position = UDim2.fromScale(i / 16 + 0.01, 0.12),
			Size = UDim2.fromScale(0.02, 0.76),
			BackgroundColor3 = colors[3],
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, strip)
	end
	return strip
end

-- Shine sweeping over a pack (shared by both looks)
local function addSheen(pack, options, strength)
	local sheen = make("Frame", {
		Name = "Sheen",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 6,
	}, pack)
	make("UICorner", { CornerRadius = UDim.new(0.04, 0) }, sheen)
	local gradient = make("UIGradient", {
		Name = "Shine",
		Rotation = 25,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.42, 1),
			NumberSequenceKeypoint.new(0.5, strength),
			NumberSequenceKeypoint.new(0.58, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-1.2, 0),
	}, sheen)
	if options.Shine ~= false and RunService:IsClient() then
		table.insert(shines, { Gradient = gradient, Phase = (options.ShinePhase or math.random()) * 3.2 })
		startShine()
	end
end

-- A card's art inside a pack window, lined up from the top: most card art has
-- its best part at the top, so the picture starts a little below the window's
-- top edge (clear of the wrapper's rim) and any extra is cut from the bottom.
-- windowAspect = the window's width / height.
PackVisuals.ArtDrop = 0.05 -- how far down the art starts (share of the window's height)
local function placeArt(window, cardId, art, windowAspect, zIndex)
	local card = CardDatabase.GetCard(cardId)
	local tall = card and (card.Type == "Commander" or card.Type == "Celestial" or card.Rarity == "Legendary")
	local artAspect = tall and 5 / 7 or 3 / 2 -- the shapes the card art is painted in
	local drop = PackVisuals.ArtDrop
	local image = make("ImageLabel", {
		Name = "Art",
		BackgroundTransparency = 1,
		Image = art,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = zIndex,
	}, window)
	if artAspect < windowAspect then
		-- taller than the window: full width, top kept, bottom trimmed
		image.Size = UDim2.fromScale(1, windowAspect / artAspect)
		image.Position = UDim2.fromScale(0, drop)
	else
		-- wider than the window: fills the height below the drop, sides trimmed evenly
		local h = 1 - drop
		local w = h * artAspect / windowAspect
		image.Size = UDim2.fromScale(w, h)
		image.Position = UDim2.fromScale((1 - w) / 2, drop)
	end
	return image
end

-- The painted wrapper: art behind, the wrapper image (with a see-through
-- window) on top, and the pack name written on its plain band.
local function drawWrapper(target, packType, frontCardId, options, wrapperImage)
	local colors = WRAPPERS[packType.Id] or WRAPPERS.All
	local pack = make("Frame", {
		Name = "Pack",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, target)
	make("UIAspectRatioConstraint", { AspectRatio = PackVisuals.Aspect }, pack)

	-- the front card's art fills the window (a little oversized; the wrapper trims it)
	local window = make("Frame", {
		Name = "ArtWindow",
		Position = UDim2.fromScale(0.08, 0.11),
		Size = UDim2.fromScale(0.84, 0.6),
		BackgroundColor3 = colors[3],
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2,
	}, pack)
	make("UICorner", { CornerRadius = UDim.new(0.06, 0) }, window)
	local art = frontCardId and CardArt.ArtFor(frontCardId)
	if art then
		placeArt(window, frontCardId, art, 0.84 * PackVisuals.Aspect / 0.6, 2)
	else
		make("UIGradient", { Color = ColorSequence.new(colors[1], colors[3]), Rotation = 90 }, window)
	end

	make("ImageLabel", {
		Name = "Wrapper",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Image = wrapperImage,
		ScaleType = Enum.ScaleType.Stretch,
		ZIndex = 3,
	}, pack)

	local factionWord = packType.Faction and packType.Faction:upper() or "CELESTIAL"
	text(pack, "PackFaction", UDim2.fromScale(0.08, 0.735), UDim2.fromScale(0.84, 0.095), factionWord, 60,
		{ TextStrokeTransparency = 0.15, TextStrokeColor3 = colors[3] })
	text(pack, "PackWord", UDim2.fromScale(0.22, 0.83), UDim2.fromScale(0.56, 0.05), "BOOSTER", 24,
		{ Font = Enum.Font.GothamBold, TextColor3 = colors[1], TextStrokeTransparency = 0.3, TextStrokeColor3 = colors[3] })
	addSheen(pack, options, 0.7)
	return pack
end

function PackVisuals.Draw(target, packTypeId, frontCardId, options)
	options = options or {}
	local packType = EconomyConfig.GetPackType(packTypeId) or EconomyConfig.GetPackType(EconomyConfig.DefaultPackType)
	local colors = WRAPPERS[packType.Id] or WRAPPERS.All
	local wrapperImage = UiAssets.Packs[packType.Id]
	if wrapperImage then
		return drawWrapper(target, packType, frontCardId, options, wrapperImage)
	end

	local pack = make("Frame", {
		Name = "Pack",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = colors[2],
		BorderSizePixel = 0,
		ZIndex = 2,
	}, target)
	make("UIAspectRatioConstraint", { AspectRatio = PackVisuals.Aspect }, pack)
	make("UICorner", { CornerRadius = UDim.new(0.04, 0) }, pack)
	-- metallic foil: light and dark bands
	make("UIGradient", {
		Name = "Foil",
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, colors[1]),
			ColorSequenceKeypoint.new(0.3, colors[2]),
			ColorSequenceKeypoint.new(0.55, colors[3]),
			ColorSequenceKeypoint.new(0.8, colors[2]),
			ColorSequenceKeypoint.new(1, colors[1]),
		}),
		Rotation = 60,
	}, pack)
	if packType.Id == "All" then
		-- the all-faction pack carries a band of every faction's color
		local band = make("Frame", {
			Name = "FactionBand",
			Position = UDim2.fromScale(0, 0.735),
			Size = UDim2.fromScale(1, 0.025),
			BorderSizePixel = 0,
			ZIndex = 3,
		}, pack)
		local keys = {}
		for i, f in ipairs({ "Solar", "Lunar", "Nebula", "Void", "Comet" }) do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / 4, CardVisuals.FactionColors[f]))
		end
		make("UIGradient", { Color = ColorSequence.new(keys) }, band)
	end
	make("UIStroke", { Color = colors[3], Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pack)
	crimp(pack, "CrimpTop", 0, colors)
	crimp(pack, "CrimpBottom", 0.93, colors)

	-- art window
	local window = make("Frame", {
		Name = "ArtWindow",
		Position = UDim2.fromScale(0.09, 0.12),
		Size = UDim2.fromScale(0.82, 0.58),
		BackgroundColor3 = colors[3],
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
	}, pack)
	make("UICorner", { CornerRadius = UDim.new(0.05, 0) }, window)
	make("UIStroke", { Color = colors[1], Thickness = 2 }, window)
	local art = frontCardId and CardArt.ArtFor(frontCardId)
	if art then
		placeArt(window, frontCardId, art, 0.82 * PackVisuals.Aspect / 0.58, 3)
	else
		-- no art yet: a starburst in the faction colors
		make("UIGradient", {
			Color = ColorSequence.new(colors[1], colors[3]),
			Rotation = 90,
		}, window)
		text(window, "Star", UDim2.fromScale(0.2, 0.25), UDim2.fromScale(0.6, 0.5), "✦", 120,
			{ TextColor3 = colors[1], TextTransparency = 0.2, ZIndex = 3 })
	end

	-- name
	local factionWord = packType.Faction and packType.Faction:upper() or "CELESTIAL"
	text(pack, "PackFaction", UDim2.fromScale(0.06, 0.755), UDim2.fromScale(0.88, 0.1), factionWord, 60,
		{ TextStrokeTransparency = 0.4, TextStrokeColor3 = colors[3] })
	text(pack, "PackWord", UDim2.fromScale(0.2, 0.855), UDim2.fromScale(0.6, 0.055), "BOOSTER", 24,
		{ Font = Enum.Font.GothamBold, TextColor3 = colors[1] })
	local tag = make("Frame", {
		Name = "CountTag",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.95, 0.085),
		Size = UDim2.fromScale(0.26, 0.055),
		BackgroundColor3 = colors[3],
		BorderSizePixel = 0,
		ZIndex = 5,
	}, pack)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, tag)
	text(tag, "Count", UDim2.fromScale(0.08, 0.1), UDim2.fromScale(0.84, 0.8), "6 CARDS", 16,
		{ Font = Enum.Font.GothamBold, ZIndex = 5 })

	addSheen(pack, options, 0.55)
	return pack
end

return PackVisuals
