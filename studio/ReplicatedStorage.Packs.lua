--[[
	Packs (ModuleScript)
	Location: ReplicatedStorage > Packs

	Builds the card pools, rolls packs, and calculates the exact odds of
	every outcome. The shop reads GetOddsTable() to show players the odds
	(Roblox requires this for paid random items). Only rolls made by the
	server count; a player running this on their own screen gets nothing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))

local Packs = {}

---------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------
local pools = nil

local function isDeckCard(card)
	return card.Type == "Unit" or card.Type == "Spell"
end

function Packs.GetPools()
	if pools then
		return pools
	end
	pools = {
		Common = {},
		Rare = {},
		Epic = {},
		LegendaryDeckCard = {},
		CommanderOrCelestial = {},
		Mythic = {},
	}
	for _, card in ipairs(CardDatabase.GetAllCards()) do
		if card.InPacks ~= false then
			table.insert(pools.Mythic, card.Id)
			if card.Type == "Commander" or card.Type == "Celestial" then
				table.insert(pools.CommanderOrCelestial, card.Id)
			elseif isDeckCard(card) then
				if card.Rarity == "Legendary" then
					table.insert(pools.LegendaryDeckCard, card.Id)
				else
					table.insert(pools[card.Rarity], card.Id)
				end
			end
		end
	end
	-- Every pool a pack can roll must have cards in it
	for _, slot in ipairs(EconomyConfig.PackSlots) do
		local total = 0
		for _, outcome in ipairs(slot.Outcomes) do
			assert(pools[outcome.Pool], "Unknown pool " .. tostring(outcome.Pool))
			assert(#pools[outcome.Pool] > 0, "Pool " .. outcome.Pool .. " has no cards")
			total = total + outcome.Chance
		end
		assert(math.abs(total - 100) < 1e-9, slot.Name .. " chances add to " .. total .. ", not 100")
	end
	return pools
end

-- The finish a card comes in when pulled from a given pool
function Packs.FinishFor(cardId, pool)
	if pool == "Mythic" then
		return "Mythic"
	end
	local card = CardDatabase.GetCard(cardId)
	return EconomyConfig.FinishForRarity[card.Rarity] or "Base"
end

---------------------------------------------------------------------
-- Rolling
-- rng(n) must return a whole number from 1 to n.
-- Returns a list of pulls: { CardId, Finish, Pool, Slot }, best card last.
---------------------------------------------------------------------
local ROLL_SCALE = 10000 -- chances are rolled in hundredths of a percent

local POOL_RANK = { Common = 1, Rare = 2, Epic = 3, LegendaryDeckCard = 4, CommanderOrCelestial = 5, Mythic = 6 }

function Packs.Roll(rng)
	local allPools = Packs.GetPools()
	local pulls = {}
	for _, slot in ipairs(EconomyConfig.PackSlots) do
		for _ = 1, slot.Count do
			local roll = rng(ROLL_SCALE) -- 1..10000
			local cumulative = 0
			local chosen = slot.Outcomes[#slot.Outcomes]
			for _, outcome in ipairs(slot.Outcomes) do
				cumulative = cumulative + math.floor(outcome.Chance * ROLL_SCALE / 100 + 0.5)
				if roll <= cumulative then
					chosen = outcome
					break
				end
			end
			local pool = allPools[chosen.Pool]
			local cardId = pool[rng(#pool)]
			table.insert(pulls, {
				CardId = cardId,
				Finish = Packs.FinishFor(cardId, chosen.Pool),
				Pool = chosen.Pool,
				Slot = slot.Name,
			})
		end
	end
	-- Reveal order: best card last (stable for equal ranks)
	for i, pull in ipairs(pulls) do
		pull.Order = i
	end
	table.sort(pulls, function(a, b)
		local ra, rb = POOL_RANK[a.Pool], POOL_RANK[b.Pool]
		if ra ~= rb then
			return ra < rb
		end
		return a.Order < b.Order
	end)
	for _, pull in ipairs(pulls) do
		pull.Order = nil
	end
	return pulls
end

---------------------------------------------------------------------
-- Rounds a list of percentages to `decimals` places so the rounded values
-- still add up to exactly `total` (largest remainder method). Displayed odds
-- must add to 100%, and plain rounding can drift (15 x 6.667% = 100.05%).
---------------------------------------------------------------------
function Packs.RoundToTotal(values, total, decimals)
	local scale = 10 ^ decimals
	local target = math.floor(total * scale + 0.5)
	local floors, remainders, sum = {}, {}, 0
	for i, v in ipairs(values) do
		local scaled = v * scale
		floors[i] = math.floor(scaled + 1e-9)
		remainders[i] = { Index = i, Rest = scaled - floors[i] }
		sum = sum + floors[i]
	end
	table.sort(remainders, function(a, b)
		if math.abs(a.Rest - b.Rest) > 1e-12 then
			return a.Rest > b.Rest
		end
		return a.Index < b.Index
	end)
	for k = 1, target - sum do
		local i = remainders[k].Index
		floors[i] = floors[i] + 1
	end
	local out = {}
	for i, f in ipairs(floors) do
		out[i] = f / scale
	end
	return out
end

local DISPLAY_DECIMALS = 3

local function shown(value)
	return ("%." .. DISPLAY_DECIMALS .. "f%%"):format(value)
end

---------------------------------------------------------------------
-- Odds for display
-- Returns {
--   Slots = { { Name, Count, Outcomes = { { Pool, Label, Chance, Cards = { { CardId, Chance } } } } } },
--   Tokens = "...",
-- }
-- Chance values are percentages for ONE card in that slot.
---------------------------------------------------------------------
function Packs.GetOddsTable()
	local allPools = Packs.GetPools()
	local result = { Slots = {} }
	for _, slot in ipairs(EconomyConfig.PackSlots) do
		local slotInfo = { Name = slot.Name, Count = slot.Count, Outcomes = {} }
		for _, outcome in ipairs(slot.Outcomes) do
			local pool = allPools[outcome.Pool]
			local exact = {}
			for i = 1, #pool do
				exact[i] = outcome.Chance / #pool
			end
			local rounded = Packs.RoundToTotal(exact, outcome.Chance, DISPLAY_DECIMALS)
			local cards = {}
			for i, cardId in ipairs(pool) do
				-- Chance is exact; Shown is the rounded text (adds up to exactly 100%)
				table.insert(cards, { CardId = cardId, Chance = exact[i], Shown = shown(rounded[i]) })
			end
			table.insert(slotInfo.Outcomes, {
				Pool = outcome.Pool,
				Label = EconomyConfig.PoolNames[outcome.Pool] or outcome.Pool,
				Chance = outcome.Chance,
				Shown = shown(outcome.Chance),
				Finish = outcome.Pool == "Mythic" and "Mythic" or nil,
				Cards = cards,
			})
		end
		table.insert(result.Slots, slotInfo)
	end
	result.PityText = ("Every pack gives %d Star Token. Trade %d Star Tokens for any Commander or Celestial of your choice.")
		:format(EconomyConfig.TokensPerPack, EconomyConfig.TokenExchangeCost)
	return result
end

-- Chance (0-100) that ONE pack contains at least one card from a pool
function Packs.ChancePerPack(poolName)
	local missAll = 1
	for _, slot in ipairs(EconomyConfig.PackSlots) do
		for _, outcome in ipairs(slot.Outcomes) do
			if outcome.Pool == poolName then
				missAll = missAll * (1 - outcome.Chance / 100) ^ slot.Count
			end
		end
	end
	return (1 - missAll) * 100
end

return Packs