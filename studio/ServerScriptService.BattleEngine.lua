--[[
	BattleEngine (ModuleScript)
	Location: ServerScriptService > BattleEngine

	Runs the rules of one match. It has no visuals: the table/UI code calls
	its actions and animates the events it returns. It lives on the server
	so players can't cheat.

	Players are seats 1 and 2. Every action returns:
	    true, events      -- it worked; events describe what happened
	    false, message    -- it was refused; nothing changed

	Actions:
	    battle:PlayCard(seat, handIndex, { Lane = 1-3 })                    -- a unit
	    battle:PlayCard(seat, handIndex, { Target = { Side = "Self"/"Enemy", Lane = 1-3 } })  -- a spell
	    battle:PlayCard(seat, handIndex, {})                                 -- a spell with no target
	    battle:SummonCelestial(seat, lane)
	    battle:UseCommanderAbility(seat, { Side = "Self", Lane = 1-3 })
	    battle:UseSpark(seat)      -- second player only, once per match: +1 energy this turn
	    battle:EndTurn(seat)       -- combat happens here, then the other player's turn starts
	    battle:Concede(seat)

	Reading the match:
	    battle:GetState(viewerSeat)   -- what that player is allowed to see
	    BattleEngine.FilterEvents(events, viewerSeat)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))

local Rules = CardDatabase.Rules

local BattleEngine = {}
local Battle = {}
Battle.__index = Battle

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function makeRng(seed)
	if Random then
		local r = seed and Random.new(seed) or Random.new()
		return function(n)
			return r:NextInteger(1, n)
		end
	end
	if seed then
		math.randomseed(seed)
	end
	return function(n)
		return math.random(1, n)
	end
end

local function shuffle(list, rng)
	for i = #list, 2, -1 do
		local j = rng(i)
		list[i], list[j] = list[j], list[i]
	end
end

