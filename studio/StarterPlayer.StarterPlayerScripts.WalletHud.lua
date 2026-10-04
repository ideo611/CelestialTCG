--[[
	WalletHud (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > WalletHud

	Shows your coins, Star Shards, Star Tokens and today's coin progress.
	In Studio only, it also shows a small test panel for opening packs and
	breaking down extras, until the real card shop is built.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local remotes = ReplicatedStorage:WaitForChild("EconomyRemotes")
local walletUpdate = remotes:WaitForChild("WalletUpdate")
local request = remotes:WaitForChild("EconomyRequest")

local player = Players.LocalPlayer
local WHITE = Color3.fromRGB(255, 255, 255)
local RARITY_COLORS = {
	Common = Color3.fromRGB(210, 210, 210),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(190, 100, 255),
	Legendary = Color3.fromRGB(255, 200, 60),
}
local MYTHIC_COLOR = Color3.fromRGB(255, 90, 200)

local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local gui = make("ScreenGui", {
	Name = "WalletGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 2,
}, player:WaitForChild("PlayerGui"))

local wallet = make("TextLabel", {
	Name = "WalletText",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(330, 54),
	BackgroundColor3 = Color3.fromRGB(24, 20, 42),
	BackgroundTransparency = 0.15,
	TextColor3 = WHITE,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextWrapped = true,
	Text = "Loading your cards...",
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, wallet)

local function onSummary(summary)
	local text = ("Coins %d   Shards %d   Tokens %d/%d\nToday: %d/%d coins earned"):format(
		summary.Coins, summary.StarShards, summary.StarTokens, EconomyConfig.TokenExchangeCost,
		summary.DailyCoinsEarned, summary.DailyCoinCap)
	if summary.Temporary then
		text = text .. "  (not saved)"
	end
	wallet.Text = text
end
walletUpdate.OnClientEvent:Connect(onSummary)

-- Ask once on start too, in case the first update arrived before this script was ready
task.spawn(function()
	local ok, summary = request:InvokeServer("GetSummary", {})
	if ok and summary then
		onSummary(summary)
	end
end)

-- The battle screen covers everything; hide the wallet while it's open
task.spawn(function()
	local battleGui = player.PlayerGui:WaitForChild("BattleGui", 10)
	if battleGui then
		wallet.Visible = not battleGui.Enabled
		battleGui:GetPropertyChangedSignal("Enabled"):Connect(function()
			wallet.Visible = not battleGui.Enabled
		end)
	end
end)

---------------------------------------------------------------------
-- Studio-only test panel
---------------------------------------------------------------------
if not RunService:IsStudio() then
	return
end

local panel = make("Frame", {
	Name = "DevPanel",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 70),
	Size = UDim2.fromOffset(330, 150),
	BackgroundColor3 = Color3.fromRGB(40, 20, 20),
	BackgroundTransparency = 0.1,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
make("TextLabel", {
	Name = "DevTitle",
	Position = UDim2.fromOffset(8, 4),
	Size = UDim2.new(1, -16, 0, 18),
	BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(255, 180, 180),
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "STUDIO TEST TOOLS (hidden in the real game)",
}, panel)

local messageLabel = make("TextLabel", {
	Name = "DevMessage",
	Position = UDim2.fromOffset(8, 124),
	Size = UDim2.new(1, -16, 0, 20),
	BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(255, 230, 120),
	Font = Enum.Font.Gotham,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
}, panel)

local buttons = {
	{ "DevOpenPack", "Open pack (coins)" },
	{ "DevOpenShardPack", "Open pack (shards)" },
	{ "DevCoins", "+500 coins" },
	{ "DevBreakDown", "Break down extras" },
	{ "DevStarter", "Claim both starters" },
	{ "DevOdds", "Print odds to Output" },
}
local made = {}
for i, info in ipairs(buttons) do
	local col = (i - 1) % 2
	local row = math.floor((i - 1) / 2)
	local b = make("TextButton", {
		Name = info[1],
		Position = UDim2.fromOffset(8 + col * 160, 26 + row * 32),
		Size = UDim2.fromOffset(152, 28),
		BackgroundColor3 = Color3.fromRGB(90, 50, 50),
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		Text = info[2],
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	made[info[1]] = b
end

-- Pack results popup
local resultsFrame = make("Frame", {
	Name = "PackResults",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(800, 300),
	BackgroundColor3 = Color3.fromRGB(14, 11, 28),
	Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 10) }, resultsFrame)
local resultsList = make("Frame", {
	Name = "Cards",
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.new(1, -20, 1, -60),
	BackgroundTransparency = 1,
}, resultsFrame)
local closeResults = make("TextButton", {
	Name = "CloseResults",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(160, 34),
	BackgroundColor3 = Color3.fromRGB(70, 60, 120),
	TextColor3 = WHITE,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	Text = "Nice",
}, resultsFrame)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, closeResults)
closeResults.Activated:Connect(function()
	resultsFrame.Visible = false
end)

local function showPulls(pulls)
	for _, child in ipairs(resultsList:GetChildren()) do
		child:Destroy()
	end
	local width = 1 / #pulls
	for i, pull in ipairs(pulls) do
		local card = CardDatabase.GetCard(pull.CardId)
		local slot = make("Frame", {
			Name = "Pull_" .. i,
			Position = UDim2.new((i - 1) * width, 4, 0, 0),
			Size = UDim2.new(width, -8, 1, 0),
			BackgroundTransparency = 1,
		}, resultsList)
		local cardFrame = make("Frame", {
			Name = "Card",
			Size = UDim2.new(1, 0, 1, -28),
		}, slot)
		CardVisuals.Draw(cardFrame, pull.CardId, { Finish = pull.Finish })
		local color = pull.Finish == "Mythic" and MYTHIC_COLOR or (RARITY_COLORS[card.Rarity] or WHITE)
		make("TextLabel", {
			Name = "Caption",
			Position = UDim2.new(0, 0, 1, -26),
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			TextColor3 = color,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			Text = CardVisuals.FinishNames[pull.Finish] .. (pull.New and "  NEW!" or ""),
		}, slot)
	end
	resultsFrame.Visible = true
end

local function ask(kind, args)
	local ok, result = request:InvokeServer(kind, args or {})
	return ok, result
end

made.DevOpenPack.Activated:Connect(function()
	local ok, result = ask("OpenPack", { Currency = "Coins" })
	if ok then
		showPulls(result)
		messageLabel.Text = "Opened a pack."
	else
		messageLabel.Text = result
	end
end)

made.DevOpenShardPack.Activated:Connect(function()
	local ok, result = ask("OpenPack", { Currency = "Shards" })
	if ok then
		showPulls(result)
		messageLabel.Text = "Opened a pack with Shards."
	else
		messageLabel.Text = result
	end
end)

made.DevCoins.Activated:Connect(function()
	local ok, result = ask("DevGrantCoins")
	messageLabel.Text = ok and ("+" .. result .. " coins") or result
end)

made.DevBreakDown.Activated:Connect(function()
	local ok, result = ask("BreakDownExtras")
	messageLabel.Text = ok and ("+" .. result .. " Star Shards") or result
end)

made.DevStarter.Activated:Connect(function()
	local okA, a = ask("DevGrantStarter", { Deck = "Solar" })
	local okB, b = ask("DevGrantStarter", { Deck = "Lunar" })
	if okA or okB then
		messageLabel.Text = "Starter decks added to your collection."
	else
		messageLabel.Text = tostring(a or b)
	end
end)

made.DevOdds.Activated:Connect(function()
	local ok, odds = ask("GetOdds")
	if not ok then
		messageLabel.Text = odds
		return
	end
	print("=== Pack odds (what the shop will show) ===")
	for _, slot in ipairs(odds.Slots) do
		print(("%s x%d"):format(slot.Name, slot.Count))
		for _, outcome in ipairs(slot.Outcomes) do
			print(("  %-26s %6.2f%%"):format(outcome.Label, outcome.Chance))
			for _, entry in ipairs(outcome.Cards) do
				print(("      %-24s %7.3f%%"):format(CardDatabase.GetCard(entry.CardId).Name, entry.Chance))
			end
		end
	end
	print(odds.PityText)
	messageLabel.Text = "Odds printed to the Output window."
end)