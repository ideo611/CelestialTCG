--[[
	CardDatabase (ModuleScript)
	Location: ReplicatedStorage > CardDatabase

	Holds every card's data plus deck-building rules and validation.
	Shared by server and client (card stats aren't secret).
	Add new cards with addCard{ ... } in the matching faction section.

	Effects (what the battle engine actually runs):
	  Spells use Effect = {...}; units can use OnPlay = {...}.
	  Kinds: Draw {Count}, DamageUnit {Amount, Target}, DamageAllEnemies {Amount},
	         DamageStrongestEnemy {Amount}  (picks the enemy unit with the most Power, then most HP),
	         BuffUnit {Power, Target}, BuffAllFriendly {Power, Faction?, Other?}  (Other = not the card itself),
	         TempBuff {Power, Target, Faction?}  (lasts until end of turn),
	         HealUnit {Amount, Target}, HealCommander {Amount},
	         HealAllFriendly {Amount, IncludeCommander?},
	         GiveShield {Target}, ShieldAllFriendly {},
	         GiveGrow {Amount, Target}, GrowAllFriendly {Amount, Other?}, GrowStrongestFriendly {Amount, Other?}, ShieldWeakestFriendly {},
	         Weaken {Amount, Target}, WeakenStrongestEnemy {Amount}, WeakenAllEnemies {Amount}  (never below 1 Power),
	         Destroy {Target, MaxPower?}, DestroyStrongestEnemy {MaxPower?},
	         DamageAllUnits {Amount, Other?}, DamageOtherEnemies {Amount}  (all enemies but the target),
	         GiveStreak {Target}, StreakAllFriendly {Other?}  (Streak until the end of this turn),
	         ReturnToHand {Target, MaxPower?}, ReturnStrongestEnemy {MaxPower?}, ReturnAllEnemies {MaxPower?},
	         PayForEnergy {HP, Energy}  (Commander takes HP damage, gains energy this turn),
	         Multi {Effects = {...}, Target?}  (several effects in a row, sharing one target)
	  Target: "AnyUnit", "FriendlyUnit" or "EnemyUnit". MaxPower = only units with that much Power or less.
	  Bonus = true on a part of a Multi that shouldn't block the card (e.g. a heal at full HP).

	Keywords: Rush, Shield, Ignite = X, Regen = X (heals X at the end of your turn),
	  Grow = X (+X Power for good at the start of your turn; see Rules.GrowTiming), Decay = X (at the end of your turn
	  the enemy unit across takes X), Streak = true (attacks the enemy Commander directly)
	HPCost = X: playing the card also costs X of your Commander's HP.

	Anomalies (Type = "Anomaly"): set face-down in one of your Anomaly slots on
	your turn (they all cost Rules.AnomalyCost energy, so the energy you spend
	doesn't give away which one it is). During your opponent's turn, the first
	time its Trigger happens it flips up, its Effect runs, and it goes to the
	graveyard.
	  Triggers: EnemyUnitPlayed, EnemyCelestial, EnemyAttacks, CommanderAttacked,
	            EnemySpell, EnemyAbility, FriendlyUnitDestroyed, LowHP (your
	            Commander drops below Rules.AnomalyLowHP), EnemyTurnEnd
	  Extra effect kinds for Anomalies (the "trigger unit" is the unit that set it off):
	    DamageTrigger {Amount}, WeakenTrigger {Amount}, FreezeTrigger (it skips its next attack),
	    ReturnTrigger {Tax?} (to its owner's hand; a Celestial goes back to its Star Gate,
	      and Tax = true makes summoning it again cost Rules.CelestialTax more),
	    CancelSpell (the spell does nothing; its energy stays spent),
	    PreventDamage (the attack doesn't hurt your Commander),
	    ReturnDestroyed (the destroyed card goes back to your hand),
	    DamageEnemyCommander {Amount}, GrowWeakestFriendly {Amount}
	  plus any normal effect that needs no target (Draw, HealCommander, ShieldAllFriendly...).
]]

local CardDatabase = {}

---------------------------------------------------------------------
-- BALANCE VERSION: change this whenever you change cards or rules, so the
-- match log can compare games before and after the change. (The log also
-- fingerprints every card automatically, as a backup.)
---------------------------------------------------------------------
CardDatabase.BalanceVersion = "2026-10-05-balance-22"

---------------------------------------------------------------------
-- GAME RULES (draft values from the design doc)
---------------------------------------------------------------------
CardDatabase.Rules = {
	DeckSize = 30,
	MaxCopies = 3,
	LegendaryMaxCopies = 1, -- Legendary units and spells are one-ofs
	StarCap = 70,          -- draft; finalize after more cards exist
	CommanderHP = 20,
	StartingEnergy = 1,
	MaxEnergy = 10,
	StartingHand = 4,
	Lanes = 3,
	CelestialTax = 2,      -- extra energy each time a Celestial is re-summoned

	-- Catch-up help for whoever goes second (going first is a big advantage)
	SecondPlayerBonusCards = 1, -- extra card in the opening hand
	SecondPlayerBonusHP = 0,    -- extra Commander HP (was 3; the second player was winning 60%)
	SecondPlayerSpark = true,   -- a one-time +1 energy boost they can use on any turn

	-- Cosmic Storm: from this round on, each Commander takes damage at the end of
	-- their turn (1, then 2, then 3...). Keeps defensive matches from dragging on.
	StormStartRound = 9,

	-- Grow timing: "StartOfTurn" = a Grow unit first grows at the start of your next
	-- turn (after it has survived one enemy turn), then every turn after.
	-- "EndOfTurn" = it grows at the end of your turn, even the turn it was played.
	GrowTiming = "StartOfTurn",
	-- Grow given by effects (Seraphine, Nursery Spark...) stacks up to this much on a unit
	-- (a card printed with more, like Grow 2, keeps its own). nil = no limit.
	MaxGrow = 2,
	-- Streak flying past a unit loses this much damage on the way (no unit across = full hit)
	StreakPassPenalty = 0, -- tried 1: far too strong a nerf (Comet fell to 38%)
	-- Overflow (extra combat damage carries to the Commander). Tested; off for now.
	Overflow = false,

	-- Anomalies: face-down cards that trigger on the opponent's turn.
	-- ON/OFF SWITCH: false takes them out of the game without deleting anything:
	-- no Anomaly slots in matches, none in packs, none in the deck builder or
	-- starters, and saved decks holding them show as not ready until they're swapped out.
	-- Cards players already own stay in their collections.
	AnomaliesEnabled = false,
	AnomalySlots = 2,
	AnomalyCost = 2,     -- every Anomaly costs the same energy, so setting one gives nothing away
	AnomalyLowHP = 10,   -- "LowHP" Anomalies trigger when your Commander drops below this
}

CardDatabase.Factions = { "Solar", "Lunar", "Nebula", "Void", "Comet", "Neutral" }
CardDatabase.Rarities = { "Common", "Rare", "Epic", "Legendary" }
CardDatabase.Types = { "Unit", "Spell", "Anomaly", "Commander", "Celestial" }

-- Most copies of a card one deck can hold (Legendary deck cards are one-ofs)
function CardDatabase.MaxCopiesFor(cardOrId)
	local card = type(cardOrId) == "table" and cardOrId or CardDatabase.GetCard(cardOrId)
	if card and card.Rarity == "Legendary" and CardDatabase.IsMainDeckType(card.Type) then
		return CardDatabase.Rules.LegendaryMaxCopies or CardDatabase.Rules.MaxCopies
	end
	return CardDatabase.Rules.MaxCopies
end

-- Cards that go in the 30-card main deck
function CardDatabase.IsMainDeckType(cardType)
	if cardType == "Anomaly" then
		return CardDatabase.Rules.AnomaliesEnabled ~= false
	end
	return cardType == "Unit" or cardType == "Spell"
end

CardDatabase.AnomalyTriggers = {
	EnemyUnitPlayed = "When an enemy unit is played",
	EnemyCelestial = "When the enemy summons their Celestial",
	EnemyAttacks = "When an enemy unit attacks",
	CommanderAttacked = "When an enemy unit would damage your Commander",
	EnemySpell = "When the enemy casts a spell",
	EnemyAbility = "When the enemy uses their Commander's ability",
	FriendlyUnitDestroyed = "When one of your units is destroyed",
	LowHP = "When your Commander drops below 10 HP",
	EnemyTurnEnd = "When the enemy ends their turn",
}

-- Finishes a card can be pulled in. Mythic is a cosmetic finish, not a separate card.
CardDatabase.Finishes = { "Base", "Holo", "Textured", "3D", "Mythic" }

local PLACEHOLDER_ART = "rbxassetid://0" -- swap in real image IDs later

---------------------------------------------------------------------
-- CARD REGISTRY
---------------------------------------------------------------------
local Cards = {}
local CardOrder = {} -- keeps cards in the order they were added

local function listContains(list, value)
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

local EFFECT_KINDS = {
	Draw = true, DamageUnit = true, DamageAllEnemies = true, BuffUnit = true,
	BuffAllFriendly = true, TempBuff = true, HealUnit = true, HealCommander = true,
	HealAllFriendly = true, GiveShield = true, ShieldAllFriendly = true, DamageStrongestEnemy = true,
	GiveGrow = true, GrowAllFriendly = true, GrowStrongestFriendly = true, ShieldWeakestFriendly = true,
	Weaken = true, WeakenStrongestEnemy = true, WeakenAllEnemies = true,
	Destroy = true, DestroyStrongestEnemy = true, DamageAllUnits = true, DamageOtherEnemies = true,
	GiveStreak = true, StreakAllFriendly = true,
	ReturnToHand = true, ReturnStrongestEnemy = true, ReturnAllEnemies = true,
	PayForEnergy = true, Reignite = true, Multi = true,
}
local TARGETS = { AnyUnit = true, FriendlyUnit = true, EnemyUnit = true }
-- Only Anomalies can use these (they act on whatever set the Anomaly off)
local ANOMALY_KINDS = {
	DamageTrigger = true, WeakenTrigger = true, FreezeTrigger = true, ReturnTrigger = true,
	CancelSpell = true, PreventDamage = true, ReturnDestroyed = true,
	DamageEnemyCommander = true, GrowWeakestFriendly = true,
}
CardDatabase.AnomalyEffectKinds = ANOMALY_KINDS

local function checkEffect(id, effect, anomaly)
	assert(EFFECT_KINDS[effect.Kind] or (anomaly and ANOMALY_KINDS[effect.Kind]),
		id .. ": unknown effect kind " .. tostring(effect.Kind))
	if effect.Target then
		assert(TARGETS[effect.Target], id .. ": bad effect Target")
	end
	if effect.Kind == "Multi" then
		assert(type(effect.Effects) == "table" and #effect.Effects > 0, id .. ": Multi needs Effects")
		local targeted = nil
		for _, part in ipairs(effect.Effects) do
			checkEffect(id, part, anomaly)
			if part.Target then
				assert(not targeted or targeted == part.Target, id .. ": Multi parts must share one target type")
				targeted = part.Target
			end
		end
		assert(effect.Target == targeted, id .. ": set the Multi's Target to its parts' target")
	end
end

-- Cards that are finished but not in the game yet (waiting for art). They
-- aren't registered at all: not in packs, decks, the collection or the shop.
-- Delete an Id from this list once its art is uploaded (CardArt) to release it.
CardDatabase.Unreleased = {
	["SOL-026"] = true, ["SOL-027"] = true, -- Dawnbreaker Phoenix, Daybreak
	["LUN-027"] = true, ["LUN-028"] = true, -- High Tide Oracle, Full Moon Rite
	["NEB-027"] = true, ["NEB-028"] = true, -- Nursery Matriarch, Cosmic Bloom
	["VOI-027"] = true, ["VOI-028"] = true, -- Eclipse Wraith, Devour
	["COM-026"] = true, ["COM-027"] = true, -- Starwake Rider, Meteor Shower
}
CardDatabase.HeldBack = {} -- [id] = card, for the ones above

local function addCard(card)
	assert(type(card.Id) == "string", "Card is missing an Id")
	if CardDatabase.Unreleased[card.Id] then
		CardDatabase.HeldBack[card.Id] = card
		return
	end
	assert(Cards[card.Id] == nil, "Duplicate card Id: " .. card.Id)
	assert(listContains(CardDatabase.Factions, card.Faction), card.Id .. ": bad Faction")
	assert(listContains(CardDatabase.Types, card.Type), card.Id .. ": bad Type")
	assert(listContains(CardDatabase.Rarities, card.Rarity), card.Id .. ": bad Rarity")

	card.Keywords = card.Keywords or {}
	card.ArtId = card.ArtId or PLACEHOLDER_ART
	card.AbilityText = card.AbilityText or ""

	if card.HPCost then
		assert(type(card.HPCost) == "number" and card.HPCost > 0, card.Id .. ": HPCost must be a positive number")
	end
	if card.Type ~= "Commander" then
		assert(type(card.StarCost) == "number" and card.StarCost >= 1 and card.StarCost <= 5,
			card.Id .. ": StarCost must be 1-5")
		assert(type(card.EnergyCost) == "number", card.Id .. ": missing EnergyCost")
	end
	if card.Type == "Unit" or card.Type == "Celestial" then
		assert(type(card.Power) == "number" and type(card.HP) == "number",
			card.Id .. ": units and Celestials need Power and HP")
	end
	if card.Type == "Celestial" then
		assert(type(card.PairsWith) == "table" and #card.PairsWith > 0,
			card.Id .. ": Celestials need PairsWith")
	end
	if card.Type == "Spell" then
		assert(type(card.Effect) == "table", card.Id .. ": spells need an Effect")
	end
	if card.Type == "Anomaly" then
		assert(type(card.Effect) == "table", card.Id .. ": Anomalies need an Effect")
		assert(CardDatabase.AnomalyTriggers[card.Trigger], card.Id .. ": bad Anomaly Trigger")
		assert(card.EnergyCost == CardDatabase.Rules.AnomalyCost,
			card.Id .. ": every Anomaly costs Rules.AnomalyCost energy")
		assert(not card.Effect.Target, card.Id .. ": Anomalies pick their own targets")
	end
	if card.Type == "Commander" then
		assert(type(card.CommanderAbility) == "table" and type(card.CommanderAbility.Effect) == "table",
			card.Id .. ": Commanders need a CommanderAbility with an Effect")
		checkEffect(card.Id, card.CommanderAbility.Effect)
	end
	if card.Effect then
		checkEffect(card.Id, card.Effect, card.Type == "Anomaly")
	end
	if card.OnPlay then
		checkEffect(card.Id, card.OnPlay)
	end

	Cards[card.Id] = card
	table.insert(CardOrder, card.Id)
end

---------------------------------------------------------------------
-- COMMANDERS
---------------------------------------------------------------------
addCard {
	Id = "CMD-SOL-01",
	Name = "Captain Sol Varro",
	Faction = "Solar",
	Type = "Commander",
	Rarity = "Legendary",
	HP = 20,
	CommanderAbility = {
		EnergyCost = 2,
		Text = "A Solar unit gets +2 Power this turn.",
		Effect = { Kind = "TempBuff", Power = 2, Target = "FriendlyUnit", Faction = "Solar" },
	},
	Starter = true,
}

addCard {
	Id = "CMD-LUN-01",
	Name = "Tidekeeper Selene",
	Faction = "Lunar",
	Type = "Commander",
	Rarity = "Legendary",
	HP = 20,
	CommanderAbility = {
		EnergyCost = 3,
		Text = "Give one of your units a Shield.",
		Effect = { Kind = "GiveShield", Target = "FriendlyUnit" },
	},
	Starter = true,
}

addCard {
	Id = "CMD-SOL-02",
	Name = "Ignara, the Forge-Mother",
	Faction = "Solar",
	Type = "Commander",
	Rarity = "Legendary",
	HP = 20,
	CommanderAbility = {
		EnergyCost = 4,
		Text = "Reignite: each of your units with Ignite hits the enemy unit across from it again.",
		Effect = { Kind = "Reignite" },
	},
}

addCard {
	Id = "CMD-LUN-02",
	Name = "Lyra, the Night Archivist",
	Faction = "Lunar",
	Type = "Commander",
	Rarity = "Legendary",
	HP = 20,
	CommanderAbility = {
		EnergyCost = 3,
		Text = "Give one of your units +2 Power.",
		Effect = { Kind = "BuffUnit", Power = 2, Target = "FriendlyUnit" },
	},
}

addCard {
	Id = "CMD-NEB-01",
	Name = "Seraphine, the Star-Nursery",
	Faction = "Nebula",
	Type = "Commander",
	Rarity = "Legendary",
	HP = 20,
	CommanderAbility = {
		EnergyCost = 2,
		Text = "Give one of your units +1 Power and Grow 1.",
		Effect = { Kind = "Multi", Target = "FriendlyUnit", Effects = {
			{ Kind = "BuffUnit", Power = 1, Target = "FriendlyUnit" },
			{ Kind = "GiveGrow", Amount = 1, Target = "FriendlyUnit", Bonus = true },
		} },
	},
	Starter = true,
}

addCard {
	Id = "CMD-NEB-02",
	Name = "Orion, the Cloud Sage",
	Faction = "Nebula",
	Type = "Commander",
	Rarity = "Legendary",
	HP = 20,
	CommanderAbility = {
		EnergyCost = 2,
		Text = "All your units get +1 Power permanently.",
		Effect = { Kind = "BuffAllFriendly", Power = 1 },
	},
}

addCard {
	Id = "CMD-VOI-01",
	Name = "Malakar, the Hollow King",
	Faction = "Void",
	Type = "Commander",
	Rarity = "Legendary",
	HP = 20,
	CommanderAbility = {
		EnergyCost = 2,
		Text = "Your Commander takes 2 damage. Gain 3 energy this turn.",
		Effect = { Kind = "PayForEnergy", HP = 2, Energy = 3 },
	},
}

addCard {
	Id = "CMD-VOI-02",
	Name = "Nyx, the Event Horizon",
	Faction = "Void",
	Type = "Commander",
	Rarity = "Legendary",
	HP = 20,
	CommanderAbility = {
		EnergyCost = 2,
		Text = "Deal 1 damage to an enemy unit. It gets -1 Power permanently (not below 1).",
		Effect = { Kind = "Multi", Target = "EnemyUnit", Effects = {
			{ Kind = "DamageUnit", Amount = 1, Target = "EnemyUnit" },
			{ Kind = "Weaken", Amount = 1, Target = "EnemyUnit", Bonus = true },
		} },
	},
	Starter = true,
}

addCard {
	Id = "CMD-COM-01",
	Name = "Halley Voss, Comet Rider",
	Faction = "Comet",
	Type = "Commander",
	Rarity = "Legendary",
	HP = 20,
	CommanderAbility = {
		EnergyCost = 3,
		Text = "One of your units gets Streak this turn.",
		Effect = { Kind = "GiveStreak", Target = "FriendlyUnit" },
	},
	Starter = true,
}

addCard {
	Id = "CMD-COM-02",
	Name = "Kessa Frostwake",
	Faction = "Comet",
	Type = "Commander",
	Rarity = "Legendary",
	HP = 20,
	CommanderAbility = {
		EnergyCost = 2,
		Text = "Return one of your units to your hand.",
		Effect = { Kind = "ReturnToHand", Target = "FriendlyUnit" },
	},
}

---------------------------------------------------------------------
-- CELESTIALS
---------------------------------------------------------------------
addCard {
	Id = "CEL-04",
	Name = "Flare Stallion",
	Faction = "Solar", -- primary faction for sorting; legality uses PairsWith
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 7,
	StarCost = 5,
	Power = 7,
	HP = 6,
	Keywords = { Rush = true },
	PairsWith = { "Solar", "Comet" },
}

addCard {
	Id = "CEL-05",
	Name = "Moonveil Jellyfish",
	Faction = "Lunar",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 7,
	StarCost = 5,
	Power = 6,
	HP = 9,
	Keywords = { Regen = 1 },
	AbilityText = "When summoned, heal your Commander 5.",
	OnPlay = { Kind = "HealCommander", Amount = 5 },
	PairsWith = { "Lunar", "Nebula" },
}

addCard {
	Id = "CEL-06",
	Name = "Umbra, the Eclipse Wyrm",
	Faction = "Lunar",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 7,
	StarCost = 5,
	Power = 6,
	HP = 7,
	Keywords = { Shield = true },
	AbilityText = "When summoned, destroy the strongest enemy unit with 4 or less Power.",
	OnPlay = { Kind = "DestroyStrongestEnemy", MaxPower = 4 },
	PairsWith = { "Lunar", "Void" },
}

addCard {
	Id = "CEL-07",
	Name = "Protostar Colossus",
	Faction = "Solar",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 7,
	StarCost = 5,
	Power = 7,
	HP = 8,
	Keywords = { Ignite = 1 },
	AbilityText = "When summoned, all your units get Grow 1 and your other units get +1 Power.",
	OnPlay = { Kind = "Multi", Effects = {
		{ Kind = "GrowAllFriendly", Amount = 1 },
		{ Kind = "BuffAllFriendly", Power = 1, Other = true },
	} },
	PairsWith = { "Solar", "Nebula" },
}

addCard {
	Id = "CEL-08",
	Name = "Equinox Seraph",
	Faction = "Solar",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 7,
	StarCost = 4,
	Power = 6,
	HP = 7,
	Keywords = { Shield = true, Ignite = 2 },
	AbilityText = "When summoned, give all your units a Shield.",
	OnPlay = { Kind = "ShieldAllFriendly" },
	PairsWith = { "Solar", "Lunar" },
}

addCard {
	Id = "CEL-09",
	Name = "Black Sun Harbinger",
	Faction = "Solar",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 7,
	StarCost = 4,
	Power = 7,
	HP = 7,
	AbilityText = "When summoned, deal 2 damage to every other unit, yours included.",
	OnPlay = { Kind = "DamageAllUnits", Amount = 2, Other = true },
	PairsWith = { "Solar", "Void" },
}

addCard {
	Id = "CEL-10",
	Name = "Tidewake Leviathan",
	Faction = "Lunar",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 7,
	StarCost = 5,
	Power = 5,
	HP = 7,
	AbilityText = "When summoned, return the strongest enemy unit with 6 or less Power to its owner's hand.",
	OnPlay = { Kind = "ReturnStrongestEnemy", MaxPower = 6 },
	PairsWith = { "Lunar", "Comet" },
}

addCard {
	Id = "CEL-11",
	Name = "Pulsar Remnant",
	Faction = "Void",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 7,
	StarCost = 5,
	Power = 7,
	HP = 8,
	Keywords = { Grow = 1, Decay = 1 },
	PairsWith = { "Nebula", "Void" },
}

addCard {
	Id = "CEL-12",
	Name = "Aurora Skywhale",
	Faction = "Nebula",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 7,
	StarCost = 5,
	Power = 6,
	HP = 8,
	Keywords = { Grow = 1 },
	AbilityText = "When summoned, draw 2 cards.",
	OnPlay = { Kind = "Draw", Count = 2 },
	PairsWith = { "Nebula", "Comet" },
}

addCard {
	Id = "CEL-13",
	Name = "Oort Reaper",
	Faction = "Comet",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 7,
	StarCost = 5,
	Power = 6,
	HP = 7,
	Keywords = { Streak = true, Decay = 1 },
	PairsWith = { "Void", "Comet" },
}

---------------------------------------------------------------------
-- SOLAR
---------------------------------------------------------------------
addCard {
	Id = "SOL-001", Name = "Ember Scout", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 2, Power = 2, HP = 1,
	Keywords = { Rush = true },
}

addCard {
	Id = "SOL-002", Name = "Kindle", Faction = "Solar", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 2,
	AbilityText = "A unit gets +2 Power permanently.",
	Effect = { Kind = "BuffUnit", Power = 2, Target = "AnyUnit" },
}

addCard {
	Id = "SOL-003", Name = "Sunforge Cadet", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 2, HP = 3,
}

addCard {
	Id = "SOL-004", Name = "Flarecat", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 3, Power = 3, HP = 2,
	Keywords = { Rush = true },
}

addCard {
	Id = "SOL-005", Name = "Solar Flare", Faction = "Solar", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 2,
	AbilityText = "Deal 3 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 3, Target = "AnyUnit" },
}

addCard {
	Id = "SOL-006", Name = "Cinder Guard", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 3, Power = 2, HP = 5,
	Keywords = { Shield = true },
}

addCard {
	Id = "SOL-007", Name = "Solar Lancer", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 3, Power = 4, HP = 3,
	Keywords = { Ignite = 1 },
}

addCard {
	Id = "SOL-008", Name = "Blazewing Hawk", Faction = "Solar", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3, Power = 4, HP = 3,
	Keywords = { Rush = true, Ignite = 1 },
}

addCard {
	Id = "SOL-009", Name = "Heat Wave", Faction = "Solar", Type = "Spell", Rarity = "Rare",
	EnergyCost = 4, StarCost = 2,
	AbilityText = "Deal 2 damage to all enemy units.",
	Effect = { Kind = "DamageAllEnemies", Amount = 2 },
}

addCard {
	Id = "SOL-010", Name = "Corona Knight", Faction = "Solar", Type = "Unit", Rarity = "Rare",
	EnergyCost = 5, StarCost = 4, Power = 5, HP = 5,
	Keywords = { Shield = true },
}

addCard {
	Id = "SOL-011", Name = "Dawnbreaker Titan", Faction = "Solar", Type = "Unit", Rarity = "Epic",
	EnergyCost = 7, StarCost = 3, Power = 7, HP = 7,
	Keywords = { Ignite = 3 },
}

-- Pack-only
addCard {
	Id = "SOL-012", Name = "Varro's Rally", Faction = "Solar", Type = "Spell", Rarity = "Epic",
	EnergyCost = 2, StarCost = 2,
	CommanderOnly = "CMD-SOL-01",
	AbilityText = "All your Solar units get +1 Power permanently. Draw a card.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "BuffAllFriendly", Power = 1, Faction = "Solar" },
		{ Kind = "Draw", Count = 1, Bonus = true },
	} },
}

addCard {
	Id = "SOL-013", Name = "Heart of the Sun", Faction = "Solar", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 7, StarCost = 4, Power = 8, HP = 8,
	Keywords = { Rush = true },
	AbilityText = "When played, deal 3 damage to all enemy units.",
	OnPlay = { Kind = "DamageAllEnemies", Amount = 3 },
}

-- Added so the starter can use 1-2 copies of more cards (packs then fill out playsets)
addCard {
	Id = "SOL-014", Name = "Spark Sprite", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 1, Power = 1, HP = 2,
	Keywords = { Ignite = 1 },
}

addCard {
	Id = "SOL-015", Name = "Sunburst", Faction = "Solar", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 2,
	AbilityText = "Deal 2 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 2, Target = "AnyUnit" },
}

addCard {
	Id = "SOL-016", Name = "Forge Hound", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 2, HP = 2,
	Keywords = { Ignite = 1 },
}

addCard {
	Id = "SOL-017", Name = "Ember Drummer", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 2, HP = 3,
	AbilityText = "When played, deal 1 damage to all enemy units.",
	OnPlay = { Kind = "DamageAllEnemies", Amount = 1 },
}

addCard {
	Id = "SOL-018", Name = "Magma Brute", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 4, StarCost = 3, Power = 5, HP = 4,
}

addCard {
	Id = "SOL-019", Name = "Sunstrike", Faction = "Solar", Type = "Spell", Rarity = "Common",
	EnergyCost = 4, StarCost = 3,
	AbilityText = "Deal 5 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 5, Target = "AnyUnit" },
}

addCard {
	Id = "SOL-020", Name = "Solar Phoenix", Faction = "Solar", Type = "Unit", Rarity = "Rare",
	EnergyCost = 5, StarCost = 3, Power = 5, HP = 3,
	Keywords = { Rush = true, Ignite = 2 },
}

addCard {
	Id = "SOL-021", Name = "Nova Burst", Faction = "Solar", Type = "Spell", Rarity = "Rare",
	EnergyCost = 5, StarCost = 2,
	AbilityText = "Deal 3 damage to all enemy units.",
	Effect = { Kind = "DamageAllEnemies", Amount = 3 },
}

addCard {
	Id = "SOL-022", Name = "Blaze Marshal", Faction = "Solar", Type = "Unit", Rarity = "Epic",
	EnergyCost = 5, StarCost = 3, Power = 5, HP = 5,
	AbilityText = "When played, all your Solar units get +1 Power permanently.",
	OnPlay = { Kind = "BuffAllFriendly", Power = 1, Faction = "Solar" },
}

---------------------------------------------------------------------
-- LUNAR
---------------------------------------------------------------------
addCard {
	Id = "LUN-001", Name = "Moonlit Wisp", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 1, Power = 1, HP = 2,
	Keywords = { Regen = 1 },
}

addCard {
	Id = "LUN-002", Name = "Tidal Blessing", Faction = "Lunar", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 3,
	AbilityText = "Heal your Commander 4.",
	Effect = { Kind = "HealCommander", Amount = 4 },
}

addCard {
	Id = "LUN-003", Name = "Silver Barrier", Faction = "Lunar", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 2,
	AbilityText = "Give one of your units a Shield. Draw a card.",
	Effect = { Kind = "Multi", Target = "FriendlyUnit", Effects = {
		{ Kind = "GiveShield", Target = "FriendlyUnit" },
		{ Kind = "Draw", Count = 1, Bonus = true },
	} },
}

addCard {
	Id = "LUN-004", Name = "Crescent Archer", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 3, HP = 2,
}

addCard {
	Id = "LUN-005", Name = "Tide Sentinel", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 3, Power = 3, HP = 2,
	Keywords = { Shield = true, Intercept = true },
}

addCard {
	Id = "LUN-006", Name = "Moonbeam", Faction = "Lunar", Type = "Spell", Rarity = "Common",
	EnergyCost = 3, StarCost = 1,
	AbilityText = "Deal 3 damage to a unit. Heal your Commander 2.",
	Effect = { Kind = "Multi", Target = "AnyUnit", Effects = {
		{ Kind = "DamageUnit", Amount = 3, Target = "AnyUnit" },
		{ Kind = "HealCommander", Amount = 2, Bonus = true },
	} },
}

addCard {
	Id = "LUN-007", Name = "Harbor Warden", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 4, Power = 3, HP = 5,
	Keywords = { Regen = 1 },
}

addCard {
	Id = "LUN-008", Name = "Lunar Priestess", Faction = "Lunar", Type = "Unit", Rarity = "Rare",
	EnergyCost = 3, StarCost = 2, Power = 3, HP = 3,
	AbilityText = "When played, heal all your units 3.",
	OnPlay = { Kind = "HealAllFriendly", Amount = 3 },
}

addCard {
	Id = "LUN-009", Name = "Eclipse Veil", Faction = "Lunar", Type = "Spell", Rarity = "Rare",
	EnergyCost = 3, StarCost = 2,
	AbilityText = "Give all your units a Shield.",
	Effect = { Kind = "ShieldAllFriendly" },
}

addCard {
	Id = "LUN-010", Name = "Silver Knight", Faction = "Lunar", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 5, Power = 4, HP = 5,
	Keywords = { Shield = true },
}

addCard {
	Id = "LUN-011", Name = "Tide Colossus", Faction = "Lunar", Type = "Unit", Rarity = "Epic",
	EnergyCost = 6, StarCost = 3, Power = 5, HP = 7,
	Keywords = { Regen = 1, Intercept = true },
}

-- Pack-only
addCard {
	Id = "LUN-012", Name = "Selene's Tide", Faction = "Lunar", Type = "Spell", Rarity = "Epic",
	EnergyCost = 3, StarCost = 2,
	CommanderOnly = "CMD-LUN-01",
	AbilityText = "Heal all your units and your Commander 4.",
	Effect = { Kind = "HealAllFriendly", Amount = 4, IncludeCommander = true },
}

addCard {
	Id = "LUN-013", Name = "Moon Leviathan", Faction = "Lunar", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 7, StarCost = 4, Power = 6, HP = 12,
	Keywords = { Shield = true, Regen = 3 },
}

-- Added so the starter can use 1-2 copies of more cards (packs then fill out playsets)
addCard {
	Id = "LUN-014", Name = "Pearl Crab", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 2, Power = 1, HP = 2,
	Keywords = { Shield = true },
}

addCard {
	Id = "LUN-015", Name = "Stargazer's Chart", Faction = "Lunar", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 3,
	AbilityText = "Draw 2 cards.",
	Effect = { Kind = "Draw", Count = 2 },
}

addCard {
	Id = "LUN-016", Name = "Reef Guardian", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 2, Power = 2, HP = 3,
	Keywords = { Regen = 1, Intercept = true },
}

addCard {
	Id = "LUN-017", Name = "Silver Mender", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 3, Power = 2, HP = 4,
	AbilityText = "When played, heal your Commander 3.",
	OnPlay = { Kind = "HealCommander", Amount = 3 },
}

addCard {
	Id = "LUN-018", Name = "Tide Caller", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 4, StarCost = 2, Power = 3, HP = 6,
	Keywords = { Regen = 1 },
}

addCard {
	Id = "LUN-019", Name = "Undertow", Faction = "Lunar", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 2,
	AbilityText = "Deal 2 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 2, Target = "AnyUnit" },
}

addCard {
	Id = "LUN-020", Name = "Crescent Warden", Faction = "Lunar", Type = "Unit", Rarity = "Rare",
	EnergyCost = 5, StarCost = 3, Power = 4, HP = 7,
	Keywords = { Shield = true, Regen = 1 },
}

addCard {
	Id = "LUN-021", Name = "Riptide", Faction = "Lunar", Type = "Spell", Rarity = "Rare",
	EnergyCost = 4, StarCost = 2,
	AbilityText = "Deal 2 damage to all enemy units.",
	Effect = { Kind = "DamageAllEnemies", Amount = 2 },
}

addCard {
	Id = "LUN-022", Name = "Moonlight Oracle", Faction = "Lunar", Type = "Unit", Rarity = "Epic",
	EnergyCost = 5, StarCost = 3, Power = 3, HP = 6,
	AbilityText = "When played, draw 2 cards.",
	OnPlay = { Kind = "Draw", Count = 2 },
}

addCard {
	Id = "LUN-023", Name = "Moontide Siren", Faction = "Lunar", Type = "Unit", Rarity = "Rare",
	EnergyCost = 3, StarCost = 1, Power = 2, HP = 4,
	AbilityText = "Whenever you heal (a spell, ability or Regen), deal 1 damage to the enemy Commander.",
	HealPing = 1,
}

---------------------------------------------------------------------
-- NEBULA: small units that Grow every turn
---------------------------------------------------------------------
addCard {
	Id = "NEB-001", Name = "Stardust Mote", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 2, Power = 1, HP = 3,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-002", Name = "Nursery Spark", Faction = "Nebula", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 1,
	AbilityText = "Give one of your units Grow 1.",
	Effect = { Kind = "GiveGrow", Amount = 1, Target = "FriendlyUnit" },
}

addCard {
	Id = "NEB-003", Name = "Gasbloom Sprout", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 3, Power = 2, HP = 4,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-004", Name = "Prism Moth", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 2, Power = 3, HP = 1,
}

addCard {
	Id = "NEB-005", Name = "Stellar Seedling", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 3, Power = 1, HP = 4,
	Keywords = { Grow = 2 },
}

addCard {
	Id = "NEB-006", Name = "Cloud Shepherd", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 2, HP = 3,
	AbilityText = "When played, your strongest other unit gets Grow 1.",
	OnPlay = { Kind = "GrowStrongestFriendly", Amount = 1, Other = true },
}

addCard {
	Id = "NEB-007", Name = "Spore Burst", Faction = "Nebula", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 3,
	AbilityText = "Deal 2 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 2, Target = "AnyUnit" },
}

addCard {
	Id = "NEB-008", Name = "Photon Gardener", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 1, Power = 2, HP = 5,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-009", Name = "Drift Grazer", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 1, Power = 2, HP = 4,
	AbilityText = "When played, draw a card.",
	OnPlay = { Kind = "Draw", Count = 1 },
}

addCard {
	Id = "NEB-010", Name = "Star Cradle", Faction = "Nebula", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 1,
	AbilityText = "Draw 2 cards.",
	Effect = { Kind = "Draw", Count = 2 },
}

addCard {
	Id = "NEB-011", Name = "Coral Golem", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 4, StarCost = 2, Power = 3, HP = 7,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-012", Name = "Nova Hatchling", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 4, StarCost = 2, Power = 4, HP = 6,
}

addCard {
	Id = "NEB-013", Name = "Gravity Bloom", Faction = "Nebula", Type = "Spell", Rarity = "Common",
	EnergyCost = 3, StarCost = 4,
	AbilityText = "Deal 3 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 3, Target = "AnyUnit" },
}

addCard {
	Id = "NEB-014", Name = "Aurora Stag", Faction = "Nebula", Type = "Unit", Rarity = "Rare",
	EnergyCost = 3, StarCost = 3, Power = 3, HP = 5,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-015", Name = "Starseed Druid", Faction = "Nebula", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 2, Power = 3, HP = 5,
	AbilityText = "When played, your other units get Grow 1.",
	OnPlay = { Kind = "GrowAllFriendly", Amount = 1, Other = true },
}

addCard {
	Id = "NEB-016", Name = "Bloom Surge", Faction = "Nebula", Type = "Spell", Rarity = "Rare",
	EnergyCost = 3, StarCost = 2,
	AbilityText = "All your units get +1 Power permanently.",
	Effect = { Kind = "BuffAllFriendly", Power = 1 },
}

addCard {
	Id = "NEB-017", Name = "Veil Ray", Faction = "Nebula", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3, Power = 4, HP = 5,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-018", Name = "Pulse of Creation", Faction = "Nebula", Type = "Spell", Rarity = "Rare",
	EnergyCost = 3, StarCost = 2,
	AbilityText = "Draw 2 cards. Your strongest unit gets Grow 1.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "Draw", Count = 2 },
		{ Kind = "GrowStrongestFriendly", Amount = 1, Bonus = true },
	} },
}

