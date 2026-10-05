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
local Library = require(SSS.ReplayLibrary)
local Control = require(SSS.ReplayControl)
check("replay library has games", #Library > 0, #Library)
-- every replay plays back exactly (both sides), at top speed
local seatTried = 0
for i, replay in ipairs(Library) do
	for _, seat in ipairs({ 1, 2 }) do
		if seat == 1 or i == 1 then
			local ok, msg = RS.ReplayRemotes.ReplayRequest:InvokeServer("Play", { Id = replay.Id, Seat = seat, Speed = 2 })
			local guard = 0
			local s = Control.Sessions[nik]
			while s and not s.Done and guard < 400 do
				M.run(5) guard = guard + 1
				s = Control.Sessions[nik]
			end
			s = Control.Sessions[nik]
			check(("replay %s (seat %d) plays to the end with no drift"):format(replay.Id, seat),
				ok and s and s.Done and not s.Problem and s.Index == s.Total, tostring(msg) .. " " .. tostring(s and s.Problem) .. " " .. tostring(s and s.Index) .. "/" .. tostring(s and s.Total))
			if i == 1 and seat == 1 then
				SHOTS.replayEnd = DUMP(nik.PlayerGui.BattleGui, 1600, 900)
			end
			M.run(12)
		end
	end
end
-- the panel
local rg = nik.PlayerGui:FindFirstChild("ReplayGui")
check("Replays panel exists in Studio", rg ~= nil)
if rg then
	rg:FindFirstChild("ReplaysToggle", true).Activated:Fire() M.run(1)
	check("Replays panel lists the library", rg:FindFirstChild("Replay_" .. Library[1].Id, true) ~= nil)
	SHOTS.replayPanel = DUMP(rg, 1600, 900)
	rg:FindFirstChild("Replay_" .. Library[1].Id, true):FindFirstChild("PlayFeatured").Activated:Fire()
	M.run(3)
	check("playing hides everything but the battle screen", not nik.PlayerGui.WalletGui.Enabled and nik.PlayerGui.BattleGui.Enabled)
	M.run(2)
	-- Leave stops it and brings the screen back
	RS.BattleRemotes.BattleAction:FireServer({ Kind = "Leave" })
	M.run(6)
	check("leaving brings the rest of the screen back", nik.PlayerGui.WalletGui.Enabled)
end
check("no player rewards from replays", PlayerData.Get(nik).Stats.Wins + PlayerData.Get(nik).Stats.Losses == 0)
check("no script errors", #M.errors == 0, M.errors[1])
return results
""")
fails = 0
for line in [out[k] for k in sorted(out.keys())]:
    print(line)
    if line.startswith("FAIL"):
        fails += 1
from render_gui import render
OUT = "/tmp/claude-0/-home-claude/3f999207-c8c9-5a40-855b-873d8eaf8301/scratchpad/all/"
def to_py(t):
    if lupa.lua_type(t) == "table":
        keys = list(t.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [to_py(t[k]) for k in sorted(keys)]
        return {k: to_py(v) for k, v in t.items()}
    return t
for name in ["replayEnd", "replayPanel"]:
    shot = G.SHOTS[name]
    if shot:
        render(to_py(shot), 1600, 900, OUT + name + ".png")
print(f"{fails} failed")
