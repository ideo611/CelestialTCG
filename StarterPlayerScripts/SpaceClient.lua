--[[
	SpaceClient (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > SpaceClient

	Draws the sky over the planet on this player's screen:
	  - a ringed gas giant, two moons, a distant sun and glowing nebula clouds
	    (they stay put in the sky as you walk, like a real skybox)
	  - shooting stars every few seconds
	  - the shows SpaceWorld starts for everyone: meteor showers, a comet,
	    a fleet flying over, auroras, and a supply ship that drops a crate
	    of new cards at the landing pad
	It also blinks the landing pad lights and turns the radio dish.
	Everything is made on this screen only, so it costs the server nothing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local skyEvent = ReplicatedStorage:WaitForChild("SpaceRemotes"):WaitForChild("SkyEvent")

local WHITE = Color3.fromRGB(255, 255, 255)
local CYAN = Color3.fromRGB(90, 220, 255)

local fx = Instance.new("Folder")
fx.Name = "SkyFX"
fx.Parent = workspace

local function part(name, size, color, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Parent = parent or fx
	return p
end

local function ball(name, diameter, color, material, parent)
	local p = part(name, Vector3.new(diameter, diameter, diameter), color, material, parent)
	p.Shape = Enum.PartType.Ball
	return p
end

local function cameraPosition()
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.Position or Vector3.new(0, 10, 0)
end

---------------------------------------------------------------------
-- The sky: parts that follow the camera so they look infinitely far away
---------------------------------------------------------------------
local skyParts = {} -- { Part, Offset (CFrame relative to the camera position) }
local skyFolder = Instance.new("Folder")
skyFolder.Name = "Sky"
skyFolder.Parent = fx

local function skyPart(p, offset)
	p.Parent = skyFolder
	table.insert(skyParts, { Part = p, Offset = offset })
	return p
end

local PLANET_AT = Vector3.new(-430, 300, -800)
local PLANET_SIZE = 520
local function buildSky()
	-- the gas giant, with color bands wrapped around it
	skyPart(ball("GasGiant", PLANET_SIZE, Color3.fromRGB(118, 92, 196), Enum.Material.SmoothPlastic), CFrame.new(PLANET_AT))
	local bands = {
		{ -0.55, Color3.fromRGB(150, 110, 210) }, { -0.25, Color3.fromRGB(96, 76, 170) },
		{ 0.05, Color3.fromRGB(170, 130, 220) }, { 0.32, Color3.fromRGB(100, 80, 180) }, { 0.6, Color3.fromRGB(140, 120, 215) },
	}
	local tilt = CFrame.Angles(0, 0, math.rad(18))
	for i, band in ipairs(bands) do
		local y = band[1] * PLANET_SIZE / 2
		local chord = 2 * math.sqrt((PLANET_SIZE / 2) ^ 2 - y * y) + 1.5
		local cylinder = part("PlanetBand", Vector3.new(PLANET_SIZE * 0.06, chord, chord), band[2], Enum.Material.SmoothPlastic)
		cylinder.Shape = Enum.PartType.Cylinder
		skyPart(cylinder, CFrame.new(PLANET_AT) * tilt * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local _ = i
	end
	-- the rings, made of many flat pieces around the planet
	local RING_IN, RING_OUT, PIECES = PLANET_SIZE * 0.68, PLANET_SIZE * 1.02, 72
	local ringTilt = CFrame.Angles(math.rad(14), 0, math.rad(18))
	for i = 1, PIECES do
		local angle = (i / PIECES) * math.pi * 2
		local mid = (RING_IN + RING_OUT) / 2
		local width = 2 * math.pi * mid / PIECES * 1.08
		local piece = part("Ring", Vector3.new(width, 1.5, RING_OUT - RING_IN),
			i % 2 == 0 and Color3.fromRGB(235, 205, 170) or Color3.fromRGB(205, 175, 150), Enum.Material.SmoothPlastic)
		piece.Transparency = 0.35
		skyPart(piece, CFrame.new(PLANET_AT) * ringTilt * CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0, -mid))
	end
	-- moons
	local moon = skyPart(ball("Moon", 120, Color3.fromRGB(205, 210, 228), Enum.Material.Slate), CFrame.new(560, 430, -660))
	for i, c in ipairs({ { 0.3, 0.2, 18 }, { -0.25, -0.1, 26 }, { 0.05, -0.35, 14 }, { -0.1, 0.35, 12 } }) do
		skyPart(ball("MoonCrater", c[3], Color3.fromRGB(160, 165, 185), Enum.Material.Slate),
			CFrame.new(560, 430, -660) * CFrame.new(c[1] * 120, c[2] * 120, 60 - c[3] * 0.3))
		local _ = i
	end
	local _ = moon
	skyPart(ball("SmallMoon", 46, Color3.fromRGB(220, 150, 130), Enum.Material.Slate), CFrame.new(150, 560, -880))
	-- a distant sun and its glow
	skyPart(ball("FarSun", 50, Color3.fromRGB(255, 240, 210)), CFrame.new(860, 140, 380))
	local halo = skyPart(ball("FarSunGlow", 130, Color3.fromRGB(255, 200, 150)), CFrame.new(860, 140, 380))
	halo.Transparency = 0.82
	-- nebula clouds
	for i, cloud in ipairs({
		{ Vector3.new(300, 520, 700), 420, Color3.fromRGB(200, 90, 220) },
		{ Vector3.new(-700, 460, 400), 360, Color3.fromRGB(90, 140, 255) },
		{ Vector3.new(-200, 700, -300), 500, Color3.fromRGB(150, 80, 230) },
		{ Vector3.new(800, 600, -200), 300, Color3.fromRGB(255, 110, 170) },
	}) do
		local c = ball("Nebula", cloud[2], cloud[3])
		c.Transparency = 0.9
		c.Size = Vector3.new(cloud[2], cloud[2] * 0.4, cloud[2] * 0.8)
		skyPart(c, CFrame.new(cloud[1]) * CFrame.Angles(0, i, 0.3 * i))
	end
end

local function updateSky()
	local at = CFrame.new(cameraPosition())
	for _, entry in ipairs(skyParts) do
		entry.Part.CFrame = at * entry.Offset
	end
end

---------------------------------------------------------------------
-- Moving effects: each has Update(t, dt) that returns false when done
---------------------------------------------------------------------
local effects = {}
local function addEffect(effect)
	table.insert(effects, effect)
	return effect
end

-- A streak of light flying across the sky (shooting stars and meteors)
local function streak(rng, options)
	options = options or {}
	local origin = cameraPosition()
	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = rng:NextNumber(350, 700)
	local height = rng:NextNumber(220, 480)
	local start = origin + Vector3.new(math.cos(angle) * distance, height, math.sin(angle) * distance)
	local direction = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.55, -0.2), rng:NextNumber(-1, 1)).Unit
	local speed = options.Speed or rng:NextNumber(350, 600)
	local life = options.Life or rng:NextNumber(0.8, 1.6)
	local color = options.Color or WHITE
	local length = options.Length or rng:NextNumber(14, 30)
	local p = part("Streak", Vector3.new(options.Width or 0.8, options.Width or 0.8, length), color)
	local age = 0
	return addEffect({
		Update = function(_, dt)
			age = age + dt
			if age >= life then
				p:Destroy()
				return false
			end
			local position = start + direction * speed * age
			p.CFrame = CFrame.lookAt(position, position + direction)
			p.Transparency = math.clamp(age / life, 0, 1) ^ 2
			return true
		end,
	})
end

local METEOR_COLORS = { WHITE, Color3.fromRGB(255, 200, 120), Color3.fromRGB(150, 220, 255), Color3.fromRGB(255, 140, 200) }

local SHOWS = {}

function SHOWS.MeteorShower(rng, duration)
	local spawnClock = 0
	return {
		Message = "A meteor shower is lighting up the sky!",
		Update = function(t, dt)
			spawnClock = spawnClock + dt
			-- builds up, peaks in the middle, fades out
			local rate = 2 + 10 * math.sin(math.clamp(t / duration, 0, 1) * math.pi)
			while spawnClock > 1 / rate do
				spawnClock = spawnClock - 1 / rate
				local big = rng:NextNumber() < 0.15
				streak(rng, {
					Color = METEOR_COLORS[rng:NextInteger(1, #METEOR_COLORS)],
					Width = big and 2 or 0.9,
					Length = big and 60 or nil,
					Life = big and 2.2 or nil,
				})
			end
			return t < duration
		end,
	}
end

function SHOWS.Comet(rng, duration)
	local head = ball("CometHead", 14, Color3.fromRGB(210, 245, 255))
	local coma = ball("CometGlow", 34, CYAN)
	coma.Transparency = 0.75
	local tail = {}
	for i = 1, 24 do
		local piece = ball("CometTail", 14 - i * 0.35, i % 2 == 0 and CYAN or Color3.fromRGB(190, 240, 255))
		piece.Transparency = 0.35 + i * 0.026
		tail[i] = piece
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local from = Vector3.new(math.cos(angle), 0, math.sin(angle)) * 900 + Vector3.new(0, 380, 0)
	local to = Vector3.new(-math.cos(angle), 0, -math.sin(angle)) * 900 + Vector3.new(0, 300, 0)
	local function pathAt(a)
		local base = from:Lerp(to, a)
		return base + Vector3.new(0, math.sin(a * math.pi) * 160, 0)
	end
	return {
		Message = "A comet is crossing the sky. Look up!",
		Update = function(t)
			local a = math.clamp(t / duration, 0, 1)
			local origin = cameraPosition()
			local position = origin + pathAt(a)
			head.CFrame = CFrame.new(position)
			coma.CFrame = CFrame.new(position)
			-- the tail trails behind along the path
			for i, piece in ipairs(tail) do
				piece.CFrame = CFrame.new(origin + pathAt(math.max(0, a - i * 0.006)) + Vector3.new(0, i * 0.8, 0))
			end
			local fade = (a < 0.08 and (1 - a / 0.08)) or (a > 0.92 and (a - 0.92) / 0.08) or 0
			head.Transparency = fade
			if t >= duration then
				head:Destroy()
				coma:Destroy()
				for _, piece in ipairs(tail) do
					piece:Destroy()
				end
				return false
			end
			return true
		end,
	}
end

local function buildShip(scale, hullColor, accent, parent)
	local ship = Instance.new("Model")
	ship.Name = "Ship"
	ship.Parent = parent or fx
	local pieces = {}
	local function add(name, size, offset, color, material)
		local p = part(name, size * scale, color, material or Enum.Material.Metal, ship)
		table.insert(pieces, { Part = p, Offset = CFrame.new(offset.Position * scale) * offset.Rotation })
		return p
	end
	add("Hull", Vector3.new(4, 2.4, 14), CFrame.new(0, 0, 0), hullColor)
	add("Nose", Vector3.new(3, 1.8, 4), CFrame.new(0, -0.2, -8) * CFrame.Angles(math.rad(-15), 0, 0), hullColor)
	add("Wings", Vector3.new(16, 0.5, 5), CFrame.new(0, -0.4, 2), accent)
	add("Fin", Vector3.new(0.5, 3, 3.5), CFrame.new(0, 2, 5), accent)
	local glowL = add("EngineGlow", Vector3.new(1.4, 1.4, 0.6), CFrame.new(-1.2, 0, 7.2), CYAN, Enum.Material.Neon)
	add("EngineGlow", Vector3.new(1.4, 1.4, 0.6), CFrame.new(1.2, 0, 7.2), CYAN, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = CYAN
	light.Brightness = 2
	light.Range = 30 * scale
	light.Parent = glowL
	return {
		Model = ship,
		Place = function(cframe)
			for _, piece in ipairs(pieces) do
				piece.Part.CFrame = cframe * piece.Offset
			end
		end,
	}
end

function SHOWS.Fleet(rng, duration)
	local ships = {}
	local formation = { Vector3.new(0, 0, 0), Vector3.new(-28, 4, 26), Vector3.new(28, 4, 26), Vector3.new(-56, 8, 52), Vector3.new(56, 8, 52) }
	for i = 1, #formation do
		ships[i] = buildShip(i == 1 and 2.2 or 1.6, Color3.fromRGB(200, 205, 220), Color3.fromRGB(110, 70, 190))
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local center = Vector3.new(0, 0, -50)
	local from = center - dir * 900 + Vector3.new(0, 170, 0)
	local to = center + dir * 900 + Vector3.new(0, 210, 0)
	return {
		Message = "A fleet is flying over the outpost!",
		Update = function(t)
			local a = math.clamp(t / duration, 0, 1)
			local lead = from:Lerp(to, a)
			local facing = CFrame.lookAt(lead, lead + (to - from))
			for i, ship in ipairs(ships) do
				ship.Place(facing * CFrame.new(formation[i]))
			end
			if t >= duration then
				for _, ship in ipairs(ships) do
					ship.Model:Destroy()
				end
				return false
			end
			return true
		end,
	}
end

function SHOWS.Aurora(rng, duration)
	local ribbons = {}
	local colors = { Color3.fromRGB(90, 255, 170), Color3.fromRGB(120, 200, 255), Color3.fromRGB(200, 120, 255) }
	for r = 1, 4 do
		local ribbon = { Pieces = {}, Base = Vector3.new(rng:NextNumber(-500, 500), 260 + r * 25, -300 - r * 120),
			Phase = rng:NextNumber(0, 6) }
		for i = 1, 14 do
			local piece = part("Aurora", Vector3.new(42, 120, 2), colors[(r + i) % #colors + 1])
			piece.Transparency = 1
			ribbon.Pieces[i] = piece
		end
		ribbons[r] = ribbon
	end
	return {
		Message = "Aurora lights are dancing over the planet.",
		Update = function(t)
			local a = math.clamp(t / duration, 0, 1)
			local strength = math.sin(a * math.pi) -- fades in and out
			local origin = cameraPosition()
			for _, ribbon in ipairs(ribbons) do
				for i, piece in ipairs(ribbon.Pieces) do
					local x = (i - 7) * 40
					local wave = math.sin(t * 0.7 + i * 0.5 + ribbon.Phase)
					piece.Size = Vector3.new(42, 90 + wave * 40, 2)
					piece.CFrame = CFrame.new(origin + ribbon.Base + Vector3.new(x, wave * 18, math.cos(i * 0.6 + t * 0.3) * 40))
						* CFrame.Angles(0, math.sin(i + t * 0.2) * 0.4, 0)
					piece.Transparency = 1 - strength * (0.32 + 0.12 * wave)
				end
			end
			if t >= duration then
				for _, ribbon in ipairs(ribbons) do
					for _, piece in ipairs(ribbon.Pieces) do
						piece:Destroy()
					end
				end
				return false
			end
			return true
		end,
	}
end

-- Flies in, hovers over the landing pad, lowers a crate of cards, flies off
function SHOWS.SupplyShip(rng, duration)
	local padBase = workspace:FindFirstChild("SpaceWorld") and workspace.SpaceWorld:FindFirstChild("LandingPad")
		and workspace.SpaceWorld.LandingPad:FindFirstChild("PadBase")
	local pad = padBase and padBase.Position or Vector3.new(75, 0, -20)
	local hover = pad + Vector3.new(-9, 26, -8)
	local ship = buildShip(1.8, Color3.fromRGB(235, 200, 90), Color3.fromRGB(60, 60, 72))
	local crate = part("SupplyCrate", Vector3.new(3, 3, 3), Color3.fromRGB(150, 100, 60), Enum.Material.WoodPlanks)
	local cable = part("Cable", Vector3.new(0.2, 1, 0.2), Color3.fromRGB(40, 40, 40), Enum.Material.Metal)
	local angle = rng:NextNumber(0, math.pi * 2)
	local away = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local from = hover + away * 700 + Vector3.new(0, 260, 0)
	local leave = hover - away * 700 + Vector3.new(0, 300, 0)
	local ARRIVE, DROP, LIFT = 14, 26, 32
	local function smooth(x)
		x = math.clamp(x, 0, 1)
		return x * x * (3 - 2 * x)
	end
	return {
		Message = "A supply ship is dropping off new cards at the landing pad!",
		Update = function(t)
			local position, look
			if t < ARRIVE then
				position = from:Lerp(hover, smooth(t / ARRIVE))
				look = hover - from
			elseif t < LIFT then
				position = hover + Vector3.new(0, math.sin(t * 2) * 0.5, 0)
				look = -away
			else
				position = hover:Lerp(leave, smooth((t - LIFT) / (duration - LIFT)) ^ 1.6)
				look = leave - hover
			end
			look = Vector3.new(look.X, 0, look.Z)
			if look.Magnitude < 0.01 then
				look = Vector3.new(0, 0, -1)
			end
			ship.Place(CFrame.lookAt(position, position + look))
			-- the crate rides along, then is lowered on a cable to the pad
			local crateY
			if t < ARRIVE then
				crateY = position.Y - 3.5
			elseif t < DROP then
				crateY = (hover.Y - 3.5) - (hover.Y - 3.5 - (pad.Y + 2.1)) * smooth((t - ARRIVE) / (DROP - ARRIVE))
			else
				crateY = pad.Y + 2.1
			end
			local cratePos = Vector3.new(position.X, crateY, position.Z)
			if t >= DROP then
				cratePos = Vector3.new(hover.X, crateY, hover.Z)
			end
			crate.CFrame = CFrame.new(cratePos)
			local cableTop = position.Y - 1.5
			local cableLength = (t >= ARRIVE and t < LIFT) and math.max(0.1, cableTop - (cratePos.Y + 1.5)) or 0.1
			cable.Size = Vector3.new(0.2, cableLength, 0.2)
			cable.CFrame = CFrame.new(Vector3.new(position.X, cableTop - cableLength / 2, position.Z))
			cable.Transparency = (t >= ARRIVE and t < LIFT) and 0 or 1
			if t >= duration then
				ship.Model:Destroy()
				cable:Destroy()
				-- the crate stays on the pad a little longer, then is "carried inside"
				task.delay(20, function()
					crate:Destroy()
				end)
				return false
			end
			return true
		end,
	}
end

---------------------------------------------------------------------
-- Announcements
---------------------------------------------------------------------
local toastGui = Instance.new("ScreenGui")
toastGui.Name = "SkyToastGui"
toastGui.ResetOnSpawn = false
toastGui.DisplayOrder = 2
toastGui.Parent = player:WaitForChild("PlayerGui")
local toast = Instance.new("TextLabel")
toast.Name = "SkyToast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 64)
toast.Size = UDim2.fromOffset(560, 40)
toast.BackgroundColor3 = Color3.fromRGB(20, 16, 40)
toast.BackgroundTransparency = 0.25
toast.TextColor3 = Color3.fromRGB(230, 220, 255)
toast.Font = Enum.Font.GothamBold
toast.TextScaled = true
toast.Text = ""
toast.Visible = false
toast.Parent = toastGui
local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0.5, 0)
toastCorner.Parent = toast
local toastPadding = Instance.new("UIPadding")
toastPadding.PaddingLeft = UDim.new(0, 16)
toastPadding.PaddingRight = UDim.new(0, 16)
toastPadding.PaddingTop = UDim.new(0, 6)
toastPadding.PaddingBottom = UDim.new(0, 6)
toastPadding.Parent = toast
local toastId = 0
local function showToast(message)
	toastId = toastId + 1
	local mine = toastId
	toast.Text = message
	toast.Visible = true
	task.delay(6, function()
		if toastId == mine then
			toast.Visible = false
		end
	end)
end

---------------------------------------------------------------------
-- Shows from the server
---------------------------------------------------------------------
local activeShow = nil

local function startShow(info)
	local make = SHOWS[info.Kind]
	if not make then
		return
	end
	local elapsed = math.max(0, workspace:GetServerTimeNow() - (info.Started or 0))
	if elapsed >= info.Duration then
		return
	end
	local show = make(Random.new(info.Seed or 1), info.Duration)
	show.Kind = info.Kind
	show.Time = elapsed
	activeShow = show
	showToast(show.Message)
end

skyEvent.OnClientEvent:Connect(startShow)

---------------------------------------------------------------------
-- Things in the world that move: pad lights, the radio dish
---------------------------------------------------------------------
local padLights, dishHead, dishBeacon, dishBase = {}, nil, nil, nil
local function findWorldBits()
	local world = workspace:FindFirstChild("SpaceWorld")
	if not world then
		return
	end
	local pad = world:FindFirstChild("LandingPad")
	if pad then
		padLights = {}
		for _, child in ipairs(pad:GetChildren()) do
			if child.Name == "PadLight" then
				table.insert(padLights, child)
			end
		end
	end
	local dish = world:FindFirstChild("RadioDish")
	if dish then
		dishHead = dish:FindFirstChild("DishBowl")
		dishBeacon = dish:FindFirstChild("DishBeacon")
		dishBase = dishHead and dishHead.Position
	end
end

---------------------------------------------------------------------
-- Every frame
---------------------------------------------------------------------
buildSky()
findWorldBits()
local shootingStarRng = Random.new()
local nextShootingStar = 4
local clock = 0
local blinkClock = 0
local lightIndex = 0

RunService.RenderStepped:Connect(function(dt)
	clock = clock + dt
	updateSky()

	-- shooting stars now and then
	nextShootingStar = nextShootingStar - dt
	if nextShootingStar <= 0 then
		nextShootingStar = shootingStarRng:NextNumber(6, 14)
		streak(shootingStarRng)
	end

	-- the current show
	if activeShow then
		activeShow.Time = activeShow.Time + dt
		if not activeShow.Update(activeShow.Time, dt) then
			activeShow = nil
		end
	end

	-- streaks and other short effects
	for i = #effects, 1, -1 do
		if not effects[i].Update(nil, dt) then
			table.remove(effects, i)
		end
	end

	-- landing lights chase around the pad (faster while a ship is coming in)
	blinkClock = blinkClock + dt
	local step = (activeShow and activeShow.Kind == "SupplyShip") and 0.06 or 0.18
	if #padLights > 0 and blinkClock >= step then
		blinkClock = 0
		lightIndex = lightIndex % #padLights + 1
		for i, bulb in ipairs(padLights) do
			bulb.Transparency = (i == lightIndex or i == (lightIndex % #padLights) + 1) and 0 or 0.7
		end
	end

	-- the radio dish slowly sweeps the sky; its beacon blinks
	if dishHead and dishBase then
		dishHead.CFrame = CFrame.new(dishBase) * CFrame.Angles(0, clock * 0.15, 0) * CFrame.Angles(0, 0, math.rad(55))
		if dishBeacon then
			dishBeacon.CFrame = dishHead.CFrame * CFrame.new(5, 0, 0)
			dishBeacon.Transparency = (clock % 1.6) < 0.25 and 0 or 0.8
		end
	end
	if not dishHead and clock % 5 < dt then
		findWorldBits() -- the world may still be loading in
	end
end)
