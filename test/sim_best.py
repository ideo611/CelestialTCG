"""Best-decks tournament: builds the strongest deck it can for every Commander
(from the card lift measured in random-deck games, sim2.py) and plays them
against each other with the Hard bot on both sides.

python3 sim_best.py GAMES random1.json[,random2.json...] OUT_PREFIX
  writes OUT_PREFIX_decks.json and OUT_PREFIX_games.json, prints the report.
  SIM_PART=k/n plays only every n-th game starting at k (to run on several cores),
  SIM_DECKS_IN=path reuses decks already built (so the parts agree).
"""
import json, math, os, sys, time
import lupa

R = "/home/claude/roblox/"
B = R + "build/"
GAMES = int(sys.argv[1])
RANDOM = sys.argv[2].split(",")
OUT = sys.argv[3]
PART = os.environ.get("SIM_PART", "1/1")
PK, PN = (int(x) for x in PART.split("/"))

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
M = lua.execute(open(R + "test/mock.lua").read())
G = lua.globals(); G.M = M
G.SRC_DB = open(B + "ReplicatedStorage.CardDatabase.lua").read()
G.SRC_EN = open(B + "ServerScriptService.BattleEngine.lua").read()
G.SRC_BOT = open(B + "ServerScriptService.BattleBot.lua").read()
env = lua.execute(r"""
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
M.addModule(RS, "CardDatabase", SRC_DB)
M.addModule(SSS, "BattleEngine", SRC_EN)
M.addModule(SSS, "BattleBot", SRC_BOT)
return { DB = require(RS.CardDatabase), E = require(SSS.BattleEngine), Bot = require(SSS.BattleBot) }
""")
DB, E, Bot = env.DB, env.E, env.Bot

def to_py(t):
    if lupa.lua_type(t) == "table":
        keys = list(t.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(t[k]) for k in sorted(keys)]
        return {k: to_py(v) for k, v in t.items()}
    return t

cards = {c["Id"]: c for c in (to_py(x) for x in DB.GetAllCards().values())}
STAR_CAP = DB.Rules.StarCap
DECK = DB.Rules.DeckSize
def max_copies(cid):
    return DB.MaxCopiesFor(cid)
def main_type(cid):
    return DB.IsMainDeckType(cards[cid]["Type"])

# ---------- 1. learn from the random-deck games ----------
recs = []
for p in RANDOM:
    recs += json.load(open(p))
def seats(r):
    S = r["S"]
    return [(1, S[0]), (2, S[1])] if isinstance(S, list) else [(1, S["1"] if "1" in S else S[1]), (2, S["2"] if "2" in S else S[2])]
fac, cmd, cel = {}, {}, {}
card_in = {}
for r in recs:
    for s, info in seats(r):
        win = r["W"] == s
        f = info["Fa"]
        a = fac.setdefault(f, [0, 0]); a[0] += win; a[1] += 1
        a = cmd.setdefault(info["Cm"], [0, 0]); a[0] += win; a[1] += 1
        a = cel.setdefault((f, info["Ce"]), [0, 0]); a[0] += win; a[1] += 1
        for cid in info["D"]:
            a = card_in.setdefault((f, cid), [0, 0]); a[0] += win; a[1] += 1
def lift(f, cid):
    w, n = card_in.get((f, cid), [0, 0])
    fw, fn = fac[f]
    ow, on = fw - w, fn - n
    if n < 15 or on < 15:
        return 0.0, n
    return (w / n - ow / on), n

