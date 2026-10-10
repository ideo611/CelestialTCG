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
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(58, 48, 86)
	Lighting.OutdoorAmbient = Color3.fromRGB(104, 86, 146)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 1 -- metal, glass and polished stone pick up the sky
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.18
	Lighting.FogColor = Color3.fromRGB(40, 26, 70)
	Lighting.FogStart = 400
	Lighting.FogEnd = 3500
	-- Future lighting (real light from every lamp, sharp shadows) can only be
	-- switched on in Studio: Lighting > Technology > Future. (Scripts can't set it.)
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
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
	-- haze that thickens toward the horizon, so the mountains fade into the sky
	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "PlanetHaze"
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.08
	atmosphere.Color = Color3.fromRGB(150, 110, 220)
	atmosphere.Decay = Color3.fromRGB(70, 40, 120)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.4
	atmosphere.Parent = Lighting
	-- post effects (ours are replaced; any the place already has are left alone)
	local function effect(className, name, props)
		local existing = Lighting:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
		if Lighting:FindFirstChildOfClass(className) then
			return nil
		end
		local e = Instance.new(className)
		e.Name = name
		for key, value in pairs(props) do
			e[key] = value
		end
		e.Parent = Lighting
		return e
	end
	effect("BloomEffect", "SpaceBloom", { Intensity = 0.85, Size = 34, Threshold = 1.25 }) -- neon and lamps glow softly
	effect("ColorCorrectionEffect", "SpaceColor", {
		Saturation = 0.14, Contrast = 0.12, Brightness = 0.015, TintColor = Color3.fromRGB(246, 240, 255),
	})
	-- a touch of distance blur: the horizon goes soft, everything near stays sharp
	effect("DepthOfFieldEffect", "SpaceDepth", { FarIntensity = 0.14, FocusDistance = 40, InFocusRadius = 90, NearIntensity = 0 })
end

---------------------------------------------------------------------
-- Ground: real terrain (rolling dust, craters, boulders, mountains)
---------------------------------------------------------------------
local terrain = workspace:FindFirstChildOfClass("Terrain")
local M = Enum.Material

-- The planet's colors for each terrain material
local TERRAIN_COLORS = {
	[M.Slate] = Color3.fromRGB(84, 70, 104),     -- the plain ground
	[M.Ground] = Color3.fromRGB(70, 58, 88),     -- darker patches
	[M.Sand] = Color3.fromRGB(116, 98, 132),     -- dust drifts
	[M.Rock] = Color3.fromRGB(78, 66, 96),       -- crater rims, mountains
	[M.Basalt] = Color3.fromRGB(52, 44, 66),     -- boulders
	[M.Sandstone] = Color3.fromRGB(104, 84, 120), -- mountain bands
	[M.Asphalt] = Color3.fromRGB(46, 40, 58),    -- crater floors
}

local function setupGround()
	if terrain then
		pcall(function()
			terrain.Decoration = false -- (not settable from scripts everywhere)
		end)
		for material, color in pairs(TERRAIN_COLORS) do
			terrain:SetMaterialColor(material, color)
		end
		-- the surface: 16 studs of rock whose top is exactly y = 0 (where everything stands)
		terrain:FillBlock(CFrame.new(0, -8, 0), Vector3.new(2048, 16, 2048), M.Slate)
	end
	-- the place's baseplate goes under the terrain (a safety floor), its grid removed
	local ground = workspace:FindFirstChild("Baseplate")
	if ground and ground:IsA("BasePart") then
		for _, child in ipairs(ground:GetChildren()) do
			if child:IsA("Texture") or child:IsA("Decal") then
				child:Destroy()
			end
		end
	elseif not terrain then
		ground = part("PlanetGround", Vector3.new(2048, 16, 2048), CFrame.new(0, -8, 0), GROUND, M.Slate)
	end
	if ground then
		ground.Color = GROUND_DARK
		ground.Material = M.Slate
		if terrain then
			ground.CFrame = CFrame.new(ground.Position.X, -16 - ground.Size.Y / 2, ground.Position.Z)
		end
	end
	if not terrain then
		return
	end
	-- patches of darker ground and drifts of dust (just the top layer changes)
	for i = 1, 34 do
		local spot = randomSpot(50, 600, 0)
		if spot then
			terrain:FillCylinder(CFrame.new(spot.X, -2, spot.Z), 4, rng:NextNumber(14, 46), i % 3 == 0 and M.Sand or M.Ground)
		end
	end
	-- gentle dunes and hills, away from the shop
	for _ = 1, 46 do
		local radius = rng:NextNumber(24, 70)
		local spot = randomSpot(110 + radius, 640, radius * 0.6)
		if spot then
			terrain:FillBall(Vector3.new(spot.X, -radius * 0.78, spot.Z), radius, rng:NextNumber() < 0.3 and M.Sand or M.Slate)
		end
	end
end

-- A crater: a raised rocky rim and a bowl dug into the ground
local function crater(center, diameter)
	local radius = diameter / 2
	local pieces = math.max(10, math.floor(diameter / 3))
	for i = 1, pieces do
		local angle = (i / pieces) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local r = radius * rng:NextNumber(0.92, 1.05)
		terrain:FillBall(center + Vector3.new(math.cos(angle) * r, rng:NextNumber(-1.5, 0), math.sin(angle) * r),
			radius * rng:NextNumber(0.18, 0.26), M.Rock)
	end
	terrain:FillBall(center + Vector3.new(0, radius * 0.62, 0), radius * 0.95, M.Air)
	terrain:FillCylinder(CFrame.new(center + Vector3.new(0, -radius * 0.33 - 1.5, 0)), 3, radius * 0.4, M.Asphalt) -- (recolors the floor only)
end

-- A boulder: a few lumps of rock pushed together
local function boulder(center, size)
	for i = 1, 3 do
		local s = size * rng:NextNumber(0.4, 0.62)
		terrain:FillBall(center + Vector3.new(rng:NextNumber(-size, size) * 0.35, s * rng:NextNumber(-0.1, 0.35),
			rng:NextNumber(-size, size) * 0.35), s, i == 3 and M.Rock or M.Basalt)
	end
end

-- Crystals: glassy shells with a glowing core
local function crystals(center, parent)
	local model = Instance.new("Model")
	model.Name = "Crystals"
	model.Parent = parent
	local color = CRYSTAL_COLORS[rng:NextInteger(1, #CRYSTAL_COLORS)]
	local tallest
	for _ = 1, rng:NextInteger(3, 6) do
		local height = rng:NextNumber(2.5, 9)
		local width = height * rng:NextNumber(0.18, 0.3)
		local cf = CFrame.new(center + Vector3.new(rng:NextNumber(-2.5, 2.5), height * 0.4, rng:NextNumber(-2.5, 2.5)))
			* CFrame.Angles(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0, math.pi), rng:NextNumber(-0.45, 0.45))
		local shell = part("Crystal", Vector3.new(width, height, width), cf, color:Lerp(Color3.new(1, 1, 1), 0.15), M.Glass, model)
		shell.Transparency = 0.35
		shell.Reflectance = 0.25
		shell.CastShadow = false
		local core = part("CrystalCore", Vector3.new(width * 0.45, height * 0.85, width * 0.45), cf, color, M.Neon, model)
		core.CastShadow = false
		if not tallest or height > tallest.Size.Y then
			tallest = core
		end
	end
	glow(tallest, 1.4, 20, color)
	return model
end

local function setupScenery()
	local scenery = Instance.new("Model")
	scenery.Name = "Scenery"
	scenery.Parent = world
	if terrain then
		for _ = 1, 10 do
			local diameter = rng:NextNumber(30, 70)
			local spot = randomSpot(90, 420, diameter * 0.6)
			if spot then
				crater(spot, diameter)
			end
		end
		for _ = 1, 70 do
			local spot = randomSpot(55, 460, 6)
			if spot then
				boulder(spot, rng:NextNumber(5, 14))
			end
		end
		-- mountains all around the horizon: big rocky masses with peaks and bands
		for i = 1, 22 do
			local angle = (i / 22) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
			local distance = rng:NextNumber(560, 880)
			local base = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance - 30)
			local radius = rng:NextNumber(70, 150)
			terrain:FillBall(base + Vector3.new(0, -radius * 0.35, 0), radius, M.Rock)
			for _ = 1, 3 do
				local r = radius * rng:NextNumber(0.35, 0.6)
				terrain:FillBall(base + Vector3.new(rng:NextNumber(-radius, radius) * 0.4, radius * rng:NextNumber(0.35, 0.7),
					rng:NextNumber(-radius, radius) * 0.4), r, rng:NextNumber() < 0.4 and M.Sandstone or M.Rock)
			end
			-- a sharp spire on some of them
			if i % 3 == 0 then
				local height = rng:NextNumber(90, 170)
				terrain:FillBlock(CFrame.new(base + Vector3.new(0, height * 0.5, 0))
					* CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(0, 3), rng:NextNumber(-0.08, 0.08)),
					Vector3.new(height * 0.22, height, height * 0.2), M.Rock)
			end
		end
	end
	for _ = 1, 26 do
		local spot = randomSpot(50, 300, 4)
		if spot then
			crystals(spot, scenery)
		end
	end
