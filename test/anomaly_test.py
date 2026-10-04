"""Checks every Anomaly against the real BattleEngine (no visuals)."""
import lupa, sys
R = "/home/claude/roblox/"
lua = lupa.LuaRuntime(unpack_returned_tuples=True)
M = lua.execute(open(R + "test/mock.lua").read()); G = lua.globals(); G.M = M
G.A = open(R + "build/ReplicatedStorage.CardDatabase.lua").read().replace("AnomaliesEnabled = false,", "AnomaliesEnabled = true,")  # test them even while switched off
G.E = open(R + "build/ServerScriptService.BattleEngine.lua").read()
out = lua.execute(r'''
local RS=game:GetService("ReplicatedStorage"); local SSS=game:GetService("ServerScriptService")
M.addModule(RS,"CardDatabase",A); M.addModule(SSS,"BattleEngine",E)
local DB=require(RS.CardDatabase); local Eng=require(SSS.BattleEngine)
local results = {}
local function check(name, ok, info) table.insert(results, (ok and "PASS " or "FAIL ") .. name .. (info and ("  -> " .. tostring(info)) or "")) end
local function deck(f)
  local s = DB.StarterDecks[f]; return { Commander = s.Commander, Celestial = s.Celestial, Cards = DB.ExpandCounts(s.Cards) }
end
-- fresh battle: seat 1 to move, seat 2 owns the Anomaly (set straight into its slot)
local function setup(anomaly, f2)
  local b = Eng.new({ Decks = { deck("Solar"), deck(f2 or "Lunar") }, Seed = 5, FirstPlayer = 1 })
  b:TakeStartEvents()
  for s = 1, 2 do local p = b.Players[s]; p.Hand = {}; p.MaxEnergy = 10; p.Energy = 10 end
  b.Players[2].Anomalies[1] = { CardId = anomaly }
  return b
end
local function unit(b, seat, lane, cardId, opts)
  local u = b:_newUnit(seat, cardId, false); u.SummonedTurn = -5
  for k, v in pairs(opts or {}) do u[k] = v end
  b.Players[seat].Lanes[lane] = u; return u
end
local function hand(b, seat, cardId) table.insert(b.Players[seat].Hand, cardId); return #b.Players[seat].Hand end
local function fired(events)
  for _, e in ipairs(events or {}) do if e.Type == "AnomalyTriggered" then return e.CardId end end
end

-- setting an Anomaly: costs AnomalyCost, hidden from the opponent
do
  local b = setup("NEU-002")
  local i = hand(b, 1, "SOL-023")
  local ok, ev = b:PlayCard(1, i, {})
  check("set: works", ok, ev)
  check("set: costs 2", b.Players[1].Energy == 8, b.Players[1].Energy)
  local f = Eng.FilterEvents(ev, 2)
  check("set: opponent can't see which", f[1].Type == "AnomalySet" and f[1].CardId == nil)
  local st = b:GetState(2)
  check("set: opponent's state hides the card", st.Players[1].Anomalies[1].Set and st.Players[1].Anomalies[1].CardId == nil)
  check("set: owner sees it", b:GetState(1).Players[1].Anomalies[1].CardId == "SOL-023")
  hand(b, 1, "SOL-024"); b:PlayCard(1, 1, {})
  local j = hand(b, 1, "NEU-002")
  local ok3, msg = b:PlayCard(1, j, {})
  check("set: only 2 slots", not ok3, msg)
  local c = b:CloneForSearch(2)
  check("clone for the opponent hides them", c.Players[1].Anomalies[1] == false)
  ok, ev = b:EndTurn(1)
  local mineFired = false
  for _, e in ipairs(ev) do if e.Type == "AnomalyTriggered" and e.Player == 1 then mineFired = true end end
  check("doesn't trigger on its owner's turn", not mineFired)
end

-- Sunflare Ambush: enemy unit played -> 2 damage
do
  local b = setup("SOL-023")
  local i = hand(b, 1, "LUN-016") -- Reef Guardian 2/3
  local ok, ev = b:PlayCard(1, i, { Lane = 2 })
  local u = b.Players[1].Lanes[2]
  check("Sunflare Ambush fires", fired(ev) == "SOL-023")
  check("Sunflare Ambush deals 2", u and u.HP == 1, u and u.HP)
  check("goes to graveyard", b.Players[2].Discard[#b.Players[2].Discard] == "SOL-023" and not b.Players[2].Anomalies[1])
end
-- Backdraft: attacker takes 3 before combat (a 3 HP attacker dies, no hit)
do
  local b = setup("SOL-024")
  local a = unit(b, 1, 1, "VOI-009") -- Rift Stalker 3/3
  local hp = b.Players[2].HP
  local ok, ev = b:EndTurn(1)
  check("Backdraft fires", fired(ev) == "SOL-024")
  check("Backdraft kills a 3 HP attacker before it hits", b.Players[1].Lanes[1] == nil and b.Players[2].HP == hp, b.Players[2].HP)
end
-- Supernova Snare: Celestial summoned -> 4 to it, 2 to their Commander
do
  local b = setup("SOL-025")
  local hp = b.Players[1].HP
  local ok, ev = b:SummonCelestial(1, 1)
  local c = b.Players[1].Lanes[1]
  check("Supernova Snare fires", fired(ev) == "SOL-025", ok)
  check("Supernova: Celestial takes 4", c and c.HP == c.MaxHP - 4, c and c.HP)
  check("Supernova: Commander takes 2", b.Players[1].HP == hp - 2, b.Players[1].HP)
end
-- Silver Veil: spell -> shields first (a damage spell gets blocked)
do
  local b = setup("LUN-024")
  local t = unit(b, 2, 1, "LUN-016")
  local i = hand(b, 1, "SOL-005") -- Solar Flare: 3 damage to a unit
  local ok, ev = b:PlayCard(1, i, { Target = { Side = "Enemy", Lane = 1 } })
  check("Silver Veil fires", fired(ev) == "LUN-024", ok)
  check("Silver Veil: shield took the hit", t.HP == t.MaxHP and not t.Shield, t.HP)
end
-- Tidal Reflection: own unit destroyed on enemy turn -> back to hand
do
  local b = setup("LUN-025")
  local t = unit(b, 2, 1, "LUN-001") -- Moonlit Wisp 1/2
  local i = hand(b, 1, "SOL-005")
  local ok, ev = b:PlayCard(1, i, { Target = { Side = "Enemy", Lane = 1 } })
  local h = b.Players[2].Hand
  check("Tidal Reflection fires", fired(ev) == "LUN-025")
  check("Tidal Reflection returns the card", h[#h] == "LUN-001", h[#h])
end
-- Moonlit Mirage: Commander attacked -> prevented + heal 2
do
  local b = setup("LUN-026")
  b.Players[2].HP = 15
  unit(b, 1, 1, "VOI-009")
  local ok, ev = b:EndTurn(1)
  check("Moonlit Mirage fires", fired(ev) == "LUN-026")
  check("Moonlit Mirage: no damage, healed 2", b.Players[2].HP == 17, b.Players[2].HP)
end
-- Spore Snare: unit played -> -1 Power, weakest friendly Grow 1
do
  local b = setup("NEB-024", "Nebula")
  local mine = unit(b, 2, 1, "NEB-001")
  local i = hand(b, 1, "VOI-009")
  local ok, ev = b:PlayCard(1, i, { Lane = 3 })
  local u = b.Players[1].Lanes[3]
  check("Spore Snare fires", fired(ev) == "NEB-024")
  check("Spore Snare: -1 Power", u.Power == 2, u.Power)
  check("Spore Snare: Grow on our weakest", mine.Grow >= 1, mine.Grow)
end
-- Seedfall: unit destroyed -> others Grow 1
do
  local b = setup("NEB-025", "Nebula")
  unit(b, 2, 1, "LUN-001"); local other = unit(b, 2, 2, "NEB-011")
  local g = other.Grow
  local i = hand(b, 1, "SOL-005")
  local ok, ev = b:PlayCard(1, i, { Target = { Side = "Enemy", Lane = 1 } })
  check("Seedfall fires", fired(ev) == "NEB-025")
  check("Seedfall: others get Grow", other.Grow == g + 1, other.Grow)
end
-- Bloom Burst: drops below 10 -> +1 Power all, heal 3
do
  local b = setup("NEB-026", "Nebula")
  b.Players[2].HP = 12
  local mine = unit(b, 2, 2, "LUN-016")
  unit(b, 1, 1, "VOI-009") -- hits for 3 -> 9
  local p = mine.Power
  local ok, ev = b:EndTurn(1)
  check("Bloom Burst fires", fired(ev) == "NEB-026")
  check("Bloom Burst: healed to 12, +1 Power", b.Players[2].HP == 12 and mine.Power == p + 1, b.Players[2].HP .. " " .. mine.Power)
end
-- Gravity Well: attacker -2 Power first
do
  local b = setup("VOI-024", "Void")
  unit(b, 1, 1, "SOL-018") -- Magma Brute 5/4
  local hp = b.Players[2].HP
  local ok, ev = b:EndTurn(1)
  check("Gravity Well fires", fired(ev) == "VOI-024")
  check("Gravity Well: hit for 3 instead of 5", b.Players[2].HP == hp - 3, hp - b.Players[2].HP)
end
-- Null Echo: ability -> 3 to their Commander, draw
do
  local b = setup("VOI-025", "Void")
  local t = unit(b, 1, 1, "SOL-004")
  local hp, hc = b.Players[1].HP, #b.Players[2].Hand
  local ok, ev = b:UseCommanderAbility(1, { Side = "Self", Lane = 1 })
  check("Null Echo fires", fired(ev) == "VOI-025", ok)
  check("Null Echo: 3 damage + draw", b.Players[1].HP == hp - 3 and #b.Players[2].Hand == hc + 1)
  check("Null Echo: the ability still works", t.TempPower == 2, t.TempPower)
end
-- Event Horizon: spell cancelled
do
  local b = setup("VOI-026", "Void")
  local t = unit(b, 2, 1, "LUN-016")
  local i = hand(b, 1, "SOL-005")
  local ok, ev = b:PlayCard(1, i, { Target = { Side = "Enemy", Lane = 1 } })
  check("Event Horizon fires", fired(ev) == "VOI-026", ok)
  check("Event Horizon: no damage, energy spent, spell in graveyard", t.HP == t.MaxHP and b.Players[1].Energy == 8
    and b.Players[1].Discard[#b.Players[1].Discard] == "SOL-005", t.HP)
end
-- Cold Snap: played unit skips its next attack
do
  local b = setup("COM-023", "Comet")
  local i = hand(b, 1, "SOL-001") -- Ember Scout (Rush?)
  local ok, ev = b:PlayCard(1, i, { Lane = 1 })
  local u = b.Players[1].Lanes[1]
  check("Cold Snap fires", fired(ev) == "COM-023")
  check("Cold Snap: frozen", u.Frozen == true and b:GetState(1).Players[1].Lanes[1].CanAttack == false)
  u.SummonedTurn = -5
  local hp = b.Players[2].HP
  b:EndTurn(1)
  check("frozen unit doesn't attack", b.Players[2].HP == hp and not u.Frozen, b.Players[2].HP)
  b:EndTurn(2)
  b:EndTurn(1)
  check("thawed unit attacks next time", b.Players[2].HP < hp, b.Players[2].HP)
end
-- Tripwire: attacker returned before hitting
do
  local b = setup("COM-024", "Comet")
  unit(b, 1, 1, "VOI-009")
  local hp = b.Players[2].HP
  local ok, ev = b:EndTurn(1)
  local h = b.Players[1].Hand
  check("Tripwire fires", fired(ev) == "COM-024")
  check("Tripwire: no damage, back in hand", b.Players[2].HP == hp and b.Players[1].Lanes[1] == nil, b.Players[2].HP)
end
-- Slingshot Orbit: Celestial frozen and -2 Power, stays on the board
do
  local b = setup("COM-025", "Comet")
  local cost = b:GetCelestialCost(1)
  local ok, ev = b:SummonCelestial(1, 1)
  local c = b.Players[1].Lanes[1]
  local printed = DB.GetCard(c.CardId).Power
  check("Slingshot fires", fired(ev) == "COM-025", ok)
  check("Slingshot: frozen and -2 Power, still on the board", c and c.Frozen and c.Power == printed - 2
    and b:GetCelestialCost(1) == cost, c and c.Power)
end
-- Static Mirage: enemy ends turn -> draw
do
  local b = setup("NEU-002")
  local hc = #b.Players[2].Hand
  local ok, ev = b:EndTurn(1)
  check("Static Mirage fires", fired(ev) == "NEU-002")
  check("Static Mirage: drew 2 (plus the turn draw)", #b.Players[2].Hand == hc + 3, #b.Players[2].Hand - hc)
end
return table.concat(results, "\n")
''')
print(out)
fails = out.count("FAIL")
print(f"\n{fails} failed")
sys.exit(1 if fails else 0)
