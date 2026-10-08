--[[
	BattleBot (ModuleScript)
	Location: ServerScriptService > BattleBot

	The practice opponent. It plans each turn by trying its options on a
	private copy of the match and looking ahead:
	  - every card it can play (each lane, each target), its Celestial, its
	    Commander's ability and the Spark
	  - for each, it plays the rest of its turn forward: the combat when it
	    ends its turn, then the other side's attacks back, and scores the board
	    that's left (Commander HP, units, keywords, open lanes, cards in hand)
	  - it also checks the best follow-up for its top few moves, so it can set
	    up combos (a buff before an attack, removal before a unit lands)
	It never looks at your hand, your deck or your face-down Anomalies: it
	only sees what you'd see.
	BattleBot.TakeTurnSimple is the old one-step bot (kept for comparisons).

	Two difficulties for practice: "Normal" (the default, an easier bot that
	plays like a beginner, BattleBot.TakeTurnEasy) and "Hard" (the planner).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))

local LANES = CardDatabase.Rules.Lanes

local BattleBot = {}

-- Effects that hurt whatever they target (aimed at enemy units)
local HARMFUL = { DamageUnit = true, Destroy = true, Weaken = true }

local function partsOf(effect)
	if effect.Kind == "Multi" then
		return effect.Effects
	end
	return { effect }
end

local function isHarmful(effect)
	for _, part in ipairs(partsOf(effect)) do
		if HARMFUL[part.Kind] or (part.Kind == "ReturnToHand" and part.Target == "EnemyUnit") then
			return true
		end
	end
	return false
end

-- Enemy lanes, best target first: units it can finish, then Shields, then the strongest
local function enemyTargets(state, seat, effect)
	local amount = 0
	for _, part in ipairs(partsOf(effect)) do
		if part.Kind == "DamageUnit" then
			amount = part.Amount
		elseif part.Kind == "Destroy" then
			amount = 999
		end
	end
	local enemy = state.Players[3 - seat]
	local scored = {}
	for lane = 1, LANES do
		local unit = enemy.Lanes[lane]
		if unit then
			local score = (unit.Power or 0) * 2 + (unit.HP or 0)
			if amount > 0 and not unit.Shield and unit.HP <= amount then
				score = score + 100
			elseif unit.Shield and amount > 0 and amount < 999 then
				score = score + 30
			end
			table.insert(scored, { Lane = lane, Score = score })
		end
	end
	table.sort(scored, function(a, b)
		return a.Score > b.Score
	end)
	local targets = {}
	for _, entry in ipairs(scored) do
		table.insert(targets, { Side = "Enemy", Lane = entry.Lane })
	end
	return targets
end

-- Own lanes worth helping, strongest first (skips pointless picks)
local function friendlyTargets(state, seat, effect)
	local me = state.Players[seat]
	local enemy = state.Players[3 - seat]
	local list = {}
	for lane = 1, LANES do
		local unit = me.Lanes[lane]
		if unit then
			local useful = true
			if effect.Kind == "ReturnToHand" then
				-- only rescue a badly hurt unit
				useful = unit.HP * 2 <= unit.MaxHP and not unit.IsCelestial
			elseif effect.Kind == "GiveStreak" then
				useful = unit.CanAttack and enemy.Lanes[lane] and not unit.Streak and (unit.Power or 0) > 0
			end
			if useful then
				table.insert(list, { Lane = lane, Power = unit.Power or 0 })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Power > b.Power
	end)
	local targets = {}
	for _, entry in ipairs(list) do
		table.insert(targets, { Side = "Self", Lane = entry.Lane })
	end
	return targets
end

