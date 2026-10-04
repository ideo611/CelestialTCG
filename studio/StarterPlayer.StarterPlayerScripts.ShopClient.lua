--[[
	ShopClient (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > ShopClient

	The Card Shop screen (opened at the shop counter):
	  - Packs: buy with coins or Star Shards. The odds are always shown, with a
	    "Card-by-card odds" button for every card's chance (Roblox rule).
	  - Opening a pack: six face-down cards; click each to flip it, best card last.
	  - Starter Decks: your first one is free, the rest cost coins.
	  - Star Tokens: trade 30 for any Commander or Celestial.
	  - Break Down: turn extra copies into Star Shards.
	  - Playmats: buy mats with coins and pick which one you bring to the table.
	Also shows big-pull announcements and a welcome screen for brand-new players.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local Playmats = require(ReplicatedStorage:WaitForChild("Playmats"))
local shopRemotes = ReplicatedStorage:WaitForChild("ShopRemotes")
local shopEvent = shopRemotes:WaitForChild("ShopEvent")
local shopRequest = shopRemotes:WaitForChild("ShopRequest")
local economyRemotes = ReplicatedStorage:WaitForChild("EconomyRemotes")
local walletUpdate = economyRemotes:WaitForChild("WalletUpdate")
local economyRequest = economyRemotes:WaitForChild("EconomyRequest")

local player = Players.LocalPlayer

local WHITE = Color3.fromRGB(255, 255, 255)
local BG = Color3.fromRGB(14, 11, 28)
local PANEL = Color3.fromRGB(24, 20, 42)
local ACCENT = Color3.fromRGB(70, 60, 120)
local SELECTED = Color3.fromRGB(120, 100, 200)
local GOLD = Color3.fromRGB(255, 200, 60)
local GREEN = Color3.fromRGB(60, 140, 90)
local GREY = Color3.fromRGB(80, 80, 90)

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
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
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextWrapped = true,
		Text = text,
	}, parent)
	if extra then
		for key, value in pairs(extra) do
			l[key] = value
		end
	end
	make("UITextSizeConstraint", { MaxTextSize = maxSize or 22, MinTextSize = 6 }, l)
	return l
end

local function button(parent, name, text, position, size, color)
	local b = make("TextButton", {
		Name = name,
		Text = text,
		Position = position,
		Size = size,
		BackgroundColor3 = color or ACCENT,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		AutoButtonColor = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	make("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 6 }, b)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
	}, b)
	return b
end

local function clear(parent)
	for _, child in ipairs(parent:GetChildren()) do
		child:Destroy()
	end
end

local function scroller(parent, name, position, size)
	return make("ScrollingFrame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, parent)
end

local function ask(kind, args)
	return shopRequest:InvokeServer(kind, args or {})
end

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local summary = nil
local tab = "Packs"
local message = ""
local oddsTable = nil
local render

local function ownedCount(cardId)
	local total = 0
	if summary and summary.Collection[cardId] then
		for _, count in pairs(summary.Collection[cardId]) do
			total = total + count
		end
	end
	return total
end

---------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------
local gui = make("ScreenGui", {
	Name = "ShopGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	DisplayOrder = 4,
	Enabled = false,
}, player:WaitForChild("PlayerGui"))

local root = make("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BG, BorderSizePixel = 0 }, gui)
local TABS = { { "Packs", "Packs" }, { "Starters", "Starter Decks" }, { "Tokens", "Star Tokens" },
	{ "BreakDown", "Break Down" }, { "Playmats", "Playmats" } }
local tabButtons = {}
for i, info in ipairs(TABS) do
	tabButtons[info[1]] = button(root, "Tab_" .. info[1], info[2], UDim2.new(0.02 + (i - 1) * 0.12, 0, 0, 12),
		UDim2.new(0.115, 0, 0, 40))
	tabButtons[info[1]].Activated:Connect(function()
		tab = info[1]
		message = ""
		render()
	end)
end
local closeButton = button(root, "CloseShop", "Close", UDim2.new(0.88, 0, 0, 12), UDim2.new(0.1, 0, 0, 40), GREY)
local walletLabel = label(root, "ShopWallet", UDim2.new(0.62, 0, 0, 12), UDim2.new(0.25, 0, 0, 40), "", 18)
local messageLabel = label(root, "ShopMessage", UDim2.new(0.02, 0, 0, 58), UDim2.new(0.96, 0, 0, 26), "", 18,
	{ TextColor3 = Color3.fromRGB(255, 230, 120) })
local content = make("Frame", {
	Name = "Content",
	Position = UDim2.new(0.02, 0, 0, 90),
	Size = UDim2.new(0.96, 0, 1, -100),
	BackgroundTransparency = 1,
}, root)

---------------------------------------------------------------------
-- Odds details popup
---------------------------------------------------------------------
local oddsPopup = make("Frame", {
	Name = "OddsPopup",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.6, 0.8),
	BackgroundColor3 = PANEL,
	Visible = false,
	ZIndex = 5,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, oddsPopup)
label(oddsPopup, "OddsTitle", UDim2.new(0, 16, 0, 10), UDim2.new(1, -32, 0, 34), "Card-by-card odds", 24, { ZIndex = 5 })
local oddsList = scroller(oddsPopup, "OddsList", UDim2.new(0, 16, 0, 50), UDim2.new(1, -32, 1, -110))
oddsList.ZIndex = 5
local oddsClose = button(oddsPopup, "CloseOdds", "Close", UDim2.new(0.5, -60, 1, -50), UDim2.fromOffset(120, 38), GREY)
oddsClose.ZIndex = 5
oddsClose.Activated:Connect(function()
	oddsPopup.Visible = false
end)

local function showOddsDetails()
	if not oddsTable then
		return
	end
	clear(oddsList)
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, oddsList)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingRight = UDim.new(0, 16) }, oddsList)
	local order = 0
	local function line(text, bold, color)
		order = order + 1
		label(oddsList, "Line_" .. order, UDim2.new(), UDim2.new(1, 0, 0, bold and 28 or 22), text, bold and 20 or 16, {
			LayoutOrder = order,
			ZIndex = 5,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
			TextColor3 = color or WHITE,
		})
	end
	for _, slot in ipairs(oddsTable.Slots) do
		line(("%s  (x%d per pack) - each card:"):format(slot.Name, slot.Count), true, GOLD)
		for _, outcome in ipairs(slot.Outcomes) do
			line(("  %s: %s"):format(outcome.Label, outcome.Shown), true)
			for _, entry in ipairs(outcome.Cards) do
				local card = CardDatabase.GetCard(entry.CardId)
				line(("      %s  %s"):format(card.Name, entry.Shown))
			end
		end
	end
	line(oddsTable.PityText, true, GOLD)
	oddsPopup.Visible = true
end

---------------------------------------------------------------------
-- Pack reveal
---------------------------------------------------------------------
local reveal = make("Frame", {
	Name = "Reveal",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(6, 4, 14),
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 6,
}, gui)
local revealTitle = label(reveal, "RevealTitle", UDim2.fromScale(0.1, 0.06), UDim2.fromScale(0.8, 0.08),
	"Click each card to flip it", 30, { ZIndex = 6 })
local revealRow = make("Frame", {
	Name = "RevealRow",
	Position = UDim2.fromScale(0.04, 0.2),
	Size = UDim2.fromScale(0.92, 0.55),
	BackgroundTransparency = 1,
	ZIndex = 6,
}, reveal)
local revealAll = button(reveal, "RevealAll", "Reveal all", UDim2.fromScale(0.3, 0.84), UDim2.fromScale(0.18, 0.07))
revealAll.ZIndex = 6
local revealDone = button(reveal, "RevealDone", "Done", UDim2.fromScale(0.52, 0.84), UDim2.fromScale(0.18, 0.07), GREEN)
revealDone.ZIndex = 6

local BIG_POOLS = { LegendaryDeckCard = "LEGENDARY!", CommanderOrCelestial = "LEGENDARY!", Mythic = "MYTHIC!!" }
local revealState = nil

local function flip(index)
	local entry = revealState and revealState.Slots[index]
	if not entry or entry.Flipped then
		return
	end
	entry.Flipped = true
	revealState.Remaining = revealState.Remaining - 1
	local pull = entry.Pull
	local cardButton = entry.Button
	clear(cardButton)
	CardVisuals.Draw(cardButton, pull.CardId, { Finish = pull.Finish })
	for _, child in ipairs(cardButton:GetDescendants()) do
		if child:IsA("TextLabel") then
			child.ZIndex = 7
		end
	end
	local card = CardDatabase.GetCard(pull.CardId)
	local big = BIG_POOLS[pull.Pool]
	local captionText = CardVisuals.FinishNames[pull.Finish] .. (pull.New and "  NEW!" or "")
	if big then
		captionText = big .. "  " .. captionText
		local stroke = cardButton:FindFirstChild("RarityStroke")
		if stroke then
			stroke.Thickness = 5
		end
	end
	entry.Caption.Text = captionText
	entry.Caption.TextColor3 = pull.Finish == "Mythic" and CardVisuals.MythicColor
		or (CardVisuals.RarityColors[card.Rarity] or WHITE)
	if revealState.Remaining == 0 then
		revealTitle.Text = "Added to your collection!"
		revealAll.Visible = false
	end
end

local function startReveal(pulls)
	clear(revealRow)
	revealState = { Slots = {}, Remaining = #pulls }
	revealTitle.Text = "Click each card to flip it"
	revealAll.Visible = true
	local width = 1 / #pulls
	for i, pull in ipairs(pulls) do
		local holder = make("Frame", {
			Name = "Slot_" .. i,
			Position = UDim2.new((i - 1) * width, 6, 0, 0),
			Size = UDim2.new(width, -12, 1, 0),
			BackgroundTransparency = 1,
			ZIndex = 6,
		}, revealRow)
		local cardButton = make("TextButton", {
			Name = "Card",
			Text = "",
			Size = UDim2.new(1, 0, 1, -34),
			AutoButtonColor = true,
			ZIndex = 6,
		}, holder)
		CardVisuals.DrawFaceDown(cardButton, i == #pulls and "Star Slot" or "?")
		for _, child in ipairs(cardButton:GetDescendants()) do
			if child:IsA("TextLabel") then
				child.ZIndex = 7
			end
		end
		local caption = label(holder, "Caption", UDim2.new(0, 0, 1, -30), UDim2.new(1, 0, 0, 28), "", 18, { ZIndex = 6 })
		revealState.Slots[i] = { Pull = pull, Button = cardButton, Caption = caption, Flipped = false }
		cardButton.Activated:Connect(function()
			flip(i)
		end)
	end
	reveal.Visible = true
end

revealAll.Activated:Connect(function()
	if revealState then
		for i = 1, #revealState.Slots do
			flip(i)
		end
	end
end)
revealDone.Activated:Connect(function()
	if revealState and revealState.Remaining > 0 then
		for i = 1, #revealState.Slots do
			flip(i)
		end
		return
	end
	reveal.Visible = false
	revealState = nil
	render()
end)

---------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------
local function renderPacks()
	local panel = make("Frame", {
		Name = "PackPanel",
		Size = UDim2.new(0.34, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(60, 40, 110),
	}, content)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
	make("UIStroke", { Color = GOLD, Thickness = 3 }, panel)
	label(panel, "PackName", UDim2.fromScale(0.08, 0.08), UDim2.fromScale(0.84, 0.14), "Celestial Booster", 34)
	label(panel, "PackSize", UDim2.fromScale(0.08, 0.24), UDim2.fromScale(0.84, 0.08), "6 cards per pack", 20,
		{ Font = Enum.Font.Gotham })

	local buyCoins = button(panel, "BuyWithCoins", ("Buy with %d coins"):format(EconomyConfig.PackPriceCoins),
		UDim2.fromScale(0.1, 0.6), UDim2.fromScale(0.8, 0.12), GREEN)
	local buyShards = button(panel, "BuyWithShards", ("Buy with %d Star Shards"):format(EconomyConfig.PackPriceShards),
		UDim2.fromScale(0.1, 0.76), UDim2.fromScale(0.8, 0.12), Color3.fromRGB(60, 110, 170))
	local function buy(currency)
		local ok, result = ask("BuyPack", { Currency = currency })
		if ok then
			message = ""
			startReveal(result)
		else
			message = result
			render()
		end
	end
	buyCoins.Activated:Connect(function()
		buy("Coins")
	end)
	buyShards.Activated:Connect(function()
		buy("Shards")
	end)

	-- Odds are shown right here, before buying
	local oddsFrame = make("Frame", {
		Name = "OddsPanel",
		Position = UDim2.new(0.36, 0, 0, 0),
		Size = UDim2.new(0.64, 0, 1, 0),
		BackgroundColor3 = PANEL,
	}, content)
	make("UICorner", { CornerRadius = UDim.new(0, 12) }, oddsFrame)
	label(oddsFrame, "OddsHeader", UDim2.new(0, 16, 0, 10), UDim2.new(1, -32, 0, 34), "Pack odds", 26,
		{ TextXAlignment = Enum.TextXAlignment.Left })
	local lines = {}
	if oddsTable then
		for _, slot in ipairs(oddsTable.Slots) do
			local parts = {}
			for _, outcome in ipairs(slot.Outcomes) do
				table.insert(parts, ("%s %s"):format(outcome.Label, outcome.Shown))
			end
			table.insert(lines, ("%s (x%d):  %s"):format(slot.Name, slot.Count, table.concat(parts, "  |  ")))
		end
		table.insert(lines, "")
		table.insert(lines, oddsTable.PityText)
	else
		table.insert(lines, "Loading odds...")
	end
	label(oddsFrame, "OddsSummary", UDim2.new(0, 16, 0, 52), UDim2.new(1, -32, 0.6, -52), table.concat(lines, "\n"), 20, {
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local details = button(oddsFrame, "OddsDetails", "Card-by-card odds", UDim2.new(0, 16, 1, -60),
		UDim2.new(0.4, 0, 0, 44))
	details.Activated:Connect(showOddsDetails)
end

local function renderStarters()
	local price = summary.StarterPrice or 0
	local grid = scroller(content, "StarterGrid", UDim2.new(), UDim2.fromScale(1, 1))
	make("UIGridLayout", {
		CellSize = UDim2.new(0.31, 0, 0, 260),
		CellPadding = UDim2.new(0.02, 0, 0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 10) }, grid)
	for i, name in ipairs(CardDatabase.StarterDeckOrder) do
		local starter = CardDatabase.StarterDecks[name]
		local ownedIt = summary.OwnedStarters[name] == true
		local box = make("Frame", {
			Name = "Starter_" .. name,
			LayoutOrder = i,
			BackgroundColor3 = CardVisuals.FactionColors[name] or ACCENT,
		}, grid)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
		label(box, "StarterName", UDim2.fromScale(0.05, 0.04), UDim2.fromScale(0.9, 0.16), name .. " Starter Deck", 26)
		label(box, "StarterInfo", UDim2.fromScale(0.07, 0.22), UDim2.fromScale(0.86, 0.48),
			("%s\n\nCommander: %s\nCelestial: %s\n30 ready-to-play cards\nIncludes the %s playmat"):format(starter.Description,
				CardDatabase.GetCard(starter.Commander).Name, CardDatabase.GetCard(starter.Celestial).Name,
				(Playmats.ForStarter(name) or Playmats.Get(Playmats.DefaultId)).Name), 18,
			{ Font = Enum.Font.Gotham })
		local text = ownedIt and "Owned" or (price == 0 and "Claim free" or ("Buy for %d coins"):format(price))
		local b = button(box, "ClaimStarter", text, UDim2.fromScale(0.1, 0.76), UDim2.fromScale(0.8, 0.17),
			ownedIt and GREY or GREEN)
		b.Activated:Connect(function()
			if ownedIt then
				return
			end
			local ok, result = ask("ClaimStarter", { Deck = name })
			message = ok and (name .. " starter deck added to your collection!") or result
			render()
		end)
	end
end

local function renderTokens()
	local cost = EconomyConfig.TokenExchangeCost
	label(content, "TokenInfo", UDim2.new(), UDim2.new(1, 0, 0, 30),
		("You have %d Star Tokens. Every pack gives %d. Trade %d for any Commander or Celestial."):format(
			summary.StarTokens, EconomyConfig.TokensPerPack, cost), 20, { Font = Enum.Font.Gotham })
	local grid = scroller(content, "TokenGrid", UDim2.new(0, 0, 0, 40), UDim2.new(1, 0, 1, -40))
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 250),
		CellPadding = UDim2.fromOffset(10, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 10) }, grid)
	local order = 0
	for _, card in ipairs(CardDatabase.GetAllCards()) do
		if (card.Type == "Commander" or card.Type == "Celestial") and card.InPacks ~= false then
			order = order + 1
			local cell = make("Frame", { Name = "Trade_" .. card.Id, LayoutOrder = order, BackgroundTransparency = 1 }, grid)
			local cardFrame = make("Frame", { Name = "Card", Size = UDim2.new(1, 0, 0, 200) }, cell)
			CardVisuals.Draw(cardFrame, card.Id, { Finish = EconomyConfig.FinishForRarity[card.Rarity] })
			local canTrade = summary.StarTokens >= cost
			local b = button(cell, "TradeButton", ("Trade %d tokens (own %d)"):format(cost, ownedCount(card.Id)),
				UDim2.new(0, 0, 0, 206), UDim2.new(1, 0, 0, 40), canTrade and GREEN or GREY)
			b.Activated:Connect(function()
				local ok, result = ask("ExchangeTokens", { CardId = card.Id })
				message = ok and ("You got " .. card.Name .. "!") or result
				render()
			end)
		end
	end
end

local function renderBreakDown()
	local ok, result = ask("GetExtras")
	local extras = ok and result.Extras or {}
	local total = ok and result.Shards or 0
	label(content, "BreakInfo", UDim2.new(), UDim2.new(1, 0, 0, 50),
		("You keep %d of each card (1 of each Commander and Celestial, and every Mythic). Extras beyond that can become Star Shards. %d Shards buy a pack."):format(
			EconomyConfig.KeepCopies.DeckCards, EconomyConfig.PackPriceShards), 18, { Font = Enum.Font.Gotham })
	local list = scroller(content, "ExtrasList", UDim2.new(0, 0, 0, 56), UDim2.new(0.6, 0, 1, -56))
	make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, list)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8) }, list)
	if #extras == 0 then
		label(list, "NoExtras", UDim2.new(), UDim2.new(1, 0, 0, 30), "No extra copies right now.", 18,
			{ Font = Enum.Font.Gotham })
	end
	for i, extra in ipairs(extras) do
		local card = CardDatabase.GetCard(extra.CardId)
		label(list, "Extra_" .. i, UDim2.new(), UDim2.new(1, -16, 0, 24),
			("%dx  %s (%s)  ->  %d Shards"):format(extra.Count, card.Name, CardVisuals.FinishNames[extra.Finish] or extra.Finish,
				extra.Shards), 16, {
				LayoutOrder = i,
				Font = Enum.Font.Gotham,
				TextXAlignment = Enum.TextXAlignment.Left,
			})
	end
	local b = button(content, "BreakDownAll", ("Break down all for %d Shards"):format(total),
		UDim2.new(0.63, 0, 0, 56), UDim2.new(0.35, 0, 0, 50), total > 0 and Color3.fromRGB(150, 80, 60) or GREY)
	b.Activated:Connect(function()
		local okBreak, gained = ask("BreakDownExtras")
		message = okBreak and ("+" .. gained .. " Star Shards") or gained
		render()
	end)
