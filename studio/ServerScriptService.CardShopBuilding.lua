--[[
	CardShopBuilding (ModuleScript)
	Location: ServerScriptService > CardShopBuilding

	Builds the card shop the first time any script asks for it:
	  - brick storefront with big windows, a lit-up sign and striped awnings
	  - plank floor, painted walls with wood trim, hanging ceiling lights
	  - the checkout counter (the shop menu opens here) with a register and
	    shelves of booster boxes behind it
	  - a glass singles case showing real cards (just for looks for now)
	  - posters of the game's art, a playmat banner and a bulletin board
	  - a rug and four spots for the play tables (the tables themselves are
	    built by BattleTableServer)

	Other scripts use:
	  Building.Model           the whole shop (workspace > CardShop)
	  Building.Counter         the counter part (ShopServer puts its prompt here)
	  Building.TablePositions  where the 4 play tables go

	Move the whole shop by changing ORIGIN.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardArt = require(ReplicatedStorage:WaitForChild("CardArt"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local Playmats = require(ReplicatedStorage:WaitForChild("Playmats"))

local ORIGIN = Vector3.new(0, 0, -50) -- floor center; the door faces +Z (toward the spawn)
local HALF_W = 36  -- inside is 72 studs wide...
local HALF_D = 26  -- ...and 52 deep
local HEIGHT = 18  -- wall height
local FLOOR = 0.4  -- floor thickness (items stand on y = FLOOR)

-- Colors
local BRICK = Color3.fromRGB(128, 62, 52)
local TRIM = Color3.fromRGB(34, 28, 44)
local WALL_PAINT = Color3.fromRGB(46, 38, 82)
local WOOD_DARK = Color3.fromRGB(92, 60, 40)
local WOOD_LIGHT = Color3.fromRGB(160, 112, 72)
local FLOOR_WOOD = Color3.fromRGB(150, 106, 70)
local GOLD = Color3.fromRGB(255, 205, 90)
local NEON_PURPLE = Color3.fromRGB(170, 110, 255)
local GLASS = Color3.fromRGB(190, 225, 255)
local WARM_LIGHT = Color3.fromRGB(255, 226, 180)

local Building = {}

local model = Instance.new("Model")
model.Name = "CardShop"

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function at(x, y, z)
	return ORIGIN + Vector3.new(x, y, z)
end

-- A box from its corner ranges (relative to ORIGIN): x1..x2, y1..y2, z1..z2
local function box(name, x1, x2, y1, y2, z1, z2, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = Vector3.new(math.abs(x2 - x1), math.abs(y2 - y1), math.abs(z2 - z1))
	part.CFrame = CFrame.new(at((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2))
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Parent = parent or model
	return part
end

local function glass(part, transparency)
	part.Material = Enum.Material.Glass
	part.Transparency = transparency or 0.65
	part.CastShadow = false
	return part
end

local function light(part, brightness, range, color)
	local l = Instance.new("PointLight")
	l.Brightness = brightness
	l.Range = range
	l.Color = color or WARM_LIGHT
	l.Parent = part
	return l
end

-- A SurfaceGui on one face of a part. glow = true ignores the room's lighting.
local function surface(part, face, glow)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Surface"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.LightInfluence = glow and 0 or 1
	gui.Parent = part
	return gui
end

local function text(parent, name, value, color, position, size, font)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = position or UDim2.new()
	l.Size = size or UDim2.fromScale(1, 1)
	l.Font = font or Enum.Font.GothamBold
	l.TextScaled = true
	l.TextWrapped = true
	l.TextColor3 = color
	l.Text = value
	l.Parent = parent
	return l
end

-- Poster on a wall. face = the side facing into the room.
-- side: "Left" wall (x = -HALF_W), "Right" wall, or "Back" wall.
local function poster(name, side, center, width, height, image, caption)
	local part
	if side == "Left" then
		part = box(name, -HALF_W + 0.3, -HALF_W + 0.45, center.Y - height / 2, center.Y + height / 2,
			center.Z - width / 2, center.Z + width / 2, TRIM)
	elseif side == "Right" then
		part = box(name, HALF_W - 0.45, HALF_W - 0.3, center.Y - height / 2, center.Y + height / 2,
			center.Z - width / 2, center.Z + width / 2, TRIM)
	else
		part = box(name, center.X - width / 2, center.X + width / 2, center.Y - height / 2, center.Y + height / 2,
			-HALF_D + 0.3, -HALF_D + 0.45, TRIM)
	end
	local faces = { Left = Enum.NormalId.Right, Right = Enum.NormalId.Left, Back = Enum.NormalId.Back }
	local gui = surface(part, faces[side], false)
	local frame = Instance.new("Frame")
	frame.Name = "PosterBorder"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = GOLD
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local picture = Instance.new("ImageLabel")
	picture.Name = "Picture"
	picture.Position = UDim2.new(0, 8, 0, 8)
	picture.Size = UDim2.new(1, -16, caption and 0.84 or 1, caption and -8 or -16)
	picture.BackgroundColor3 = WALL_PAINT
	picture.BorderSizePixel = 0
	picture.Image = image or ""
	picture.ScaleType = Enum.ScaleType.Crop
	picture.Parent = frame
	if caption then
		local plate = Instance.new("Frame")
		plate.Name = "CaptionPlate"
		plate.Position = UDim2.new(0, 8, 0.84, 4)
		plate.Size = UDim2.new(1, -16, 0.16, -12)
		plate.BackgroundColor3 = TRIM
		plate.BorderSizePixel = 0
		plate.Parent = frame
		text(plate, "Caption", caption, GOLD, UDim2.fromScale(0.04, 0.1), UDim2.fromScale(0.92, 0.8))
	end
	return part
end

---------------------------------------------------------------------
-- Floor, walls, roof
---------------------------------------------------------------------
local W, D, H = HALF_W, HALF_D, HEIGHT

box("Floor", -W, W, 0, FLOOR, -D, D, FLOOR_WOOD, Enum.Material.WoodPlanks)
box("Sidewalk", -W - 6, W + 6, 0, 0.3, D + 1, D + 10, Color3.fromRGB(150, 150, 155), Enum.Material.Concrete)
box("Roof", -W - 1, W + 1, H, H + 1, -D - 1, D, Color3.fromRGB(58, 56, 64), Enum.Material.Concrete)

-- Brick outside walls (back and sides)
box("BackWall", -W - 1, W + 1, 0, H, -D - 1, -D, BRICK, Enum.Material.Brick)
box("LeftWall", -W - 1, -W, 0, H, -D, D, BRICK, Enum.Material.Brick)
box("RightWall", W, W + 1, 0, H, -D, D, BRICK, Enum.Material.Brick)

-- Painted inside, with wood paneling on the lower part and a trim rail
local inside = Instance.new("Model")
inside.Name = "InsideWalls"
inside.Parent = model
box("BackPaint", -W, W, FLOOR, H, -D, -D + 0.2, WALL_PAINT, nil, inside)
box("LeftPaint", -W, -W + 0.2, FLOOR, H, -D, D, WALL_PAINT, nil, inside)
box("RightPaint", W - 0.2, W, FLOOR, H, -D, D, WALL_PAINT, nil, inside)
box("BackPanel", -W, W, FLOOR, 4.4, -D, -D + 0.3, WOOD_DARK, Enum.Material.Wood, inside)
box("LeftPanel", -W, -W + 0.3, FLOOR, 4.4, -D, D - 1, WOOD_DARK, Enum.Material.Wood, inside)
box("RightPanel", W - 0.3, W, FLOOR, 4.4, -D, D - 1, WOOD_DARK, Enum.Material.Wood, inside)
box("BackRail", -W, W, 4.4, 4.7, -D, -D + 0.4, WOOD_LIGHT, Enum.Material.Wood, inside)
box("LeftRail", -W, -W + 0.4, 4.4, 4.7, -D, D - 1, WOOD_LIGHT, Enum.Material.Wood, inside)
box("RightRail", W - 0.4, W, 4.4, 4.7, -D, D - 1, WOOD_LIGHT, Enum.Material.Wood, inside)
box("CeilingTrim", -W, W, H - 0.6, H, -D, -D + 0.5, TRIM, nil, inside)

-- Storefront: brick around two big windows and the door
local front = Instance.new("Model")
front.Name = "Storefront"
front.Parent = model
local FZ1, FZ2 = D, D + 1
local WIN_Y1, WIN_Y2 = 3, 12
local DOOR_W, DOOR_H = 4, 11
for _, sideSign in ipairs({ -1, 1 }) do
	local function xs(a, b) -- mirrored x range
		if sideSign < 0 then
			return -b, -a
		end
		return a, b
	end
	local x1, x2 = xs(30, W + 1)
	box("Pillar", x1, x2, 0, H, FZ1, FZ2, BRICK, Enum.Material.Brick, front)
	x1, x2 = xs(DOOR_W, 8)
	box("DoorPillar", x1, x2, 0, H, FZ1, FZ2, BRICK, Enum.Material.Brick, front)
	x1, x2 = xs(8, 30)
	box("UnderWindow", x1, x2, 0, WIN_Y1, FZ1, FZ2, BRICK, Enum.Material.Brick, front)
	box("OverWindow", x1, x2, WIN_Y2, H, FZ1, FZ2, BRICK, Enum.Material.Brick, front)
	glass(box("Window", x1, x2, WIN_Y1, WIN_Y2, FZ1 + 0.4, FZ1 + 0.6, GLASS, nil, front))
	box("Sill", x1, x2, WIN_Y1 - 0.05, WIN_Y1 + 0.25, FZ1 - 0.3, FZ2 + 0.5, WOOD_LIGHT, Enum.Material.Wood, front)
	local mx1, mx2 = xs(18.8, 19.2)
	box("Mullion", mx1, mx2, WIN_Y1, WIN_Y2, FZ1 + 0.3, FZ1 + 0.7, TRIM, nil, front)
	box("WindowTop", x1, x2, WIN_Y2 - 0.1, WIN_Y2 + 0.2, FZ1 - 0.1, FZ2 + 0.2, TRIM, nil, front)
	-- Striped awning over each window
	local stripe = 0
	for sx = 8, 28, 2 do
		local ax1, ax2 = xs(sx, sx + 2)
		stripe = stripe + 1
		local color = stripe % 2 == 0 and Color3.fromRGB(245, 240, 230) or Color3.fromRGB(110, 60, 190)
		box("Awning", ax1, ax2, WIN_Y2 + 0.8, WIN_Y2 + 1.2, FZ2, FZ2 + 3.5, color, Enum.Material.Fabric, front)
	end
	local vx1, vx2 = xs(8, 30)
	box("AwningEdge", vx1, vx2, WIN_Y2 + 0.2, WIN_Y2 + 0.8, FZ2 + 3.3, FZ2 + 3.5, Color3.fromRGB(110, 60, 190),
		Enum.Material.Fabric, front)
	-- Little lamps beside the door
	local lx1, lx2 = xs(5.2, 5.8)
	light(box("DoorLamp", lx1, lx2, 8.5, 9.7, FZ2, FZ2 + 0.6, WARM_LIGHT, Enum.Material.Neon, front), 1.5, 14)
end
box("OverDoor", -DOOR_W, DOOR_W, DOOR_H, H, FZ1, FZ2, BRICK, Enum.Material.Brick, front)
box("DoorFrameLeft", -DOOR_W, -DOOR_W + 0.4, 0, DOOR_H, FZ1 - 0.2, FZ2 + 0.2, TRIM, nil, front)
box("DoorFrameRight", DOOR_W - 0.4, DOOR_W, 0, DOOR_H, FZ1 - 0.2, FZ2 + 0.2, TRIM, nil, front)
box("DoorFrameTop", -DOOR_W, DOOR_W, DOOR_H - 0.4, DOOR_H, FZ1 - 0.2, FZ2 + 0.2, TRIM, nil, front)
-- Glass doors, propped open against the inside wall
glass(box("DoorLeft", -DOOR_W - 3.9, -DOOR_W - 0.1, 0.4, DOOR_H - 0.2, FZ1 - 0.35, FZ1 - 0.15, GLASS, nil, front), 0.55)
glass(box("DoorRight", DOOR_W + 0.1, DOOR_W + 3.9, 0.4, DOOR_H - 0.2, FZ1 - 0.35, FZ1 - 0.15, GLASS, nil, front), 0.55)

-- The big sign on top of the storefront
box("Parapet", -W - 1, W + 1, H, H + 5, FZ1, FZ2, BRICK, Enum.Material.Brick, front)
local signBoard = box("ShopSignBoard", -17, 17, H + 0.5, H + 4.5, FZ2, FZ2 + 0.4, TRIM, nil, front)
local signGui = surface(signBoard, Enum.NormalId.Back, true)
text(signGui, "SignText", "CARD SHOP", GOLD, UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.62))
text(signGui, "SignSubtext", "PACKS  -  PLAYMATS  -  PLAY TABLES", Color3.fromRGB(215, 190, 255),
	UDim2.fromScale(0.1, 0.7), UDim2.fromScale(0.8, 0.24), Enum.Font.Gotham)
for _, r in ipairs({
	{ -17.3, 17.3, H + 4.5, H + 4.8 }, { -17.3, 17.3, H + 0.2, H + 0.5 },
	{ -17.3, -17, H + 0.2, H + 4.8 }, { 17, 17.3, H + 0.2, H + 4.8 },
	}) do
	box("SignNeon", r[1], r[2], r[3], r[4], FZ2, FZ2 + 0.5, NEON_PURPLE, Enum.Material.Neon, front)
end

-- "OPEN" sign in the window
local openSign = box("OpenSign", -27, -22, 8, 9.8, FZ1 - 0.2, FZ1 + 0.2, TRIM, nil, front)
text(surface(openSign, Enum.NormalId.Back, true), "OpenText", "OPEN", Color3.fromRGB(255, 80, 90))
light(openSign, 0.6, 6, Color3.fromRGB(255, 80, 90))

---------------------------------------------------------------------
-- Lights
---------------------------------------------------------------------
for _, x in ipairs({ -24, -8, 8, 24 }) do
	for _, z in ipairs({ -14, 4, 18 }) do
		box("LightRod", x - 0.1, x + 0.1, H - 2, H, z - 0.1, z + 0.1, TRIM)
		local lamp = box("CeilingLight", x - 2.5, x + 2.5, H - 2.4, H - 2, z - 0.7, z + 0.7, WARM_LIGHT, Enum.Material.Neon)
		lamp.CastShadow = false
		light(lamp, 1.1, 24)
	end
end

---------------------------------------------------------------------
-- Checkout counter (right side, near the back)
---------------------------------------------------------------------
local counter = box("Counter", 10, 29, FLOOR, FLOOR + 3.6, -16, -13, WOOD_DARK, Enum.Material.Wood)
box("CounterTop", 9.7, 29.3, FLOOR + 3.6, FLOOR + 3.9, -16.3, -12.7, WOOD_LIGHT, Enum.Material.Wood)
box("CounterGlow", 10, 29, FLOOR + 3.2, FLOOR + 3.35, -12.95, -12.85, NEON_PURPLE, Enum.Material.Neon)
local counterSign = box("CounterSign", 14, 25, FLOOR + 1, FLOOR + 2.8, -12.95, -12.85, TRIM)
text(surface(counterSign, Enum.NormalId.Back, true), "CounterText", "PACKS  -  STARTER DECKS  -  PLAYMATS", GOLD,
	UDim2.fromScale(0.03, 0.15), UDim2.fromScale(0.94, 0.7))
local T = FLOOR + 3.9 -- countertop height
box("Register", 22.5, 25, T, T + 0.9, -15.4, -13.8, TRIM)
local screen = box("RegisterScreen", 23, 24.6, T + 0.9, T + 2, -15.2, -15, Color3.fromRGB(20, 20, 30))
text(surface(screen, Enum.NormalId.Back, true), "ScreenText", "WELCOME!", Color3.fromRGB(120, 230, 255))
local rack = box("PackRack", 12.5, 15.5, T, T + 1.2, -15.2, -13.6, WOOD_LIGHT, Enum.Material.Wood)
text(surface(rack, Enum.NormalId.Back, false), "RackText", "BOOSTERS", TRIM)
for i, color in ipairs({ Color3.fromRGB(230, 120, 40), Color3.fromRGB(80, 120, 220), Color3.fromRGB(150, 80, 220),
	Color3.fromRGB(230, 120, 40), Color3.fromRGB(80, 120, 220) }) do
	local x = 12.7 + (i - 1) * 0.55
	box("RackPack", x, x + 0.45, T + 1.2, T + 2.3, -14.9, -14.8, color)
end

-- Shelves of booster boxes behind the counter
local SX1, SX2 = 10, 33
local SZ = -D + 0.2
for _, x in ipairs({ SX1, (SX1 + SX2) / 2, SX2 }) do
	box("ShelfPost", x - 0.2, x + 0.2, FLOOR, 14, SZ, SZ + 1.8, WOOD_DARK, Enum.Material.Wood)
end
local BOX_COLORS = { Color3.fromRGB(230, 120, 40), Color3.fromRGB(80, 120, 220), Color3.fromRGB(150, 80, 220) }
for level, y in ipairs({ 5, 8.3, 11.6 }) do
	box("Shelf", SX1, SX2, y - 0.3, y, SZ, SZ + 1.8, WOOD_LIGHT, Enum.Material.Wood)
	local n = 0
	for x = SX1 + 0.6, SX2 - 2, 1.9 do
		n = n + 1
		if not (x > (SX1 + SX2) / 2 - 1.2 and x < (SX1 + SX2) / 2 + 0.4) then
			local color = BOX_COLORS[(n + level) % #BOX_COLORS + 1]
			local b = box("BoosterBox", x, x + 1.6, y, y + 2.3, SZ + 0.2, SZ + 1.4, color)
			local g = surface(b, Enum.NormalId.Back, false)
			text(g, "Star", utf8.char(0x2605), GOLD, UDim2.fromScale(0.2, 0.15), UDim2.fromScale(0.6, 0.45))
			text(g, "BoxText", "BOOSTER", Color3.fromRGB(255, 255, 255), UDim2.fromScale(0.08, 0.62),
				UDim2.fromScale(0.84, 0.22))
		end
	end
end
local banner = box("BoosterBanner", SX1, SX2, 14.4, 17, SZ, SZ + 0.15, TRIM)
local bannerGui = surface(banner, Enum.NormalId.Back, true)
text(bannerGui, "BannerText", "CELESTIAL BOOSTERS  -  NOW IN STOCK", GOLD, UDim2.fromScale(0.03, 0.12),
	UDim2.fromScale(0.94, 0.76))

---------------------------------------------------------------------
-- Singles case (left side, against the back wall). Just for looks for now.
---------------------------------------------------------------------
local CX1, CX2 = -30, -8
local CZ1, CZ2 = -D + 0.3, -D + 3.6
box("CaseBase", CX1, CX2, FLOOR, FLOOR + 3, CZ1, CZ2, WOOD_DARK, Enum.Material.Wood)
box("CaseTrim", CX1 - 0.1, CX2 + 0.1, FLOOR + 3, FLOOR + 3.2, CZ1, CZ2 + 0.1, WOOD_LIGHT, Enum.Material.Wood)
local backboard = box("CaseBackboard", CX1, CX2, FLOOR + 3.2, FLOOR + 9.6, CZ1, CZ1 + 0.3, Color3.fromRGB(28, 20, 48),
	Enum.Material.Fabric)
glass(box("CaseFront", CX1, CX2, FLOOR + 3.2, FLOOR + 9.6, CZ2 - 0.15, CZ2, GLASS))
glass(box("CaseSideL", CX1, CX1 + 0.15, FLOOR + 3.2, FLOOR + 9.6, CZ1, CZ2, GLASS))
glass(box("CaseSideR", CX2 - 0.15, CX2, FLOOR + 3.2, FLOOR + 9.6, CZ1, CZ2, GLASS))
glass(box("CaseShelf", CX1, CX2, FLOOR + 6.3, FLOOR + 6.4, CZ1 + 0.3, CZ2 - 0.2, GLASS), 0.5)
local caseTop = box("CaseTop", CX1 - 0.1, CX2 + 0.1, FLOOR + 9.6, FLOOR + 9.9, CZ1, CZ2 + 0.1, WOOD_DARK, Enum.Material.Wood)
light(caseTop, 1.2, 10, Color3.fromRGB(220, 235, 255))

-- The cards on display: real cards drawn the same way as in the game
local SINGLES = {
	{ "SOL-008", "Rare" }, { "SOL-020", "Rare" }, { "SOL-010", "Rare" }, { "SOL-022", "Epic" },
	{ "SOL-011", "Epic" }, { "SOL-013", "Legendary" }, { "CEL-04", "Legendary" },
	{ "LUN-008", "Rare" }, { "LUN-020", "Rare" }, { "LUN-010", "Rare" }, { "LUN-022", "Epic" },
	{ "LUN-011", "Epic" }, { "LUN-013", "Legendary" }, { "CEL-05", "Legendary" },
}
local singlesGui = surface(backboard, Enum.NormalId.Back, false)
local PER_ROW = 7
for i, entry in ipairs(SINGLES) do
	local row = math.floor((i - 1) / PER_ROW)
	local col = (i - 1) % PER_ROW
	local holder = Instance.new("Frame")
	holder.Name = "Single_" .. entry[1]
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0.02 + col * 0.14, 0.04 + row * 0.5)
	holder.Size = UDim2.fromScale(0.12, 0.44)
	holder.Parent = singlesGui
	local cardFrame = Instance.new("Frame")
	cardFrame.Name = "Card"
	cardFrame.BackgroundTransparency = 1
	cardFrame.Size = UDim2.fromScale(1, 0.84)
	cardFrame.Parent = holder
	CardVisuals.Draw(cardFrame, entry[1], { Finish = entry[2] == "Legendary" and "3D" or "Holo" })
	local tag = text(holder, "Tag", string.upper(entry[2]), CardVisuals.RarityColors[entry[2]],
		UDim2.fromScale(0.1, 0.87), UDim2.fromScale(0.8, 0.12))
	tag.BackgroundTransparency = 0
	tag.BackgroundColor3 = TRIM
end
local singlesSign = box("SinglesSign", -24, -14, FLOOR + 10.3, FLOOR + 11.9, CZ1 + 0.3, CZ1 + 0.5, TRIM)
local singlesSignGui = surface(singlesSign, Enum.NormalId.Back, true)
text(singlesSignGui, "SinglesText", "SINGLES", GOLD, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.62))
text(singlesSignGui, "SinglesSoon", "coming soon", Color3.fromRGB(215, 190, 255), UDim2.fromScale(0.2, 0.66),
	UDim2.fromScale(0.6, 0.3), Enum.Font.Gotham)

---------------------------------------------------------------------
-- Posters, playmat banner, bulletin board
---------------------------------------------------------------------
local function artOf(cardId)
	return CardArt.ArtFor(cardId)
end
poster("Poster_Varro", "Left", Vector3.new(0, 10.5, -12), 5, 7, artOf("CMD-SOL-01"), "CAPTAIN SOL VARRO")
poster("Poster_Stallion", "Left", Vector3.new(0, 10.5, 0), 5, 7, artOf("CEL-04"), "FLARE STALLION")
poster("Poster_HeartOfSun", "Left", Vector3.new(0, 10.5, 12), 5, 7, artOf("SOL-013"), "HEART OF THE SUN")
poster("Poster_Selene", "Right", Vector3.new(0, 10.5, 0), 5, 7, artOf("CMD-LUN-01"), "TIDEKEEPER SELENE")
poster("Poster_Jellyfish", "Right", Vector3.new(0, 10.5, 12), 5, 7, artOf("CEL-05"), "MOONVEIL JELLYFISH")
poster("Poster_Leviathan", "Right", Vector3.new(0, 10.5, -8), 5, 7, artOf("LUN-013"), "MOON LEVIATHAN")

local horizon = Playmats.Get("MAT-EVENT-HORIZON")
poster("Banner_Playmats", "Back", Vector3.new(1, 12.2, 0), 13, 7.8,
	horizon and horizon.Image and ("rbxassetid://" .. horizon.Image), "NEW PLAYMATS AT THE COUNTER")

-- Bulletin board (right wall, near the front)
local board = box("BulletinBoard", W - 0.5, W - 0.3, 5.5, 10.5, 16, 24, Color3.fromRGB(170, 130, 90), Enum.Material.Wood)
local boardGui = surface(board, Enum.NormalId.Left, false)
local NOTES = {
	{ "FRIDAY NIGHT BATTLES\nBest of 3 at any table!", Color3.fromRGB(255, 245, 170), 0.04, 0.06 },
	{ "HOUSE RULES\nBe kind. Have fun.\nShuffle your deck!", Color3.fromRGB(200, 235, 255), 0.52, 0.08 },
	{ "NEW CARDS!\nBlaze Marshal\nMoonlight Oracle", Color3.fromRGB(255, 205, 225), 0.08, 0.52 },
	{ "Try Practice vs Bot\nat any open table", Color3.fromRGB(210, 255, 210), 0.54, 0.54 },
}
for i, note in ipairs(NOTES) do
	local paper = Instance.new("Frame")
	paper.Name = "Note_" .. i
	paper.Position = UDim2.fromScale(note[3], note[4])
	paper.Size = UDim2.fromScale(0.42, 0.4)
	paper.BackgroundColor3 = note[2]
	paper.BorderSizePixel = 0
	paper.Parent = boardGui
	text(paper, "NoteText", note[1], Color3.fromRGB(40, 30, 40), UDim2.fromScale(0.06, 0.08), UDim2.fromScale(0.88, 0.84),
		Enum.Font.Gotham)
end

---------------------------------------------------------------------
-- Play area: rug and decor
---------------------------------------------------------------------
box("PlayRug", -32, 32, FLOOR, FLOOR + 0.06, -8, 12, Color3.fromRGB(62, 44, 100), Enum.Material.Fabric)
box("RugBorder", -32.5, 32.5, FLOOR, FLOOR + 0.04, -8.5, 12.5, GOLD, Enum.Material.Fabric)
box("EntranceMat", -3.5, 3.5, FLOOR, FLOOR + 0.06, D - 3.5, D - 0.5, Color3.fromRGB(40, 36, 44), Enum.Material.Fabric)

local function plant(x, z)
	box("PlantPot", x - 0.8, x + 0.8, FLOOR, FLOOR + 1.6, z - 0.8, z + 0.8, Color3.fromRGB(170, 90, 60), Enum.Material.Concrete)
	local leaves = box("PlantLeaves", x - 1.3, x + 1.3, FLOOR + 1.4, FLOOR + 4, z - 1.3, z + 1.3,
		Color3.fromRGB(60, 140, 70), Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball
end
plant(-7, D - 2.5)
plant(7, D - 2.5)
plant(-W + 2.5, D - 2.5)
plant(W - 2.5, D - 2.5)

-- Where the tables go (BattleTableServer builds them): one row across the room
Building.TablePositions = {
	at(-24, FLOOR, 2),
	at(-8, FLOOR, 2),
	at(8, FLOOR, 2),
	at(24, FLOOR, 2),
}

model.Parent = workspace
Building.Model = model
Building.Counter = counter
Building.Origin = ORIGIN

return Building