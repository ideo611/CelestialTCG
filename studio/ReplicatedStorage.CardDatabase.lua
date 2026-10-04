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
	         GiveShield {Target}, ShieldAllFriendly {}
	  Target: "AnyUnit" or "FriendlyUnit"

	Keywords: Rush, Shield, Ignite = X, Regen = X (heals X at the end of your turn)
]]

local CardDatabase = {}

---------------------------------------------------------------------
-- BALANCE VERSION: change this whenever you change cards or rules, so the
-- match log can compare games before and after the change. (The log also
-- fingerprints every card automatically, as a backup.)
---------------------------------------------------------------------
CardDatabase.BalanceVersion = "2026-10-01"

---------------------------------------------------------------------
-- GAME RULES (draft values from the design doc)
---------------------------------------------------------------------
CardDatabase.Rules = {
	DeckSize = 30,
	MaxCopies = 3,
	StarCap = 65,          -- draft; finalize after more cards exist
	CommanderHP = 20,
	StartingEnergy = 1,
	MaxEnergy = 10,
	StartingHand = 4,
	Lanes = 3,
	CelestialTax = 2,      -- extra energy each time a Celestial is re-summoned

	-- Catch-up help for whoever goes second (going first is a big advantage)
	SecondPlayerBonusCards = 1, -- extra card in the opening hand
	SecondPlayerBonusHP = 3,    -- extra Commander HP
	SecondPlayerSpark = true,   -- a one-time +1 energy boost they can use on any turn

	-- Cosmic Storm: from this round on, each Commander takes damage at the start of
	-- their turn (1, then 2, then 3...). Keeps defensive matches from dragging on.
	StormStartRound = 9,
	-- Overflow (extra combat damage carries to the Commander). Tested; off for now.
	Overflow = false,
}

CardDatabase.Factions = { "Solar", "Lunar", "Nebula", "Void", "Comet", "Neutral" }
CardDatabase.Rarities = { "Common", "Rare", "Epic", "Legendary" }
CardDatabase.Types = { "Unit", "Spell", "Commander", "Celestial" }

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
}

local function checkEffect(id, effect)
	assert(EFFECT_KINDS[effect.Kind], id .. ": unknown effect kind " .. tostring(effect.Kind))
	if effect.Target then
		assert(effect.Target == "AnyUnit" or effect.Target == "FriendlyUnit", id .. ": bad effect Target")
	end
end

local function addCard(card)
	assert(type(card.Id) == "string", "Card is missing an Id")
	assert(Cards[card.Id] == nil, "Duplicate card Id: " .. card.Id)
	assert(listContains(CardDatabase.Factions, card.Faction), card.Id .. ": bad Faction")
	assert(listContains(CardDatabase.Types, card.Type), card.Id .. ": bad Type")
	assert(listContains(CardDatabase.Rarities, card.Rarity), card.Id .. ": bad Rarity")

	card.Keywords = card.Keywords or {}
	card.ArtId = card.ArtId or PLACEHOLDER_ART
	card.AbilityText = card.AbilityText or ""

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
	if card.Type == "Commander" then
		assert(type(card.CommanderAbility) == "table" and type(card.CommanderAbility.Effect) == "table",
			card.Id .. ": Commanders need a CommanderAbility with an Effect")
		checkEffect(card.Id, card.CommanderAbility.Effect)
	end
	if card.Effect then
		checkEffect(card.Id, card.Effect)
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
		EnergyCost = 2,
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
		EnergyCost = 2,
		Text = "Deal 1 damage to any unit.",
		Effect = { Kind = "DamageUnit", Amount = 1, Target = "AnyUnit" },
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

---------------------------------------------------------------------
-- CELESTIALS
---------------------------------------------------------------------
addCard {
	Id = "CEL-04",
	Name = "Flare Stallion",
	Faction = "Solar", -- primary faction for sorting; legality uses PairsWith
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 6,
	StarCost = 5,
	Power = 6,
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
	EnergyCost = 6,
	StarCost = 5,
	Power = 4,
	HP = 8,
	Keywords = { Regen = 1 },
	AbilityText = "When summoned, heal your Commander 4.",
	OnPlay = { Kind = "HealCommander", Amount = 4 },
	PairsWith = { "Lunar", "Nebula" },
}