local function copyList(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	return out
end

local function other(seat)
	return 3 - seat
end

local function effectivePower(unit)
	return math.max(0, unit.Power + unit.TempPower)
end

---------------------------------------------------------------------
-- Creating a match
-- config = {
--     Decks = { [1] = { Commander = id, Celestial = id, Cards = { id, id, ... } }, [2] = {...} },
--     Seed = number (optional), FirstPlayer = 1 or 2 (optional, random if missing),
-- }
---------------------------------------------------------------------
-- Per-seat match stats (see Battle:_track)
local function newSeatStats()
	return { Opening = {}, Drawn = {}, Played = {}, Abilities = 0, Summons = 0, StormDamage = 0, SparkUsed = false }
end

function BattleEngine.new(config)
	local self = setmetatable({}, Battle)
	self.Rng = config.Rng or makeRng(config.Seed)
	self.Turn = 0
	self.Current = nil
	self.Winner = nil
	self.NextUid = 1
	self.Players = {}
	self._events = {}
	self.Stats = { newSeatStats(), newSeatStats() }
	self._dealing = true -- draws until the first turn starts are the opening hands

	for seat = 1, 2 do
		local deckConfig = config.Decks[seat]
		assert(deckConfig, "Missing deck for seat " .. seat)
		local ok, errors = CardDatabase.ValidateDeck(deckConfig.Commander, deckConfig.Celestial, deckConfig.Cards)
		if not ok then
			error(("Seat %d deck is illegal: %s"):format(seat, table.concat(errors, " ")))
		end

		local deck = copyList(deckConfig.Cards)
		shuffle(deck, self.Rng)

		self.Players[seat] = {
			CommanderId = deckConfig.Commander,
			HP = Rules.CommanderHP,
			MaxEnergy = Rules.StartingEnergy - 1, -- goes up by 1 when the first turn starts
			Energy = 0,
			Deck = deck,
			Hand = {},
			Discard = {},
			Lanes = {}, -- [lane] = unit or nil
			AbilityUsed = false,
			HasSpark = false,
			StarGate = {
				CardId = deckConfig.Celestial,
				Revealed = false,
				OnBoard = false,
				TimesReturned = 0,
			},
		}
	end

	local first = config.FirstPlayer or self.Rng(2)
	local second = other(first)
	self:_emit({ Type = "MatchStarted", FirstPlayer = first })

	-- Going second gets some help to even out the first player's head start
	self.Players[second].HP = self.Players[second].HP + (Rules.SecondPlayerBonusHP or 0)
	for seat = 1, 2 do
		self.Players[seat].MaxHP = self.Players[seat].HP -- healing can't go above the starting HP
	end
	self.Players[second].HasSpark = Rules.SecondPlayerSpark == true

	for seat = 1, 2 do
		local handSize = Rules.StartingHand
		if seat == second then
			handSize = handSize + (Rules.SecondPlayerBonusCards or 0)
		end
		for _ = 1, handSize do
			self:_draw(seat)
		end
	end

	self._dealing = false
	self:_startTurn(first)
	self._startEvents = self._events
	self._events = {}
	return self
end

-- Events from dealing opening hands and the first turn
function Battle:TakeStartEvents()
	local events = self._startEvents or {}
	self._startEvents = nil
	return events
end

---------------------------------------------------------------------
-- Internal: events, drawing, turns
---------------------------------------------------------------------
function Battle:_emit(event)
	table.insert(self._events, event)
	self:_track(event)
end

---------------------------------------------------------------------
-- Match stats for the balance log (MatchLog reads battle.Stats at the end).
-- Opening = cards in the opening hand, Drawn = cards drawn after that,
-- Played = { cardId, round } for each card played, in order.
---------------------------------------------------------------------
function Battle:_track(event)
	local stats = self.Stats
	if not stats then
		return
	end
	local kind = event.Type
	local seatStats = event.Player and stats[event.Player]
	local round = math.max(1, math.ceil(self.Turn / 2))
	if kind == "Draw" and seatStats then
		table.insert(self._dealing and seatStats.Opening or seatStats.Drawn, event.CardId)
	elseif (kind == "UnitPlayed" or kind == "SpellCast") and seatStats then
		table.insert(seatStats.Played, { event.CardId, round })
	elseif kind == "CelestialSummoned" and seatStats then
		seatStats.Summons = seatStats.Summons + 1
	elseif kind == "CommanderAbility" and seatStats then
		seatStats.Abilities = seatStats.Abilities + 1
	elseif kind == "SparkUsed" and seatStats then
		seatStats.SparkUsed = true
	elseif kind == "StormDamage" and seatStats then
		seatStats.StormDamage = seatStats.StormDamage + event.Amount
		if event.HP <= 0 then
			stats.StormKill = true
		end
	elseif kind == "MatchStarted" then
		stats.FirstPlayer = event.FirstPlayer
	elseif kind == "MatchOver" then
		stats.Reason = event.Reason
	end
end

function Battle:_draw(seat)
	local player = self.Players[seat]
	if #player.Deck == 0 then
		self:_emit({ Type = "DeckEmpty", Player = seat })
		return
	end
	local cardId = table.remove(player.Deck)
	table.insert(player.Hand, cardId)
	self:_emit({ Type = "Draw", Player = seat, CardId = cardId })
end

function Battle:_startTurn(seat)
	self.Turn = self.Turn + 1
	self.Current = seat
	local player = self.Players[seat]
	player.MaxEnergy = math.min(Rules.MaxEnergy, player.MaxEnergy + 1)
	player.Energy = player.MaxEnergy
	player.AbilityUsed = false
	self:_emit({ Type = "TurnStarted", Player = seat, Turn = self.Turn, Energy = player.Energy })

	-- Cosmic Storm: late in the match both Commanders take growing damage
	local round = math.ceil(self.Turn / 2)
	if Rules.StormStartRound and round >= Rules.StormStartRound then
		local amount = round - Rules.StormStartRound + 1
		player.HP = player.HP - amount
		self:_emit({ Type = "StormDamage", Player = seat, Amount = amount, HP = player.HP })
	end
	-- The player who goes first skips their first draw
	if self.Turn > 1 then
		self:_draw(seat)
	end
end

function Battle:_newUnit(seat, cardId, isCelestial)
	local card = CardDatabase.GetCard(cardId)
	local unit = {
		Uid = self.NextUid,
		CardId = cardId,
		Owner = seat,
		Power = card.Power,
		TempPower = 0,
		HP = card.HP,
		MaxHP = card.HP,
		Shield = card.Keywords.Shield == true,
		Rush = card.Keywords.Rush == true,
		Ignite = card.Keywords.Ignite or 0,
		Regen = card.Keywords.Regen or 0,
		SummonedTurn = self.Turn,
		IsCelestial = isCelestial or false,
		Buffs = {},          -- where each Power boost came from: { Source, Power, Temporary }
		ShieldSource = card.Keywords.Shield and "Shield keyword" or nil,
	}
	self.NextUid = self.NextUid + 1
	return unit
end

---------------------------------------------------------------------
-- Internal: damage, death, effects
---------------------------------------------------------------------
function Battle:_damageUnit(unit, amount)
	if amount <= 0 then
		return
	end
	if unit.Shield then
		unit.Shield = false
		unit.ShieldSource = nil
		self:_emit({ Type = "ShieldBroken", Uid = unit.Uid })
		return
	end
	unit.HP = unit.HP - amount
	self:_emit({ Type = "UnitDamaged", Uid = unit.Uid, Amount = amount, HP = unit.HP })
end

function Battle:_healUnit(unit, amount)
	local healed = math.min(amount, unit.MaxHP - unit.HP)
	if healed > 0 then
		unit.HP = unit.HP + healed
		self:_emit({ Type = "UnitHealed", Uid = unit.Uid, Amount = healed, HP = unit.HP })
	end
end

function Battle:_healCommander(seat, amount)
	local player = self.Players[seat]
	local healed = math.min(amount, player.MaxHP - player.HP)
	if healed > 0 then
		player.HP = player.HP + healed
		self:_emit({ Type = "CommanderHealed", Player = seat, Amount = healed, HP = player.HP })
	end
end

function Battle:_giveShield(unit, source)
	if not unit.Shield then
		unit.Shield = true
		unit.ShieldSource = source or "Effect"
		self:_emit({ Type = "ShieldGained", Uid = unit.Uid })
	end
end

function Battle:_removeDead()
	for seat = 1, 2 do
		local player = self.Players[seat]
		for lane = 1, Rules.Lanes do
			local unit = player.Lanes[lane]
			if unit and unit.HP <= 0 then
				player.Lanes[lane] = nil
				if unit.IsCelestial then
					player.StarGate.OnBoard = false
					player.StarGate.TimesReturned = player.StarGate.TimesReturned + 1
					self:_emit({ Type = "CelestialReturned", Player = seat, Uid = unit.Uid,
						NextCost = self:GetCelestialCost(seat) })
				else
					table.insert(player.Discard, unit.CardId)
					self:_emit({ Type = "UnitDestroyed", Player = seat, Lane = lane, Uid = unit.Uid })
				end
			end
		end
	end
end

-- Target = { Side = "Self" or "Enemy", Lane = n }, relative to the seat using it
function Battle:_unitAt(seat, target)
	if type(target) ~= "table" then
		return nil
	end
	local lane = target.Lane
	if type(lane) ~= "number" or lane < 1 or lane > Rules.Lanes then
		return nil
	end
	if target.Side == "Self" then
		return self.Players[seat].Lanes[lane]
	elseif target.Side == "Enemy" then
		return self.Players[other(seat)].Lanes[lane]
	end
	return nil
end

-- Checks an effect can be used right now. Returns true, or false + message.
function Battle:_checkEffect(seat, effect, target)
	if effect.Target == "AnyUnit" or effect.Target == "FriendlyUnit" then
		local unit = self:_unitAt(seat, target)
		if not unit then
			return false, "Choose a unit to target."
		end
		if effect.Target == "FriendlyUnit" and unit.Owner ~= seat then
			return false, "Choose one of your own units."
		end
		if effect.Faction and CardDatabase.GetCard(unit.CardId).Faction ~= effect.Faction then
			return false, "That only works on " .. effect.Faction .. " units."
		end
		if effect.Kind == "HealUnit" and unit.HP >= unit.MaxHP then
			return false, "That unit isn't damaged."
		end
		if effect.Kind == "GiveShield" and unit.Shield then
			return false, "That unit already has a Shield."
		end
	end
	if effect.Kind == "HealCommander" then
		local player = self.Players[seat]
		if player.HP >= player.MaxHP then
			return false, "Your Commander is already at full HP."
		end
	end
	if effect.Kind == "ShieldAllFriendly" then
		local any = false
		for lane = 1, Rules.Lanes do
			local unit = self.Players[seat].Lanes[lane]
			if unit and not unit.Shield then
				any = true
			end
		end
		if not any then
			return false, "You have no units that need a Shield."
		end
	end
	return true
end

-- source = name of what caused it (a card, or a Commander's ability), for the inspect view
function Battle:_applyEffect(seat, effect, target, source)
	local kind = effect.Kind
	if kind == "Draw" then
		for _ = 1, effect.Count or 1 do
			self:_draw(seat)
		end
	elseif kind == "DamageUnit" then
		self:_damageUnit(self:_unitAt(seat, target), effect.Amount)
	elseif kind == "DamageAllEnemies" then
		local enemyLanes = self.Players[other(seat)].Lanes
		for lane = 1, Rules.Lanes do
			if enemyLanes[lane] then
				self:_damageUnit(enemyLanes[lane], effect.Amount)
			end
		end
	elseif kind == "BuffUnit" then
		local unit = self:_unitAt(seat, target)
		unit.Power = unit.Power + effect.Power
		table.insert(unit.Buffs, { Source = source or "Effect", Power = effect.Power })
		self:_emit({ Type = "UnitBuffed", Uid = unit.Uid, Power = unit.Power })
	elseif kind == "DamageStrongestEnemy" then
		-- picks its own target: the enemy unit with the most Power (then the most HP, then the leftmost)
		local best
		for lane = 1, Rules.Lanes do
			local unit = self.Players[other(seat)].Lanes[lane]
			if unit then
				local power, bestPower = effectivePower(unit), best and effectivePower(best)
				if not best or power > bestPower or (power == bestPower and unit.HP > best.HP) then
					best = unit
				end
			end
		end
		if best then
			self:_damageUnit(best, effect.Amount)
		end
	elseif kind == "BuffAllFriendly" then
		local lanes = self.Players[seat].Lanes
		for lane = 1, Rules.Lanes do
			local unit = lanes[lane]
			if unit and not (effect.Other and unit == self._placing) and (not effect.Faction or CardDatabase.GetCard(unit.CardId).Faction == effect.Faction) then
				unit.Power = unit.Power + effect.Power
				table.insert(unit.Buffs, { Source = source or "Effect", Power = effect.Power })
				self:_emit({ Type = "UnitBuffed", Uid = unit.Uid, Power = unit.Power })
			end
		end
	elseif kind == "TempBuff" then
		local unit = self:_unitAt(seat, target)
		unit.TempPower = unit.TempPower + effect.Power
		table.insert(unit.Buffs, { Source = source or "Effect", Power = effect.Power, Temporary = true })
		self:_emit({ Type = "UnitBuffed", Uid = unit.Uid, Power = effectivePower(unit), Temporary = true })
	elseif kind == "HealUnit" then
		self:_healUnit(self:_unitAt(seat, target), effect.Amount)
	elseif kind == "HealCommander" then
		self:_healCommander(seat, effect.Amount)
	elseif kind == "HealAllFriendly" then
		local lanes = self.Players[seat].Lanes
		for lane = 1, Rules.Lanes do
			if lanes[lane] then
				self:_healUnit(lanes[lane], effect.Amount)
			end
		end
		if effect.IncludeCommander then
			self:_healCommander(seat, effect.Amount)
		end
	elseif kind == "GiveShield" then
		self:_giveShield(self:_unitAt(seat, target), source)
	elseif kind == "ShieldAllFriendly" then
		local lanes = self.Players[seat].Lanes
		for lane = 1, Rules.Lanes do
			if lanes[lane] then
				self:_giveShield(lanes[lane], source)
			end
		end
	else
		error("Unknown effect kind: " .. tostring(kind))
	end
end

-- Puts a unit in a lane and runs Ignite / OnPlay
function Battle:_placeUnit(seat, unit, lane)
	self.Players[seat].Lanes[lane] = unit
	if unit.Ignite > 0 then
		local across = self.Players[other(seat)].Lanes[lane]
		if across then
			self:_emit({ Type = "Ignite", Uid = unit.Uid, Target = across.Uid, Amount = unit.Ignite })
			self:_damageUnit(across, unit.Ignite)
		end
	end
	local card = CardDatabase.GetCard(unit.CardId)
	if card.OnPlay then
		self._placing = unit -- so "your other units" can leave this one out
		self:_applyEffect(seat, card.OnPlay, nil, card.Name)
		self._placing = nil
	end
	self:_removeDead()
end

---------------------------------------------------------------------
-- Action wrapper: refuses actions that aren't allowed, collects events
---------------------------------------------------------------------
function Battle:_act(seat, fn)
	if self.Winner then
		return false, "The match is over."
	end
	if seat ~= self.Current then
		return false, "It's not your turn."
	end
	self._events = {}
	local ok, message = fn()
	if not ok then
		return false, message
	end
	self:_checkWinner()
	return true, self._events
end

function Battle:_checkWinner()
	if self.Winner then
		return
	end
	for seat = 1, 2 do
		if self.Players[seat].HP <= 0 then
			self.Winner = other(seat)
			self:_emit({ Type = "MatchOver", Winner = self.Winner, Reason = "CommanderDefeated" })
			return
		end
	end
end

---------------------------------------------------------------------
-- Public actions
---------------------------------------------------------------------
function Battle:GetCelestialCost(seat)
	local player = self.Players[seat]
	local card = CardDatabase.GetCard(player.StarGate.CardId)
	return card.EnergyCost + Rules.CelestialTax * player.StarGate.TimesReturned
end

function Battle:PlayCard(seat, handIndex, options)
	return self:_act(seat, function()
		options = options or {}
		local player = self.Players[seat]
		local cardId = player.Hand[handIndex]
		if not cardId then
			return false, "That card isn't in your hand."
		end
		local card = CardDatabase.GetCard(cardId)
		if card.EnergyCost > player.Energy then
			return false, "Not enough energy."
		end

		if card.Type == "Unit" then
			local lane = options.Lane
			if type(lane) ~= "number" or lane < 1 or lane > Rules.Lanes then
				return false, "Choose a lane."
			end
			if player.Lanes[lane] then
				return false, "That lane is taken."
			end
			table.remove(player.Hand, handIndex)
			player.Energy = player.Energy - card.EnergyCost
			local unit = self:_newUnit(seat, cardId, false)
			self:_emit({ Type = "UnitPlayed", Player = seat, CardId = cardId, Lane = lane, Uid = unit.Uid })
			self:_placeUnit(seat, unit, lane)
			return true
		elseif card.Type == "Spell" then
			local ok, message = self:_checkEffect(seat, card.Effect, options.Target)
			if not ok then
				return false, message
			end
			table.remove(player.Hand, handIndex)
			player.Energy = player.Energy - card.EnergyCost
			self:_emit({ Type = "SpellCast", Player = seat, CardId = cardId, Target = options.Target })
			self:_applyEffect(seat, card.Effect, options.Target, card.Name)
			table.insert(player.Discard, cardId)
			self:_removeDead()
			return true
		end
		return false, "That card can't be played from your hand."
	end)
end

function Battle:SummonCelestial(seat, lane)
	return self:_act(seat, function()
		local player = self.Players[seat]
		local gate = player.StarGate
		if gate.OnBoard then
			return false, "Your Celestial is already on the board."
		end
		if type(lane) ~= "number" or lane < 1 or lane > Rules.Lanes then
			return false, "Choose a lane."
		end
		if player.Lanes[lane] then
			return false, "That lane is taken."
		end
		local cost = self:GetCelestialCost(seat)
		if cost > player.Energy then
			return false, ("Not enough energy (needs %d)."):format(cost)
		end
		player.Energy = player.Energy - cost
		local firstReveal = not gate.Revealed
		gate.Revealed = true
		gate.OnBoard = true
		local unit = self:_newUnit(seat, gate.CardId, true)
		self:_emit({ Type = "CelestialSummoned", Player = seat, CardId = gate.CardId, Lane = lane,
			Uid = unit.Uid, FirstReveal = firstReveal })
		self:_placeUnit(seat, unit, lane)
		return true
	end)
end

function Battle:UseCommanderAbility(seat, target)
	return self:_act(seat, function()
		local player = self.Players[seat]
		local ability = CardDatabase.GetCard(player.CommanderId).CommanderAbility
		if player.AbilityUsed then
			return false, "Your Commander ability was already used this turn."
		end
		if ability.EnergyCost > player.Energy then
			return false, "Not enough energy."
		end
		local ok, message = self:_checkEffect(seat, ability.Effect, target)
		if not ok then
			return false, message
		end
		player.Energy = player.Energy - ability.EnergyCost
		player.AbilityUsed = true
		self:_emit({ Type = "CommanderAbility", Player = seat, Target = target })
		self:_applyEffect(seat, ability.Effect, target, CardDatabase.GetCard(player.CommanderId).Name .. "'s ability")
		self:_removeDead()
		return true
	end)
end

-- The second player's one-time +1 energy boost
function Battle:UseSpark(seat)
	return self:_act(seat, function()
		local player = self.Players[seat]
		if not player.HasSpark then
			return false, "You don't have a Spark."
		end
		player.HasSpark = false
		player.Energy = player.Energy + 1
		self:_emit({ Type = "SparkUsed", Player = seat, Energy = player.Energy })
		return true
	end)
end

function Battle:EndTurn(seat)
	return self:_act(seat, function()
		local me = self.Players[seat]
		local enemy = self.Players[other(seat)]

		-- Combat, lane by lane
		for lane = 1, Rules.Lanes do
			local attacker = me.Lanes[lane]
			if attacker and (attacker.SummonedTurn < self.Turn or attacker.Rush) then
				local defender = enemy.Lanes[lane]
				local attackPower = effectivePower(attacker)
				if defender then
					local defendPower = effectivePower(defender)
					self:_emit({ Type = "Attack", Lane = lane, Attacker = attacker.Uid, Defender = defender.Uid })
					local shielded = defender.Shield
					self:_damageUnit(defender, attackPower)
					self:_damageUnit(attacker, defendPower)
					-- Overflow: damage beyond what the defender could take hits the Commander
					if Rules.Overflow and not shielded and defender.HP < 0 then
						local excess = -defender.HP
						enemy.HP = enemy.HP - excess
						self:_emit({ Type = "CommanderDamaged", Player = other(seat), Lane = lane,
							Attacker = attacker.Uid, Amount = excess, HP = enemy.HP, Overflow = true })
					end
					self:_removeDead()
				elseif attackPower > 0 then
					enemy.HP = enemy.HP - attackPower
					self:_emit({ Type = "CommanderDamaged", Player = other(seat), Lane = lane,
						Attacker = attacker.Uid, Amount = attackPower, HP = enemy.HP })
				end
			end
		end

		-- Temporary buffs wear off; Regen units heal
		for lane = 1, Rules.Lanes do
			local unit = me.Lanes[lane]
			if unit then
				unit.TempPower = 0
				-- this-turn boosts wear off
				for i = #unit.Buffs, 1, -1 do
					if unit.Buffs[i].Temporary then
						table.remove(unit.Buffs, i)
					end
				end
				if unit.Regen > 0 then
					self:_healUnit(unit, unit.Regen)
				end
			end
		end

		self:_emit({ Type = "TurnEnded", Player = seat })
		self:_checkWinner()
		if not self.Winner then
			self:_startTurn(other(seat))
		end
		return true
	end)
end

function Battle:Concede(seat)
	if self.Winner then
		return false, "The match is over."
	end
	self._events = {}
	self.Winner = other(seat)
	self:_emit({ Type = "MatchOver", Winner = self.Winner, Reason = "Concede" })
	return true, self._events
end

---------------------------------------------------------------------
-- What a player is allowed to see
---------------------------------------------------------------------
local function copyBuffs(buffs)
	local out = {}
	for i, buff in ipairs(buffs) do
		out[i] = { Source = buff.Source, Power = buff.Power, Temporary = buff.Temporary == true }
	end
	return out
end

local function unitView(unit)
	if not unit then
		return nil
	end
	return {
		Uid = unit.Uid,
		CardId = unit.CardId,
		Power = effectivePower(unit),
		HP = unit.HP,
		MaxHP = unit.MaxHP,
		Shield = unit.Shield,
		Rush = unit.Rush,
		Regen = unit.Regen,
		Ignite = unit.Ignite,
		IsCelestial = unit.IsCelestial,
		-- For the inspect view
		BasePower = CardDatabase.GetCard(unit.CardId).Power,
		BaseHP = CardDatabase.GetCard(unit.CardId).HP,
		Buffs = copyBuffs(unit.Buffs),
		ShieldSource = unit.ShieldSource,
	}
end

function Battle:GetState(viewer)
	local state = {
		Turn = self.Turn,
		Current = self.Current,
		Winner = self.Winner,
		You = viewer,
		Players = {},
	}
	for seat = 1, 2 do
		local player = self.Players[seat]
		local isYou = seat == viewer
		local lanes = {}
		for lane = 1, Rules.Lanes do
			local unit = player.Lanes[lane]
			local view = unitView(unit)
			if view then
				view.CanAttack = unit.Rush or unit.SummonedTurn < self.Turn
			end
			lanes[lane] = view or false -- false (not nil) keeps the list intact when sent to players
		end
		local gate = player.StarGate
		state.Players[seat] = {
			CommanderId = player.CommanderId,
			HP = player.HP,
			MaxHP = player.MaxHP,
			Energy = player.Energy,
			MaxEnergy = player.MaxEnergy,
			AbilityUsed = player.AbilityUsed,
			HasSpark = player.HasSpark,
			DeckCount = #player.Deck,
			HandCount = #player.Hand,
			Hand = isYou and copyList(player.Hand) or nil,
			DiscardCount = #player.Discard,
			Lanes = lanes,
			StarGate = {
				-- The face-down Celestial stays secret from the opponent until summoned
				CardId = (isYou or gate.Revealed) and gate.CardId or nil,
				Revealed = gate.Revealed,
				OnBoard = gate.OnBoard,
				-- Current summon cost (goes up each time it returns). Hidden with the card.
				Cost = (isYou or gate.Revealed) and self:GetCelestialCost(seat) or nil,
				TimesReturned = gate.TimesReturned,
			},
		}
	end
	return state
end

-- Hides the opponent's drawn cards from event lists before sending them to a player
function BattleEngine.FilterEvents(events, viewer)
	local out = {}
	for i, event in ipairs(events) do
		if event.Type == "Draw" and event.Player ~= viewer then
			out[i] = { Type = "Draw", Player = event.Player }
		else
			out[i] = event
		end
	end
	return out
end

return BattleEngine