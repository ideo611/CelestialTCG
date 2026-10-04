import sys, lupa
R="/home/claude/roblox/"; B=R+"build/"
lua=lupa.LuaRuntime(unpack_returned_tuples=True)
M=lua.execute(open(R+"test/mock.lua").read()); G=lua.globals(); G.M=M
G.SRC_DB=open(B+"ReplicatedStorage.CardDatabase.lua").read(); G.SRC_EN=open(B+"ServerScriptService.BattleEngine.lua").read(); G.SRC_BOT=open(B+"ServerScriptService.BattleBot.lua").read()
print(lua.execute(r"""
local RS=game:GetService("ReplicatedStorage"); local SSS=game:GetService("ServerScriptService")
M.addModule(RS,"CardDatabase",SRC_DB); M.addModule(SSS,"BattleEngine",SRC_EN); M.addModule(SSS,"BattleBot",SRC_BOT)
local DB=require(RS.CardDatabase); local E=require(SSS.BattleEngine); local Bot=require(SSS.BattleBot)
local function deck(n) local s=DB.StarterDecks[n] return {Commander=s.Commander,Celestial=s.Celestial,Cards=DB.ExpandCounts(s.Cards)} end
return function(A, Bn)
local dmg={ {Streak=0,Normal=0,Storm=0,Paid=0,Played={}}, {Streak=0,Normal=0,Storm=0,Paid=0,Played={}} }
local wins={0,0}
for g=1,200 do
  uidCard={}
  local b=E.new({Decks={deck(A),deck(Bn)},Seed=g,FirstPlayer=(g%2)+1})
  local function on(ev) for _,e in ipairs(ev) do
    if e.Type=="CommanderDamaged" then local d=dmg[3-e.Player]; if e.Streak then d.Streak=d.Streak+e.Amount else d.Normal=d.Normal+e.Amount end
      local cid=uidCard[e.Attacker or 0] or "?"; d.By=d.By or {}; d.By[cid]=(d.By[cid] or 0)+e.Amount
    elseif e.Type=="UnitPlayed" or e.Type=="CelestialSummoned" then uidCard[e.Uid]=e.CardId; if e.Type=="UnitPlayed" then local p=dmg[e.Player].Played; p[e.CardId]=(p[e.CardId] or 0)+1 end
    elseif e.Type=="StormDamage" then dmg[e.Player].Storm=dmg[e.Player].Storm+e.Amount
    elseif e.Type=="CommanderPaidHP" then dmg[e.Player].Paid=dmg[e.Player].Paid+e.Amount
    elseif e.Type=="UnitPlayed" or e.Type=="SpellCast" then local p=dmg[e.Player].Played; p[e.CardId]=(p[e.CardId] or 0)+1 end end end
  local guard=0
  while not b.Winner and guard<80 do guard=guard+1; Bot.TakeTurn(b,b.Current,on,nil) end
  if b.Winner then wins[b.Winner]=wins[b.Winner]+1 end
end
local out={}
for s=1,2 do local d=dmg[s]
 table.insert(out,("%s: wins %d  dealt streak %.1f normal %.1f /game; storm taken %.1f; paid %.1f"):format(s==1 and A or Bn,wins[s],d.Streak/200,d.Normal/200,d.Storm/200,d.Paid/200))
 local list={} for id,n in pairs(d.Played) do table.insert(list,{id,n}) end table.sort(list,function(a,b) return a[2]>b[2] end)
 local parts={} for i=1,math.min(12,#list) do table.insert(parts,DB.GetCard(list[i][1]).Name.."="..string.format("%.2f",list[i][2]/200)) end
 table.insert(out,"   plays/game: "..table.concat(parts,", "))
 local by={} for id,n in pairs(d.By or {}) do table.insert(by,{id,n}) end table.sort(by,function(a,b) return a[2]>b[2] end)
 local bp={} for i=1,math.min(10,#by) do local c=DB.GetCard(by[i][1]); table.insert(bp,(c and c.Name or by[i][1]).."="..string.format("%.1f",by[i][2]/200)) end
 table.insert(out,"   face dmg/game by: "..table.concat(bp,", "))
end
return table.concat(out,"\n")
end
""")(sys.argv[1],sys.argv[2]))
