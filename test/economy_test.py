"""Economy + data-safety checks: session lock, Robux receipts (granted once,
only after saving), tickets, the daily coin-pack limit, booster boxes,
first-win and tutorial tickets, and the shop's Robux screens."""
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

G.SHOTS = lua.table()
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
local EconomyConfig = require(RS.EconomyConfig)
require(SSS.RateLimit).Enabled = false
local MPS = game:GetService("MarketplaceService")
local Granted = Enum.ProductPurchaseDecision.PurchaseGranted
local NotYet = Enum.ProductPurchaseDecision.NotProcessedYet
local store = M.dataStores["PlayerData_v2"]
local shopRequest = RS.ShopRemotes.ShopRequest
local function shop(kind, args) return shopRequest:InvokeServer(kind, args or {}) end
local data = PlayerData.Get(nik)

-- 1. session lock
local saved = store.Data["u_101"]
check("save holds this server's lock", saved and saved.SessionLock and saved.SessionLock.Id ~= nil)
-- a second player whose save is locked by another (live) server: waits, then takes over
store.Data["u_202"] = { Coins = 777, Collection = {}, OwnedStarters = {}, SessionLock = { Id = "other-server", Time = os.time() } }
local amy = M.addPlayer("Amy", 202)
M.run(6)
check("waits while another server holds the save", not PlayerData.IsLoaded(amy))
M.run(30)
check("takes over a save that isn't let go", PlayerData.IsLoaded(amy) and PlayerData.Get(amy).Coins == 777)
-- stale lock (crashed server) is taken over at once
store.Data["u_303"] = { Coins = 55, Collection = {}, OwnedStarters = {}, SessionLock = { Id = "dead", Time = os.time() - 99999 } }
local bo = M.addPlayer("Bo", 303)
M.run(1)
check("a crashed server's old lock is taken over at once", PlayerData.IsLoaded(bo) and PlayerData.Get(bo).Coins == 55)
-- another server takes Bo's save: this server must not overwrite it
store.Data["u_303"].SessionLock = { Id = "newer-server", Time = os.time() }
store.Data["u_303"].Coins = 999
local okSave = PlayerData.Save(bo)
check("a save taken by another server isn't overwritten", okSave == false and store.Data["u_303"].Coins == 999)
-- leaving lets go of the lock, and nothing puts it back afterwards
PlayerData.Release(amy)
check("leaving releases the lock", store.Data["u_202"].SessionLock == nil)
PlayerData.Save(amy)
check("a save after leaving doesn't lock it again", store.Data["u_202"].SessionLock == nil)
-- the lock is per visit: a save with no lock (someone else's visit ended) isn't overwritten
local cy = M.addPlayer("Cy", 404)
M.run(1)
store.Data["u_404"].SessionLock = nil
store.Data["u_404"].Coins = 4321
check("a save someone else let go of isn't overwritten", PlayerData.Save(cy) == false and store.Data["u_404"].Coins == 4321)
-- receipts while leaving are left for next time
local dee = M.addPlayer("Dee", 505)
M.run(1)
EconomyConfig.Products.Ticket1.ProductId = 1001
local profileDee = PlayerData.Get(dee)
local saveFn = PlayerData.Save
local releaseThread = coroutine.create(function() PlayerData.Release(dee) end)
-- simulate: release has started (Releasing set) when a receipt arrives
PlayerData.Save = function(p, release) if release then coroutine.yield() end return saveFn(p, release) end
coroutine.resume(releaseThread)
PlayerData.Save = saveFn
local dLeave = MPS.ProcessReceipt({ PlayerId = 505, ProductId = 1001, PurchaseId = "rcpt-leaving" })
check("a receipt during leaving isn't confirmed (asked again next visit)", dLeave == NotYet and (profileDee.Tickets or 0) == 0)
coroutine.resume(releaseThread)
EconomyConfig.Products.Ticket1.ProductId = 0

-- 2. economy numbers
check("packs cost 50 coins, 3 coin packs a day", EconomyConfig.PackPriceCoins == 50 and EconomyConfig.DailyCoinPacks == 3)
data.Coins = 1000
local opened = 0
for _ = 1, 4 do
	local ok = shop("BuyPack", { PackType = "Solar", Currency = "Coins" })
	if ok then opened = opened + 1 end
end
local okFourth, msg4 = shop("BuyPack", { PackType = "Solar", Currency = "Coins" })
check("only 3 coin packs per day", opened == 3 and not okFourth, msg4)
check("coin packs took 150 coins", data.Coins == 850, data.Coins)

-- 3. tickets: no daily limit
data.Tickets = 2
local okT1 = shop("BuyPack", { PackType = "Lunar", Currency = "Ticket" })
local okT2 = shop("BuyPack", { PackType = "Comet", Currency = "Ticket" })
local okT3, msgT3 = shop("BuyPack", { PackType = "Comet", Currency = "Ticket" })
check("tickets open packs past the daily limit", okT1 and okT2 and data.Tickets == 0)
check("no ticket, no pack", not okT3, msgT3)

-- 4. first win ticket, tutorial ticket
data.Onboarding.FirstWinDay = 0
local _, _, t1 = PlayerData.RecordMatch(nik, true, true, 10)
local _, _, t2 = PlayerData.RecordMatch(nik, true, true, 10)
check("first win of the day pays a ticket, once", t1 == 1 and t2 == 0 and data.Tickets == 1, tostring(t1) .. "/" .. tostring(t2))
data.Onboarding.TutorialRewarded = nil
local r1 = PlayerData.SetTutorialDone(nik, false)
local r2 = PlayerData.SetTutorialDone(nik, false)
check("finishing the tutorial pays a ticket, once", r1 == 1 and r2 == 0 and data.Tickets == 2)
local coinsBefore = data.Coins
data.DailyCoinsEarned = 0
local won = PlayerData.RecordMatch(nik, true, false, 10)
local lost = PlayerData.RecordMatch(nik, false, false, 10)
check("wins pay 10 coins, losses 5", won == 10 and lost == 5 and data.Coins == coinsBefore + 15)

-- 5. Robux products
local okSoon, soon = shop("BuyProduct", { Product = "Ticket1" })
check("products without an id say coming soon", not okSoon and soon == "Coming soon!", soon)
EconomyConfig.Products.Ticket1.ProductId = 1001
EconomyConfig.Products.Ticket5.ProductId = 1005
EconomyConfig.Products.BoosterBox.ProductId = 1449
local okPrompt = shop("BuyProduct", { Product = "Ticket5" })
check("buying prompts Roblox's purchase box", okPrompt and #M.purchasePrompts == 1 and M.purchasePrompts[1].ProductId == 1005)
local tickets0 = data.Tickets
local d1 = MPS.ProcessReceipt({ PlayerId = 101, ProductId = 1005, PurchaseId = "rcpt-1" })
check("a purchase is granted and saved", d1 == Granted and data.Tickets == tickets0 + 5
	and store.Data["u_101"].Tickets == tickets0 + 5, tostring(d1 and d1.Name))
local d2 = MPS.ProcessReceipt({ PlayerId = 101, ProductId = 1005, PurchaseId = "rcpt-1" })
check("the same purchase is never granted twice", d2 == Granted and data.Tickets == tickets0 + 5)
local d3 = MPS.ProcessReceipt({ PlayerId = 999, ProductId = 1005, PurchaseId = "rcpt-2" })
check("a buyer who left: Roblox asks again later", d3 == NotYet)
local d4 = MPS.ProcessReceipt({ PlayerId = 101, ProductId = 4242, PurchaseId = "rcpt-3" })
check("an unknown product isn't confirmed", d4 == NotYet)
-- a failed save means not confirmed (and granting again later doesn't double it)
local t1before = data.Tickets
local function withFailingSaves(fn)
	local saveFn = PlayerData.Save
	PlayerData.Save = function() return false end
	local r = fn()
	PlayerData.Save = saveFn
	return r
end
local d5 = withFailingSaves(function() return MPS.ProcessReceipt({ PlayerId = 101, ProductId = 1001, PurchaseId = "rcpt-4" }) end)
check("not confirmed while the save fails", d5 == NotYet)
local d6 = MPS.ProcessReceipt({ PlayerId = 101, ProductId = 1001, PurchaseId = "rcpt-4" })
check("retried later: granted once", d6 == Granted and data.Tickets == t1before + 1, data.Tickets - t1before)

-- 6. booster box
local dBox = MPS.ProcessReceipt({ PlayerId = 101, ProductId = 1449, PurchaseId = "rcpt-box" })
check("a Booster Box arrives sealed", dBox == Granted and data.SealedBoxes == 1)
local tokens0, packs0 = data.StarTokens, data.PacksOpened
local okBox, box = shop("OpenBox", { PackType = "Void" })
check("opening a box gives 12 Void packs + a topper", okBox and #box.Packs == 12 and #box.Packs[1] == 6 and box.Topper
	and data.SealedBoxes == 0, okBox and #box.Packs or box)
local CardDatabase = require(RS.CardDatabase)
local topper = okBox and CardDatabase.GetCard(box.Topper.CardId)
check("the topper is a Commander or Celestial in a shiny finish", topper and (topper.Type == "Commander" or topper.Type == "Celestial")
	and box.Topper.Finish ~= "Base", topper and topper.Type .. "/" .. box.Topper.Finish)
check("box packs count as 12 packs (tokens too)", data.StarTokens == tokens0 + 12 and data.PacksOpened == packs0 + 12)
local okBox2, msgBox2 = shop("OpenBox", { PackType = "Void" })
check("no sealed box, no opening", not okBox2, msgBox2)

-- 7. purchase log stays small
for i = 1, 260 do PlayerData.GrantPurchase(nik, "bulk-" .. i, "Ticket1") end
check("recent purchase ids are all remembered", #data.Purchases >= 260, #data.Purchases)
table.insert(data.Purchases, 1, { Id = "ancient", Product = "Ticket1", Time = os.time() - 200 * 86400 })
PlayerData.GrantPurchase(nik, "bulk-new", "Ticket1")
check("only very old purchase ids are forgotten", not PlayerData.HasPurchase(data, "ancient") and PlayerData.HasPurchase(data, "bulk-1"))

-- 8. restricted regions can't buy tickets/boxes
local restrictedFn = PlayerData.IsRestricted
PlayerData.IsRestricted = function() return true end
local okR, msgR = shop("BuyProduct", { Product = "Ticket1" })
check("restricted players can't buy tickets", not okR and msgR:find("region") ~= nil, msgR)
PlayerData.IsRestricted = restrictedFn

-- 9. the shop screens
local pg = nik.PlayerGui
local shopGui = pg:FindFirstChild("ShopGui")
shopGui.OpenShop:Fire("Packs")
M.run(1)
local ticketButton = shopGui:FindFirstChild("BuyWithTicket", true)
check("Packs tab has a ticket button", ticketButton ~= nil)
check("coin button shows packs left today", shopGui:FindFirstChild("BuyWithCoins", true) ~= nil
	and shopGui:FindFirstChild("BuyWithCoins", true).Text:find("left today") ~= nil)
shopGui:FindFirstChild("Tab_Boxes", true).Activated:Fire()
M.run(1)
local boxBuy = shopGui:FindFirstChild("Buy_BoosterBox", true)
check("Tickets & Boxes tab shows the products with Robux prices", boxBuy and boxBuy.Text == "R$ 1440", boxBuy and boxBuy.Text)
SHOTS.boxesTab = DUMP(shopGui, 1600, 900)
MPS.ProcessReceipt({ PlayerId = 101, ProductId = 1449, PurchaseId = "rcpt-box-2" })
M.run(1)
shopGui:FindFirstChild("OpenSealedBox", true).Activated:Fire()
M.run(0.5)
check("opening a box asks which boosters", shopGui:FindFirstChild("BoxPicker", true).Visible)
shopGui:FindFirstChild("BoxOf_Solar", true).Activated:Fire()
M.run(4)
local boxScreen = shopGui:FindFirstChild("BoxOpening", true)
check("the box screen opens with the topper", boxScreen.Visible and boxScreen:FindFirstChild("TopperCaption", true).Text ~= "",
	boxScreen:FindFirstChild("TopperCaption", true).Text)
SHOTS.boxTopper = DUMP(shopGui, 1600, 900)
shopGui:FindFirstChild("BoxNextPack", true).Activated:Fire()
M.run(1)
local reveal = shopGui:FindFirstChild("Reveal", true)
check("first pack of the box reveals", reveal.Visible and reveal:FindFirstChild("RevealTitle", true).Text:find("1/12") ~= nil,
	reveal:FindFirstChild("RevealTitle", true).Text)
shopGui:FindFirstChild("RevealDone", true).Activated:Fire()
M.run(3)
shopGui:FindFirstChild("RevealDone", true).Activated:Fire()
M.run(1)
check("back to the box after the pack", boxScreen.Visible and shopGui:FindFirstChild("BoxNextPack", true).Text:find("2 of 12") ~= nil,
	shopGui:FindFirstChild("BoxNextPack", true).Text)
shopGui:FindFirstChild("BoxShowAll", true).Activated:Fire()
M.run(2)
local cards = boxScreen:FindFirstChild("BoxCards", true)
local n = 0
for _, c in ipairs(cards:GetChildren()) do if c.Name:match("^BoxCard_") then n = n + 1 end end
check("every card: 72 pack cards + the topper", n == 73, n)
SHOTS.boxAll = DUMP(shopGui, 1600, 900)
shopGui:FindFirstChild("BoxNextPack", true).Activated:Fire()
M.run(1)
check("Done closes the box", not boxScreen.Visible)

check("no script errors", #M.errors == 0, M.errors[1])
return results
""")
for line in out.values():
    print(line)
fails = sum(1 for l in out.values() if l.startswith("FAIL"))
import sys
sys.path.insert(0, R + "test")
from render_gui import render
OUT = "/tmp/claude-0/-home-claude/3f999207-c8c9-5a40-855b-873d8eaf8301/scratchpad/all/"
def to_py(t):
    if lupa.lua_type(t) == "table":
        keys = list(t.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(t[k]) for k in sorted(keys)]
        return {k: to_py(v) for k, v in t.items()}
    return t
for name in ["boxesTab", "boxTopper", "boxAll"]:
    shot = G.SHOTS[name]
    if shot:
        render(to_py(shot), 1600, 900, OUT + name + ".png")
print(f"{fails} failed")
