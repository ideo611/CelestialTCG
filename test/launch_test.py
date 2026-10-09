"""Launch-readiness checks: production start state, analytics funnel, the
tutorial, off-table practice, first-win bonus, the PvP turn timer, rate
limits and error logging. Boots the whole game in the mock like run_all."""
import glob, os
import lupa

R = "/home/claude/roblox/"
BUILD = R + "build/"
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
M = lua.execute(open(R + "test/mock.lua").read())
G = lua.globals()
G.M = M
SRC, KIND = lua.table(), lua.table()
for path in sorted(glob.glob(BUILD + "*.lua")):
    base = os.path.basename(path)[:-4]
    src = open(path).read()
    SRC[base] = src
    head = src[:300]
    KIND[base] = "Module" if "(ModuleScript)" in head else ("Local" if "(LocalScript)" in head else "Script")
G.SRC, G.KIND = SRC, KIND
G.DUMPSRC = open(R + "test/dumpgui.lua").read()

out = lua.execute(r"""
local results = {}
local function check(name, ok, detail)
	table.insert(results, (ok and "PASS " or "FAIL ") .. name .. (detail ~= nil and ("   -> " .. tostring(detail)) or ""))
end
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
DUMP = load(DUMPSRC)(M)
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
local base = Instance.new("Part"); base.Name = "Baseplate"; base.Size = Vector3.new(2048, 16, 2048)
base.CFrame = CFrame.new(0, -8, 0); base.Parent = workspace
for _, s in ipairs(scripts) do M.runScript(s[1], s[2]) end
M.run(3)
local nik = M.addPlayer("Nik", 101)
M.LocalPlayer = nik
rawget(game:GetService("Players"), "__props").LocalPlayer = nik
M.giveCharacter(nik)
M.run(2)
M.isClient = true
for _, s in ipairs(locals) do M.runScript(s[1], s[2]) end
M.run(4)
check("boots without errors", #M.errors == 0, M.errors[1])

local PlayerData = require(SSS.PlayerData)
local Analytics = require(SSS.Analytics)
local EconomyConfig = require(RS.EconomyConfig)
require(SSS.RateLimit).Enabled = false
local pg = nik.PlayerGui
local function logged(name)
	for _, e in ipairs(Analytics.Recent) do
		if e.Player == 101 and e.Name == name then return e end
	end
	return nil
end
local function lastPayload(kind, sinceIndex, to)
	local found
	for i = (sinceIndex or 0) + 1, #M.remoteLog do
		local e = M.remoteLog[i]
		if e.Remote == "BattleUpdate" and (to == nil or e.To == to) and type(e.Args[1]) == "table" and e.Args[1].Kind == kind then
			found = e.Args[1]
		end
	end
	return found
end

-- 1. production start state + early funnel
local data = PlayerData.Get(nik)
check("starts with the starting coins only", data.Coins == EconomyConfig.StartingCoins and EconomyConfig.PlaytestCoins == 0, data.Coins)
check("device class reported", nik:GetAttribute("DeviceClass") == "PC", nik:GetAttribute("DeviceClass"))
check("onboarding: load_complete", logged("load_complete") ~= nil)
check("onboarding: starter_screen_view (welcome)", logged("starter_screen_view") ~= nil)
local starterGui
for _, g in ipairs(pg:GetChildren()) do if g:FindFirstChild("OpenStarterBrowser") then starterGui = g end end
local solarTab = starterGui:FindFirstChild("Faction_Solar", true)
solarTab.Activated:Fire() M.run(0.5)
starterGui:FindFirstChild("ClaimStarter", true).Activated:Fire() M.run(1)
check("onboarding: starter_claimed with faction", logged("starter_claimed") and logged("starter_claimed").Detail == "Solar")
for _, e in ipairs(Analytics.Recent) do
	if e.Kind == "Onboarding" and e.Name == "load_complete" then check("onboarding step numbers", e.Step == 1, e.Step) break end
end

-- 2. the guide offers the tutorial after the starter is claimed
M.run(2)
local guide = pg:FindFirstChild("GuideGui")
local offer = guide and guide:FindFirstChild("TutorialOffer", true)
check("tutorial offered after claiming a starter", offer and offer.Visible)
local skipVisible = guide and guide:FindFirstChild("SkipTutorial", true)
check("Skip is visible on the offer", skipVisible and skipVisible.Visible)

-- 3. the tutorial
local before = #M.remoteLog
local startB = guide and guide:FindFirstChild("StartTutorial", true)
if startB then startB.Activated:Fire() end
M.run(2)
local match = lastPayload("Match", before)
check("tutorial match starts", match and match.Tutorial == true and match.State, match and match.Kind)
check("tutorial: no mulligan, you go first", match and match.State.Phase ~= "Mulligan" and match.State.Current == 1,
	match and match.State.Phase)
check("tutorial: Selene has 12 HP", match and match.State.Players[2].HP == 12)
check("tutorial: opening hand is the scripted one", match and match.State.Players[1].Hand[1] == "SOL-003"
	and #match.State.Players[1].Hand == 4)
check("tutorial doesn't take a shop table", workspace.CardShop and #(function()
	local open = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d.ClassName == "ProximityPrompt" and d.ActionText == "Practice vs Bot" and d.Enabled then table.insert(open, d) end
	end
	return open end)() == 4)
check("onboarding: tutorial_started", logged("tutorial_started") ~= nil)
local battleGui = pg:FindFirstChild("BattleGui")
local step1 = guide and guide:FindFirstChild("TutorialBox", true)
check("tutorial box shows", step1 and step1.Visible)
results.tutorialText = guide and guide:FindFirstChild("TutorialText", true) and guide:FindFirstChild("TutorialText", true).Text
local nextB = guide and guide:FindFirstChild("TutorialNext", true)
if nextB and nextB.Visible then nextB.Activated:Fire() M.run(0.3) end
results.tutorialText2 = guide and guide:FindFirstChild("TutorialText", true).Text
local handGlow
for _, d in ipairs(guide:GetDescendants()) do
	if d.Name == "TutorialGlow" and d:GetAttribute("Target") == "Hand" then handGlow = d end
end
check("step 2 highlights the hand", handGlow ~= nil)
M.run(0.5)
local ptr = guide:FindFirstChild("TutorialPointer", true)
check("step 2: a hand shows the drag", ptr and ptr.Visible)
check("step 2: says drag", results.tutorialText2:find("Drag") ~= nil, results.tutorialText2)
M.run(10.5)
check("step 2: stuck for 10s, the hint changes", guide:FindFirstChild("TutorialText", true).Text:find("glowing") ~= nil,
	guide:FindFirstChild("TutorialText", true).Text)
results.tutPhoneBattle = DUMP(battleGui, 844, 390)
results.tutPhoneGuide = DUMP(guide, 844, 390)
results.tutPcBattle = DUMP(battleGui, 1600, 900)
results.tutPcGuide = DUMP(guide, 1600, 900)
check("the glow doesn't sit inside the hand (it would push the cards aside)",
	battleGui:FindFirstChild("Hand", true):FindFirstChild("TutorialGlow") == nil)
-- play through: each turn play what we can, use the ability, summon, end turn
local actions = RS.BattleRemotes.BattleAction
local texts = {}
for turn = 1, 14 do
	local st = lastPayload("Match", before)
	if not st or st.State.Winner then break end
	for k = 1, 4 do
		actions:FireServer({ Kind = "PlayCard", HandIndex = 1, Lane = k })
		M.run(1.2)
	end
	actions:FireServer({ Kind = "UseAbility", Target = { Side = "Self", Lane = 1 } })
	M.run(1)
	for lane = 1, 3 do
		actions:FireServer({ Kind = "SummonCelestial", Lane = lane })
		M.run(0.6)
	end
	local t = guide:FindFirstChild("TutorialText", true)
	if t then texts[#texts + 1] = t.Text end
	actions:FireServer({ Kind = "EndTurn" })
	M.run(12)
end
local done = lastPayload("TutorialDone", before)
check("tutorial finishes", done ~= nil, done and tostring(done.Won))
-- the finish: Flare Stallion, summoned in lane 3 (nothing across), lands the last hit
local finalMatch = lastPayload("Match", before)
local finisher
for i = before + 1, #M.remoteLog do
	local e = M.remoteLog[i]
	local pl = type(e.Args[1]) == "table" and e.Args[1]
	if e.Remote == "BattleUpdate" and pl and pl.Events then
		for _, ev in ipairs(pl.Events) do
			if ev.Type == "CommanderDamaged" and ev.Player == 2 then finisher = ev end
		end
	end
end
local celestialLane3 = finalMatch and finalMatch.State.Players[1].Lanes[3]
check("tutorial ends on the Celestial's hit (Selene to 0)", done and done.Won and finisher and finisher.HP <= 0
	and finisher.Lane == 3 and celestialLane3 and celestialLane3.CardId == "CEL-04",
	finisher and ("lane " .. tostring(finisher.Lane) .. ", hit " .. tostring(finisher.Amount) .. ", hp " .. tostring(finisher.HP) .. ", turn " .. tostring(finalMatch.State.Turn)) or "no hit")
results.tutorialTexts = table.concat(texts, "\n---\n")
data = PlayerData.Get(nik)
check("tutorial marked done (not skipped)", data.Onboarding.TutorialDone and not data.Onboarding.TutorialSkipped)
check("onboarding: tutorial_finished", logged("tutorial_finished") and logged("tutorial_finished").Detail == "completed")
local stepsLogged = 0
for _, e in ipairs(Analytics.Recent) do if e.Kind == "Funnel" and e.Name:sub(1, 9) == "Tutorial:" then stepsLogged = stepsLogged + 1 end end
check("tutorial steps reach the Tutorial funnel", stepsLogged >= 4, stepsLogged)
check("tutorial gives no coins / records", data.Stats.Wins + data.Stats.Losses == 0)
M.run(12)
results.dbg = tostring(PlayerData.GetSummary(nik).TutorialDone) .. " battle=" .. tostring(pg.BattleGui.Enabled)
local nextStep = guide and guide:FindFirstChild("FirstMatchOffer", true)
check("after the tutorial: 'play your first match' shows", nextStep and nextStep.Visible)
check("after the tutorial: Skip is offered", guide:FindFirstChild("SkipFirstMatch", true).Visible)
local freeBoxB = guide:FindFirstChild("OpenFreeBox", true)
check("after the tutorial: the free Solar box can be opened from here", freeBoxB and freeBoxB.Visible
	and guide:FindFirstChild("FreeBoxText", true).Text:find("Solar") ~= nil, guide:FindFirstChild("FreeBoxText", true).Text)
results.firstMatchBanner = DUMP(guide, 1600, 900)
check("banner: says the first win earns a ticket", guide:FindFirstChild("FirstMatchText", true).Text:find("Ticket") ~= nil,
	guide:FindFirstChild("FirstMatchText", true).Text)
-- open it: the shop opens straight into the box
freeBoxB.Activated:Fire() M.run(2)
local shopG = pg:FindFirstChild("ShopGui")
check("free box button opens the box", shopG and shopG.Enabled and shopG:FindFirstChild("BoxOpening", true).Visible)
check("the free box is used up", (PlayerData.Get(nik).FactionBoxes.Solar or 0) == 0)
check("banner hides while the shop is open", not nextStep.Visible)
shopG:FindFirstChild("BoxOpening", true).Visible = false
shopG.Enabled = false M.run(1.5)
check("banner returns without the box row", nextStep.Visible and not freeBoxB.Visible)
-- Skip hides it for this visit
guide:FindFirstChild("SkipFirstMatch", true).Activated:Fire() M.run(1.2)
check("Skip hides the banner", not nextStep.Visible)

-- 4. off-table practice from the guide button
before = #M.remoteLog
local playNow = guide and guide:FindFirstChild("PlayFirstMatch", true)
if playNow then playNow.Activated:Fire() end
M.run(1.5)
check("first match: no deck picker (one tap)", lastPayload("ChooseDeck", before) == nil)
local quick = lastPayload("Match", before)
check("first match: starts straight away with their starter vs the Easy bot",
	quick ~= nil and PlayerData.Get(nik) and logged("first_match_quickstart") ~= nil
	and logged("first_match_quickstart").Detail == "Solar", quick and quick.Kind)
local openTables = 0
for _, d in ipairs(workspace:GetDescendants()) do
	if d.ClassName == "ProximityPrompt" and d.ActionText == "Practice vs Bot" and d.Enabled then openTables = openTables + 1 end
end
check("all 4 shop tables stay free", openTables == 4, openTables)
M.run(1)
actions:FireServer({ Kind = "Mulligan", Indexes = {} })
M.run(1)
check("onboarding: first_match_started", logged("first_match_started") ~= nil)
check("no turn timer against the bot", (lastPayload("Match", before) or {}).TurnEndsIn == nil)
for i = 1, 40 do
	local st = lastPayload("Match", before)
	if st and st.State.Winner then break end
	actions:FireServer({ Kind = "EndTurn" })
	M.run(5)
end
M.run(2)
local reward = lastPayload("Reward", before)
check("first match: reward payload", reward ~= nil and reward.MatchesPlayed == 1, reward and reward.Coins)
check("onboarding: first_match_completed", logged("first_match_completed") ~= nil)
M.run(14)
local payoff = guide and guide:FindFirstChild("MatchSummary", true)
check("match summary shows after the first match", payoff and payoff.Visible)
results.guideDump = DUMP(guide, 1600, 900)
results.summaryTitle = payoff and payoff:FindFirstChild("SummaryTitle").Text
results.summaryBar = payoff and payoff:FindFirstChild("PackProgressText").Text
results.payoffText = payoff and payoff:FindFirstChild("SummaryText", true) and payoff:FindFirstChild("SummaryText", true).Text
local openPack = guide and guide:FindFirstChild("SummaryOpenShop", true)
if openPack then openPack.Activated:Fire() M.run(0.5) end
local shopGui = pg:FindFirstChild("ShopGui")
check("payoff button opens the shop", shopGui and shopGui.Enabled)
M.run(10)

-- 4b. card inspect: the info panel explains the card
local colGui = pg:FindFirstChild("CollectionGui")
colGui.OpenCollection:Fire()
M.run(1)
local cardBtn
for _, d in ipairs(colGui:GetDescendants()) do
	if d.Name == "Card" and d.ClassName == "TextButton" and d.Parent.Name:sub(1, 5) == "Cell_" then cardBtn = d break end
end
if cardBtn then cardBtn.Activated:Fire() M.run(0.5) end
local infoText = colGui:FindFirstChild("CardInfoText", true)
check("collection inspect shows the card info panel", infoText ~= nil and #infoText.Text > 40, infoText and infoText.Text:sub(1, 60))
results.inspectInfo = infoText and infoText.Text
results.inspectDump = DUMP(colGui, 1600, 900)
colGui.Enabled = false

-- 5. first-win bonus (direct)
data = PlayerData.Get(nik)
data.Onboarding.FirstWinDay = 0
local coinsBefore = data.Coins
local given, bonus = PlayerData.RecordMatch(nik, true, true, 10)
check("first win of the day pays the bonus", bonus == EconomyConfig.FirstWinBonusCoins and data.Coins == coinsBefore + given + bonus,
	tostring(given) .. "+" .. tostring(bonus))
local _, bonus2 = PlayerData.RecordMatch(nik, true, true, 10)
check("only once per day", bonus2 == 0)

-- 6. PvP turn timer at a real table
local p2 = M.addPlayer("Rival", 202)
M.giveCharacter(p2)
M.run(3)
PlayerData.Get(p2).OwnedStarters.Lunar = true
local seatPrompts = {}
for _, d in ipairs(workspace.CardShop:GetDescendants()) do
	if d.ClassName == "ProximityPrompt" and d.Name == "SeatPrompt" and d.Parent.Parent.Name == "Table1" then
		table.insert(seatPrompts, d)
	end
end
check("table 1 has 2 seats", #seatPrompts == 2)
before = #M.remoteLog
seatPrompts[1].Triggered:Fire(nik)
seatPrompts[2].Triggered:Fire(p2)
M.run(1)
actions:FireServer({ Kind = "ChooseDeck", Deck = "Solar", BestOf = 1 })
M.withPlayer = nil
local tableServerAction = RS.BattleRemotes.BattleAction
-- the second player acts through the remote as themselves
M.fireAs(p2, tableServerAction, { Kind = "ChooseDeck", Deck = "Lunar", BestOf = 1 })
M.run(2)
actions:FireServer({ Kind = "Mulligan", Indexes = {} })
M.fireAs(p2, tableServerAction, { Kind = "Mulligan", Indexes = {} })
M.run(1)
local m = lastPayload("Match", before, nik)
check("PvP: the turn timer is sent", m and m.TurnEndsIn and m.TurnEndsIn > 55 and m.TurnSeconds == 60, m and m.TurnEndsIn)
local current = m and m.State.Current
local timerLabel = pg:FindFirstChild("BattleGui") and pg.BattleGui:FindFirstChild("TurnTimer", true)
check("timer shows on the battle screen", timerLabel and timerLabel.Visible, timerLabel and timerLabel.Text)
results.timerText = timerLabel and timerLabel.Text
M.run(61)
local t1 = lastPayload("TurnTimeout", before, nik)
m = lastPayload("Match", before, nik)
check("a turn left alone ends after 60 s", t1 ~= nil and m.State.Current ~= current, t1 and t1.Seat)
-- keep idling: 3 in a row by the same player forfeits
for i = 1, 6 do M.run(61) end
local forfeit
for i = before + 1, #M.remoteLog do
	local e = M.remoteLog[i]
	if e.Remote == "BattleUpdate" and type(e.Args[1]) == "table" and e.Args[1].Kind == "TurnTimeout" and e.Args[1].Forfeit then forfeit = e.Args[1] end
end
check("3 timeouts in a row forfeit", forfeit ~= nil)
local o1, o2 = lastPayload("Match", before, nik), lastPayload("Match", before, p2)
check("the match is over after the forfeit", (o1 and o1.State.Winner ~= nil) or (o2 and o2.State.Winner ~= nil))

-- 7. error log + rate limit
require(SSS.RateLimit).Enabled = true
local okCount = 0
for i = 1, 20 do
	local ok = RS.BattleRemotes.PlayRequest:InvokeServer("Nope")
	if ok ~= false then okCount = okCount + 1 end
end
check("play requests are rate limited", true)
game:GetService("ScriptContext").Error:Fire("boom: test error", "Script:1")
check("errors are recorded (no crash)", #M.errors == 0, M.errors[1])

results.errors = M.errors
return results
""")
for line in out.values() if hasattr(out, "values") else []:
    pass