addCard {
	Id = "NEB-019", Name = "Pillar Titan", Faction = "Nebula", Type = "Unit", Rarity = "Epic",
	EnergyCost = 5, StarCost = 5, Power = 5, HP = 7,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-020", Name = "Genesis Bloom", Faction = "Nebula", Type = "Spell", Rarity = "Epic",
	EnergyCost = 3, StarCost = 2,
	AbilityText = "All your units get Grow 1. Your lowest-Power unit gets a Shield.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "GrowAllFriendly", Amount = 1 },
		{ Kind = "ShieldWeakestFriendly", Bonus = true },
	} },
}

addCard {
	Id = "NEB-021", Name = "Cradle Warden", Faction = "Nebula", Type = "Unit", Rarity = "Epic",
	EnergyCost = 5, StarCost = 3, Power = 4, HP = 6,
	Keywords = { Grow = 1 },
	AbilityText = "When played, your other units get Grow 1.",
	OnPlay = { Kind = "GrowAllFriendly", Amount = 1, Other = true },
}

addCard {
	Id = "NEB-022", Name = "The First Light", Faction = "Nebula", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 7, StarCost = 4, Power = 7, HP = 9,
	Keywords = { Grow = 2 },
	AbilityText = "When played, draw 2 cards.",
	OnPlay = { Kind = "Draw", Count = 2 },
}