addCard {
	Id = "CEL-06",
	Name = "Umbra, the Eclipse Wyrm",
	Faction = "Lunar",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 6,
	StarCost = 5,
	Power = 5,
	HP = 6,
	Keywords = { Shield = true },
	AbilityText = "When summoned, deal 2 damage to the strongest enemy unit.",
	OnPlay = { Kind = "DamageStrongestEnemy", Amount = 2 },
	PairsWith = { "Lunar", "Void" },
}

addCard {
	Id = "CEL-07",
	Name = "Protostar Colossus",
	Faction = "Solar",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 6,
	StarCost = 5,
	Power = 5,
	HP = 6,
	Keywords = { Ignite = 1 },
	AbilityText = "When summoned, your other units get +1 Power.",
	OnPlay = { Kind = "BuffAllFriendly", Power = 1, Other = true },
	PairsWith = { "Solar", "Nebula" },
}

---------------------------------------------------------------------
-- SOLAR
---------------------------------------------------------------------
addCard {
	Id = "SOL-001", Name = "Ember Scout", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 1, Power = 2, HP = 1,
	Keywords = { Rush = true },
}

addCard {
	Id = "SOL-002", Name = "Kindle", Faction = "Solar", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 1,
	AbilityText = "A unit gets +2 Power permanently.",
	Effect = { Kind = "BuffUnit", Power = 2, Target = "AnyUnit" },
}

addCard {
	Id = "SOL-003", Name = "Sunforge Cadet", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 2, HP = 3,
}

addCard {
	Id = "SOL-004", Name = "Flarecat", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 2, Power = 3, HP = 2,
	Keywords = { Rush = true },
}

addCard {
	Id = "SOL-005", Name = "Solar Flare", Faction = "Solar", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 1,
	AbilityText = "Deal 3 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 3, Target = "AnyUnit" },
}

addCard {
	Id = "SOL-006", Name = "Cinder Guard", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 2, HP = 5,
	Keywords = { Shield = true },
}

addCard {
	Id = "SOL-007", Name = "Solar Lancer", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 4, HP = 3,
	Keywords = { Ignite = 1 },
}

addCard {
	Id = "SOL-008", Name = "Blazewing Hawk", Faction = "Solar", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3, Power = 4, HP = 3,
	Keywords = { Rush = true, Ignite = 1 },
}

addCard {
	Id = "SOL-009", Name = "Heat Wave", Faction = "Solar", Type = "Spell", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3,
	AbilityText = "Deal 2 damage to all enemy units.",
	Effect = { Kind = "DamageAllEnemies", Amount = 2 },
}

addCard {
	Id = "SOL-010", Name = "Corona Knight", Faction = "Solar", Type = "Unit", Rarity = "Rare",
	EnergyCost = 5, StarCost = 3, Power = 5, HP = 6,
	Keywords = { Shield = true },
}

addCard {
	Id = "SOL-011", Name = "Dawnbreaker Titan", Faction = "Solar", Type = "Unit", Rarity = "Epic",
	EnergyCost = 7, StarCost = 4, Power = 7, HP = 7,
	Keywords = { Ignite = 3 },
}

-- Pack-only
addCard {
	Id = "SOL-012", Name = "Varro's Rally", Faction = "Solar", Type = "Spell", Rarity = "Epic",
	EnergyCost = 3, StarCost = 3,
	CommanderOnly = "CMD-SOL-01",
	AbilityText = "All your Solar units get +1 Power permanently.",
	Effect = { Kind = "BuffAllFriendly", Power = 1, Faction = "Solar" },
}

