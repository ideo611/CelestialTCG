--[[
	SpaceWorld (Script)
	Location: ServerScriptService > SpaceWorld

	Puts the card shop on an alien planet:
	  - night sky full of stars, a purple haze and glowing neon (Lighting)
	  - rocky violet ground with craters, boulders and glowing crystals
	  - a lit path from the spawn to the shop door
	  - a landing pad with a parked shuttle, a radio dish and habitat domes
	And runs the sky shows everyone sees together (the effects themselves are
	drawn on each player's screen by SpaceClient):
	  - meteor showers, a passing comet, a fleet flying over, auroras,
	    and a supply ship that lands on the pad and takes off again.

	Everything here is decoration: change or remove it freely.
	Set APPLY_LIGHTING = false to keep your own Lighting settings.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local APPLY_LIGHTING = true
local EVENT_GAP = { 75, 150 } -- seconds between sky events (random in this range)

-- Where things are (the shop's door faces +Z, toward the spawn)
local SHOP_CENTER = Vector3.new(0, 0, -50)
local SHOP_HALF = Vector3.new(44, 0, 36)      -- keep decorations out of this box around the shop
local PATH_HALF_WIDTH = 9                      -- and off the path from the spawn to the door
local PAD_CENTER = Vector3.new(75, 0, -20)    -- landing pad
local DISH_CENTER = Vector3.new(-80, 0, -80)  -- radio dish
local DOMES_CENTER = Vector3.new(-85, 0, 5)   -- habitat domes

local GROUND = Color3.fromRGB(78, 64, 96)
local GROUND_DARK = Color3.fromRGB(56, 46, 72)
local ROCK = Color3.fromRGB(70, 60, 84)
local CRYSTAL_COLORS = { Color3.fromRGB(170, 110, 255), Color3.fromRGB(90, 220, 255), Color3.fromRGB(255, 110, 200) }
local METAL = Color3.fromRGB(150, 150, 165)
local DARK_METAL = Color3.fromRGB(60, 60, 72)
local CYAN = Color3.fromRGB(90, 220, 255)

local world = Instance.new("Model")
world.Name = "SpaceWorld"

local rng = Random.new(2026) -- the same layout every time

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function part(name, size, cframe, color, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent or world
	return p
end

local function shaped(shape, name, size, cframe, color, material, parent)
	local p = part(name, size, cframe, color, material, parent)
	p.Shape = shape
	return p
end

local function glow(p, brightness, range, color)
	local light = Instance.new("PointLight")
	light.Brightness = brightness
	light.Range = range
	light.Color = color
	light.Parent = p
	return light
end

-- A flat disc lying on the ground (cylinders point along X, so tip it up)
local function disc(name, center, diameter, thickness, color, material, parent)
	return shaped(Enum.PartType.Cylinder, name, Vector3.new(thickness, diameter, diameter),
		CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material, parent)
end

local function clearOfShop(position, margin)
	margin = margin or 0
	local d = position - SHOP_CENTER
	if math.abs(d.X) < SHOP_HALF.X + margin and math.abs(d.Z) < SHOP_HALF.Z + margin then
		return false
	end
	-- the path from the spawn (around the origin) to the door
	if math.abs(position.X) < PATH_HALF_WIDTH + margin and position.Z > -20 and position.Z < 40 then
		return false
	end
	for _, spot in ipairs({ PAD_CENTER, DISH_CENTER, DOMES_CENTER }) do
		if (Vector3.new(position.X, 0, position.Z) - spot).Magnitude < 26 + margin then
			return false
		end
	end
	-- the spawn area
	if Vector3.new(position.X, 0, position.Z).Magnitude < 22 + margin then
		return false
	end
	return true
end

-- A random spot on the ground, away from the shop, the path and the landmarks
local function randomSpot(minRadius, maxRadius, margin)
	for _ = 1, 40 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(minRadius, maxRadius)
		local spot = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius - 30)
		if clearOfShop(spot, margin) then
			return spot
		end
	end
	return nil
end

---------------------------------------------------------------------
-- Sky and light
---------------------------------------------------------------------
local function setupLighting()
	Lighting.ClockTime = 0.5
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(70, 58, 100)
	Lighting.OutdoorAmbient = Color3.fromRGB(110, 92, 150)
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.FogColor = Color3.fromRGB(40, 26, 70)
	Lighting.FogStart = 400
	Lighting.FogEnd = 3500
	for _, child in ipairs(Lighting:GetChildren()) do
		if child:IsA("Sky") or child:IsA("Atmosphere") then
			child:Destroy()
		end
	end
	local sky = Instance.new("Sky")
	sky.Name = "SpaceSky"
	sky.StarCount = 5000
	sky.CelestialBodiesShown = false -- the planet and moons are ours (SpaceClient)
	sky.Parent = Lighting
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "PlanetHaze"
	atmosphere.Density = 0.12
	atmosphere.Offset = 0.05
	atmosphere.Color = Color3.fromRGB(150, 110, 220)
	atmosphere.Decay = Color3.fromRGB(70, 40, 120)
	atmosphere.Glare = 0.2
	atmosphere.Haze = 0.6
	atmosphere.Parent = Lighting
	if not Lighting:FindFirstChild("SpaceBloom") then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "SpaceBloom"
		bloom.Intensity = 0.7
		bloom.Size = 28
		bloom.Threshold = 1.6
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChild("SpaceColor") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "SpaceColor"
		cc.Saturation = 0.12
		cc.Contrast = 0.05
		cc.TintColor = Color3.fromRGB(245, 238, 255)
		cc.Parent = Lighting
	end
end

---------------------------------------------------------------------
-- Ground
---------------------------------------------------------------------
local function setupGround()
	-- reuse the place's baseplate as the planet's surface (or make one)
	local ground = workspace:FindFirstChild("Baseplate")
	if ground and ground:IsA("BasePart") then
		for _, child in ipairs(ground:GetChildren()) do
			if child:IsA("Texture") or child:IsA("Decal") then
				child:Destroy() -- the grid texture
			end
		end
	else
		ground = part("PlanetGround", Vector3.new(2048, 16, 2048), CFrame.new(0, -8, 0), GROUND, Enum.Material.Slate)
	end
	ground.Color = GROUND
	ground.Material = Enum.Material.Slate

	-- patches of darker and dustier ground
	local patches = Instance.new("Model")
	patches.Name = "GroundPatches"
	patches.Parent = world
	for i = 1, 26 do
		local spot = randomSpot(60, 420, 0)
		if spot then
			local size = rng:NextNumber(30, 90)
			local color = i % 2 == 0 and GROUND_DARK or Color3.fromRGB(96, 78, 110)
			disc("Patch", spot + Vector3.new(0, 0.02 + i * 0.002, 0), size, 0.1, color,
				i % 3 == 0 and Enum.Material.Sand or Enum.Material.Slate, patches)
		end
	end
end

-- A crater: a dark floor with a raised rim of rocks around it
local function crater(center, diameter, parent)
	local model = Instance.new("Model")
	model.Name = "Crater"
	model.Parent = parent
	disc("CraterFloor", center + Vector3.new(0, 0.06, 0), diameter, 0.12, Color3.fromRGB(44, 36, 58), Enum.Material.Slate, model)
	local radius = diameter / 2
	local pieces = math.max(10, math.floor(diameter / 2.5))
	for i = 1, pieces do
		local angle = (i / pieces) * math.pi * 2
		local width = 2 * math.pi * radius / pieces + 1.2
		part("CraterRim", Vector3.new(width, rng:NextNumber(1.2, 2.6), 2.4),
			CFrame.new(center + Vector3.new(math.cos(angle) * radius, 0.4, math.sin(angle) * radius))
				* CFrame.Angles(0, -angle + math.pi / 2, 0) * CFrame.Angles(math.rad(rng:NextNumber(-25, -10)), 0, 0),
			ROCK, Enum.Material.Slate, model)
	end
	return model
end

local function boulder(center, size, parent)
	local model = Instance.new("Model")
	model.Name = "Boulder"
	model.Parent = parent
	for i = 1, 3 do
		local s = size * rng:NextNumber(0.55, 1)
		part("Rock", Vector3.new(s, s * rng:NextNumber(0.5, 0.9), s * rng:NextNumber(0.7, 1.1)),
			CFrame.new(center + Vector3.new(rng:NextNumber(-size, size) * 0.4, s * 0.25, rng:NextNumber(-size, size) * 0.4))
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi), rng:NextNumber(-0.4, 0.4)),
			i == 1 and ROCK or Color3.fromRGB(84, 70, 98), i == 2 and Enum.Material.Basalt or Enum.Material.Slate, model)
	end
	return model
end

local function crystals(center, parent)
	local model = Instance.new("Model")
	model.Name = "Crystals"
	model.Parent = parent
	local color = CRYSTAL_COLORS[rng:NextInteger(1, #CRYSTAL_COLORS)]
	local tallest
	for i = 1, rng:NextInteger(3, 6) do
		local height = rng:NextNumber(2.5, 9)
		local width = height * rng:NextNumber(0.18, 0.3)
		local crystal = part("Crystal", Vector3.new(width, height, width),
			CFrame.new(center + Vector3.new(rng:NextNumber(-2.5, 2.5), height * 0.4, rng:NextNumber(-2.5, 2.5)))
				* CFrame.Angles(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0, math.pi), rng:NextNumber(-0.45, 0.45)),
			color, Enum.Material.Neon, model)
		crystal.Transparency = 0.15
		crystal.CastShadow = false
		if not tallest or height > tallest.Size.Y then
			tallest = crystal
		end
		local _ = i
	end
	glow(tallest, 1.2, 18, color)
	return model
end

local function setupScenery()
	local scenery = Instance.new("Model")
	scenery.Name = "Scenery"
	scenery.Parent = world
	for _ = 1, 9 do
		local spot = randomSpot(90, 380, 25)
		if spot then
			crater(spot, rng:NextNumber(26, 60), scenery)
		end
	end
	for _ = 1, 70 do
		local spot = randomSpot(55, 420, 4)
		if spot then
			boulder(spot, rng:NextNumber(3, 12), scenery)
		end
	end
	for _ = 1, 26 do
		local spot = randomSpot(50, 300, 4)
		if spot then
			crystals(spot, scenery)
		end
	end
	-- a few huge rock spires on the horizon
	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2 + 0.3
		local spot = Vector3.new(math.cos(angle) * 520, 0, math.sin(angle) * 520 - 30)
		local height = rng:NextNumber(60, 140)
		part("Spire", Vector3.new(height * 0.35, height, height * 0.3),
			CFrame.new(spot + Vector3.new(0, height * 0.42, 0)) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), rng:NextNumber(0, 3), rng:NextNumber(-0.12, 0.12)),
			Color3.fromRGB(62, 50, 78), Enum.Material.Slate, scenery)
	end
end

---------------------------------------------------------------------
-- Path, landing pad, dish, domes
---------------------------------------------------------------------
local function setupPath()
	local path = Instance.new("Model")
	path.Name = "Path"
	path.Parent = world
	-- glowing strips on each side of the walk from the spawn to the door
	for _, x in ipairs({ -6.5, 6.5 }) do
		part("PathEdge", Vector3.new(0.4, 0.15, 44), CFrame.new(x, 0.08, 8), CYAN, Enum.Material.Neon, path).CastShadow = false
	end
	part("Walkway", Vector3.new(12.6, 0.1, 44), CFrame.new(0, 0.05, 8), Color3.fromRGB(70, 66, 80), Enum.Material.Concrete, path)
	-- lamp posts
	for _, z in ipairs({ -10, 4, 18, 30 }) do
		for _, x in ipairs({ -8, 8 }) do
			part("LampPost", Vector3.new(0.4, 7, 0.4), CFrame.new(x, 3.5, z), DARK_METAL, Enum.Material.Metal, path)
			local bulb = shaped(Enum.PartType.Ball, "LampGlobe", Vector3.new(1.3, 1.3, 1.3), CFrame.new(x, 7.4, z), CYAN,
				Enum.Material.Neon, path)
			bulb.CastShadow = false
			glow(bulb, 1.4, 16, CYAN)
		end
	end
	-- the sign welcoming you in
	local sign = part("WelcomeSign", Vector3.new(14, 2.6, 0.3), CFrame.new(0, 11, 30), Color3.fromRGB(26, 20, 40), nil, path)
	for _, x in ipairs({ -6.6, 6.6 }) do
		part("WelcomePost", Vector3.new(0.4, 9.8, 0.4), CFrame.new(x, 4.9, 30), DARK_METAL, Enum.Material.Metal, path)
	end
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "WelcomeText"
		gui.Face = face
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = sign
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.TextColor3 = Color3.fromRGB(255, 205, 90)
		label.Text = "OUTPOST CARD SHOP"
		label.Parent = gui
	end
end

local function setupLandingPad()
	local pad = Instance.new("Model")
	pad.Name = "LandingPad"
	pad.Parent = world
	disc("PadBase", PAD_CENTER + Vector3.new(0, 0.3, 0), 40, 0.6, Color3.fromRGB(90, 90, 104), Enum.Material.DiamondPlate, pad)
	disc("PadCircle", PAD_CENTER + Vector3.new(0, 0.62, 0), 26, 0.05, Color3.fromRGB(240, 200, 70), Enum.Material.SmoothPlastic, pad)
	disc("PadInner", PAD_CENTER + Vector3.new(0, 0.66, 0), 24, 0.05, Color3.fromRGB(90, 90, 104), Enum.Material.DiamondPlate, pad)
	-- landing lights around the edge (SpaceClient makes them blink)
	for i = 1, 12 do
		local angle = (i / 12) * math.pi * 2
		local bulb = shaped(Enum.PartType.Ball, "PadLight", Vector3.new(0.9, 0.9, 0.9),
			CFrame.new(PAD_CENTER + Vector3.new(math.cos(angle) * 19.2, 0.9, math.sin(angle) * 19.2)), CYAN, Enum.Material.Neon, pad)
		bulb.CastShadow = false
	end
	-- the parked shuttle
	local ship = Instance.new("Model")
	ship.Name = "ParkedShuttle"
	ship.Parent = pad
	local base = CFrame.new(PAD_CENTER + Vector3.new(0, 0, 0)) * CFrame.Angles(0, math.rad(35), 0)
	local hull = Color3.fromRGB(225, 225, 235)
	part("Hull", Vector3.new(6, 4, 16), base * CFrame.new(0, 4.2, 0), hull, Enum.Material.Metal, ship)
	part("Nose", Vector3.new(5, 3, 5), base * CFrame.new(0, 4, -9.5) * CFrame.Angles(math.rad(-20), 0, 0), hull, Enum.Material.Metal, ship)
	local cockpit = part("Cockpit", Vector3.new(4.2, 1.6, 4), base * CFrame.new(0, 6.3, -6) * CFrame.Angles(math.rad(-12), 0, 0),
		Color3.fromRGB(120, 200, 255), Enum.Material.Glass, ship)
	cockpit.Transparency = 0.3
	for _, side in ipairs({ -1, 1 }) do
		part("Wing", Vector3.new(9, 0.6, 7), base * CFrame.new(side * 7, 3.4, 2) * CFrame.Angles(0, 0, math.rad(side * -8)),
			Color3.fromRGB(110, 70, 190), Enum.Material.Metal, ship)
		part("WingTip", Vector3.new(0.6, 2.6, 4), base * CFrame.new(side * 11.3, 4.2, 3.2), hull, Enum.Material.Metal, ship)
		part("Leg", Vector3.new(0.6, 2.4, 0.6), base * CFrame.new(side * 2.4, 1.4, -4), DARK_METAL, Enum.Material.Metal, ship)
		part("Leg", Vector3.new(0.6, 2.4, 0.6), base * CFrame.new(side * 2.4, 1.4, 5), DARK_METAL, Enum.Material.Metal, ship)
		local engine = shaped(Enum.PartType.Cylinder, "Engine", Vector3.new(4, 2.4, 2.4),
			base * CFrame.new(side * 2, 4.2, 8.6) * CFrame.Angles(0, math.rad(90), 0), DARK_METAL, Enum.Material.Metal, ship)
		local flame = shaped(Enum.PartType.Cylinder, "EngineGlow", Vector3.new(0.3, 1.9, 1.9),
			base * CFrame.new(side * 2, 4.2, 10.6) * CFrame.Angles(0, math.rad(90), 0), CYAN, Enum.Material.Neon, ship)
		flame.CastShadow = false
		local _ = engine
	end
	part("Stripe", Vector3.new(6.05, 0.5, 12), base * CFrame.new(0, 4.6, 1), Color3.fromRGB(255, 205, 90), Enum.Material.SmoothPlastic, ship)
	part("Ramp", Vector3.new(3.2, 0.3, 6), base * CFrame.new(0, 1.6, 10.5) * CFrame.Angles(math.rad(22), 0, 0), METAL,
		Enum.Material.DiamondPlate, ship)
	-- a stack of crates waiting for the next delivery
	for i, offset in ipairs({ Vector3.new(14, 1.5, 9), Vector3.new(16.6, 1.5, 9.4), Vector3.new(15.2, 4.4, 9.2) }) do
		local crate = part("Crate", Vector3.new(2.8, 2.8, 2.8), CFrame.new(PAD_CENTER + offset) * CFrame.Angles(0, i * 0.3, 0),
			Color3.fromRGB(150, 100, 60), Enum.Material.WoodPlanks, pad)
		local _ = crate
	end
end

local function setupDish()
	local dish = Instance.new("Model")
	dish.Name = "RadioDish"
	dish.Parent = world
	part("DishBase", Vector3.new(8, 2, 8), CFrame.new(DISH_CENTER + Vector3.new(0, 1, 0)), DARK_METAL, Enum.Material.Concrete, dish)
	-- lattice tower
	for _, c in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do
		part("TowerLeg", Vector3.new(0.5, 26, 0.5), CFrame.new(DISH_CENTER + Vector3.new(c[1], 15, c[2]))
			* CFrame.Angles(math.rad(c[2] * -1.5), 0, math.rad(c[1] * 1.5)), METAL, Enum.Material.Metal, dish)
	end
	for y = 6, 26, 5 do
		part("TowerBrace", Vector3.new(4.5, 0.3, 0.3), CFrame.new(DISH_CENTER + Vector3.new(0, y, -2)), METAL, Enum.Material.Metal, dish)
		part("TowerBrace", Vector3.new(4.5, 0.3, 0.3), CFrame.new(DISH_CENTER + Vector3.new(0, y, 2)), METAL, Enum.Material.Metal, dish)
	end
	-- the dish: a squashed ball tilted toward the sky (SpaceClient turns it slowly)
	local head = shaped(Enum.PartType.Ball, "DishBowl", Vector3.new(18, 18, 18),
		CFrame.new(DISH_CENTER + Vector3.new(0, 30, 0)), Color3.fromRGB(215, 215, 225), Enum.Material.Metal, dish)
	head.Size = Vector3.new(4, 18, 18)
	head.Shape = Enum.PartType.Cylinder
	head.CFrame = CFrame.new(DISH_CENTER + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(55))
	local tip = shaped(Enum.PartType.Ball, "DishBeacon", Vector3.new(1.4, 1.4, 1.4),
		head.CFrame * CFrame.new(5, 0, 0), Color3.fromRGB(255, 60, 70), Enum.Material.Neon, dish)
	tip.CastShadow = false
	glow(tip, 2, 20, Color3.fromRGB(255, 60, 70))
end

local function setupDomes()
	local domes = Instance.new("Model")
	domes.Name = "HabitatDomes"
	domes.Parent = world
	for i, info in ipairs({ { Vector3.new(0, 0, 0), 30 }, { Vector3.new(26, 0, 12), 20 }, { Vector3.new(-6, 0, 26), 16 } }) do
		local center = DOMES_CENTER + info[1]
		local size = info[2]
		local dome = shaped(Enum.PartType.Ball, "Dome", Vector3.new(size, size, size), CFrame.new(center), Color3.fromRGB(160, 220, 255),
			Enum.Material.Glass, domes)
		dome.Transparency = 0.45
		disc("DomeRing", center + Vector3.new(0, 0.5, 0), size + 1.5, 1, METAL, Enum.Material.Metal, domes)
		-- a glow inside, and plants growing under the glass
		local lamp = part("DomeLamp", Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, size * 0.3, 0)), Color3.fromRGB(255, 230, 180),
			Enum.Material.Neon, domes)
		lamp.Transparency = 1
		glow(lamp, 1.5, size, Color3.fromRGB(255, 220, 170))
		for j = 1, 3 + i do
			local a = j * 2.1
			shaped(Enum.PartType.Ball, "DomePlant", Vector3.new(3, 3, 3),
				CFrame.new(center + Vector3.new(math.cos(a) * size * 0.22, 1.2, math.sin(a) * size * 0.22)),
				Color3.fromRGB(70, 170, 110), Enum.Material.Grass, domes)
		end
	end
	-- a tube connecting the big dome to the next
	part("Tube", Vector3.new(4, 4, 18), CFrame.lookAt(DOMES_CENTER + Vector3.new(6, 2, 2), DOMES_CENTER + Vector3.new(26, 2, 12))
		* CFrame.new(0, 0, -6), Color3.fromRGB(160, 220, 255), Enum.Material.Glass, domes).Transparency = 0.4