-- Protects a growing unit long enough for it to pay off
addCard {
	Id = "NEB-023", Name = "Petal Ward", Faction = "Nebula", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 2,
	AbilityText = "Give one of your units a Shield and Grow 1.",
	Effect = { Kind = "Multi", Target = "FriendlyUnit", Effects = {
		{ Kind = "GiveShield", Target = "FriendlyUnit" },
		{ Kind = "GiveGrow", Amount = 1, Target = "FriendlyUnit", Bonus = true },
	} },
}

---------------------------------------------------------------------
-- VOID: Decay wears enemies down; some cards cost your Commander's HP
---------------------------------------------------------------------
addCard {
	Id = "VOI-001", Name = "Shade Wisp", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 1, Power = 1, HP = 3,
	Keywords = { Decay = 1 },
}

addCard {
	Id = "VOI-002", Name = "Hollow Pact", Faction = "Void", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, HPCost = 2, StarCost = 1,
	AbilityText = "Draw 2 cards.",
	Effect = { Kind = "Draw", Count = 2 },
}

addCard {
	Id = "VOI-003", Name = "Gravity Mite", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 2, HP = 3,
	Keywords = { Decay = 1 },
}

addCard {
	Id = "VOI-004", Name = "Entropy Bolt", Faction = "Void", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, HPCost = 2, StarCost = 3,
	AbilityText = "Deal 3 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 3, Target = "AnyUnit" },
}

