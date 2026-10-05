"""Loads every script from build/ into the mock, boots the server and one
player's client, then exercises shop, packs, singles, starters, binder,
battle + spectate. Prints a checklist and renders key screens."""
import glob, os, sys
import lupa
from render_gui import render

R = "/home/claude/roblox/"
BUILD = R + "build/"
OUT = "/tmp/claude-0/-home-claude/3f999207-c8c9-5a40-855b-873d8eaf8301/scratchpad/all"
os.makedirs(OUT, exist_ok=True)

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
M = lua.execute(open(R + "test/mock.lua").read())
G = lua.globals()
G.M = M
files = {}
for path in sorted(glob.glob(BUILD + "*.lua")):
    base = os.path.basename(path)[:-4]
    parts = base.split(".")
    files[base] = (parts[0], parts[-1], open(path).read())
SRC = lua.table()
KIND = lua.table()
for base, (svc, name, src) in files.items():
    SRC[base] = src
    head = src[:300]
    KIND[base] = "Module" if "(ModuleScript)" in head else ("Local" if "(LocalScript)" in head else "Script")
G.SRC, G.KIND = SRC, KIND
G.DUMPSRC = open(R + "test/dumpgui.lua").read()

checks = lua.execute(r"""
local results = {}
local function check(name, ok, detail)
	table.insert(results, { name, ok and true or false, detail and tostring(detail) or "" })
end
local dump = load(DUMPSRC)(M)
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

-- modules first (they're only run when required)
local scripts, locals = {}, {}
for base, src in pairs(SRC) do
	local svc, name = base:match("^(%w+)%..-(%w+)$")
	if KIND[base] == "Module" then
		M.addModule(svc == "ReplicatedStorage" and RS or SSS, name, src)
	elseif KIND[base] == "Script" then
		table.insert(scripts, { name, src })
	else
		table.insert(locals, { name, src })
	end
end
table.sort(scripts, function(a, b) return a[1] < b[1] end)
table.sort(locals, function(a, b) return a[1] < b[1] end)

-- a baseplate and spawn like the real place
local base = Instance.new("Part"); base.Name = "Baseplate"; base.Size = Vector3.new(2048, 16, 2048)
base.CFrame = CFrame.new(0, -8, 0); base.Parent = workspace

M.isClient = false
for _, s in ipairs(scripts) do M.runScript(s[1], s[2]) end
M.run(3)
check("server scripts boot without errors", #M.errors == 0, M.errors[1])

local nik = M.addPlayer("Nik", 101)
M.LocalPlayer = nik
rawget(game:GetService("Players"), "__props").LocalPlayer = nik
M.giveCharacter(nik)
M.run(2)
M.isClient = true
for _, s in ipairs(locals) do M.runScript(s[1], s[2]) end
M.run(4)
check("client scripts boot without errors", #M.errors == 0, M.errors[1])

-- rate limiting: a burst of shop requests gets cut off, then tests may hammer freely
do
	local RateLimit = require(SSS.RateLimit)
	local refused = 0
	for _ = 1, 30 do
		local ok, msg = RS.ShopRemotes.ShopRequest:InvokeServer("Nope", {})
		if msg == "Slow down a little." then refused = refused + 1 end
	end
	check("rate limit cuts off a burst of 30 shop requests", refused >= 15, refused)
	RateLimit.Enabled = false
	require(RS.EconomyConfig).DailyCoinPacks = 100000 -- (the shop tests open lots of packs)
end
local PlayerData = require(SSS.PlayerData)
local EconomyConfig = require(RS.EconomyConfig)
local Packs = require(RS.Packs)
local Singles = require(RS.Singles)
local Building = require(SSS.CardShopBuilding)
local shopRequest = RS.ShopRemotes.ShopRequest
local pg = nik.PlayerGui

-- welcome: the starter browser opens for brand-new players
local starterGui
for _, g in ipairs(pg:GetChildren()) do
	if g:FindFirstChild("OpenStarterBrowser") then starterGui = g end
end
check("starter browser opens as the welcome screen", starterGui and starterGui.Enabled)
results.starterWelcome = starterGui and dump(starterGui, 1600, 900)
-- look at a faction without a deck yet
if starterGui then
	local tab = starterGui:FindFirstChild("Faction_Nebula", true)
	if tab then tab.Activated:Fire() M.run(0.5) end
	results.starterNebula = dump(starterGui, 1600, 900)
	check("Nebula tab shows its starter deck", starterGui:FindFirstChild("DeckList", true) ~= nil
		and starterGui:FindFirstChild("ComingSoon", true) == nil)
	local solarTab = starterGui:FindFirstChild("Faction_Solar", true)
	if solarTab then solarTab.Activated:Fire() M.run(0.5) end
	local claim = starterGui:FindFirstChild("ClaimStarter", true)
	if claim then claim.Activated:Fire() M.run(1) end
end
local data = PlayerData.Get(nik)
check("claimed the free Solar starter from the browser", data and data.OwnedStarters and data.OwnedStarters.Solar == true)

-- production start state: no test coins, only the starting coins and the free starter
check("new player starts with exactly the starting coins (no test coins)",
	data and data.Coins == EconomyConfig.StartingCoins and EconomyConfig.PlaytestCoins == 0 and not data.PlaytestCoinsGiven,
	data and data.Coins)
check("new player has no shards, tokens or extra starters", data and data.StarShards == 0 and data.StarTokens == 0
	and data.OwnedStarters.Lunar == nil)

-- packs: each booster type
data.Coins = 5000
data.StarShards = 500
local typeIds = {}
for _, t in ipairs(EconomyConfig.PackTypes) do table.insert(typeIds, t.Id) end
check("enabled boosters", #typeIds == 6, table.concat(typeIds, ","))
for _, id in ipairs(typeIds) do
	local ok, odds = shopRequest:InvokeServer("GetOdds", { PackType = id })
	local sumOk = ok and true
	if ok then
		for _, slot in ipairs(odds.Slots) do
			for _, outcome in ipairs(slot.Outcomes) do
				local total = 0
				for _, c in ipairs(outcome.Cards) do total = total + tonumber(c.Shown:sub(1, -2)) end
				if math.abs(total - outcome.Chance) > 1e-6 then sumOk = false end
			end
		end
	end
	check("odds for " .. id .. " add up", sumOk)
	local okOffer, offer = shopRequest:InvokeServer("PackOffer", { PackType = id, Currency = "Coins" })
	check(id .. " offer has 3 different fronts", okOffer and #offer.Fronts == 3 and offer.Fronts[1] ~= offer.Fronts[2]
		and offer.Fronts[2] ~= offer.Fronts[3], okOffer and table.concat(offer.Fronts, ",") or offer)
	local okBuy, result = shopRequest:InvokeServer("BuyPack", { PackType = id, Currency = "Coins", Choice = 2 })
	check(id .. " pack opens with the chosen front", okBuy and result.Front == offer.Fronts[2] and #result.Pulls == 6,
		okBuy and result.Front or result)
	-- faction packs only hold that faction (+ Neutral, + paired Celestials)
	if id ~= "All" and okBuy then
		local CardDatabase = require(RS.CardDatabase)
		local fine = true
		for _ = 1, 40 do
			local _, r = shopRequest:InvokeServer("BuyPack", { PackType = id, Currency = "Coins" })
			for _, pull in ipairs(r.Pulls) do
				local card = CardDatabase.GetCard(pull.CardId)
				local okCard = card.Faction == id or card.Faction == "Neutral"
				if card.PairsWith then
					okCard = false
					for _, f in ipairs(card.PairsWith) do if f == id then okCard = true end end
				end
				if not okCard then fine = false end
			end
			data.Coins = 5000
		end
		check(id .. " booster: 40 packs only pull " .. id .. "/Neutral/paired cards", fine)
	end
end

-- the pick-a-pack screen
local shopGui = pg:FindFirstChild("ShopGui")
for _, g in ipairs(pg:GetChildren()) do if g:FindFirstChild("PackPicker", true) or g:FindFirstChild("PickerRow", true) then shopGui = g end end
RS.ShopRemotes.ShopEvent:FireClient(nik, { Kind = "OpenShop", Tab = "Packs" })
M.run(1)
if shopGui then
	results.shopPacks = dump(shopGui, 1600, 900)
	results.shopPhone = dump(shopGui, 1169, 540)
	local solarButton = shopGui:FindFirstChild("PackType_Solar", true)
	if solarButton then solarButton.Activated:Fire() M.run(0.5) end
	local buy = shopGui:FindFirstChild("BuyWithCoins", true)
	if buy then buy.Activated:Fire() M.run(1) end
	results.shopPicker = dump(shopGui, 1600, 900)
	check("pick-a-pack shows 3 packs", shopGui:FindFirstChild("PackChoice_3", true) ~= nil)
	local choice = shopGui:FindFirstChild("PackChoice_1", true)
	if choice then choice.Activated:Fire() M.run(2) end
	results.shopReveal = dump(shopGui, 1600, 900)
end

-- singles
local okS, singles = shopRequest:InvokeServer("GetSingles", {})
check("singles stock today", okS and #singles.Stock == 12, okS and #singles.Stock)
local first = singles.Stock[1]
local coinsBefore = data.Coins
local okB, bought = shopRequest:InvokeServer("BuySingle", { CardId = first.CardId })
check("buy a single (" .. first.CardId .. " for " .. tostring(first.Price) .. ")", okB and data.Coins == coinsBefore - first.Price, bought)
local okB2, again = shopRequest:InvokeServer("BuySingle", { CardId = first.CardId })
check("can't buy the same single twice a day", not okB2, again)
local priceList = {}
for _, e in ipairs(singles.Stock) do table.insert(priceList, e.CardId .. "=" .. e.Price .. "(" .. e.ExpectedPacks .. " packs)") end
results.singlesPrices = table.concat(priceList, "  ")
RS.ShopRemotes.ShopEvent:FireClient(nik, { Kind = "OpenShop", Tab = "Singles" })
M.run(1)
if shopGui then results.shopSingles = dump(shopGui, 1600, 900) end
check("singles case shows today's cards", #Building.SinglesCase.Parent:FindFirstChild("CaseBackboard").Surface:GetChildren() == 12)

-- prompts placed on the building
check("singles prompt", Building.SinglesCase:FindFirstChild("SinglesPrompt") ~= nil)
check("starter table prompt", Building.StarterTable:FindFirstChild("StarterPrompt") ~= nil)
check("cat prompt", Building.Cat and Building.Cat:FindFirstChild("PetPrompt") ~= nil)
Building.Cat.PetPrompt.Triggered:Fire(nik)
M.run(0.5)
check("petting the cat shows hearts", Building.Cat.CatHearts.Enabled)

-- binder: open mine, pull it out, someone looks
local binderRequest = RS.BinderRemotes.BinderRequest
local okM, mine = binderRequest:InvokeServer("GetMine", {})
check("binder: get mine", okM, mine)
local okOut = binderRequest:InvokeServer("SetOut", { Out = true })
check("binder: pull out", okOut)
local okCase = binderRequest:InvokeServer("SetShowcase", { Cards = { { CardId = "CMD-SOL-01", Finish = "Base" } } })
check("binder: set front page", okCase)
local binderGui = pg:FindFirstChild("BinderGui")
local openMine = pg:FindFirstChild("OpenMyBinder", true)
if openMine then openMine.Activated:Fire() M.run(1) end
for _, g in ipairs(pg:GetChildren()) do if g:FindFirstChild("BinderTitle", true) then binderGui = g end end
results.binder = binderGui and dump(binderGui, 1600, 900)
local next = binderGui and binderGui:FindFirstChild("NextPage", true)
if next then next.Activated:Fire() M.run(1) results.binder2 = dump(binderGui, 1600, 900) end
local closeBinder = binderGui and binderGui:FindFirstChild("CloseBinder", true)
if closeBinder then closeBinder.Activated:Fire() M.run(0.5) end
if binderGui then binderGui.Enabled = false end

-- deck builder: edit a saved deck, then sort its list by stars
do
	local DB = require(RS.CardDatabase)
	local sd = DB.StarterDecks.Solar
	local list = {}
	for id, n in pairs(sd.Cards) do for _ = 1, n do table.insert(list, id) end end
	local okSave, saveResult = RS.EconomyRemotes.EconomyRequest:InvokeServer("SaveDeck",
		{ Name = "Test Solar", Commander = sd.Commander, Celestial = sd.Celestial, Cards = list })
	check("deck builder: save a deck", okSave, saveResult)
end
local openCards = pg:FindFirstChild("OpenCollection", true)
if openCards then openCards.Activated:Fire() M.run(0.5) end
local colGui = pg:FindFirstChild("CollectionGui")
local decksTab = colGui and colGui:FindFirstChild("DecksTab", true)
if decksTab then decksTab.Activated:Fire() M.run(0.5) end
local editDeck = colGui and colGui:FindFirstChild("EditDeck", true)
check("deck builder: a deck to edit", editDeck ~= nil)
if editDeck then editDeck.Activated:Fire() M.run(0.5) end
local starCells = 0
for _, d in ipairs(colGui and colGui:GetDescendants() or {}) do
	if d.Name:sub(1, 6) == "Stars_" then starCells = starCells + 1 end
end
check("deck builder: star column", starCells > 0, starCells)
results.deckEditor = colGui and dump(colGui, 1600, 900)
results.deckEditorPhone = colGui and dump(colGui, 1169, 540)
local sortB = colGui and colGui:FindFirstChild("SortDeckList", true)
check("deck builder: sort button", sortB ~= nil)
if sortB then sortB.Activated:Fire() M.run(0.5) end
results.deckEditor2 = colGui and dump(colGui, 1600, 900)
local fmtB = colGui and colGui:FindFirstChild("DeckFormatToggle", true)
check("deck builder: format toggle", fmtB ~= nil)
if fmtB then fmtB.Activated:Fire() M.run(0.5) end
local starText = colGui and colGui:FindFirstChild("StarText", true)
check("deck builder: Open format has no star limit", starText and starText.Text:find("no limit") ~= nil, starText and starText.Text)
local saveB = colGui and colGui:FindFirstChild("SaveDeck", true)
if saveB then saveB.Activated:Fire() M.run(0.5) end
do
	local data = require(game:GetService("ServerScriptService").PlayerData).Get(game:GetService("Players"):GetPlayers()[1])
	check("deck builder: deck saved as Open", data and data.Decks[1] and data.Decks[1].Format == "Open", data and data.Decks[1] and data.Decks[1].Format)
end
local editAgain = colGui and colGui:FindFirstChild("EditDeck", true)
if editAgain then editAgain.Activated:Fire() M.run(0.5) end
local cancelDeck = colGui and colGui:FindFirstChild("CancelDeck", true)
if cancelDeck then cancelDeck.Activated:Fire() M.run(0.5) end
local closeCol = colGui and colGui:FindFirstChild("CloseCollection", true)
if closeCol then closeCol.Activated:Fire() M.run(0.5) end

-- the rulebook (How to play)
local howB = pg:FindFirstChild("HowToPlay", true)
if howB then howB.Activated:Fire() M.run(0.5) end
local rulebook = pg:FindFirstChild("RulebookGui")
check("How to play opens the rulebook", rulebook and rulebook.Enabled)
local dockGui = pg:FindFirstChild("HudDockGui")
M.run(0.5)
check("HUD column hides under the rulebook", dockGui and dockGui:FindFirstChild("Dock") and not dockGui.Dock.Visible)
if rulebook then
	results.rulebook = dump(rulebook, 1600, 900)
	results.rulebookPhone = dump(rulebook, 844, 390)
	rulebook:FindFirstChild("Next", true).Activated:Fire() M.run(0.2)
	check("rulebook Next turns the page", rulebook:FindFirstChild("PageTitle", true).Text == "Your deck", rulebook:FindFirstChild("PageTitle", true).Text)
	rulebook:FindFirstChild("Tab9", true).Activated:Fire() M.run(0.2)
	local body = rulebook:FindFirstChild("Body", true).Text
	check("rulebook Collecting page has the live numbers", body:find("Star Tokens") and body:find("50 coins"), body:sub(1, 80))
	results.rulebook2 = dump(rulebook, 1600, 900)
	check("rulebook has Replay tutorial", rulebook:FindFirstChild("ReplayTutorial", true).Visible)
	rulebook:FindFirstChild("Close", true).Activated:Fire() M.run(0.2)
	check("rulebook closes", not rulebook.Enabled)
end

-- battle vs bot at table 1, with the TV following along
local tvs = workspace:FindFirstChild("SpectateTVs")
check("4 TVs over the tables", tvs and #tvs:GetChildren() == 4)
local tableModel
for _, d in ipairs(workspace:GetDescendants()) do
	if d.ClassName == "ProximityPrompt" and d.ActionText == "Practice vs Bot" and not tableModel then tableModel = d end
end
tableModel.Triggered:Fire(nik)
M.run(1)
local actions = RS.BattleRemotes.BattleAction
actions:FireServer({ Kind = "ChooseDeck", Deck = "Solar", BestOf = 1 })
M.run(2)
local snapsBefore = 0
for _, e in ipairs(M.remoteLog) do if e.Remote == "TableUpdate" then snapsBefore = snapsBefore + 1 end end
check("match started and TV got it", snapsBefore > 0 and tvs.TV1.LiveLamp.Color.R > 0.9, snapsBefore)
local battleGui
for _, g in ipairs(pg:GetChildren()) do if g:FindFirstChild("EndTurn", true) or g.Name == "BattleGui" then battleGui = g end end
-- the Commander intro: both Commanders big in the middle, the board dark, no hand yet
do
	local intro = {}
	for _, d in ipairs(battleGui:GetDescendants()) do if d.Name == "IntroCommander" then table.insert(intro, d) end end
	check("intro: both Commanders shown big", #intro == 2, #intro)
	check("intro: the opening hand waits", not battleGui:FindFirstChild("Mulligan", true).Visible)
	results.intro = dump(battleGui, 1600, 900)
	M.run(18) -- (the mock's sounds never report ending, so each line runs to its time limit)
	local left = 0
	for _, d in ipairs(battleGui:GetDescendants()) do if d.Name == "IntroCommander" or d.Name == "IntroDim" then left = left + 1 end end
	check("intro: cleans up after", left == 0, left)
end
-- mulligan: the opening hand shows; pick the first card, send it back
local mull = battleGui and battleGui:FindFirstChild("Mulligan", true)
check("mulligan screen shows", mull and mull.Visible)
do
	local gs = game:GetService("SoundService"):FindFirstChild("GameSounds")
	local n = 0
	for _, c in ipairs(gs and gs:GetChildren() or {}) do if c.Name == "CommanderVoice" then n = n + 1 end end
	check("match start: never two Commanders at once", n <= 1, n)
end
do
	M.run(0.5)
	local dg = pg:FindFirstChild("HudDockGui")
	local ob = pg:FindFirstChild("OpenMyBinder", true)
	local tb = pg:FindFirstChild("ToggleBinderOut", true)
	local function shown(b)
		local o = b
		while o and o ~= pg do
			if o:IsA("GuiObject") and not o.Visible then return false end
			if o:IsA("ScreenGui") and not o.Enabled then return false end
			o = o.Parent
		end
		return true
	end
	check("binder buttons hidden in a match", ob and tb and not shown(ob) and not shown(tb) and not ob.Visible,
		tostring(ob and ob.Parent and ob.Parent.Name) .. " dock=" .. tostring(dg and dg.Dock.Visible) .. " battle=" .. tostring(battleGui and battleGui.Enabled))
end
local firstCard = mull and mull:FindFirstChild("MulliganCard_1", true)
if firstCard then firstCard.Activated:Fire() M.run(0.3) end
check("mulligan marks a card", mull and mull:FindFirstChild("SendBack", true) ~= nil)
results.mulligan = battleGui and dump(battleGui, 1600, 900)
local confirmM = mull and mull:FindFirstChild("MulliganConfirm", true)
if confirmM then confirmM.Activated:Fire() M.run(2) end
check("mulligan screen closes", mull and not mull.Visible)
local sawMull = false
for _, e in ipairs(M.remoteLog) do
	if e.Remote == "BattleUpdate" and type(e.Args[1]) == "table" and e.Args[1].Events then
		for _, ev in ipairs(e.Args[1].Events) do if ev.Type == "Mulligan" and (ev.Count or 0) == 1 then sawMull = true end end
	end
end
check("mulligan sent back one card", sawMull)
-- picking a hand card on your turn shows it big over the log
do
	local shown = false
	for _ = 1, 4 do
		local hc = battleGui and battleGui:FindFirstChild("HandCard_1", true)
		if hc then hc.Activated:Fire() M.run(0.3) end
		local pick = battleGui and battleGui:FindFirstChild("PickPreview", true)
		if pick and pick.Visible then
			shown = true
			results.battlePhonePick = dump(battleGui, 844, 390)
			hc.Activated:Fire() M.run(0.3)
			check("unpicking hides it again", not pick.Visible)
			break
		end
		actions:FireServer({ Kind = "EndTurn" })
		M.run(6)
	end
	check("picking a hand card shows it big", shown)
end
for i = 1, 4 do
	actions:FireServer({ Kind = "EndTurn" })
	M.run(6)
end
workspace.CurrentCamera.CFrame = CFrame.new(tvs.TV1.Screen.Position + Vector3.new(0, -6, 18))
M.run(1)
results.tvLive = dump(pg:FindFirstChild("SpectateTV1_Front"), 420, 240)
for i = 1, 10 do
	actions:FireServer({ Kind = "EndTurn" })
	M.run(6)
	if i == 1 then
		local graveButton = battleGui and battleGui:FindFirstChild("TheirGraveyard", true)
		check("graveyard button", graveButton ~= nil)
		if graveButton then
			graveButton.Activated:Fire() M.run(0.3)
			local graveCount = 0
			for _, d in ipairs(battleGui:FindFirstChild("GraveyardCards", true):GetChildren()) do
				if d.Name:sub(1, 6) == "Grave_" then graveCount = graveCount + 1 end
			end
			if not battleGui:FindFirstChild("Graveyard", true).Visible then
			local kinds = {}
			for _, e in ipairs(M.remoteLog) do
				if e.Remote == "BattleUpdate" and type(e.Args[1]) == "table" then
					local ev = {}
					for _, x in ipairs(e.Args[1].Events or {}) do table.insert(ev, x.Type) end
					table.insert(kinds, e.Args[1].Kind .. "[" .. table.concat(ev, ",") .. "]")
				end
			end
			print("GRAVEDBG updates: " .. table.concat(kinds, " | "))
		end
		check("graveyard window opens", battleGui:FindFirstChild("Graveyard", true).Visible,
			battleGui:FindFirstChild("GraveyardTitle", true).Text)
			results.graveyard = dump(battleGui, 1600, 900)
			battleGui:FindFirstChild("GraveyardClose", true).Activated:Fire() M.run(0.2)
		end
	end
end
results.battle = battleGui and dump(battleGui, 1600, 900)
results.battlePhone = battleGui and dump(battleGui, 844, 390)
check("own match keeps the spectator view closed", not pg.SpectateGui.Enabled)
-- look at the TV from the floor
workspace.CurrentCamera.CFrame = CFrame.new(tvs.TV1.Screen.Position + Vector3.new(0, -6, 18))
M.run(1)
results.tv = dump(pg:FindFirstChild("SpectateTV1_Front"), 540, 300)

-- more games: you play each new starter against random bot decks (bot plays the new cards;
-- your screen animates every new event type)
local CardDatabase = require(RS.CardDatabase)
for _, name in ipairs({ "Nebula", "Void", "Comet" }) do
	data.OwnedStarters[name] = true
end
-- give those starters (and the bot's copies) some Anomalies so their events show up too
-- (only while Anomalies are switched on)
CardDatabase.DeckFormats.Zenith.StarCap = 999
if CardDatabase.Rules.AnomaliesEnabled == false then ANOMALY_SKIP = true end
local ANOMALY_TEST = { Nebula = { "NEB-024", "NEB-025", "NEB-026" }, Void = { "VOI-024", "VOI-025", "VOI-026" },
	Comet = { "COM-023", "COM-024", "COM-025" }, Solar = { "SOL-023", "SOL-024", "SOL-025" },
	Lunar = { "LUN-024", "LUN-025", "LUN-026" } }
for name, ids in pairs(ANOMALY_SKIP and {} or ANOMALY_TEST) do
	local cards = CardDatabase.StarterDecks[name].Cards
	local removed = 0
	for id, n in pairs(cards) do
		if removed < 6 and n == 2 then cards[id] = nil removed = removed + 2 end
	end
	for _, id in ipairs(ids) do cards[id] = 2 end
	cards[ids[1]] = 2 + (6 - removed) -- keep the deck at 30
end
local seen = {}
local before = #M.remoteLog
for round, deckName in ipairs({ "Nebula", "Void", "Comet", "Nebula", "Void", "Comet" }) do
	-- wait for the table to reset
	M.run(12)
	tableModel.Triggered:Fire(nik)
	M.run(1)
	actions:FireServer({ Kind = "ChooseDeck", Deck = deckName, BestOf = 1 })
	M.run(2)
	actions:FireServer({ Kind = "Mulligan", Indexes = {} })
	M.run(1)
	for i = 1, 30 do
		-- play the first affordable card each turn, then end the turn
		for k = 1, 4 do
			actions:FireServer({ Kind = "PlayCard", HandIndex = k, Lane = k % 3 + 1,
				Target = { Side = (k % 2 == 0) and "Self" or "Enemy", Lane = (k % 3) + 1 } })
			M.run(0.5)
		end
		actions:FireServer({ Kind = "UseAbility", Target = { Side = "Enemy", Lane = 1 } })
		M.run(0.3)
		actions:FireServer({ Kind = "UseAbility", Target = { Side = "Self", Lane = 1 } })
		M.run(0.3)
		actions:FireServer({ Kind = "UseAbility" })
		M.run(0.3)
		actions:FireServer({ Kind = "EndTurn" })
		M.run(5)
	end
end
for i = before + 1, #M.remoteLog do
	local entry = M.remoteLog[i]
	if entry.Remote == "BattleUpdate" and type(entry.Args[1]) == "table" and entry.Args[1].Events then
		for _, e in ipairs(entry.Args[1].Events) do seen[e.Type] = true end
	end
end
local kinds = {}
for k in pairs(seen) do table.insert(kinds, k) end
table.sort(kinds)
results.eventKinds = table.concat(kinds, " ")
if CardDatabase.Rules.AnomaliesEnabled ~= false then
	check("battle screen has Anomaly slots", battleGui and battleGui:FindFirstChild("MyAnomaly1", true) ~= nil
		and battleGui:FindFirstChild("EnemyAnomaly2", true) ~= nil)
	for _, k in ipairs({ "AnomalySet", "AnomalyTriggered" }) do
		check("battle screen got event " .. k, seen[k])
	end
else
	check("Anomalies switched off: no Anomaly events", not seen.AnomalySet and not seen.AnomalyTriggered)
	local chip = battleGui and battleGui:FindFirstChild("MyAnomaly1", true)
	check("Anomalies switched off: slots hidden", not chip or not chip.Visible)
end
for _, k in ipairs({ "UnitGrew", "GrowGained", "Decay", "UnitWeakened", "StreakGained", "UnitReturned", "CommanderPaidHP" }) do
	check("battle screen got event " .. k, seen[k])
end
results.battle2 = battleGui and dump(battleGui, 1600, 900)

-- space world
check("space world built", workspace:FindFirstChild("SpaceWorld") ~= nil)
workspace:SetAttribute("SpaceEventNow", "Comet")
M.run(3)

local parts = {}
for _, root in ipairs({ workspace.CardShop, workspace.SpectateTVs }) do
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			local cf, sz = d.CFrame, d.Size
			table.insert(parts, { name = d.Name, x = cf.X, y = cf.Y, z = cf.Z, sx = sz.X, sy = sz.Y, sz = sz.Z,
				c = { d.Color.R, d.Color.G, d.Color.B }, t = d.Transparency or 0, parent = d.Parent.Name })
		end
	end
end
results.parts = parts
results.problems = M.remoteProblems
results.errors = M.errors
results.warnings = M.warnings
results.list = results
return results
""")


