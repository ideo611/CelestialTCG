"""Runs Spectate (server) + SpectateClient (client) against real battles
played by the bot, checks for errors and remote problems, and renders the
spectator view and a TV face to PNGs."""
import json, os, sys
import lupa
from render_gui import render

R = "/home/claude/roblox/"
OLD = R + "_old/"
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/-home-claude/3f999207-c8c9-5a40-855b-873d8eaf8301/scratchpad"
os.makedirs(OUT, exist_ok=True)

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
M = lua.execute(open(R + "test/mock.lua").read())
read = lambda p: open(p).read()

card_art = read(OLD + "eb72d8fa-CardArt.lua").replace(
    "return CardArt", "function CardArt.MythicFrameFor() return nil end\nreturn CardArt")
building_stub = """
local Building = {}
local ORIGIN = Vector3.new(0, 0, -50)
Building.Origin = ORIGIN
Building.TablePositions = {}
for i, x in ipairs({ -24, -8, 8, 24 }) do Building.TablePositions[i] = ORIGIN + Vector3.new(x, 0.4, 2) end
return Building
"""
lua.globals().SRC = {
    "CardDatabase": read(OLD + "e0b71141-CardDatabase.lua"),
    "CardArt": card_art,
    "CardVisuals": read(R + "ReplicatedStorage/CardVisuals.lua"),
    "Playmats": read(OLD + "d9336044-Playmats.lua"),
    "BattleEngine": read(OLD + "b3995dbd-BattleEngine.lua"),
    "BattleBot": read(OLD + "8570162a-BattleBot.lua"),
    "CardShopBuilding": building_stub,
    "Spectate": read(R + "ServerScriptService/Spectate.lua"),
    "SpectateClient": read(R + "StarterPlayerScripts/SpectateClient.lua"),
    "dumpgui": read(R + "test/dumpgui.lua"),
}
lua.globals().M = M

