--[[
	BattleTableServer (Script)
	Location: ServerScriptService > BattleTableServer

	Builds the 4 play tables inside the card shop and runs a match on each.
	Every table works on its own:
	  - Two seat pads: walk up and press "Sit down". When both are taken, the match starts.
	  - "Practice vs Bot" on the table top: play the bot by yourself.
	You can only sit at one table at a time.
	  - Matches can be best of 1, 3 or 5. Against the bot you pick; against a
	    player you both vote, and if you disagree the shorter series wins.
	    The loser of each game goes first in the next. Leaving forfeits the series.
	Every action a player sends is checked by the BattleEngine, so the
	client can only ask; the server decides.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local Playmats = require(ReplicatedStorage:WaitForChild("Playmats"))
local BattleEngine = require(ServerScriptService:WaitForChild("BattleEngine"))
local BattleBot = require(ServerScriptService:WaitForChild("BattleBot"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local Building = require(ServerScriptService:WaitForChild("CardShopBuilding"))
local MatchLog = require(ServerScriptService:WaitForChild("MatchLog"))
local Spectate = require(ServerScriptService:WaitForChild("Spectate"))
local Analytics = require(ServerScriptService:WaitForChild("Analytics"))
local RateLimit = require(ServerScriptService:WaitForChild("RateLimit"))

local BOT = "BOT"
local BOT_ACTION_DELAY = 0.8 -- seconds between bot plays, so you can follow along
local MULLIGAN_SECONDS = 30  -- time to choose a starting hand before it's kept as is
local TABLE_WOOD = Color3.fromRGB(120, 80, 52)
local TABLE_WOOD_DARK = Color3.fromRGB(80, 52, 36)
local FELT = Color3.fromRGB(40, 110, 70)
local SEAT_COLOR = Color3.fromRGB(90, 70, 160)
local RESET_DELAY = 8        -- seconds the result stays up before the table resets
local NEXT_GAME_DELAY = 6    -- seconds between games in a series
local FORMATS = { [1] = true, [3] = true, [5] = true } -- best of 1, 3 or 5
-- Turn timer (player vs player only): a turn left this long ends by itself.
-- Timing out this many turns in a row forfeits the game.
local TURN_SECONDS = 60
local MAX_TIMEOUTS = 3

-- The tutorial match: Captain Sol Varro (you) against Tidekeeper Selene.
-- Cards are drawn in the order listed (opening hand first). Selene starts low
-- on HP and can't summon her Celestial; your Celestial is discounted so it
-- arrives on your 4th turn.
-- The tutorial's steps (GuideClient shows them; the server logs them in order)
local TUTORIAL_STEPS = { "intro", "play_unit", "end_turn", "their_turn", "lanes", "their_turn2", "ability", "spend",
	"their_turn3", "celestial", "finish" }

local TUTORIAL = {
	Decks = {
		{ Commander = "CMD-SOL-01", Celestial = "CEL-04", Format = "Open", Cards = {
			"SOL-003", "SOL-003", "SOL-018", "SOL-003",          -- opening hand
			"SOL-018", "SOL-003", "SOL-018", "SOL-007", "SOL-018", "SOL-003", "SOL-007", "SOL-018",
		} },
		{ Commander = "CMD-LUN-01", Celestial = "CEL-05", Format = "Open", Cards = {
			"LUN-004", "LUN-001", "LUN-004",                     -- opening hand
			"LUN-004", "LUN-001", "LUN-004", "LUN-001", "LUN-004", "LUN-001", "LUN-004",
		} },
	},
	Scripted = {
		{ StartingEnergy = 2, CelestialDiscount = 2, HandSize = 4 },
		{ HP = 12, CelestialDiscount = -20, HandSize = 3 },
	},
}

-- The finish each card in a player's deck shows: the one picked in the deck
-- builder (saved decks), otherwise the shiniest copy they own. { [cardId] = finish }
local function bestFinishes(player, deck)
	return PlayerData.DeckFinishes(PlayerData.Get(player), deck)
end

-- The opponent's finishes, but only for cards you can see right now
local function visibleFinishes(finishes, playerState)
	local shown = {}
	if not finishes then
		return shown
	end
	local function add(cardId)
		if cardId and finishes[cardId] then
			shown[cardId] = finishes[cardId]
		end
	end
	add(playerState.CommanderId)
	add(playerState.StarGate.CardId) -- nil until the Celestial is revealed
	-- (not ipairs: an empty lane would stop it before the lanes after it)
	for lane = 1, CardDatabase.Rules.Lanes do
		local unit = playerState.Lanes[lane]
		if unit then
			add(unit.CardId)
		end
	end
	return shown
end

---------------------------------------------------------------------
-- Remotes (how the players' screens talk to the server)
---------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "BattleRemotes"

local actionRemote = Instance.new("RemoteEvent")
actionRemote.Name = "BattleAction"
actionRemote.Parent = remotes

local updateRemote = Instance.new("RemoteEvent")
updateRemote.Name = "BattleUpdate"
updateRemote.Parent = remotes

remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------
-- The tables (each runs its own match)
---------------------------------------------------------------------
local tables = {}

-- Which table a player is sitting at (nil if none)
local function tableOf(player)
	for _, t in ipairs(tables) do
		if t.SeatOf(player) then
			return t
		end
	end
	return nil
end

-- options (optional): { Virtual = true } makes an off-table match (practice
-- or the tutorial) with no furniture, no TV and no table number, so it never
-- takes one of the shop's tables. Tutorial = true runs the tutorial match.
-- OnClosed() is called when a virtual match closes.
local function createTable(index, position, parent, options)
	options = options or {}
	local self = {}
	local virtual = options.Virtual == true
	local tutorial = options.Tutorial == true
	local PAD_POSITIONS, seatPrompts, practicePrompt, signLabel
	if virtual then
		PAD_POSITIONS = {}
		seatPrompts = { { Enabled = false }, { Enabled = false } }
		practicePrompt = { Enabled = false }
		signLabel = { Text = "" }
	else
	local model = Instance.new("Model")
	model.Name = "Table" .. index

	local function makePart(name, size, offset, color, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = CFrame.new(position + offset)
		part.Anchored = true
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Parent = model
		return part
	end

	-- A wooden game table with a green felt play area, and a rug spot for each seat
	local tableTop = makePart("Top", Vector3.new(10, 0.6, 6), Vector3.new(0, 3.2, 0), TABLE_WOOD, Enum.Material.Wood)
	makePart("Felt", Vector3.new(9, 0.08, 5), Vector3.new(0, 3.54, 0), FELT, Enum.Material.Fabric)
	makePart("Apron", Vector3.new(9.4, 0.6, 5.4), Vector3.new(0, 2.6, 0), TABLE_WOOD_DARK, Enum.Material.Wood)
	for _, offset in ipairs({
		Vector3.new(4.3, 1.2, 2.3), Vector3.new(-4.3, 1.2, 2.3),
		Vector3.new(4.3, 1.2, -2.3), Vector3.new(-4.3, 1.2, -2.3),
		}) do
		makePart("Leg", Vector3.new(0.6, 2.4, 0.6), offset, TABLE_WOOD_DARK, Enum.Material.Wood)
	end
	-- A deck box on each side of the felt, for looks
	makePart("DeckBox", Vector3.new(0.7, 0.5, 0.9), Vector3.new(3.6, 3.83, 1.6), Color3.fromRGB(230, 120, 40))
	makePart("DeckBox", Vector3.new(0.7, 0.5, 0.9), Vector3.new(-3.6, 3.83, -1.6), Color3.fromRGB(80, 120, 220))

	PAD_POSITIONS = {
		position + Vector3.new(0, 0.1, 6),
		position + Vector3.new(0, 0.1, -6),
	}
	local pads = {}
	for seat = 1, 2 do
		pads[seat] = makePart("SeatPad" .. seat, Vector3.new(4, 0.2, 4), PAD_POSITIONS[seat] - position, SEAT_COLOR,
			Enum.Material.Fabric)
	end

	local function addPrompt(part, name, actionText, objectText)
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = name
		prompt.ActionText = actionText
		prompt.ObjectText = objectText
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
		return prompt
	end

	seatPrompts = {
		addPrompt(pads[1], "SeatPrompt", "Sit down", ("Table %d, seat 1"):format(index)),
		addPrompt(pads[2], "SeatPrompt", "Sit down", ("Table %d, seat 2"):format(index)),
	}
	practicePrompt = addPrompt(tableTop, "PracticePrompt", "Practice vs Bot", ("Table %d"):format(index))

	-- Floating sign above the table: its number and what's happening there
	local sign = Instance.new("BillboardGui")
	sign.Name = "StatusSign"
	sign.Size = UDim2.fromScale(8, 2.4)
	sign.StudsOffset = Vector3.new(0, 4.5, 0)
	sign.MaxDistance = 60
	sign.AlwaysOnTop = false
	local numberLabel = Instance.new("TextLabel")
	numberLabel.Name = "TableNumber"
	numberLabel.Size = UDim2.fromScale(1, 0.4)
	numberLabel.BackgroundTransparency = 1
	numberLabel.TextScaled = true
	numberLabel.Font = Enum.Font.GothamBold
	numberLabel.TextColor3 = Color3.fromRGB(255, 205, 90)
	numberLabel.TextStrokeTransparency = 0.3
	numberLabel.Text = "TABLE " .. index
	numberLabel.Parent = sign
	signLabel = Instance.new("TextLabel")
	signLabel.Name = "StatusText"
	signLabel.Position = UDim2.fromScale(0, 0.4)
	signLabel.Size = UDim2.fromScale(1, 0.6)
	signLabel.BackgroundTransparency = 1
	signLabel.TextScaled = true
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	signLabel.TextStrokeTransparency = 0.3
	signLabel.Text = "Open table"
	signLabel.Parent = sign
	sign.Parent = tableTop

	model.Parent = parent
	end -- (physical table)

	---------------------------------------------------------------------
	-- Match state for this table
	---------------------------------------------------------------------
	local match = {
		Seats = {},    -- [1], [2] = a Player, BOT, or nil
		Decks = {},    -- [1], [2] = the deck each seat picked
		Votes = {},    -- [1], [2] = best-of vote (1, 3 or 5)
		Finishes = {}, -- [1], [2] = { [cardId] = finish } (the shiniest copies each player owns)
		Battle = nil,
		Over = false,  -- the current game is over and handled
		Series = nil,  -- { BestOf, WinsNeeded, Wins = { a, b }, Game, Over }
		LogPlayers = {},   -- who played this game, for the match log (kept even if they leave)
		LogExperience = {},
		LeftSeat = nil,    -- set when a player leaves mid-game
		Timeouts = { 0, 0 },  -- turns in a row each seat let the timer run out
		TimerTurn = nil,      -- the turn the timer is running for
		TurnEndsAt = nil,     -- os.clock() when the current turn times out (PvP only)
		StartedAt = nil,      -- os.clock() when the current game started
	}

	local function isHuman(occupant)
		return occupant ~= nil and occupant ~= BOT
	end

	local function seatOf(player)
		for seat = 1, 2 do
			if match.Seats[seat] == player then
				return seat
			end
		end
		return nil
	end

	local function refreshTable()
		local battle = match.Battle
		if battle then
			local series = match.Series
			if series and series.BestOf > 1 then
				signLabel.Text = ("Best of %d  |  %d - %d"):format(series.BestOf, series.Wins[1], series.Wins[2])
			else
				signLabel.Text = battle.Winner and "Match over" or "Match in progress"
			end
		elseif match.Seats[1] and match.Seats[2] then
			signLabel.Text = "Choosing decks"
		elseif match.Seats[1] or match.Seats[2] then
			signLabel.Text = "Waiting for an opponent"
		else
			signLabel.Text = "Open table"
		end
		for seat = 1, 2 do
			seatPrompts[seat].Enabled = battle == nil and match.Seats[seat] == nil
		end
		practicePrompt.Enabled = battle == nil and match.Seats[1] == nil and match.Seats[2] == nil
	end

	local function send(player, payload)
		updateRemote:FireClient(player, payload)
	end

	local function seatNames()
		local names = {}
		for seat = 1, 2 do
			local occupant = match.Seats[seat]
			if occupant == BOT then
				names[seat] = "Practice Bot"
			elseif occupant then
				names[seat] = occupant.DisplayName
			else
				names[seat] = "(left)"
			end
		end
		return names
	end

	local onTimeout -- defined below
	local leaveSeat -- defined below

	-- Starts the turn timer when a new PvP turn begins (safe to call any time)
	local function scheduleTimer()
		local battle = match.Battle
		local pvp = isHuman(match.Seats[1]) and isHuman(match.Seats[2])
		if not battle or battle.Winner or battle.Phase == "Mulligan" or not pvp then
			match.TurnEndsAt = nil
			return
		end
		if match.TimerTurn == battle.Turn then
			return
		end
		match.TimerTurn = battle.Turn
		match.TurnEndsAt = os.clock() + TURN_SECONDS
		local turn, seat = battle.Turn, battle.Current
		task.delay(TURN_SECONDS, function()
			if match.Battle == battle and not battle.Winner and battle.Turn == turn and battle.Current == seat then
				onTimeout(battle, seat)
			end
		end)
	end

	local function sendMatchUpdate(events)
		local battle = match.Battle
		if not battle then
			return
		end
		scheduleTimer()
		local names = seatNames()
		for seat = 1, 2 do
			local occupant = match.Seats[seat]
			if isHuman(occupant) then
				local state = battle:GetState(seat)
				local finishes = {}
				-- Named fields (not [1]/[2]): a numbered list built out of order can arrive
				-- scrambled through a RemoteEvent, which lost seat 2's finishes
				finishes.Mine = match.Finishes[seat] or {}
				finishes.Theirs = visibleFinishes(match.Finishes[3 - seat], state.Players[3 - seat])
				send(occupant, {
					Kind = "Match",
					Seat = seat,
					Names = names,
					Mats = match.Mats,
					Series = match.Series and {
						BestOf = match.Series.BestOf,
						Wins = { match.Series.Wins[1], match.Series.Wins[2] },
						Game = match.Series.Game,
						Over = match.Series.Over,
						DeckFormat = match.Series.DeckFormat,
					} or nil,
					Finishes = finishes,
					State = state,
					Events = BattleEngine.FilterEvents(events or {}, seat),
					TurnEndsIn = match.TurnEndsAt and math.max(0, match.TurnEndsAt - os.clock()) or nil,
					TurnSeconds = match.TurnEndsAt and TURN_SECONDS or nil,
					Tutorial = tutorial or nil,
				})
			end
		end
		-- the TV above the table and everyone watching (they see only what's on the table)
		if virtual then
			return
		end
		local onTable = battle:GetState(0)
		Spectate.Update(index, battle, {
			Names = names,
			Events = events,
			Mats = match.Mats,
			Finishes = {
				visibleFinishes(match.Finishes[1], onTable.Players[1]),
				visibleFinishes(match.Finishes[2], onTable.Players[2]),
			},
			BestOf = match.Series and match.Series.BestOf or 1,
			Game = match.Series and match.Series.Game or 1,
			Wins = match.Series and { match.Series.Wins[1], match.Series.Wins[2] } or nil,
		})
	end

	local function resetTable()
		for seat = 1, 2 do
			local occupant = match.Seats[seat]
			if isHuman(occupant) then
				send(occupant, { Kind = "Closed" })
			end
		end
		match.Seats = {}
		match.Decks = {}
		match.Votes = {}
		match.Finishes = {}
		match.Mats = nil
		match.Series = nil
		match.Battle = nil
		match.Over = false
		match.TurnEndsAt = nil
		refreshTable()
		if virtual then
			if options.OnClosed then
				options.OnClosed()
			end
		else
			Spectate.Closed(index)
		end
	end

	local afterAction
	local startGame

	local function runBotTurn(battle, seat)
		BattleBot.TakeTurn(battle, seat, function(events)
			if match.Battle == battle then
				sendMatchUpdate(events)
			end
		end, function()
			task.wait(BOT_ACTION_DELAY)
		end)
		if match.Battle == battle then
			afterAction()
		end
	end

	-- Runs after anything changes: ends the match or lets the bot move
	afterAction = function()
		local battle = match.Battle
		if not battle then
			return
		end
		if battle.Winner then
			if not match.Over and tutorial then
				-- The tutorial: no coins or records; it counts as done either way
				match.Over = true
				local player = match.Seats[1]
				if isHuman(player) then
					local won = battle.Winner == 1
					PlayerData.SetTutorialDone(player, false)
					Analytics.Onboarding(player, "tutorial_finished", "completed")
					Analytics.Event(player, "tutorial_completed", won and "won" or "lost",
						math.floor(os.clock() - (match.StartedAt or os.clock())))
					send(player, { Kind = "TutorialDone", Won = won })
				end
				task.delay(RESET_DELAY, function()
					if match.Battle == battle then
						resetTable()
					end
				end)
				return
			end
			if not match.Over then
				match.Over = true
				-- Coins and win/loss records (per game) for everyone still at the table
				local vsBot = match.Seats[1] == BOT or match.Seats[2] == BOT
				local duration = os.clock() - (match.StartedAt or os.clock())
				local devices = {}
				for seat = 1, 2 do
					devices[seat] = match.LogPlayers[seat] and Analytics.DeviceOf(match.LogPlayers[seat]) or nil
				end
				MatchLog.Record({
					Battle = battle,
					Decks = match.LogDecks,
					Players = { match.LogPlayers[1], match.LogPlayers[2] },
					Experience = match.LogExperience,
					Mode = match.LogVsBot and "Bot" or "PvP",
					BestOf = match.Series and match.Series.BestOf or 1,
					Game = match.Series and match.Series.Game or 1,
					Left = match.LeftSeat,
					Table = (not virtual) and index or nil,
					Duration = duration,
					Devices = devices,
					TimedOut = { match.Timeouts[1], match.Timeouts[2] },
				})
				for seat = 1, 2 do
					local occupant = match.Seats[seat]
					if isHuman(occupant) then
						local won = battle.Winner == seat
						local coins, bonus = PlayerData.RecordMatch(occupant, won, vsBot, battle.Turn)
						local data = PlayerData.Get(occupant)
						local played = data and (data.Stats.Wins + data.Stats.Losses) or 0
						send(occupant, { Kind = "Reward", Coins = coins, Bonus = bonus or 0, VsBot = vsBot,
							Won = won, MatchesPlayed = played })
						Analytics.Event(occupant, vsBot and "practice_match_completed" or "pvp_match_completed",
							won and "won" or "lost", math.floor(duration))
						if played == 1 then
							Analytics.Onboarding(occupant, "first_match_completed", vsBot and "bot" or "pvp")
						end
					end
				end
				local series = match.Series
				if series then
					series.Wins[battle.Winner] = series.Wins[battle.Winner] + 1
					if series.Wins[battle.Winner] >= series.WinsNeeded then
						series.Over = true
					end
					sendMatchUpdate({}) -- everyone sees the new series score
				end
				refreshTable()
				if series and not series.Over then
					-- Next game: same decks, the loser goes first
					local loser = 3 - battle.Winner
					task.delay(NEXT_GAME_DELAY, function()
						if match.Battle ~= battle then
							return
						end
						if match.Seats[1] and match.Seats[2] then
							series.Game = series.Game + 1
							startGame(loser)
						else
							resetTable()
						end
					end)
				else
					task.delay(RESET_DELAY, function()
						if match.Battle == battle then
							resetTable()
						end
					end)
				end
			end
			return
		end
		if match.Seats[battle.Current] == BOT then
			task.spawn(runBotTurn, battle, battle.Current)
		end
	end

	-- A turn ran out (PvP): the turn ends by itself. Too many in a row and the
	-- player is out of the match (like leaving the table).
	onTimeout = function(battle, seat)
		match.Timeouts[seat] = match.Timeouts[seat] + 1
		local timedOut = match.Seats[seat]
		local forfeit = match.Timeouts[seat] >= MAX_TIMEOUTS
		for s2 = 1, 2 do
			if isHuman(match.Seats[s2]) then
				send(match.Seats[s2], { Kind = "TurnTimeout", Seat = s2 == seat and "You" or "Opponent",
					Count = match.Timeouts[seat], Max = MAX_TIMEOUTS, Forfeit = forfeit })
			end
		end
		if isHuman(timedOut) then
			Analytics.Event(timedOut, "turn_timeout", forfeit and "forfeit" or tostring(match.Timeouts[seat]))
		end
		if forfeit then
			if isHuman(timedOut) then
				leaveSeat(timedOut, seat)
				send(timedOut, { Kind = "Closed" })
			end
			return
		end
		local ok, events = battle:EndTurn(seat)
		if ok then
			sendMatchUpdate(events)
			afterAction()
		end
	end

	local function buildDeck(name)
		-- Prototype: starter decks only, until collections exist
		local starter = CardDatabase.StarterDecks[name]
		return {
			Commander = starter.Commander,
			Celestial = starter.Celestial,
			Cards = CardDatabase.ExpandCounts(starter.Cards),
			Format = "Zenith", -- starter decks fit the Zenith star cap
		}
	end

	-- Each side's playmat: your equipped mat, or the bot's faction mat
	local function matFor(seat)
		local occupant = match.Seats[seat]
		if isHuman(occupant) then
			return PlayerData.GetEquippedMat(occupant)
		end
		local commander = CardDatabase.GetCard(match.Decks[seat].Commander)
		return Playmats.ForFaction(commander and commander.Faction)
	end

	-- One game of the series. firstPlayer = nil for a random first player.
	startGame = function(firstPlayer)
		-- Remember who's playing for the match log (a player who leaves is
		-- removed from their seat before the game is recorded)
		match.LogPlayers, match.LogExperience, match.LogDecks = {}, {}, { match.Decks[1], match.Decks[2] }
		match.LogVsBot = match.Seats[1] == BOT or match.Seats[2] == BOT
		match.LeftSeat = nil
		for seat = 1, 2 do
			local occupant = match.Seats[seat]
			if isHuman(occupant) then
				match.LogPlayers[seat] = occupant
				local data = PlayerData.Get(occupant)
				local stats = data and data.Stats
				match.LogExperience[seat] = stats and (stats.Wins + stats.Losses) or 0
			end
		end
		local battle = BattleEngine.new({ Decks = { match.Decks[1], match.Decks[2] },
			FirstPlayer = tutorial and 1 or firstPlayer,
			Mulligan = not tutorial,
			Scripted = tutorial and TUTORIAL.Scripted or nil })
		match.Battle = battle
		match.Over = false
		match.StartedAt = os.clock()
		match.Timeouts = { 0, 0 }
		match.TimerTurn = nil
		match.TurnEndsAt = nil
		if not tutorial then
			local vsBot = match.Seats[1] == BOT or match.Seats[2] == BOT
			for seat = 1, 2 do
				local occupant = match.Seats[seat]
				if isHuman(occupant) and (not match.Series or match.Series.Game == 1) then
					local n = PlayerData.NoteMatchStarted(occupant)
					local commander = CardDatabase.GetCard(match.Decks[seat].Commander)
					Analytics.Event(occupant, vsBot and "practice_match_started" or "pvp_match_started",
						commander and commander.Faction)
					if n == 1 then
						Analytics.Onboarding(occupant, "first_match_started", vsBot and "bot" or "pvp")
					elseif n == 2 then
						Analytics.Onboarding(occupant, "second_match_started", vsBot and "bot" or "pvp")
					end
				end
			end
		end
		refreshTable()
		sendMatchUpdate(battle:TakeStartEvents())
		-- Starting hands: the bot chooses right away; anyone who hasn't chosen
		-- when time runs out keeps their hand
		local function mulligan(seat, picks)
			if match.Battle ~= battle or battle.Phase ~= "Mulligan" then
				return
			end
			local ok, events = battle:Mulligan(seat, picks)
			if ok then
				sendMatchUpdate(events)
				afterAction()
			end
		end
		for seat = 1, 2 do
			if match.Seats[seat] == BOT then
				task.delay(1, function()
					mulligan(seat, BattleBot.ChooseMulligan(battle, seat))
				end)
			end
		end
		task.delay(MULLIGAN_SECONDS, function()
			for seat = 1, 2 do
				if battle.Players[seat] and not battle.Players[seat].MulliganDone then
					mulligan(seat, {})
				end
			end
		end)
		afterAction()
	end

	-- The series format: the human's pick against the bot, else the shorter vote
	local function decideFormat()
		local votes = {}
		for seat = 1, 2 do
			if isHuman(match.Seats[seat]) then
				table.insert(votes, match.Votes[seat] or 1)
			end
		end
		local bestOf = votes[1] or 1
		for _, vote in ipairs(votes) do
			bestOf = math.min(bestOf, vote)
		end
		return bestOf
	end

	-- The match is Zenith only if both decks fit the Zenith star cap; otherwise it's Open
	local function decideDeckFormat()
		for seat = 1, 2 do
			local deck = match.Decks[seat]
			if not CardDatabase.ValidateDeck(deck.Commander, deck.Celestial, deck.Cards, "Zenith") then
				return "Open"
			end
		end
		return "Zenith"
	end

	local function startMatch()
		match.Mats = { matFor(1), matFor(2) }
		local bestOf = decideFormat()
		match.Series = { BestOf = bestOf, WinsNeeded = (bestOf + 1) // 2, Wins = { 0, 0 }, Game = 1, Over = false,
			DeckFormat = decideDeckFormat() }
		startGame(nil)
	end

	local function moveToPad(player, seat)
		if virtual then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = CFrame.new(PAD_POSITIONS[seat] + Vector3.new(0, 3, 0))
		end
	end

	local function cardName(id)
		local card = id and CardDatabase.GetCard(id)
		return card and card.Name or "?"
	end

	-- Your saved decks first, then the starter decks you own
	local function sendDeckChoice(player)
		local options = {}
		local data = PlayerData.Get(player)
		if data then
			for _, deck in ipairs(data.Decks) do
				local legal, problems, stars = PlayerData.CheckDeck(data, deck)
				local format = CardDatabase.FormatOf(deck.Format)
				table.insert(options, {
					Key = "saved:" .. deck.Id,
					Name = deck.Name,
					Format = format,
					Faction = CardDatabase.GetCard(deck.Commander).Faction,
					Description = legal and ("%s deck: %d cards, %d stars"):format(format, #deck.Cards, stars) or problems[1],
					Commander = cardName(deck.Commander),
					Celestial = cardName(deck.Celestial),
					Legal = legal,
				})
			end
		end
		for _, name in ipairs(CardDatabase.StarterDeckOrder) do
			local starter = CardDatabase.StarterDecks[name]
			if data and data.OwnedStarters[name] then
				table.insert(options, {
					Key = name,
					Name = name .. " starter",
					Format = "Zenith",
					Faction = name,
					Description = starter.Description,
					Commander = cardName(starter.Commander),
					Celestial = cardName(starter.Celestial),
					Legal = true,
				})
			end
		end
		local seat = seatOf(player)
		local otherSeat = seat and 3 - seat
		send(player, {
			Kind = "ChooseDeck",
			Decks = options,
			VsBot = otherSeat ~= nil and match.Seats[otherSeat] == BOT,
			OpponentVote = otherSeat and match.Decks[otherSeat] and match.Votes[otherSeat] or nil,
			OpponentDeckFormat = otherSeat and match.Decks[otherSeat] and match.Decks[otherSeat].Format or nil,
		})
	end

	-- Turns a picker choice into a playable deck, or nil + reason
	local function resolveDeck(player, key)
		if type(key) ~= "string" then
			return nil, "Pick a deck."
		end
		if CardDatabase.StarterDecks[key] then
			local data = PlayerData.Get(player)
			if not (data and data.OwnedStarters[key]) then
				return nil, "You don't own that starter deck. Get it at the Card Shop."
			end
			return buildDeck(key)
		end
		local id = key:match("^saved:(.+)$")
		local deck = id and PlayerData.GetDeck(player, id)
		if not deck then
			return nil, "That deck doesn't exist anymore."
		end
		local legal, problems = PlayerData.CheckDeck(PlayerData.Get(player), deck)
		if not legal then
			return nil, deck.Name .. " isn't ready: " .. problems[1]
		end
		local cards = {}
		for i, cardId in ipairs(deck.Cards) do
			cards[i] = cardId
		end
		return { Commander = deck.Commander, Celestial = deck.Celestial, Cards = cards, Finishes = deck.Finishes,
			Format = CardDatabase.FormatOf(deck.Format) }
	end

	-- A player gets up: leaving mid-match counts as conceding
	leaveSeat = function(player, seat)
		match.Seats[seat] = nil
		match.Decks[seat] = nil
		local battle = match.Battle
		-- Leaving a practice table before it starts also sends the bot away
		if not battle and match.Seats[3 - seat] == BOT then
			match.Seats[3 - seat] = nil
			match.Decks[3 - seat] = nil
		end
		-- Someone still seated and ready goes back to waiting for a new opponent
		local remaining = match.Seats[3 - seat]
		if not battle and isHuman(remaining) and match.Decks[3 - seat] then
			send(remaining, { Kind = "Waiting", Message = "Your opponent left. Waiting for someone to sit down..." })
		end
		-- Leaving forfeits the whole series, not just this game
		if match.Series and not match.Series.Over then
			match.Series.Wins[3 - seat] = match.Series.WinsNeeded - 1 -- the concede below finishes it
			if battle and battle.Winner then
				match.Series.Wins[3 - seat] = match.Series.WinsNeeded
				match.Series.Over = true
				sendMatchUpdate({})
				task.delay(RESET_DELAY, function()
					if match.Battle == battle then
						resetTable()
					end
				end)
			end
		end
		if battle and not battle.Winner then
			match.LeftSeat = seat
			local ok, events = battle:Concede(seat)
			if ok then
				sendMatchUpdate(events)
				afterAction()
			end
		end
		refreshTable()
	end

	---------------------------------------------------------------------
	-- Sitting down
	---------------------------------------------------------------------
	for seat = 1, virtual and 0 or 2 do
		seatPrompts[seat].Triggered:Connect(function(player)
			if match.Battle or match.Seats[seat] or tableOf(player) then
				return
			end
			match.Seats[seat] = player
			moveToPad(player, seat)
			refreshTable()
			sendDeckChoice(player)
		end)
	end

	local function startPractice(player)
		if match.Battle or match.Seats[1] or match.Seats[2] or (tableOf(player) and tableOf(player) ~= self) then
			return false
		end
		match.Seats[1] = player
		match.Seats[2] = BOT
		moveToPad(player, 1)
		refreshTable()
		sendDeckChoice(player)
		return true
	end
	if not virtual then
		practicePrompt.Triggered:Connect(startPractice)
	end

	-- The tutorial: straight into the scripted match (no deck choice, no mulligan)
	local function startTutorial(player)
		match.Seats[1] = player
		match.Seats[2] = BOT
		for seat = 1, 2 do
			local deck = TUTORIAL.Decks[seat]
			match.Decks[seat] = { Commander = deck.Commander, Celestial = deck.Celestial, Cards = table.clone and
				table.clone(deck.Cards) or { table.unpack(deck.Cards) }, Format = deck.Format }
			match.Votes[seat] = 1
		end
		match.Finishes[1] = bestFinishes(player, match.Decks[1])
		send(player, { Kind = "Waiting", Message = "Starting the tutorial..." })
		startMatch()
		return true
	end

	---------------------------------------------------------------------
	-- Actions from players (never trusted: checked here and by the engine)
	---------------------------------------------------------------------
	local function toInt(value)
		if type(value) == "number" and value == math.floor(value) and value >= -100 and value <= 100 then
			return value
		end
		return nil
	end

	local function toTarget(value)
		if type(value) ~= "table" then
			return nil
		end
		if value.Side ~= "Self" and value.Side ~= "Enemy" then
			return nil
		end
		local lane = toInt(value.Lane)
		if not lane then
			return nil
		end
		return { Side = value.Side, Lane = lane }
	end


	local function handleAction(player, action)
		if type(action) ~= "table" then
			return
		end
		local seat = seatOf(player)
		if not seat then
			return
		end

		if action.Kind == "Leave" then
			if tutorial and match.Battle and not match.Battle.Winner then
				Analytics.Event(player, "tutorial_left", tostring(math.ceil(match.Battle.Turn / 2)))
			end
			leaveSeat(player, seat)
			send(player, { Kind = "Closed" })
			if virtual then
				resetTable()
			end
			return
		end

		-- The tutorial's steps, for the "Tutorial" analytics funnel
		if action.Kind == "TutorialStep" then
			local step = toInt(action.Step)
			if tutorial and step and TUTORIAL_STEPS[step] and step > (match.TutorialLastStep or 0) then
				match.TutorialLastStep = step
				match.TutorialSession = match.TutorialSession or (tostring(player.UserId) .. "-" .. tostring(os.time()))
				Analytics.Funnel(player, "Tutorial", match.TutorialSession, step, TUTORIAL_STEPS[step])
			end
			return
		end

		if action.Kind == "ChooseDeck" then
			if match.Battle then
				return
			end
			local deck, reason = resolveDeck(player, action.Deck)
			if not deck then
				send(player, { Kind = "DeckError", Message = reason })
				return
			end
			match.Decks[seat] = deck
			match.Finishes[seat] = bestFinishes(player, deck)
			match.Votes[seat] = FORMATS[action.BestOf] and action.BestOf or 1
			local otherSeat = 3 - seat
			-- The other player (if still picking) sees this vote
			local other = match.Seats[otherSeat]
			if isHuman(other) and not match.Decks[otherSeat] then
				send(other, { Kind = "OpponentVote", BestOf = match.Votes[seat], DeckFormat = deck.Format })
			end
			if match.Seats[otherSeat] == BOT and not match.Decks[otherSeat] then
				local order = CardDatabase.StarterDeckOrder
				match.Decks[otherSeat] = buildDeck(order[math.random(1, #order)])
			end
			if match.Seats[otherSeat] and match.Decks[otherSeat] then
				startMatch()
			elseif match.Seats[otherSeat] then
				send(player, { Kind = "Waiting", Message = ("You voted best of %d. Waiting for your opponent to pick a deck..."):format(match.Votes[seat]) })
			else
				send(player, { Kind = "Waiting", Message = "Waiting for an opponent to sit down..." })
			end
			return
		end

		local battle = match.Battle
		if not battle or battle.Winner then
			return
		end

		local ok, result
		local kind = action.Kind
		if kind == "PlayCard" then
			ok, result = battle:PlayCard(seat, toInt(action.HandIndex), {
				Lane = toInt(action.Lane),
				Target = toTarget(action.Target),
			})
		elseif kind == "SummonCelestial" then
			ok, result = battle:SummonCelestial(seat, toInt(action.Lane))
		elseif kind == "UseAbility" then
			ok, result = battle:UseCommanderAbility(seat, toTarget(action.Target))
		elseif kind == "UseSpark" then
			ok, result = battle:UseSpark(seat)
		elseif kind == "EndTurn" then
			ok, result = battle:EndTurn(seat)
			if ok then
				match.Timeouts[seat] = 0
			end
		elseif kind == "Mulligan" then
			local picks = {}
			if type(action.Indexes) == "table" then
				for i = 1, 10 do
					local index = toInt(action.Indexes[i])
					if index then
						table.insert(picks, index)
					end
				end
			end
			ok, result = battle:Mulligan(seat, picks)
		else
			return
		end

		if ok then
			match.Timeouts[seat] = 0 -- playing at all (not just ending the turn) shows they're there
			sendMatchUpdate(result)
			afterAction()
		else
			send(player, { Kind = "Error", Message = result })
		end
	end

	self.Index = index
	self.Virtual = virtual
	self.SeatOf = seatOf
	self.HandleAction = handleAction
	self.Leave = leaveSeat
	self.Refresh = refreshTable
	self.StartPractice = startPractice
	self.StartTutorial = startTutorial
	self.Close = resetTable
	return self
end

for index, position in ipairs(Building.TablePositions) do
	tables[index] = createTable(index, position, Building.Model)
end

---------------------------------------------------------------------
-- Off-table matches: practice vs the bot from anywhere (the "Play" button)
-- and the tutorial. They don't use one of the shop's tables, so the bot
-- never blocks a table that two players could use.
---------------------------------------------------------------------
local nextVirtual = 1000
local function newVirtualTable(isTutorial)
	nextVirtual = nextVirtual + 1
	local t
	t = createTable(nextVirtual, nil, nil, {
		Virtual = true,
		Tutorial = isTutorial,
		OnClosed = function()
			for i, other in ipairs(tables) do
				if other == t then
					table.remove(tables, i)
					break
				end
			end
		end,
	})
	table.insert(tables, t)
	return t
end

local playRequest = Instance.new("RemoteFunction")
playRequest.Name = "PlayRequest"
playRequest.Parent = remotes

playRequest.OnServerInvoke = function(player, kind)
	if not RateLimit.Allow(player, "Play", 4, 3) then
		return false, "One moment..."
	end
	if not PlayerData.IsLoaded(player) then
		return false, "Your cards haven't loaded yet."
	end
	local data = PlayerData.Get(player)
	if kind == "SkipTutorial" then
		if data and not data.Onboarding.TutorialDone then
			PlayerData.SetTutorialDone(player, true)
			Analytics.Onboarding(player, "tutorial_finished", "skipped")
			Analytics.Event(player, "tutorial_skipped")
		end
		return true
	end
	if tableOf(player) then
		return false, "You're already in a match. Leave it first."
	end
	if kind == "StartTutorial" then
		Analytics.Onboarding(player, "tutorial_started")
		Analytics.Event(player, "tutorial_started", data and data.Onboarding.TutorialDone and "replay" or "first")
		local t = newVirtualTable(true)
		local ok, err = pcall(t.StartTutorial, player)
		if not ok then
			warn("Tutorial failed to start: " .. tostring(err))
			t.Close()
			return false, "Couldn't start the tutorial right now."
		end
		return true
	elseif kind == "Practice" then
		if not data or next(data.OwnedStarters) == nil and #data.Decks == 0 then
			return false, "Claim a starter deck first (the starter deck table in the shop)."
		end
		local t = newVirtualTable(false)
		local ok, started = pcall(t.StartPractice, player)
		if not ok or not started then
			t.Close()
			return false, "Couldn't start a match right now."
		end
		return true
	end
	return false, "Unknown request."
end

actionRemote.OnServerEvent:Connect(function(player, action)
	local leaving = type(action) == "table" and action.Kind == "Leave"
	if not leaving and not RateLimit.Allow(player, "BattleAction", 25, 5) then
		return
	end
	local t = tableOf(player)
	if t then
		t.HandleAction(player, action)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local t = tableOf(player)
	if t then
		t.Leave(player, t.SeatOf(player))
		if t.Virtual then
			t.Close()
		end
	end
end)

for _, t in ipairs(tables) do
	t.Refresh()
end

MatchLog.Start()