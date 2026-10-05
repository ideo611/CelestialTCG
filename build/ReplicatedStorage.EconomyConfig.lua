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
EconomyConfig.PackPriceCoins = 50
EconomyConfig.DailyCoinCap = 150       -- most coins you can earn from matches per day (3 packs)
EconomyConfig.DailyCoinPacks = 3       -- packs you can buy with coins per day (tickets and Star Shards don't count)
EconomyConfig.CoinCapMultiplier = 1    -- set to 2 during a special event to double the cap
EconomyConfig.StartingCoins = 100      -- new players can open one pack right away

-- PLAYTEST: every player is topped up to this many coins once (new and
-- returning players alike), so testers can try packs, singles and mats.
-- Set to 0 before the real launch.
EconomyConfig.PlaytestCoins = 0 -- LAUNCH: no test coins (was 5000 for playtesting)

-- Starter decks: a new player's first one is free, the rest cost coins
EconomyConfig.StarterDeckPriceCoins = 150

-- Turn on once coins can be bought with Robux. Coin-bought packs then count as
-- paid random items, and players whose region restricts them (PolicyService
-- ArePaidRandomItemsRestricted) are blocked from buying packs with coins.
-- They can still earn packs through Star Shards.
EconomyConfig.CoinsSoldForRobux = false

-- First win of each day (UTC) pays a Booster Pack Ticket on top of the match
-- reward (and FirstWinBonusCoins, now 0). Neither counts toward the daily cap.
EconomyConfig.FirstWinTickets = 1
EconomyConfig.FirstWinBonusCoins = 0
-- Finishing the tutorial (not skipping it) pays this many tickets, once
EconomyConfig.TutorialTickets = 1

EconomyConfig.MatchRewards = {
	PvPWin = 10,
	PvPLoss = 5,
	BotWin = 10,
	BotLoss = 5,
	MinTurns = 6, -- matches shorter than this pay nothing (stops quick-concede farming)
}

---------------------------------------------------------------------
-- Robux products (Developer Products). Create each one in the Creator
-- Dashboard (Monetization > Developer Products) and paste its Product ID.
-- ProductId 0 = not set up yet: the shop shows "coming soon" for it.
-- Booster Pack Tickets open any booster, don't count toward the daily coin
-- pack limit, and never expire. A Booster Box is kept sealed until opened.
---------------------------------------------------------------------
EconomyConfig.Products = {
	-- Robux = the price set on the Creator Dashboard (what Roblox actually charges;
	-- the shop reads the live price from Roblox and only falls back to this).
	-- ~80 Robux = $1 in the smallest Robux bundle.
	Ticket1 = { ProductId = 3716569130, Robux = 160, Tickets = 1, Name = "1 Booster Pack Ticket" },    -- ~$2
	Ticket5 = { ProductId = 3716569254, Robux = 640, Tickets = 5, Name = "5 Booster Pack Tickets" },   -- ~$8 (20% off)
	BoosterBox = { ProductId = 3716569336, Robux = 1440, Boxes = 1, Name = "Booster Box" },           -- ~$18 (12 packs + topper, 25% off)
}
EconomyConfig.ProductOrder = { "Ticket1", "Ticket5", "BoosterBox" }

function EconomyConfig.ProductKeyForId(productId)
	for key, product in pairs(EconomyConfig.Products) do
		if product.ProductId ~= 0 and product.ProductId == productId then
			return key
		end
	end
	return nil
end

-- Launch gift: until Ends (a time in seconds, os.time), every player who has a
-- starter deck gets Boxes free Booster Boxes of their first starter's faction
-- (once per player). Ends 2026-10-19, midnight Pacific.
EconomyConfig.LaunchGift = { Ends = 1792393200, Boxes = 1 }

-- A Booster Box: this many packs of one booster (picked when opening), plus a
-- box topper: a Commander or Celestial (one you don't own yet if possible)
-- in a shiny finish
EconomyConfig.Box = {
	Packs = 12,
	TopperFinishes = {
		{ Finish = "Holo", Chance = 60 },
		{ Finish = "Textured", Chance = 30 },
		{ Finish = "3D", Chance = 10 },
	},
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
