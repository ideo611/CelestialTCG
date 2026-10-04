"""Bot-vs-bot simulations between the starter decks (or custom decks).
python3 sim.py [games_per_side] [deck names...]"""
import sys, math, json, itertools
import lupa
R = "/home/claude/roblox/"
B = R + "build/"
N = int(sys.argv[1]) if len(sys.argv) > 1 else 200
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
M = lua.execute(open(R + "test/mock.lua").read())
G = lua.globals(); G.M = M
G.SRC_DB = open(B + "ReplicatedStorage.CardDatabase.lua").read()
G.SRC_EN = open(B + "ServerScriptService.BattleEngine.lua").read()
G.SRC_BOT = open(B + "ServerScriptService.BattleBot.lua").read()
EXTRA = sys.argv[2] if len(sys.argv) > 2 else ""
run = lua.execute(r"""
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
M.addModule(RS, "CardDatabase", SRC_DB)
M.addModule(SSS, "BattleEngine", SRC_EN)
M.addModule(SSS, "BattleBot", SRC_BOT)
local CardDatabase = require(RS.CardDatabase)
local BattleEngine = require(SSS.BattleEngine)
local BattleBot = require(SSS.BattleBot)
for name, d in pairs(CardDatabase.StarterDecks) do
	local ok, errs, stars = CardDatabase.ValidateDeck(d.Commander, d.Celestial, CardDatabase.ExpandCounts(d.Cards))
	print(("starter %-7s legal=%s stars=%d %s"):format(name, tostring(ok), stars, ok and "" or table.concat(errs, " ")))
end
local function deckOf(spec)
	if type(spec) == "string" then
		local s = CardDatabase.StarterDecks[spec]
		return { Commander = s.Commander, Celestial = s.Celestial, Cards = CardDatabase.ExpandCounts(s.Cards) }
	end
	return spec
end
return function(a, b, games, seed0)
	local res = { AWins = 0, Turns = 0, Storm = 0, FirstWins = 0, Errors = 0, Draws = 0 }
	for g = 1, games do
		local first = (g % 2) + 1
		local ok, err = pcall(function()
			local battle = BattleEngine.new({ Decks = { deckOf(a), deckOf(b) }, Seed = seed0 + g, FirstPlayer = first })
			local guard = 0
			while not battle.Winner and guard < 80 do
				guard = guard + 1
				BattleBot.TakeTurn(battle, battle.Current, function() end, nil)
			end
			if not battle.Winner then
				res.Draws = res.Draws + 1
				return
			end
			if battle.Winner == 1 then res.AWins = res.AWins + 1 end
			if battle.Winner == first then res.FirstWins = res.FirstWins + 1 end
			res.Turns = res.Turns + battle.Turn
			if battle.Stats.StormKill then res.Storm = res.Storm + 1 end
		end)
		if not ok then
			res.Errors = res.Errors + 1
			if res.Errors == 1 then print("ERROR: " .. tostring(err)) end
		end
	end
	return res
end
""")
names = ["Solar", "Lunar", "Nebula", "Void", "Comet"]
def wilson(w, n, z=1.96):
    if n == 0: return (0, 0)
    p = w / n; d = 1 + z*z/n; c = p + z*z/(2*n); r = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n))
    return ((c - r)/d, (c + r)/d)
table = {}
overall = {n: [0, 0] for n in names}
for i, a in enumerate(names):
    for b in names[i:]:
        r = run(a, b, N, 1000 * (i + 1) + names.index(b) * 7)
        games = N - r.Errors - r.Draws
        aw = r.AWins
        lo, hi = wilson(aw, games)
        if a != b:
            overall[a][0] += aw; overall[a][1] += games
            overall[b][0] += games - aw; overall[b][1] += games
        print(f"{a:>7} vs {b:<7} {aw/games*100:5.1f}% ({lo*100:4.1f}-{hi*100:4.1f})  turns {r.Turns/games:4.1f}  "
              f"first-player {r.FirstWins/games*100:4.1f}%  storm {r.Storm/games*100:4.1f}%  errors {r.Errors} draws {r.Draws}")
print()
for n in names:
    w, g = overall[n]
    print(f"{n:>7}: {w/g*100:5.1f}% overall vs other factions")