addCard {
	Id = "VOI-005", Name = "Duskforged Sentry", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 2, Power = 2, HP = 5,
	Keywords = { Intercept = true },
}

addCard {
	Id = "VOI-006", Name = "Null Acolyte", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 1, Power = 3, HP = 3,
	AbilityText = "When played, the strongest enemy unit gets -1 Power permanently (not below 1).",
	OnPlay = { Kind = "WeakenStrongestEnemy", Amount = 1 },
}

addCard {
	Id = "VOI-007", Name = "Wither", Faction = "Void", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 3,
	AbilityText = "An enemy unit gets -2 Power permanently (not below 1).",
	Effect = { Kind = "Weaken", Amount = 2, Target = "EnemyUnit" },
}

addCard {
	Id = "VOI-008", Name = "Event Skimmer", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 3, Power = 3, HP = 4,
	Keywords = { Decay = 1 },
}

addCard {
	Id = "VOI-009", Name = "Rift Stalker", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 2, Power = 3, HP = 3,
}

addCard {
	Id = "VOI-010", Name = "Obsidian Hulk", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, HPCost = 2, StarCost = 3, Power = 5, HP = 4,
}

addCard {
	Id = "VOI-011", Name = "Dark Matter Shroud", Faction = "Void", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 3,
	AbilityText = "Destroy a unit with 2 or less Power.",
	Effect = { Kind = "Destroy", Target = "AnyUnit", MaxPower = 2 },
}

