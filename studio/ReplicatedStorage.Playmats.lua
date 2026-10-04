--[[
	Playmats (ModuleScript)
	Location: ReplicatedStorage > Playmats

	The mats that sit under the battle board. The board is split down the
	middle: your mat on your half, your opponent's mat on theirs.

	To add art to a mat: upload the image, then paste its Asset ID as Image.
	Until then the mat shows its two placeholder colors as a gradient.

	How each mat is shown: the image is scaled to fill the player's half of
	the screen and the edges are trimmed (Crop), so the middle of the art is
	always what shows. Art should be 3:2 with the important parts in a wide
	band across the middle.

	Fields:
	  Id, Name, Description
	  Image        -- Asset ID number (nil until uploaded)
	  Colors       -- { top, bottom } placeholder gradient
	  Accent       -- edge color for empty lanes on this mat
	  Shade        -- optional: how much the battle board darkens this mat
	                  (0 to 1; bright art needs more so cards stand out)
	  StarterDeck  -- comes free with this starter deck (not sold)
	  PriceCoins   -- sold in the Card Shop for this many coins
	  Default      -- everyone has it
]]

local Playmats = {}

Playmats.DefaultId = "MAT-STARFIELD"

Playmats.List = {
	{
		Id = "MAT-STARFIELD",
		Name = "Starfield",
		Description = "The table's own mat. Everyone has it.",
		Image = 129849764479710, -- mat-starfield
		Colors = { Color3.fromRGB(18, 16, 40), Color3.fromRGB(8, 8, 20) },
		Accent = Color3.fromRGB(120, 110, 200),
		Default = true,
	},
	{
		Id = "MAT-SOL-STARTER",
		Name = "Solar Forge",
		Description = "Comes with the Solar starter deck.",
		Image = 120865299160887, -- mat-solar-forge
		Colors = { Color3.fromRGB(90, 34, 10), Color3.fromRGB(30, 10, 6) },
		Accent = Color3.fromRGB(255, 170, 70),
		Shade = 0.35, -- bright art
		StarterDeck = "Solar",
	},
	{
		Id = "MAT-LUN-STARTER",
		Name = "Moonlit Tide",
		Description = "Comes with the Lunar starter deck.",
		Image = 91581944098747, -- mat-moonlit-tide
		Colors = { Color3.fromRGB(20, 40, 96), Color3.fromRGB(6, 10, 32) },
		Accent = Color3.fromRGB(150, 200, 255),
		StarterDeck = "Lunar",
	},
	{
		Id = "MAT-NEBULA-DRIFT",
		Name = "Nebula Drift",
		Description = "Swirling pink and violet star clouds.",
		Image = 105486541753786, -- mat-nebula-drift
		Colors = { Color3.fromRGB(80, 26, 96), Color3.fromRGB(20, 8, 40) },
		Accent = Color3.fromRGB(230, 130, 255),
		PriceCoins = 400,
	},
	{
		Id = "MAT-COMET-TRAIL",
		Name = "Comet Trail",
		Description = "A bright comet streaking across teal skies.",
		Image = 103284377034027, -- mat-comet-trail
		Colors = { Color3.fromRGB(10, 70, 76), Color3.fromRGB(4, 20, 26) },
		Accent = Color3.fromRGB(110, 240, 220),
		PriceCoins = 400,
	},
	{
		Id = "MAT-EVENT-HORIZON",
		Name = "Event Horizon",
		Description = "The edge of a black hole, ringed with light.",
		Image = 73731490913036, -- mat-event-horizon
		Colors = { Color3.fromRGB(34, 20, 60), Color3.fromRGB(4, 2, 10) },
		Accent = Color3.fromRGB(190, 160, 255),
		PriceCoins = 400,
	},
}

local byId = {}
for i, mat in ipairs(Playmats.List) do
	mat.Order = i
	byId[mat.Id] = mat
end

function Playmats.Get(id)
	return byId[id]
end

-- The mat that comes with a starter deck (nil if none)
function Playmats.ForStarter(deckName)
	for _, mat in ipairs(Playmats.List) do
		if mat.StarterDeck == deckName then
			return mat
		end
	end
	return nil
end

-- Used for the practice bot: the starter mat of its faction
function Playmats.ForFaction(faction)
	local mat = Playmats.ForStarter(faction)
	return mat and mat.Id or Playmats.DefaultId
end

---------------------------------------------------------------------
-- Drawing (used by the battle screen and the shop)
---------------------------------------------------------------------
local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

-- Fills target with the mat. shade (0 to 1) darkens it so cards stand out.
function Playmats.Draw(target, id, shade)
	local mat = byId[id] or byId[Playmats.DefaultId]
	if shade and shade > 0 and mat.Shade then
		shade = mat.Shade
	end
	target.ClipsDescendants = true
	target.BackgroundColor3 = mat.Colors[2]
	target.BackgroundTransparency = 0
	if mat.Image then
		make("ImageLabel", {
			Name = "MatImage",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = "rbxassetid://" .. mat.Image,
			ScaleType = Enum.ScaleType.Crop,
		}, target)
	else
		local fill = make("Frame", {
			Name = "MatImage",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
		}, target)
		make("UIGradient", {
			Name = "MatGradient",
			Color = ColorSequence.new(mat.Colors[1], mat.Colors[2]),
			Rotation = 90,
		}, fill)
	end
	if shade and shade > 0 then
		make("Frame", {
			Name = "MatShade",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 1 - shade,
			BorderSizePixel = 0,
		}, target)
	end
	return mat
end

return Playmats