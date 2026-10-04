--[[
	BattleBot (ModuleScript)
	Location: ServerScriptService > BattleBot

	A simple practice opponent. On its turn it summons its Celestial when it
	can, plays its most expensive affordable cards, aims damage at enemy
	units and buffs at its own, then ends its turn.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))

local LANES = CardDatabase.Rules.Lanes

local BattleBot = {}

-- Tries one action. Returns true, events if something was played.
local function tryOneAction(battle, seat)
	local state = battle:GetState(seat)
	local me = state.Players[seat]

	local emptyLane, ownTarget
	for lane = 1, LANES do
		if not me.Lanes[lane] and not emptyLane then
			emptyLane = lane
		end
		if me.Lanes[lane] and not ownTarget then
			ownTarget = { Side = "Self", Lane = lane }
		end
	end

	if not me.StarGate.OnBoard and emptyLane and me.StarGate.Cost <= me.Energy then
		local ok, events = battle:SummonCelestial(seat, emptyLane)
		if ok then
			return true, events
		end
	end

	local order = {}
	for i, cardId in ipairs(me.Hand) do
		table.insert(order, { Index = i, Card = CardDatabase.GetCard(cardId) })
	end
	table.sort(order, function(a, b)
		return a.Card.EnergyCost > b.Card.EnergyCost
	end)
	for _, entry in ipairs(order) do
		local card = entry.Card
		local attempts
		if card.Type == "Unit" then
			attempts = { { Lane = emptyLane } }
		elseif card.Effect.Kind == "DamageUnit" then
			attempts = {}
			for lane = 1, LANES do
				table.insert(attempts, { Target = { Side = "Enemy", Lane = lane } })
			end
		elseif card.Effect.Target then
			attempts = {}
			for lane = 1, LANES do
				table.insert(attempts, { Target = { Side = "Self", Lane = lane } })
			end
		else
			attempts = { {} }
		end
		for _, options in ipairs(attempts) do
			local ok, events = battle:PlayCard(seat, entry.Index, options)
			if ok then
				return true, events
			end
		end
	end

	if me.HasSpark and state.Turn >= 4 then
		local ok, events = battle:UseSpark(seat)
		if ok then
			return true, events
		end
	end

	if not me.AbilityUsed then
		local effect = CardDatabase.GetCard(me.CommanderId).CommanderAbility.Effect
		local targets = {}
		if effect.Kind == "DamageUnit" then
			-- damage: finish off a unit first, then break a Shield, then hit the strongest
			local enemy = state.Players[3 - seat]
			local scored = {}
			for lane = 1, LANES do
				local unit = enemy.Lanes[lane]
				if unit then
					local score = unit.Power or 0
					if not unit.Shield and unit.HP <= effect.Amount then
						score = score + 100
					elseif unit.Shield then
						score = score + 50
					end
					table.insert(scored, { Lane = lane, Score = score })
				end
			end
			table.sort(scored, function(a, b)
				return a.Score > b.Score
			end)
			for _, entry in ipairs(scored) do
				table.insert(targets, { Side = "Enemy", Lane = entry.Lane })
			end
		elseif effect.Target then
			if ownTarget then
				for lane = 1, LANES do
					table.insert(targets, { Side = "Self", Lane = lane })
				end
			end
		else
			targets = { false } -- no target needed
		end
		for _, target in ipairs(targets) do
			local ok, events = battle:UseCommanderAbility(seat, target or nil)
			if ok then
				return true, events
			end
		end
	end

	return false
end

-- Plays out the bot's whole turn.
-- onEvents(events) is called after every action; pause() runs between actions.
function BattleBot.TakeTurn(battle, seat, onEvents, pause)
	for _ = 1, 20 do
		if battle.Winner or battle.Current ~= seat then
			return
		end
		local ok, events = tryOneAction(battle, seat)
		if not ok then
			break
		end
		onEvents(events)
		if pause then
			pause()
		end
	end
	if battle.Winner or battle.Current ~= seat then
		return
	end
	local ok, events = battle:EndTurn(seat)
	if ok then
		onEvents(events)
	end
end

return BattleBot