addCard {
	Id = "VOI-012", Name = "Horizon Warden", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 4, StarCost = 2, Power = 3, HP = 6,
	Keywords = { Decay = 1 },
}

addCard {
	Id = "VOI-013", Name = "Siphon", Faction = "Void", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 3,
	AbilityText = "Deal 2 damage to a unit. Heal your Commander 2.",
	Effect = { Kind = "Multi", Target = "AnyUnit", Effects = {
		{ Kind = "DamageUnit", Amount = 2, Target = "AnyUnit" },
		{ Kind = "HealCommander", Amount = 2, Bonus = true },
	} },
}

addCard {
	Id = "VOI-014", Name = "Accretion Knight", Faction = "Void", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3, Power = 4, HP = 6,
	Keywords = { Decay = 1 },
}

addCard {
	Id = "VOI-015", Name = "Collapse", Faction = "Void", Type = "Spell", Rarity = "Rare",
	EnergyCost = 3, HPCost = 3, StarCost = 4,
	AbilityText = "Destroy a unit.",
	Effect = { Kind = "Destroy", Target = "AnyUnit" },
}

addCard {
	Id = "VOI-016", Name = "Umbral Lantern-Bearer", Faction = "Void", Type = "Unit", Rarity = "Rare",
	EnergyCost = 3, StarCost = 2, Power = 2, HP = 4,
	AbilityText = "When played, all enemy units get -1 Power permanently (not below 1).",
	OnPlay = { Kind = "WeakenAllEnemies", Amount = 1 },
}

addCard {
	Id = "VOI-017", Name = "Graviton Lancer", Faction = "Void", Type = "Unit", Rarity = "Rare",
	EnergyCost = 5, StarCost = 2, Power = 5, HP = 4,
	Keywords = { Decay = 2 },
}

addCard {
	Id = "VOI-018", Name = "Black Tide", Faction = "Void", Type = "Spell", Rarity = "Rare",
	EnergyCost = 3, StarCost = 2,
	AbilityText = "Deal 2 damage to all units, yours included.",
	Effect = { Kind = "DamageAllUnits", Amount = 2 },
}

addCard {
	Id = "VOI-023", Name = "Gravity Anchor", Faction = "Void", Type = "Unit", Rarity = "Rare",
	EnergyCost = 3, StarCost = 2, Power = 2, HP = 4,
	Keywords = { Intercept = true },
	AbilityText = "When played, heal your Commander 2.",
	OnPlay = { Kind = "HealCommander", Amount = 2 },
}

addCard {
	Id = "VOI-019", Name = "Singularity Behemoth", Faction = "Void", Type = "Unit", Rarity = "Epic",
	EnergyCost = 7, StarCost = 3, Power = 6, HP = 8,
	Keywords = { Decay = 2 },
}

addCard {
	Id = "VOI-020", Name = "Malakar's Bargain", Faction = "Void", Type = "Spell", Rarity = "Epic",
	EnergyCost = 2, HPCost = 3, StarCost = 2,
	AbilityText = "Draw 3 cards.",
	Effect = { Kind = "Draw", Count = 3 },
}

addCard {
	Id = "VOI-021", Name = "Hollow Archon", Faction = "Void", Type = "Unit", Rarity = "Epic",
	EnergyCost = 5, StarCost = 4, Power = 4, HP = 5,
	AbilityText = "When played, destroy the strongest enemy unit with 2 or less Power.",
	OnPlay = { Kind = "DestroyStrongestEnemy", MaxPower = 2 },
}

addCard {
	Id = "VOI-022", Name = "Night Sovereign", Faction = "Void", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 7, StarCost = 4, Power = 7, HP = 9,
	Keywords = { Decay = 3 },
	AbilityText = "When played, all enemy units get -2 Power.",
	OnPlay = { Kind = "WeakenAllEnemies", Amount = 2 },
}