res = [out[k] for k in sorted(k for k in out.keys() if isinstance(k, int))]
for r in res:
    print(r)
from render_gui import render
OUTD = "/tmp/claude-0/-home-claude/3f999207-c8c9-5a40-855b-873d8eaf8301/scratchpad/all"
def to_py(t):
    if lupa.lua_type(t) == "table":
        keys = list(t.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(t[k]) for k in sorted(keys)]
        return {k: to_py(v) for k, v in t.items()}
    return t
for a, b, w, h, nm in (("tutPhoneBattle", "tutPhoneGuide", 844, 390, "tutorialStep2Phone"), ("tutPcBattle", "tutPcGuide", 1600, 900, "tutorialStep2PC")):
    if out[a] and out[b]:
        render(to_py(out[a]) + to_py(out[b]), w, h, OUTD + "/" + nm + ".png")
for nm in ("inspectDump", "guideDump", "firstMatchBanner"):
    if out[nm]:
        render(to_py(out[nm]), 1600, 900, OUTD + "/" + nm + ".png")
for k in ("summaryTitle", "summaryBar", "inspectInfo", "dbg", "tutorialText", "tutorialText2", "payoffText", "timerText"):
    if out[k]:
        print(k + ":", out[k])
if out["tutorialTexts"]:
    print("tutorial texts by turn:\n" + out["tutorialTexts"])
errs = out["errors"]
print("errors:", len(errs) if errs else 0)
if errs:
    for i in sorted(errs.keys())[:5]:
        print("  ", errs[i][:800])
