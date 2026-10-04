--[[
	StarterClient (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > StarterClient

	The starter deck browser, opened at the starter deck table in the shop
	(and shown to brand-new players as their welcome screen):
	  - one tab per faction, with what the faction is about and its keywords
	  - the deck's Commander and Celestial, shown big
	  - the whole deck list (click any card to see it up close)
	  - the playmat that comes with it, and the claim / buy button
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local FactionInfo = require(ReplicatedStorage:WaitForChild("FactionInfo"))
local Playmats = require(ReplicatedStorage:WaitForChild("Playmats"))
local UiAssets = require(ReplicatedStorage:WaitForChild("UiAssets"))
local shopRemotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local shopEvent = shopRemotes:WaitForChild("ShopEvent")
local shopRequest = shopRemotes:WaitForChild("ShopRequest")
local economyRemotes = ReplicatedStorage:WaitForChild("EconomyRemotes")
local walletUpdate = economyRemotes:WaitForChild("WalletUpdate")
local economyRequest = economyRemotes:WaitForChild("EconomyRequest")

local player = Players.LocalPlayer

local WHITE = Color3.fromRGB(255, 255, 255)
local BG = Color3.fromRGB(12, 10, 24)
local PANEL = Color3.fromRGB(24, 20, 42)
local MUTED = Color3.fromRGB(190, 180, 220)
local GOLD = Color3.fromRGB(255, 205, 90)
local GREEN = Color3.fromRGB(60, 140, 90)
local GREY = Color3.fromRGB(80, 80, 90)
local CARD_ASPECT = 1060 / 1484

local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function label(parent, name, position, size, text, maxSize, extra)
	local l = make("TextLabel", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextWrapped = true,
	}, parent)
	for key, value in pairs(extra or {}) do
		l[key] = value
	end
	make("UITextSizeConstraint", { MaxTextSize = maxSize or 20, MinTextSize = 6 }, l)
	return l
end

local function button(parent, name, text, position, size, color)
	local b = make("TextButton", {
		Name = name,
		Text = text,
		Position = position,
		Size = size,
		BackgroundColor3 = color or PANEL,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		AutoButtonColor = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	make("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 6 }, b)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, b)
	return b
end

local function clear(parent)
	for _, child in ipairs(parent:GetChildren()) do
		child:Destroy()
	end
end

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local summary = nil
local selected = FactionInfo.Order[1]
local welcomeMode = false -- true for a brand-new player (no starter yet)
local message = ""
local render

---------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "StarterBrowserGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	DisplayOrder = 6,
	Enabled = false,
}, player:WaitForChild("PlayerGui"))
-- Other screens (the shop's Starter Decks tab) open the browser with this
local openEvent = make("BindableEvent", { Name = "OpenStarterBrowser" }, gui)

local root = make("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BG, BorderSizePixel = 0 }, gui)
local title = label(root, "Title", UDim2.new(0.02, 0, 0, 12), UDim2.new(0.7, 0, 0, 40), "Starter Decks", 30,
	{ TextXAlignment = Enum.TextXAlignment.Left })
local closeButton = button(root, "CloseStarters", "Close", UDim2.new(0.86, 0, 0, 12), UDim2.new(0.12, 0, 0, 40), GREY)
local body = make("Frame", {
	Name = "Body",
	Position = UDim2.new(0.02, 0, 0, 64),
	Size = UDim2.new(0.96, 0, 1, -76),
	BackgroundTransparency = 1,
}, root)

-- Big card view
local zoom = make("TextButton", {
	Name = "Zoom",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.3,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 10,
}, gui)
local function showZoom(cardId)
	clear(zoom)
	local big = make("Frame", {
		Name = "BigCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.47),
		Size = UDim2.fromScale(0.5, 0.8),
		BackgroundTransparency = 1,
		ZIndex = 10,
	}, zoom)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, big)
	CardVisuals.Draw(big, cardId, {})
	for _, d in ipairs(big:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = d.ZIndex + 10
		end
	end
	label(zoom, "ZoomHint", UDim2.fromScale(0.3, 0.9), UDim2.fromScale(0.4, 0.05), "Click anywhere to close", 18,
		{ ZIndex = 11, TextColor3 = MUTED, Font = Enum.Font.Gotham })
	zoom.Visible = true
end
zoom.Activated:Connect(function()
	zoom.Visible = false
end)

-- A card that can be clicked to zoom in
local function cardTile(parent, name, cardId, position, size)
	local tile = make("TextButton", {
		Name = name,
		Text = "",
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
	}, parent)
	local holder = make("Frame", {
		Name = "Holder",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, tile)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, holder)
	CardVisuals.Draw(holder, cardId, {})
	tile.Activated:Connect(function()
		showZoom(cardId)
	end)
	return tile
end

---------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------
local function ownedStarter(name)
	return summary and summary.OwnedStarters and summary.OwnedStarters[name] == true
end

function render()
	clear(body)
	if welcomeMode then
		title.Text = "Welcome to the Card Shop! Pick your first deck. It's free."
	else
		title.Text = "Starter Decks"
	end
	local info = FactionInfo.Get(selected)
	local starter = CardDatabase.StarterDecks[selected]
	local color = CardVisuals.FactionColors[selected] or PANEL

	-- Left: faction tabs
	local tabs = make("Frame", { Name = "FactionTabs", Size = UDim2.fromScale(0.17, 1), BackgroundTransparency = 1 }, body)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	for i, faction in ipairs(FactionInfo.Order) do
		local f = FactionInfo.Get(faction)
		local b = button(tabs, "Faction_" .. faction, "", UDim2.new(), UDim2.new(1, 0, 0, 64),
			faction == selected and CardVisuals.FactionColors[faction] or PANEL)
		b.LayoutOrder = i
		local emblem = UiAssets.Icon(UiAssets.Emblems[faction], UDim2.fromOffset(48, 48), UDim2.new(0, 6, 0.5, -24), b,
			b.ZIndex + 1)
		local textX = emblem and 58 or 0
		label(b, "Name", UDim2.new(0, textX, 0, 0), UDim2.new(1, -textX, 0.55, 0),
			faction .. (ownedStarter(faction) and "  (owned)" or ""), 22)
		label(b, "Style", UDim2.new(0, textX, 0.55, 0), UDim2.new(1, -textX, 0.4, 0), f.Style .. "  |  " .. f.Difficulty, 14,
			{ Font = Enum.Font.Gotham, TextColor3 = faction == selected and WHITE or MUTED })
		if faction == selected then
			make("UIStroke", { Color = GOLD, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		end
		b.Activated:Connect(function()
			selected = faction
			message = ""
			render()
		end)
	end

	-- Middle: about the faction, then the deck list
	local mid = make("Frame", {
		Name = "About",
		Position = UDim2.fromScale(0.185, 0),
		Size = UDim2.fromScale(0.47, 1),
		BackgroundColor3 = PANEL,
	}, body)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, mid)
	make("UIStroke", { Color = color, Thickness = 2 }, mid)
	local bigEmblem = UiAssets.Icon(UiAssets.Emblems[selected], UDim2.fromOffset(52, 52), UDim2.new(1, -66, 0, 8), mid)
	label(mid, "FactionName", UDim2.new(0, 18, 0, 10), UDim2.new(1, bigEmblem and -90 or -36, 0, 44), selected, 36,
		{ TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color:Lerp(WHITE, 0.45) })
	label(mid, "Tagline", UDim2.new(0, 18, 0, 54), UDim2.new(1, -36, 0, 26), info.Tagline, 20,
		{ TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	label(mid, "Description", UDim2.new(0, 18, 0, 86), UDim2.new(1, -36, 0, 92), info.Description, 18,
		{ TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Gotham })
	local kwLines = {}
	for _, kw in ipairs(info.Keywords) do
		table.insert(kwLines, ("%s: %s"):format(kw[1], kw[2]))
	end
	label(mid, "Keywords", UDim2.new(0, 18, 0, 182), UDim2.new(1, -36, 0, 54), table.concat(kwLines, "\n"), 16,
		{ TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = MUTED })
	label(mid, "GoodFor", UDim2.new(0, 18, 0, 240), UDim2.new(1, -36, 0, 22),
		("Style: %s   |   Difficulty: %s   |   %s"):format(info.Style, info.Difficulty, info.GoodFor), 14,
		{ TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.Gotham })

	-- A faction whose cards aren't out yet: just the faction info
	if not starter then
		label(mid, "ComingSoon", UDim2.new(0, 18, 0, 280), UDim2.new(1, -36, 0, 60),
			"This faction's starter deck arrives with its cards in a coming update.", 20,
			{ TextColor3 = GOLD })
		label(body, "ComingSoonRight", UDim2.fromScale(0.67, 0.4), UDim2.fromScale(0.33, 0.1), "Coming soon", 34,
			{ TextColor3 = color:Lerp(WHITE, 0.45) })
		return
	end

	-- deck list
	label(mid, "DeckHeader", UDim2.new(0, 18, 0, 270), UDim2.new(1, -36, 0, 24), "The deck: 30 cards (click any card)", 16,
		{ TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	local list = make("ScrollingFrame", {
		Name = "DeckList",
		Position = UDim2.new(0, 12, 0, 298),
		Size = UDim2.new(1, -24, 1, -306),
		BackgroundTransparency = 1,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BorderSizePixel = 0,
	}, mid)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(92, 148),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, list)
	local ids = {}
	for id in pairs(starter.Cards) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ca, cb = CardDatabase.GetCard(a), CardDatabase.GetCard(b)
		if ca.EnergyCost ~= cb.EnergyCost then
			return ca.EnergyCost < cb.EnergyCost
		end
		return ca.Name < cb.Name
	end)
	for i, id in ipairs(ids) do
		local cell = make("Frame", { Name = "Deck_" .. id, LayoutOrder = i, BackgroundTransparency = 1 }, list)
		cardTile(cell, "Card", id, UDim2.new(), UDim2.new(1, 0, 1, -20))
		label(cell, "Copies", UDim2.new(0, 0, 1, -18), UDim2.new(1, 0, 0, 18), "x" .. starter.Cards[id], 14)
	end

	-- Right: Commander, Celestial, playmat, claim
	local right = make("Frame", {
		Name = "Leaders",
		Position = UDim2.fromScale(0.67, 0),
		Size = UDim2.fromScale(0.33, 1),
		BackgroundTransparency = 1,
	}, body)
	label(right, "LeadersHeader", UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.04), "Commander and Celestial", 18,
		{ TextColor3 = GOLD })
	cardTile(right, "Commander", starter.Commander, UDim2.fromScale(0, 0.05), UDim2.fromScale(0.49, 0.5))
	cardTile(right, "Celestial", starter.Celestial, UDim2.fromScale(0.51, 0.05), UDim2.fromScale(0.49, 0.5))
	local mat = Playmats.ForStarter(selected) or Playmats.Get(Playmats.DefaultId)
	local matFrame = make("Frame", {
		Name = "Playmat",
		Position = UDim2.fromScale(0.05, 0.57),
		Size = UDim2.fromScale(0.9, 0.18),
		BackgroundColor3 = PANEL,
	}, right)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, matFrame)
	Playmats.Draw(matFrame, mat.Id, 0)
	label(right, "PlaymatName", UDim2.fromScale(0, 0.755), UDim2.fromScale(1, 0.04), "Comes with the " .. mat.Name .. " playmat", 16,
		{ Font = Enum.Font.Gotham })

	local price = summary and summary.StarterPrice or 0
	local owned = ownedStarter(selected)
	local claimText = owned and "You own this deck"
		or (price == 0 and ("Take the %s deck (free)"):format(selected) or ("Buy for %d coins"):format(price))
	local claim = button(right, "ClaimStarter", claimText, UDim2.fromScale(0.05, 0.81), UDim2.fromScale(0.9, 0.09),
		owned and GREY or GREEN)
	label(right, "StarterMessage", UDim2.fromScale(0, 0.92), UDim2.fromScale(1, 0.07), message, 16,
		{ TextColor3 = GOLD, Font = Enum.Font.Gotham })
	claim.Activated:Connect(function()
		if owned then
			return
		end
		local ok, result = shopRequest:InvokeServer("ClaimStarter", { Deck = selected })
		if ok then
			welcomeMode = false
			message = ("The %s starter deck is yours! Try it at any play table."):format(selected)
		else
			message = result
		end
		render()
	end)
end

local function open(faction, isWelcome)
	if faction and FactionInfo.Get(faction) then
		selected = faction
	end
	welcomeMode = isWelcome or false
	message = ""
	gui.Enabled = true
	render()
end

closeButton.Activated:Connect(function()
	gui.Enabled = false
	zoom.Visible = false
end)
openEvent.Event:Connect(function(faction)
	open(faction, false)
end)

shopEvent.OnClientEvent:Connect(function(payload)
	if payload.Kind == "OpenStarters" then
		open(nil, summary ~= nil and next(summary.OwnedStarters) == nil)
	end
end)

-- Brand-new players see this first, as the welcome screen
local welcomed = false
local function onSummary(newSummary)
	summary = newSummary
	if not welcomed and next(summary.OwnedStarters) == nil then
		welcomed = true
		open(nil, true)
	elseif gui.Enabled then
		render()
	end
end
walletUpdate.OnClientEvent:Connect(onSummary)
task.spawn(function()
	local ok, result = economyRequest:InvokeServer("GetSummary", {})
	if ok and result then
		onSummary(result)
	end
end)
