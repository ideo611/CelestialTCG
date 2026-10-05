--[[
	Rulebook (ModuleScript)
	Location: ReplicatedStorage > Rulebook

	The in-game rulebook: everything about the game, short and to the point,
	in a few pages. Opened from the "How to play" button (GuideClient).

	  Rulebook.Sections          { { Title, Text } } -- Text uses RichText (<b>)
	  Rulebook.Open(onReplay)    shows the rulebook window (client only).
	                             onReplay (optional) = what "Replay tutorial" does.
	  Rulebook.Close()

	The numbers come straight from CardDatabase.Rules and EconomyConfig, so
	the rulebook stays right when the game's numbers change.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))

local Rulebook = {}

local R = CardDatabase.Rules
local E = EconomyConfig
local REWARDS = E.MatchRewards

local function lines(list)
	return table.concat(list, "\n")
end

local function chance(poolName)
	for _, slot in ipairs(E.PackSlots) do
		for _, outcome in ipairs(slot.Outcomes) do
			if outcome.Pool == poolName then
				return outcome.Chance
			end
		end
	end
	return 0
end

local function packSize()
	local n = 0
	for _, slot in ipairs(E.PackSlots) do
		n = n + slot.Count
	end
	return n
end

local function giftLine()
	local gift = E.LaunchGift
	if gift and gift.Ends and os.time() < gift.Ends then
		return ("• <b>Launch gift:</b> a free Booster Box of your starter's faction (for a limited time).")
	end
	return nil
end

local function collecting()
	local list = {
		("• <b>Packs (%d cards):</b> Commons, a Rare slot and a <b>Star Slot</b> (Rare, Epic, Legendary, Commander or Celestial, or a <b>%s%% Mythic</b> full-art)."):format(packSize(), tostring(chance("Mythic"))),
		"• Any card can roll a shiny finish: <b>Holo</b>, <b>Textured</b> or <b>3D</b>.",
		"• <b>Boosters:</b> Celestial (every faction) or one faction. Same odds in every pack.",
		("• <b>Coins:</b> wins pay %d, losses %d (up to %d a day). A pack costs %d coins, %d coin packs a day."):format(
			REWARDS.PvPWin, REWARDS.PvPLoss, E.DailyCoinCap, E.PackPriceCoins, E.DailyCoinPacks),
		"• <b>Pack Tickets:</b> open any pack, no daily limit, never expire. Free for your <b>first win each day</b> and for <b>finishing the tutorial</b>.",
		("• <b>Booster Box:</b> %d packs of one booster plus a shiny Commander or Celestial topper."):format(E.Box.Packs),
		("• <b>Star Tokens:</b> %d per pack. Trade %d for any Commander or Celestial."):format(E.TokensPerPack, E.TokenExchangeCost),
		("• <b>Star Shards:</b> break down extra copies (beyond a playset). %d shards = 1 pack."):format(E.PackPriceShards),
		("• <b>Singles:</b> buy the exact card you want with coins. <b>Starter decks:</b> first one free, then %d coins."):format(E.StarterDeckPriceCoins),
	}
	local referral = E.Referral
	if referral then
		table.insert(list, ("• <b>Invite friends:</b> when a new friend you invite finishes their first match vs the bot, you both get %d Pack Tickets (up to %d friends)."):format(
			referral.Tickets, referral.MaxFriends))
	end
	local gift = giftLine()
	if gift then
		table.insert(list, gift)
	end
	return lines(list)
end

Rulebook.Sections = {
	{
		Title = "Goal",
		Text = lines({
			("Take the enemy Commander from <b>%d HP to 0</b>. That's it."):format(R.CommanderHP),
			"",
			"Matches are best of 1, 3 or 5. Practice against the bot on <b>Normal</b> or <b>Hard</b>.",
		}),
	},
	{
		Title = "Your deck",
		Text = lines({
			"• <b>1 Commander</b>: picks your faction (Solar, Lunar, Nebula, Void or Comet) and has a once-per-turn ability.",
			"• <b>1 Celestial</b>: a giant unit that pairs with your Commander's faction. It waits in your Star Gate, not your deck.",
			("• <b>Exactly %d cards</b>: units and spells of your faction or Neutral."):format(R.DeckSize),
			("• <b>Max %d copies</b> of a card. Legendary units and spells: <b>%d copy</b>."):format(R.MaxCopies, R.LegendaryMaxCopies),
			("• <b>Zenith</b> format: every card costs stars, the deck must fit <b>%d stars</b>. <b>Open</b> format: no star cap."):format(R.StarCap),
		}),
	},
	{
		Title = "The board",
		Text = lines({
			("Each side has <b>%d lanes</b>, a <b>Commander</b> and a <b>Star Gate</b> (where your Celestial waits)."):format(R.Lanes),
			"",
			"Lanes face each other: your lane 1 fights their lane 1, and so on.",
		}),
	},
	{
		Title = "Setting up",
		Text = lines({
			("1. Shuffle and draw <b>%d cards</b>."):format(R.StartingHand),
			"2. <b>Mulligan:</b> send back any cards you don't want and draw new ones.",
			"3. The first player <b>skips their first draw</b>.",
			("4. The second player gets <b>+%d card</b> and a one-time <b>Spark</b> (+1 energy on any turn)."):format(R.SecondPlayerBonusCards),
		}),
	},
	{
		Title = "Your turn",
		Text = lines({
			("1. <b>Energy:</b> your max goes up by 1 (starts at %d, caps at %d) and refills."):format(R.StartingEnergy, R.MaxEnergy),
			"2. <b>Draw 1 card</b> (empty deck: no draw).",
			"3. In any order:",
			"   • Play <b>units</b> into your empty lanes.",
			"   • Cast <b>spells</b>.",
			"   • Use your <b>Commander's ability</b> (once per turn).",
			("   • <b>Summon your Celestial</b> into an empty lane. If it's destroyed it returns to the Star Gate, and each re-summon costs <b>+%d energy</b>."):format(R.CelestialTax),
			"4. <b>End Turn</b>: combat happens.",
			"",
			"Online: <b>60 seconds</b> a turn. Time out 3 turns in a row and you forfeit.",
		}),
	},
	{
		Title = "Combat",
		Text = lines({
			"When you press End Turn, each of your units <b>attacks the lane straight across</b>:",
			"• <b>Unit across?</b> Both deal their Power to each other.",
			"• <b>Lane empty?</b> The hit goes to the enemy <b>Commander</b>.",
			"• A unit at <b>0 HP</b> is destroyed and goes to the graveyard.",
			"• New units <b>wait a turn</b> before attacking (unless they have Rush).",
		}),
	},
	{
		Title = "Keywords",
		Text = lines({
			"<b>Rush</b>: can attack the turn it's played.",
			"<b>Shield</b>: blocks the next hit completely, then breaks.",
			"<b>Ignite X</b>: when played, deals X to the enemy unit across.",
			"<b>Regen X</b>: heals X at the end of each of your turns.",
			"<b>Grow X</b>: +X Power for good at the start of each of your turns.",
			"<b>Decay X</b>: end of your turn, the enemy unit across takes X.",
			"<b>Streak</b>: flies past the unit across and hits the Commander.",
			"<b>Intercept</b>: Streak units can't fly past it.",
			"",
			"Some cards also cost <b>HP</b>: playing them hurts your own Commander.",
			"Tap or hover any card to see what it does.",
		}),
	},
	{
		Title = "Cosmic Storm",
		Text = lines({
			("From <b>round %d</b>, each Commander takes damage at the end of their own turn: <b>1, then 2, then 3</b>..."):format(R.StormStartRound),
			"",
			"Every game ends, so push for the win.",
		}),
	},
	{
		Title = "Collecting",
		Text = nil, -- filled when opened (some lines depend on the date)
	},
}

function Rulebook.TextFor(section)
	if section.Title == "Collecting" then
		return collecting()
	end
	return section.Text or ""
end

---------------------------------------------------------------------
-- The window (client only)
---------------------------------------------------------------------
local gui, pageTitle, pageText, pageScroll, tabButtons, replayButton
local onReplayCallback
local current = 1

local GOLD = Color3.fromRGB(255, 205, 90)

local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function showPage(index)
	current = index
	local section = Rulebook.Sections[index]
	pageTitle.Text = section.Title
	pageText.Text = Rulebook.TextFor(section)
	pageScroll.CanvasPosition = Vector2.new(0, 0)
	for i, b in ipairs(tabButtons) do
		b.BackgroundColor3 = i == index and Color3.fromRGB(200, 150, 60) or Color3.fromRGB(70, 70, 110)
	end
end

local function build()
	if gui then
		return
	end
	local UiTheme = require(ReplicatedStorage:WaitForChild("UiTheme"))
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	gui = make("ScreenGui", {
		Name = "RulebookGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 8,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	}, playerGui)

	local dim = make("TextButton", {
		Name = "Dim", Text = "", AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4,
	}, gui)
	dim:SetAttribute("NoTheme", true)

	-- FitScreen area: a phone shrinks it instead of overflowing
	local area = make("Frame", { Name = "Area", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
	UiTheme.FitScreen(area, 900, 520)

	local window = make("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(820, 480),
		BackgroundColor3 = Color3.fromRGB(20, 16, 40),
	}, area)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, window)
	UiTheme.Panel(window)

	local title = make("TextLabel", {
		Name = "Title", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(24, 12), Size = UDim2.new(1, -90, 0, 40),
		Font = Enum.Font.GothamBlack, TextSize = 30, Text = "Rulebook",
		TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left,
	}, window)
	UiTheme.Title(title)

	local close = make("TextButton", {
		Name = "Close", Text = "X", Font = Enum.Font.GothamBlack, TextSize = 22,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 14), Size = UDim2.fromOffset(44, 40),
		BackgroundColor3 = Color3.fromRGB(170, 60, 60), TextColor3 = Color3.new(1, 1, 1),
	}, window)
	UiTheme.Button(close)
	close.Activated:Connect(Rulebook.Close)
	dim.Activated:Connect(Rulebook.Close)

	-- section tabs down the left
	local tabs = make("Frame", {
		Name = "Tabs", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 64), Size = UDim2.new(0, 190, 1, -84),
	}, window)
	make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	tabButtons = {}
	for i, section in ipairs(Rulebook.Sections) do
		local b = make("TextButton", {
			Name = "Tab" .. i, LayoutOrder = i, Text = section.Title,
			Font = Enum.Font.GothamBold, TextSize = 17, TextColor3 = Color3.new(1, 1, 1),
			Size = UDim2.new(1, 0, 0, 37), BackgroundColor3 = Color3.fromRGB(70, 70, 110),
		}, tabs)
		UiTheme.Button(b)
		b.Activated:Connect(function()
			showPage(i)
		end)
		tabButtons[i] = b
	end

	-- the page
	local page = make("Frame", {
		Name = "Page", BackgroundColor3 = Color3.fromRGB(22, 18, 42),
		Position = UDim2.fromOffset(226, 64), Size = UDim2.new(1, -246, 1, -136),
	}, window)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, page)
	UiTheme.List(page)
	pageTitle = make("TextLabel", {
		Name = "PageTitle", BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -36, 0, 34),
		Font = Enum.Font.GothamBlack, TextSize = 24, TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left, Text = "",
	}, page)
	pageScroll = make("ScrollingFrame", {
		Name = "Scroll", BackgroundTransparency = 1, BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 48), Size = UDim2.new(1, -30, 1, -58),
		CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, page)
	pageText = make("TextLabel", {
		Name = "Body", BackgroundTransparency = 1,
		Size = UDim2.new(1, -12, 1, 0), AutomaticSize = Enum.AutomaticSize.Y, -- (fills the page; grows when longer)
		Font = Enum.Font.Gotham, TextSize = 19, LineHeight = 1.15, RichText = true,
		TextWrapped = true, TextColor3 = Color3.fromRGB(235, 235, 245),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Text = "",
	}, pageScroll)

	-- bottom row: previous / next / replay tutorial
	local function navButton(name, label, x, width, color)
		local b = make("TextButton", {
			Name = name, Text = label, Font = Enum.Font.GothamBold, TextSize = 17,
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, x, 1, -16), Size = UDim2.fromOffset(width, 44),
			BackgroundColor3 = color, TextColor3 = Color3.new(1, 1, 1),
		}, window)
		return UiTheme.Button(b)
	end
	local prev = navButton("Prev", "< Back", 226, 110, Color3.fromRGB(70, 70, 110))
	local nextB = navButton("Next", "Next >", 346, 110, Color3.fromRGB(70, 110, 190))
	replayButton = navButton("ReplayTutorial", "Replay tutorial", 594, 210, Color3.fromRGB(70, 170, 90))
	prev.Activated:Connect(function()
		showPage(current > 1 and current - 1 or #Rulebook.Sections)
	end)
	nextB.Activated:Connect(function()
		showPage(current < #Rulebook.Sections and current + 1 or 1)
	end)
	replayButton.Activated:Connect(function()
		local callback = onReplayCallback
		Rulebook.Close()
		if callback then
			callback()
		end
	end)
end

function Rulebook.Open(onReplay)
	build()
	onReplayCallback = onReplay
	replayButton.Visible = onReplay ~= nil
	showPage(current)
	gui.Enabled = true
end

function Rulebook.Close()
	if gui then
		gui.Enabled = false
	end
end

function Rulebook.IsOpen()
	return gui ~= nil and gui.Enabled
end

return Rulebook