---------------------------------------------------------------------
-- COMET: fragile units with Streak that fly past blockers
---------------------------------------------------------------------
addCard {
	Id = "COM-001", Name = "Frost Skipper", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 2, Power = 1, HP = 2,
	Keywords = { Streak = true },
}

addCard {
	Id = "COM-002", Name = "Slipstream", Faction = "Comet", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 1,
	AbilityText = "One of your units gets Streak this turn.",
	Effect = { Kind = "GiveStreak", Target = "FriendlyUnit" },
}

addCard {
	Id = "COM-003", Name = "Ice Courier", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 3, Power = 3, HP = 2,
	Keywords = { Rush = true },
}

addCard {
	Id = "COM-004", Name = "Tailwind Glider", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 1, HP = 4,
	Keywords = { Streak = true },
}

addCard {
	Id = "COM-005", Name = "Rime Hound", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 3, Power = 3, HP = 3,
}

addCard {
	Id = "COM-006", Name = "Recall Beacon", Faction = "Comet", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 1,
	AbilityText = "Return one of your units to your hand. Draw a card.",
	Effect = { Kind = "Multi", Target = "FriendlyUnit", Effects = {
		{ Kind = "ReturnToHand", Target = "FriendlyUnit" },
		{ Kind = "Draw", Count = 1, Bonus = true },
	} },
}

addCard {
	Id = "COM-007", Name = "Ice Shard", Faction = "Comet", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 2,
	AbilityText = "Deal 2 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 2, Target = "AnyUnit" },
}

addCard {
	Id = "COM-008", Name = "Shard Racer", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 2, Power = 1, HP = 3,
	Keywords = { Streak = true, Rush = true },
}

addCard {
	Id = "COM-009", Name = "Glacier Ward", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 3, Power = 2, HP = 5,
}

addCard {
	Id = "COM-010", Name = "Frostbite Archer", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 3, Power = 3, HP = 4,
	AbilityText = "When played, deal 1 damage to the strongest enemy unit.",
	OnPlay = { Kind = "DamageStrongestEnemy", Amount = 1 },
}

addCard {
	Id = "COM-011", Name = "Deflect", Faction = "Comet", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 3,
	AbilityText = "Return an enemy unit with 3 or less Power to its owner's hand.",
	Effect = { Kind = "ReturnToHand", Target = "EnemyUnit", MaxPower = 3 },
}

addCard {
	Id = "COM-012", Name = "Kuiper Drifter", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 2, HP = 4,
	Keywords = { Streak = true },
}

addCard {
	Id = "COM-013", Name = "Hailstorm", Faction = "Comet", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 1,
	AbilityText = "Deal 1 damage to all enemy units.",
	Effect = { Kind = "DamageAllEnemies", Amount = 1 },
}

addCard {
	Id = "COM-014", Name = "Aurora Cavalier", Faction = "Comet", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 5, Power = 5, HP = 3,
	Keywords = { Rush = true },
}

addCard {
	Id = "COM-015", Name = "Starlance Interceptor", Faction = "Comet", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3, Power = 4, HP = 6,
	Keywords = { Streak = true },
}

addCard {
	Id = "COM-016", Name = "Perihelion Dash", Faction = "Comet", Type = "Spell", Rarity = "Rare",
	EnergyCost = 2, StarCost = 2,
	AbilityText = "Your units get Streak this turn. Draw a card.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "StreakAllFriendly", Bonus = true },
		{ Kind = "Draw", Count = 1 },
	} },
}

addCard {
	Id = "COM-017", Name = "Iceborn Sentinel", Faction = "Comet", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3, Power = 3, HP = 6,
	AbilityText = "When played, return the strongest enemy unit with 2 or less Power to its owner's hand.",
	OnPlay = { Kind = "ReturnStrongestEnemy", MaxPower = 2 },
}

addCard {
	Id = "COM-018", Name = "Comet Fall", Faction = "Comet", Type = "Spell", Rarity = "Rare",
	EnergyCost = 4, StarCost = 2,
	AbilityText = "Deal 4 damage to an enemy unit and 1 to every other enemy unit.",
	Effect = { Kind = "Multi", Target = "EnemyUnit", Effects = {
		{ Kind = "DamageUnit", Amount = 4, Target = "EnemyUnit" },
		{ Kind = "DamageOtherEnemies", Amount = 1 },
	} },
}

addCard {
	Id = "COM-019", Name = "Vanguard of the Long Orbit", Faction = "Comet", Type = "Unit", Rarity = "Epic",
	EnergyCost = 6, StarCost = 3, Power = 4, HP = 6,
	Keywords = { Rush = true, Streak = true },
}

addCard {
	Id = "COM-020", Name = "Frostwake Tide", Faction = "Comet", Type = "Spell", Rarity = "Epic",
	EnergyCost = 4, StarCost = 3,
	AbilityText = "Return all enemy units with 3 or less Power to their owners' hands.",
	Effect = { Kind = "ReturnAllEnemies", MaxPower = 3 },
}

addCard {
	Id = "COM-021", Name = "Tailwind Herald", Faction = "Comet", Type = "Unit", Rarity = "Epic",
	EnergyCost = 5, StarCost = 3, Power = 4, HP = 5,
	AbilityText = "When played, your other units get Streak this turn.",
	OnPlay = { Kind = "StreakAllFriendly", Other = true },
}

addCard {
	Id = "COM-022", Name = "The Great Comet", Faction = "Comet", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 7, StarCost = 5, Power = 7, HP = 7,
	Keywords = { Rush = true, Streak = true },
}

---------------------------------------------------------------------
-- ANOMALIES: set face-down, they trigger on the opponent's turn (all cost Rules.AnomalyCost)
---------------------------------------------------------------------
addCard {
	Id = "SOL-023", Name = "Sunflare Ambush", Faction = "Solar", Type = "Anomaly", Rarity = "Common",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 1,
	Trigger = "EnemyUnitPlayed",
	AbilityText = "When an enemy unit is played, deal 2 damage to it.",
	Effect = { Kind = "DamageTrigger", Amount = 2 },
}

addCard {
	Id = "SOL-024", Name = "Backdraft", Faction = "Solar", Type = "Anomaly", Rarity = "Common",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 2,
	Trigger = "EnemyAttacks",
	AbilityText = "When an enemy unit attacks, deal 3 damage to it before combat.",
	Effect = { Kind = "DamageTrigger", Amount = 3 },
}

addCard {
	Id = "SOL-025", Name = "Supernova Snare", Faction = "Solar", Type = "Anomaly", Rarity = "Rare",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 3,
	Trigger = "EnemyCelestial",
	AbilityText = "When the enemy summons their Celestial, deal 4 damage to it and 2 damage to their Commander.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "DamageTrigger", Amount = 4 },
		{ Kind = "DamageEnemyCommander", Amount = 2 },
	} },
}

addCard {
	Id = "LUN-024", Name = "Silver Veil", Faction = "Lunar", Type = "Anomaly", Rarity = "Common",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 2,
	Trigger = "EnemySpell",
	AbilityText = "When the enemy casts a spell, give all your units a Shield first.",
	Effect = { Kind = "ShieldAllFriendly" },
}

addCard {
	Id = "LUN-025", Name = "Tidal Reflection", Faction = "Lunar", Type = "Anomaly", Rarity = "Common",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 2,
	Trigger = "FriendlyUnitDestroyed",
	AbilityText = "When one of your units is destroyed, return it to your hand.",
	Effect = { Kind = "ReturnDestroyed" },
}

addCard {
	Id = "LUN-026", Name = "Moonlit Mirage", Faction = "Lunar", Type = "Anomaly", Rarity = "Rare",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 3,
	Trigger = "CommanderAttacked",
	AbilityText = "When an enemy unit would damage your Commander, prevent it and heal your Commander 2.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "PreventDamage" },
		{ Kind = "HealCommander", Amount = 2 },
	} },
}

addCard {
	Id = "NEB-024", Name = "Spore Snare", Faction = "Nebula", Type = "Anomaly", Rarity = "Common",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 1,
	Trigger = "EnemyUnitPlayed",
	AbilityText = "When an enemy unit is played, it gets -1 Power permanently and your weakest unit gets Grow 1.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "WeakenTrigger", Amount = 1 },
		{ Kind = "GrowWeakestFriendly", Amount = 1 },
	} },
}

addCard {
	Id = "NEB-025", Name = "Seedfall", Faction = "Nebula", Type = "Anomaly", Rarity = "Common",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 2,
	Trigger = "FriendlyUnitDestroyed",
	AbilityText = "When one of your units is destroyed, your other units get Grow 1.",
	Effect = { Kind = "GrowAllFriendly", Amount = 1 },
}

addCard {
	Id = "NEB-026", Name = "Bloom Burst", Faction = "Nebula", Type = "Anomaly", Rarity = "Rare",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 3,
	Trigger = "LowHP",
	AbilityText = "When your Commander drops below 10 HP, all your units get +1 Power and your Commander heals 3.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "BuffAllFriendly", Power = 1 },
		{ Kind = "HealCommander", Amount = 3 },
	} },
}

