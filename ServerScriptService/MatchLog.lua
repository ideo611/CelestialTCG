--[[
	MatchLog (ModuleScript)
	Location: ServerScriptService > MatchLog

	Saves one small record for every game played, so cards can be balanced
	against real matches. Records are collected in memory and saved in
	batches to the "MatchLog" data store (a batch every couple of minutes,
	or sooner when enough games pile up, plus a final save when the server
	shuts down).

	Each batch is saved under its own key:  m_YYYYMMDD_<server>_<batch #>
	so a whole day can be downloaded with the export script by asking for
	keys that start with "m_YYYYMMDD".

	Before each update that changes cards, bump CardDatabase.BalanceVersion.
	Every record also stores a fingerprint of all card stats and rules, so
	games from different card versions are never mixed up even if you forget.

	Players are stored as a scrambled ID (not their real UserId), plus how
	many games they had played before this one, as a rough experience level.

	In Studio, records are built and checked but not saved, so test games
	don't end up in the real data (set MatchLog.SaveInStudio = true to test
	saving).
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))

local MatchLog = {}

MatchLog.StoreName = "MatchLog"
MatchLog.Schema = 1               -- the record layout; bump if fields change meaning
MatchLog.FlushEvery = 120         -- seconds between saves
MatchLog.BatchSize = 40           -- save early once this many games are waiting
MatchLog.MaxBuffered = 1000       -- if saving keeps failing, oldest games are dropped past this
MatchLog.SaveInStudio = false
MatchLog.IdSalt = "celestial-log-1" -- scrambles player IDs; don't change it once live

local buffer = {}
local batchNumber = 0
local store
local saving = false

---------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------

-- A 32-bit string hash (djb2). Two different seeds give 64 bits.
local function hash32(text, seed)
	local h = seed
	for i = 1, #text do
		h = (h * 33 + string.byte(text, i)) % 4294967296
	end
	return h
end

-- Hashes three times, feeding each result into the front of the next, so a
-- one-letter change (UserId 41 vs 42) scrambles the whole output
local function hashHex(text)
	local a = hash32(text, 5381)
	local b = hash32(tostring(a) .. ":" .. text, 52711)
	local c = hash32(tostring(b) .. ":" .. text .. ":" .. tostring(a), 7919)
	return string.format("%08x%08x", b, c)
end

-- Turns any data into the same text every time (table keys sorted), so
-- the fingerprint only changes when the cards or rules actually change
local function stableText(value, out)
	local kind = type(value)
	if kind == "table" then
		local keys = {}
		for key in pairs(value) do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		table.insert(out, "{")
		for _, key in ipairs(keys) do
			table.insert(out, tostring(key))
			table.insert(out, "=")
			stableText(value[key], out)
			table.insert(out, ";")
		end
		table.insert(out, "}")
	elseif kind ~= "function" then
		table.insert(out, tostring(value))
	end
	return out
end

local fingerprint
function MatchLog.Fingerprint()
	if not fingerprint then
		local cards = {}
		for _, card in ipairs(CardDatabase.GetAllCards()) do
			cards[card.Id] = card
		end
		fingerprint = hashHex(table.concat(stableText({ Cards = cards, Rules = CardDatabase.Rules }, {})))
	end
	return fingerprint
end

local serverId
local function getServerId()
	if not serverId then
		local jobId = game.JobId
		if type(jobId) == "string" and #jobId >= 12 then
			serverId = jobId:gsub("-", ""):sub(1, 12):lower()
		else
			serverId = string.format("%06x%06x", math.random(0, 0xFFFFFF), math.random(0, 0xFFFFFF))
		end
	end
	return serverId
end

-- A deck as "CARD-ID:count" pairs, sorted, e.g. "LUN-001:2,LUN-004:1"
local function deckText(cards)
	local counts, ids = {}, {}
	for _, id in ipairs(cards) do
		if not counts[id] then
			table.insert(ids, id)
		end
		counts[id] = (counts[id] or 0) + 1
	end
	table.sort(ids)
	local parts = {}
	for _, id in ipairs(ids) do
		table.insert(parts, id .. ":" .. counts[id])
	end
	return table.concat(parts, ",")
end

local function copyList(list)
	local out = {}
	for i, v in ipairs(list) do
		out[i] = v
	end
	return out
end

---------------------------------------------------------------------
-- Building a record
---------------------------------------------------------------------

