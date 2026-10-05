"""Finds dramatic bot-vs-bot games for TikTok and saves them as replays.

python3 tools/replays.py [games_per_scenario] [scenario ...]

Each scenario is a featured deck (seat 1) against the other starter decks,
with conditions (the featured card must show up, the featured side wins) and
a drama score (close finish, comeback, the featured card landing the final
blow...). The best games of each scenario are written to
build/ServerScriptService.ReplayLibrary.lua, which the Studio replay player
(ReplayServer) plays back on the real battle screen.

A replay = the decks, who went first, every random number the match used
(shuffles) and every move both sides made. Played back with the same random
numbers, the engine reproduces the game exactly.
"""
import sys, os, time, json
import lupa

R = "/home/claude/roblox/"
B = R + "build/"
N = int(sys.argv[1]) if len(sys.argv) > 1 else 60
ONLY = set(sys.argv[2:])
KEEP = 2  # best games kept per scenario

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
M = lua.execute(open(R + "test/mock.lua").read())
G = lua.globals()
G.M = M
G.SRC_DB = open(B + "ReplicatedStorage.CardDatabase.lua").read()
G.SRC_EN = open(B + "ServerScriptService.BattleEngine.lua").read()
G.SRC_BOT = open(B + "ServerScriptService.BattleBot.lua").read()

play = lua.execute(r"""
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
M.addModule(RS, "CardDatabase", SRC_DB)
M.addModule(SSS, "BattleEngine", SRC_EN)
M.addModule(SSS, "BattleBot", SRC_BOT)
local DB = require(RS.CardDatabase)
local BattleEngine = require(SSS.BattleEngine)
local BattleBot = require(SSS.BattleBot)

-- record every real (not planning) move both sides make
local ACTIONS = { "Mulligan", "PlayCard", "SummonCelestial", "UseCommanderAbility", "UseSpark", "EndTurn", "Concede" }
local probe = BattleEngine.new({ Decks = {
	{ Commander = DB.StarterDecks.Solar.Commander, Celestial = DB.StarterDecks.Solar.Celestial, Cards = DB.ExpandCounts(DB.StarterDecks.Solar.Cards) },
	{ Commander = DB.StarterDecks.Lunar.Commander, Celestial = DB.StarterDecks.Lunar.Celestial, Cards = DB.ExpandCounts(DB.StarterDecks.Lunar.Cards) },
} })
local Battle = getmetatable(probe).__index
for _, name in ipairs(ACTIONS) do
	local original = Battle[name]
	Battle[name] = function(self, seat, a, b)
		local rec = rawget(self, "_rec")
		if not rec or self.Searching or rec.Busy then
			return original(self, seat, a, b)
		end
		rec.Busy = true
		local ok, result = original(self, seat, a, b)
		rec.Busy = false
		if ok then
			local entry = { Kind = name, Seat = seat }
			if name == "PlayCard" then
				entry.Hand = a
				if type(b) == "table" then
					entry.Lane = b.Lane
					if b.Target then entry.Target = { Side = b.Target.Side, Lane = b.Target.Lane } end
					entry.Slot = b.Slot
				end
			elseif name == "SummonCelestial" then
				entry.Lane = a
			elseif name == "UseCommanderAbility" then
				if a then entry.Target = { Side = a.Side, Lane = a.Lane } end
			elseif name == "Mulligan" then
				entry.Picks = a
			end
			entry.Check = ("%d,%d,%d"):format(self.Players[1].HP, self.Players[2].HP, self.Turn)
			entry.Events = result
			table.insert(rec.Actions, entry)
		end
		return ok, result
	end
end

local function starter(name)
	local s = DB.StarterDecks[name]
	return { Commander = s.Commander, Celestial = s.Celestial, Counts = s.Cards }
end

-- a faction starter with a different Commander / Celestial and some cards added
-- (each added card replaces a copy of the most-copied Common)
local function buildDeck(spec)
	local base = DB.StarterDecks[spec.Base]
	local counts = {}
	for id, n in pairs(base.Cards) do counts[id] = n end
	for id, want in pairs(spec.Add or {}) do
		local guard = 0
		while (counts[id] or 0) < want and guard < 10 do
			guard = guard + 1
			local victim, most = nil, 0
			for vid, n in pairs(counts) do
				local card = DB.GetCard(vid)
				if n > 0 and not (spec.Add or {})[vid] and card.Rarity == "Common" and (n > most or (n == most and vid < victim)) then
					victim, most = vid, n
				end
			end
			if not victim then break end
			counts[victim] = counts[victim] - 1
			counts[id] = (counts[id] or 0) + 1
		end
	end
	local deck = {
		Commander = spec.Commander or base.Commander,
		Celestial = spec.Celestial or base.Celestial,
		Cards = DB.ExpandCounts(counts),
		Format = "Open",
	}
	table.sort(deck.Cards)
	local ok, errs = DB.ValidateDeck(deck.Commander, deck.Celestial, deck.Cards, "Open")
	assert(ok, (spec.Base or "?") .. " deck illegal: " .. table.concat(errs or {}, " "))
	return deck
end

local function lcg(seed)
	local state = seed % 2147483647
	if state <= 0 then state = state + 2147483646 end
	return function(n)
		state = (state * 48271) % 2147483647
		return (state % n) + 1
	end
end

CardName = function(id)
	local card = id and DB.GetCard(id)
	return card and card.Name or tostring(id)
end

-- one game; returns the record (or nil if it stalled)
return function(featured, opponentName, seed, first, difficulty)
	local decks = { buildDeck(featured), buildDeck({ Base = opponentName }) }
	local base = lcg(seed)
	local rngLog = {}
	local battle = BattleEngine.new({
		Decks = decks,
		FirstPlayer = first,
		Rng = function(n)
			local v = base(n)
			table.insert(rngLog, v)
			return v
		end,
	})
	local rec = { Actions = {} }
	battle._rec = rec
	local start = battle:TakeStartEvents()
	local guard = 0
	while not battle.Winner and guard < 90 do
		guard = guard + 1
		BattleBot.TakeTurn(battle, battle.Current, function() end, nil, difficulty)
	end
	if not battle.Winner then return nil end
	return {
		Decks = decks, First = first, Winner = battle.Winner, Turn = battle.Turn,
		HP = { battle.Players[1].HP, battle.Players[2].HP },
		Rng = rngLog, Actions = rec.Actions, Start = start,
	}
end
""")

# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------
STARTERS = ["Solar", "Lunar", "Nebula", "Void", "Comet"]

# what each scenario needs (checked against the featured seat's events)
SCENARIOS = [
    dict(id="malakar_oort", title="Malakar + Oort Reaper",
         blurb="Malakar, the Hollow King with Oort Reaper: the Reaper streaks in for the finish.",
         deck=dict(Base="Void", Commander="CMD-VOI-01", Celestial="CEL-13", Add={"VOI-020": 2}),
         need=["summon"], star=["CEL-13"], ability=True),
    dict(id="ignara_reignite", title="Ignara's Reignite",
         blurb="Ignara, the Forge-Mother sets the board on fire twice.",
         deck=dict(Base="Solar", Commander="CMD-SOL-02", Add={"SOL-011": 2}),
         need=["ability"], star=[], ability=True),
    dict(id="great_comet", title="The Great Comet",
         blurb="The Great Comet (Legendary) streaks past everything.",
         deck=dict(Base="Comet", Add={"COM-022": 1, "COM-019": 2}), need=["play:COM-022"], star=["COM-022"]),
    dict(id="heart_of_the_sun", title="Heart of the Sun",
         blurb="An 8/8 with Rush: Heart of the Sun (Legendary) closes it out.",
         deck=dict(Base="Solar", Add={"SOL-013": 1, "SOL-011": 1}), need=["play:SOL-013"], star=["SOL-013"]),
    dict(id="night_sovereign", title="Night Sovereign",
         blurb="Night Sovereign (Legendary) decays everything across from it.",
         deck=dict(Base="Void", Add={"VOI-022": 1, "VOI-019": 2}), need=["play:VOI-022"], star=["VOI-022"]),
    dict(id="moon_leviathan", title="Moon Leviathan",
         blurb="Moon Leviathan (Legendary): the 12-HP wall that turns a game around.",
         deck=dict(Base="Lunar", Add={"LUN-013": 1, "LUN-011": 2}), need=["play:LUN-013"], star=["LUN-013"]),
    dict(id="first_light", title="The First Light",
         blurb="The First Light (Legendary) grows into a monster.",
         deck=dict(Base="Nebula", Add={"NEB-022": 1, "NEB-019": 2}), need=["play:NEB-022"], star=["NEB-022"]),
    dict(id="flare_stallion", title="Flare Stallion reveal",
         blurb="Captain Sol Varro's Celestial, Flare Stallion, charges in with Rush.",
         deck=dict(Base="Solar"), need=["summon"], star=["CEL-04"]),
    dict(id="moonveil", title="Moonveil Jellyfish reveal",
         blurb="Tidekeeper Selene's Celestial, Moonveil Jellyfish, holds the line.",
         deck=dict(Base="Lunar"), need=["summon"], star=["CEL-05"]),
    dict(id="skywhale", title="Aurora Skywhale reveal",
         blurb="Seraphine's Celestial, Aurora Skywhale, grows every turn.",
         deck=dict(Base="Nebula"), need=["summon"], star=["CEL-12"]),
    dict(id="pulsar", title="Pulsar Remnant reveal",
         blurb="Nyx's Celestial, Pulsar Remnant, decays and grows.",
         deck=dict(Base="Void"), need=["summon"], star=["CEL-11"]),
    dict(id="oort_halley", title="Halley Voss + Oort Reaper",
         blurb="Halley Voss, Comet Rider and Oort Reaper: Streak straight at the Commander.",
         deck=dict(Base="Comet"), need=["summon"], star=["CEL-13"]),
    dict(id="black_sun", title="Black Sun Harbinger reveal",
         blurb="Captain Sol Varro calls the Black Sun Harbinger.",
         deck=dict(Base="Solar", Celestial="CEL-09"), need=["summon"], star=["CEL-09"]),
    dict(id="umbra", title="Umbra, the Eclipse Wyrm reveal",
         blurb="Tidekeeper Selene summons Umbra, the Eclipse Wyrm.",
         deck=dict(Base="Lunar", Celestial="CEL-06"), need=["summon"], star=["CEL-06"]),
    dict(id="kessa", title="Kessa Frostwake",
         blurb="Kessa Frostwake's ability, game after game.",
         deck=dict(Base="Comet", Commander="CMD-COM-02"), need=["ability"], star=[], ability=True),
    dict(id="lyra", title="Lyra, the Night Archivist",
         blurb="Lyra, the Night Archivist runs the Lunar deck.",
         deck=dict(Base="Lunar", Commander="CMD-LUN-02"), need=["ability"], star=[], ability=True),
    dict(id="orion", title="Orion, the Cloud Sage",
         blurb="Orion, the Cloud Sage leads the Nebula deck.",
         deck=dict(Base="Nebula", Commander="CMD-NEB-02"), need=["ability"], star=[], ability=True),
    dict(id="cosmic_storm", title="Cosmic Storm finish",
         blurb="Both sides hang on until the Cosmic Storm decides it.",
         deck=dict(Base="Lunar"), need=["storm_kill"], star=[]),
]