end

---------------------------------------------------------------------
-- Sky events (everyone sees the same show; SpaceClient draws it)
---------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "SpaceRemotes"
local skyEvent = Instance.new("RemoteEvent")
skyEvent.Name = "SkyEvent"
skyEvent.Parent = remotes
remotes.Parent = ReplicatedStorage

local EVENTS = {
	{ Kind = "MeteorShower", Duration = 28, Weight = 3 },
	{ Kind = "Comet", Duration = 50, Weight = 2 },
	{ Kind = "Fleet", Duration = 30, Weight = 2 },
	{ Kind = "Aurora", Duration = 45, Weight = 2 },
	{ Kind = "SupplyShip", Duration = 46, Weight = 2 },
}

local current = nil -- { Kind, Seed, Started, Duration }

local function pickEvent(lastKind)
	local total = 0
	for _, e in ipairs(EVENTS) do
		if e.Kind ~= lastKind then
			total = total + e.Weight
		end
	end
	local roll = rng:NextNumber(0, total)
	for _, e in ipairs(EVENTS) do
		if e.Kind ~= lastKind then
			roll = roll - e.Weight
			if roll <= 0 then
				return e
			end
		end
	end
	return EVENTS[1]
end

local function startEvent(event)
	current = {
		Kind = event.Kind,
		Seed = rng:NextInteger(1, 1000000),
		Started = workspace:GetServerTimeNow(),
		Duration = event.Duration,
	}
	skyEvent:FireAllClients(current)
