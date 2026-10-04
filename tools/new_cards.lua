--@@COMMANDERS
addCard {
	Id = "CMD-NEB-01",
	Name = "Seraphine, the Star-Nursery",
	Faction = "Nebula",
	Type = "Commander",
	Rarity = "Legendary",
	HP = 20,
	CommanderAbility = {
		EnergyCost = 2,
		Text = "Give one of your units Grow 1.",
		Effect = { Kind = "GiveGrow", Amount = 1, Target = "FriendlyUnit" },
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
		EnergyCost = 3,
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
		EnergyCost = 1,
		Text = "Your Commander takes 2 damage. Gain 2 energy this turn.",
		Effect = { Kind = "PayForEnergy", HP = 2, Energy = 2 },
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
		EnergyCost = 3,
		Text = "An enemy unit gets -2 Power permanently.",
		Effect = { Kind = "Weaken", Amount = 2, Target = "EnemyUnit" },
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
		EnergyCost = 2,
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
--@@CELESTIALS
addCard {
	Id = "CEL-08",
	Name = "Equinox Seraph",
	Faction = "Solar",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 6,
	StarCost = 5,
	Power = 5,
	HP = 6,
	Keywords = { Shield = true, Ignite = 1 },
	PairsWith = { "Solar", "Lunar" },
}

addCard {
	Id = "CEL-09",
	Name = "Black Sun Harbinger",
	Faction = "Solar",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 6,
	StarCost = 5,
	Power = 6,
	HP = 5,
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
	EnergyCost = 6,
	StarCost = 5,
	Power = 5,
	HP = 6,
	AbilityText = "When summoned, return the strongest enemy unit to its owner's hand.",
	OnPlay = { Kind = "ReturnStrongestEnemy" },
	PairsWith = { "Lunar", "Comet" },
}

addCard {
	Id = "CEL-11",
	Name = "Pulsar Remnant",
	Faction = "Void",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 6,
	StarCost = 5,
	Power = 4,
	HP = 6,
	Keywords = { Grow = 1, Decay = 1 },
	PairsWith = { "Nebula", "Void" },
}

addCard {
	Id = "CEL-12",
	Name = "Aurora Skywhale",
	Faction = "Nebula",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 6,
	StarCost = 5,
	Power = 4,
	HP = 7,
	Keywords = { Grow = 1 },
	AbilityText = "When summoned, draw a card.",
	OnPlay = { Kind = "Draw", Count = 1 },
	PairsWith = { "Nebula", "Comet" },
}

addCard {
	Id = "CEL-13",
	Name = "Oort Reaper",
	Faction = "Comet",
	Type = "Celestial",
	Rarity = "Legendary",
	EnergyCost = 6,
	StarCost = 5,
	Power = 4,
	HP = 5,
	Keywords = { Streak = true },
	PairsWith = { "Void", "Comet" },
}
--@@FACTIONS
---------------------------------------------------------------------
-- NEBULA: small units that Grow every turn
---------------------------------------------------------------------
addCard {
	Id = "NEB-001", Name = "Stardust Mote", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 1, Power = 1, HP = 2,
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
	EnergyCost = 2, StarCost = 1, Power = 1, HP = 4,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-004", Name = "Prism Moth", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 1, Power = 3, HP = 1,
}

addCard {
	Id = "NEB-005", Name = "Stellar Seedling", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 2, Power = 0, HP = 3,
	Keywords = { Grow = 2 },
}

addCard {
	Id = "NEB-006", Name = "Cloud Shepherd", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 2, Power = 2, HP = 2,
	AbilityText = "When played, your strongest other unit gets Grow 1.",
	OnPlay = { Kind = "GrowStrongestFriendly", Amount = 1, Other = true },
}

addCard {
	Id = "NEB-007", Name = "Spore Burst", Faction = "Nebula", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 1,
	AbilityText = "Deal 2 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 2, Target = "AnyUnit" },
}

addCard {
	Id = "NEB-008", Name = "Photon Gardener", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 2, HP = 4,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-009", Name = "Drift Grazer", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 2, HP = 3,
	AbilityText = "When played, draw a card.",
	OnPlay = { Kind = "Draw", Count = 1 },
}

addCard {
	Id = "NEB-010", Name = "Star Cradle", Faction = "Nebula", Type = "Spell", Rarity = "Common",
	EnergyCost = 3, StarCost = 2,
	AbilityText = "Draw 2 cards.",
	Effect = { Kind = "Draw", Count = 2 },
}

addCard {
	Id = "NEB-011", Name = "Coral Golem", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 5, StarCost = 2, Power = 3, HP = 6,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-012", Name = "Nova Hatchling", Faction = "Nebula", Type = "Unit", Rarity = "Common",
	EnergyCost = 4, StarCost = 2, Power = 4, HP = 5,
}

addCard {
	Id = "NEB-013", Name = "Gravity Bloom", Faction = "Nebula", Type = "Spell", Rarity = "Common",
	EnergyCost = 3, StarCost = 2,
	AbilityText = "Deal 3 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 3, Target = "AnyUnit" },
}

addCard {
	Id = "NEB-014", Name = "Aurora Stag", Faction = "Nebula", Type = "Unit", Rarity = "Rare",
	EnergyCost = 3, StarCost = 3, Power = 3, HP = 3,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-015", Name = "Starseed Druid", Faction = "Nebula", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3, Power = 3, HP = 5,
	AbilityText = "When played, your other units get Grow 1.",
	OnPlay = { Kind = "GrowAllFriendly", Amount = 1, Other = true },
}

addCard {
	Id = "NEB-016", Name = "Bloom Surge", Faction = "Nebula", Type = "Spell", Rarity = "Rare",
	EnergyCost = 3, StarCost = 3,
	AbilityText = "All your units get +1 Power permanently.",
	Effect = { Kind = "BuffAllFriendly", Power = 1 },
}

addCard {
	Id = "NEB-017", Name = "Veil Ray", Faction = "Nebula", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3, Power = 4, HP = 4,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-018", Name = "Pulse of Creation", Faction = "Nebula", Type = "Spell", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3,
	AbilityText = "Draw 2 cards. Your strongest unit gets Grow 1.",
	Effect = { Kind = "Multi", Effects = {
		{ Kind = "Draw", Count = 2 },
		{ Kind = "GrowStrongestFriendly", Amount = 1, Bonus = true },
	} },
}

addCard {
	Id = "NEB-019", Name = "Pillar Titan", Faction = "Nebula", Type = "Unit", Rarity = "Epic",
	EnergyCost = 7, StarCost = 4, Power = 5, HP = 8,
	Keywords = { Grow = 1 },
}

addCard {
	Id = "NEB-020", Name = "Genesis Bloom", Faction = "Nebula", Type = "Spell", Rarity = "Epic",
	EnergyCost = 4, StarCost = 4,
	AbilityText = "All your units get Grow 1.",
	Effect = { Kind = "GrowAllFriendly", Amount = 1 },
}

addCard {
	Id = "NEB-021", Name = "Cradle Warden", Faction = "Nebula", Type = "Unit", Rarity = "Epic",
	EnergyCost = 6, StarCost = 4, Power = 4, HP = 6,
	Keywords = { Grow = 1 },
	AbilityText = "When played, your other units get Grow 1.",
	OnPlay = { Kind = "GrowAllFriendly", Amount = 1, Other = true },
}

addCard {
	Id = "NEB-022", Name = "The First Light", Faction = "Nebula", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 8, StarCost = 5, Power = 6, HP = 9,
	Keywords = { Grow = 2 },
}

---------------------------------------------------------------------
-- VOID: Decay wears enemies down; some cards cost your Commander's HP
---------------------------------------------------------------------
addCard {
	Id = "VOI-001", Name = "Shade Wisp", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 1, Power = 1, HP = 2,
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
	EnergyCost = 2, StarCost = 1, Power = 2, HP = 2,
	Keywords = { Decay = 1 },
}

addCard {
	Id = "VOI-004", Name = "Entropy Bolt", Faction = "Void", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, HPCost = 2, StarCost = 1,
	AbilityText = "Deal 3 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 3, Target = "AnyUnit" },
}

addCard {
	Id = "VOI-005", Name = "Duskforged Sentry", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 2, HP = 4,
}

addCard {
	Id = "VOI-006", Name = "Null Acolyte", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 3, HP = 3,
	AbilityText = "When played, the strongest enemy unit gets -1 Power permanently.",
	OnPlay = { Kind = "WeakenStrongestEnemy", Amount = 1 },
}

addCard {
	Id = "VOI-007", Name = "Wither", Faction = "Void", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 1,
	AbilityText = "An enemy unit gets -2 Power permanently.",
	Effect = { Kind = "Weaken", Amount = 2, Target = "EnemyUnit" },
}

addCard {
	Id = "VOI-008", Name = "Event Skimmer", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 3, HP = 3,
	Keywords = { Decay = 1 },
}

addCard {
	Id = "VOI-009", Name = "Rift Stalker", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 3, HP = 2,
}

addCard {
	Id = "VOI-010", Name = "Obsidian Hulk", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, HPCost = 2, StarCost = 2, Power = 5, HP = 4,
}

addCard {
	Id = "VOI-011", Name = "Dark Matter Shroud", Faction = "Void", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 2,
	AbilityText = "Destroy a unit with 2 or less Power.",
	Effect = { Kind = "Destroy", Target = "AnyUnit", MaxPower = 2 },
}

addCard {
	Id = "VOI-012", Name = "Horizon Warden", Faction = "Void", Type = "Unit", Rarity = "Common",
	EnergyCost = 5, StarCost = 2, Power = 3, HP = 6,
	Keywords = { Decay = 1 },
}

addCard {
	Id = "VOI-013", Name = "Siphon", Faction = "Void", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 1,
	AbilityText = "Deal 2 damage to a unit. Heal your Commander 2.",
	Effect = { Kind = "Multi", Target = "AnyUnit", Effects = {
		{ Kind = "DamageUnit", Amount = 2, Target = "AnyUnit" },
		{ Kind = "HealCommander", Amount = 2, Bonus = true },
	} },
}

addCard {
	Id = "VOI-014", Name = "Accretion Knight", Faction = "Void", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3, Power = 4, HP = 5,
	Keywords = { Decay = 1 },
}

addCard {
	Id = "VOI-015", Name = "Collapse", Faction = "Void", Type = "Spell", Rarity = "Rare",
	EnergyCost = 3, HPCost = 3, StarCost = 3,
	AbilityText = "Destroy a unit.",
	Effect = { Kind = "Destroy", Target = "AnyUnit" },
}

addCard {
	Id = "VOI-016", Name = "Umbral Lantern-Bearer", Faction = "Void", Type = "Unit", Rarity = "Rare",
	EnergyCost = 3, StarCost = 3, Power = 2, HP = 4,
	AbilityText = "When played, all enemy units get -1 Power permanently.",
	OnPlay = { Kind = "WeakenAllEnemies", Amount = 1 },
}

addCard {
	Id = "VOI-017", Name = "Graviton Lancer", Faction = "Void", Type = "Unit", Rarity = "Rare",
	EnergyCost = 5, StarCost = 3, Power = 5, HP = 4,
	Keywords = { Decay = 2 },
}

addCard {
	Id = "VOI-018", Name = "Black Tide", Faction = "Void", Type = "Spell", Rarity = "Rare",
	EnergyCost = 3, StarCost = 3,
	AbilityText = "Deal 2 damage to all units, yours included.",
	Effect = { Kind = "DamageAllUnits", Amount = 2 },
}

addCard {
	Id = "VOI-019", Name = "Singularity Behemoth", Faction = "Void", Type = "Unit", Rarity = "Epic",
	EnergyCost = 7, StarCost = 4, Power = 6, HP = 8,
	Keywords = { Decay = 2 },
}

addCard {
	Id = "VOI-020", Name = "Malakar's Bargain", Faction = "Void", Type = "Spell", Rarity = "Epic",
	EnergyCost = 2, HPCost = 4, StarCost = 3,
	AbilityText = "Draw 3 cards.",
	Effect = { Kind = "Draw", Count = 3 },
}

addCard {
	Id = "VOI-021", Name = "Hollow Archon", Faction = "Void", Type = "Unit", Rarity = "Epic",
	EnergyCost = 5, StarCost = 4, Power = 4, HP = 5,
	AbilityText = "When played, destroy the strongest enemy unit with 3 or less Power.",
	OnPlay = { Kind = "DestroyStrongestEnemy", MaxPower = 3 },
}

addCard {
	Id = "VOI-022", Name = "Night Sovereign", Faction = "Void", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 8, StarCost = 5, Power = 7, HP = 9,
	Keywords = { Decay = 3 },
}

---------------------------------------------------------------------
-- COMET: fragile units with Streak that fly past blockers
---------------------------------------------------------------------
addCard {
	Id = "COM-001", Name = "Frost Skipper", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 1, StarCost = 1, Power = 1, HP = 1,
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
	EnergyCost = 2, StarCost = 1, Power = 2, HP = 2,
	Keywords = { Rush = true },
}

addCard {
	Id = "COM-004", Name = "Tailwind Glider", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 1, HP = 3,
	Keywords = { Streak = true },
}

addCard {
	Id = "COM-005", Name = "Rime Hound", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 2, StarCost = 1, Power = 2, HP = 3,
}

addCard {
	Id = "COM-006", Name = "Recall Beacon", Faction = "Comet", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 1,
	AbilityText = "Return one of your units to your hand.",
	Effect = { Kind = "ReturnToHand", Target = "FriendlyUnit" },
}

addCard {
	Id = "COM-007", Name = "Ice Shard", Faction = "Comet", Type = "Spell", Rarity = "Common",
	EnergyCost = 1, StarCost = 1,
	AbilityText = "Deal 2 damage to a unit.",
	Effect = { Kind = "DamageUnit", Amount = 2, Target = "AnyUnit" },
}

addCard {
	Id = "COM-008", Name = "Shard Racer", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 2, HP = 2,
	Keywords = { Streak = true, Rush = true },
}

addCard {
	Id = "COM-009", Name = "Glacier Ward", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 1, Power = 2, HP = 5,
}

addCard {
	Id = "COM-010", Name = "Frostbite Archer", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 3, StarCost = 2, Power = 3, HP = 3,
	AbilityText = "When played, deal 1 damage to the strongest enemy unit.",
	OnPlay = { Kind = "DamageStrongestEnemy", Amount = 1 },
}

addCard {
	Id = "COM-011", Name = "Deflect", Faction = "Comet", Type = "Spell", Rarity = "Common",
	EnergyCost = 2, StarCost = 1,
	AbilityText = "Return an enemy unit with 3 or less Power to its owner's hand.",
	Effect = { Kind = "ReturnToHand", Target = "EnemyUnit", MaxPower = 3 },
}

addCard {
	Id = "COM-012", Name = "Kuiper Drifter", Faction = "Comet", Type = "Unit", Rarity = "Common",
	EnergyCost = 4, StarCost = 2, Power = 3, HP = 3,
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
	EnergyCost = 4, StarCost = 3, Power = 4, HP = 4,
	Keywords = { Rush = true },
}

addCard {
	Id = "COM-015", Name = "Starlance Interceptor", Faction = "Comet", Type = "Unit", Rarity = "Rare",
	EnergyCost = 5, StarCost = 3, Power = 4, HP = 4,
	Keywords = { Streak = true },
}

addCard {
	Id = "COM-016", Name = "Perihelion Dash", Faction = "Comet", Type = "Spell", Rarity = "Rare",
	EnergyCost = 3, StarCost = 3,
	AbilityText = "Your units get Streak this turn.",
	Effect = { Kind = "StreakAllFriendly" },
}

addCard {
	Id = "COM-017", Name = "Iceborn Sentinel", Faction = "Comet", Type = "Unit", Rarity = "Rare",
	EnergyCost = 4, StarCost = 3, Power = 3, HP = 6,
	AbilityText = "When played, return the strongest enemy unit with 2 or less Power to its owner's hand.",
	OnPlay = { Kind = "ReturnStrongestEnemy", MaxPower = 2 },
}

addCard {
	Id = "COM-018", Name = "Comet Fall", Faction = "Comet", Type = "Spell", Rarity = "Rare",
	EnergyCost = 5, StarCost = 3,
	AbilityText = "Deal 4 damage to an enemy unit and 1 to every other enemy unit.",
	Effect = { Kind = "Multi", Target = "EnemyUnit", Effects = {
		{ Kind = "DamageUnit", Amount = 4, Target = "EnemyUnit" },
		{ Kind = "DamageOtherEnemies", Amount = 1 },
	} },
}

addCard {
	Id = "COM-019", Name = "Vanguard of the Long Orbit", Faction = "Comet", Type = "Unit", Rarity = "Epic",
	EnergyCost = 7, StarCost = 4, Power = 5, HP = 5,
	Keywords = { Rush = true, Streak = true },
}

addCard {
	Id = "COM-020", Name = "Frostwake Tide", Faction = "Comet", Type = "Spell", Rarity = "Epic",
	EnergyCost = 5, StarCost = 4,
	AbilityText = "Return all enemy units with 3 or less Power to their owners' hands.",
	Effect = { Kind = "ReturnAllEnemies", MaxPower = 3 },
}

addCard {
	Id = "COM-021", Name = "Tailwind Herald", Faction = "Comet", Type = "Unit", Rarity = "Epic",
	EnergyCost = 5, StarCost = 4, Power = 3, HP = 5,
	AbilityText = "When played, your other units get Streak this turn.",
	OnPlay = { Kind = "StreakAllFriendly", Other = true },
}

addCard {
	Id = "COM-022", Name = "The Great Comet", Faction = "Comet", Type = "Unit", Rarity = "Legendary",
	EnergyCost = 9, StarCost = 5, Power = 7, HP = 7,
	Keywords = { Rush = true, Streak = true },
}

