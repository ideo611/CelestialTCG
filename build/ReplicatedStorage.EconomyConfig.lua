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

-- PLAYTEST: every player is topped up to this many coins once (new and
-- returning players alike), so testers can try packs, singles and mats.
-- Set to 0 before the real launch.
EconomyConfig.PlaytestCoins = 0 -- LAUNCH: no test coins (was 5000 for playtesting)

-- Starter decks: a new player's first one is free, the rest cost coins
EconomyConfig.StarterDeckPriceCoins = 300

-- Turn on once coins can be bought with Robux. Coin-bought packs then count as
-- paid random items, and players whose region restricts them (PolicyService
-- ArePaidRandomItemsRestricted) are blocked from buying packs with coins.
-- They can still earn packs through Star Shards.
EconomyConfig.CoinsSoldForRobux = false

-- First win of each day (UTC) pays this bonus on top of the match reward.
-- It doesn't count toward the daily cap. (Planned: becomes a Booster Pack Ticket.)
EconomyConfig.FirstWinBonusCoins = 50

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
	LegendaryDeckCards = 1,    -- Legendary units and spells are one-ofs
	CommandersAndCelestials = 1,
}
EconomyConfig.MythicCanBreakDown = false

---------------------------------------------------------------------
-- Star Tokens (pity): 1 per pack, trade 30 for any Commander or Celestial
---------------------------------------------------------------------
EconomyConfig.TokensPerPack = 1
EconomyConfig.TokenExchangeCost = 30

---------------------------------------------------------------------
-- Finishes used outside packs (singles and token trades): the finish of the
-- card's rarity. Pack cards roll their finish instead (PackSlots below).
---------------------------------------------------------------------
EconomyConfig.FinishForRarity = {
	Common = "Base",
	Rare = "Holo",
	Epic = "Textured",
	Legendary = "3D",
}
EconomyConfig.StarterFinish = "Base" -- starter deck copies are always the plain version

---------------------------------------------------------------------
-- Pack contents. Each card first rolls its rarity (the slot's Outcomes),
-- then rolls its finish (the slot's Finishes). Chances in each list add to 100.
-- Pools:
--   Common / Rare / Epic      -> deck cards (units and spells) of that rarity
--   LegendaryDeckCard         -> Legendary units and spells
--   CommanderOrCelestial      -> any Commander or Celestial (also Legendary)
---------------------------------------------------------------------
EconomyConfig.PackSlots = {
	{ Name = "Common", Count = 4, Outcomes = {
		{ Pool = "Common", Chance = 100 },
	}, Finishes = {
		{ Finish = "Base", Chance = 85 },
		{ Finish = "Holo", Chance = 12 },
		{ Finish = "Textured", Chance = 2.5 },
		{ Finish = "3D", Chance = 0.5 },
	} },
	{ Name = "Rare slot", Count = 1, Outcomes = {
		{ Pool = "Common", Chance = 65 },
		{ Pool = "Rare", Chance = 35 },
	}, Finishes = {
		{ Finish = "Base", Chance = 70 },
		{ Finish = "Holo", Chance = 22 },
		{ Finish = "Textured", Chance = 6 },
		{ Finish = "3D", Chance = 2 },
	} },
	{ Name = "Star Slot", Count = 1, Outcomes = {
		{ Pool = "Rare", Chance = 59 },
		{ Pool = "Epic", Chance = 30 },
		{ Pool = "LegendaryDeckCard", Chance = 5 },
		{ Pool = "CommanderOrCelestial", Chance = 5 },
		-- Mythic: a full-art Commander or Celestial, always in the Mythic finish,
		-- never one you already have as a Mythic (until you have them all)
		{ Pool = "Mythic", Chance = 1, Finish = "Mythic" },
	}, Finishes = {
		{ Finish = "Base", Chance = 50 },
		{ Finish = "Holo", Chance = 30 },
		{ Finish = "Textured", Chance = 13 },
		{ Finish = "3D", Chance = 7 },
	} },
}

EconomyConfig.PoolNames = {
	Common = "Common",
	Rare = "Rare",
	Epic = "Epic",
	LegendaryDeckCard = "Legendary",
	CommanderOrCelestial = "Commander or Celestial",
	Mythic = "Mythic (full-art Commander or Celestial)",
}

---------------------------------------------------------------------
-- Booster types. Every booster has the same slots and chances (above);
-- a faction booster only holds that faction's cards, plus Neutral cards
-- and every Celestial that pairs with the faction.
-- To sell a faction's booster once its cards are in the game, set
-- Enabled = true on it. Only enabled boosters show up anywhere.
---------------------------------------------------------------------
EconomyConfig.AllPackTypes = {
	{ Id = "All", Name = "Celestial Booster", Faction = nil, Enabled = true },
	{ Id = "Solar", Name = "Solar Booster", Faction = "Solar", Enabled = true },
	{ Id = "Lunar", Name = "Lunar Booster", Faction = "Lunar", Enabled = true },
	{ Id = "Nebula", Name = "Nebula Booster", Faction = "Nebula", Enabled = true },
	{ Id = "Void", Name = "Void Booster", Faction = "Void", Enabled = true },
	{ Id = "Comet", Name = "Comet Booster", Faction = "Comet", Enabled = true },
}
EconomyConfig.DefaultPackType = "All"

-- When buying, the shop lays out this many packs of the chosen booster,
-- each with a different card's art on the front, and the player picks one.
-- The front is only a look: every pack has the same odds.
EconomyConfig.PackChoices = 3

EconomyConfig.PackTypes = {}
for _, packType in ipairs(EconomyConfig.AllPackTypes) do
	if packType.Enabled then
		table.insert(EconomyConfig.PackTypes, packType)
	end
end

function EconomyConfig.GetPackType(id)
	for _, packType in ipairs(EconomyConfig.PackTypes) do
		if packType.Id == id then
			return packType
		end
	end
	return nil
end

return EconomyConfig
