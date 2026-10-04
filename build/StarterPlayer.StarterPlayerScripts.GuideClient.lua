--[[
	GuideClient (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > GuideClient

	Walks new players from "I have a starter deck" to "I played a match and
	opened a pack", and adds a few things to the battle screen:
	  - Tutorial offer, right after the free starter is claimed:
	    "Learn to play (about 5 minutes)" or Skip.
	  - The tutorial itself: a scripted match against Tidekeeper Selene, with
	    Captain Sol Varro explaining one thing at a time (box over the match
	    log) and a glow on whatever to tap next.
	  - "Play your first match" banner after the tutorial (or Skip), until the
	    first real match is played. Its button starts a practice match against
	    the bot right away (no table needed).
	  - After every match: Victory / Defeat, coins earned, progress to the next
	    pack, and Open a pack (or My Cards) / Play vs Bot / Close.
	  - HUD buttons: "Play vs Bot" (any time) and "How to play" (replay the
	    tutorial), plus a reminder of the first-win-of-the-day bonus.
	  - Battle screen: the turn timer in player-vs-player matches.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CardArt = require(ReplicatedStorage:WaitForChild("CardArt"))
local SoundAssets = require(ReplicatedStorage:WaitForChild("SoundAssets"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local battleRemotes = ReplicatedStorage:WaitForChild("BattleRemotes")
local battleUpdate = battleRemotes:WaitForChild("BattleUpdate")
local battleAction = battleRemotes:WaitForChild("BattleAction")
local playRequest = battleRemotes:WaitForChild("PlayRequest")
local economyRemotes = ReplicatedStorage:WaitForChild("EconomyRemotes")
local walletUpdate = economyRemotes:WaitForChild("WalletUpdate")
local economyRequest = economyRemotes:WaitForChild("EconomyRequest")

local GOLD = Color3.fromRGB(255, 205, 90)
local PANEL = Color3.fromRGB(20, 16, 40)
local WHITE = Color3.fromRGB(255, 255, 255)
local GREEN = Color3.fromRGB(70, 170, 90)
local GREY = Color3.fromRGB(90, 90, 110)
local RED = Color3.fromRGB(235, 80, 70)

local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

-- Text that scales with the screen but never gets too small to read on a phone
local function text(parent, name, position, size, value, props)
	local label = make("TextLabel", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextColor3 = WHITE,
		TextScaled = true,
		TextWrapped = true,
		Text = value,
	}, parent)
	for key, v in pairs(props or {}) do
		label[key] = v
	end
	make("UITextSizeConstraint", { MinTextSize = 14, MaxTextSize = 34 }, label)
	return label
end

local function button(parent, name, value, position, size, color)
	local b = make("TextButton", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundColor3 = color or GREEN,
		Font = Enum.Font.GothamBold,
		TextColor3 = WHITE,
		TextScaled = true,
		Text = value,
		AutoButtonColor = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
	make("UITextSizeConstraint", { MinTextSize = 16, MaxTextSize = 30 }, b)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, b)
	return b
end

local function panel(parent, name, position, size)
	local frame = make("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = position,
		Size = size,
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.05,
		Visible = false,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, frame)
	make("UIStroke", { Color = GOLD, Thickness = 2 }, frame)
	return frame
end

local gui = make("ScreenGui", {
	Name = "GuideGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 5, -- above the battle screen (the tutorial box sits on it)
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local state = {
	Summary = nil,
	InBattle = false,
	Tutorial = nil,     -- { Step = n, Seat = n } while the tutorial match runs
	TurnEndsAt = nil,   -- os.clock() when the current PvP turn times out
	TurnMine = false,
	TurnSeconds = 60,
	OfferDismissed = false,
	Series = nil,       -- { Won, Coins, Bonus, Games, First } for the match summary
}

local showSummary -- defined below

local function battleGui()
	return playerGui:FindFirstChild("BattleGui")
end

local function starterBrowserOpen()
	for _, g in ipairs(playerGui:GetChildren()) do
		if g:IsA("ScreenGui") and g:FindFirstChild("OpenStarterBrowser") and g.Enabled then
			return true
		end
	end
	return false
end

local function ownsStarter(summary)
	return summary ~= nil and summary.OwnedStarters ~= nil and next(summary.OwnedStarters) ~= nil
end

local function ask(kind)
	local ok, result, message = pcall(function()
		return playRequest:InvokeServer(kind)
	end)
	if not ok then
		return false, "Couldn't reach the server."
	end
	return result, message
end

---------------------------------------------------------------------
-- Tutorial offer
---------------------------------------------------------------------
local offer = panel(gui, "TutorialOffer", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.5))
make("UISizeConstraint", { MinSize = Vector2.new(300, 240) }, offer)
local varroArt = CardArt.ArtFor and CardArt.ArtFor("CMD-SOL-01")
if varroArt then
	make("ImageLabel", {
		Name = "Portrait",
		Position = UDim2.fromScale(0.04, 0.08),
		Size = UDim2.fromScale(0.26, 0.5),
		BackgroundTransparency = 1,
		Image = varroArt,
		ScaleType = Enum.ScaleType.Crop,
	}, offer)
end
text(offer, "OfferTitle", UDim2.fromScale(0.33, 0.06), UDim2.fromScale(0.63, 0.16), "Ready, cadet?", { TextColor3 = GOLD })
text(offer, "OfferText", UDim2.fromScale(0.33, 0.24), UDim2.fromScale(0.63, 0.36),
	"I'm Captain Sol Varro. Let me show you how to play: one quick practice match, about 5 minutes.",
	{ Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left })
local startTutorialButton = button(offer, "StartTutorial", "Learn to play", UDim2.fromScale(0.06, 0.68),
	UDim2.fromScale(0.5, 0.22))
local skipTutorialButton = button(offer, "SkipTutorial", "Skip, I know how", UDim2.fromScale(0.6, 0.68),
	UDim2.fromScale(0.34, 0.22), GREY)

---------------------------------------------------------------------
-- "Play your first match" banner (after the tutorial or Skip)
---------------------------------------------------------------------
local firstMatch = make("Frame", {
	Name = "FirstMatchOffer",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.1),
	Size = UDim2.fromScale(0.52, 0.12),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.05,
	Visible = false,
}, gui)
make("UISizeConstraint", { MinSize = Vector2.new(320, 80) }, firstMatch)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, firstMatch)
make("UIStroke", { Color = GOLD, Thickness = 2 }, firstMatch)
text(firstMatch, "FirstMatchText", UDim2.fromScale(0.03, 0.1), UDim2.fromScale(0.6, 0.8),
	"NEXT: play your first match against the Practice Bot!", { TextXAlignment = Enum.TextXAlignment.Left })
local playFirstButton = button(firstMatch, "PlayFirstMatch", "Play now", UDim2.fromScale(0.66, 0.15),
	UDim2.fromScale(0.31, 0.7))

---------------------------------------------------------------------
-- After every match: result, coins, progress to the next pack, what next
---------------------------------------------------------------------
local payoff = panel(gui, "MatchSummary", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.5, 0.5))
make("UISizeConstraint", { MinSize = Vector2.new(320, 260) }, payoff)
local payoffTitle = text(payoff, "SummaryTitle", UDim2.fromScale(0.05, 0.05), UDim2.fromScale(0.9, 0.16), "",
	{ TextColor3 = GOLD })
local payoffText = text(payoff, "SummaryText", UDim2.fromScale(0.06, 0.23), UDim2.fromScale(0.88, 0.22), "",
	{ Font = Enum.Font.Gotham })
-- progress toward the next pack
local barBack = make("Frame", {
	Name = "PackProgress",
	Position = UDim2.fromScale(0.06, 0.48),
	Size = UDim2.fromScale(0.88, 0.07),
	BackgroundColor3 = Color3.fromRGB(50, 44, 80),
	BorderSizePixel = 0,
}, payoff)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, barBack)
local barFill = make("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = GOLD,
	BorderSizePixel = 0,
}, barBack)
make("UICorner", { CornerRadius = UDim.new(1, 0) }, barFill)
local barText = text(payoff, "PackProgressText", UDim2.fromScale(0.06, 0.56), UDim2.fromScale(0.88, 0.1), "",
	{ Font = Enum.Font.Gotham, TextColor3 = Color3.fromRGB(200, 195, 225) })