def to_py(t):
    if lupa.lua_type(t) == "table":
        keys = list(t.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(t[k]) for k in sorted(keys)]
        return {k: to_py(v) for k, v in t.items() if k != "list"}
    return t


res = to_py(checks)
for item in [v for k, v in sorted((k, v) for k, v in res.items() if isinstance(k, int))]:
    print(("PASS " if item[1] else "FAIL ") + item[0] + ("   -> " + item[2] if item[2] else ""))
print("remote problems:", len(res.get("problems") or []))
for p in (res.get("problems") or [])[:8]:
    print("  ", p)
print("errors:", len(res.get("errors") or []))
for e in (res.get("errors") or [])[:6]:
    print("  ", e[:1500])
print("warnings:", len(res.get("warnings") or []))
for w in (res.get("warnings") or [])[:8]:
    print("  ", w[:300])
print("singles:", res.get("singlesPrices"))
print("events seen:", res.get("eventKinds"))
for name, size in [("mulligan", (1600, 900)), ("graveyard", (1600, 900)), ("deckEditor", (1600, 900)), ("deckEditor2", (1600, 900)), ("starterWelcome", (1600, 900)), ("starterNebula", (1600, 900)), ("shopPacks", (1600, 900)),
                   ("shopPicker", (1600, 900)), ("shopReveal", (1600, 900)), ("shopSingles", (1600, 900)),
                   ("binder", (1600, 900)), ("binder2", (1600, 900)), ("battle", (1600, 900)), ("battle2", (1600, 900)), ("battlePhone", (844, 390)), ("battlePhonePick", (844, 390)), ("deckEditorPhone", (1169, 540)), ("shopPhone", (1169, 540)), ("intro", (1600, 900)), ("rulebook", (1600, 900)), ("rulebook2", (1600, 900)), ("rulebookPhone", (844, 390)), ("tv", (540, 300)), ("tvLive", (420, 240))]:
    if res.get(name):
        render(res[name], size[0], size[1], f"{OUT}/{name}.png")
import json
json.dump(res["parts"], open(OUT + "/parts.json", "w"))
print("parts:", len(res["parts"]))
print("renders in", OUT)
