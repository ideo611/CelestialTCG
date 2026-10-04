--[[
	BinderServer (Script)
	Location: ServerScriptService > BinderServer

	Card binders. A player can pull out their binder: their character holds
	it (with their name on the cover) and other players can walk up and look
	through it. While someone is flipping through it, the binder opens in
	the owner's hands so everyone nearby can see it's being looked at.

	Requests (BinderRemotes.BinderRequest):
	  "GetMine"                      -> your own binder (always allowed)
	  "SetOut"      { Out = bool }   -> pull out / put away
	  "Look"        { UserId }       -> someone else's binder (must be out, and you nearby)
	  "StopLooking" { UserId }
	  "SetShowcase" { Cards = { { CardId, Finish }, ... } }  -> your front page
	  "SetCover"    { Cover = "Nebula" }
	Events to players (BinderRemotes.BinderEvent):
	  { Kind = "OpenBinder", Binder = view }       (someone's prompt was used)
	  { Kind = "BinderUpdated", Binder = view }    (the owner changed it while you look)
	  { Kind = "BinderClosed", UserId, Name }      (the owner put it away or left)
	  { Kind = "Viewers", Names = { ... } }        (to the owner: who is looking)
	  { Kind = "BinderOut", Out = bool }           (to the owner)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CardArt = require(ReplicatedStorage:WaitForChild("CardArt"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local RateLimit = require(ServerScriptService:WaitForChild("RateLimit"))

local LOOK_DISTANCE = 18 -- studs between you and the binder's owner
local MAX_LOOKS_PER_MINUTE = 30

---------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "BinderRemotes"
local request = Instance.new("RemoteFunction")
request.Name = "BinderRequest"
request.Parent = remotes
local event = Instance.new("RemoteEvent")
event.Name = "BinderEvent"
event.Parent = remotes
remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local held = {}     -- [owner] = the binder model in their hands
local viewers = {}  -- [owner] = { [viewer] = true }
local looks = {}    -- [viewer] = { count, windowStart } (rate limit)

local COVER_COLORS = {
	Black = Color3.fromRGB(28, 26, 36),
}
for faction, color in pairs(CardVisuals.FactionColors) do
	COVER_COLORS[faction] = color
end

local function coverColor(cover)
	return COVER_COLORS[cover] or COVER_COLORS.Black
end

---------------------------------------------------------------------
-- The binder in the player's hands
---------------------------------------------------------------------
local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function looseProps(extra)
	local props = {
		Anchored = false,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		Massless = true,
		CastShadow = false,
		Material = Enum.Material.SmoothPlastic,
	}
	for key, value in pairs(extra) do
		props[key] = value
	end
	return props
end

local function weld(part0, part1, c0, name)
	return make("Weld", { Name = name or "Weld", Part0 = part0, Part1 = part1, C0 = c0 }, part1)
end

-- Where the binder sits: held against the chest, tilted a little forward
local function holdOffset()
	return CFrame.new(0, -0.35, -0.85) * CFrame.Angles(math.rad(-12), 0, 0)
end

local COVER_W, COVER_H, PAGES_D, COVER_D = 1.7, 2.1, 0.22, 0.06
local CLOSED_HINGE = CFrame.new(-COVER_W / 2, 0, -(PAGES_D / 2 + COVER_D / 2))
local function hingeC0(open)
	-- the front cover swings open around the rings on the left edge
	local angle = open and math.rad(150) or 0
	return CLOSED_HINGE * CFrame.Angles(0, -angle, 0) * CFrame.new(COVER_W / 2, 0, 0)
end

local function drawCover(cover, ownerName, coverId, showcase)
	local gui = make("SurfaceGui", {
		Name = "CoverGui",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 100,
		LightInfluence = 0.6,
	}, cover)
	local color = coverColor(coverId)
	local bg = make("Frame", {
		Name = "Cover",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, gui)
	make("UIGradient", {
		Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.15), color:Lerp(Color3.new(0, 0, 0), 0.45)),
		Rotation = 60,
	}, bg)
	-- a window on the cover showing the first card of the front page
	local window = make("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.1),
		Size = UDim2.fromScale(0.62, 0.56),
		BackgroundColor3 = Color3.fromRGB(10, 10, 16),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, bg)
	make("UIStroke", { Color = Color3.fromRGB(230, 200, 120), Thickness = 4 }, window)
	local first = showcase[1]
	local art = first and CardArt.ArtFor(first.CardId)
	if art then
		make("ImageLabel", {
			Name = "Art",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = art,
			ScaleType = Enum.ScaleType.Crop,
		}, window)
	else
		make("TextLabel", {
			Name = "Star",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "★",
			TextScaled = true,
			TextColor3 = color:Lerp(Color3.new(1, 1, 1), 0.5),
			Font = Enum.Font.GothamBlack,
		}, window)
	end
	make("TextLabel", {
		Name = "OwnerName",
		Position = UDim2.fromScale(0.06, 0.72),
		Size = UDim2.fromScale(0.88, 0.12),
		BackgroundTransparency = 1,
		Text = ownerName,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0.5,
		Font = Enum.Font.GothamBlack,
	}, bg)
	make("TextLabel", {
		Name = "BinderWord",
		Position = UDim2.fromScale(0.2, 0.85),
		Size = UDim2.fromScale(0.6, 0.07),
		BackgroundTransparency = 1,
		Text = "CARD BINDER",
		TextScaled = true,
		TextColor3 = Color3.fromRGB(230, 200, 120),
		Font = Enum.Font.GothamBold,
	}, bg)
	return gui
end

-- The open page facing out: a 3x3 grid of sleeves
local function drawPage(pages)
	local gui = make("SurfaceGui", {
		Name = "PageGui",
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 60,
		LightInfluence = 0.6,
	}, pages)
	local grid = make("Frame", {
		Name = "Pockets",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(230, 232, 240),
		BorderSizePixel = 0,
	}, gui)
	local tints = { "Solar", "Lunar", "Nebula", "Void", "Comet", "Solar", "Nebula", "Comet", "Lunar" }
	for i = 0, 8 do
		local col, row = i % 3, math.floor(i / 3)
		make("Frame", {
			Name = "Pocket",
			Position = UDim2.fromScale(0.05 + col * 0.31, 0.04 + row * 0.32),
			Size = UDim2.fromScale(0.28, 0.29),
			BackgroundColor3 = CardVisuals.FactionColors[tints[i + 1]] or Color3.fromRGB(80, 80, 90),
			BorderSizePixel = 0,
		}, grid)
	end
	return gui
end

local function removeBinder(owner)
	local model = held[owner]
	held[owner] = nil
	if model then
		model:Destroy()
	end
end

local function torsoOf(character)
	return character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		or character:FindFirstChild("HumanoidRootPart"))
end

local function buildBinder(owner)
	removeBinder(owner)
	local character = owner.Character
	local torso = torsoOf(character)
	local view = PlayerData.BinderView(owner)
	if not torso or not view then
		return nil
	end
	local color = coverColor(view.Cover)
	local model = make("Model", { Name = "HeldBinder" }, nil)

	local pages = make("Part", looseProps({
		Name = "Pages",
		Size = Vector3.new(COVER_W - 0.08, COVER_H - 0.08, PAGES_D),
		Color = Color3.fromRGB(230, 232, 240),
		CFrame = torso.CFrame * holdOffset(),
	}), model)
	model.PrimaryPart = pages
	weld(torso, pages, holdOffset(), "HoldWeld")
	drawPage(pages)

	local back = make("Part", looseProps({
		Name = "BackCover",
		Size = Vector3.new(COVER_W, COVER_H, COVER_D),
		Color = color:Lerp(Color3.new(0, 0, 0), 0.3),
	}), model)
	weld(pages, back, CFrame.new(0, 0, PAGES_D / 2 + COVER_D / 2))

	local spine = make("Part", looseProps({
		Name = "Spine",
		Size = Vector3.new(0.12, COVER_H, PAGES_D + COVER_D * 2),
		Color = color:Lerp(Color3.new(0, 0, 0), 0.4),
	}), model)
	weld(pages, spine, CFrame.new(-COVER_W / 2 - 0.02, 0, 0))

	for i, y in ipairs({ -0.65, 0, 0.65 }) do
		local ring = make("Part", looseProps({
			Name = "Ring" .. i,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.05, 0.22, 0.22),
			Color = Color3.fromRGB(200, 200, 210),
			Material = Enum.Material.Metal,
		}), model)
		-- a cylinder's round faces point along X, so turn it to face out of the page
		weld(pages, ring, CFrame.new(-COVER_W / 2 + 0.16, y, -PAGES_D / 2) * CFrame.Angles(0, math.rad(90), 0))
	end

	local front = make("Part", looseProps({
		Name = "FrontCover",
		Size = Vector3.new(COVER_W, COVER_H, COVER_D),
		Color = color,
	}), model)
	weld(pages, front, hingeC0(false), "Hinge")
	drawCover(front, view.OwnerName, view.Cover, view.Showcase)

	-- the "look" prompt lives on the binder (the owner's own screen hides it)
	make("ProximityPrompt", {
		Name = "BinderPrompt",
		ActionText = "Look through binder",
		ObjectText = view.OwnerName .. "'s binder",
		HoldDuration = 0,
		MaxActivationDistance = 10,
		RequiresLineOfSight = false,
	}, pages)

	model:SetAttribute("OwnerUserId", owner.UserId)
	model.Parent = character
	held[owner] = model
	return model
end

local function setOpen(owner, open)
	local model = held[owner]
	local pages = model and model:FindFirstChild("Pages")
	local front = model and model:FindFirstChild("FrontCover")
	local hinge = front and front:FindFirstChild("Hinge")
	if hinge then
		hinge.C0 = hingeC0(open)
	end
end

local function viewerNames(owner)
	local names = {}
	for viewer in pairs(viewers[owner] or {}) do
		table.insert(names, viewer.DisplayName)
	end
	table.sort(names)
	return names
end

local function viewersChanged(owner)
	local count = #viewerNames(owner)
	setOpen(owner, count > 0)
	if owner.Parent then
		event:FireClient(owner, { Kind = "Viewers", Names = viewerNames(owner) })
	end
end

local function closeFor(owner, reason)
	for viewer in pairs(viewers[owner] or {}) do
		if viewer.Parent then
			event:FireClient(viewer, { Kind = "BinderClosed", UserId = owner.UserId, Name = owner.DisplayName, Reason = reason })
		end
	end
	viewers[owner] = nil
end

local function putAway(owner, reason)
	closeFor(owner, reason or "put their binder away")
	removeBinder(owner)
	if owner.Parent then
		event:FireClient(owner, { Kind = "BinderOut", Out = false })
	end
end

local function isOut(owner)
	local model = held[owner]
	if model and not model.Parent then
		-- the character the binder was on is gone (respawned)
		held[owner] = nil
		return false
	end
	return model ~= nil
end

local function stopLooking(viewer, owner)
	if viewers[owner] and viewers[owner][viewer] then
		viewers[owner][viewer] = nil
		viewersChanged(owner)
	end
end

local function stopAllLooking(viewer)
	for owner, set in pairs(viewers) do
		if set[viewer] then
			stopLooking(viewer, owner)
		end
	end
end

local function rootPosition(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

local function rateLimited(viewer)
	local now = os.clock()
	local entry = looks[viewer]
	if not entry or now - entry.Start > 60 then
		entry = { Count = 0, Start = now }
		looks[viewer] = entry
	end
	entry.Count = entry.Count + 1
	return entry.Count > MAX_LOOKS_PER_MINUTE
end

-- Start looking at owner's binder. Returns ok, view or message.
local function look(viewer, owner)
	if owner == viewer then
		return true, PlayerData.BinderView(owner)
	end
	if not isOut(owner) then
		return false, owner.DisplayName .. " doesn't have their binder out."
	end
	if rateLimited(viewer) then
		return false, "Slow down a little."
	end
	local a, b = rootPosition(viewer), rootPosition(owner)
	if not a or not b or (a - b).Magnitude > LOOK_DISTANCE then
		return false, "Get closer to " .. owner.DisplayName .. " to look at their binder."
	end
	local view = PlayerData.BinderView(owner)
	if not view then
		return false, "That binder isn't ready yet."
	end
	stopAllLooking(viewer) -- one binder at a time
	viewers[owner] = viewers[owner] or {}
	viewers[owner][viewer] = true
	viewersChanged(owner)
	return true, view
end

-- When the owner changes their binder, everyone looking sees it straight away
local function pushUpdate(owner)
	local view = PlayerData.BinderView(owner)
	if not view then
		return
	end
	for viewer in pairs(viewers[owner] or {}) do
		event:FireClient(viewer, { Kind = "BinderUpdated", Binder = view })
	end
	if isOut(owner) then
		buildBinder(owner) -- new cover color / cover card
		setOpen(owner, next(viewers[owner] or {}) ~= nil)
	end
end

---------------------------------------------------------------------
-- Requests
---------------------------------------------------------------------
local handlers = {}

function handlers.GetMine(player)
	return true, { Binder = PlayerData.BinderView(player), Out = isOut(player), Viewers = viewerNames(player) }
end

function handlers.SetOut(player, args)
	if args.Out == true then
		if not buildBinder(player) then
			return false, "You need to be in the world to pull out your binder."
		end
		event:FireClient(player, { Kind = "BinderOut", Out = true })
		return true, true
	end
	putAway(player)
	return true, false
end

local function findPlayer(userId)
	if type(userId) ~= "number" then
		return nil
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == userId then
			return p
		end
	end
	return nil
end

function handlers.Look(player, args)
	local owner = findPlayer(args.UserId)
	if not owner then
		return false, "That player isn't here."
	end
	return look(player, owner)
end

function handlers.StopLooking(player, args)
	local owner = findPlayer(args.UserId)
	if owner then
		stopLooking(player, owner)
	end
	return true, true
end

function handlers.SetShowcase(player, args)
	local ok, result = PlayerData.SetShowcase(player, args.Cards)
	if ok then
		pushUpdate(player)
	end
	return ok, result
end

function handlers.SetCover(player, args)
	local ok, result = PlayerData.SetBinderCover(player, args.Cover)
	if ok then
		pushUpdate(player)
	end
	return ok, result
end

request.OnServerInvoke = function(player, kind, args)
	if not RateLimit.Allow(player, "Binder", 15, 2) then
		return false, "Slow down a little."
	end
	if type(kind) ~= "string" or not handlers[kind] then
		return false, "Unknown request."
	end
	if type(args) ~= "table" then
		args = {}
	end
	if not PlayerData.IsLoaded(player) then
		return false, "Your cards haven't loaded yet."
	end
	local ok, okResult, result = pcall(handlers[kind], player, args)
	if not ok then
		warn("BinderServer: " .. kind .. " failed: " .. tostring(okResult))
		return false, "Something went wrong. Try again."
	end
	return okResult, result
end

---------------------------------------------------------------------
-- The prompt on someone's binder
---------------------------------------------------------------------
local ProximityPromptService = game:GetService("ProximityPromptService")
ProximityPromptService.PromptTriggered:Connect(function(prompt, viewer)
	if prompt.Name ~= "BinderPrompt" then
		return
	end
	local model = prompt.Parent and prompt.Parent.Parent
	local ownerId = model and model:GetAttribute("OwnerUserId")
	local owner = findPlayer(ownerId)
	if not owner or owner == viewer then
		return
	end
	local ok, result = look(viewer, owner)
	if ok then
		event:FireClient(viewer, { Kind = "OpenBinder", Binder = result })
	else
		event:FireClient(viewer, { Kind = "BinderMessage", Text = result })
	end
end)

---------------------------------------------------------------------
-- Respawning and leaving
---------------------------------------------------------------------
local function watch(player)
	player.CharacterRemoving:Connect(function()
		if held[player] then
			putAway(player, "put their binder away")
		end
		stopAllLooking(player)
	end)
end
Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end

Players.PlayerRemoving:Connect(function(player)
	closeFor(player, "left")
	removeBinder(player)
	stopAllLooking(player)
	viewers[player] = nil
	looks[player] = nil
end)