local payoffShop = button(payoff, "SummaryOpenShop", "Open a pack", UDim2.fromScale(0.04, 0.72),
	UDim2.fromScale(0.3, 0.18))
local payoffAgain = button(payoff, "SummaryPlayAgain", "Play vs Bot", UDim2.fromScale(0.35, 0.72),
	UDim2.fromScale(0.3, 0.18), Color3.fromRGB(70, 110, 190))
local payoffClose = button(payoff, "SummaryClose", "Close", UDim2.fromScale(0.66, 0.72),
	UDim2.fromScale(0.3, 0.18), GREY)

---------------------------------------------------------------------
-- HUD: Play vs Bot, How to play, first-win reminder
---------------------------------------------------------------------
local playButton = button(gui, "PlayVsBot", "Play vs Bot", UDim2.new(0, 10, 0.45, -104), UDim2.fromOffset(120, 44))
local howButton = button(gui, "HowToPlay", "How to play", UDim2.new(0, 10, 0.45, -54), UDim2.fromOffset(120, 44),
	Color3.fromRGB(70, 110, 190))
local firstWinHint = text(gui, "FirstWinHint", UDim2.new(0, 136, 0.45, -104), UDim2.fromOffset(250, 44),
	"", { TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, Visible = false })
local hudMessage = text(gui, "GuideMessage", UDim2.new(0, 136, 0.45, -54), UDim2.fromOffset(300, 44), "",
	{ TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Left, Visible = false })

