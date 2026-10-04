"""Outlier finder: bot-vs-bot games between RANDOM legal decks.

Because every deck is random, a card's "lift" (win rate of decks that run it
minus decks of the same faction that don't) is a fair, controlled estimate of
how strong the card is. Also reports Commanders, Celestials, factions, and
win rate when a card is actually played.

python3 sim2.py GAMES [rules_json] [out.json]
  rules_json e.g. '{"GrowTiming":"StartOfTurn","MaxGrow":2}'
"""
import json, math, os, sys, time
import lupa

R = "/home/claude/roblox/"
B = R + "build/"
GAMES = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
RULES = json.loads(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2] else {}
OUT = sys.argv[3] if len(sys.argv) > 3 else None
CARDS_OVERRIDE = json.loads(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else {}

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
M = lua.execute(open(R + "test/mock.lua").read())
G = lua.globals(); G.M = M
G.SRC_DB = open(B + "ReplicatedStorage.CardDatabase.lua").read()
G.SIM_SEED = int(os.environ.get("SIM_SEED", "12345"))
if os.environ.get("SIM_DECKS"):
    _fixed = json.load(open(os.environ["SIM_DECKS"]))
    _ft = lua.table()
    for _f, _d in _fixed.items():
        _ft[_f] = lua.table_from({"Commander": _d["Commander"], "Celestial": _d["Celestial"],
                                  "Cards": lua.table_from(_d["Cards"]), "Faction": _f})
    G.FIXED_DECKS = _ft
G.SRC_EN = open(B + "ServerScriptService.BattleEngine.lua").read()
G.SRC_BOT = open(B + "ServerScriptService.BattleBot.lua").read()
setup = lua.execute(r"""
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
M.addModule(RS, "CardDatabase", SRC_DB)
M.addModule(SSS, "BattleEngine", SRC_EN)
M.addModule(SSS, "BattleBot", SRC_BOT)
local DB = require(RS.CardDatabase)
local E = require(SSS.BattleEngine)
local Bot = require(SSS.BattleBot)
local FACTIONS = { "Solar", "Lunar", "Nebula", "Void", "Comet" }

local function setRules(t)
	for k, v in pairs(t) do DB.Rules[k] = v end
end
-- card stat overrides: { ["NEB-001"] = { Power = 1, Keywords = { Grow = 1 } } }
local function setCards(t)
	for id, fields in pairs(t) do
		local card = DB.GetCard(id)
		for k, v in pairs(fields) do card[k] = v end
	end
end

local rng = Random.new(SIM_SEED or 12345)
local pools, commanders, celestials = {}, {}, {}
for _, f in ipairs(FACTIONS) do pools[f] = {} commanders[f] = {} celestials[f] = {} end
for _, card in ipairs(DB.GetAllCards()) do
	if card.Type == "Commander" then
		table.insert(commanders[card.Faction], card.Id)
	elseif card.Type == "Celestial" then
		for _, f in ipairs(card.PairsWith) do table.insert(celestials[f], card.Id) end
	elseif DB.IsMainDeckType(card.Type) then -- (skips Anomalies while they're switched off)
		for _, f in ipairs(FACTIONS) do
			if (card.Faction == f or card.Faction == "Neutral") then
				table.insert(pools[f], card.Id)
			end
		end
	end
end

local function randomDeck(faction)
	if FIXED_DECKS and FIXED_DECKS[faction] then
		local d = FIXED_DECKS[faction]
		assert(DB.ValidateDeck(d.Commander, d.Celestial, d.Cards), "fixed deck illegal: " .. faction)
		return d
	end
	for _ = 1, 200 do
		local cmd = commanders[faction][rng:NextInteger(1, #commanders[faction])]
		local cel = celestials[faction][rng:NextInteger(1, #celestials[faction])]
		local cards, copies, stars = {}, {}, DB.GetCard(cel).StarCost
		local pool = pools[faction]
		local tries = 0
		while #cards < 30 and tries < 500 do
			tries = tries + 1
			local id = pool[rng:NextInteger(1, #pool)]
			local card = DB.GetCard(id)
			local ok = (copies[id] or 0) < DB.MaxCopiesFor(card) and (not card.CommanderOnly or card.CommanderOnly == cmd)
			-- leave room so the stars still fit
			local left = 30 - #cards - 1
			if ok and stars + card.StarCost + left <= DB.Rules.StarCap then
				copies[id] = (copies[id] or 0) + 1
				stars = stars + card.StarCost
				table.insert(cards, id)
			end
		end
		if #cards == 30 and DB.ValidateDeck(cmd, cel, cards) then
			return { Commander = cmd, Celestial = cel, Cards = cards, Faction = faction }
		end
	end
	error("couldn't build a deck for " .. faction)
end

return function(games, rules, cards)
	setRules(rules)
	setCards(cards)
	local out = {}
	for g = 1, games do
		local decks = {}
		for s = 1, 2 do decks[s] = randomDeck(FACTIONS[rng:NextInteger(1, 5)]) end
		local played = { {}, {}, }
		local ok, err = pcall(function()
			local battle = E.new({ Decks = decks, Seed = g * 7 + 3 + (SIM_SEED or 0) * 100003, FirstPlayer = (g % 2) + 1 })
			local function on(events)
				for _, e in ipairs(events) do
					if (e.Type == "UnitPlayed" or e.Type == "SpellCast" or e.Type == "AnomalySet") and e.Player then
						played[e.Player][e.CardId] = true
					end
				end
			end
			local guard = 0
			while not battle.Winner and guard < 90 do
				guard = guard + 1
				Bot.TakeTurn(battle, battle.Current, on, nil)
			end
			local rec = { W = battle.Winner or 0, T = battle.Turn, F = battle.Stats.FirstPlayer, S = {} }
			for s = 1, 2 do
				local counts = {}
				for _, id in ipairs(decks[s].Cards) do counts[id] = (counts[id] or 0) + 1 end
				local p = {}
				for id in pairs(played[s]) do table.insert(p, id) end
				rec.S[s] = { Fa = decks[s].Faction, Cm = decks[s].Commander, Ce = decks[s].Celestial, D = counts, P = p }
			end
			table.insert(out, rec)
		end)
		if not ok then
			table.insert(out, { Err = tostring(err) })
		end
	end
	return out
end
""")

t0 = time.time()
CHUNK = 250
records = []
def to_py(t):
    if lupa.lua_type(t) == "table":
        keys = list(t.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(t[k]) for k in sorted(keys)]
        return {k: to_py(v) for k, v in t.items()}
    return t
def to_lua(v):
    if isinstance(v, dict):
        t = lua.table()
        for kk, vv in v.items(): t[kk] = to_lua(vv)
        return t
    if isinstance(v, list):
        t = lua.table()
        for i, vv in enumerate(v): t[i + 1] = to_lua(vv)
        return t
    return v
rules_lua = lua.table_from(RULES)
cards_lua = lua.table()
for cid, fields in CARDS_OVERRIDE.items():
    ft = lua.table()
    for k, v in fields.items():
        ft[k] = to_lua(v)
    cards_lua[cid] = ft
done = 0
MERGE = os.environ.get("SIM_MERGE")
if MERGE:
    GAMES = 0
    for path in MERGE.split(","):
        records += json.load(open(path))
while done < GAMES:
    n = min(CHUNK, GAMES - done)
    records += to_py(setup(n, rules_lua, cards_lua))
    done += n
errors = [r for r in records if "Err" in r]
records = [r for r in records if "Err" not in r and r["W"] in (1, 2)]
avg_t = sum(r["T"] for r in records) / max(1, len(records))
print(f"{len(records)} games in {time.time()-t0:.0f}s, avg turns {avg_t:.1f}, errors {len(errors)}", (errors[0]["Err"][:300] if errors else ""))
if OUT:
    json.dump(records, open(OUT, "w"))

# ---------- analysis ----------
def wilson(w, n, z=1.96):
    if n == 0: return (0, 1)
    p = w / n; d = 1 + z*z/n; c = p + z*z/(2*n); r = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n))
    return ((c - r)/d, (c + r)/d)