def to_py(t):
    if lupa.lua_type(t) == "table":
        keys = list(t.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(t[k]) for k in sorted(keys)]
        return {k: to_py(v) for k, v in t.items()}
    return t


def analyse(rec):
    """What happened, from seat 1's side (the featured deck)."""
    uid_card = {}
    info = dict(plays=set(), summons=0, abilities=0, killer=None, storm_kill=False,
                hp_line=[], moments={}, kill_round=None)
    hp = [20, 20]
    for a in rec["Actions"]:
        rnd = (int(a["Check"].split(",")[2]) + 1) // 2
        for e in a.get("Events") or []:
            t = e.get("Type")
            if t in ("UnitPlayed", "CelestialSummoned") and e.get("Uid"):
                uid_card[e["Uid"]] = e.get("CardId")
            if e.get("Player") == 1 and t in ("UnitPlayed", "SpellCast", "CelestialSummoned"):
                info["plays"].add(e.get("CardId"))
                info["moments"].setdefault(e.get("CardId"), rnd)
            if e.get("Player") == 1 and t == "CelestialSummoned":
                info["summons"] += 1
            if e.get("Player") == 1 and t == "CommanderAbility":
                info["abilities"] += 1
            if t in ("CommanderDamaged", "StormDamage", "CommanderHealed", "CommanderPaidHP") and e.get("HP") is not None:
                hp[e["Player"] - 1] = e["HP"]
                info["hp_line"].append(hp[0] - hp[1])
            if t == "CommanderDamaged" and e.get("Player") == 2 and (e.get("HP") or 1) <= 0:
                info["killer"] = uid_card.get(e.get("Attacker"))
                info["kill_round"] = rnd
            if t == "StormDamage" and (e.get("HP") or 1) <= 0:
                info["storm_kill"] = True
    return info


def score(sc, rec):
    if rec["Winner"] != 1:
        return None
    info = analyse(rec)
    for need in sc["need"]:
        if need == "summon" and info["summons"] == 0:
            return None
        if need == "ability" and info["abilities"] < 1:
            return None
        if need.startswith("play:") and need[5:] not in info["plays"]:
            return None
        if need == "storm_kill" and not info["storm_kill"]:
            return None
    for star in sc["star"]:
        if star not in info["plays"]:
            return None
    rounds = (rec["Turn"] + 1) // 2
    winner_hp = rec["HP"][0]
    s = 0.0
    s += max(0, 8 - winner_hp) * 3          # close: the winner barely survived
    worst = min(info["hp_line"] or [0])
    s += max(0, -worst) * 1.5              # comeback: how far behind they were
    if info["killer"] in sc["star"]:
        s += 15                            # the featured card lands the final blow
    if sc.get("ability"):
        s += min(info["abilities"], 4) * 2
    if 5 <= rounds <= 10:
        s += 6                             # a good length for a short video
    elif rounds > 13:
        s -= (rounds - 13) * 2
    return s, info, rounds, winner_hp


