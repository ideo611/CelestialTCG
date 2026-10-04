import lupa
R="/home/claude/roblox/"; B=R+"build/"
lua=lupa.LuaRuntime(unpack_returned_tuples=True)
M=lua.execute(open(R+"test/mock.lua").read()); G=lua.globals(); G.M=M
G.SRC_DB=open(B+"ReplicatedStorage.CardDatabase.lua").read(); G.SRC_EN=open(B+"ServerScriptService.BattleEngine.lua").read()
print(lua.execute(r"""
local RS=game:GetService("ReplicatedStorage"); local SSS=game:GetService("ServerScriptService")
M.addModule(RS,"CardDatabase",SRC_DB); M.addModule(SSS,"BattleEngine",SRC_EN)
local DB=require(RS.CardDatabase); local E=require(SSS.BattleEngine)
local function deck(n) local s=DB.StarterDecks[n] return {Commander=s.Commander,Celestial=s.Celestial,Cards=DB.ExpandCounts(s.Cards)} end
local b=E.new({Decks={deck("Void"),deck("Solar")},Seed=1,FirstPlayer=1})
local out={}
-- put a 3-power Solar unit in enemy lane 1 and a 1-power unit in lane 2
local u=b:_newUnit(2,"SOL-007",false); b.Players[2].Lanes[1]=u
local w=b:_newUnit(2,"SOL-014",false); b.Players[2].Lanes[2]=w
b.Players[1].Energy=10
table.insert(b.Players[1].Hand,"VOI-007"); table.insert(b.Players[1].Hand,"VOI-007"); table.insert(b.Players[1].Hand,"VOI-007")
local function idx() for i,c in ipairs(b.Players[1].Hand) do if c=="VOI-007" then return i end end end
local ok=b:PlayCard(1,idx(),{Target={Side="Enemy",Lane=1}}); table.insert(out,"Wither on 4-power Lancer: "..tostring(ok).." -> power "..u.Power)
ok=b:PlayCard(1,idx(),{Target={Side="Enemy",Lane=1}}); table.insert(out,"Wither again: "..tostring(ok).." -> power "..u.Power)
local ok2,msg=b:PlayCard(1,idx(),{Target={Side="Enemy",Lane=1}}); table.insert(out,"Wither on 1-power: "..tostring(ok2).." "..tostring(msg).." power "..u.Power)
local ok3,msg3=b:PlayCard(1,idx(),{Target={Side="Enemy",Lane=2}}); table.insert(out,"Wither on 1-power Sprite: "..tostring(ok3).." "..tostring(msg3))
b:_applyEffect(1,{Kind="WeakenAllEnemies",Amount=1},nil,"test"); table.insert(out,"Lantern-Bearer effect: lancer "..u.Power.." sprite "..w.Power)
return table.concat(out,"\n")
"""))
