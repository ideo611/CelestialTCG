--[[
	BattleEngine (ModuleScript)
	Location: ServerScriptService > BattleEngine

	Runs the rules of one match. It has no visuals: the table/UI code calls
	its actions and animates the events it returns. It lives on the server
	so players can't cheat.

	Players are seats 1 and 2. Every action returns:
	    true, events      -- it worked; events describe what happened
	    false, message    -- it was refused; nothing changed

	Config: BattleEngine.new({ Decks = { deck1, deck2 }, FirstPlayer?, Seed?, Mulligan? })
	    Scripted = { [seat] = { HP?, StartingEnergy?, HandSize?, CelestialDiscount? } }
	    makes a scripted match (the tutorial): decks aren't checked or shuffled
	    (cards are drawn in the listed order) and nobody gets the Spark.

	Actions:
	    battle:PlayCard(seat, handIndex, { Lane = 1-3 })                    -- a unit
	    battle:PlayCard(seat, handIndex, { Target = { Side = "Self"/"Enemy", Lane = 1-3 } })  -- a spell
	    battle:PlayCard(seat, handIndex, {})                                 -- a spell with no target
	    battle:SummonCelestial(seat, lane)
	    battle:UseCommanderAbility(seat, { Side = "Self", Lane = 1-3 })
	    battle:UseSpark(seat)      -- second player only, once per match: +1 energy this turn
	    battle:EndTurn(seat)       -- combat happens here, then the other player's turn starts
	    battle:Concede(seat)

	Keywords: Rush, Shield, Ignite X, Regen X, Grow X (start of your turn, once it has lived through an enemy turn: +X Power for good),
	Decay X (end of your turn: the enemy unit across takes X), Streak (attacks the enemy
	Commander directly, past the unit across, which doesn't hit back).
	Some cards also cost Commander HP (card.HPCost) on top of their energy.
	Anomalies: PlayCard(seat, handIndex, {}) sets one face-down in a free Anomaly
	slot. During the other player's turn it flips up the first time its Trigger
	happens (see CardDatabase), runs its Effect and goes to the graveyard.

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
		if not config.Scripted then
			local ok, errors = CardDatabase.ValidateDeck(deckConfig.Commander, deckConfig.Celestial, deckConfig.Cards, deckConfig.Format)
			if not ok then
				error(("Seat %d deck is illegal: %s"):format(seat, table.concat(errors, " ")))
			end
		end

		local deck = copyList(deckConfig.Cards)
		if config.Scripted then
			-- scripted match (the tutorial): cards are drawn in the listed order
			local reversed = {}
			for i = #deck, 1, -1 do
				table.insert(reversed, deck[i])
			end
			deck = reversed
		else
			shuffle(deck, self.Rng)
		end
		local scripted = config.Scripted and config.Scripted[seat] or {}

		self.Players[seat] = {
			CommanderId = deckConfig.Commander,
			HP = scripted.HP or Rules.CommanderHP,
			MaxEnergy = (scripted.StartingEnergy or Rules.StartingEnergy) - 1, -- goes up by 1 when the first turn starts
			CelestialDiscount = scripted.CelestialDiscount or 0,
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
			Anomalies = {}, -- [slot] = { CardId } face-down, or false when empty
		}
		for slot = 1, (Rules.AnomaliesEnabled ~= false and Rules.AnomalySlots) or 0 do
			self.Players[seat].Anomalies[slot] = false
		end
	end

	local first = config.FirstPlayer or self.Rng(2)
	local second = other(first)
	self:_emit({ Type = "MatchStarted", FirstPlayer = first })

	-- Going second gets some help to even out the first player's head start
	self.Players[second].HP = self.Players[second].HP + (Rules.SecondPlayerBonusHP or 0)
	for seat = 1, 2 do
		self.Players[seat].MaxHP = self.Players[seat].HP -- healing can't go above the starting HP
	end
	self.Players[second].HasSpark = Rules.SecondPlayerSpark == true and not config.Scripted

	for seat = 1, 2 do
		local handSize = Rules.StartingHand
		if seat == second then
			handSize = handSize + (Rules.SecondPlayerBonusCards or 0)
		end
		if config.Scripted and config.Scripted[seat] and config.Scripted[seat].HandSize then
			handSize = config.Scripted[seat].HandSize
		end
		for _ = 1, handSize do
			self:_draw(seat)
		end
	end

	self.FirstPlayer = first
	if config.Mulligan then
		-- Both players look at their opening hand and may send cards back
		-- (Battle:Mulligan). The first turn starts once both have chosen.
		self.Phase = "Mulligan"
		for seat = 1, 2 do
			self.Players[seat].MulliganDone = false
		end
	else
		self._dealing = false
		self:_startTurn(first)
	end
	self._startEvents = self._events
	self._events = {}
	return self
end

-- A private copy of the match for the bot to try moves on (nothing it does
-- touches the real match). Random effects in the copy use a fixed seed.
local function deepCopy(value, seen)
	if type(value) ~= "table" then
		return value
	end
	if seen[value] then
		return seen[value]
	end
	local out = {}
	seen[value] = out
	for k, v in pairs(value) do
		out[deepCopy(k, seen)] = deepCopy(v, seen)
	end
	return out
end

-- viewer (optional): the seat doing the planning. The other side's face-down
-- Anomalies are left out of the copy, so the bot can't see what they are.
function Battle:CloneForSearch(viewer)
	local seen = {}
	local copy = {}
	for key, value in pairs(self) do
		if key ~= "Rng" and key ~= "Stats" and key ~= "_events" and key ~= "_startEvents" then
			copy[key] = deepCopy(value, seen)
		end
	end
	copy.Rng = makeRng(self.Turn * 7919 + 17)
	copy._events = {}
	copy.Searching = true
	if viewer then
		local hidden = copy.Players[other(viewer)].Anomalies
		for slot = 1, #hidden do
			hidden[slot] = false
		end
	end
	return setmetatable(copy, Battle)
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
	elseif (kind == "UnitPlayed" or kind == "SpellCast" or kind == "AnomalySet") and seatStats then
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

-- Adds to a unit's Power for good, keeping one line per source in the inspect view
local function addPower(unit, amount, source)
	local before = unit.Power
	unit.Power = math.max(0, unit.Power + amount)
	local change = unit.Power - before
	if change ~= 0 then
		for _, buff in ipairs(unit.Buffs) do
			if buff.Source == source and not buff.Temporary then
				buff.Power = buff.Power + change
				return change
			end
		end
		table.insert(unit.Buffs, { Source = source, Power = change })
	end
	return change
end

function Battle:_growAll(seat)
	for lane = 1, Rules.Lanes do
		local unit = self.Players[seat].Lanes[lane]
		if unit and unit.Grow > 0 then
			addPower(unit, unit.Grow, "Grow")
			self:_emit({ Type = "UnitGrew", Uid = unit.Uid, Amount = unit.Grow, Power = effectivePower(unit) })
		end
	end
end

function Battle:_startTurn(seat)
	self.Turn = self.Turn + 1
	self.Current = seat
	local player = self.Players[seat]
	player.MaxEnergy = math.min(Rules.MaxEnergy, player.MaxEnergy + 1)
	player.Energy = player.MaxEnergy
	player.AbilityUsed = false
	self:_emit({ Type = "TurnStarted", Player = seat, Turn = self.Turn, Energy = player.Energy })
	-- Grow on the start-of-turn timing: every unit still here has lived through an enemy turn
	if Rules.GrowTiming == "StartOfTurn" then
		self:_growAll(seat)
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
		Grow = card.Keywords.Grow or 0,
		Decay = card.Keywords.Decay or 0,
		Streak = card.Keywords.Streak == true,
		Intercept = card.Keywords.Intercept == true, -- Streak can't fly past it
		TempStreak = false,  -- Streak given by an effect, until the end of this turn
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
	return healed > 0 and healed or 0
end

function Battle:_healCommander(seat, amount)
	local player = self.Players[seat]
	local healed = math.min(amount, player.MaxHP - player.HP)
	if healed > 0 then
		player.HP = player.HP + healed
		self:_emit({ Type = "CommanderHealed", Player = seat, Amount = healed, HP = player.HP })
	end
	return healed > 0 and healed or 0
end

-- Heal triggers (Moontide Siren): after one of your heal effects actually heals
-- something, each of your units with HealPing deals that much to the enemy Commander.
-- Counts once per heal effect, not once per unit it healed.
function Battle:_afterHeal(seat, healed)
	if healed <= 0 then
		return
	end
	local enemy = self.Players[other(seat)]
	for _, unit in ipairs(self:_units(seat)) do
		local ping = CardDatabase.GetCard(unit.CardId).HealPing
		if ping and ping > 0 and unit.HP > 0 then
			enemy.HP = enemy.HP - ping
			self:_emit({ Type = "CommanderDamaged", Player = other(seat), Attacker = unit.Uid,
				Amount = ping, HP = enemy.HP, HealPing = true })
		end
	end
end

function Battle:_giveShield(unit, source)
	if not unit.Shield then
		unit.Shield = true
		unit.ShieldSource = source or "Effect"
		self:_emit({ Type = "ShieldGained", Uid = unit.Uid })
	end
end

-- Weakening never takes a unit below 1 Power
function Battle:_weaken(unit, amount, source)
	amount = math.max(0, math.min(amount, unit.Power - 1))
	if amount == 0 then
		return
	end
	local change = addPower(unit, -amount, source or "Effect")
	if change ~= 0 then
		self:_emit({ Type = "UnitWeakened", Uid = unit.Uid, Amount = -change, Power = effectivePower(unit) })
	end
end

function Battle:_giveGrow(unit, amount, source)
	unit.Grow = unit.Grow + amount
	if Rules.MaxGrow then
		unit.Grow = math.min(unit.Grow, math.max(Rules.MaxGrow, CardDatabase.GetCard(unit.CardId).Keywords.Grow or 0))
	end
	unit.GrowSource = source
	self:_emit({ Type = "GrowGained", Uid = unit.Uid, Grow = unit.Grow })
end

function Battle:_giveStreak(unit, source)
	if not unit.Streak and not unit.TempStreak then
		unit.TempStreak = true
		unit.StreakSource = source
		self:_emit({ Type = "StreakGained", Uid = unit.Uid })
	end
end

function Battle:_destroy(unit)
	unit.Shield = false
	unit.HP = 0
	self:_emit({ Type = "UnitDestroyedByEffect", Uid = unit.Uid })
end

-- Sends a unit back to its owner's hand (a Celestial goes back to its Star Gate)
function Battle:_returnToHand(unit)
	local owner = self.Players[unit.Owner]
	for lane = 1, Rules.Lanes do
		if owner.Lanes[lane] == unit then
			owner.Lanes[lane] = nil
			if unit.IsCelestial then
				owner.StarGate.OnBoard = false
				self:_emit({ Type = "UnitReturned", Player = unit.Owner, Lane = lane, Uid = unit.Uid,
					CardId = unit.CardId, ToGate = true, NextCost = self:GetCelestialCost(unit.Owner) })
			else
				table.insert(owner.Hand, unit.CardId)
				self:_emit({ Type = "UnitReturned", Player = unit.Owner, Lane = lane, Uid = unit.Uid, CardId = unit.CardId })
			end
			return
		end
	end
end

-- Every unit on the board (seat = only that player's)
function Battle:_units(seat)
	local list = {}
	for s = 1, 2 do
		if not seat or s == seat then
			for lane = 1, Rules.Lanes do
				local unit = self.Players[s].Lanes[lane]
				if unit then
					table.insert(list, unit)
				end
			end
		end
	end
	return list
end

-- The unit with the most Power (then most HP, then leftmost); maxPower limits the pick
local function strongest(units, maxPower)
	local best
	for _, unit in ipairs(units) do
		local power = effectivePower(unit)
		if not maxPower or power <= maxPower then
			local bestPower = best and effectivePower(best)
			if not best or power > bestPower or (power == bestPower and unit.HP > best.HP) then
				best = unit
			end
		end
	end
	return best
end

function Battle:_removeDead()
	local destroyed = {}
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
					table.insert(destroyed, { Seat = seat, CardId = unit.CardId })
				end
			end
		end
	end
	-- Anomalies that react to losing a unit on the opponent's turn
	for _, entry in ipairs(destroyed) do
		self:_triggerAnomalies(entry.Seat, "FriendlyUnitDestroyed", { CardId = entry.CardId })
	end
end

---------------------------------------------------------------------
-- Anomalies
---------------------------------------------------------------------
function Battle:_isOnBoard(unit)
	local lanes = self.Players[unit.Owner].Lanes
	for lane = 1, Rules.Lanes do
		if lanes[lane] == unit then
			return true
		end
	end
	return false
end

-- Flips owner's face-down Anomalies whose Trigger matches (only during the other
-- player's turn). ctx = { Unit = the unit that set it off, CardId = the card involved };
-- effects can mark ctx.Cancelled (spell), ctx.Prevented (Commander damage) or
-- ctx.Removed (the unit left the board). Returns ctx.
function Battle:_triggerAnomalies(owner, trigger, ctx)
	ctx = ctx or {}
	if self.Winner or not self.Current or self.Current == owner then
		return ctx
	end
	local player = self.Players[owner]
	for slot = 1, #player.Anomalies do
		local set = player.Anomalies[slot]
		if set then
			local card = CardDatabase.GetCard(set.CardId)
			if card.Trigger == trigger then
				player.Anomalies[slot] = false
				table.insert(player.Discard, set.CardId)
				self:_emit({ Type = "AnomalyTriggered", Player = owner, Slot = slot, CardId = set.CardId,
					Trigger = trigger, Uid = ctx.Unit and ctx.Unit.Uid or nil })
				self:_resolveAnomaly(owner, card, card.Effect, ctx)
			end
		end
	end
	return ctx
end

function Battle:_resolveAnomaly(owner, card, effect, ctx)
	local kind = effect.Kind
	local unit = ctx.Unit
	local alive = unit ~= nil and unit.HP > 0 and self:_isOnBoard(unit)
	if kind == "Multi" then
		for _, part in ipairs(effect.Effects) do
			self:_resolveAnomaly(owner, card, part, ctx)
		end
	elseif kind == "DamageTrigger" then
		if alive then
			self:_damageUnit(unit, effect.Amount)
		end
	elseif kind == "WeakenTrigger" then
		if alive then
			self:_weaken(unit, effect.Amount, card.Name)
		end
	elseif kind == "FreezeTrigger" then
		if alive then
			unit.Frozen = true
			self:_emit({ Type = "UnitFrozen", Uid = unit.Uid })
		end
	elseif kind == "ReturnTrigger" then
		if alive then
			if unit.IsCelestial and effect.Tax then
				local gate = self.Players[unit.Owner].StarGate
				gate.TimesReturned = gate.TimesReturned + 1
			end
			self:_returnToHand(unit)
			ctx.Removed = true
		end
	elseif kind == "CancelSpell" then
		ctx.Cancelled = true
		self:_emit({ Type = "SpellCancelled", Player = other(owner), CardId = ctx.CardId })
	elseif kind == "PreventDamage" then
		ctx.Prevented = true
	elseif kind == "ReturnDestroyed" then
		local player = self.Players[owner]
		for i = #player.Discard, 1, -1 do
			if player.Discard[i] == ctx.CardId then
				table.remove(player.Discard, i)
				table.insert(player.Hand, ctx.CardId)
				self:_emit({ Type = "CardRecovered", Player = owner, CardId = ctx.CardId })
				break
			end
		end
	elseif kind == "DamageEnemyCommander" then
		local enemy = self.Players[other(owner)]
		enemy.HP = enemy.HP - effect.Amount
		self:_emit({ Type = "CommanderDamaged", Player = other(owner), Amount = effect.Amount, HP = enemy.HP,
			Anomaly = true })
	elseif kind == "GrowWeakestFriendly" then
		local weakest
		for _, u in ipairs(self:_units(owner)) do
			local p = effectivePower(u)
			if not weakest or p < effectivePower(weakest) or (p == effectivePower(weakest) and u.HP < weakest.HP) then
				weakest = u
			end
		end
		if weakest then
			self:_giveGrow(weakest, effect.Amount or 1, card.Name)
		end
	else
		self:_applyEffect(owner, effect, nil, card.Name)
	end
end

-- "LowHP" Anomalies: the player whose turn it isn't just dropped below the line
function Battle:_checkLowHP()
	if self.Winner or not self.Current then
		return
	end
	local owner = other(self.Current)
	local player = self.Players[owner]
	if player.HP > 0 and player.HP < (Rules.AnomalyLowHP or 10) then
		self:_triggerAnomalies(owner, "LowHP")
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
	if effect.Kind == "Multi" then
		for _, part in ipairs(effect.Effects) do
			local ok, message = self:_checkEffect(seat, part, target)
			if not ok then
				return false, message
			end
		end
		return true
	end
	if effect.Target == "AnyUnit" or effect.Target == "FriendlyUnit" or effect.Target == "EnemyUnit" then
		local unit = self:_unitAt(seat, target)
		if not unit then
			return false, "Choose a unit to target."
		end
		if effect.Target == "FriendlyUnit" and unit.Owner ~= seat then
			return false, "Choose one of your own units."
		end
		if effect.Target == "EnemyUnit" and unit.Owner == seat then
			return false, "Choose an enemy unit."
		end
		if effect.MaxPower and effectivePower(unit) > effect.MaxPower then
			return false, ("That only works on a unit with %d or less Power."):format(effect.MaxPower)
		end
		if effect.Kind == "Weaken" and unit.Power <= 1 and not effect.Bonus then
			return false, "That unit can't go below 1 Power."
		end
		if effect.Kind == "GiveStreak" and (unit.Streak or unit.TempStreak) then
			return false, "That unit already has Streak."
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
	if effect.Kind == "HealCommander" and not effect.Bonus then
		local player = self.Players[seat]
		if player.HP >= player.MaxHP then
			return false, "Your Commander is already at full HP."
		end
	end
	if effect.Kind == "PayForEnergy" and self.Players[seat].HP <= effect.HP then
		return false, "Your Commander doesn't have enough HP to pay."
	end
	local needsFriendly = { BuffAllFriendly = true, GrowAllFriendly = true, StreakAllFriendly = true,
		GrowStrongestFriendly = true, ShieldWeakestFriendly = true }
	if needsFriendly[effect.Kind] and not effect.Bonus and #self:_units(seat) == 0 then
		return false, "You have no units on the board."
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
		self:_afterHeal(seat, self:_healUnit(self:_unitAt(seat, target), effect.Amount))
	elseif kind == "HealCommander" then
		self:_afterHeal(seat, self:_healCommander(seat, effect.Amount))
	elseif kind == "HealAllFriendly" then
		local lanes = self.Players[seat].Lanes
		local healed = 0
		for lane = 1, Rules.Lanes do
			if lanes[lane] then
				healed = healed + self:_healUnit(lanes[lane], effect.Amount)
			end
		end
		if effect.IncludeCommander then
			healed = healed + self:_healCommander(seat, effect.Amount)
		end
		self:_afterHeal(seat, healed)
	elseif kind == "GiveShield" then
		self:_giveShield(self:_unitAt(seat, target), source)
	elseif kind == "ShieldWeakestFriendly" then
		-- your lowest-Power unit that doesn't have a Shield yet (ties: the lowest HP)
		local weakest
		for _, unit in ipairs(self:_units(seat)) do
			if not unit.Shield then
				local p, wp = effectivePower(unit), weakest and effectivePower(weakest)
				if not weakest or p < wp or (p == wp and unit.HP < weakest.HP) then
					weakest = unit
				end
			end
		end
		if weakest then
			self:_giveShield(weakest, source)
		end
	elseif kind == "ShieldAllFriendly" then
		local lanes = self.Players[seat].Lanes
		for lane = 1, Rules.Lanes do
			if lanes[lane] then
				self:_giveShield(lanes[lane], source)
			end
		end
	elseif kind == "Multi" then
		for _, part in ipairs(effect.Effects) do
			self:_applyEffect(seat, part, target, source)
		end
	elseif kind == "GiveGrow" then
		self:_giveGrow(self:_unitAt(seat, target), effect.Amount or 1, source)
	elseif kind == "GrowAllFriendly" then
		for _, unit in ipairs(self:_units(seat)) do
			if not (effect.Other and unit == self._placing) then
				self:_giveGrow(unit, effect.Amount or 1, source)
			end
		end
	elseif kind == "GrowStrongestFriendly" then
		local others = {}
		for _, unit in ipairs(self:_units(seat)) do
			if not (effect.Other and unit == self._placing) then
				table.insert(others, unit)
			end
		end
		local best = strongest(others)
		if best then
			self:_giveGrow(best, effect.Amount or 1, source)
		end
	elseif kind == "Weaken" then
		self:_weaken(self:_unitAt(seat, target), effect.Amount, source)
	elseif kind == "WeakenStrongestEnemy" then
		local best = strongest(self:_units(other(seat)))
		if best then
			self:_weaken(best, effect.Amount, source)
		end
	elseif kind == "WeakenAllEnemies" then
		for _, unit in ipairs(self:_units(other(seat))) do
			self:_weaken(unit, effect.Amount, source)
		end
	elseif kind == "Destroy" then
		self:_destroy(self:_unitAt(seat, target))
	elseif kind == "DestroyStrongestEnemy" then
		local best = strongest(self:_units(other(seat)), effect.MaxPower)
		if best then
			self:_destroy(best)
		end
	elseif kind == "DamageAllUnits" then
		for _, unit in ipairs(self:_units()) do
			if not (effect.Other and unit == self._placing) then
				self:_damageUnit(unit, effect.Amount)
			end
		end
	elseif kind == "DamageOtherEnemies" then
		-- every enemy unit except the one targeted by the same card
		local skip = self:_unitAt(seat, target)
		for _, unit in ipairs(self:_units(other(seat))) do
			if unit ~= skip then
				self:_damageUnit(unit, effect.Amount)
			end
		end
	elseif kind == "GiveStreak" then
		self:_giveStreak(self:_unitAt(seat, target), source)
	elseif kind == "StreakAllFriendly" then
		for _, unit in ipairs(self:_units(seat)) do
			if not (effect.Other and unit == self._placing) then
				self:_giveStreak(unit, source)
			end
		end
	elseif kind == "ReturnToHand" then
		self:_returnToHand(self:_unitAt(seat, target))
	elseif kind == "ReturnStrongestEnemy" then
		local best = strongest(self:_units(other(seat)), effect.MaxPower)
		if best then
			self:_returnToHand(best)
		end
	elseif kind == "ReturnAllEnemies" then
		for _, unit in ipairs(self:_units(other(seat))) do
			if not effect.MaxPower or effectivePower(unit) <= effect.MaxPower then
				self:_returnToHand(unit)
			end
		end
	elseif kind == "PayForEnergy" then
		local player = self.Players[seat]
		player.HP = player.HP - effect.HP
		player.Energy = player.Energy + effect.Energy
		self:_emit({ Type = "CommanderPaidHP", Player = seat, Amount = effect.HP, HP = player.HP })
		self:_emit({ Type = "EnergyGained", Player = seat, Amount = effect.Energy, Energy = player.Energy })
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
	if self.Phase == "Mulligan" then
		return false, "Choose your starting hand first."
	end
	if seat ~= self.Current then
		return false, "It's not your turn."
	end
	self._events = {}
	local turnBefore = self.Turn
	local ok, message = fn()
	if not ok then
		return false, message
	end
	if self.Turn == turnBefore then
		self:_checkLowHP()
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

-- Mulligan: send the cards at these hand positions back into the deck,
-- shuffle, and draw that many new ones. An empty list keeps the hand.
-- Each player does this once; the first turn starts when both are done.
function Battle:Mulligan(seat, handIndexes)
	if self.Winner then
		return false, "The match is over."
	end
	if self.Phase ~= "Mulligan" then
		return false, "The starting hands are already set."
	end
	local player = self.Players[seat]
	if not player then
		return false, "You're not in this match."
	end
	if player.MulliganDone then
		return false, "You've already chosen your hand."
	end
	-- check the picks: whole numbers, in the hand, no repeats
	local picks, seen = {}, {}
	for _, index in ipairs(type(handIndexes) == "table" and handIndexes or {}) do
		if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #player.Hand or seen[index] then
			return false, "Pick cards from your hand."
		end
		seen[index] = true
		table.insert(picks, index)
	end
	table.sort(picks, function(a, b) return a > b end)

	self._events = {}
	local opening = self.Stats and self.Stats[seat] and self.Stats[seat].Opening
	local returned = {}
	for _, index in ipairs(picks) do
		local cardId = table.remove(player.Hand, index)
		table.insert(returned, cardId)
		-- the match log's opening hand is the hand that was kept
		if opening then
			local at = table.find(opening, cardId)
			if at then
				table.remove(opening, at)
			end
		end
	end
	-- draw the replacements first, then shuffle the sent-back cards in
	-- (so you never draw the same card straight back)
	for _ = 1, #returned do
		self:_draw(seat)
	end
	if #returned > 0 then
		for _, cardId in ipairs(returned) do
			table.insert(player.Deck, cardId)
		end
		shuffle(player.Deck, self.Rng)
	end
	player.MulliganDone = true
	self:_emit({ Type = "Mulligan", Player = seat, Count = #picks })

	if self.Players[1].MulliganDone and self.Players[2].MulliganDone then
		self.Phase = nil
		self._dealing = false
		self:_startTurn(self.FirstPlayer)
	end
	return true, self._events
end

function Battle:GetCelestialCost(seat)
	local player = self.Players[seat]
	local card = CardDatabase.GetCard(player.StarGate.CardId)
	return math.max(0, card.EnergyCost + Rules.CelestialTax * player.StarGate.TimesReturned - (player.CelestialDiscount or 0))
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
		local hpCost = card.HPCost or 0
		if hpCost > 0 and player.HP <= hpCost then
			return false, ("Your Commander needs more than %d HP to pay for that."):format(hpCost)
		end
		local function payHP()
			if hpCost > 0 then
				player.HP = player.HP - hpCost
				self:_emit({ Type = "CommanderPaidHP", Player = seat, Amount = hpCost, HP = player.HP })
			end
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
			payHP()
			local unit = self:_newUnit(seat, cardId, false)
			self:_emit({ Type = "UnitPlayed", Player = seat, CardId = cardId, Lane = lane, Uid = unit.Uid })
			self:_placeUnit(seat, unit, lane)
			self:_triggerAnomalies(other(seat), "EnemyUnitPlayed", { Unit = unit })
			self:_removeDead()
			return true
		elseif card.Type == "Spell" then
			local ok, message = self:_checkEffect(seat, card.Effect, options.Target)
			if not ok then
				return false, message
			end
			table.remove(player.Hand, handIndex)
			player.Energy = player.Energy - card.EnergyCost
			payHP()
			self:_emit({ Type = "SpellCast", Player = seat, CardId = cardId, Target = options.Target })
			-- the other side's Anomalies get to react first (and may cancel it)
			local ctx = self:_triggerAnomalies(other(seat), "EnemySpell", { CardId = cardId })
			if not ctx.Cancelled and self:_checkEffect(seat, card.Effect, options.Target) then
				self:_applyEffect(seat, card.Effect, options.Target, card.Name)
			end
			table.insert(player.Discard, cardId)
			self:_removeDead()
			return true
		elseif card.Type == "Anomaly" then
			local slot
			for i = 1, #player.Anomalies do
				if not player.Anomalies[i] then
					slot = i
					break
				end
			end
			if not slot then
				return false, "Your Anomaly slots are full."
			end
			table.remove(player.Hand, handIndex)
			player.Energy = player.Energy - card.EnergyCost
			payHP()
			player.Anomalies[slot] = { CardId = cardId }
			self:_emit({ Type = "AnomalySet", Player = seat, Slot = slot, CardId = cardId })
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
		self:_triggerAnomalies(other(seat), "EnemyCelestial", { Unit = unit })
		self:_removeDead()
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
		self:_triggerAnomalies(other(seat), "EnemyAbility", {})
		if self:_checkEffect(seat, ability.Effect, target) then
			self:_applyEffect(seat, ability.Effect, target, CardDatabase.GetCard(player.CommanderId).Name .. "'s ability")
		end
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

		-- An attack that would reach the enemy Commander: their Anomalies can stop it
		local function hitCommander(attacker, lane, amount, streak)
			local ctx = self:_triggerAnomalies(other(seat), "CommanderAttacked", { Unit = attacker })
			if ctx.Prevented then
				self:_emit({ Type = "DamagePrevented", Player = other(seat), Lane = lane, Attacker = attacker.Uid,
					Amount = amount })
				return
			end
			if ctx.Removed or me.Lanes[lane] ~= attacker or attacker.HP <= 0 then
				return
			end
			enemy.HP = enemy.HP - amount
			self:_emit({ Type = "CommanderDamaged", Player = other(seat), Lane = lane,
				Attacker = attacker.Uid, Amount = amount, HP = enemy.HP, Streak = streak or nil })
			self:_checkLowHP()
		end

		-- Combat, lane by lane
		for lane = 1, Rules.Lanes do
			local attacker = me.Lanes[lane]
			local attacks = false
			if attacker and (attacker.SummonedTurn < self.Turn or attacker.Rush) then
				if attacker.Frozen then
					-- frozen by an Anomaly: it skips this attack, then thaws
					attacker.Frozen = nil
					self:_emit({ Type = "UnitThawed", Uid = attacker.Uid })
				else
					self:_triggerAnomalies(other(seat), "EnemyAttacks", { Unit = attacker })
					self:_removeDead()
					attacks = me.Lanes[lane] == attacker and attacker.HP > 0
				end
			end
			if attacks then
				local defender = enemy.Lanes[lane]
				local attackPower = effectivePower(attacker)
				local streaking = attacker.Streak or attacker.TempStreak
				-- Streak flies past the unit across, unless that unit also has Streak
				-- (they clash in the air) or Intercept (it's built to catch them)
				if defender and streaking and (defender.Streak or defender.TempStreak or defender.Intercept) then
					streaking = false
				end
				if defender and streaking and attackPower > 0 then
					-- Streak: flies past the unit across and hits the Commander; no hit back,
					-- but flying past costs a little damage (Rules.StreakPassPenalty)
					local amount = math.max(0, attackPower - (Rules.StreakPassPenalty or 0))
					if amount > 0 then
						hitCommander(attacker, lane, amount, true)
					end
				elseif defender and not streaking then
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
					hitCommander(attacker, lane, attackPower, false)
				end
			end
		end

		-- Grow: +Power for good (at the end of your turn, unless Rules.GrowTiming says
		-- "StartOfTurn"). Decay: the enemy unit across takes damage.
		if Rules.GrowTiming ~= "StartOfTurn" then
			self:_growAll(seat)
		end
		for lane = 1, Rules.Lanes do
			local unit = me.Lanes[lane]
			local across = enemy.Lanes[lane]
			if unit and across and unit.Decay > 0 then
				self:_emit({ Type = "Decay", Uid = unit.Uid, Target = across.Uid, Amount = unit.Decay })
				self:_damageUnit(across, unit.Decay)
			end
		end
		self:_removeDead()

		-- Temporary buffs wear off; Regen units heal
		for lane = 1, Rules.Lanes do
			local unit = me.Lanes[lane]
			if unit then
				unit.TempPower = 0
				unit.TempStreak = false
				unit.StreakSource = nil
				-- this-turn boosts wear off
				for i = #unit.Buffs, 1, -1 do
					if unit.Buffs[i].Temporary then
						table.remove(unit.Buffs, i)
					end
				end
				if unit.Regen > 0 then
					self:_afterHeal(seat, self:_healUnit(unit, unit.Regen))
				end
			end
		end

		self:_checkLowHP()

		-- Cosmic Storm: late in the match each Commander takes growing damage at the
		-- end of their own turn. A win from this turn's attacks counts first.
		self:_checkWinner()
		local round = math.ceil(self.Turn / 2)
		if not self.Winner and Rules.StormStartRound and round >= Rules.StormStartRound then
			local amount = round - Rules.StormStartRound + 1
			me.HP = me.HP - amount
			self:_emit({ Type = "StormDamage", Player = seat, Amount = amount, HP = me.HP })
		end

		self:_triggerAnomalies(other(seat), "EnemyTurnEnd", {})
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
		Grow = unit.Grow,
		Decay = unit.Decay,
		Streak = unit.Streak or unit.TempStreak,
		Intercept = unit.Intercept or nil,
		Frozen = unit.Frozen or nil,
		StreakThisTurn = unit.TempStreak or nil,
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
		Phase = self.Phase, -- "Mulligan" while starting hands are being chosen
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
				view.CanAttack = (unit.Rush or unit.SummonedTurn < self.Turn) and not unit.Frozen
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
			MulliganDone = player.MulliganDone,
			DiscardCount = #player.Discard,
			Discard = copyList(player.Discard), -- the graveyard (oldest first); everyone can look
			Lanes = lanes,
			-- Face-down Anomalies: the owner sees which card; the opponent only sees that one is set
			Anomalies = (function()
				local list = {}
				for slot, set in ipairs(player.Anomalies) do
					list[slot] = set and { Set = true, CardId = isYou and set.CardId or nil } or false
				end
				return list
			end)(),
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

-- Hides the opponent's drawn cards and face-down Anomalies from event lists before sending them to a player
function BattleEngine.FilterEvents(events, viewer)
	local out = {}
	for i, event in ipairs(events) do
		if event.Type == "Draw" and event.Player ~= viewer then
			out[i] = { Type = "Draw", Player = event.Player }
		elseif event.Type == "AnomalySet" and event.Player ~= viewer then
			out[i] = { Type = "AnomalySet", Player = event.Player, Slot = event.Slot }
		else
			out[i] = event
		end
	end
	return out
end

return BattleEngine