-- Every target worth trying for an effect (false = no target needed)
local function targetsFor(state, seat, effect)
	if not effect.Target then
		if effect.Kind == "DamageAllUnits" then
			-- only when it hurts the enemy more than it hurts us
			local function score(seatNo)
				local total = 0
				for lane = 1, LANES do
					local unit = state.Players[seatNo].Lanes[lane]
					if unit and not unit.Shield and unit.HP <= effect.Amount then
						total = total + (unit.Power or 0) + unit.HP
					end
				end
				return total
			end
			if score(3 - seat) > score(seat) then
				return { false }
			end
			return {}
		end
		if effect.Kind == "StreakAllFriendly" then
			-- only when something is blocked
			local me, enemy = state.Players[seat], state.Players[3 - seat]
			for lane = 1, LANES do
				local unit = me.Lanes[lane]
				if unit and unit.CanAttack and enemy.Lanes[lane] then
					return { false }
				end
			end
			return {}
		end
		return { false }
	end
	if effect.Target == "EnemyUnit" or (effect.Target == "AnyUnit" and isHarmful(effect)) then
		return enemyTargets(state, seat, effect)
	end
	return friendlyTargets(state, seat, effect)
end

-- Tries one action. Returns true, events if something was played.
local function tryOneAction(battle, seat)
	local state = battle:GetState(seat)
	local me = state.Players[seat]

	local emptyLane
	for lane = 1, LANES do
		if not me.Lanes[lane] and not emptyLane then
			emptyLane = lane
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
		-- don't pay HP when it's running low
		local hpCost = card.HPCost or 0
		if card.EnergyCost <= me.Energy and (hpCost == 0 or me.HP > hpCost + 6) then
			local attempts = {}
			if card.Type == "Unit" then
				if emptyLane then
					attempts = { { Lane = emptyLane } }
				end
			else
				for _, target in ipairs(targetsFor(state, seat, card.Effect)) do
					table.insert(attempts, { Target = target or nil })
				end
			end
			for _, options in ipairs(attempts) do
				local ok, events = battle:PlayCard(seat, entry.Index, options)
				if ok then
					return true, events
				end
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
		local ability = CardDatabase.GetCard(me.CommanderId).CommanderAbility
		local effect = ability.Effect
		local worthIt = true
		if effect.Kind == "PayForEnergy" then
			-- only if the extra energy lets it play something it can't afford now
			worthIt = false
			if me.HP > effect.HP + 8 then
				local energyAfter = me.Energy - ability.EnergyCost + effect.Energy
				for _, cardId in ipairs(me.Hand) do
					local cost = CardDatabase.GetCard(cardId).EnergyCost
					if cost > me.Energy and cost <= energyAfter then
						worthIt = true
					end
				end
			end
		end
		if worthIt then
			for _, target in ipairs(targetsFor(state, seat, effect)) do
				local ok, events = battle:UseCommanderAbility(seat, target or nil)
				if ok then
					return true, events
				end
			end
		end
	end

	return false
end

-- Plays out the bot's whole turn.
-- onEvents(events) is called after every action; pause() runs between actions.
-- Opening hand: send back expensive cards (5+ energy), and if nothing is
-- cheap enough to play early, the most expensive card left too.
function BattleBot.ChooseMulligan(battle, seat)
	local hand = battle.Players[seat].Hand
	local picks, cheap = {}, false
	local worst, worstCost = nil, -1
	for i, cardId in ipairs(hand) do
		local cost = CardDatabase.GetCard(cardId).EnergyCost or 0
		if cost >= 5 then
			table.insert(picks, i)
		else
			if cost <= 2 then
				cheap = true
			end
			if cost > worstCost then
				worst, worstCost = i, cost
			end
		end
	end
	if not cheap and worst then
		table.insert(picks, worst)
	end
	return picks
end

function BattleBot.TakeTurnSimple(battle, seat, onEvents, pause)
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