fac = {}
for r in records:
    for s in (1, 2):
        f = r["S"][s-1]["Fa"] if isinstance(r["S"], list) else r["S"][s]["Fa"]
        a = fac.setdefault(f, [0, 0]); a[1] += 1; a[0] += r["W"] == s
print("\nFaction win rates (random decks, all opponents):")
for f, (w, n) in sorted(fac.items(), key=lambda kv: -kv[1][0]/kv[1][1]):
    print(f"  {f:7s} {w/n*100:5.1f}%  ({n} decks)")

def seats(r):
    S = r["S"]
    return [(1, S[0]), (2, S[1])] if isinstance(S, list) else [(1, S[1]), (2, S[2])]

def leaders(key):
    stat = {}
    for r in records:
        for s, info in seats(r):
            a = stat.setdefault(info[key], [0, 0]); a[1] += 1; a[0] += r["W"] == s
    return stat
for key, title in (("Cm", "Commanders"), ("Ce", "Celestials")):
    print(f"\n{title}:")
    for cid, (w, n) in sorted(leaders(key).items(), key=lambda kv: -kv[1][0]/kv[1][1]):
        lo, hi = wilson(w, n)
        print(f"  {cid:11s} {w/n*100:5.1f}%  ({lo*100:4.1f}-{hi*100:4.1f}, n={n})")

# card lift within faction: decks with >=1 copy vs decks of that faction without
names = {}
cards = {}
for r in records:
    for s, info in seats(r):
        f = info["Fa"]; win = r["W"] == s
        for cid in info["D"]:
            c = cards.setdefault((f, cid), {"in": [0, 0], "played": [0, 0], "copies": 0})
            c["in"][1] += 1; c["in"][0] += win; c["copies"] += info["D"][cid]
        for cid in (info["P"] or []):
            c = cards.setdefault((f, cid), {"in": [0, 0], "played": [0, 0], "copies": 0})
            c["played"][1] += 1; c["played"][0] += win
rows = []
for (f, cid), c in cards.items():
    fw, fn = fac[f]
    w, n = c["in"]
    if n < 30 or cid.startswith("NEU"):
        continue
    ow, on = fw - w, fn - n   # same faction decks without the card
    if on < 30: continue
    p1, p0 = w / n, ow / on
    se = math.sqrt(p1*(1-p1)/n + p0*(1-p0)/on)
    pw, pn = c["played"]
    rows.append((cid, f, p1 - p0, (p1 - p0) / se if se else 0, n, pw / pn if pn else 0, c["copies"] / n))
rows.sort(key=lambda r: -r[2])
print("\nCards by lift (win rate with the card minus without, same faction):")
print("  card        faction  lift    z     decks  played-WR  avg copies")
for cid, f, lift, z, n, pwr, cp in rows[:20]:
    print(f"  {cid:11s} {f:7s} {lift*100:+5.1f}  {z:+5.1f}  {n:6d}  {pwr*100:5.1f}%     {cp:.2f}")
print("  ...")
for cid, f, lift, z, n, pwr, cp in rows[-10:]:
    print(f"  {cid:11s} {f:7s} {lift*100:+5.1f}  {z:+5.1f}  {n:6d}  {pwr*100:5.1f}%     {cp:.2f}")
if OUT:
    json.dump({"rows": rows, "fac": fac}, open(OUT.replace(".json", "_summary.json"), "w"))