local function flashHud(message)
	hudMessage.Text = message or ""
	hudMessage.Visible = message ~= nil
	task.delay(4, function()
		if hudMessage.Text == message then
			hudMessage.Visible = false
		end
	end)
end

---------------------------------------------------------------------
-- Tutorial box (sits over the match log) and glows
---------------------------------------------------------------------
local box = make("Frame", {
	Name = "TutorialBox",
	Position = UDim2.fromScale(0.758, 0.063),
	Size = UDim2.fromScale(0.229, 0.435),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.02,
	Visible = false,
	ZIndex = 20,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, box)
make("UIStroke", { Color = GOLD, Thickness = 3 }, box)
text(box, "TutorialSpeaker", UDim2.fromScale(0.05, 0.02), UDim2.fromScale(0.9, 0.1), "Captain Sol Varro",
	{ TextColor3 = GOLD, ZIndex = 21 })
local boxTitle = text(box, "TutorialTitle", UDim2.fromScale(0.05, 0.14), UDim2.fromScale(0.9, 0.2), "",
	{ Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21 })
local boxText = text(box, "TutorialText", UDim2.fromScale(0.05, 0.37), UDim2.fromScale(0.9, 0.42), "",
	{ Font = Enum.Font.Gotham, TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 21 })
local boxNext = button(box, "TutorialNext", "Next", UDim2.fromScale(0.05, 0.82), UDim2.fromScale(0.42, 0.14))
boxNext.ZIndex = 21
local boxSkip = button(box, "TutorialQuit", "Skip tutorial", UDim2.fromScale(0.53, 0.82), UDim2.fromScale(0.42, 0.14), GREY)
boxSkip.ZIndex = 21

local glows = {}
local function clearGlows()
	for _, g in ipairs(glows) do
		g:Destroy()
	end
	glows = {}
end

local function glow(names)
	clearGlows()
	local bg = battleGui()
	if not bg then
		return
	end
	for _, name in ipairs(names or {}) do
		local target = bg:FindFirstChild(name, true)
		if target then
			local frame = make("Frame", {
				Name = "TutorialGlow",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 30,
			}, target)
			make("UIStroke", { Name = "GlowStroke", Color = GOLD, Thickness = 5, Transparency = 0 }, frame)
			make("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
			table.insert(glows, frame)
		end
	end
end

-- Spotlight: during a tutorial step, everything except the step's targets is
-- dimmed (four dark panels around them) and taps outside them are blocked.
-- The tutorial box stays on top and usable.
-- a full-screen reference: target positions are measured relative to it, so
-- the screens' top-bar insets never throw the hole off
local spotlightRoot = make("Frame", {
	Name = "SpotlightRoot",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
}, gui)
local shades = {}
for i = 1, 4 do
	shades[i] = make("Frame", {
		Name = "TutorialShade" .. i,
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Active = true, -- swallows taps
		Visible = false,
		ZIndex = 15,
	}, spotlightRoot)
end

local function focusRect()
	local bg = battleGui()
	if not (bg and bg.Enabled and state.Focus) then
		return nil
	end
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, name in ipairs(state.Focus) do
		local target = bg:FindFirstChild(name, true)
		if target and target:IsA("GuiObject") and target.Visible then
			local ok, pos, size = pcall(function()
				return target.AbsolutePosition, target.AbsoluteSize
			end)
			if ok and pos and size and size.X > 0 then
				x0, y0 = math.min(x0, pos.X), math.min(y0, pos.Y)
				x1, y1 = math.max(x1, pos.X + size.X), math.max(y1, pos.Y + size.Y)
			end
		end
	end
	if x0 == math.huge then
		return nil
	end
	local origin = spotlightRoot.AbsolutePosition
	x0, x1, y0, y1 = x0 - origin.X, x1 - origin.X, y0 - origin.Y, y1 - origin.Y
	local pad = 8
	return x0 - pad, y0 - pad, x1 + pad, y1 + pad
end

local function updateSpotlight()
	local x0, y0, x1, y1 = focusRect()
	if not x0 then
		for _, shade in ipairs(shades) do
			shade.Visible = false
		end
		return
	end
	-- top, bottom, left, right of the lit area (pixels; the guide and battle screens share an origin)
	shades[1].Position, shades[1].Size = UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, math.max(0, y0))
	shades[2].Position, shades[2].Size = UDim2.fromOffset(0, y1), UDim2.new(1, 0, 1, -y1)
	shades[3].Position, shades[3].Size = UDim2.fromOffset(0, y0), UDim2.fromOffset(math.max(0, x0), y1 - y0)
	shades[4].Position, shades[4].Size = UDim2.fromOffset(x1, y0), UDim2.new(1, -x1, 0, y1 - y0)
	for _, shade in ipairs(shades) do
		shade.Visible = true
	end
end

-- Pulse the glows
RunService.Heartbeat:Connect(function()
	local t = os.clock()
	updateSpotlight()
	for _, g in ipairs(glows) do
		local stroke = g:FindFirstChild("GlowStroke")
		if stroke then
			stroke.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(t * 5))
		end
	end
end)