end

local function renderPlaymats()
	label(content, "MatInfo", UDim2.new(), UDim2.new(1, 0, 0, 30),
		"Your playmat goes on your half of the battle board, and your opponent sees it too.", 20,
		{ Font = Enum.Font.Gotham })
	local grid = scroller(content, "MatGrid", UDim2.new(0, 0, 0, 40), UDim2.new(1, 0, 1, -40))
	make("UIGridLayout", {
		CellSize = UDim2.new(0.31, 0, 0, 290),
		CellPadding = UDim2.new(0.02, 0, 0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 10) }, grid)
	for _, mat in ipairs(Playmats.List) do
		local owned = mat.Default == true or (summary.OwnedMats and summary.OwnedMats[mat.Id] == true)
		local equipped = summary.EquippedMat == mat.Id
		local box = make("Frame", { Name = "Mat_" .. mat.Id, LayoutOrder = mat.Order, BackgroundColor3 = PANEL }, grid)
		make("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
		if equipped then
			make("UIStroke", { Color = GOLD, Thickness = 3 }, box)
		end
		-- Preview, shaped like one half of the battle board
		local preview = make("Frame", {
			Name = "MatPreview",
			Position = UDim2.new(0, 8, 0, 8),
			Size = UDim2.new(1, -16, 0, 150),
		}, box)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, preview)
		Playmats.Draw(preview, mat.Id, 0)
		label(box, "MatName", UDim2.new(0, 10, 0, 164), UDim2.new(1, -20, 0, 28), mat.Name, 24)
		label(box, "MatDescription", UDim2.new(0, 10, 0, 194), UDim2.new(1, -20, 0, 34), mat.Description, 16,
			{ Font = Enum.Font.Gotham })
		local text, color
		if equipped then
			text, color = "On your table", GREY
		elseif owned then
			text, color = "Use this mat", ACCENT
		elseif mat.PriceCoins then
			text, color = ("Buy for %d coins"):format(mat.PriceCoins), GREEN
		else
			text, color = ("Comes with the %s starter"):format(mat.StarterDeck or "?"), GREY
		end
		local b = button(box, "MatButton", text, UDim2.new(0, 10, 1, -52), UDim2.new(1, -20, 0, 42), color)
		b.Activated:Connect(function()
			if equipped then
				return
			end
			if owned then
				local ok, result = ask("EquipMat", { MatId = mat.Id })
				message = ok and (result .. " is now on your table.") or result
			elseif mat.PriceCoins then
				local ok, result = ask("BuyMat", { MatId = mat.Id })
				message = ok and ("You got the " .. result .. " playmat! It's on your table now.") or result
			else
				tab = "Starters"
				message = ("Get the %s starter deck to unlock this playmat."):format(mat.StarterDeck or "?")
			end
			render()
		end)
	end