addCard {
	Id = "SOL-013", Name = "Heart of the Sun", Faction = "Solar", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 8, StarCost = 5, Power = 8, HP = 8,
	AbilityText = "When played, deal 2 damage to all enemy units.",
	OnPlay = { Kind = "DamageAllEnemies", Amount = 2 },
}

-- Added so the starter can use 1-2 copies of more cards (packs then fill out playsets)
addCard {
	Id = "SOL-014", Name = "Spark Sprite", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 1, Power = 1, HP = 2,
	Keywords = { Ignite = 1 },
}

addCard {
	Id = "SOL-015", Name = "Sunburst", Faction = "Solar", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 1,
	AbilityText = "Deal 2 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 2, Target = "AnyUnit" },
}

addCard {
	Id = "SOL-016", Name = "Forge Hound", Faction = "Solar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 2, Power = 2, HP = 2,
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
	EnergyCost = 4, StarCost = 2, Power = 5, HP = 4,
}

addCard {
	Id = "SOL-019", Name = "Sunstrike", Faction = "Solar", Type = "Spell", Rarity = "Common",
	EnergyCost = 4, StarCost = 2,
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
	EnergyCost = 5, StarCost = 3,
	AbilityText = "Deal 3 damage to all enemy units.",
	Effect = { Kind = "DamageAllEnemies", Amount = 3 },
}

addCard {
	Id = "SOL-022", Name = "Blaze Marshal", Faction = "Solar", Type = "Unit", Rarity = "Epic",
	EnergyCost = 5, StarCost = 4, Power = 5, HP = 5,
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
	EnergyCost = 1, StarCost = 1,
	AbilityText = "Heal your Commander 4.",
	Effect = { Kind = "HealCommander", Amount = 4 },
}

addCard {
	Id = "LUN-003", Name = "Silver Barrier", Faction = "Lunar", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 1,
	AbilityText = "Give one of your units a Shield.",
	Effect = { Kind = "GiveShield", Target = "FriendlyUnit" },
}

addCard {
	Id = "LUN-004", Name = "Crescent Archer", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 3, HP = 2,
}

addCard {
	Id = "LUN-005", Name = "Tide Sentinel", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 2, Power = 1, HP = 4,
	Keywords = { Shield = true },
}

addCard {
	Id = "LUN-006", Name = "Moonbeam", Faction = "Lunar", Type = "Spell", Rarity = "Common",
	EnergyCost = 3, StarCost = 2,
	AbilityText = "Deal 3 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 3, Target = "AnyUnit" },
}

addCard {
	Id = "LUN-007", Name = "Harbor Warden", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 2, HP = 5,
	Keywords = { Regen = 1 },
}

addCard {
	Id = "LUN-008", Name = "Lunar Priestess", Faction = "Lunar", Type = "Unit", Rarity = "Rare",
	EnergyCost = 3, StarCost = 2, Power = 2, HP = 4,
	AbilityText = "When played, heal all your units 3.",
	OnPlay = { Kind = "HealAllFriendly", Amount = 3 },
}

addCard {
	Id = "LUN-009", Name = "Eclipse Veil", Faction = "Lunar", Type = "Spell", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3,
	AbilityText = "Give all your units a Shield.",
	Effect = { Kind = "ShieldAllFriendly" },
}

addCard {
	Id = "LUN-010", Name = "Silver Knight", Faction = "Lunar", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3, Power = 4, HP = 5,
	Keywords = { Shield = true },
}

addCard {
	Id = "LUN-011", Name = "Tide Colossus", Faction = "Lunar", Type = "Unit", Rarity = "Epic",
	EnergyCost = 6, StarCost = 4, Power = 5, HP = 7,
	Keywords = { Regen = 1 },
}

-- Pack-only
addCard {
	Id = "LUN-012", Name = "Selene's Tide", Faction = "Lunar", Type = "Spell", Rarity = "Epic",
	EnergyCost = 4, StarCost = 3,
	CommanderOnly = "CMD-LUN-01",
	AbilityText = "Heal all your units and your Commander 4.",
	Effect = { Kind = "HealAllFriendly", Amount = 4, IncludeCommander = true },
}