--[[ The tutorial, one thing at a time. Kind:
	"mine"   happens on your turn (skipped ahead if your turn ends first)
	"theirs" Selene's turn (ends when your turn starts)
	"final"  until the match ends
	Until = an event of yours that finishes the step early ]]
local STEPS = {
	{ Id = "intro", Kind = "mine", Next = true, Focus = { "EnemyCommander" },
		Title = "BEAT SELENE", Text = "Knock her Commander from 12 HP down to 0." },
	{ Id = "play_unit", Kind = "mine", Until = "UnitPlayed", Glow = { "Hand" },
		Focus = { "Hand", "Slot_Self_1", "Slot_Self_2", "Slot_Self_3" },
		Title = "PLAY A UNIT", Text = "Tap a card, then tap one of your lanes." },
	{ Id = "end_turn", Kind = "mine", Glow = { "EndTurnButton" }, Focus = { "EndTurnButton" },
		Title = "END YOUR TURN", Text = "New units attack starting next turn." },
	{ Id = "their_turn", Kind = "theirs",
		Title = "SELENE'S TURN", Text = "Watch what she plays." },
	{ Id = "lanes", Kind = "mine", Glow = { "Slot_Self_1", "Slot_Self_2", "Slot_Self_3" },
		Focus = { "Hand", "Slot_Self_1", "Slot_Self_2", "Slot_Self_3", "Slot_Enemy_1", "Slot_Enemy_2", "Slot_Enemy_3", "EndTurnButton" },
		Title = "LANES FIGHT", Text = "Units hit the lane straight across. Empty lane? It hits Selene! Play a unit, then End Turn." },
	{ Id = "their_turn2", Kind = "theirs",
		Title = "SELENE'S TURN", Text = "Units with 0 Health are defeated." },
	{ Id = "ability", Kind = "mine", Until = "CommanderAbility", Glow = { "AbilityButton" },
		Focus = { "AbilityButton", "MyCommander", "Slot_Self_1", "Slot_Self_2", "Slot_Self_3" },
		Title = "USE YOUR POWER", Text = "Tap Ability, then a unit: +2 Power this turn." },
	{ Id = "spend", Kind = "mine", Glow = { "Hand", "EndTurnButton" },
		Title = "SPEND YOUR ENERGY", Text = "You get 1 more energy every turn. Play a card, then End Turn." },
	{ Id = "their_turn3", Kind = "theirs",
		Title = "SELENE'S TURN", Text = "Get ready. Something big is coming..." },
	{ Id = "celestial", Kind = "mine", Until = "CelestialSummoned", Glow = { "StarGateButton" },
		Focus = { "StarGateButton", "Slot_Self_1", "Slot_Self_2", "Slot_Self_3" },
		Title = "SUMMON YOUR CELESTIAL", Text = "Tap the Star Gate, then an empty lane. It has Rush: it attacks right away!" },
	{ Id = "finish", Kind = "final",
		Title = "FINISH HER!", Text = "Keep playing cards and ending your turn. Tap Inspect to read any card." },
}