---------------------------------------------------------------------
-- The Normal (easier) bot: the default practice opponent
-- Plays like a beginner: it plays cards it can afford in no special order,
-- puts units in a random open lane, picks targets loosely, doesn't save the
-- Spark for the right moment (never uses it), and sometimes ends its turn
-- with energy left over. Still plays its Celestial and Commander ability, so
-- it shows new players everything the game does.
---------------------------------------------------------------------
-- Easy (the default) is gentler still: it often stops after a card or two,
-- rarely uses its ability, aims almost at random, and doesn't always bring
-- out its Celestial the moment it can.
BattleBot.Difficulties = { "Easy", "Normal", "Hard" }
BattleBot.DefaultDifficulty = "Easy"
local LEVELS = {
	Normal = {
		StopChance = 0.12,     -- after each play, chance it just ends its turn
		AbilityChance = 0.5,   -- chance it uses its Commander ability when it could
		SloppyTarget = 0.35,   -- chance it aims at a random target instead of the best
		CelestialChance = 1,   -- chance it summons its Celestial when it can
		MaxPlays = 20,         -- most cards it plays in a turn
	},
	Easy = {
		StopChance = 0.35,
		AbilityChance = 0.2,
		SloppyTarget = 0.8,
		CelestialChance = 0.5,
		MaxPlays = 2,
	},
}
local EASY = LEVELS.Normal -- (the level of the turn being played)

local easyRng = Random.new()

local function shuffled(list)
	for i = #list, 2, -1 do
		local j = easyRng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function looseTargets(state, seat, effect)
	local targets = targetsFor(state, seat, effect)
	if #targets > 1 and easyRng:NextNumber() < EASY.SloppyTarget then
		shuffled(targets)
	end
	return targets
end

local function tryEasyAction(battle, seat, playedSomething)
	if playedSomething and easyRng:NextNumber() < EASY.StopChance then
		return false
	end
	local state = battle:GetState(seat)
	local me = state.Players[seat]
	local open = {}
	for lane = 1, LANES do
		if not me.Lanes[lane] then
			table.insert(open, lane)
		end
	end
	shuffled(open)

	if not me.StarGate.OnBoard and #open > 0 and me.StarGate.Cost <= me.Energy
		and easyRng:NextNumber() < (EASY.CelestialChance or 1) then
		local ok, events = battle:SummonCelestial(seat, open[1])
		if ok then
			return true, events
		end
	end

	local order = {}
	for i, cardId in ipairs(me.Hand) do
		table.insert(order, { Index = i, Card = CardDatabase.GetCard(cardId) })
	end
	shuffled(order)
	for _, entry in ipairs(order) do
		local card = entry.Card
		local hpCost = card.HPCost or 0
		if card.EnergyCost <= me.Energy and (hpCost == 0 or me.HP > hpCost + 6) then
			local attempts = {}
			if card.Type == "Unit" then
				if open[1] then
					attempts = { { Lane = open[1] } }
				end
			else
				for _, target in ipairs(looseTargets(state, seat, card.Effect)) do
					table.insert(attempts, { Target = target or nil })
				end
			end
			for _, options in ipairs(attempts) do
				local ok, events = battle:PlayCard(seat, entry.Index, options)
				if ok then
					return true, events
				end
			end
		end
	end

	if not me.AbilityUsed and easyRng:NextNumber() < EASY.AbilityChance then
		local ability = CardDatabase.GetCard(me.CommanderId).CommanderAbility
		local effect = ability.Effect
		if effect.Kind ~= "PayForEnergy" then
			for _, target in ipairs(looseTargets(state, seat, effect)) do
				local ok, events = battle:UseCommanderAbility(seat, target or nil)
				if ok then
					return true, events
				end
			end
		end
	end
	return false
end

function BattleBot.TakeTurnEasy(battle, seat, onEvents, pause, level)
	EASY = LEVELS[level or "Normal"] or LEVELS.Normal
	local played = false
	for _ = 1, EASY.MaxPlays or 20 do
		if battle.Winner or battle.Current ~= seat then
			return
		end
		local ok, events = tryEasyAction(battle, seat, played)
		if not ok then
			break
		end
		played = true
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

-- The Normal bot keeps whatever hand it's dealt
function BattleBot.ChooseMulliganFor(difficulty, battle, seat)
	if difficulty == "Hard" then
		return BattleBot.ChooseMulligan(battle, seat)
	end
	return {}
end

---------------------------------------------------------------------
-- The planner
---------------------------------------------------------------------
local Rules = CardDatabase.Rules

