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
local CardArt = require(ReplicatedStorage:WaitForChild("CardArt"))

local Packs = {}

---------------------------------------------------------------------
-- Pools
---------------------------------------------------------------------
local poolsByType = {}

local function isDeckCard(card)
	return CardDatabase.IsMainDeckType(card.Type)
end

-- Does a card belong in this booster? (nil faction = the all-faction booster)
local function belongs(card, faction)
	if not faction or card.Faction == "Neutral" then
		return true
	end
	if card.Type == "Celestial" and card.PairsWith then
		for _, f in ipairs(card.PairsWith) do
			if f == faction then
				return true
			end
		end
		return false
	end
	return card.Faction == faction
end

-- The card pools of a booster type (default: the all-faction booster)
function Packs.GetPools(packTypeId)
	local packType = EconomyConfig.GetPackType(packTypeId or EconomyConfig.DefaultPackType)
	assert(packType, "Unknown booster " .. tostring(packTypeId))
	if poolsByType[packType.Id] then
		return poolsByType[packType.Id]
	end
	local pools = {
		Common = {},
		Rare = {},
		Epic = {},
		LegendaryDeckCard = {},
		CommanderOrCelestial = {},
		Mythic = {},
	}
	for _, card in ipairs(CardDatabase.GetAllCards()) do
		local switchedOff = card.Type == "Anomaly" and CardDatabase.Rules.AnomaliesEnabled == false
		if card.InPacks ~= false and not switchedOff and belongs(card, packType.Faction) then
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
			assert(#pools[outcome.Pool] > 0, packType.Name .. ": pool " .. outcome.Pool .. " has no cards")
			total = total + outcome.Chance
		end
		assert(math.abs(total - 100) < 1e-9, slot.Name .. " chances add to " .. total .. ", not 100")
		if slot.Finishes then
			local finishTotal = 0
			for _, f in ipairs(slot.Finishes) do
				finishTotal = finishTotal + f.Chance
			end
			assert(math.abs(finishTotal - 100) < 1e-9, slot.Name .. " finish chances add to " .. finishTotal .. ", not 100")
		end
	end
	poolsByType[packType.Id] = pools
	return pools
end

---------------------------------------------------------------------
-- Pack fronts: each pack on the shelf shows one card's art from its
-- booster. Purely a look; it has nothing to do with what's inside.
---------------------------------------------------------------------
local frontsByType = {}

-- Every card that can be on the front of this booster (cards with art first;
-- if no card has art yet, any card from the booster)
function Packs.FrontCards(packTypeId)
	local key = packTypeId or EconomyConfig.DefaultPackType
	if frontsByType[key] then
		return frontsByType[key]
	end
	local pools = Packs.GetPools(key)
	local withArt, all = {}, {}
	for _, cardId in ipairs(pools.Mythic) do -- the Mythic pool holds every card in the booster
		table.insert(all, cardId)
		if CardArt.ArtFor(cardId) then
			table.insert(withArt, cardId)
		end
	end
	table.sort(withArt)
	table.sort(all)
	frontsByType[key] = #withArt > 0 and withArt or all
	return frontsByType[key]
end

-- count different fronts, picked at random. rng(n) returns 1..n.
function Packs.PickFronts(packTypeId, rng, count)
	local choices = {}
	for i, cardId in ipairs(Packs.FrontCards(packTypeId)) do
		choices[i] = cardId
	end
	local picked = {}
	for i = 1, count do
		if #choices == 0 then
			-- fewer cards with art than packs: reuse fronts
			picked[i] = picked[rng(i - 1)]
		else
			picked[i] = table.remove(choices, rng(#choices))
		end
	end
	return picked
end

-- A pack card's finish: rolled from the slot's Finishes list.
-- roll is a number from 1 to ROLL_SCALE.
local function pickChance(list, roll, scale)
	local cumulative = 0
	for _, entry in ipairs(list) do
		cumulative = cumulative + math.floor(entry.Chance * scale / 100 + 0.5)
		if roll <= cumulative then
			return entry
		end
	end
	return list[#list]
end

---------------------------------------------------------------------
-- Rolling
-- rng(n) must return a whole number from 1 to n. packTypeId picks the
-- booster (nil = the all-faction booster).
-- Returns a list of pulls: { CardId, Finish, Pool, Slot }, best card last.
---------------------------------------------------------------------
local ROLL_SCALE = 10000 -- chances are rolled in hundredths of a percent

local POOL_RANK = { Common = 1, Rare = 2, Epic = 3, LegendaryDeckCard = 4, CommanderOrCelestial = 5 }
local FINISH_RANK = { Base = 1, Holo = 2, Textured = 3, ["3D"] = 4, Mythic = 5 }
Packs.FinishRank = FINISH_RANK

-- Pools that never give a duplicate while the player is missing one of them
Packs.NoDuplicatePools = { LegendaryDeckCard = true }

-- owns(cardId) -> true if the player already has that card (optional)
function Packs.Roll(rng, packTypeId, owns)
	local allPools = Packs.GetPools(packTypeId)
	local pulls = {}
	for _, slot in ipairs(EconomyConfig.PackSlots) do
		for _ = 1, slot.Count do
			-- 1. rarity
			local chosen = pickChance(slot.Outcomes, rng(ROLL_SCALE), ROLL_SCALE)
			local pool = allPools[chosen.Pool]
			if owns and Packs.NoDuplicatePools[chosen.Pool] then
				-- duplicate protection: only cards they're missing, until they have them all
				local missing = {}
				for _, id in ipairs(pool) do
					if not owns(id) then
						table.insert(missing, id)
					end
				end
				if #missing > 0 then
					pool = missing
				end
			end
			local cardId = pool[rng(#pool)]
			-- 2. finish
			local finish = slot.Finishes and pickChance(slot.Finishes, rng(ROLL_SCALE), ROLL_SCALE).Finish or "Base"
			table.insert(pulls, {
				CardId = cardId,
				Finish = finish,
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
		local fa, fb = FINISH_RANK[a.Finish] or 1, FINISH_RANK[b.Finish] or 1
		if fa ~= fb then
			return fa < fb
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
function Packs.GetOddsTable(packTypeId)
	local allPools = Packs.GetPools(packTypeId)
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
				Cards = cards,
			})
		end
		slotInfo.Finishes = {}
		for _, f in ipairs(slot.Finishes or {}) do
			table.insert(slotInfo.Finishes, { Finish = f.Finish, Chance = f.Chance, Shown = shown(f.Chance) })
		end
		table.insert(result.Slots, slotInfo)
	end
	local packType = EconomyConfig.GetPackType(packTypeId or EconomyConfig.DefaultPackType)
	result.PackType = packType.Id
	result.PackName = packType.Name
	result.PityText = ("Every pack gives %d Star Token. Trade %d Star Tokens for any Commander or Celestial of your choice.")
		:format(EconomyConfig.TokensPerPack, EconomyConfig.TokenExchangeCost)
	return result
end

-- Chance (0-100) that ONE pack contains at least one card from a pool
-- (or, for "Mythic", at least one Mythic finish)
function Packs.ChancePerPack(poolName)
	local missAll = 1
	for _, slot in ipairs(EconomyConfig.PackSlots) do
		local list = poolName == "Mythic" and (slot.Finishes or {}) or slot.Outcomes
		for _, entry in ipairs(list) do
			if entry.Pool == poolName or entry.Finish == poolName then
				missAll = missAll * (1 - entry.Chance / 100) ^ slot.Count
			end
		end
	end
	return (1 - missAll) * 100
end

return Packs