local function showStep()
	local tut = state.Tutorial
	local step = tut and STEPS[tut.Step]
	if not step then
		box.Visible = false
		clearGlows()
		return
	end
	box.Visible = true
	boxTitle.Text = step.Title or ""
	boxText.Text = step.Text
	boxNext.Visible = step.Next == true
	glow(step.Glow)
	state.Focus = step.Focus -- the spotlight (below) dims everything else
end

local function reportStep()
	local tut = state.Tutorial
	local step = tut and STEPS[tut.Step]
	if step then
		battleAction:FireServer({ Kind = "TutorialStep", Step = tut.Step, Name = step.Id })
	end
end

local function advance()
	local tut = state.Tutorial
	if not tut or tut.Step >= #STEPS then
		return
	end
	tut.Step = tut.Step + 1
	reportStep()
	showStep()
end

local function onTutorialEvents(seat, events)
	local tut = state.Tutorial
	if not tut then
		return
	end
	for _, e in ipairs(events or {}) do
		local step = STEPS[tut.Step]
		if not step then
			break
		end
		if e.Type == "TurnStarted" and e.Player ~= seat then
			while STEPS[tut.Step] and STEPS[tut.Step].Kind == "mine" do
				advance()
			end
		elseif e.Type == "TurnStarted" and e.Player == seat then
			while STEPS[tut.Step] and STEPS[tut.Step].Kind == "theirs" do
				advance()
			end
		elseif step.Until and e.Type == step.Until and e.Player == seat then
			advance()
		end
	end
end

boxNext.Activated:Connect(function()
	advance()
end)

boxSkip.Activated:Connect(function()
	-- leaving the tutorial match (it can be replayed from "How to play")
	battleAction:FireServer({ Kind = "Leave" })
	ask("SkipTutorial")
end)