end

---------------------------------------------------------------------
-- Path, landing pad, dish, domes
---------------------------------------------------------------------
local function setupPath()
	local path = Instance.new("Model")
	path.Name = "Path"
	path.Parent = world
	-- solid ground under the whole walk (the terrain is cleared away here)
	part("PathGround", Vector3.new(20, 4, 44), CFrame.new(0, -2, 8), GROUND, Enum.Material.Slate, path)
	-- the walk from the spawn to the door: stone pavers between metal curbs,
	-- a glowing strip set into each curb
	part("Walkway", Vector3.new(12.6, 0.1, 44), CFrame.new(0, 0.05, 8), Color3.fromRGB(88, 82, 100), Enum.Material.Pavement, path)
	for z = -13.5, 29.5, 4 do
		part("PaverJoint", Vector3.new(12.6, 0.12, 0.12), CFrame.new(0, 0.06, z), Color3.fromRGB(52, 46, 62),
			Enum.Material.Concrete, path).CastShadow = false
	end
	for _, x in ipairs({ -6.6, 6.6 }) do
		local curb = part("PathCurb", Vector3.new(0.9, 0.35, 44), CFrame.new(x, 0.17, 8), DARK_METAL, Enum.Material.Metal, path)
		curb.Reflectance = 0.1
		part("PathEdge", Vector3.new(0.25, 0.08, 43.4), CFrame.new(x, 0.36, 8), CYAN, Enum.Material.Neon, path).CastShadow = false
	end
	-- lamp posts: a plinth, a slim pole and an arm reaching over the walk,
	-- with a lamp that throws a pool of light onto the path
	for _, z in ipairs({ -10, 4, 18, 30 }) do
		for _, x in ipairs({ -8.4, 8.4 }) do
			local inward = x < 0 and 1 or -1
			local plinth = part("LampPlinth", Vector3.new(1.2, 0.8, 1.2), CFrame.new(x, 0.4, z), DARK_METAL, Enum.Material.Metal, path)
			plinth.Reflectance = 0.08
			local pole = part("LampPost", Vector3.new(0.35, 8, 0.35), CFrame.new(x, 4.6, z), DARK_METAL, Enum.Material.Metal, path)
			pole.Reflectance = 0.12
			part("LampRing", Vector3.new(0.55, 0.15, 0.55), CFrame.new(x, 2.2, z), Color3.fromRGB(255, 205, 90), Enum.Material.Foil, path)
			part("LampArm", Vector3.new(2.2, 0.22, 0.22), CFrame.new(x + inward * 1, 8.5, z), DARK_METAL, Enum.Material.Metal, path)
			part("LampHead", Vector3.new(1.4, 0.4, 0.9), CFrame.new(x + inward * 1.9, 8.4, z), DARK_METAL, Enum.Material.Metal, path)
			local bulb = part("LampGlobe", Vector3.new(1.1, 0.12, 0.7), CFrame.new(x + inward * 1.9, 8.15, z), CYAN,
				Enum.Material.Neon, path)
			bulb.CastShadow = false
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Bottom
			spot.Angle = 85
			spot.Range = 22
			spot.Brightness = 2.2
			spot.Color = Color3.fromRGB(150, 230, 255)
			spot.Shadows = true
			spot.Parent = bulb
			glow(bulb, 0.4, 9, CYAN)
		end
	end
	-- the sign welcoming you in
	local sign = part("WelcomeSign", Vector3.new(14, 2.6, 0.3), CFrame.new(0, 11, 30), Color3.fromRGB(26, 20, 40), nil, path)
	for _, x in ipairs({ -6.6, 6.6 }) do
		part("WelcomePost", Vector3.new(0.5, 9.8, 0.5), CFrame.new(x, 4.9, 30), DARK_METAL, Enum.Material.Metal, path).Reflectance = 0.12
	end
	-- a gold frame around the sign
	for _, r in ipairs({ { 0, 1.4, 14.4, 0.2 }, { 0, -1.4, 14.4, 0.2 }, { -7.1, 0, 0.2, 3 }, { 7.1, 0, 0.2, 3 } }) do
		part("WelcomeFrame", Vector3.new(r[3], r[4], 0.45), CFrame.new(r[1], 11 + r[2], 30), Color3.fromRGB(255, 205, 90),
			Enum.Material.Foil, path)
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
	disc("PadBase", PAD_CENTER + Vector3.new(0, -1.7, 0), 40, 4.6, Color3.fromRGB(90, 90, 104), Enum.Material.DiamondPlate, pad)
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
	part("Stripe", Vector3.new(6.05, 0.5, 12), base * CFrame.new(0, 4.6, 1), Color3.fromRGB(255, 205, 90), Enum.Material.Foil, ship)
	-- polished hull, and a light on the cockpit
	for _, piece in ipairs(ship:GetChildren()) do
		if piece:IsA("BasePart") and piece.Material == Enum.Material.Metal then
			piece.Reflectance = piece.Color.R > 0.8 and 0.18 or 0.1
		end
	end
	glow(cockpit, 0.8, 8, Color3.fromRGB(120, 200, 255))
	-- floodlights at the pad's corners, aimed at the shuttle
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2 + math.rad(45)
		local spot = PAD_CENTER + Vector3.new(math.cos(angle) * 22, 0, math.sin(angle) * 22)
		part("FloodPost", Vector3.new(0.5, 5, 0.5), CFrame.new(spot + Vector3.new(0, 2.5, 0)), DARK_METAL, Enum.Material.Metal, pad)
		local head = part("FloodLamp", Vector3.new(1.6, 1, 0.5), CFrame.lookAt(spot + Vector3.new(0, 5.2, 0), PAD_CENTER + Vector3.new(0, 3, 0)),
			Color3.fromRGB(255, 240, 210), Enum.Material.Neon, pad)
		head.CastShadow = false
		local beam = Instance.new("SpotLight")
		beam.Face = Enum.NormalId.Front
		beam.Angle = 50
		beam.Range = 34
		beam.Brightness = 2.4
		beam.Color = Color3.fromRGB(255, 236, 205)
		beam.Shadows = true
		beam.Parent = head
	end
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
	part("DishBase", Vector3.new(8, 6, 8), CFrame.new(DISH_CENTER + Vector3.new(0, -1, 0)), DARK_METAL, Enum.Material.Concrete, dish)
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