-- How good a board is for seat (higher = better). Only uses what's on the
-- table, both Commanders' HP and how many cards each side holds.
local function unitValue(unit)
	local power = math.max(0, (unit.Power or 0) + (unit.TempPower or 0))
	local v = power * 1.6 + math.max(0, unit.HP or 0) * 0.9 + 1
	if unit.Shield then v = v + 2.5 end
	if (unit.Grow or 0) > 0 then v = v + unit.Grow * 2.5 end
	if (unit.Decay or 0) > 0 then v = v + unit.Decay * 1.5 end
	if (unit.Regen or 0) > 0 then v = v + unit.Regen end
	if unit.Streak then v = v + 2 end
	if unit.Intercept then v = v + 1 end
	if unit.IsCelestial then v = v + 2 end
	return v
end

local function evaluate(b, seat)
	if b.Winner then
		return b.Winner == seat and (100000 - b.Turn) or (-100000 + b.Turn)
	end
	local me, them = b.Players[seat], b.Players[3 - seat]
	local score = (me.HP - them.HP) * 3
	if me.HP <= 6 then
		score = score - (7 - me.HP) * 5 -- getting low is worse than it looks
	end
	if them.HP <= 6 then
		score = score + (7 - them.HP) * 3
	end
	for lane = 1, Rules.Lanes do
		local mine, theirs = me.Lanes[lane], them.Lanes[lane]
		if mine then
			score = score + unitValue(mine)
			if not theirs then
				score = score + math.max(0, mine.Power + (mine.TempPower or 0)) * 0.8 -- an open lane to hit
			end
		end
		if theirs then
			score = score - unitValue(theirs)
			if not mine then
				score = score - math.max(0, theirs.Power + (theirs.TempPower or 0)) * 1.2 -- a hit coming at us
			end
		end
	end
	score = score + #me.Hand * 1.2 - #them.Hand * 0.4
	-- a face-down Anomaly is worth about a small card on the board until it fires
	-- (ones that react to attacks fire during the look-ahead and score for real)
	for _, set in ipairs(me.Anomalies or {}) do
		if set then
			score = score + BattleBot.AnomalyValue
		end
	end
	if not me.StarGate.OnBoard then
		score = score + 2 -- the Celestial is still ready to come out
	end
	if #me.Deck == 0 then
		score = score - 3
	end
	return score
end

-- End the turn on a copy, let the other side's units hit back, and score it
local function rollout(b, seat)
	if not b.Winner and b.Current == seat then
		b:EndTurn(seat)
	end
	if not b.Winner and b.Current == 3 - seat then
		b:EndTurn(3 - seat) -- their attacks (we can't know what they'll play)
	end
	return evaluate(b, seat)
end

-- Every move worth trying right now: { Kind, Index, Options, Lane, Target, Label }
local function candidateMoves(b, seat)
	local me, them = b.Players[seat], b.Players[3 - seat]
	local moves = {}
	local emptyLanes, unitTargets = {}, {}
	for lane = 1, Rules.Lanes do
		if not me.Lanes[lane] then
			table.insert(emptyLanes, lane)
		else
			table.insert(unitTargets, { Side = "Self", Lane = lane })
		end
		if them.Lanes[lane] then
			table.insert(unitTargets, { Side = "Enemy", Lane = lane })
		end
	end
	local function targetsFor(effect)
		if not effect or not effect.Target then
			return { false }
		end
		return unitTargets
	end
	local tried = {}
	for index, cardId in ipairs(me.Hand) do
		local card = CardDatabase.GetCard(cardId)
		local hpCost = card.HPCost or 0
		if not tried[cardId] and card.EnergyCost <= me.Energy and (hpCost == 0 or me.HP > hpCost + 3) then
			tried[cardId] = true
			if card.Type == "Unit" then
				for _, lane in ipairs(emptyLanes) do
					table.insert(moves, { Kind = "Play", Index = index, Options = { Lane = lane } })
				end
			else
				for _, target in ipairs(targetsFor(card.Effect)) do
					table.insert(moves, { Kind = "Play", Index = index, Options = { Target = target or nil } })
				end
			end
		end
	end
	if not me.StarGate.OnBoard and b:GetCelestialCost(seat) <= me.Energy then
		for _, lane in ipairs(emptyLanes) do
			table.insert(moves, { Kind = "Summon", Lane = lane })
		end
	end
	if not me.AbilityUsed then
		local ability = CardDatabase.GetCard(me.CommanderId).CommanderAbility
		if ability and ability.EnergyCost <= me.Energy then
			for _, target in ipairs(targetsFor(ability.Effect)) do
				table.insert(moves, { Kind = "Ability", Target = target or nil })
			end
		end
	end
	if me.HasSpark then
		table.insert(moves, { Kind = "Spark" })
	end
	return moves