result = lua.execute(r"""
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
for _, n in ipairs({ "CardDatabase", "CardArt", "CardVisuals", "Playmats" }) do M.addModule(RS, n, SRC[n]) end
for _, n in ipairs({ "BattleEngine", "BattleBot", "CardShopBuilding", "Spectate" }) do M.addModule(SSS, n, SRC[n]) end
local dump = load(SRC.dumpgui)(M)

local me = M.addPlayer("Nik", 1)
local other = M.addPlayer("Watcher2", 2)
M.LocalPlayer = me
rawget(game:GetService("Players"), "__props").LocalPlayer = me

local Spectate, BattleEngine, BattleBot, CardDatabase
task.spawn(function()
	Spectate = require(SSS.Spectate)
	BattleEngine = require(SSS.BattleEngine)
	BattleBot = require(SSS.BattleBot)
	CardDatabase = require(RS.CardDatabase)
end)
M.run(0.2)
assert(Spectate, "Spectate didn't load")
assert(#workspace.SpectateTVs:GetChildren() == 4, "expected 4 TVs")

M.runScript("SpectateClient", SRC.SpectateClient)
M.run(1)

local function deckOf(name)
	local s = CardDatabase.StarterDecks[name]
	return { Commander = s.Commander, Celestial = s.Celestial, Cards = CardDatabase.ExpandCounts(s.Cards) }
end

-- Play a whole bot-vs-bot game on table 2, telling Spectate after every action
local function playGame(tableIndex, seed, names, stopAtTurn)
	local battle = BattleEngine.new({ Decks = { deckOf("Solar"), deckOf("Solar") }, Seed = seed })
	local info = { Names = names, Mats = { "MAT-SOL-STARTER", "MAT-LUN-STARTER" }, BestOf = 3, Game = 2, Wins = { 1, 0 },
		Finishes = { { ["CMD-SOL-01"] = "Holo" }, {} } }
	info.Events = battle:TakeStartEvents()
	Spectate.Update(tableIndex, battle, info)
	local guard = 0
	while not battle.Winner and guard < 80 and (not stopAtTurn or battle.Turn < stopAtTurn) do
		guard = guard + 1
		local seat = battle.Current
		BattleBot.TakeTurn(battle, seat, function(events)
			info.Events = events
			Spectate.Update(tableIndex, battle, info)
		end, function() task.wait(0.3) end)
	end
	return battle
end

local battle
task.spawn(function() battle = playGame(2, 7, { "Nik", "Practice Bot" }, 9) end)
M.run(60)
assert(battle, "game didn't run")

local tv2 = workspace.SpectateTVs.TV2
local snapCount = 0
for _, entry in ipairs(M.remoteLog) do if entry.Remote == "TableUpdate" then snapCount = snapCount + 1 end end

-- TVs near the camera get drawn
workspace.CurrentCamera.CFrame = CFrame.new(tv2.Screen.Position + Vector3.new(0, -5, 20))
M.run(1)
local pg = me.PlayerGui
local tvGui = pg:FindFirstChild("SpectateTV2_Front")
assert(tvGui, "TV gui missing")
local tvList = dump(tvGui, 540, 300)
local farGui = pg:FindFirstChild("SpectateTV4_Front")
local farDrawn = #farGui.Board:GetChildren()

-- the prompt opens the spectator view
assert(tv2.Screen.WatchPrompt.Enabled, "prompt should be on during a match")
tv2.Screen.WatchPrompt.Triggered:Fire(me)
M.run(0.5)
local view = pg.SpectateGui
assert(view.Enabled, "spectator view didn't open")
local viewList = dump(view, 1600, 900)
local phoneList = dump(view, 844, 390)

-- finish the game, check the winner screen
task.spawn(function()
	local guard = 0
	while not battle.Winner and guard < 80 do
		guard = guard + 1
		BattleBot.TakeTurn(battle, battle.Current, function(events)
			Spectate.Update(2, battle, { Names = { "Nik", "Practice Bot" }, Events = events,
				Mats = { "MAT-SOL-STARTER", "MAT-LUN-STARTER" }, BestOf = 3, Game = 2, Wins = { 1, 0 } })
		end, function() task.wait(0.3) end)
	end
end)
M.run(120)
local winList = dump(view, 1600, 900)

-- second table starts; Next table + stop
local battle2
task.spawn(function() battle2 = playGame(4, 11, { "Alex", "Sam" }, 4) end)
M.run(20)
local listButton = pg:FindFirstChild("LiveGames", true)
local hudWhileWatching = pg.SpectateButtonGui.Enabled

-- table resets: view goes to waiting screen
Spectate.Closed(2)
M.run(1)
local waitingList = dump(view, 1600, 900)
local waitingHasNext = view.Root:FindFirstChild("Waiting") and view.Root.Waiting:FindFirstChild("NextTable") ~= nil

view.Root.Waiting.NextTable.Activated:Fire()
M.run(1)
local nowWatching4 = view.Root:FindFirstChild("TopBar") ~= nil

view.Root.TopBar.StopWatching.Activated:Fire()
M.run(1)
local closed = not view.Enabled
local hudBack = pg.SpectateButtonGui.Enabled
listButton.Activated:Fire()
M.run(0.2)
local listItems = #pg.SpectateButtonGui.LiveList:GetChildren()

-- your own match closes the view
local br = Instance.new("Folder"); br.Name = "BattleRemotes"
local bu = Instance.new("RemoteEvent"); bu.Name = "BattleUpdate"; bu.Parent = br
br.Parent = RS
M.run(1)
pg.SpectateButtonGui.LiveList.Watch4.Activated:Fire()
M.run(0.5)
local openedAgain = view.Enabled
bu:FireClient(me, { Kind = "Match" })
M.run(0.5)
local closedByMatch = not view.Enabled
local hudHiddenInMatch = not pg.SpectateButtonGui.Enabled
bu:FireClient(me, { Kind = "Closed" })
M.run(0.5)

-- leaving players don't break counts
M.removePlayer(other)
M.run(1)

return {
	errors = #M.errors, problems = #M.remoteProblems, warnings = #M.warnings,
	snapCount = snapCount, winner = battle.Winner, turns = battle.Turn,
	farDrawn = farDrawn, hudWhileWatching = hudWhileWatching, waitingHasNext = waitingHasNext,
	nowWatching4 = nowWatching4, closed = closed, hudBack = hudBack, listItems = listItems,
	openedAgain = openedAgain, closedByMatch = closedByMatch, hudHiddenInMatch = hudHiddenInMatch,
	lamp = tostring(tv2.LiveLamp.Color.R),
	tv = tvList, view = viewList, phone = phoneList, win = winList, waiting = waitingList,
	problemList = M.remoteProblems, errorList = M.errors,
}
""")


def to_py(t):
    if lupa.lua_type(t) == "table":
        keys = list(t.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(t[k]) for k in sorted(keys)]
        return {k: to_py(v) for k, v in t.items()}
    return t


res = to_py(result)
for k in ["errors", "problems", "warnings", "snapCount", "winner", "turns", "farDrawn", "hudWhileWatching",
          "waitingHasNext", "nowWatching4", "closed", "hudBack", "listItems", "openedAgain", "closedByMatch",
          "hudHiddenInMatch", "lamp"]:
    print(k, res.get(k))
for p in (res.get("problemList") or [])[:10]:
    print("PROBLEM", p)
for e in (res.get("errorList") or [])[:5]:
    print("ERROR", e)
render(res["tv"], 540, 300, OUT + "/spectate_tv.png")
render(res["view"], 1600, 900, OUT + "/spectate_view.png")
render(res["phone"], 844, 390, OUT + "/spectate_phone.png")
render(res["win"], 1600, 900, OUT + "/spectate_winner.png")
render(res["waiting"], 1600, 900, OUT + "/spectate_waiting.png")
print("rendered to", OUT)