-- Clear the terrain where buildings stand, so it can never poke up through a
-- floor (the shop, its sidewalk, the path, the pad, the dish and the domes all
-- have solid bases reaching below the ground instead)
local DOMES = { { Vector3.new(0, 0, 0), 30 }, { Vector3.new(26, 0, 12), 20 }, { Vector3.new(-6, 0, 26), 16 } }
local function flattenSettlement()
	if not terrain then
		return
	end
	local AIR = M.Air
	local function clearBox(x1, x2, z1, z2)
		terrain:FillBlock(CFrame.new((x1 + x2) / 2, 28, (z1 + z2) / 2), Vector3.new(x2 - x1, 64, z2 - z1), AIR)
	end
	local function clearRound(center, radius)
		terrain:FillCylinder(CFrame.new(center.X, 28, center.Z), 64, radius, AIR)
	end
	local s = SHOP_CENTER
	clearBox(s.X - 37, s.X + 37, s.Z - 27, s.Z + 27)   -- the shop
	clearBox(s.X - 42, s.X + 42, s.Z + 26, s.Z + 36)   -- its sidewalk
	clearBox(-10, 10, -14, 30)                           -- the path
	clearRound(PAD_CENTER, 20)
	clearBox(DISH_CENTER.X - 4, DISH_CENTER.X + 4, DISH_CENTER.Z - 4, DISH_CENTER.Z + 4)
	for _, info in ipairs(DOMES) do
		clearRound(DOMES_CENTER + info[1], (info[2] + 1.5) / 2)
	end
