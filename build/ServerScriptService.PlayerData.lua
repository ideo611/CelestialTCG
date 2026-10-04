--[[
	PlayerData (ModuleScript)
	Location: ServerScriptService > PlayerData

	Loads, changes and saves each player's collection and currencies.
	Every change to a player's cards or money goes through here, on the server.

	Saving needs the place published with "Studio Access to API Services"
	turned on. Without it, in Studio, players get temporary data that isn't
	saved (you'll see a warning in Output), so you can still test.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local Packs = require(ReplicatedStorage:WaitForChild("Packs"))
local Playmats = require(ReplicatedStorage:WaitForChild("Playmats"))

local STORE_NAME = "PlayerData_v1"
local LOAD_RETRIES = 3
local DATA_VERSION = 1
-- Bump when starter deck lists change: players who own a starter get any
-- cards the new list has that they're missing.
local STARTER_VERSION = 4 -- 3: Nebula starter gets Petal Ward; 4: star-rating pass

local PlayerData = {}
PlayerData.Changed = nil -- set by PlayerDataServer: function(player) called after any change
PlayerData.PackOpened = nil -- set by ShopServer: function(player, pulls) called after a pack opens
PlayerData.IsRestricted = nil -- set by ShopServer: function(player) -> true if paid random items are restricted
PlayerData.Clock = os.time -- replaceable for testing

local profiles = {} -- [player] = { Data = {...}, Temporary = bool }
local store = nil
local random = Random and Random.new() or nil

local function rng(n)
	if random then
		return random:NextInteger(1, n)
	end
	return math.random(1, n)
end

---------------------------------------------------------------------
-- Data shape
---------------------------------------------------------------------
local function defaultData()
	return {
		Version = DATA_VERSION,
		Coins = EconomyConfig.StartingCoins,
		StarShards = 0,
		StarTokens = 0,
		Collection = {},        -- [cardId] = { [finish] = count }
		OwnedStarters = {},     -- [deckName] = true
		DailyCoinsEarned = 0,
		DailyDay = 0,           -- which UTC day DailyCoinsEarned belongs to
		PacksOpened = 0,
		Stats = { Wins = 0, Losses = 0 },
		Decks = {},             -- list of { Id, Name, Commander, Celestial, Cards = { cardId, ... },
		                        --           Finishes = { [cardId] = finish to show } }
		NextDeckId = 1,
		OwnedMats = {},         -- [matId] = true
		EquippedMat = "",       -- "" = the default mat
		StarterVersion = 0,     -- which starter lists this save has been topped up to
		SinglesDay = 0,         -- the UTC day SinglesBought belongs to
		SinglesBought = {},     -- [cardId] = true: singles bought that day (one of each per day)
		BinderShowcase = {},    -- the binder's front page: list of { CardId, Finish } (up to 9)
		BinderCover = "",       -- binder cover color: a faction name ("" = default)
		Settings = {            -- battle screen settings, kept between visits
			AnimSpeed = 1,      -- 1 Normal, 2 Fast, 0 Off
			Sound = true,
			OpponentSpeed = "Normal", -- how fast the other side's plays are shown: Slow / Normal / Fast
		},
	}
end

local addCopies -- defined below

-- Starter lists changed: top up owned starters so every card in the new list
-- is in the collection. Extra copies from the old lists are kept.
local function topUpStarters(data)
	if (data.StarterVersion or 0) >= STARTER_VERSION then
		return
	end
	for deckName in pairs(data.OwnedStarters) do
		local starter = CardDatabase.StarterDecks[deckName]
		if starter then
			for cardId, count in pairs(starter.Cards) do
				local owned = PlayerData.CountOwned(data, cardId)
				if owned < count then
					addCopies(data, cardId, EconomyConfig.StarterFinish, count - owned)
				end
			end
		end
	end
	data.StarterVersion = STARTER_VERSION
end

-- Playtest coins: once per player, raise their coins to EconomyConfig.PlaytestCoins
local function grantPlaytestCoins(data)
	local amount = EconomyConfig.PlaytestCoins or 0
	if amount > 0 and not data.PlaytestCoinsGiven then
		data.Coins = math.max(data.Coins, amount)
		data.PlaytestCoinsGiven = true
	end
end

-- Starter mats for starter decks owned before mats existed
local function grantMissingStarterMats(data)
	for deckName in pairs(data.OwnedStarters) do
		local mat = Playmats.ForStarter(deckName)
		if mat and not data.OwnedMats[mat.Id] then
			data.OwnedMats[mat.Id] = true
			if data.EquippedMat == "" then
				data.EquippedMat = mat.Id
			end
		end
	end
end

-- Fills in anything missing from older saves
local function reconcile(data, template)
	for key, value in pairs(template) do
		if data[key] == nil then
			if type(value) == "table" then
				local copy = {}
				reconcile(copy, value)
				data[key] = copy
			else
				data[key] = value
			end
		elseif type(value) == "table" and type(data[key]) == "table" then
			reconcile(data[key], value)
		end
	end
	return data
end

local function today()
	return math.floor(PlayerData.Clock() / 86400)
end

local function rollDay(data)
	local day = today()
	if data.DailyDay ~= day then
		data.DailyDay = day
		data.DailyCoinsEarned = 0
	end
end

---------------------------------------------------------------------
-- Loading and saving
---------------------------------------------------------------------
local function getStore()
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	end
	return store
end

local function keyFor(player)
	return "u_" .. tostring(player.UserId)
end

-- Returns true if loaded. On failure outside Studio the player is kicked,
-- because giving them blank data could overwrite their real save.
function PlayerData.Load(player)
	local data, loaded = nil, false
	local ds = getStore()
	if ds then
		for attempt = 1, LOAD_RETRIES do
			local ok, result = pcall(function()
				return ds:GetAsync(keyFor(player))
			end)
			if ok then
				data = result
				loaded = true
				break
			end
			warn(("PlayerData: load attempt %d for %s failed: %s"):format(attempt, player.Name, tostring(result)))
			if attempt < LOAD_RETRIES then
				task.wait(2)
			end
		end
	end

	if not loaded then
		if RunService:IsStudio() then
			warn("PlayerData: saving isn't available (publish the place and turn on Studio Access to API Services). "
				.. player.Name .. " gets temporary data that won't be saved.")
			local temp = defaultData()
			grantPlaytestCoins(temp)
			profiles[player] = { Data = temp, Temporary = true }
			PlayerData.ApplySettings(player)
			player:SetAttribute("DataLoaded", true) -- lifts the loading screen
			return true
		end
		player:Kick("We couldn't load your cards. Please rejoin in a moment.")
		return false
	end

	if type(data) ~= "table" then
		data = defaultData()
	else
		reconcile(data, defaultData())
	end
	grantMissingStarterMats(data)
	topUpStarters(data)
	grantPlaytestCoins(data)
	profiles[player] = { Data = data, Temporary = false }
	PlayerData.ApplySettings(player)
	player:SetAttribute("DataLoaded", true) -- lifts the loading screen
	return true
end

function PlayerData.Save(player)
	local profile = profiles[player]
	if not profile or profile.Temporary then
		return true
	end
	local ds = getStore()
	if not ds then
		return false
	end
	local ok, err = pcall(function()
		ds:UpdateAsync(keyFor(player), function()
			return profile.Data
		end)
	end)
	if not ok then
		warn(("PlayerData: save for %s failed: %s"):format(player.Name, tostring(err)))
	end
	return ok
end

function PlayerData.Release(player)
	PlayerData.Save(player)
	profiles[player] = nil
end

-- Battle settings: shown to the player's scripts as attributes
local OPPONENT_SPEEDS = { Slow = true, Normal = true, Fast = true }
local ANIM_SPEEDS = { [0] = true, [1] = true, [2] = true }

function PlayerData.ApplySettings(player)
	local profile = profiles[player]
	local settings = profile and profile.Data.Settings
	if not settings then
		return
	end
	player:SetAttribute("BattleAnimSpeed", settings.AnimSpeed)
	player:SetAttribute("BattleSound", settings.Sound)
	player:SetAttribute("BattleOpponentSpeed", settings.OpponentSpeed)
end

function PlayerData.SaveSettings(player, args)
	local profile = profiles[player]
	if not profile then
		return false, "Not loaded."
	end
	local settings = profile.Data.Settings
	if ANIM_SPEEDS[args.AnimSpeed] then
		settings.AnimSpeed = args.AnimSpeed
	end
	if type(args.Sound) == "boolean" then
		settings.Sound = args.Sound
	end
	if OPPONENT_SPEEDS[args.OpponentSpeed] then
		settings.OpponentSpeed = args.OpponentSpeed
	end
	return true, settings
end

function PlayerData.IsLoaded(player)
	return profiles[player] ~= nil
end

function PlayerData.IsTemporary(player)
	return profiles[player] ~= nil and profiles[player].Temporary
end

-- Read-only use only; change data through the functions below
function PlayerData.Get(player)
	local profile = profiles[player]
	return profile and profile.Data
end

local function changed(player)
	if PlayerData.Changed then
		PlayerData.Changed(player)
	end
end

---------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------
function addCopies(data, cardId, finish, count)
	local entry = data.Collection[cardId]
	if not entry then
		entry = {}
		data.Collection[cardId] = entry
	end
	entry[finish] = (entry[finish] or 0) + count
end

function PlayerData.CountOwned(data, cardId)
	local total = 0
	for _, count in pairs(data.Collection[cardId] or {}) do
		total = total + count
	end
	return total
end

-- A player's first starter deck is free; after that they cost coins.
function PlayerData.StarterPrice(data)
	for _ in pairs(data.OwnedStarters) do
		return EconomyConfig.StarterDeckPriceCoins
	end
	return 0
end

function PlayerData.ClaimStarter(player, deckName)
	local data = PlayerData.Get(player)
	if not data or type(deckName) ~= "string" or not CardDatabase.StarterDecks[deckName] then
		return false, "Unknown starter deck."
	end
	if data.OwnedStarters[deckName] then
		return false, "You already own that starter deck."
	end
	local price = PlayerData.StarterPrice(data)
	if data.Coins < price then
		return false, ("You need %d coins."):format(price)
	end
	data.Coins = data.Coins - price
	local ok, message = PlayerData.GrantStarter(player, deckName)
	if not ok then
		data.Coins = data.Coins + price
		return false, message
	end
	PlayerData.Save(player)
	return true, price
end

-- Gives a starter deck's cards (plain finish). Returns ok, message.
function PlayerData.GrantStarter(player, deckName)
	local data = PlayerData.Get(player)
	local starter = CardDatabase.StarterDecks[deckName]
	if not data or not starter then
		return false, "Unknown starter deck."
	end
	if data.OwnedStarters[deckName] then
		return false, "You already own that starter deck."
	end
	data.OwnedStarters[deckName] = true
	local finish = EconomyConfig.StarterFinish
	addCopies(data, starter.Commander, finish, 1)
	addCopies(data, starter.Celestial, finish, 1)
	for cardId, count in pairs(starter.Cards) do
		addCopies(data, cardId, finish, count)
	end
	grantMissingStarterMats(data) -- the deck's playmat comes with it
	changed(player)
	return true
end

---------------------------------------------------------------------
-- Coins
---------------------------------------------------------------------
function PlayerData.DailyCap()
	return EconomyConfig.DailyCoinCap * EconomyConfig.CoinCapMultiplier
end

-- Coins earned from playing count toward the daily cap. Returns coins actually given.
function PlayerData.AddEarnedCoins(player, amount)
	local data = PlayerData.Get(player)
	if not data or amount <= 0 then
		return 0
	end
	rollDay(data)
	local room = math.max(0, PlayerData.DailyCap() - data.DailyCoinsEarned)
	local given = math.min(amount, room)
	if given > 0 then
		data.Coins = data.Coins + given
		data.DailyCoinsEarned = data.DailyCoinsEarned + given
		changed(player)
	end
	return given
end

-- Coins from events, gifts or testing (don't count toward the daily cap)
function PlayerData.GrantCoins(player, amount)
	local data = PlayerData.Get(player)
	if not data or amount <= 0 then
		return 0
	end
	data.Coins = data.Coins + amount
	changed(player)
	return amount
end

-- Called when a match ends. Returns coins given.
function PlayerData.RecordMatch(player, won, vsBot, turns)
	local data = PlayerData.Get(player)
	if not data then
		return 0
	end
	local rewards = EconomyConfig.MatchRewards
	if won then
		data.Stats.Wins = data.Stats.Wins + 1
	else
		data.Stats.Losses = data.Stats.Losses + 1
	end
	if turns < rewards.MinTurns then
		changed(player)
		return 0
	end
	local amount
	if vsBot then
		amount = won and rewards.BotWin or rewards.BotLoss
	else
		amount = won and rewards.PvPWin or rewards.PvPLoss
	end
	local given = PlayerData.AddEarnedCoins(player, amount)
	changed(player)
	return given
end

---------------------------------------------------------------------
-- Packs
-- currency = "Coins" or "Shards". Returns ok, pulls-or-message.
---------------------------------------------------------------------
function PlayerData.OpenPack(player, currency, packTypeId)
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your cards haven't loaded yet."
	end
	packTypeId = packTypeId or EconomyConfig.DefaultPackType
	if not EconomyConfig.GetPackType(packTypeId) then
		return false, "Pick a pack."
	end
	if currency == "Coins" then
		if EconomyConfig.CoinsSoldForRobux and PlayerData.IsRestricted and PlayerData.IsRestricted(player) then
			return false, "Packs can't be bought with coins in your region. You can still open packs with Star Shards."
		end
		if data.Coins < EconomyConfig.PackPriceCoins then
			return false, ("You need %d coins."):format(EconomyConfig.PackPriceCoins)
		end
		data.Coins = data.Coins - EconomyConfig.PackPriceCoins
	elseif currency == "Shards" then
		if data.StarShards < EconomyConfig.PackPriceShards then
			return false, ("You need %d Star Shards."):format(EconomyConfig.PackPriceShards)
		end
		data.StarShards = data.StarShards - EconomyConfig.PackPriceShards
	else
		return false, "Pick how to pay."
	end

	local pulls = Packs.Roll(rng, packTypeId, function(cardId)
		return PlayerData.CountOwned(data, cardId) > 0
	end)
	for _, pull in ipairs(pulls) do
		pull.New = PlayerData.CountOwned(data, pull.CardId) == 0
		addCopies(data, pull.CardId, pull.Finish, 1)
	end
	data.StarTokens = data.StarTokens + EconomyConfig.TokensPerPack
	data.PacksOpened = data.PacksOpened + 1
	changed(player)
	PlayerData.Save(player) -- pack results are saved right away
	if PlayerData.PackOpened then
		task.spawn(PlayerData.PackOpened, player, pulls)
	end
	return true, pulls
end

---------------------------------------------------------------------
-- Breaking down extras into Star Shards
---------------------------------------------------------------------
local function keepFor(card)
	if card.Type == "Commander" or card.Type == "Celestial" then
		return EconomyConfig.KeepCopies.CommandersAndCelestials
	end
	if card.Rarity == "Legendary" then
		return EconomyConfig.KeepCopies.LegendaryDeckCards or 1
	end
	return EconomyConfig.KeepCopies.DeckCards
end

-- How many copies of each card/finish can be broken down, and for how many Shards
function PlayerData.GetExtras(player)
	local data = PlayerData.Get(player)
	local extras, totalShards = {}, 0
	if not data then
		return extras, 0
	end
	for cardId, finishes in pairs(data.Collection) do
		local card = CardDatabase.GetCard(cardId)
		if card then
			for finish, count in pairs(finishes) do
				local breakable = true
				if finish == "Mythic" and not EconomyConfig.MythicCanBreakDown then
					breakable = false
				end
				-- Starter decks give at most a playset of plain copies, which are always
				-- kept, so starter cards are never broken down.
				local extra = count - keepFor(card)
				if breakable and extra > 0 then
					local value = (EconomyConfig.ShardValues[card.Rarity] or 0) * extra
					table.insert(extras, { CardId = cardId, Finish = finish, Count = extra, Shards = value })
					totalShards = totalShards + value
				end
			end
		end
	end
	table.sort(extras, function(a, b)
		if a.CardId ~= b.CardId then
			return a.CardId < b.CardId
		end
		return a.Finish < b.Finish
	end)
	return extras, totalShards
end

-- Breaks down every extra copy at once. Returns ok, shardsGained-or-message.
function PlayerData.BreakDownExtras(player)
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your cards haven't loaded yet."
	end
	local extras, total = PlayerData.GetExtras(player)
	if #extras == 0 then
		return false, "You have no extra copies to break down."
	end
	for _, extra in ipairs(extras) do
		local entry = data.Collection[extra.CardId]
		entry[extra.Finish] = entry[extra.Finish] - extra.Count
		if entry[extra.Finish] <= 0 then
			entry[extra.Finish] = nil
		end
	end
	data.StarShards = data.StarShards + total
	changed(player)
	PlayerData.Save(player)
	return true, total
end

---------------------------------------------------------------------
-- Star Token exchange (pity)
---------------------------------------------------------------------
function PlayerData.ExchangeTokens(player, cardId)
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your cards haven't loaded yet."
	end
	local card = type(cardId) == "string" and CardDatabase.GetCard(cardId)
	if not card or (card.Type ~= "Commander" and card.Type ~= "Celestial") or card.InPacks == false then
		return false, "Pick a Commander or Celestial."
	end
	if data.StarTokens < EconomyConfig.TokenExchangeCost then
		return false, ("You need %d Star Tokens."):format(EconomyConfig.TokenExchangeCost)
	end
	data.StarTokens = data.StarTokens - EconomyConfig.TokenExchangeCost
	local finish = EconomyConfig.FinishForRarity[card.Rarity] or "Base"
	addCopies(data, cardId, finish, 1)
	changed(player)
	PlayerData.Save(player)
	return true, { CardId = cardId, Finish = finish }
end

---------------------------------------------------------------------
-- Singles case: today's cards for coins, one of each per player per day
---------------------------------------------------------------------
local function singlesToday(data)
	local Singles = require(ReplicatedStorage:WaitForChild("Singles"))
	local day = Singles.Today()
	if data.SinglesDay ~= day then
		data.SinglesDay = day
		data.SinglesBought = {}
	end
	return day, Singles
end

-- Which of today's singles this player already bought: { cardId, ... }
function PlayerData.SinglesBoughtToday(player)
	local data = PlayerData.Get(player)
	local list = {}
	if data then
		singlesToday(data)
		for cardId in pairs(data.SinglesBought) do
			table.insert(list, cardId)
		end
	end
	return list
end

function PlayerData.BuySingle(player, cardId)
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your cards haven't loaded yet."
	end
	local day, Singles = singlesToday(data)
	local entry = type(cardId) == "string" and Singles.FindInStock(day, cardId)
	if not entry then
		return false, "That card isn't in the case today."
	end
	if data.SinglesBought[cardId] then
		return false, "You already bought that one today. New cards arrive at midnight UTC."
	end
	if data.Coins < entry.Price then
		return false, ("You need %d coins."):format(entry.Price)
	end
	data.Coins = data.Coins - entry.Price
	data.SinglesBought[cardId] = true
	local isNew = PlayerData.CountOwned(data, cardId) == 0
	addCopies(data, cardId, entry.Finish, 1)
	changed(player)
	PlayerData.Save(player)
	return true, { CardId = cardId, Finish = entry.Finish, Price = entry.Price, New = isNew }
end

---------------------------------------------------------------------
-- Saved decks
---------------------------------------------------------------------
PlayerData.MaxDecks = 12
PlayerData.MaxDeckNameLength = 24

-- Can this deck be taken into a match right now? Returns legal, problems, totalStars.
function PlayerData.CheckDeck(data, deck)
	local problems = {}
	local legal, errors, stars = CardDatabase.ValidateDeck(deck.Commander, deck.Celestial, deck.Cards or {}, deck.Format)
	if not legal then
		for _, e in ipairs(errors) do
			table.insert(problems, e)
		end
	end
	local counts = {}
	for _, cardId in ipairs(deck.Cards or {}) do
		counts[cardId] = (counts[cardId] or 0) + 1
	end
	for cardId, count in pairs(counts) do
		local card = CardDatabase.GetCard(cardId)
		if card and PlayerData.CountOwned(data, cardId) < count then
			table.insert(problems, ("You only own %d %s."):format(PlayerData.CountOwned(data, cardId), card.Name))
		end
	end
	for _, id in ipairs({ deck.Commander, deck.Celestial }) do
		local card = id and CardDatabase.GetCard(id)
		if card and PlayerData.CountOwned(data, id) < 1 then
			table.insert(problems, "You don't own " .. card.Name .. ".")
		end
	end
	return #problems == 0, problems, stars or 0
end

local function findDeck(data, id)
	for i, deck in ipairs(data.Decks) do
		if deck.Id == id then
			return deck, i
		end
	end
	return nil
end

function PlayerData.GetDeck(player, id)
	local data = PlayerData.Get(player)
	return data and findDeck(data, id)
end

-- Finishes, best first ("Base" = the plain card)
PlayerData.FinishOrder = { "Mythic", "3D", "Textured", "Holo", "Base" }
local VALID_FINISH = { Mythic = true, ["3D"] = true, Textured = true, Holo = true, Base = true }

local function ownsFinish(data, cardId, finish)
	local entry = data.Collection[cardId]
	return entry ~= nil and (entry[finish] or 0) > 0
end

-- The finish each card in a deck shows in a match: the one picked in the deck
-- builder if you still own a copy in that finish, otherwise your best one.
-- deck = { Commander, Celestial, Cards, Finishes? }. Returns { [cardId] = finish }
-- ("Base" cards are left out).
function PlayerData.DeckFinishes(data, deck)
	local result = {}
	if not data then
		return result
	end
	local chosen = type(deck.Finishes) == "table" and deck.Finishes or {}
	local ids = { deck.Commander, deck.Celestial }
	for _, cardId in ipairs(deck.Cards or {}) do
		table.insert(ids, cardId)
	end
	for _, cardId in ipairs(ids) do
		if result[cardId] == nil then
			local pick = chosen[cardId]
			if not (pick and VALID_FINISH[pick] and ownsFinish(data, cardId, pick)) then
				pick = "Base"
				for _, finish in ipairs(PlayerData.FinishOrder) do
					if ownsFinish(data, cardId, finish) then
						pick = finish
						break
					end
				end
			end
			result[cardId] = pick
		end
	end
	for cardId, finish in pairs(result) do
		if finish == "Base" then
			result[cardId] = nil
		end
	end
	return result
end

-- Studio testing only (PlayerDataServer only allows it in Studio): one more
-- copy of every card in every finish
function PlayerData.DevGrantAllFinishes(player)
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your cards haven't loaded yet."
	end
	for _, card in ipairs(CardDatabase.GetAllCards()) do
		for _, finish in ipairs(PlayerData.FinishOrder) do
			addCopies(data, card.Id, finish, 1)
		end
	end
	changed(player)
	return true, "Added one copy of every card in every finish."
end

-- input = { Id = existing id or nil, Format ("Zenith" or "Open"), Commander, Celestial, Cards = { ids },
--           Finishes = { [cardId] = finish } (optional; only finishes you own are kept) }
-- name must already be filtered. Unfinished decks can be saved; CheckDeck says if they're playable.
function PlayerData.SaveDeck(player, input, name)
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your cards haven't loaded yet."
	end
	if type(input) ~= "table" or type(name) ~= "string" or name == "" then
		return false, "Give your deck a name."
	end
	local commander = type(input.Commander) == "string" and CardDatabase.GetCard(input.Commander)
	if not commander or commander.Type ~= "Commander" or PlayerData.CountOwned(data, input.Commander) < 1 then
		return false, "Pick a Commander you own."
	end
	local celestial = type(input.Celestial) == "string" and CardDatabase.GetCard(input.Celestial)
	if not celestial or celestial.Type ~= "Celestial" or PlayerData.CountOwned(data, input.Celestial) < 1 then
		return false, "Pick a Celestial you own."
	end
	if type(input.Cards) ~= "table" or #input.Cards > CardDatabase.Rules.DeckSize then
		return false, ("A deck holds at most %d cards."):format(CardDatabase.Rules.DeckSize)
	end
	local cards, counts = {}, {}
	for i, cardId in ipairs(input.Cards) do
		local card = type(cardId) == "string" and CardDatabase.GetCard(cardId)
		if not card or not CardDatabase.IsMainDeckType(card.Type) then
			return false, "That deck has a card that can't go in a deck."
		end
		counts[cardId] = (counts[cardId] or 0) + 1
		if counts[cardId] > PlayerData.CountOwned(data, cardId) then
			return false, ("You don't own enough copies of %s."):format(card.Name)
		end
		cards[i] = cardId
	end

	local deck = type(input.Id) == "string" and findDeck(data, input.Id)
	if not deck then
		if #data.Decks >= PlayerData.MaxDecks then
			return false, ("You can save up to %d decks. Delete one first."):format(PlayerData.MaxDecks)
		end
		deck = { Id = "d" .. data.NextDeckId }
		data.NextDeckId = data.NextDeckId + 1
		table.insert(data.Decks, deck)
	end
	-- Chosen finishes: only for cards in this deck, and only ones you own
	local finishes = {}
	if type(input.Finishes) == "table" then
		local inDeck = { [input.Commander] = true, [input.Celestial] = true }
		for _, cardId in ipairs(cards) do
			inDeck[cardId] = true
		end
		for cardId, finish in pairs(input.Finishes) do
			if type(cardId) == "string" and inDeck[cardId] and type(finish) == "string" and VALID_FINISH[finish]
				and ownsFinish(data, cardId, finish) then
				finishes[cardId] = finish
			end
		end
	end

	deck.Name = name:sub(1, PlayerData.MaxDeckNameLength)
	deck.Format = CardDatabase.FormatOf(input.Format)
	deck.Commander = input.Commander
	deck.Celestial = input.Celestial
	deck.Cards = cards
	deck.Finishes = finishes
	changed(player)
	PlayerData.Save(player)
	return true, deck.Id
end

function PlayerData.DeleteDeck(player, id)
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your cards haven't loaded yet."
	end
	local deck, index = findDeck(data, id)
	if not deck then
		return false, "That deck doesn't exist."
	end
	table.remove(data.Decks, index)
	changed(player)
	PlayerData.Save(player)
	return true
end

---------------------------------------------------------------------
-- Playmats
---------------------------------------------------------------------
function PlayerData.OwnsMat(data, matId)
	local mat = Playmats.Get(matId)
	return mat ~= nil and (mat.Default == true or data.OwnedMats[matId] == true)
end

-- The mat this player brings to the table
function PlayerData.GetEquippedMat(player)
	local data = PlayerData.Get(player)
	if data and data.EquippedMat ~= "" and PlayerData.OwnsMat(data, data.EquippedMat) then
		return data.EquippedMat
	end
	return Playmats.DefaultId
end

-- Returns ok, message
function PlayerData.BuyMat(player, matId)
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your cards haven't loaded yet."
	end
	local mat = type(matId) == "string" and Playmats.Get(matId)
	if not mat then
		return false, "Unknown playmat."
	end
	if PlayerData.OwnsMat(data, matId) then
		return false, "You already own that playmat."
	end
	if not mat.PriceCoins then
		if mat.StarterDeck then
			return false, ("That playmat comes with the %s starter deck."):format(mat.StarterDeck)
		end
		return false, "That playmat isn't for sale."
	end
	if data.Coins < mat.PriceCoins then
		return false, ("You need %d coins."):format(mat.PriceCoins)
	end
	data.Coins = data.Coins - mat.PriceCoins
	data.OwnedMats[matId] = true
	data.EquippedMat = matId -- put it straight on the table
	changed(player)
	PlayerData.Save(player)
	return true, mat.Name
end

function PlayerData.EquipMat(player, matId)
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your cards haven't loaded yet."
	end
	if type(matId) ~= "string" or not PlayerData.OwnsMat(data, matId) then
		return false, "You don't own that playmat."
	end
	data.EquippedMat = matId
	changed(player)
	return true, Playmats.Get(matId).Name
end

---------------------------------------------------------------------
-- Binder: the front page (showcase) and the cover
---------------------------------------------------------------------
PlayerData.ShowcaseSize = 9
PlayerData.BinderCovers = { "Solar", "Lunar", "Nebula", "Void", "Comet", "Black" }
local VALID_COVER = {}
for _, cover in ipairs(PlayerData.BinderCovers) do
	VALID_COVER[cover] = true
end

-- list = { { CardId, Finish }, ... }; cards you don't own (in that finish) are dropped
function PlayerData.SetShowcase(player, list)
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your cards haven't loaded yet."
	end
	if type(list) ~= "table" then
		return false, "Bad showcase."
	end
	local clean, seen = {}, {}
	for i = 1, math.min(#list, PlayerData.ShowcaseSize) do
		local entry = list[i]
		if type(entry) == "table" and type(entry.CardId) == "string" and type(entry.Finish) == "string"
			and VALID_FINISH[entry.Finish] and ownsFinish(data, entry.CardId, entry.Finish) then
			local key = entry.CardId .. "|" .. entry.Finish
			if not seen[key] then
				seen[key] = true
				table.insert(clean, { CardId = entry.CardId, Finish = entry.Finish })
			end
		end
	end
	data.BinderShowcase = clean
	changed(player)
	return true, clean
end

function PlayerData.SetBinderCover(player, cover)
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your cards haven't loaded yet."
	end
	if not VALID_COVER[cover] then
		return false, "Unknown cover."
	end
	data.BinderCover = cover
	changed(player)
	return true, cover
end

-- Showcase entries you still own (cards can be broken down after being showcased)
function PlayerData.GetShowcase(data)
	local list = {}
	for _, entry in ipairs(data.BinderShowcase or {}) do
		if ownsFinish(data, entry.CardId, entry.Finish) then
			table.insert(list, { CardId = entry.CardId, Finish = entry.Finish })
		end
	end
	return list
end

-- What someone looking through this player's binder gets
function PlayerData.BinderView(player)
	local data = PlayerData.Get(player)
	if not data then
		return nil
	end
	return {
		OwnerName = player.DisplayName,
		OwnerUserId = player.UserId,
		Collection = data.Collection,
		Showcase = PlayerData.GetShowcase(data),
		Cover = VALID_COVER[data.BinderCover] and data.BinderCover or "Black",
	}
end

---------------------------------------------------------------------
-- What the player's screen gets to see
---------------------------------------------------------------------
function PlayerData.GetDeckSummaries(data)
	local list = {}
	for _, deck in ipairs(data.Decks) do
		local legal, problems, stars = PlayerData.CheckDeck(data, deck)
		table.insert(list, {
			Id = deck.Id,
			Name = deck.Name,
			Format = CardDatabase.FormatOf(deck.Format),
			Commander = deck.Commander,
			Celestial = deck.Celestial,
			Cards = deck.Cards,
			Finishes = deck.Finishes or {},
			Legal = legal,
			Problem = problems[1],
			Stars = stars,
		})
	end
	return list
end

function PlayerData.GetSummary(player)
	local data = PlayerData.Get(player)
	if not data then
		return nil
	end
	rollDay(data)
	local _, shardsAvailable = PlayerData.GetExtras(player)
	return {
		Coins = data.Coins,
		StarShards = data.StarShards,
		StarTokens = data.StarTokens,
		DailyCoinsEarned = data.DailyCoinsEarned,
		DailyCoinCap = PlayerData.DailyCap(),
		PacksOpened = data.PacksOpened,
		Collection = data.Collection,
		OwnedStarters = data.OwnedStarters,
		ShardsFromExtras = shardsAvailable,
		Temporary = PlayerData.IsTemporary(player),
		Decks = PlayerData.GetDeckSummaries(data),
		StarterPrice = PlayerData.StarterPrice(data),
		MaxDecks = PlayerData.MaxDecks,
		OwnedMats = data.OwnedMats,
		EquippedMat = PlayerData.GetEquippedMat(player),
		BinderShowcase = PlayerData.GetShowcase(data),
		BinderCover = VALID_COVER[data.BinderCover] and data.BinderCover or "Black",
	}
end

return PlayerData