# ---------- 2. build the best deck for each Commander ----------
def build(cmd_id):
    f = cards[cmd_id]["Faction"]
    # Celestial: the best one for this faction (shrunk toward 50% when few games)
    best_cel, best_score = None, -9
    for (ff, ce), (w, n) in cel.items():
        if ff != f or ce not in cards:
            continue
        score = (w + 10) / (n + 20)
        if score > best_score:
            best_cel, best_score = ce, score
    pool = []
    for cid, c in cards.items():
        if not main_type(cid) or c["Faction"] not in (f, "Neutral"):
            continue
        if c.get("CommanderOnly") and c["CommanderOnly"] != cmd_id:
            continue
        l, n = lift(f, cid)
        shrunk = l * n / (n + 150)  # trust lifts measured over more decks
        if c.get("CommanderOnly") == cmd_id:
            shrunk += 0.01  # (its own signature card: random decks rarely had it with this Commander)
        pool.append((shrunk, cid))
    pool.sort(reverse=True)
    deck, stars = [], cards[best_cel]["StarCost"]
    pricey = 0
    for score, cid in pool:
        c = cards[cid]
        for _ in range(max_copies(cid)):
            if len(deck) >= DECK:
                break
            if c["EnergyCost"] >= 5 and pricey >= 6:
                break  # keep the curve playable: at most 6 cards costing 5+
            left = DECK - len(deck) - 1
            if stars + c["StarCost"] + left > STAR_CAP:
                break
            deck.append(cid); stars += c["StarCost"]
            if c["EnergyCost"] >= 5:
                pricey += 1
    # fill (shouldn't happen): cheapest legal cards
    if len(deck) < DECK:
        for score, cid in sorted(pool, key=lambda t: cards[t[1]]["StarCost"]):
            while len(deck) < DECK and deck.count(cid) < max_copies(cid):
                deck.append(cid)
    return {"Commander": cmd_id, "Celestial": best_cel, "Cards": deck, "Faction": f}

if os.environ.get("SIM_DECKS_IN"):
    decks = json.load(open(os.environ["SIM_DECKS_IN"]))
else:
    decks = [build(cid) for cid, c in cards.items() if c["Type"] == "Commander"]
    for d in decks:
        ok, errs = DB.ValidateDeck(d["Commander"], d["Celestial"], lua.table_from(d["Cards"]), "Zenith")[0:2]
        d["Legal"] = bool(ok)
    json.dump(decks, open(OUT + "_decks.json", "w"), indent=1)

# ---------- 3. the tournament ----------
pairs = [(a, b) for a in range(len(decks)) for b in range(len(decks)) if a != b]
play = lua.execute(r"""
return function(E, Bot) return function(d1, d2, seed, first)
	local played = { {}, {} }
	local battle = E.new({ Decks = { d1, d2 }, Seed = seed, FirstPlayer = first })
	local function on(events)
		for _, e in ipairs(events) do
			if (e.Type == "UnitPlayed" or e.Type == "SpellCast") and e.Player then played[e.Player][e.CardId] = true end
		end
	end
	local guard = 0
	while not battle.Winner and guard < 90 do
		guard = guard + 1
		Bot.TakeTurn(battle, battle.Current, on, nil)
	end
	local p = { {}, {} }
	for s = 1, 2 do for id in pairs(played[s]) do table.insert(p[s], id) end end
	return battle.Winner or 0, battle.Turn, p[1], p[2]
end end
""")(E, Bot)
def lua_deck(d):
    return lua.table_from({"Commander": d["Commander"], "Celestial": d["Celestial"], "Cards": lua.table_from(d["Cards"])})
LD = [lua_deck(d) for d in decks]
t0 = time.time()
games = []
for g in range(GAMES):
    if g % PN != PK - 1:
        continue
    a, b = pairs[g % len(pairs)]
    first = 1 if (g // len(pairs)) % 2 == 0 else 2
    try:
        w, turns, p1, p2 = play(LD[a], LD[b], 900001 + g * 13, first)
        games.append({"A": a, "B": b, "W": w, "T": turns, "F": first,
                      "P1": list(to_py(p1) or []), "P2": list(to_py(p2) or [])})
    except Exception as ex:
        games.append({"A": a, "B": b, "Err": str(ex)[:200]})
json.dump(games, open(OUT + f"_games_{PK}.json", "w"))
print(f"part {PART}: {len(games)} games in {time.time()-t0:.0f}s")