end

local function applyMove(b, seat, move)
	if move.Kind == "Play" then
		return b:PlayCard(seat, move.Index, move.Options)
	elseif move.Kind == "Summon" then
		return b:SummonCelestial(seat, move.Lane)
	elseif move.Kind == "Ability" then
		return b:UseCommanderAbility(seat, move.Target)
	elseif move.Kind == "Spark" then
		return b:UseSpark(seat)
	end
	return false
end

-- Scores every move by playing it on a copy and looking ahead.
-- Returns a list of { Move, Score, Copy } (copy = the board right after the move)
local function scoreMoves(b, seat)
	local scored = {}
	for _, move in ipairs(candidateMoves(b, seat)) do
		local copy = b:CloneForSearch()
		local ok = applyMove(copy, seat, move)
		if ok then
			local after = copy:CloneForSearch()
			table.insert(scored, { Move = move, Score = rollout(after, seat), Copy = copy })
		end
	end
	table.sort(scored, function(x, y)
		return x.Score > y.Score
	end)
	return scored
end

BattleBot.FollowUps = 4 -- how many top moves also get their best next move checked
BattleBot.AnomalyValue = 3.5 -- how much a set, unfired Anomaly adds to a board's score

-- The best move now, or nil to end the turn
local function chooseMove(b, seat)
	local endNow = rollout(b:CloneForSearch(), seat)
	local scored = scoreMoves(b, seat)
	if #scored == 0 then
		return nil
	end
	-- look one move further for the top few: a move that sets up a better
	-- next move can beat one that looks best on its own
	local best, bestValue = nil, endNow
	for i, entry in ipairs(scored) do
		local value = entry.Score
		if i <= BattleBot.FollowUps and not entry.Copy.Winner and entry.Copy.Current == seat then
			local next = scoreMoves(entry.Copy, seat)
			if next[1] then
				value = math.max(value, next[1].Score)
			end
		end
		if value > bestValue + 0.01 then
			best, bestValue = entry.Move, value
		end
	end
	return best
end

-- Plays out the bot's whole turn.
-- onEvents(events) is called after every action; pause() runs between actions.
-- difficulty: "Easy" (default practice bot), "Normal" or "Hard" (the planner)
function BattleBot.TakeTurn(battle, seat, onEvents, pause, difficulty)
	if difficulty == "Normal" or difficulty == "Easy" then
		return BattleBot.TakeTurnEasy(battle, seat, onEvents, pause, difficulty)
	end
	if not battle.CloneForSearch then
		return BattleBot.TakeTurnSimple(battle, seat, onEvents, pause)
	end
	for _ = 1, 15 do
		if battle.Winner or battle.Current ~= seat then
			return
		end
		-- plan on a copy that doesn't show the other side's face-down Anomalies
		local okPlan, move = pcall(function()
			return chooseMove(battle:CloneForSearch(seat), seat)
		end)
		if not okPlan then
			warn("BattleBot: planning failed, playing simply: " .. tostring(move))
			return BattleBot.TakeTurnSimple(battle, seat, onEvents, pause)
		end
		if not move then
			break
		end
		local ok, events = applyMove(battle, seat, move)
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