addCard {
	Id = "LUN-013", Name = "Moon Leviathan", Faction = "Lunar", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 8, StarCost = 5, Power = 6, HP = 12,
	Keywords = { Shield = true, Regen = 3 },
}

-- Added so the starter can use 1-2 copies of more cards (packs then fill out playsets)
addCard {
	Id = "LUN-014", Name = "Pearl Crab", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 1, Power = 1, HP = 2,
	Keywords = { Shield = true },
}

addCard {
	Id = "LUN-015", Name = "Stargazer's Chart", Faction = "Lunar", Type = "Spell", Rarity = "Common",
	EnergyCost = 3, StarCost = 2,
	AbilityText = "Draw 2 cards.",
	Effect = { Kind = "Draw", Count = 2 },
}

addCard {
	Id = "LUN-016", Name = "Reef Guardian", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 2, Power = 2, HP = 3,
	Keywords = { Regen = 1 },
}

addCard {
	Id = "LUN-017", Name = "Silver Mender", Faction = "Lunar", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 2, HP = 4,
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
	EnergyCost = 2, StarCost = 1,
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
	EnergyCost = 5, StarCost = 3,
	AbilityText = "Deal 2 damage to all enemy units.",
	Effect = { Kind = "DamageAllEnemies", Amount = 2 },
}

addCard {
	Id = "LUN-022", Name = "Moonlight Oracle", Faction = "Lunar", Type = "Unit", Rarity = "Epic",
	EnergyCost = 5, StarCost = 4, Power = 3, HP = 6,
	AbilityText = "When played, draw 2 cards.",
	OnPlay = { Kind = "Draw", Count = 2 },
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
			-- 1 copy
			["NEU-001"] = 1, -- Star Map
			["SOL-015"] = 1, -- Sunburst
			["SOL-017"] = 1, -- Ember Drummer
			["SOL-018"] = 1, -- Magma Brute
			["SOL-019"] = 1, -- Sunstrike
			["SOL-008"] = 1, -- Blazewing Hawk
			["SOL-009"] = 1, -- Heat Wave
			["SOL-010"] = 1, -- Corona Knight
			["SOL-020"] = 1, -- Solar Phoenix
			["SOL-021"] = 1, -- Nova Burst
			["SOL-022"] = 1, -- Blaze Marshal
			["SOL-011"] = 1, -- Dawnbreaker Titan
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
			-- 1 copy
			["NEU-001"] = 1, -- Star Map
			["LUN-002"] = 1, -- Tidal Blessing
			["LUN-015"] = 1, -- Stargazer's Chart
			["LUN-017"] = 1, -- Silver Mender
			["LUN-018"] = 1, -- Tide Caller
			["LUN-008"] = 1, -- Lunar Priestess
			["LUN-009"] = 1, -- Eclipse Veil
			["LUN-010"] = 1, -- Silver Knight
			["LUN-020"] = 1, -- Crescent Warden
			["LUN-021"] = 1, -- Riptide
			["LUN-022"] = 1, -- Moonlight Oracle
			["LUN-011"] = 1, -- Tide Colossus
		},
	},
}

-- Display order for deck pickers
CardDatabase.StarterDeckOrder = { "Solar", "Lunar" }

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
function CardDatabase.ValidateDeck(commanderId, celestialId, cardIds)
	local rules = CardDatabase.Rules
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
		elseif card.Type ~= "Unit" and card.Type ~= "Spell" then
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
			if copies[id] == rules.MaxCopies + 1 then
				table.insert(errors, ("Too many copies of %s (max %d)."):format(card.Name, rules.MaxCopies))
			end
		end
	end

	if totalStars > rules.StarCap then
		table.insert(errors, ("Deck uses %d stars; the cap is %d."):format(totalStars, rules.StarCap))
	end

	return #errors == 0, errors, totalStars
end

return CardDatabase