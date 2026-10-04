--[[
	CollectionClient (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > CollectionClient

	The "My Cards" screen:
	  - Collection: every card, how many you own and in which finishes.
	    Click a card to see it large.
	  - Decks: your saved decks. Build a new one or edit, rename and delete.
	  - Deck builder: pick a Commander, then a Celestial that pairs with it,
	    then add cards (click to add, click in the list to remove). Name it and save.
	The server checks everything again when you save or play.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local UiAssets = require(ReplicatedStorage:WaitForChild("UiAssets"))
local UiTheme = require(ReplicatedStorage:WaitForChild("UiTheme"))
local SoundAssets = require(ReplicatedStorage:WaitForChild("SoundAssets"))
local remotes = ReplicatedStorage:WaitForChild("EconomyRemotes")
local walletUpdate = remotes:WaitForChild("WalletUpdate")
local request = remotes:WaitForChild("EconomyRequest")

local player = Players.LocalPlayer
local Rules = CardDatabase.Rules

local WHITE = Color3.fromRGB(255, 255, 255)
local BG = Color3.fromRGB(14, 11, 28)
local PANEL = Color3.fromRGB(24, 20, 42)
local ACCENT = Color3.fromRGB(70, 60, 120)
local GOOD = Color3.fromRGB(120, 220, 140)
local BAD = Color3.fromRGB(255, 130, 130)
local CARD_W, CARD_H = 130, 186

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

local function label(parent, props)
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextWrapped = true,
	}
	for key, value in pairs(props) do
		if key ~= "MaxText" then -- our own setting, not a Roblox property
			defaults[key] = value
		end
	end
	local l = make("TextLabel", defaults, parent)
	make("UITextSizeConstraint", { MaxTextSize = props.MaxText or 22, MinTextSize = 9 }, l)
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
	make("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 10 }, b)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
	}, b)
	return UiTheme.Button(b)
end

local function clear(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:GetAttribute("ThemePart") then -- (keeps the menu's border and plate)
			child:Destroy()
		end
	end
end

local function scroller(parent, name, position, size)
	return UiTheme.List(make("ScrollingFrame", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, parent))
end

local function cardGrid(frame)
	make("UIGridLayout", {
		CellSize = UDim2.fromOffset(CARD_W, CARD_H + 24),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, frame)
	make("UIPadding", {
		PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
	}, frame)
end

local TYPE_ORDER = { Commander = 1, Celestial = 2, Unit = 3, Spell = 4, Anomaly = 5 }
local FACTION_ORDER = { Solar = 1, Lunar = 2, Nebula = 3, Void = 4, Comet = 5, Neutral = 6 }

local function sortCards(ids)
	table.sort(ids, function(a, b)
		local ca, cb = CardDatabase.GetCard(a), CardDatabase.GetCard(b)
		if TYPE_ORDER[ca.Type] ~= TYPE_ORDER[cb.Type] then
			return TYPE_ORDER[ca.Type] < TYPE_ORDER[cb.Type]
		end
		if FACTION_ORDER[ca.Faction] ~= FACTION_ORDER[cb.Faction] then
			return FACTION_ORDER[ca.Faction] < FACTION_ORDER[cb.Faction]
		end
		if (ca.EnergyCost or 0) ~= (cb.EnergyCost or 0) then
			return (ca.EnergyCost or 0) < (cb.EnergyCost or 0)
		end
		return ca.Name < cb.Name
	end)
	return ids
end

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local summary = nil     -- latest wallet/collection summary from the server
local view = "Collection"
local filter = "All"
local showUnowned = true
local deckSortByStars = false -- deck list order in the editor
local STAR = utf8.char(0x2605)
local editor = nil      -- the deck being built: { Id, Name, Commander, Celestial, Cards = {}, Phase }
local confirmDelete = nil
local render -- defined at the bottom

local function owned(cardId)
	local total = 0
	if summary and summary.Collection[cardId] then
		for _, count in pairs(summary.Collection[cardId]) do
			total = total + count
		end
	end
	return total
end

local function finishesText(cardId)
	local entry = summary and summary.Collection[cardId]
	if not entry then
		return "Not owned"
	end
	local parts = {}
	for _, finish in ipairs({ "Base", "Holo", "Textured", "3D", "Mythic" }) do
		if entry[finish] and entry[finish] > 0 then
			table.insert(parts, ("%s x%d"):format(CardVisuals.FinishNames[finish], entry[finish]))
		end
	end
	return table.concat(parts, ", ")
end

local function bestFinish(cardId)
	local entry = summary and summary.Collection[cardId] or {}
	for _, finish in ipairs({ "Mythic", "3D", "Textured", "Holo", "Base" }) do
		if entry[finish] and entry[finish] > 0 then
			return finish
		end
	end
	return "Base"
end

-- The finishes you own of a card, plainest first
local function ownedFinishes(cardId)
	local entry = summary and summary.Collection[cardId] or {}
	local list = {}
	for _, finish in ipairs({ "Base", "Holo", "Textured", "3D", "Mythic" }) do
		if entry[finish] and entry[finish] > 0 then
			table.insert(list, finish)
		end
	end
	return list
end

local FINISH_COLORS = {
	Base = Color3.fromRGB(70, 70, 85),
	Holo = Color3.fromRGB(60, 130, 200),
	Textured = Color3.fromRGB(40, 150, 140),
	["3D"] = Color3.fromRGB(190, 140, 40),
	Mythic = Color3.fromRGB(200, 60, 160),
}

---------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------
local openGui = make("ScreenGui", { Name = "CardsButtonGui", ResetOnSpawn = false, DisplayOrder = 1,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling },
player:WaitForChild("PlayerGui"))
local openButton = button(openGui, "OpenCollection", "My Cards", UDim2.new(0, 10, 0.45, 0), UDim2.fromOffset(120, 44))

local gui = make("ScreenGui", {
	Name = "CollectionGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	DisplayOrder = 3,
	Enabled = false,
}, player.PlayerGui)
local root = make("Frame", { Name = "Root", Size = UDim2.fromScale(1, 1), BackgroundColor3 = BG, BorderSizePixel = 0 }, gui)
UiTheme.Backdrop(root, { Seed = 21 })

local collectionTab = button(root, "CollectionTab", "Collection", UDim2.new(0.02, 0, 0, 12), UDim2.new(0.14, 0, 0, 40))
local decksTab = button(root, "DecksTab", "Decks", UDim2.new(0.17, 0, 0, 12), UDim2.new(0.12, 0, 0, 40))
local closeButton = button(root, "CloseCollection", "Close", UDim2.new(0.88, 0, 0, 12), UDim2.new(0.1, 0, 0, 40),
	Color3.fromRGB(80, 80, 90))
local headerLabel = label(root, {
	Name = "Header",
	Position = UDim2.new(0.31, 0, 0, 12),
	Size = UDim2.new(0.55, 0, 0, 40),
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})

local content = make("Frame", {
	Name = "Content",
	Position = UDim2.new(0.02, 0, 0, 64),
	Size = UDim2.new(0.96, 0, 1, -76),
	BackgroundTransparency = 1,
}, root)

-- Large card view
local inspect = make("TextButton", {
	Name = "Inspect",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.2,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 10,
}, gui)

local function showInspect(cardId)
	clear(inspect)
	local big = make("Frame", {
		Name = "BigCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.3, 0.46),
		Size = UDim2.fromScale(0.45, 0.75),
		ZIndex = 10,
	}, inspect)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_W / CARD_H }, big)
	CardVisuals.Draw(big, cardId, { Finish = bestFinish(cardId) })
	CardVisuals.MakeHandheld(big) -- hold the mouse on it to move the light around
	for _, child in ipairs(big:GetDescendants()) do
		if child:IsA("TextLabel") then
			child.ZIndex = 11
		end
	end
	-- what the card is and what its keywords mean
	CardVisuals.DrawInfoPanel(inspect, cardId, {
		Position = UDim2.fromScale(0.55, 0.09),
		Size = UDim2.fromScale(0.41, 0.74),
		ZIndex = 11,
		Owned = "You own: " .. finishesText(cardId),
	})
	label(inspect, {
		Name = "InspectInfo",
		Position = UDim2.fromScale(0.2, 0.87),
		Size = UDim2.fromScale(0.6, 0.05),
		ZIndex = 11,
		Text = "Hold the card to move the light  |  tap anywhere else to close",
	})
	inspect.Visible = true
end
inspect.Activated:Connect(function()
	inspect.Visible = false
end)

-- A card with a caption underneath, inside a grid
local function cardCell(parent, cardId, order, caption, options)
	local cell = make("Frame", {
		Name = "Cell_" .. cardId,
		LayoutOrder = order,
		BackgroundTransparency = 1,
	}, parent)
	local cardButton = make("TextButton", {
		Name = "Card",
		Text = "",
		Size = UDim2.new(1, 0, 0, CARD_H),
		AutoButtonColor = true,
	}, cell)
	CardVisuals.Draw(cardButton, cardId, options)
	label(cell, {
		Name = "Caption",
		Position = UDim2.new(0, 0, 0, CARD_H + 2),
		Size = UDim2.new(1, 0, 0, 20),
		Font = Enum.Font.Gotham,
		MaxText = 14,
		Text = caption,
	})
	return cardButton
end

---------------------------------------------------------------------
-- Collection view
---------------------------------------------------------------------
local FILTERS = { "All", "Solar", "Lunar", "Nebula", "Void", "Comet", "Neutral", "Leaders" }

local function renderCollection()
	local allIds, ownedCount, total = {}, 0, 0
	for _, card in ipairs(CardDatabase.GetAllCards()) do
		-- switched-off card types (Anomalies) can't be collected right now
		local collectable = card.Type ~= "Anomaly" or CardDatabase.IsMainDeckType(card.Type)
		if collectable then
			total = total + 1
		end
		if collectable and owned(card.Id) > 0 then
			ownedCount = ownedCount + 1
		end
		local pass = collectable and (filter == "All"
			or (filter == "Leaders" and (card.Type == "Commander" or card.Type == "Celestial"))
			or (filter ~= "Leaders" and card.Faction == filter and card.Type ~= "Commander" and card.Type ~= "Celestial"))
		if pass and (showUnowned or owned(card.Id) > 0) then
			table.insert(allIds, card.Id)
		end
	end
	headerLabel.Text = ("Collection: %d / %d cards found (%d%%)"):format(ownedCount, total,
		total > 0 and math.floor(ownedCount / total * 100) or 0)

	for i, name in ipairs(FILTERS) do
		local b = button(content, "Filter_" .. name, name, UDim2.fromOffset((i - 1) * 92, 0), UDim2.fromOffset(86, 34),
			filter == name and Color3.fromRGB(120, 100, 200) or ACCENT)
		if UiAssets.Emblems[name] then
			make("UIPadding", { PaddingLeft = UDim.new(0, 24) }, b)
			UiAssets.Icon(UiAssets.Emblems[name], UDim2.fromOffset(24, 24), UDim2.new(0, -21, 0.5, -12), b, b.ZIndex + 1)
		end
		b.Activated:Connect(function()
			filter = name
			render()
		end)
	end
	local toggle = button(content, "ToggleUnowned", showUnowned and "Showing unowned" or "Hiding unowned",
		UDim2.fromOffset(#FILTERS * 92 + 12, 0), UDim2.fromOffset(160, 34), Color3.fromRGB(60, 60, 80))
	toggle.Activated:Connect(function()
		showUnowned = not showUnowned
		render()
	end)

	-- Studio only: get every finish of every card, to test how they look
	if game:GetService("RunService"):IsStudio() then
		local dev = button(content, "DevAllFinishes", "Studio: get all finishes",
			UDim2.fromOffset(#FILTERS * 108 + 184, 0), UDim2.fromOffset(200, 34), Color3.fromRGB(150, 90, 40))
		dev.Activated:Connect(function()
			local ok, message = request:InvokeServer("DevGrantAllFinishes", {})
			headerLabel.Text = message or (ok and "Done." or "Couldn't do that.")
		end)
	end

	local grid = scroller(content, "CollectionGrid", UDim2.fromOffset(0, 44), UDim2.new(1, 0, 1, -44))
	cardGrid(grid)
	for i, cardId in ipairs(sortCards(allIds)) do
		local count = owned(cardId)
		local b = cardCell(grid, cardId, i, count > 0 and ("x%d  %s"):format(count, finishesText(cardId)) or "Not owned",
			{ Dim = count == 0, Finish = bestFinish(cardId) })
		b.Activated:Connect(function()
			showInspect(cardId)
		end)
	end
end

---------------------------------------------------------------------
-- Decks list
---------------------------------------------------------------------
local function startEditor(deck)
	pcall(function() ReplicatedStorage.AnalyticsRemotes.Track:FireServer("deck_editor_opened", deck and "edit" or "new") end) -- launch analytics
	if deck then
		local cards = {}
		for i, id in ipairs(deck.Cards) do
			cards[i] = id
		end
		local finishes = {}
		for cardId, finish in pairs(deck.Finishes or {}) do
			finishes[cardId] = finish
		end
		editor = { Id = deck.Id, Name = deck.Name, Commander = deck.Commander, Celestial = deck.Celestial,
			Cards = cards, Finishes = finishes, Phase = "Cards", Format = CardDatabase.FormatOf(deck.Format) }
	else
		editor = { Name = "", Cards = {}, Finishes = {}, Phase = "Commander", Format = CardDatabase.DefaultDeckFormat }
	end
	editor.Message = ""
	view = "Editor"
	render()
end

local function renderDecks()
	local decks = summary and summary.Decks or {}
	local maxDecks = summary and summary.MaxDecks or 12
	headerLabel.Text = ("Decks: %d / %d saved"):format(#decks, maxDecks)
	local newButton = button(content, "NewDeck", "+ New deck", UDim2.fromOffset(0, 0), UDim2.fromOffset(160, 38),
		Color3.fromRGB(60, 140, 90))
	newButton.Activated:Connect(function()
		if #decks >= maxDecks then
			headerLabel.Text = "You have the most decks allowed. Delete one first."
			return
		end
		startEditor(nil)
	end)

	local list = scroller(content, "DeckList", UDim2.fromOffset(0, 48), UDim2.new(1, 0, 1, -48))
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingRight = UDim.new(0, 16) }, list)
	if #decks == 0 then
		label(list, {
			Name = "NoDecks",
			Size = UDim2.new(1, 0, 0, 60),
			Font = Enum.Font.Gotham,
			Text = "No decks yet. Press \"+ New deck\" to build one from your cards.",
		})
	end
	for i, deck in ipairs(decks) do
		local commander = CardDatabase.GetCard(deck.Commander)
		local row = make("Frame", {
			Name = "Deck_" .. deck.Id,
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 72),
			BackgroundColor3 = CardVisuals.FactionColors[commander and commander.Faction or "Neutral"],
			BorderSizePixel = 0,
		}, list)
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, row)
		UiTheme.Panel(row, { Color = UiTheme.Tinted(row.BackgroundColor3, 0.55), Thickness = 12 })
		label(row, {
			Name = "DeckName",
			Position = UDim2.new(0, 12, 0, 6),
			Size = UDim2.new(0.5, 0, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = deck.Name,
		})
		local celestial = CardDatabase.GetCard(deck.Celestial)
		label(row, {
			Name = "DeckInfo",
			Position = UDim2.new(0, 12, 0, 38),
			Size = UDim2.new(0.62, 0, 0, 26),
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = deck.Legal and GOOD or BAD,
			MaxText = 16,
			Text = ("%s  |  %s + %s  |  %d/%d cards  |  %s"):format(CardDatabase.FormatOf(deck.Format),
				commander and commander.Name or "?",
				celestial and celestial.Name or "?", #deck.Cards, Rules.DeckSize,
				deck.Legal and "Ready to play" or (deck.Problem or "Not ready")),
		})
		local edit = button(row, "EditDeck", "Edit", UDim2.new(1, -220, 0.5, -18), UDim2.fromOffset(100, 36))
		edit.Activated:Connect(function()
			startEditor(deck)
		end)
		local deleting = confirmDelete == deck.Id
		local del = button(row, "DeleteDeck", deleting and "Sure?" or "Delete", UDim2.new(1, -110, 0.5, -18),
			UDim2.fromOffset(100, 36), deleting and Color3.fromRGB(200, 60, 60) or Color3.fromRGB(90, 60, 60))
		del.Activated:Connect(function()
			if confirmDelete ~= deck.Id then
				confirmDelete = deck.Id
				render()
				return
			end
			confirmDelete = nil
			local ok, message = request:InvokeServer("DeleteDeck", { Id = deck.Id })
			if not ok then
				headerLabel.Text = message
			end
		end)
	end
end

---------------------------------------------------------------------
-- Deck builder
---------------------------------------------------------------------
local function deckCounts()
	local counts = {}
	for _, id in ipairs(editor.Cards) do
		counts[id] = (counts[id] or 0) + 1
	end
	return counts
end

-- The finish a card shows in this deck: your pick if you still own it, else your best
local function deckFinish(cardId)
	local pick = editor.Finishes[cardId]
	if pick then
		for _, finish in ipairs(ownedFinishes(cardId)) do
			if finish == pick then
				return pick
			end
		end
	end
	return bestFinish(cardId)
end

-- Next owned finish for a card (wraps around)
local function cycleFinish(cardId)
	local options = ownedFinishes(cardId)
	if #options <= 1 then
		return false
	end
	local current = deckFinish(cardId)
	local nextIndex = 1
	for i, finish in ipairs(options) do
		if finish == current then
			nextIndex = i % #options + 1
		end
	end
	editor.Finishes[cardId] = options[nextIndex]
	return true
end

local function eligible(card)
	local commander = CardDatabase.GetCard(editor.Commander)
	if not CardDatabase.IsMainDeckType(card.Type) then
		return false
	end
	if card.Faction ~= commander.Faction and card.Faction ~= "Neutral" then
		return false
	end
	if card.CommanderOnly and card.CommanderOnly ~= editor.Commander then
		return false
	end
	return true
end

local function pickPhase(kind)
	local isCommander = kind == "Commander"
	headerLabel.Text = isCommander and "New deck: pick your Commander"
		or ("Pick a Celestial partner for " .. CardDatabase.GetCard(editor.Commander).Name)
	local back = button(content, "EditorBack", "Back", UDim2.fromOffset(0, 0), UDim2.fromOffset(100, 34),
		Color3.fromRGB(80, 80, 90))
	back.Activated:Connect(function()
		if not isCommander then
			editor.Phase = "Commander"
		elseif editor.Commander and editor.Celestial then
			editor.Phase = "Cards" -- came here from the builder; go back to it
		else
			editor = nil
			view = "Decks"
		end
		render()
	end)
	local grid = scroller(content, "PickGrid", UDim2.fromOffset(0, 44), UDim2.new(1, 0, 1, -44))
	cardGrid(grid)
	local ids = {}
	local commander = editor.Commander and CardDatabase.GetCard(editor.Commander)
	for _, card in ipairs(CardDatabase.GetAllCards()) do
		if card.Type == kind and owned(card.Id) > 0 then
			local fits = true
			if not isCommander then
				fits = false
				for _, faction in ipairs(card.PairsWith) do
					if faction == commander.Faction then
						fits = true
					end
				end
			end
			if fits then
				table.insert(ids, card.Id)
			end
		end
	end
	if #ids == 0 then
		label(grid, {
			Name = "NothingToPick",
			Size = UDim2.new(1, 0, 0, 60),
			Font = Enum.Font.Gotham,
			Text = isCommander and "You don't own any Commanders yet. Open packs or get a starter deck."
				or ("You don't own a Celestial that pairs with " .. commander.Faction .. " yet."),
		})
	end
	for i, cardId in ipairs(sortCards(ids)) do
		local b = cardCell(grid, cardId, i, editor[kind] == cardId and "Current pick" or "Click to pick",
			{ Finish = deckFinish(cardId) })
		b.Name = "Pick_" .. cardId
		b.Activated:Connect(function()
			if isCommander then
				if editor.Commander ~= cardId then
					editor.Commander = cardId
					editor.Celestial = nil
					-- drop cards the new Commander can't use
					local keep = {}
					for _, id in ipairs(editor.Cards) do
						if eligible(CardDatabase.GetCard(id)) then
							table.insert(keep, id)
						end
					end
					editor.Cards = keep
				end
				editor.Phase = "Celestial"
			else
				editor.Celestial = cardId
				editor.Phase = "Cards"
			end
			render()
		end)
	end
end

local function renderEditor()
	if editor.Phase == "Commander" or editor.Phase == "Celestial" then
		pickPhase(editor.Phase)
		return
	end

	local commander = CardDatabase.GetCard(editor.Commander)
	local celestial = CardDatabase.GetCard(editor.Celestial)
	local counts = deckCounts()
	local legal, problems, stars = CardDatabase.ValidateDeck(editor.Commander, editor.Celestial, editor.Cards, editor.Format)
	headerLabel.Text = ("Building: %s + %s"):format(commander.Name, celestial.Name)

	-- Top row: name, counts, buttons
	local nameBox = make("TextBox", {
		Name = "DeckNameBox",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0.24, 0, 0, 36),
		BackgroundColor3 = PANEL,
		TextColor3 = WHITE,
		PlaceholderText = "Name your deck",
		PlaceholderColor3 = Color3.fromRGB(150, 140, 180),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		ClearTextOnFocus = false,
		Text = editor.Name,
	}, content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, nameBox)
	UiTheme.List(nameBox)
	nameBox.FocusLost:Connect(function()
		editor.Name = nameBox.Text
	end)

	label(content, {
		Name = "CardCount",
		Position = UDim2.new(0.25, 0, 0, 0),
		Size = UDim2.new(0.12, 0, 0, 36),
		TextColor3 = #editor.Cards == Rules.DeckSize and GOOD or WHITE,
		Text = ("Cards %d/%d"):format(#editor.Cards, Rules.DeckSize),
	})

	-- Star Cap meter
	local meter = make("Frame", {
		Name = "StarMeter",
		Position = UDim2.new(0.38, 0, 0, 4),
		Size = UDim2.new(0.2, 0, 0, 28),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
	}, content)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, meter)
	UiTheme.List(meter)
	local starCap = CardDatabase.DeckFormats[CardDatabase.FormatOf(editor.Format)].StarCap
	local over = starCap ~= nil and stars > starCap
	local fill = make("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(starCap and math.min(1, stars / starCap) or 1, 1),
		BackgroundColor3 = over and Color3.fromRGB(210, 60, 60) or Color3.fromRGB(230, 180, 60),
		BorderSizePixel = 0,
	}, meter)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, fill)
	label(meter, {
		Name = "StarText",
		Size = UDim2.fromScale(1, 1),
		Text = starCap and ("Stars %d / %d"):format(stars, starCap) or ("Stars %d (no limit)"):format(stars),
	})
	if not starCap then
		fill.BackgroundColor3 = Color3.fromRGB(80, 150, 200)
	end

	local changeLeaders = button(content, "ChangeLeaders", "Change Commander", UDim2.new(0.59, 0, 0, 0),
		UDim2.new(0.14, 0, 0, 36), Color3.fromRGB(60, 60, 90))
	changeLeaders.Activated:Connect(function()
		editor.Name = nameBox.Text
		editor.Phase = "Commander"
		render()
	end)
	local save = button(content, "SaveDeck", "Save", UDim2.new(0.74, 0, 0, 0), UDim2.new(0.12, 0, 0, 36),
		Color3.fromRGB(60, 140, 90))
	local cancel = button(content, "CancelDeck", "Cancel", UDim2.new(0.87, 0, 0, 0), UDim2.new(0.13, 0, 0, 36),
		Color3.fromRGB(80, 80, 90))

	-- Format: Zenith (star cap) or Open (no limit); click to switch
	local isOpen = CardDatabase.FormatOf(editor.Format) == "Open"
	local formatButton = button(content, "DeckFormatToggle",
		isOpen and "Format: Open" or "Format: Zenith",
		UDim2.new(0.8, 0, 0, 38), UDim2.new(0.2, 0, 0, 26),
		isOpen and Color3.fromRGB(50, 110, 160) or Color3.fromRGB(150, 110, 30))
	formatButton.Activated:Connect(function()
		editor.Name = nameBox.Text
		editor.Format = isOpen and "Zenith" or "Open"
		editor.Message = CardDatabase.DeckFormats[editor.Format].Description
		SoundAssets.Play("MenuOpen")
		render()
	end)

	local status = label(content, {
		Name = "EditorStatus",
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(0.79, 0, 0, 22),
		Font = Enum.Font.Gotham,
		MaxText = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = editor.Message ~= "" and Color3.fromRGB(255, 230, 120) or (legal and GOOD or BAD),
		Text = editor.Message ~= "" and editor.Message
			or (legal and "Ready to play!" or ("To play this deck: " .. (problems[1] or ""))),
	})

	-- Left: cards you can add
	local pool = scroller(content, "CardPool", UDim2.fromOffset(0, 68), UDim2.new(0.64, 0, 1, -68))
	cardGrid(pool)
	local ids = {}
	for _, card in ipairs(CardDatabase.GetAllCards()) do
		if eligible(card) and owned(card.Id) > 0 then
			table.insert(ids, card.Id)
		end
	end
	if #ids == 0 then
		label(pool, { Name = "NoCards", Size = UDim2.new(1, 0, 0, 60), Font = Enum.Font.Gotham,
			Text = "You don't own any " .. commander.Faction .. " or Neutral cards yet." })
	end
	for i, cardId in ipairs(sortCards(ids)) do
		local card = CardDatabase.GetCard(cardId)
		local inDeck = counts[cardId] or 0
		local maxCopies = CardDatabase.MaxCopiesFor(card)
		local limit = math.min(maxCopies, owned(cardId))
		local caption = ("%d/%d in deck  |  %d stars"):format(inDeck, limit, card.StarCost)
		local b = cardCell(pool, cardId, i, caption, { Dim = inDeck >= limit, Finish = deckFinish(cardId) })
		b.Name = "Add_" .. cardId
		b.Activated:Connect(function()
			editor.Name = nameBox.Text
			if #editor.Cards >= Rules.DeckSize then
				editor.Message = ("The deck is full (%d cards)."):format(Rules.DeckSize)
			elseif inDeck >= limit then
				editor.Message = inDeck >= maxCopies
					and (maxCopies == 1 and (card.Name .. " is Legendary: only 1 per deck.")
						or ("Max %d copies of a card."):format(maxCopies))
					or ("You only own %d %s."):format(owned(cardId), card.Name)
			else
				table.insert(editor.Cards, cardId)
				editor.Message = ""
			end
			render()
		end)
	end

	-- Right: the deck list (click to remove one)
	local listFrame = scroller(content, "DeckCards", UDim2.new(0.66, 0, 0, 68), UDim2.new(0.34, 0, 1, -68))
	make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listFrame)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 6), PaddingRight = UDim.new(0, 14) }, listFrame)
	local unique = {}
	for id in pairs(counts) do
		table.insert(unique, id)
	end
	sortCards(unique)
	if deckSortByStars then
		-- most stars first (then the usual order), to find what to cut when over the Star Cap
		local rank = {}
		for i, id in ipairs(unique) do
			rank[id] = i
		end
		table.sort(unique, function(a, b)
			local sa, sb = CardDatabase.GetCard(a).StarCost, CardDatabase.GetCard(b).StarCost
			if sa ~= sb then
				return sa > sb
			end
			return rank[a] < rank[b]
		end)
	end
	local sortButton = button(listFrame, "SortDeckList", deckSortByStars and "Sorted by stars (most first)  >"
		or "Sorted by energy  >", UDim2.new(), UDim2.new(1, 0, 0, 28), Color3.fromRGB(60, 60, 90))
	sortButton.LayoutOrder = -20
	sortButton.Activated:Connect(function()
		editor.Name = nameBox.Text
		deckSortByStars = not deckSortByStars
		render()
	end)
	-- A finish button: shows the finish this card uses in the deck; click to switch
	-- to the next finish you own
	local function finishButton(parent, cardId, position, size)
		local finish = deckFinish(cardId)
		local options = ownedFinishes(cardId)
		local b = button(parent, "Finish_" .. cardId,
			CardVisuals.FinishNames[finish] .. (#options > 1 and "  >" or ""),
			position, size, FINISH_COLORS[finish])
		b.Activated:Connect(function()
			editor.Name = nameBox.Text
			if cycleFinish(cardId) then
				editor.Message = ("%s will show as %s."):format(CardDatabase.GetCard(cardId).Name,
					CardVisuals.FinishNames[deckFinish(cardId)])
			else
				editor.Message = ("You only own the %s version of %s."):format(CardVisuals.FinishNames[finish],
					CardDatabase.GetCard(cardId).Name)
			end
			render()
		end)
		return b
	end

	-- Commander and Celestial (pick their finish here; change them with "Change Commander")
	for i, leader in ipairs({ { "Commander", editor.Commander }, { "Celestial", editor.Celestial } }) do
		local card = CardDatabase.GetCard(leader[2])
		local row = make("Frame", { Name = "Leader_" .. leader[1], LayoutOrder = i - 10, Size = UDim2.new(1, 0, 0, 34),
			BackgroundColor3 = CardVisuals.FactionColors[card.Faction], BorderSizePixel = 0 }, listFrame)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, row)
		UiTheme.List(row, { Color = UiTheme.Tinted(row.BackgroundColor3, 0.6) })
		label(row, { Name = "LeaderName", Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(0.66, -8, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Left, MaxText = 15, Text = leader[1] .. ": " .. card.Name })
		finishButton(row, leader[2], UDim2.new(0.68, 0, 0, 2), UDim2.new(0.32, 0, 1, -4))
	end

	if #unique == 0 then
		label(listFrame, { Name = "EmptyDeck", Size = UDim2.new(1, 0, 0, 50), Font = Enum.Font.Gotham,
			Text = "Click cards on the left to add them." })
	end
	for i, cardId in ipairs(unique) do
		local card = CardDatabase.GetCard(cardId)
		local row = make("Frame", { Name = "Row_" .. cardId, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 34),
			BackgroundTransparency = 1 }, listFrame)
		local remove = button(row, "Remove_" .. cardId,
			("%dx  %s  (%d energy)"):format(counts[cardId], card.Name, card.EnergyCost),
			UDim2.new(0, 0, 0, 0), UDim2.new(0.5, 0, 1, 0),
			CardVisuals.FactionColors[card.Faction])
		remove.TextXAlignment = Enum.TextXAlignment.Left
		-- star cost (and the total for all copies), so it's easy to see what to cut
		local starText = string.rep(STAR, card.StarCost)
		if counts[cardId] > 1 then
			starText = starText .. ("  =%d"):format(card.StarCost * counts[cardId])
		end
		label(row, { Name = "Stars_" .. cardId, Position = UDim2.new(0.51, 0, 0, 0), Size = UDim2.new(0.16, 0, 1, 0),
			MaxText = 15, TextColor3 = Color3.fromRGB(240, 190, 60), Text = starText })
		remove.Activated:Connect(function()
			editor.Name = nameBox.Text
			for index = #editor.Cards, 1, -1 do
				if editor.Cards[index] == cardId then
					table.remove(editor.Cards, index)
					break
				end
			end
			editor.Message = ""
			render()
		end)
		finishButton(row, cardId, UDim2.new(0.68, 0, 0, 0), UDim2.new(0.32, 0, 1, 0))
	end

	save.Activated:Connect(function()
		editor.Name = nameBox.Text
		local ok, result = request:InvokeServer("SaveDeck", {
			Id = editor.Id,
			Name = editor.Name,
			Format = editor.Format,
			Commander = editor.Commander,
			Celestial = editor.Celestial,
			Cards = editor.Cards,
			Finishes = editor.Finishes,
		})
		SoundAssets.Play(ok and "DeckSave" or "NotEnough")
		if ok then
			editor = nil
			view = "Decks"
			render()
			headerLabel.Text = legal and "Deck saved. It's ready to play!" or "Deck saved. Finish it to play it."
		else
			editor.Message = result
			render()
		end
	end)
	cancel.Activated:Connect(function()
		editor = nil
		view = "Decks"
		render()
	end)
