"""Spectator animations: a bot-vs-bot game on table 2 while Nik watches full
screen. Checks events arrive with snapshots, animations run (pop numbers,
spell cards, cards landing) with no errors, and renders a mid-animation frame."""
import os, sys
import lupa
from render_gui import render

R = "/home/claude/roblox/"
B = R + "build/"
OUT = "/tmp/claude-0/-home-claude/3f999207-c8c9-5a40-855b-873d8eaf8301/scratchpad/all"
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
M = lua.execute(open(R + "test/mock.lua").read())
read = lambda p: open(p).read()
building_stub = """
local Building = {}
local ORIGIN = Vector3.new(0, 0, -50)
Building.Origin = ORIGIN
Building.TablePositions = {}
for i, x in ipairs({ -24, -8, 8, 24 }) do Building.TablePositions[i] = ORIGIN + Vector3.new(x, 0.4, 2) end
return Building
"""
G = lua.globals()
G.M = M
src = {}
for n in ["CardDatabase", "CardArt", "CardVisuals", "UiAssets", "Playmats"]:
    src[n] = read(B + "ReplicatedStorage." + n + ".lua")
for n in ["BattleEngine", "BattleBot", "Spectate"]:
    src[n] = read(B + "ServerScriptService." + n + ".lua")
src["CardShopBuilding"] = building_stub
src["SpectateClient"] = read(B + "StarterPlayer.StarterPlayerScripts.SpectateClient.lua")
src["dumpgui"] = read(R + "test/dumpgui.lua")
G.SRC = lua.table_from(src)
res = lua.execute(r"""
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
for _, n in ipairs({ "CardDatabase", "CardArt", "CardVisuals", "UiAssets", "Playmats" }) do M.addModule(RS, n, SRC[n]) end
for _, n in ipairs({ "BattleEngine", "BattleBot", "CardShopBuilding", "Spectate" }) do M.addModule(SSS, n, SRC[n]) end
local dump = load(SRC.dumpgui)(M)
local me = M.addPlayer("Nik", 1)
M.LocalPlayer = me
rawget(game:GetService("Players"), "__props").LocalPlayer = me
local Spectate, BattleEngine, BattleBot, CardDatabase
task.spawn(function()
	Spectate = require(SSS.Spectate)
	BattleEngine = require(SSS.BattleEngine)
	BattleBot = require(SSS.BattleBot)
	CardDatabase = require(RS.CardDatabase)
	Spectate.Setup(4)
end)
M.run(0.2)
M.runScript("SpectateClient", SRC.SpectateClient)
M.run(1)
local pg = me.PlayerGui

local function deckOf(name)
	local s = CardDatabase.StarterDecks[name]
	return { Commander = s.Commander, Celestial = s.Celestial, Cards = CardDatabase.ExpandCounts(s.Cards) }
end
local out = { pops = 0, casts = 0, lands = 0, events = 0, frames = {} }
-- watch table 2 before the game starts
local tv2 = workspace.SpectateTVs.TV2
tv2.Screen.WatchPrompt.Triggered:Fire(me)
M.run(0.3)

-- count animation pieces as they appear
local seen = {}
task.spawn(function()
	while true do
		for _, d in ipairs(pg.SpectateGui:GetDescendants()) do
			if not seen[d] then
				seen[d] = true
				if d.Name == "Pop" then out.pops = out.pops + 1 end
				if d.Name == "CastCard" then
					out.casts = out.casts + 1
					if #out.frames < 1 then table.insert(out.frames, dump(pg.SpectateGui, 1600, 900)) end
				end
				if d:IsA("UIScale") then out.lands = out.lands + 1 end
			end
		end
		task.wait(0.05)
	end
end)

local battle
task.spawn(function()
	battle = BattleEngine.new({ Decks = { deckOf("Comet"), deckOf("Void") }, Seed = 3 })
	local info = { Names = { "Alex", "Sam" }, Mats = { "MAT-COMET-TRAIL", "MAT-EVENT-HORIZON" } }
	info.Events = battle:TakeStartEvents()
	Spectate.Update(2, battle, info)
	local guard = 0
	while not battle.Winner and guard < 40 do
		guard = guard + 1
		BattleBot.TakeTurn(battle, battle.Current, function(events)
			info.Events = events
			Spectate.Update(2, battle, info)
		end, function() task.wait(0.8) end)
	end
end)
M.run(240)
for _, entry in ipairs(M.remoteLog) do
	if entry.Remote == "TableUpdate" then
		local snap = entry.Args[1] and entry.Args[1].Snapshot
		if snap and snap.Events then out.events = out.events + #snap.Events end
	end
end
out.winner = battle and battle.Winner
out.errors = M.errors
out.problems = M.remoteProblems
out.final = dump(pg.SpectateGui, 1600, 900)
return out
""")
def to_py(t):
    if lupa.lua_type(t) == "table":
        keys = list(t.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(t[k]) for k in sorted(keys)]
        return {k: to_py(v) for k, v in t.items()}
    return t
r = to_py(res)
print("winner", r.get("winner"), "events sent", r["events"], "pops", r["pops"], "spell cards", r["casts"], "scales", r["lands"])
print("errors", len(r.get("errors") or []), (r.get("errors") or [""])[0][:600])
print("remote problems", len(r.get("problems") or []), (r.get("problems") or [""])[:2])
if r["frames"]:
    render(r["frames"][0], 1600, 900, OUT + "/spectateCast.png")
render(r["final"], 1600, 900, OUT + "/spectateFinal.png")