end

function render()
	clear(content)
	for key, b in pairs(tabButtons) do
		b.BackgroundColor3 = key == tab and SELECTED or ACCENT
	end
	messageLabel.Text = message
	if not summary then
		walletLabel.Text = "Loading..."
		return
	end
	walletLabel.Text = ("Coins %d   Shards %d   Tokens %d"):format(summary.Coins, summary.StarShards, summary.StarTokens)
	if tab == "Packs" then
		renderPacks()
	elseif tab == "Starters" then
		renderStarters()
	elseif tab == "Tokens" then
		renderTokens()
	elseif tab == "BreakDown" then
		renderBreakDown()
	elseif tab == "Playmats" then
		renderPlaymats()
	end
end

local function openShop()
	gui.Enabled = true
	if not oddsTable then
		local ok, result = ask("GetOdds")
		if ok then
			oddsTable = result
		end
	end
	render()
end

closeButton.Activated:Connect(function()
	gui.Enabled = false
	oddsPopup.Visible = false
end)

---------------------------------------------------------------------
-- Announcements (big pulls anywhere in the server)
---------------------------------------------------------------------
local toastGui = make("ScreenGui", { Name = "AnnouncementGui", ResetOnSpawn = false, DisplayOrder = 10,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player.PlayerGui)
local toast = label(toastGui, "Announcement", UDim2.new(0.2, 0, 0, 70), UDim2.new(0.6, 0, 0, 48), "", 28, {
	BackgroundTransparency = 0.2,
	BackgroundColor3 = Color3.fromRGB(20, 10, 40),
	Visible = false,
})
make("UICorner", { CornerRadius = UDim.new(0, 10) }, toast)
local toastCount = 0

local function showToast(text, tier)
	toastCount = toastCount + 1
	local mine = toastCount
	toast.Text = text
	toast.TextColor3 = tier == "Mythic" and CardVisuals.MythicColor or GOLD
	toast.Visible = true
	task.delay(tier == "Mythic" and 7 or 4, function()
		if toastCount == mine then
			toast.Visible = false
		end
	end)
end

---------------------------------------------------------------------
-- Welcome screen: brand-new players pick their free starter deck
---------------------------------------------------------------------
local welcome = make("Frame", {
	Name = "Welcome",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BG,
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 8,
}, toastGui)
label(welcome, "WelcomeTitle", UDim2.fromScale(0.1, 0.08), UDim2.fromScale(0.8, 0.1), "Welcome, Commander!", 40,
	{ ZIndex = 8 })
label(welcome, "WelcomeText", UDim2.fromScale(0.15, 0.18), UDim2.fromScale(0.7, 0.08),
	"Pick your first starter deck. It's free! You can get the others later at the Card Shop.", 22,
	{ ZIndex = 8, Font = Enum.Font.Gotham })
local welcomeRow = make("Frame", {
	Name = "WelcomeRow",
	Position = UDim2.fromScale(0.1, 0.3),
	Size = UDim2.fromScale(0.8, 0.55),
	BackgroundTransparency = 1,
	ZIndex = 8,
}, welcome)
local welcomeShown = false

local function showWelcome()
	welcomeShown = true
	clear(welcomeRow)
	local count = #CardDatabase.StarterDeckOrder
	for i, name in ipairs(CardDatabase.StarterDeckOrder) do
		local starter = CardDatabase.StarterDecks[name]
		local b = make("TextButton", {
			Name = "Welcome_" .. name,
			Text = "",
			Position = UDim2.new((i - 1) / count, 8, 0, 0),
			Size = UDim2.new(1 / count, -16, 1, 0),
			BackgroundColor3 = CardVisuals.FactionColors[name] or ACCENT,
			ZIndex = 8,
		}, welcomeRow)
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, b)
		label(b, "Name", UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.15), name, 34, { ZIndex = 9 })
		label(b, "Info", UDim2.fromScale(0.08, 0.25), UDim2.fromScale(0.84, 0.65),
			("%s\n\nCommander: %s\nCelestial: %s"):format(starter.Description,
				CardDatabase.GetCard(starter.Commander).Name, CardDatabase.GetCard(starter.Celestial).Name), 22,
			{ ZIndex = 9, Font = Enum.Font.Gotham })
		b.Activated:Connect(function()
			local ok, result = ask("ClaimStarter", { Deck = name })
			if ok then
				welcome.Visible = false
				showToast("The " .. name .. " starter deck is yours! Try it at the card table.", "Legendary")
			else
				label(welcome, "WelcomeError", UDim2.fromScale(0.2, 0.88), UDim2.fromScale(0.6, 0.05), result, 20,
					{ ZIndex = 8, TextColor3 = Color3.fromRGB(255, 140, 140) })
			end
		end)
	end
	welcome.Visible = true
end

---------------------------------------------------------------------
-- Events
---------------------------------------------------------------------
local function onSummary(newSummary)
	summary = newSummary
	if not welcomeShown and next(summary.OwnedStarters) == nil then
		showWelcome()
	end
	if gui.Enabled and not reveal.Visible then
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

shopEvent.OnClientEvent:Connect(function(payload)
	if payload.Kind == "OpenShop" then
		openShop()
	elseif payload.Kind == "Announcement" then
		showToast(payload.Text, payload.Tier)
	end
end)