--[[ info = {
	Battle    = the finished battle
	Decks     = { [1], [2] } the decks as played ({ Commander, Celestial, Cards })
	Players   = { [1], [2] } a Player, or nil for the bot
	Experience= { [1], [2] } games each player had played before this one
	Mode      = "Bot" or "PvP"
	BestOf    = 1, 3 or 5;  Game = which game of the series
	Left      = seat that left the table (if the game ended that way)
	Table     = table number
} ]]
function MatchLog.BuildRecord(info)
	local battle = info.Battle
	local stats = battle.Stats or {}
	local reason = "KO"
	if info.Left then
		reason = "Left"
	elseif stats.Reason == "Concede" then
		reason = "Concede"
	elseif stats.StormKill then
		reason = "Storm"
	end

	local seats = {}
	for seat = 1, 2 do
		local deck = info.Decks[seat]
		local player = info.Players[seat]
		local seatStats = stats[seat] or {}
		local state = battle.Players[seat]
		local played = {}
		for i, entry in ipairs(seatStats.Played or {}) do
			played[i] = { entry[1], entry[2] }
		end
		seats[seat] = {
			Who = player and hashHex(MatchLog.IdSalt .. ":" .. tostring(player.UserId)) or "bot",
			Exp = player and info.Experience and info.Experience[seat] or nil,
			Commander = deck.Commander,
			Celestial = deck.Celestial,
			Deck = deckText(deck.Cards),
			HP = state and state.HP or 0,
			Opening = copyList(seatStats.Opening or {}),
			Drawn = copyList(seatStats.Drawn or {}),
			Played = played,
			Abilities = seatStats.Abilities or 0,
			Summons = seatStats.Summons or 0,
			Storm = seatStats.StormDamage or 0,
			Spark = seatStats.SparkUsed or false,
		}
	end

	return {
		Schema = MatchLog.Schema,
		Version = CardDatabase.BalanceVersion or "unset",
		Fingerprint = MatchLog.Fingerprint(),
		Time = os.time(),
		Server = getServerId(),
		Studio = RunService:IsStudio() or nil,
		Table = info.Table,
		Mode = info.Mode,
		BestOf = info.BestOf or 1,
		Game = info.Game or 1,
		First = stats.FirstPlayer,
		Winner = battle.Winner,
		Reason = reason,
		Left = info.Left,
		Turns = battle.Turn,
		Rounds = math.ceil(battle.Turn / 2),
		Seats = seats,
	}
end

---------------------------------------------------------------------
-- Saving
---------------------------------------------------------------------

local function getStore()
	if not store then
		local ok, result = pcall(function()
			return DataStoreService:GetDataStore(MatchLog.StoreName)
		end)
		if ok then
			store = result
		end
	end
	return store
end

local function canSave()
	return MatchLog.SaveInStudio or not RunService:IsStudio()
end

-- Saves everything waiting. Returns how many games were saved.
function MatchLog.Flush()
	if saving or #buffer == 0 then
		return 0
	end
	if not canSave() then
		buffer = {}
		return 0
	end
	local ds = getStore()
	if not ds then
		return 0
	end
	saving = true
	local saved = 0
	while #buffer > 0 do
		local count = math.min(#buffer, MatchLog.BatchSize * 2)
		local batch = {}
		for i = 1, count do
			batch[i] = buffer[i]
		end
		batchNumber = batchNumber + 1
		local now = os.date("!*t")
		local day = string.format("%04d%02d%02d", now.year, now.month, now.day)
		local key = string.format("m_%s_%s_%04d", day, getServerId(), batchNumber)
		local ok, err = pcall(function()
			ds:SetAsync(key, { Schema = MatchLog.Schema, Records = batch })
		end)
		if not ok then
			batchNumber = batchNumber - 1
			warn("MatchLog: couldn't save " .. count .. " games, will retry: " .. tostring(err))
			break
		end
		for _ = 1, count do
			table.remove(buffer, 1)
		end
		saved = saved + count
	end
	saving = false
	return saved
end

-- Adds a finished game. Never errors: a logging problem must not break a match.
function MatchLog.Record(info)
	local ok, recordOrError = pcall(MatchLog.BuildRecord, info)
	if not ok then
		warn("MatchLog: couldn't build a record: " .. tostring(recordOrError))
		return nil
	end
	table.insert(buffer, recordOrError)
	while #buffer > MatchLog.MaxBuffered do
		table.remove(buffer, 1)
	end
	if #buffer >= MatchLog.BatchSize then
		task.spawn(MatchLog.Flush)
	end
	return recordOrError
end

function MatchLog.Pending()
	return #buffer
end

-- Background saving: every FlushEvery seconds, and when the server closes
local started = false
function MatchLog.Start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			task.wait(MatchLog.FlushEvery)
			MatchLog.Flush()
		end
	end)
	game:BindToClose(function()
		-- let a save that's already running finish, then save the rest
		local waited = 0
		while saving and waited < 15 do
			task.wait(0.5)
			waited = waited + 0.5
		end
		MatchLog.Flush()
	end)
end

return MatchLog