addCard {
	Id = "VOI-024", Name = "Gravity Well", Faction = "Void", Type = "Anomaly", Rarity = "Common",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 2,
	Trigger = "EnemyAttacks",
	AbilityText = "When an enemy unit attacks, it gets -2 Power permanently first.",
	Effect = { Kind = "WeakenTrigger", Amount = 2 },
}

addCard {
	Id = "VOI-025", Name = "Null Echo", Faction = "Void", Type = "Anomaly", Rarity = "Common",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 2,
	Trigger = "EnemyAbility",
	AbilityText = "When the enemy uses their Commander's ability, their Commander takes 3 damage and you draw a card.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "DamageEnemyCommander", Amount = 3 },
		{ Kind = "Draw", Count = 1 },
	} },
}

addCard {
	Id = "VOI-026", Name = "Event Horizon", Faction = "Void", Type = "Anomaly", Rarity = "Epic",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 4,
	Trigger = "EnemySpell",
	AbilityText = "When the enemy casts a spell, cancel it. Its energy stays spent.",
	Effect = { Kind = "CancelSpell" },
}

addCard {
	Id = "COM-023", Name = "Cold Snap", Faction = "Comet", Type = "Anomaly", Rarity = "Common",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 2,
	Trigger = "EnemyUnitPlayed",
	AbilityText = "When an enemy unit is played, freeze it: it skips its next attack.",
	Effect = { Kind = "FreezeTrigger" },
}

addCard {
	Id = "COM-024", Name = "Tripwire", Faction = "Comet", Type = "Anomaly", Rarity = "Rare",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 3,
	Trigger = "CommanderAttacked",
	AbilityText = "When an enemy unit would damage your Commander, return it to its owner's hand first.",
	Effect = { Kind = "ReturnTrigger" },
}

addCard {
	Id = "COM-025", Name = "Slingshot Orbit", Faction = "Comet", Type = "Anomaly", Rarity = "Rare",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 3,
	Trigger = "EnemyCelestial",
	AbilityText = "When the enemy summons their Celestial, freeze it (it skips its next attack) and it gets -2 Power permanently.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "FreezeTrigger" },
		{ Kind = "WeakenTrigger", Amount = 2 },
	} },
}

addCard {
	Id = "NEU-002", Name = "Static Mirage", Faction = "Neutral", Type = "Anomaly", Rarity = "Common",
	EnergyCost = CardDatabase.Rules.AnomalyCost, StarCost = 2,
	Trigger = "EnemyTurnEnd",
	AbilityText = "When the enemy ends their turn, draw 2 cards.",
	Effect = { Kind = "Draw", Count = 2 },
}

---------------------------------------------------------------------
-- NEUTRAL
---------------------------------------------------------------------
addCard {
	Id = "NEU-001", Name = "Star Map", Faction = "Neutral", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 1,
	AbilityText = "Draw a card.",
	Effect = { Kind = "Draw", Count = 1 },
}

---------------------------------------------------------------------
-- LEGENDARIES (set 2): two more per faction, at mid costs, so a faction's
-- Legendary pull isn't always the same 8-drop
---------------------------------------------------------------------
addCard {
	Id = "SOL-026", Name = "Dawnbreaker Phoenix", Faction = "Solar", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 5, StarCost = 4, Power = 6, HP = 5,
	Keywords = { Rush = true, Ignite = 2 },
}

addCard {
	Id = "SOL-027", Name = "Daybreak", Faction = "Solar", Type = "Spell", Rarity = "Legendary",
	EnergyCost = 3, StarCost = 4,
	AbilityText = "Deal 3 damage to all enemy units. Your units get +1 Power.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "DamageAllEnemies", Amount = 3 },
		{ Kind = "BuffAllFriendly", Power = 1, Bonus = true },
	} },
}

addCard {
	Id = "LUN-027", Name = "High Tide Oracle", Faction = "Lunar", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 5, StarCost = 4, Power = 5, HP = 7,
	Keywords = { Regen = 2 },
	AbilityText = "When played, heal all your units and your Commander 3.",
	OnPlay = { Kind = "HealAllFriendly", Amount = 3, IncludeCommander = true },
}

addCard {
	Id = "LUN-028", Name = "Full Moon Rite", Faction = "Lunar", Type = "Spell", Rarity = "Legendary",
	EnergyCost = 4, StarCost = 4,
	AbilityText = "Give all your units a Shield. Heal your Commander 5.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "ShieldAllFriendly" },
		{ Kind = "HealCommander", Amount = 5, Bonus = true },
	} },
}

addCard {
	Id = "NEB-027", Name = "Nursery Matriarch", Faction = "Nebula", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 3, StarCost = 4, Power = 4, HP = 5,
	Keywords = { Grow = 1 },
	AbilityText = "When played, your other units Grow 1. Draw a card.",
	OnPlay = { Kind = "Multi", Effects = {
		{ Kind = "GrowAllFriendly", Amount = 1, Other = true, Bonus = true },
		{ Kind = "Draw", Count = 1 },
	} },
}

addCard {
	Id = "NEB-028", Name = "Cosmic Bloom", Faction = "Nebula", Type = "Spell", Rarity = "Legendary",
	EnergyCost = 3, StarCost = 4,
	AbilityText = "Your units get +2 Power and Grow 1. Draw 2 cards.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "BuffAllFriendly", Power = 2, Bonus = true },
		{ Kind = "GrowAllFriendly", Amount = 1, Bonus = true },
		{ Kind = "Draw", Count = 2 },
	} },
}

addCard {
	Id = "VOI-027", Name = "Eclipse Wraith", Faction = "Void", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 5, HPCost = 2, StarCost = 4, Power = 6, HP = 6,
	Keywords = { Decay = 2 },
	AbilityText = "When played, all enemy units get -2 Power.",
	OnPlay = { Kind = "WeakenAllEnemies", Amount = 2 },
}

addCard {
	Id = "VOI-028", Name = "Devour", Faction = "Void", Type = "Spell", Rarity = "Legendary",
	EnergyCost = 6, StarCost = 4,
	AbilityText = "Destroy an enemy unit with 5 or less Power. Heal your Commander 3.",
	Effect = { Kind = "Multi", Target = "EnemyUnit", Effects = {
		{ Kind = "Destroy", Target = "EnemyUnit", MaxPower = 5 },
		{ Kind = "HealCommander", Amount = 3, Bonus = true },
	} },
}

addCard {
	Id = "COM-026", Name = "Starwake Rider", Faction = "Comet", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 4, StarCost = 5, Power = 4, HP = 4,
	Keywords = { Streak = true },
	AbilityText = "When played, return the strongest enemy unit with 4 or less Power to its owner's hand.",
	OnPlay = { Kind = "ReturnStrongestEnemy", MaxPower = 4 },
}

addCard {
	Id = "COM-027", Name = "Meteor Shower", Faction = "Comet", Type = "Spell", Rarity = "Legendary",
	EnergyCost = 3, StarCost = 4,
	AbilityText = "Deal 3 damage to all enemy units. Draw a card.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "DamageAllEnemies", Amount = 3 },
		{ Kind = "Draw", Count = 1, Bonus = true },
	} },
}