end

-- Someone joining mid-show still sees the rest of it
Players.PlayerAdded:Connect(function(player)
	if current and workspace:GetServerTimeNow() < current.Started + current.Duration then
		skyEvent:FireClient(player, current)
	end
end)

local SpaceWorld = {}

-- For testing in Studio: SpaceWorld.Trigger("Comet") from the command bar is not
-- available (this is a Script), so use the "SpaceEventNow" attribute instead:
-- set workspace:SetAttribute("SpaceEventNow", "Comet") while playing.
workspace:GetAttributeChangedSignal("SpaceEventNow"):Connect(function()
	local kind = workspace:GetAttribute("SpaceEventNow")
	for _, e in ipairs(EVENTS) do
		if e.Kind == kind then
			startEvent(e)
		end
	end
end)

---------------------------------------------------------------------
-- Build it
---------------------------------------------------------------------
if APPLY_LIGHTING then
	setupLighting()
end
setupGround()
setupScenery()
setupPath()
setupLandingPad()
setupDish()
setupDomes()
world.Parent = workspace

task.spawn(function()
	local last = nil
	task.wait(20) -- a little quiet time first
	while true do
		local event = pickEvent(last)
		last = event.Kind
		startEvent(event)
		task.wait(event.Duration + rng:NextNumber(EVENT_GAP[1], EVENT_GAP[2]))
	end
end)

return SpaceWorld