---------------------------------------------------------------------
-- What shows when
---------------------------------------------------------------------
local function refresh()
	local summary = state.Summary
	local bg = battleGui()
	state.InBattle = bg ~= nil and bg.Enabled
	local busy = state.InBattle or starterBrowserOpen()
	local tutorialDone = summary and summary.TutorialDone
	offer.Visible = not busy and ownsStarter(summary) and not tutorialDone and not state.OfferDismissed
		and not payoff.Visible
	firstMatch.Visible = not busy and not offer.Visible and not payoff.Visible and ownsStarter(summary)
		and (tutorialDone or state.OfferDismissed) and (summary.MatchesPlayed or 0) == 0
	playButton.Visible = not state.InBattle and ownsStarter(summary)
	howButton.Visible = not state.InBattle and ownsStarter(summary)
	firstWinHint.Visible = not state.InBattle and summary ~= nil and summary.FirstWinAvailable == true
		and (summary.FirstWinBonus or 0) > 0 and (summary.MatchesPlayed or 0) > 0
	if firstWinHint.Visible then
		firstWinHint.Text = ("First win today: +%d bonus coins"):format(summary.FirstWinBonus)
	end
	if not state.InBattle then
		hudMessage.Visible = hudMessage.Visible and hudMessage.Text ~= ""
	end
end

local function onSummary(summary)
	state.Summary = summary
	refresh()
end
walletUpdate.OnClientEvent:Connect(onSummary)
task.spawn(function()
	local ok, okResult, summary = pcall(function()
		return economyRequest:InvokeServer("GetSummary", {})
	end)
	if ok and okResult and summary then
		onSummary(summary)
	end
end)

local function startPractice()
	local ok, message = ask("Practice")
	if not ok then
		flashHud(message)
	end
	refresh()
end

startTutorialButton.Activated:Connect(function()
	offer.Visible = false
	local ok, message = ask("StartTutorial")
	if not ok then
		flashHud(message)
	end
end)
skipTutorialButton.Activated:Connect(function()
	state.OfferDismissed = true
	ask("SkipTutorial")
	refresh()
end)
playFirstButton.Activated:Connect(startPractice)
playButton.Activated:Connect(startPractice)
howButton.Activated:Connect(function()
	pcall(function() ReplicatedStorage.AnalyticsRemotes.Track:FireServer("rulebook_opened", "replay_tutorial") end)
	local ok, message = ask("StartTutorial")
	if not ok then
		flashHud(message)
	end
end)
payoffShop.Activated:Connect(function()
	payoff.Visible = false
	-- enough coins: the shop; otherwise the collection
	local canBuy = payoffShop:GetAttribute("CanBuy")
	local targetGui = playerGui:FindFirstChild(canBuy and "ShopGui" or "CollectionGui")
	local open = targetGui and targetGui:FindFirstChild(canBuy and "OpenShop" or "OpenCollection")
	if open then
		open:Fire()
	end
	refresh()
end)
payoffClose.Activated:Connect(function()
	payoff.Visible = false
	refresh()
end)
payoffAgain.Activated:Connect(function()
	payoff.Visible = false
	startPractice()
end)

-- The match summary, once the battle screen has closed
showSummary = function(series)
	local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
	local bg = battleGui()
	local started = os.clock()
	while bg and bg.Enabled and os.clock() - started < 10 do
		task.wait(0.3)
	end
	task.wait(0.4) -- let the wallet catch up with the reward
	local summary = state.Summary or {}
	local coins = summary.Coins or 0
	local price = EconomyConfig.PackPriceCoins or 100
	payoffTitle.Text = (series.First and "First match done! " or "") .. (series.Won and "Victory!" or "Defeat")
	local earned = series.Coins + series.Bonus
	local line
	if earned > 0 then
		line = ("+%d coins"):format(earned)
		if series.Bonus > 0 then
			line = line .. (" (including a %d first-win bonus)"):format(series.Bonus)
		end
	else
		line = "No coins this time (the daily coin limit was reached, or the match was very short)."
	end
	if series.First then
		line = line .. "\nCoins buy booster packs at the shop counter."
	end
	payoffText.Text = line
	local canBuy = coins >= price
	barFill.Size = UDim2.fromScale(math.clamp(coins / price, 0, 1), 1)
	barText.Text = canBuy and ("%d coins: you can open a pack!"):format(coins)
		or ("%d / %d coins to your next pack"):format(coins, price)
	payoffShop.Text = canBuy and "Open a pack" or "My Cards"
	payoffShop:SetAttribute("CanBuy", canBuy)
	payoff.Visible = true
	refresh()