---------------------------------------------------------------------
-- STARTER DECKS  (card Id -> number of copies)
---------------------------------------------------------------------
-- Starters use at most 2 copies of a card (many are 1-ofs), so pulling
-- the same commons from packs still builds toward a full set of 3.
CardDatabase.StarterDecks = {
	Solar = {
		Description = "Fast and aggressive: Rush, Ignite and burn spells.",
		Commander = "CMD-SOL-01",
		Celestial = "CEL-04",
		Cards = {
			-- 2 copies
			["SOL-001"] = 2, -- Ember Scout
			["SOL-002"] = 2, -- Kindle
			["SOL-014"] = 2, -- Spark Sprite
			["SOL-003"] = 2, -- Sunforge Cadet
			["SOL-004"] = 2, -- Flarecat
			["SOL-005"] = 2, -- Solar Flare
			["SOL-016"] = 2, -- Forge Hound
			["SOL-006"] = 2, -- Cinder Guard
			["SOL-007"] = 2, -- Solar Lancer
			["NEU-001"] = 1, -- Star Map
			["SOL-015"] = 2, -- Sunburst
			["SOL-017"] = 1, -- Ember Drummer
			["SOL-021"] = 2, -- Nova Burst
			-- 1 copy
			["SOL-019"] = 1, -- Sunstrike
			["SOL-008"] = 1, -- Blazewing Hawk
			["SOL-010"] = 1, -- Corona Knight
			["SOL-009"] = 1, -- Heat Wave
			["SOL-018"] = 1, -- Magma Brute
			["SOL-020"] = 1, -- Solar Phoenix
		},
	},
	Lunar = {
		Description = "Tough and patient: Shields, healing and Regen.",
		Commander = "CMD-LUN-01",
		Celestial = "CEL-05",
		Cards = {
			-- 2 copies
			["LUN-001"] = 2, -- Moonlit Wisp
			["LUN-014"] = 2, -- Pearl Crab
			["LUN-003"] = 2, -- Silver Barrier
			["LUN-004"] = 2, -- Crescent Archer
			["LUN-005"] = 2, -- Tide Sentinel
			["LUN-016"] = 2, -- Reef Guardian
			["LUN-019"] = 2, -- Undertow
			["LUN-006"] = 2, -- Moonbeam
			["LUN-007"] = 2, -- Harbor Warden
			["LUN-018"] = 2, -- Tide Caller
			["LUN-023"] = 2, -- Moontide Siren
			-- 1 copy
			["NEU-001"] = 1, -- Star Map
			["LUN-002"] = 1, -- Tidal Blessing
			["LUN-015"] = 1, -- Stargazer's Chart
			["LUN-017"] = 1, -- Silver Mender
			["LUN-009"] = 1, -- Eclipse Veil
			["LUN-010"] = 1, -- Silver Knight
			["LUN-020"] = 1, -- Crescent Warden
			["LUN-022"] = 1, -- Moonlight Oracle
		},
	},
	Nebula = {
		Description = "Patient and growing: Grow, permanent buffs and card draw.",
		Commander = "CMD-NEB-01",
		Celestial = "CEL-12",
		Cards = {
			-- 2 copies
			["NEB-001"] = 2, -- Stardust Mote
			["NEB-011"] = 2, -- Coral Golem
			["NEB-003"] = 2, -- Gasbloom Sprout
			["NEB-004"] = 2, -- Prism Moth
			["NEB-005"] = 2, -- Stellar Seedling
			["NEB-006"] = 2, -- Cloud Shepherd
			["NEB-007"] = 2, -- Spore Burst
			["NEB-013"] = 2, -- Gravity Bloom
			["NEB-008"] = 2, -- Photon Gardener
			["NEU-001"] = 2, -- Star Map
			["NEB-009"] = 2, -- Drift Grazer
			["NEB-010"] = 2, -- Star Cradle
			-- 1 copy
			["NEB-023"] = 1, -- Petal Ward
			["NEB-002"] = 1, -- Nursery Spark
			["NEB-014"] = 1, -- Aurora Stag
			["NEB-017"] = 1, -- Veil Ray
			["NEB-019"] = 1, -- Pillar Titan
			["NEB-021"] = 1, -- Cradle Warden
		},
	},
	Void = {
		Description = "Grinding and ruthless: Decay, removal and cards that cost HP.",
		Commander = "CMD-VOI-02",
		Celestial = "CEL-11",
		Cards = {
			-- 2 copies
			["VOI-001"] = 2, -- Shade Wisp
			["VOI-003"] = 2, -- Gravity Mite
			["VOI-004"] = 2, -- Entropy Bolt
			["VOI-005"] = 2, -- Duskforged Sentry
			["VOI-006"] = 2, -- Null Acolyte
			["VOI-007"] = 2, -- Wither
			["VOI-008"] = 2, -- Event Skimmer
			["VOI-009"] = 2, -- Rift Stalker
			["VOI-013"] = 2, -- Siphon
			["NEU-001"] = 2, -- Star Map
			-- 1 copy
			["VOI-002"] = 1, -- Hollow Pact
			["VOI-010"] = 1, -- Obsidian Hulk
			["VOI-011"] = 1, -- Dark Matter Shroud
			["VOI-012"] = 2, -- Horizon Warden
			["VOI-014"] = 1, -- Accretion Knight
			["VOI-015"] = 1, -- Collapse
			["VOI-016"] = 1, -- Umbral Lantern-Bearer
			["VOI-017"] = 1, -- Graviton Lancer
			["VOI-019"] = 1, -- Singularity Behemoth
		},
	},
	Comet = {
		Description = "Fast and slippery: Streak past blockers and bounce units back to hand.",
		Commander = "CMD-COM-01",
		Celestial = "CEL-13",
		Cards = {
			-- 2 copies
			["COM-009"] = 2, -- Glacier Ward
			["COM-002"] = 2, -- Slipstream
			["COM-003"] = 2, -- Ice Courier
			["COM-004"] = 3, -- Tailwind Glider
			["COM-005"] = 2, -- Rime Hound
			["COM-007"] = 2, -- Ice Shard
			["COM-008"] = 2, -- Shard Racer
			["COM-010"] = 2, -- Frostbite Archer
			["COM-011"] = 2, -- Deflect
			["NEU-001"] = 2, -- Star Map
			["COM-001"] = 2, -- Frost Skipper
			["COM-013"] = 3, -- Hailstorm
			-- 1 copy
			["COM-012"] = 1, -- Kuiper Drifter
			["COM-014"] = 1, -- Aurora Cavalier
			["COM-017"] = 1, -- Iceborn Sentinel
			["COM-019"] = 1, -- Vanguard of the Long Orbit
		},
	},
}

-- Display order for deck pickers
CardDatabase.StarterDeckOrder = { "Solar", "Lunar", "Nebula", "Void", "Comet" }

---------------------------------------------------------------------
-- LOOKUP HELPERS
---------------------------------------------------------------------
function CardDatabase.GetCard(id)
	return Cards[id]
end

function CardDatabase.GetAllCards()
	local list = {}
	for _, id in ipairs(CardOrder) do
		table.insert(list, Cards[id])
	end
	return list
end

function CardDatabase.GetCardsByFaction(faction)
	local list = {}
	for _, id in ipairs(CardOrder) do
		if Cards[id].Faction == faction then
			table.insert(list, Cards[id])
		end
	end
	return list
end

-- Turns { ["SOL-001"] = 3 } into { "SOL-001", "SOL-001", "SOL-001" }
function CardDatabase.ExpandCounts(counts)
	local list = {}
	-- sort ids so the result is the same every time
	local ids = {}
	for id in pairs(counts) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		for _ = 1, counts[id] do
			table.insert(list, id)
		end
	end
	return list
end

---------------------------------------------------------------------
-- DECK VALIDATION
-- Returns: isValid (bool), errors (list of strings), totalStars (number)
---------------------------------------------------------------------
--[[ Deck formats: every saved deck is built for one of these.
	Zenith: the competitive format. The deck (main deck + Celestial) must fit the Star Cap.
	Open:   anything goes, any number of stars.
	Every other rule (30 cards, 3 copies, faction, pairing) is the same in both. ]]
CardDatabase.DeckFormats = {
	Zenith = {
		Name = "Zenith",
		StarCap = CardDatabase.Rules.StarCap,
		Description = ("Competitive: the deck must fit %d stars."):format(CardDatabase.Rules.StarCap),
	},
	Open = {
		Name = "Open",
		StarCap = nil,
		Description = "Anything goes: no star limit.",
	},
}
CardDatabase.DeckFormatOrder = { "Zenith", "Open" }
CardDatabase.DefaultDeckFormat = "Zenith"

-- A format name you can trust (unknown or missing = the default, Zenith)
function CardDatabase.FormatOf(name)
	if type(name) == "string" and CardDatabase.DeckFormats[name] then
		return name
	end
	return CardDatabase.DefaultDeckFormat
end

-- format is optional ("Zenith" when left out)
function CardDatabase.ValidateDeck(commanderId, celestialId, cardIds, format)
	local rules = CardDatabase.Rules
	local starCap = CardDatabase.DeckFormats[CardDatabase.FormatOf(format)].StarCap
	local errors = {}
	local totalStars = 0

	local commander = Cards[commanderId]
	if not commander or commander.Type ~= "Commander" then
		table.insert(errors, "Pick a valid Commander.")
		return false, errors, 0
	end

	local celestial = Cards[celestialId]
	if not celestial or celestial.Type ~= "Celestial" then
		table.insert(errors, "Pick a valid Celestial.")
	elseif not listContains(celestial.PairsWith, commander.Faction) then
		table.insert(errors, celestial.Name .. " can't pair with a " .. commander.Faction .. " Commander.")
	else
		totalStars = totalStars + celestial.StarCost
	end

	if #cardIds ~= rules.DeckSize then
		table.insert(errors, ("Deck has %d cards; it needs exactly %d."):format(#cardIds, rules.DeckSize))
	end

	local copies = {}
	for _, id in ipairs(cardIds) do
		local card = Cards[id]
		if not card then
			table.insert(errors, "Unknown card: " .. tostring(id))
		elseif card.Type == "Anomaly" and not CardDatabase.IsMainDeckType(card.Type) then
			table.insert(errors, card.Name .. ": Anomalies are switched off right now. Take it out of the deck.")
		elseif not CardDatabase.IsMainDeckType(card.Type) then
			table.insert(errors, card.Name .. " can't go in the main deck.")
		else
			copies[id] = (copies[id] or 0) + 1
			totalStars = totalStars + card.StarCost

			if card.Faction ~= commander.Faction and card.Faction ~= "Neutral" then
				if copies[id] == 1 then
					table.insert(errors, card.Name .. " is " .. card.Faction .. ", not " .. commander.Faction .. ".")
				end
			end
			if card.CommanderOnly and card.CommanderOnly ~= commanderId and copies[id] == 1 then
				table.insert(errors, card.Name .. " can only be used by " .. Cards[card.CommanderOnly].Name .. ".")
			end
			local maxCopies = CardDatabase.MaxCopiesFor(card)
			if copies[id] == maxCopies + 1 then
				table.insert(errors, maxCopies == 1 and (card.Name .. " is Legendary: only 1 copy per deck.")
					or ("Too many copies of %s (max %d)."):format(card.Name, maxCopies))
			end
		end
	end

	if starCap and totalStars > starCap then
		table.insert(errors, ("Deck uses %d stars; Zenith's cap is %d. (Open decks have no cap.)"):format(totalStars, starCap))
	end

	return #errors == 0, errors, totalStars
end

return CardDatabase