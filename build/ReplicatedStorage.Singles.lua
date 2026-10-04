--[[
	Singles (ModuleScript)
	Location: ReplicatedStorage > Singles

	The singles case: a handful of cards for sale, changing every day at
	midnight UTC. Every server picks the same cards (the day number seeds the
	pick), so the case matches for everyone.

	Prices come from the real pack odds: how many boosters it takes on average
	to pull that card (from its own faction's booster), times the pack price,
	times a discount (packs give you other cards too, so a single costs less
	than the full expected spend).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local Packs = require(ReplicatedStorage:WaitForChild("Packs"))

local Singles = {}

-- What the case holds each day (counts by kind)
Singles.Mix = {
	{ Kind = "Rare", Count = 5 },
	{ Kind = "Epic", Count = 4 },
	{ Kind = "Legendary", Count = 2 },        -- Legendary units and spells
	{ Kind = "CommanderOrCelestial", Count = 1 },
}
Singles.Discount = 0.5   -- price = expected pack spend x this
Singles.MinPrice = 40
Singles.RoundTo = 5
-- A Commander or Celestial never costs more than trading Star Tokens would
-- (30 tokens = 30 packs), at the same discount
Singles.MaxPrice = math.floor(EconomyConfig.TokenExchangeCost * EconomyConfig.PackPriceCoins * 0.5)

local SECONDS_PER_DAY = 86400

function Singles.Today(now)
	return math.floor((now or os.time()) / SECONDS_PER_DAY)
end

function Singles.SecondsUntilRestock(now)
	now = now or os.time()
	return SECONDS_PER_DAY - (now % SECONDS_PER_DAY)
end

-- Expected copies of this card in one pack of a type (sum over every slot)
function Singles.CopiesPerPack(cardId, packTypeId)
	local pools = Packs.GetPools(packTypeId)
	local expected = 0
	for _, slot in ipairs(EconomyConfig.PackSlots) do
		for _, outcome in ipairs(slot.Outcomes) do
			if outcome.Pool ~= "Mythic" then
				local pool = pools[outcome.Pool]
				for _, id in ipairs(pool) do
					if id == cardId then
						expected = expected + slot.Count * (outcome.Chance / 100) / #pool
					end
				end
			end
		end
	end
	return expected
end

-- The booster that pulls this card most often
local function bestPackFor(card)
	local best, bestRate = nil, 0
	for _, packType in ipairs(EconomyConfig.PackTypes) do
		local rate = Singles.CopiesPerPack(card.Id, packType.Id)
		if rate > bestRate then
			best, bestRate = packType, rate
		end
	end
	return best, bestRate
end

-- Price of a card, and how it was worked out
-- Returns price, { ExpectedPacks, PackName }
function Singles.PriceFor(cardId)
	local card = CardDatabase.GetCard(cardId)
	local packType, rate = bestPackFor(card)
	if not packType or rate <= 0 then
		return nil
	end
	local expectedPacks = 1 / rate
	local price = expectedPacks * EconomyConfig.PackPriceCoins * Singles.Discount
	if card.Type == "Commander" or card.Type == "Celestial" then
		price = math.min(price, Singles.MaxPrice)
	end
	price = math.max(Singles.MinPrice, math.floor(price / Singles.RoundTo + 0.5) * Singles.RoundTo)
	return price, { ExpectedPacks = expectedPacks, PackName = packType.Name }
end

local function kindOf(card)
	if card.Type == "Commander" or card.Type == "Celestial" then
		return "CommanderOrCelestial"
	end
	return card.Rarity
end

-- Today's stock: list of { CardId, Finish, Price, ExpectedPacks, PackName }
local cache = {}
function Singles.StockForDay(day)
	if cache[day] then
		return cache[day]
	end
	-- the same day gives the same cards on every server
	local rng = Random.new(day * 7919 + 101)
	local byKind = {}
	for _, card in ipairs(CardDatabase.GetAllCards()) do
		-- (Anomalies only while they're switched on)
		local switchedOff = card.Type == "Anomaly" and CardDatabase.Rules.AnomaliesEnabled == false
		if card.InPacks ~= false and not switchedOff then
			local kind = kindOf(card)
			byKind[kind] = byKind[kind] or {}
			table.insert(byKind[kind], card.Id)
		end
	end
	local stock = {}
	for _, want in ipairs(Singles.Mix) do
		local pool = {}
		for i, id in ipairs(byKind[want.Kind] or {}) do
			pool[i] = id
		end
		table.sort(pool) -- same order everywhere before the seeded pick
		for _ = 1, math.min(want.Count, #pool) do
			local cardId = table.remove(pool, rng:NextInteger(1, #pool))
			local card = CardDatabase.GetCard(cardId)
			local price, info = Singles.PriceFor(cardId)
			if price then
			table.insert(stock, {
				CardId = cardId,
				Finish = EconomyConfig.FinishForRarity[card.Rarity] or "Base",
				Price = price,
				ExpectedPacks = math.floor(info.ExpectedPacks * 10 + 0.5) / 10,
				PackName = info.PackName,
			})
			end
		end
	end
	cache = { [day] = stock } -- keep only the current day
	return stock
end

function Singles.FindInStock(day, cardId)
	for _, entry in ipairs(Singles.StockForDay(day)) do
		if entry.CardId == cardId then
			return entry
		end
	end
	return nil
end

return Singles