end

---------------------------------------------------------------------
-- Battle updates: the tutorial, the turn timer, the match summary
---------------------------------------------------------------------
local turnTimer -- created on the battle screen the first time it's needed
local function getTurnTimer()
	if turnTimer and turnTimer.Parent then
		return turnTimer
	end
	local bg = battleGui()
	local root = bg and bg:FindFirstChild("Root")
	if not root then
		return nil
	end
	turnTimer = text(root, "TurnTimer", UDim2.fromScale(0.62, 0.008), UDim2.fromScale(0.135, 0.047), "",
		{ TextColor3 = GOLD, Visible = false, ZIndex = 8 })
	return turnTimer
end

local function formatSeconds(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

RunService.Heartbeat:Connect(function()
	local label = state.TurnEndsAt and getTurnTimer()
	if not label then
		if turnTimer then
			turnTimer.Visible = false
		end
		return
	end
	local left = state.TurnEndsAt - os.clock()
	label.Visible = true
	label.Text = (state.TurnMine and "Your turn  " or "Their turn  ") .. formatSeconds(left)
	label.TextColor3 = (left <= 15) and RED or GOLD
end)

battleUpdate.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.Kind == "Match" then
		local s = payload.State
		if payload.TurnEndsIn and s and not s.Winner then
			state.TurnEndsAt = os.clock() + payload.TurnEndsIn
			state.TurnMine = s.Current == payload.Seat
			state.TurnSeconds = payload.TurnSeconds or 60
		else
			state.TurnEndsAt = nil
		end
		if payload.Tutorial then
			if not state.Tutorial then
				state.Tutorial = { Step = 1, Seat = payload.Seat }
				reportStep()
				showStep()
			end
			onTutorialEvents(payload.Seat, payload.Events)
		end
		task.defer(refresh)
	elseif payload.Kind == "TurnTimeout" then
		local who = payload.Seat == "You" and "Your" or "Their"
		local message = payload.Forfeit and (who .. " turn timed out 3 times in a row: that's a forfeit.")
			or ("%s turn ran out of time (%d/%d)."):format(who, payload.Count or 1, payload.Max or 3)
		local label = getTurnTimer()
		if label then
			label.Text = message
		end
		SoundAssets.Play("Error")
	elseif payload.Kind == "TutorialDone" then
		if state.Tutorial then
			state.Tutorial.Step = #STEPS + 1
			box.Visible = true
			boxNext.Visible = false
			boxSkip.Visible = false
			clearGlows()
			state.Focus = nil
			boxTitle.Text = payload.Won and "VICTORY!" or "GOOD TRY!"
			boxText.Text = payload.Won and "That's how it's done, cadet. You're ready for a real match."
				or "You know the basics now. The bot is waiting whenever you're ready."
		end
	elseif payload.Kind == "Reward" then
		-- add up the games of this match (a best-of series sends one per game)
		local series = state.Series or { Coins = 0, Bonus = 0, Games = 0 }
		series.Coins = series.Coins + (payload.Coins or 0)
		series.Bonus = series.Bonus + (payload.Bonus or 0)
		series.Games = series.Games + 1
		series.Won = payload.Won == true
		series.First = series.First or (payload.MatchesPlayed or 0) == 1
		series.VsBot = payload.VsBot == true
		state.Series = series
	elseif payload.Kind == "Closed" then
		local series = state.Series
		state.Series = nil
		if series and not state.Tutorial then
			task.spawn(showSummary, series)
		end
		state.TurnEndsAt = nil
		if state.Tutorial then
			state.Tutorial = nil
			state.Focus = nil
			box.Visible = false
			boxSkip.Visible = true
			clearGlows()
		end
		task.defer(refresh)
	end
end)

-- Re-check now and then (the starter browser and battle screen open and close)
task.spawn(function()
	while true do
		task.wait(1)
		refresh()
	end
end)
