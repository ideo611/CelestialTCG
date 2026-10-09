--[[
	CardShopBuilding (ModuleScript)
	Location: ServerScriptService > CardShopBuilding

	Builds the card shop the first time any script asks for it:
	  - brick storefront with big windows, a lit-up sign and striped awnings
	  - plank floor, painted walls with wood trim, hanging ceiling lights
	  - the checkout counter (the shop menu opens here) with a register and
	    shelves of booster boxes behind it
	  - a glass singles case showing today's singles for sale
	  - the starter deck table (browse every faction's starter deck)
	  - booster displays with real pack art, a pack rack on the counter
	  - accessories wall, bulk bins, a drinks cooler, playmat rack, gacha
	    machine, staff door, clock, and Nova the shop cat on the counter
	  - posters of the game's art, a playmat banner and a bulletin board
	  - a rug and four spots for the play tables (the tables themselves are
	    built by BattleTableServer)

	Other scripts use:
	  Building.Model           the whole shop (workspace > CardShop)
	  Building.Counter         the counter part (ShopServer puts its prompt here)
	  Building.TablePositions  where the 4 play tables go
	  Building.SinglesCase     the singles case (ShopServer's "Browse singles" prompt)
	  Building.ShowSingles(stock)  puts today's singles in the case
	  Building.StarterTable    the starter deck table (its prompt)
	  Building.Cat             Nova the shop cat (her "Pet" prompt)

	Move the whole shop by changing ORIGIN.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local Packs = require(ReplicatedStorage:WaitForChild("Packs"))
local PackVisuals = require(ReplicatedStorage:WaitForChild("PackVisuals"))
local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local CardArt = require(ReplicatedStorage:WaitForChild("CardArt"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local Playmats = require(ReplicatedStorage:WaitForChild("Playmats"))
local UiAssets = require(ReplicatedStorage:WaitForChild("UiAssets"))

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
if UiAssets.Logo then
	-- the game's logo on the left, the shop words on the right
	local logo = Instance.new("ImageLabel")
	logo.Name = "SignLogo"
	logo.Position = UDim2.fromScale(0.02, 0.04)
	logo.Size = UDim2.fromScale(0.3, 0.92)
	logo.BackgroundTransparency = 1
	logo.Image = UiAssets.Logo
	logo.ScaleType = Enum.ScaleType.Fit
	logo.Parent = signGui
	text(signGui, "SignText", "CARD SHOP", GOLD, UDim2.fromScale(0.34, 0.08), UDim2.fromScale(0.62, 0.62))
	text(signGui, "SignSubtext", "PACKS  -  PLAYMATS  -  PLAY TABLES", Color3.fromRGB(215, 190, 255),
		UDim2.fromScale(0.36, 0.7), UDim2.fromScale(0.58, 0.24), Enum.Font.Gotham)
else
	text(signGui, "SignText", "CARD SHOP", GOLD, UDim2.fromScale(0.05, 0.08), UDim2.fromScale(0.9, 0.62))
	text(signGui, "SignSubtext", "PACKS  -  PLAYMATS  -  PLAY TABLES", Color3.fromRGB(215, 190, 255),
		UDim2.fromScale(0.1, 0.7), UDim2.fromScale(0.8, 0.24), Enum.Font.Gotham)
end
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
-- Real packs standing in the rack, one of each booster (with card art on the front)
local function packOnPart(part, face, packTypeId, frontIndex)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PackFace"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 90
	gui.LightInfluence = 0.4
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = part
	local fronts = Packs.FrontCards(packTypeId)
	PackVisuals.Draw(gui, packTypeId, fronts[(frontIndex - 1) % #fronts + 1], { Shine = false })
	return gui
end
for i = 1, 3 do
	local packType = EconomyConfig.PackTypes[(i - 1) % #EconomyConfig.PackTypes + 1]
	local x = 12.6 + (i - 1) * 0.98
	local p = box("RackPack", x, x + 0.88, T + 1.2, T + 2.58, -14.9, -14.8, Color3.fromRGB(30, 26, 40))
	packOnPart(p, Enum.NormalId.Back, packType.Id, i)
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
-- Singles case (left side, against the back wall)
---------------------------------------------------------------------
local CX1, CX2 = -30, -8
local CZ1, CZ2 = -D + 0.3, -D + 3.6
box("CaseBase", CX1, CX2, FLOOR, FLOOR + 3, CZ1, CZ2, WOOD_DARK, Enum.Material.Wood)
box("CaseTrim", CX1 - 0.1, CX2 + 0.1, FLOOR + 3, FLOOR + 3.2, CZ1, CZ2 + 0.1, WOOD_LIGHT, Enum.Material.Wood)
local backboard = box("CaseBackboard", CX1, CX2, FLOOR + 3.2, FLOOR + 9.6, CZ1, CZ1 + 0.3, Color3.fromRGB(28, 20, 48),
	Enum.Material.Fabric)
local caseFront = glass(box("CaseFront", CX1, CX2, FLOOR + 3.2, FLOOR + 9.6, CZ2 - 0.15, CZ2, GLASS))
glass(box("CaseSideL", CX1, CX1 + 0.15, FLOOR + 3.2, FLOOR + 9.6, CZ1, CZ2, GLASS))
glass(box("CaseSideR", CX2 - 0.15, CX2, FLOOR + 3.2, FLOOR + 9.6, CZ1, CZ2, GLASS))
glass(box("CaseShelf", CX1, CX2, FLOOR + 6.3, FLOOR + 6.4, CZ1 + 0.3, CZ2 - 0.2, GLASS), 0.5)
local caseTop = box("CaseTop", CX1 - 0.1, CX2 + 0.1, FLOOR + 9.6, FLOOR + 9.9, CZ1, CZ2 + 0.1, WOOD_DARK, Enum.Material.Wood)
light(caseTop, 1.2, 10, Color3.fromRGB(220, 235, 255))

-- The cards on display: today's singles (ShopServer calls Building.ShowSingles
-- every day with the new stock). Real cards drawn the same way as in the game.
local singlesGui = surface(backboard, Enum.NormalId.Back, false)
local PER_ROW = 6

function Building.ShowSingles(stock)
	singlesGui:ClearAllChildren()
	for i, entry in ipairs(stock) do
		if i > PER_ROW * 2 then
			break
		end
		local row = math.floor((i - 1) / PER_ROW)
		local col = (i - 1) % PER_ROW
		local holder = Instance.new("Frame")
		holder.Name = "Single_" .. entry.CardId
		holder.BackgroundTransparency = 1
		holder.Position = UDim2.fromScale(0.015 + col * (0.97 / PER_ROW), 0.03 + row * 0.5)
		holder.Size = UDim2.fromScale(0.97 / PER_ROW - 0.01, 0.44)
		holder.Parent = singlesGui
		local cardFrame = Instance.new("Frame")
		cardFrame.Name = "Card"
		cardFrame.BackgroundTransparency = 1
		cardFrame.AnchorPoint = Vector2.new(0.5, 0)
		cardFrame.Position = UDim2.fromScale(0.5, 0)
		cardFrame.Size = UDim2.fromScale(1, 0.8)
		cardFrame.Parent = holder
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1060 / 1484
		aspect.Parent = cardFrame
		CardVisuals.Draw(cardFrame, entry.CardId, { Finish = entry.Finish })
		local tag = text(holder, "PriceTag", ("%d coins"):format(entry.Price or 0), GOLD,
			UDim2.fromScale(0.1, 0.83), UDim2.fromScale(0.8, 0.15))
		tag.BackgroundTransparency = 0
		tag.BackgroundColor3 = TRIM
	end
end

local singlesSign = box("SinglesSign", -24, -14, FLOOR + 10.3, FLOOR + 11.9, CZ1 + 0.3, CZ1 + 0.5, TRIM)
local singlesSignGui = surface(singlesSign, Enum.NormalId.Back, true)
text(singlesSignGui, "SinglesText", "SINGLES", GOLD, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.62))
text(singlesSignGui, "SinglesSubtext", "new cards every day", Color3.fromRGB(215, 190, 255), UDim2.fromScale(0.15, 0.66),
	UDim2.fromScale(0.7, 0.3), Enum.Font.Gotham)
-- the case itself (ShopServer puts its "Browse singles" prompt here)
Building.SinglesCase = caseFront

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

-- Painted posters and the mural (UiAssets.Decor)
local DECOR = UiAssets.Decor
if DECOR.Mural then
	-- a wide band of the mural above the singles case
	poster("Mural", "Back", Vector3.new(-19, 14.95, 0), 21, 4.5, DECOR.Mural)
end
if DECOR.PosterFactions then
	poster("Poster_Factions", "Right", Vector3.new(0, 10.5, -17.25), 10.5, 7, DECOR.PosterFactions)
end
if DECOR.PosterBattles then
	poster("Poster_Battles", "Left", Vector3.new(0, 10.75, 18), 5, 7.5, DECOR.PosterBattles)
end
if DECOR.PosterComet then
	poster("Poster_Comet", "Left", Vector3.new(0, 10.6, 23.05), 4.5, 6.75, DECOR.PosterComet)
end

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

---------------------------------------------------------------------
-- Booster display stand (left of the counter): every booster on sale
---------------------------------------------------------------------
do
	box("DisplayBase", 2.6, 8.4, FLOOR, FLOOR + 1, -15.6, -13.6, TRIM)
	local board = box("BoosterDisplay", 2.8, 8.2, FLOOR + 1, FLOOR + 7.4, -15, -14.8, Color3.fromRGB(26, 20, 44))
	local gui = surface(board, Enum.NormalId.Back, true)
	gui.PixelsPerStud = 60
	text(gui, "DisplayTitle", "BOOSTERS", GOLD, UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.1))
	text(gui, "DisplayHint", "pick your pack at the counter", Color3.fromRGB(215, 190, 255),
		UDim2.fromScale(0.1, 0.115), UDim2.fromScale(0.8, 0.05), Enum.Font.Gotham)
	local types = EconomyConfig.PackTypes
	local perRow = math.min(3, #types)
	local rows = math.ceil(#types / perRow)
	for i, packType in ipairs(types) do
		local row = math.floor((i - 1) / perRow)
		local col = (i - 1) % perRow
		local slot = Instance.new("Frame")
		slot.Name = "Display_" .. packType.Id
		slot.BackgroundTransparency = 1
		slot.Position = UDim2.fromScale(0.03 + col * (0.94 / perRow), 0.19 + row * (0.8 / rows))
		slot.Size = UDim2.fromScale(0.94 / perRow - 0.02, 0.8 / rows - 0.02)
		slot.Parent = gui
		local fronts = Packs.FrontCards(packType.Id)
		PackVisuals.Draw(slot, packType.Id, fronts[i % #fronts + 1], { Shine = false })
	end
	light(board, 0.8, 9, Color3.fromRGB(230, 210, 255))
end

---------------------------------------------------------------------
-- Starter deck table (front left): browse every faction's starter deck
---------------------------------------------------------------------
local FACTION_ORDER = { "Solar", "Lunar", "Nebula", "Void", "Comet" }
local STX1, STX2, STZ1, STZ2 = -27, -13, 15, 19.5
local starterTable = box("StarterTable", STX1, STX2, FLOOR + 2.7, FLOOR + 3.1, STZ1, STZ2, WOOD_LIGHT, Enum.Material.Wood)
box("StarterTableCloth", STX1 - 0.05, STX2 + 0.05, FLOOR + 1.7, FLOOR + 3.12, STZ2 - 0.05, STZ2 + 0.05,
	Color3.fromRGB(110, 60, 190), Enum.Material.Fabric)
for _, x in ipairs({ STX1 + 0.4, STX2 - 0.4 }) do
	for _, z in ipairs({ STZ1 + 0.4, STZ2 - 0.4 }) do
		box("StarterTableLeg", x - 0.2, x + 0.2, FLOOR, FLOOR + 2.7, z - 0.2, z + 0.2, WOOD_DARK, Enum.Material.Wood)
	end
end
local TT = FLOOR + 3.1
for i, faction in ipairs(FACTION_ORDER) do
	local starter = CardDatabase.StarterDecks[faction]
	local x = STX1 + 1.4 + (i - 1) * 2.8
	-- the deck box, standing up, front toward the door
	local deckBox = box("StarterBox_" .. faction, x, x + 1.8, TT, TT + 2.5, STZ1 + 2.2, STZ1 + 3.1,
		CardVisuals.FactionColors[faction] or TRIM)
	local gui = surface(deckBox, Enum.NormalId.Back, true)
	gui.PixelsPerStud = 80
	local bg = Instance.new("Frame")
	bg.Name = "BoxFront"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = (CardVisuals.FactionColors[faction] or TRIM):Lerp(Color3.new(0, 0, 0), 0.35)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local art = starter and CardArt.ArtFor(starter.Commander)
	local picture = Instance.new("ImageLabel")
	picture.Name = "BoxArt"
	picture.Position = UDim2.fromScale(0.08, 0.06)
	picture.Size = UDim2.fromScale(0.84, 0.6)
	picture.BackgroundColor3 = CardVisuals.FactionColors[faction] or TRIM
	picture.BorderSizePixel = 0
	picture.Image = art or ""
	picture.ScaleType = Enum.ScaleType.Crop
	picture.Parent = bg
	if UiAssets.Emblems[faction] then
		local emblem = Instance.new("ImageLabel")
		emblem.Name = "BoxEmblem"
		emblem.AnchorPoint = Vector2.new(0.5, 0.5)
		emblem.Position = UDim2.fromScale(0.82, 0.62)
		emblem.Size = UDim2.fromScale(0.34, 0.24)
		emblem.BackgroundTransparency = 1
		emblem.Image = UiAssets.Emblems[faction]
		emblem.ScaleType = Enum.ScaleType.Fit
		emblem.ZIndex = 2
		emblem.Parent = bg
	end
	text(bg, "BoxFaction", string.upper(faction), GOLD, UDim2.fromScale(0.05, 0.69), UDim2.fromScale(0.9, 0.14))
	text(bg, "BoxWord", starter and "STARTER DECK" or "COMING SOON", Color3.fromRGB(255, 255, 255),
		UDim2.fromScale(0.08, 0.84), UDim2.fromScale(0.84, 0.1), Enum.Font.Gotham)
	-- a sample card lying in front of each box
	local sample = box("SampleCard", x + 0.3, x + 1.5, TT, TT + 0.04, STZ1 + 3.4, STZ1 + 4.6, Color3.fromRGB(235, 230, 220))
	if UiAssets.CardBack then
		local back = Instance.new("Decal")
		back.Name = "CardBack"
		back.Face = Enum.NormalId.Top
		back.Texture = UiAssets.CardBack
		back.Parent = sample
	end
end
local starterSign = box("StarterSign", STX1 + 1, STX2 - 1, FLOOR + 5, FLOOR + 7, STZ1 + 0.7, STZ1 + 0.9, TRIM)
for _, x in ipairs({ STX1 + 1.3, STX2 - 1.3 }) do
	box("StarterSignPost", x - 0.1, x + 0.1, TT, FLOOR + 5, STZ1 + 0.7, STZ1 + 0.9, TRIM)
end
local starterSignGui = surface(starterSign, Enum.NormalId.Back, true)
text(starterSignGui, "StarterTitle", "STARTER DECKS", GOLD, UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.55))
text(starterSignGui, "StarterHint", "Meet the factions. Your first deck is free!", Color3.fromRGB(215, 190, 255),
	UDim2.fromScale(0.05, 0.62), UDim2.fromScale(0.9, 0.3), Enum.Font.Gotham)
light(starterSign, 0.9, 12, WARM_LIGHT)
Building.StarterTable = starterTable

---------------------------------------------------------------------
-- Accessories wall (left wall, near the back): sleeves, deck boxes, binders
---------------------------------------------------------------------
do
	local AZ1, AZ2 = -21.5, -15
	local AX1, AX2 = -W + 0.2, -W + 2
	box("AccessoryBack", AX1, AX1 + 0.2, FLOOR, 10, AZ1, AZ2, Color3.fromRGB(200, 190, 170), Enum.Material.Wood)
	for _, z in ipairs({ AZ1, AZ2 - 0.2 }) do
		box("AccessorySide", AX1, AX2, FLOOR, 10, z, z + 0.2, WOOD_DARK, Enum.Material.Wood)
	end
	local SLEEVE_COLORS = { Color3.fromRGB(220, 60, 70), Color3.fromRGB(60, 120, 230), Color3.fromRGB(240, 200, 60),
		Color3.fromRGB(40, 40, 50), Color3.fromRGB(150, 80, 220), Color3.fromRGB(60, 190, 140), Color3.fromRGB(240, 240, 245) }
	local n = 0
	for level, y in ipairs({ 1.6, 4, 6.4, 8.8 }) do
		box("AccessoryShelf", AX1, AX2, y - 0.15, y, AZ1, AZ2, WOOD_LIGHT, Enum.Material.Wood)
		for z = AZ1 + 0.45, AZ2 - 0.9, level % 2 == 0 and 0.75 or 1.1 do
			n = n + 1
			local color = SLEEVE_COLORS[n % #SLEEVE_COLORS + 1]
			if level == 1 then
				-- binders, spines out
				box("Binder", AX1 + 0.3, AX1 + 1.6, y, y + 1.9, z, z + 0.45, color)
			elseif level % 2 == 0 then
				-- sleeve packs
				box("Sleeves", AX1 + 0.6, AX1 + 0.75, y, y + 1.2, z, z + 0.6, color)
			else
				-- deck boxes
				box("DeckBox", AX1 + 0.5, AX1 + 1.3, y, y + 1, z, z + 0.85, color)
			end
		end
	end
	local sign = box("AccessorySign", AX2 - 0.2, AX2, 10.3, 11.7, AZ1 + 0.3, AZ2 - 0.3, TRIM)
	text(surface(sign, Enum.NormalId.Right, true), "AccessoryText", "SLEEVES - DECK BOXES - BINDERS", GOLD,
		UDim2.fromScale(0.04, 0.12), UDim2.fromScale(0.92, 0.76))
end

---------------------------------------------------------------------
-- Drinks cooler (right wall) and snacks
---------------------------------------------------------------------
do
	local QX1, QX2, QZ1, QZ2 = W - 2.6, W - 0.2, -5, -0.8
	box("CoolerBody", QX1, QX2, FLOOR, FLOOR + 5.6, QZ1, QZ2, Color3.fromRGB(230, 232, 240), Enum.Material.Metal)
	local inside = box("CoolerInside", QX1 + 0.3, QX2 - 0.3, FLOOR + 0.6, FLOOR + 5, QZ1 + 0.2, QZ2 - 0.2,
		Color3.fromRGB(190, 230, 255), Enum.Material.Neon)
	inside.Transparency = 0.6
	inside.CastShadow = false
	light(inside, 0.8, 8, Color3.fromRGB(190, 230, 255))
	local DRINKS = { Color3.fromRGB(230, 60, 60), Color3.fromRGB(60, 200, 90), Color3.fromRGB(250, 160, 40),
		Color3.fromRGB(70, 130, 240) }
	for row, y in ipairs({ 1.2, 2.5, 3.8 }) do
		box("CoolerShelf", QX1 + 0.3, QX2 - 0.3, FLOOR + y - 0.1, FLOOR + y, QZ1 + 0.2, QZ2 - 0.2, Color3.fromRGB(200, 200, 210))
		for k = 0, 5 do
			local z = QZ1 + 0.45 + k * 0.58
			local can = box("Drink", QX1 + 0.5, QX1 + 0.85, FLOOR + y, FLOOR + y + 0.8, z, z + 0.35, DRINKS[(k + row) % #DRINKS + 1])
			can.Shape = Enum.PartType.Cylinder
			can.Size = Vector3.new(0.8, 0.38, 0.38)
			can.CFrame = CFrame.new(at(QX1 + 0.7, FLOOR + y + 0.4, z + 0.18)) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
	glass(box("CoolerDoor", QX1, QX1 + 0.1, FLOOR + 0.4, FLOOR + 5.2, QZ1 + 0.1, QZ2 - 0.1, GLASS), 0.7)
	local top = box("CoolerSign", QX1, QX2, FLOOR + 5.6, FLOOR + 6.3, QZ1, QZ2, Color3.fromRGB(200, 40, 60))
	text(surface(top, Enum.NormalId.Left, true), "CoolerText", "COLD DRINKS", Color3.fromRGB(255, 255, 255))
	-- snack rack beside it
	box("SnackRack", W - 1.8, W - 0.2, FLOOR, FLOOR + 4.2, -9, -6, WOOD_DARK, Enum.Material.Wood)
	local SNACKS = { Color3.fromRGB(250, 210, 60), Color3.fromRGB(240, 90, 60), Color3.fromRGB(120, 200, 80),
		Color3.fromRGB(170, 100, 230) }
	for row, y in ipairs({ 1.2, 2.4, 3.6 }) do
		for k = 0, 3 do
			local z = -8.8 + k * 0.7
			box("Snack", W - 2, W - 1.8, FLOOR + y - 0.3, FLOOR + y + 0.55, z, z + 0.55, SNACKS[(k + row) % #SNACKS + 1])
		end
	end
end

---------------------------------------------------------------------
-- Bulk bins (front right): boxes of loose commons
---------------------------------------------------------------------
do
	local BX1, BX2, BZ1, BZ2 = 13, 25, 15.5, 19
	box("BulkTable", BX1, BX2, FLOOR, FLOOR + 2.6, BZ1, BZ2, WOOD_DARK, Enum.Material.Wood)
	local CARD_COLORS = { Color3.fromRGB(226, 120, 40), Color3.fromRGB(90, 130, 220), Color3.fromRGB(235, 228, 210) }
	local bulkRng = Random.new(7)
	for i = 0, 2 do
		local x1 = BX1 + 0.4 + i * 3.95
		local x2 = x1 + 3.6
		local t = FLOOR + 2.6
		box("BinFloor", x1, x2, t, t + 0.1, BZ1 + 0.4, BZ2 - 0.4, Color3.fromRGB(205, 175, 130), Enum.Material.Cardboard)
		for _, wall in ipairs({ { x1, x1 + 0.1 }, { x2 - 0.1, x2 } }) do
			box("BinWall", wall[1], wall[2], t, t + 0.9, BZ1 + 0.4, BZ2 - 0.4, Color3.fromRGB(190, 160, 115), Enum.Material.Cardboard)
		end
		for _, z in ipairs({ BZ1 + 0.4, BZ2 - 0.5 }) do
			box("BinWall", x1, x2, t, t + 0.9, z, z + 0.1, Color3.fromRGB(190, 160, 115), Enum.Material.Cardboard)
		end
		-- cards standing in rows, a little messy
		for row = 0, 4 do
			local z = BZ1 + 0.7 + row * 0.5
			local card = box("BulkCards", x1 + 0.2, x2 - 0.2, t + 0.1, t + 0.85 + bulkRng:NextNumber(-0.1, 0.1), z, z + 0.35,
				CARD_COLORS[(row + i) % #CARD_COLORS + 1])
			card.CFrame = card.CFrame * CFrame.Angles(math.rad(bulkRng:NextNumber(-8, 8)), 0, 0)
		end
	end
	local sign = box("BulkSign", BX1 + 2, BX2 - 2, FLOOR + 4.2, FLOOR + 5.6, BZ1 + 0.1, BZ1 + 0.3, Color3.fromRGB(255, 245, 170))
	for _, x in ipairs({ BX1 + 2.3, BX2 - 2.3 }) do
		box("BulkSignPost", x - 0.08, x + 0.08, FLOOR + 3.5, FLOOR + 4.2, BZ1 + 0.1, BZ1 + 0.3, TRIM)
	end
	text(surface(sign, Enum.NormalId.Back, false), "BulkText", "BULK BINS - dig for treasure!", Color3.fromRGB(60, 40, 40),
		UDim2.fromScale(0.04, 0.12), UDim2.fromScale(0.92, 0.76))
end

---------------------------------------------------------------------
-- Capsule machine by the door, playmat barrel, staff door, clock
---------------------------------------------------------------------
do
	local gx, gz = W - 4, D - 7
	box("CapsuleBase", gx - 1.1, gx + 1.1, FLOOR, FLOOR + 3, gz - 1.1, gz + 1.1, Color3.fromRGB(210, 40, 60))
	local globe = box("CapsuleGlobe", gx - 1.3, gx + 1.3, FLOOR + 3, FLOOR + 5.6, gz - 1.3, gz + 1.3, GLASS)
	globe.Shape = Enum.PartType.Ball
	glass(globe, 0.45)
	local capsuleRng = Random.new(3)
	for i = 1, 14 do
		local c = box("Capsule", 0, 0.55, 0, 0.55, 0, 0.55, Color3.fromHSV(capsuleRng:NextNumber(), 0.7, 1))
		c.Shape = Enum.PartType.Ball
		c.CFrame = CFrame.new(at(gx + capsuleRng:NextNumber(-0.7, 0.7), FLOOR + 3.4 + capsuleRng:NextNumber(0, 0.9),
			gz + capsuleRng:NextNumber(-0.7, 0.7)))
	end
	box("CapsuleTop", gx - 0.5, gx + 0.5, FLOOR + 5.5, FLOOR + 5.9, gz - 0.5, gz + 0.5, Color3.fromRGB(210, 40, 60))
	box("CapsuleKnob", gx - 0.3, gx + 0.3, FLOOR + 1.6, FLOOR + 2.2, gz - 1.25, gz - 1.1, Color3.fromRGB(235, 235, 240), Enum.Material.Metal)

	-- rolled-up playmats standing in a barrel (back wall)
	local px, pz = 5.5, -23.8
	local barrel = box("MatBarrel", px - 1.2, px + 1.2, FLOOR, FLOOR + 2.4, pz - 1.2, pz + 1.2, WOOD_DARK, Enum.Material.Wood)
	barrel.Shape = Enum.PartType.Cylinder
	barrel.Size = Vector3.new(2.4, 2.4, 2.4)
	barrel.CFrame = CFrame.new(at(px, FLOOR + 1.2, pz)) * CFrame.Angles(0, 0, math.rad(90))
	local MAT_COLORS = { Color3.fromRGB(226, 120, 40), Color3.fromRGB(90, 130, 220), Color3.fromRGB(170, 80, 200),
		Color3.fromRGB(40, 160, 170), Color3.fromRGB(70, 50, 110) }
	for i, color in ipairs(MAT_COLORS) do
		local a = i * 1.25
		local roll = box("RolledMat", 0, 0.5, 0, 3.6, 0, 0.5, color, Enum.Material.Fabric)
		roll.Shape = Enum.PartType.Cylinder
		roll.Size = Vector3.new(3.6, 0.55, 0.55)
		roll.CFrame = CFrame.new(at(px + math.cos(a) * 0.55, FLOOR + 2.4, pz + math.sin(a) * 0.55))
			* CFrame.Angles(math.rad(math.cos(a) * 6), 0, math.rad(90 + math.sin(a) * 6))
	end

	-- staff door (back wall, between the singles case and the banner)
	box("StaffDoor", -4.6, -1.2, FLOOR, FLOOR + 7.6, -D + 0.2, -D + 0.35, WOOD_DARK, Enum.Material.Wood)
	box("StaffDoorFrame", -4.9, -0.9, FLOOR + 7.6, FLOOR + 7.9, -D + 0.2, -D + 0.4, TRIM)
	box("StaffDoorKnob", -1.8, -1.5, FLOOR + 3.6, FLOOR + 3.9, -D + 0.35, -D + 0.55, GOLD, Enum.Material.Metal)
	local staffSign = box("StaffSign", -3.9, -1.9, FLOOR + 5.6, FLOOR + 6.4, -D + 0.35, -D + 0.4, Color3.fromRGB(240, 240, 240))
	text(surface(staffSign, Enum.NormalId.Back, false), "StaffText", "STAFF ONLY", Color3.fromRGB(180, 30, 40))

	-- clock over the door (inside)
	local clock = box("Clock", -1.6, 1.6, 12.4, 15.6, D - 0.3, D - 0.1, Color3.fromRGB(245, 240, 230))
	local clockGui = surface(clock, Enum.NormalId.Front, false)
	local ring = Instance.new("Frame")
	ring.Name = "ClockFace"
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundColor3 = Color3.fromRGB(245, 240, 230)
	ring.Parent = clockGui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = TRIM
	stroke.Thickness = 6
	stroke.Parent = ring
	text(ring, "ClockText", "TIME TO\nDUEL", TRIM, UDim2.fromScale(0.2, 0.3), UDim2.fromScale(0.6, 0.4))
end

---------------------------------------------------------------------
-- Nova the shop cat, napping on the end of the counter
---------------------------------------------------------------------
local cat
do
	local cx, cz = 11.2, -14.6
	local FUR = Color3.fromRGB(235, 150, 70)
	local CREAM = Color3.fromRGB(250, 230, 200)
	local cushion = box("CatCushion", cx - 1.1, cx + 1.1, T, T + 0.25, cz - 0.8, cz + 0.8, Color3.fromRGB(120, 70, 180), Enum.Material.Fabric)
	local _ = cushion
	local catModel = Instance.new("Model")
	catModel.Name = "ShopCat"
	catModel.Parent = model
	local base = T + 0.25
	cat = box("CatBody", cx - 0.75, cx + 0.55, base, base + 0.75, cz - 0.4, cz + 0.4, FUR, Enum.Material.Fabric, catModel)
	box("CatChest", cx + 0.35, cx + 0.7, base, base + 0.6, cz - 0.3, cz + 0.3, CREAM, Enum.Material.Fabric, catModel)
	box("CatHead", cx + 0.55, cx + 1.15, base + 0.35, base + 0.95, cz - 0.32, cz + 0.32, FUR, Enum.Material.Fabric, catModel)
	box("CatMuzzle", cx + 1.1, cx + 1.25, base + 0.4, base + 0.62, cz - 0.15, cz + 0.15, CREAM, Enum.Material.Fabric, catModel)
	for _, side in ipairs({ -1, 1 }) do
		local ear = Instance.new("WedgePart")
		ear.Name = "CatEar"
		ear.Anchored = true
		ear.Size = Vector3.new(0.12, 0.28, 0.22)
		ear.Color = FUR
		ear.Material = Enum.Material.Fabric
		ear.CFrame = CFrame.new(at(cx + 0.82, base + 1.08, cz + side * 0.2))
		ear.Parent = catModel
		box("CatEye", cx + 1.15, cx + 1.17, base + 0.68, base + 0.78, cz + side * 0.15 - 0.05, cz + side * 0.15 + 0.05,
			Color3.fromRGB(40, 120, 60), Enum.Material.Neon, catModel)
	end
	-- tail curled around the front
	box("CatTail", cx - 0.95, cx - 0.65, base, base + 0.2, cz - 0.1, cz + 0.55, FUR, Enum.Material.Fabric, catModel)
	box("CatTailTip", cx - 0.95, cx + 0.1, base, base + 0.2, cz + 0.45, cz + 0.65, FUR, Enum.Material.Fabric, catModel)
	local tag = box("CatTag", cx + 0.7, cx + 0.74, base + 0.25, base + 0.4, cz - 0.07, cz + 0.07, GOLD, Enum.Material.Metal, catModel)
	local __ = tag
end
Building.Cat = cat

---------------------------------------------------------------------
-- Premium finish: richer materials, ceiling and moldings, stone trim
-- outside, and real light (spotlights on the art, the tables and the
-- facade). Looks best with Lighting > Technology set to Future in Studio.
---------------------------------------------------------------------
do
	local STONE = Color3.fromRGB(196, 186, 176)      -- light limestone trim outside
	local STONE_DARK = Color3.fromRGB(64, 58, 72)    -- dark granite base band
	local MARBLE_DARK = Color3.fromRGB(36, 32, 46)   -- black marble (counter, floor border)
	local CEILING = Color3.fromRGB(34, 28, 48)

	local function sameColor(a, b)
		return math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
	end

	local function spotlight(name, from, to, angle, range, brightness, color, shadows, parent)
		local can = Instance.new("Part")
		can.Name = name
		can.Anchored = true
		can.CanCollide = false
		can.CastShadow = false
		can.Size = Vector3.new(0.45, 0.45, 0.7)
		can.CFrame = CFrame.lookAt(from, to)
		can.Color = TRIM
		can.Material = Enum.Material.Metal
		can.Parent = parent or model
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Angle = angle
		beam.Range = range
		beam.Brightness = brightness
		beam.Color = color or WARM_LIGHT
		beam.Shadows = shadows == true
		beam.Parent = can
		return can
	end

	-- 1) materials: dark trim becomes brushed metal, painted walls plaster,
	--    glass gets a reflection, the countertop black marble
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			if p.Material == Enum.Material.SmoothPlastic and sameColor(p.Color, TRIM) then
				p.Material = Enum.Material.Metal
				p.Reflectance = 0.06
			elseif sameColor(p.Color, WALL_PAINT) then
				p.Material = Enum.Material.Plaster
			elseif p.Material == Enum.Material.Glass then
				p.Reflectance = math.max(p.Reflectance or 0, 0.12)
			end
			if p.Name == "CounterTop" then
				p.Color = MARBLE_DARK
				p.Material = Enum.Material.Marble
				p.Reflectance = 0.08
			elseif p.Name == "Floor" then
				p.Color = Color3.fromRGB(128, 86, 56) -- a deeper walnut
			end
		end
	end

	-- 2) the floor: a black marble border with a thin gold line
	local finish = Instance.new("Model")
	finish.Name = "Finish"
	finish.Parent = model
	local B = 1.2
	for _, r in ipairs({
		{ -W, W, -D, -D + B }, { -W, W, D - B, D }, { -W, -W + B, -D + B, D - B }, { W - B, W, -D + B, D - B },
		}) do
		box("FloorBorder", r[1], r[2], FLOOR, FLOOR + 0.02, r[3], r[4], MARBLE_DARK, Enum.Material.Marble, finish).Reflectance = 0.06
	end
	for _, r in ipairs({
		{ -W + B, W - B, -D + B, -D + B + 0.15 }, { -W + B, W - B, D - B - 0.15, D - B },
		{ -W + B, -W + B + 0.15, -D + B, D - B }, { W - B - 0.15, W - B, -D + B, D - B },
		}) do
		box("FloorInlay", r[1], r[2], FLOOR, FLOOR + 0.025, r[3], r[4], GOLD, Enum.Material.Foil, finish)
	end

	-- 3) a ceiling with wooden beams, crown molding and a glowing cove line
	box("Ceiling", -W, W, H - 0.25, H, -D, D, CEILING, Enum.Material.Plaster, finish)
	for _, x in ipairs({ -32, -16, 0, 16, 32 }) do
		box("CeilingBeam", x - 0.5, x + 0.5, H - 1.1, H - 0.25, -D + 0.7, D - 0.5, WOOD_DARK, Enum.Material.Wood, finish)
	end
	for _, r in ipairs({
		{ -W, -W + 0.5, -D, D }, { W - 0.5, W, -D, D }, { -W, W, D - 0.5, D }, { -W, W, -D, -D + 0.5 },
		}) do
		local molding = box("CrownMolding", r[1], r[2], H - 0.65, H - 0.25, r[3], r[4], TRIM, Enum.Material.Metal, finish)
		molding.Reflectance = 0.06
	end
	for _, r in ipairs({
		{ -W + 0.5, -W + 0.6, -D + 0.5, D - 0.5 }, { W - 0.6, W - 0.5, -D + 0.5, D - 0.5 }, { -W + 0.5, W - 0.5, -D + 0.5, -D + 0.6 },
		}) do
		box("CoveLight", r[1], r[2], H - 0.72, H - 0.65, r[3], r[4], NEON_PURPLE, Enum.Material.Neon, finish).CastShadow = false
	end

	-- 4) ceiling lamps: a metal shade over each glowing panel, and light that
	--    falls downward in a soft pool (instead of a plain glow in every direction)
	for _, lamp in ipairs(model:GetChildren()) do
		if lamp.Name == "CeilingLight" then
			for _, l in ipairs(lamp:GetChildren()) do
				if l:IsA("PointLight") then
					l.Brightness = 0.35
					l.Range = 16
				end
			end
			local pool = Instance.new("SurfaceLight")
			pool.Face = Enum.NormalId.Bottom
			pool.Angle = 110
			pool.Range = 20
			pool.Brightness = 1.5
			pool.Color = WARM_LIGHT
			pool.Shadows = true
			pool.Parent = lamp
			local c = lamp.Position - ORIGIN
			box("LampShade", c.X - 2.7, c.X + 2.7, H - 2.05, H - 1.85, c.Z - 0.9, c.Z + 0.9, TRIM, Enum.Material.Metal, finish)
		end
	end

	-- 5) spotlights on every poster, the playmat banner and the mural
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and (p.Name:sub(1, 7) == "Poster_" or p.Name:sub(1, 7) == "Banner_" or p.Name == "Mural") then
			local c = p.Position - ORIGIN
			local from
			if c.X < -W + 2 then
				from = at(-W + 2.6, H - 1.5, c.Z)
			elseif c.X > W - 2 then
				from = at(W - 2.6, H - 1.5, c.Z)
			else
				from = at(c.X, H - 1.5, -D + 2.6)
			end
			spotlight("ArtLight", from, p.Position, 42, 16, 2.2, Color3.fromRGB(255, 236, 205), false, finish)
		end
	end

	-- 6) a pool of light on each play table (and its felt)
	for _, x in ipairs({ -24, -8, 8, 24 }) do
		for _, dz in ipairs({ -4.5, 4.5 }) do
			spotlight("TableLight", at(x, H - 0.45, 2 + dz), at(x, FLOOR + 3.5, 2), 48, 22, 1.8, WARM_LIGHT, true, finish)
		end
	end

	-- 7) shelves and the singles case light up what's on them
	for _, y in ipairs({ 5, 8.3, 11.6 }) do
		local strip = box("ShelfLight", SX1, SX2, y - 0.4, y - 0.3, SZ + 1.55, SZ + 1.75, WARM_LIGHT, Enum.Material.Neon, finish)
		strip.CastShadow = false
		local down = Instance.new("SurfaceLight")
		down.Face = Enum.NormalId.Bottom
		down.Angle = 120
		down.Range = 5
		down.Brightness = 1.2
		down.Color = WARM_LIGHT
		down.Parent = strip
	end
	do
		local caseLight = Instance.new("SurfaceLight")
		caseLight.Face = Enum.NormalId.Bottom
		caseLight.Angle = 120
		caseLight.Range = 9
		caseLight.Brightness = 1.6
		caseLight.Color = Color3.fromRGB(225, 238, 255)
		caseLight.Parent = caseTop
	end

	-- 8) outside: stone cornices, a granite base, stone pilasters, and lights
	--    shining up the front of the building
	local outside = Instance.new("Model")
	outside.Name = "FacadeTrim"
	outside.Parent = model
	box("Cornice", -W - 1.6, W + 1.6, H + 5, H + 5.55, FZ1 - 0.3, FZ2 + 0.7, STONE, Enum.Material.Limestone, outside)
	box("CorniceStep", -W - 1.3, W + 1.3, H + 4.7, H + 5, FZ2, FZ2 + 0.35, STONE, Enum.Material.Limestone, outside)
	box("RoofCornice", -W - 1.4, W + 1.4, H + 1, H + 1.45, -D - 1.4, FZ1 - 0.3, STONE, Enum.Material.Limestone, outside)
	for _, sideSign in ipairs({ -1, 1 }) do
		local function xs(a, b)
			if sideSign < 0 then
				return -b, -a
			end
			return a, b
		end
		local x1, x2 = xs(DOOR_W + 0.1, W + 1.3)
		box("BaseBand", x1, x2, 0, 1.1, FZ2, FZ2 + 0.3, STONE_DARK, Enum.Material.Granite, outside)
		for _, range in ipairs({ { W, W + 1.4 }, { 6.4, 7.8 } }) do
			local px1, px2 = xs(range[1], range[2])
			box("Pilaster", px1, px2, 1.1, H + 4.7, FZ2, FZ2 + 0.35, STONE, Enum.Material.Limestone, outside)
			local cx = (px1 + px2) / 2
			spotlight("Uplight", at(cx, 0.35, FZ2 + 1.4), at(cx, H + 2, FZ2), 28, 26, 3, WARM_LIGHT, false, outside)
		end
		-- planters by the door, with glowing alien plants
		local pxa, pxb = xs(9.5, 12.5)
		local planter = box("Planter", pxa, pxb, 0.3, 2, FZ2 + 1, FZ2 + 3, STONE_DARK, Enum.Material.Granite, outside)
		local mid = (pxa + pxb) / 2
		for k = 1, 4 do
			local blade = box("GlowPlant", mid - 0.15, mid + 0.15, 2, 2 + 1.6 + k * 0.5, FZ2 + 1.85, FZ2 + 2.15,
				k % 2 == 0 and NEON_PURPLE or Color3.fromRGB(90, 220, 255), Enum.Material.Neon, outside)
			blade.CastShadow = false
			blade.CFrame = blade.CFrame * CFrame.new((k - 2.5) * 0.35, 0, 0) * CFrame.Angles(0, k * 0.8, math.rad((k - 2.5) * 12))
		end
		local plantGlow = Instance.new("PointLight")
		plantGlow.Color = NEON_PURPLE
		plantGlow.Brightness = 0.8
		plantGlow.Range = 9
		plantGlow.Parent = planter
	end
end

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