end

---------------------------------------------------------------------
-- Drawing the current view
---------------------------------------------------------------------
function render()
	clear(content)
	collectionTab.BackgroundColor3 = view == "Collection" and Color3.fromRGB(120, 100, 200) or ACCENT
	decksTab.BackgroundColor3 = view ~= "Collection" and Color3.fromRGB(120, 100, 200) or ACCENT
	if not summary then
		headerLabel.Text = "Loading your cards..."
		return
	end
	if view == "Collection" then
		renderCollection()
	elseif view == "Decks" then
		renderDecks()
	elseif view == "Editor" and editor then
		renderEditor()
	end
end

collectionTab.Activated:Connect(function()
	if view == "Editor" then
		return -- finish or cancel the deck first
	end
	view = "Collection"
	render()
end)
decksTab.Activated:Connect(function()
	if view == "Editor" then
		return
	end
	view = "Decks"
	render()
end)
-- Other screens (the match summary) can open this: CollectionGui.OpenCollection:Fire()
make("BindableEvent", { Name = "OpenCollection" }, gui).Event:Connect(function()
	SoundAssets.Play("MenuOpen")
	gui.Enabled = true
	render()
end)
openButton.Activated:Connect(function()
	SoundAssets.Play("MenuOpen")
	gui.Enabled = true
	pcall(function() ReplicatedStorage.AnalyticsRemotes.Track:FireServer("collection_opened") end) -- launch analytics
	render()
end)
closeButton.Activated:Connect(function()
	SoundAssets.Play("MenuClose")
	gui.Enabled = false
	inspect.Visible = false
end)

walletUpdate.OnClientEvent:Connect(function(newSummary)
	summary = newSummary
	if gui.Enabled and view ~= "Editor" then
		render()
	end
end)

task.spawn(function()
	local ok, result = request:InvokeServer("GetSummary", {})
	if ok and result then
		summary = result
	end
end)

-- Hide the button during battles
task.spawn(function()
	local battleGui = player.PlayerGui:WaitForChild("BattleGui", 10)
	if battleGui then
		openButton.Visible = not battleGui.Enabled
		battleGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			openButton.Visible = not battleGui.Enabled
			if battleGui.Enabled then
				gui.Enabled = false
			end
		end)
	end
end)