def name(card_id):
    return G.CardName(card_id)


def summary(sc, opp, whp, rounds, info):
    parts = [f"Beats the {opp} deck on {whp} HP in round {rounds}"]
    for star in sc["star"]:
        if star in info["moments"]:
            parts.append(f"{name(star)} comes in round {info['moments'][star]}")
    if info["killer"]:
        parts.append(f"final blow: {name(info['killer'])}")
    if info["storm_kill"]:
        parts.append("Cosmic Storm finish")
    if sc.get("ability"):
        parts.append(f"ability used {info['abilities']}x")
    return ", ".join(parts)


def lua_value(v, indent=""):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(int(v)) if float(v).is_integer() else repr(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ", ".join(lua_value(x) for x in v) + "}"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            key = k if isinstance(k, str) and k.isidentifier() else "[" + lua_value(k) + "]"
            parts.append(f"{key} = {lua_value(x)}")
        return "{" + ", ".join(parts) + "}"
    if v is None:
        return "nil"
    raise TypeError(type(v))


def compact_action(a):
    out = {"K": a["Kind"], "S": a["Seat"], "C": a["Check"]}
    for src, dst in (("Hand", "H"), ("Lane", "L"), ("Slot", "Sl"), ("Picks", "P")):
        if a.get(src) is not None:
            out[dst] = a[src]
    if a.get("Target"):
        out["T"] = [a["Target"]["Side"], a["Target"]["Lane"]]
    return out


def main():
    started = time.time()
    library = []
    for sc in SCENARIOS:
        if ONLY and sc["id"] not in ONLY:
            continue
        found = []
        opponents = [s for s in STARTERS if s != sc["deck"]["Base"]] or STARTERS
        deck_lua = lua.table_from({k: (lua.table_from(v) if isinstance(v, dict) else v) for k, v in sc["deck"].items()})
        for g in range(N):
            opp = opponents[g % len(opponents)]
            first = 1 + (g // len(opponents)) % 2
            seed = 1000 + g * 7919 + sum(ord(c) * 31 for c in sc["id"])
            try:
                rec = play(deck_lua, opp, seed, first, "Hard")
            except Exception as err:  # noqa
                print("  error:", str(err)[:200])
                continue
            if rec is None:
                continue
            rec = to_py(rec)
            result = score(sc, rec)
            if result:
                s, info, rounds, whp = result
                found.append((s, g, opp, rounds, whp, info, rec))
        found.sort(key=lambda x: -x[0])
        print(f"{sc['id']:18s} {len(found):3d}/{N} qualifying", end="")
        for s, g, opp, rounds, whp, info, rec in found[:KEEP]:
            print(f" | {s:.0f}pts vs {opp} r{rounds} hp{whp} killer={info['killer']}", end="")
            library.append(dict(
                Id=f"{sc['id']}_{len(library) + 1}",
                Title=sc["title"],
                Blurb=sc["blurb"],
                Summary=summary(sc, opp, whp, rounds, info),
                Score=round(s),
                Decks=rec["Decks"], First=rec["First"], Winner=rec["Winner"],
                Rng=",".join(str(v) for v in rec["Rng"]),
                Actions=[compact_action(a) for a in rec["Actions"]],
            ))
        print()
    lines = [
        "--[[",
        "\tReplayLibrary (ModuleScript)",
        "\tLocation: ServerScriptService > ReplayLibrary",
        "",
        "\tGenerated by tools/replays.py: dramatic bot-vs-bot games for videos,",
        "\tplayed back in Studio by ReplayServer. Don't edit by hand; rerun the tool.",
        "\tEach replay: Decks, First (who went first), Rng (every random number the",
        "\tmatch used), Actions (every move: K = kind, S = seat, H = hand index,",
        "\tL = lane, T = target {side, lane}, C = 'hp1,hp2,turn' after the move).",
        "]]",
        "",
        "return {",
    ]
    for r in library:
        lines.append("\t" + lua_value(r) + ",")
    lines.append("}")
    path = B + "ServerScriptService.ReplayLibrary.lua"
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{len(library)} replays -> {path} ({os.path.getsize(path) // 1024} KB) in {time.time() - started:.0f}s")


if __name__ == "__main__":
    main()