end

-- Anything standing on the ground (y = 0) reaches 4 studs down, so no gap or
-- sliver shows where it meets the terrain
local function rootInGround(container)
	for _, p in ipairs(container:GetDescendants()) do
		if p:IsA("Part") and p.Shape ~= Enum.PartType.Ball and p.Shape ~= Enum.PartType.Cylinder then
			local bottom = p.Position.Y - p.Size.Y / 2
			local upright = p.CFrame.UpVector.Y > 0.999
			if upright and math.abs(bottom) < 0.02 then
				p.Size = p.Size + Vector3.new(0, 4, 0)
				p.CFrame = p.CFrame * CFrame.new(0, -2, 0)
			end
		end
	end
end

local function setupDomes()
	local domes = Instance.new("Model")
	domes.Name = "HabitatDomes"
	domes.Parent = world
	for i, info in ipairs(DOMES) do
		local center = DOMES_CENTER + info[1]
		local size = info[2]
		local dome = shaped(Enum.PartType.Ball, "Dome", Vector3.new(size, size, size), CFrame.new(center), Color3.fromRGB(160, 220, 255),
			Enum.Material.Glass, domes)
		dome.Transparency = 0.55
		dome.Reflectance = 0.25
		disc("DomeRing", center + Vector3.new(0, -1.5, 0), size + 1.5, 5, METAL, Enum.Material.Metal, domes).Reflectance = 0.15
		-- a ring of little lights around the base
		local count = math.floor(size * 0.8)
		for k = 1, count do
			local a = (k / count) * math.pi * 2
			local r = size / 2 + 0.75
			part("DomeLight", Vector3.new(0.5, 0.25, 0.5), CFrame.new(center + Vector3.new(math.cos(a) * r, 1.1, math.sin(a) * r)),
				CYAN, Enum.Material.Neon, domes).CastShadow = false
		end
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
-- each piece is built on its own: if one fails, the rest still appear
-- (and the error shows in the Output window)
local function build(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		warn(("SpaceWorld: %s failed: %s"):format(name, tostring(err)))
	end
end
if APPLY_LIGHTING then
	build("lighting", setupLighting)
end
build("ground", setupGround)
build("scenery", setupScenery)
build("path", setupPath)
build("landing pad", setupLandingPad)
build("radio dish", setupDish)
build("domes", setupDomes)
build("flatten", flattenSettlement)
-- the place's spawn pad: players still appear on it, but it can't be seen
-- (no grey slab with the spawn symbol on the path) and nobody trips on it
build("spawn", function()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") then
			d.Transparency = 1
			d.CanCollide = false
			d.CastShadow = false
			for _, child in ipairs(d:GetChildren()) do
				if child:IsA("Decal") or child:IsA("Texture") then
					child:Destroy()
				end
			end
		end
	end
end)
build("rooting", function()
	rootInGround(world)
end)
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
