--[[
	EconomyConfig (ModuleScript)
	Location: ReplicatedStorage > EconomyConfig

	Every number that controls coins, packs and currencies lives here.
	It's shared, so the shop can show players exactly the odds the server uses.
	Change a value here and both sides update.
]]

local EconomyConfig = {}

---------------------------------------------------------------------
-- Coins
---------------------------------------------------------------------
EconomyConfig.PackPriceCoins = 100
EconomyConfig.DailyCoinCap = 100       -- most coins you can earn from matches per day (~1 pack)
EconomyConfig.CoinCapMultiplier = 1    -- set to 2 during a special event to double the cap
EconomyConfig.StartingCoins = 100      -- new players can open one pack right away

-- Starter decks: a new player's first one is free, the rest cost coins
EconomyConfig.StarterDeckPriceCoins = 300

-- Turn on once coins can be bought with Robux. Coin-bought packs then count as
-- paid random items, and players whose region restricts them (PolicyService
-- ArePaidRandomItemsRestricted) are blocked from buying packs with coins.
-- They can still earn packs through Star Shards.
EconomyConfig.CoinsSoldForRobux = false

EconomyConfig.MatchRewards = {
	PvPWin = 50,
	PvPLoss = 25,
	BotWin = 25,
	BotLoss = 10,
	MinTurns = 6, -- matches shorter than this pay nothing (stops quick-concede farming)
}

---------------------------------------------------------------------
-- Star Shards (from breaking down duplicates; only buy packs)
---------------------------------------------------------------------
EconomyConfig.PackPriceShards = 100
EconomyConfig.ShardValues = {
	Common = 1,
	Rare = 5,
	Epic = 20,
	Legendary = 60,
}
-- Copies you always keep (per finish). Only extras beyond this can be broken down.
EconomyConfig.KeepCopies = {
	DeckCards = 3,             -- a full playset of units and spells
	CommandersAndCelestials = 1,
}
EconomyConfig.MythicCanBreakDown = false

---------------------------------------------------------------------
-- Star Tokens (pity): 1 per pack, trade 30 for any Commander or Celestial
---------------------------------------------------------------------
EconomyConfig.TokensPerPack = 1
EconomyConfig.TokenExchangeCost = 30

---------------------------------------------------------------------
-- Finishes: a pack copy shows the finish of its rarity
---------------------------------------------------------------------
EconomyConfig.FinishForRarity = {
	Common = "Base",
	Rare = "Holo",
	Epic = "Textured",
	Legendary = "3D",
}
EconomyConfig.StarterFinish = "Base" -- starter deck copies are always the plain version

---------------------------------------------------------------------
-- Pack contents. Each slot rolls once; Chance values in a slot add to 100.
-- Pools:
--   Common / Rare / Epic      -> deck cards (units and spells) of that rarity
--   LegendaryDeckCard         -> Legendary units and spells
--   CommanderOrCelestial      -> any Commander or Celestial
--   Mythic                    -> the Mythic alt art of any card
---------------------------------------------------------------------
EconomyConfig.PackSlots = {
	{ Name = "Common", Count = 4, Outcomes = {
		{ Pool = "Common", Chance = 100 },
	} },
	{ Name = "Rare slot", Count = 1, Outcomes = {
		{ Pool = "Rare", Chance = 90 },
		{ Pool = "Epic", Chance = 10 },
	} },
	{ Name = "Star Slot", Count = 1, Outcomes = {
		{ Pool = "Epic", Chance = 89.5 },
		{ Pool = "LegendaryDeckCard", Chance = 5 },
		{ Pool = "CommanderOrCelestial", Chance = 5 },
		{ Pool = "Mythic", Chance = 0.5 },
	} },
}

EconomyConfig.PoolNames = {
	Common = "Common",
	Rare = "Rare",
	Epic = "Epic",
	LegendaryDeckCard = "Legendary",
	CommanderOrCelestial = "Commander or Celestial",
	Mythic = "Mythic alt art (any card)",
}

return EconomyConfig