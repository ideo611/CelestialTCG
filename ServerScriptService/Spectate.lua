--[[
	Spectate (ModuleScript)
	Location: ServerScriptService > Spectate

	Lets everyone in the shop watch the matches:
	  - a TV hangs above every play table showing the live board
	  - walk under a TV and press F ("Watch match"), click WATCH on the TV
	    screen, or use the "Live games" button, to watch full screen
	  - the TV also shows how many people are watching

	What spectators see is the same as a stranger standing at the table:
	the board, both Commanders' HP, how many cards each player holds, but
	never the cards in anyone's hand or a face-down Celestial.

	BattleTableServer tells this module what's happening with two calls:
	  Spectate.Update(tableIndex, battle, info)   after every change
	  Spectate.Closed(tableIndex)                 when the table resets
	info (every field optional):
	  Names    = { seat 1 name, seat 2 name }
	  Events   = the battle events that just happened (for the play-by-play)
	  Mats     = { seat 1 playmat id, seat 2 playmat id }
	  Finishes = { seat 1 {cardId = finish}, seat 2 {cardId = finish} }
	  BestOf, Game, Wins = { seat 1 wins, seat 2 wins }

	Everything sent to players uses named keys (Seat1 / Seat2, L1 / L2 / L3)
	so nothing gets scrambled on the way.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))

local Spectate = {}

Spectate.TvBottom = 10.5     -- studs above the table's floor spot
Spectate.TvSize = Vector2.new(7, 4)
Spectate.CeilingHeight = 17.6 -- the hanging rods reach up this far (the shop's ceiling)
Spectate.MinGap = 0.25       -- seconds between TV updates for one table
Spectate.TickerLines = 8     -- play-by-play lines kept per table
Spectate.LiveColor = Color3.fromRGB(255, 70, 80)
Spectate.IdleColor = Color3.fromRGB(70, 70, 80)

---------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "SpectateRemotes"
local tableUpdate = Instance.new("RemoteEvent")
tableUpdate.Name = "TableUpdate"
tableUpdate.Parent = remotes
local request = Instance.new("RemoteFunction")
request.Name = "SpectateRequest"
request.Parent = remotes
remotes.Parent = ReplicatedStorage

local tvFolder = Instance.new("Folder")
tvFolder.Name = "SpectateTVs"
tvFolder.Parent = workspace

---------------------------------------------------------------------
-- Per-table state
---------------------------------------------------------------------
local tables = {}   -- [index] = { Snapshot, Battle, Ticker, UidCards, Screen, Lamp, Prompt, ... }
local watching = {} -- [player] = table index

local function watcherCount(index)
	local n = 0
	for _, watched in pairs(watching) do
		if watched == index then
			n = n + 1
		end
	end
	return n
end

local function idleSnapshot(index)
	return { Table = index, Live = false, Watchers = watcherCount(index) }
end

---------------------------------------------------------------------
-- The TV in the world
---------------------------------------------------------------------
local function tablePosition(index)
	local ok, Building = pcall(function()
		return require(ServerScriptService:WaitForChild("CardShopBuilding", 5))
	end)
	if ok and type(Building) == "table" and Building.TablePositions then
		return Building.TablePositions[index]
	end
	return nil
end

local function part(name, size, cframe, color, material, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function buildTv(index, t)
	local base = tablePosition(index)
	if not base then
		return
	end
	local model = Instance.new("Model")
	model.Name = "TV" .. index

	local w, h = Spectate.TvSize.X, Spectate.TvSize.Y
	local center = base + Vector3.new(0, Spectate.TvBottom + h / 2, 0)
	local cf = CFrame.new(center)

	-- The screen shows on both sides: Front faces one seat, Back the other
	local screen = part("Screen", Vector3.new(w, h, 0.3), cf, Color3.fromRGB(8, 8, 14), Enum.Material.SmoothPlastic, model)
	screen:SetAttribute("TableIndex", index)
	part("Bezel", Vector3.new(w + 0.5, h + 0.5, 0.22), cf, Color3.fromRGB(28, 26, 36), Enum.Material.Metal, model)

	local lamp = part("LiveLamp", Vector3.new(0.9, 0.3, 0.3), cf * CFrame.new(0, h / 2 + 0.4, 0),
		Spectate.IdleColor, Enum.Material.Neon, model)

	local topY = center.Y + h / 2 + 0.25
	local ceilingY = base.Y + Spectate.CeilingHeight
	if ceilingY > topY + 0.2 then
		for _, x in ipairs({ -w / 2 + 0.8, w / 2 - 0.8 }) do
			local length = ceilingY - topY
			part("Rod", Vector3.new(0.18, length, 0.18), CFrame.new(center.X + x, topY + length / 2, center.Z),
				Color3.fromRGB(34, 28, 44), Enum.Material.Metal, model)
		end
	end

	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local glow = Instance.new("SurfaceLight")
		glow.Face = face
		glow.Brightness = 0.6
		glow.Range = 10
		glow.Angle = 100
		glow.Color = Color3.fromRGB(150, 170, 255)
		glow.Parent = screen
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WatchPrompt"
	prompt.ActionText = "Watch match"
	prompt.ObjectText = "Table " .. index
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 24
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = screen
	prompt.Triggered:Connect(function(player)
		tableUpdate:FireClient(player, { Kind = "OpenWatch", Table = index })
	end)

	model.Parent = tvFolder
	t.Screen, t.Lamp, t.Prompt = screen, lamp, prompt
end

local function getTable(index)
	local t = tables[index]
	if not t then
		t = {
			Snapshot = idleSnapshot(index),
			Ticker = {},
			UidCards = {},
			LastSent = 0,
		}
		tables[index] = t
		buildTv(index, t)
	end
	return t
end

local function setLive(t, live)
	if t.Lamp then
		t.Lamp.Color = live and Spectate.LiveColor or Spectate.IdleColor
	end
	if t.Prompt then
		t.Prompt.Enabled = live
	end
end

---------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------
local function sendNow(index)
	local t = tables[index]
	t.LastSent = os.clock()
	t.Snapshot.Watchers = watcherCount(index)
	tableUpdate:FireAllClients({ Kind = "Table", Snapshot = t.Snapshot })
end

local function broadcast(index)
	local t = tables[index]
	if t.Scheduled then
		return
	end
	local waitFor = t.LastSent + Spectate.MinGap - os.clock()
	if waitFor <= 0 then
		sendNow(index)
	else
		t.Scheduled = true
		task.delay(waitFor, function()
			t.Scheduled = false
			sendNow(index)
		end)
	end
end

---------------------------------------------------------------------
-- Building what spectators see
---------------------------------------------------------------------
local function cardName(cardId)
	local card = cardId and CardDatabase.GetCard(cardId)
	return card and card.Name or "a card"
end

local function addLine(t, line)
	table.insert(t.Ticker, line)
	while #t.Ticker > Spectate.TickerLines do
		table.remove(t.Ticker, 1)
	end
end

local function describe(t, event, names)
	local kind = event.Type
	local who = event.Player and names[event.Player] or "?"
	if kind == "MatchStarted" then
		addLine(t, (names[event.FirstPlayer] or "?") .. " goes first.")
	elseif kind == "TurnStarted" then
		addLine(t, "- " .. who .. "'s turn -")
	elseif kind == "UnitPlayed" then
		t.UidCards[event.Uid or 0] = event.CardId
		addLine(t, who .. " played " .. cardName(event.CardId) .. ".")
	elseif kind == "SpellCast" then
		addLine(t, who .. " cast " .. cardName(event.CardId) .. ".")
	elseif kind == "CelestialSummoned" then
		t.UidCards[event.Uid or 0] = event.CardId
		addLine(t, who .. " summoned " .. cardName(event.CardId) .. "!")
	elseif kind == "CommanderAbility" then
		addLine(t, who .. " used their Commander's ability.")
	elseif kind == "UnitDestroyed" then
		addLine(t, cardName(t.UidCards[event.Uid or 0]) .. " was destroyed.")
	elseif kind == "CommanderDamaged" and event.Amount then
		addLine(t, who .. " took " .. event.Amount .. " damage.")
	elseif kind == "MatchOver" and event.Winner then
		addLine(t, (names[event.Winner] or "?") .. " wins!")
	end
end

local function unitView(t, unit)
	if type(unit) ~= "table" or not unit.CardId then
		return nil
	end
	if unit.Uid then
		t.UidCards[unit.Uid] = unit.CardId
	end
	return {
		CardId = unit.CardId,
		Power = unit.Power,
		HP = unit.HP,
		MaxHP = unit.MaxHP,
		Shield = unit.Shield or nil,
		Celestial = unit.IsCelestial or nil,
	}
end

local function seatValue(list, seat)
	if type(list) == "table" then
		return list[seat]
	end
	return nil
end

local function buildSnapshot(index, t, battle, info)
	-- viewer 0 = nobody's seat: hands and face-down Celestials stay hidden
	local ok, state = pcall(function()
		return battle:GetState(0)
	end)
	if not ok or type(state) ~= "table" or type(state.Players) ~= "table" then
		return nil
	end
	local names = {}
	for seat = 1, 2 do
		names[seat] = tostring(seatValue(info.Names, seat) or ("Player " .. seat))
	end

	local seats = {}
	for seat = 1, 2 do
		local p = state.Players[seat] or {}
		local gate = p.StarGate or {}
		local lanes = {}
		for lane = 1, 3 do
			lanes["L" .. lane] = unitView(t, p.Lanes and p.Lanes[lane])
		end
		local finishes = {}
		local given = seatValue(info.Finishes, seat)
		if type(given) == "table" then
			for cardId, finish in pairs(given) do
				if type(cardId) == "string" and type(finish) == "string" then
					finishes[cardId] = finish
				end
			end
		end
		seats["Seat" .. seat] = {
			Name = names[seat],
			Commander = p.CommanderId,
			HP = p.HP,
			Energy = p.Energy,
			MaxEnergy = p.MaxEnergy,
			Hand = p.HandCount or 0,
			Deck = p.DeckCount or 0,
			Gate = {
				CardId = gate.Revealed and gate.CardId or nil,
				Revealed = gate.Revealed or false,
				OnBoard = gate.OnBoard or false,
			},
			Lanes = lanes,
			Mat = seatValue(info.Mats, seat),
			Finishes = finishes,
			Wins = seatValue(info.Wins, seat),
		}
	end

	for _, event in ipairs(info.Events or {}) do
		if type(event) == "table" then
			describe(t, event, names)
		end
	end
	local ticker = {}
	for i, line in ipairs(t.Ticker) do
		ticker[i] = line
	end

	return {
		Table = index,
		Live = true,
		Turn = state.Turn,
		Current = state.Current and ("Seat" .. state.Current) or nil,
		Winner = state.Winner and ("Seat" .. state.Winner) or nil,
		Seats = seats,
		BestOf = info.BestOf,
		Game = info.Game,
		Ticker = ticker,
		Watchers = watcherCount(index),
	}
end

---------------------------------------------------------------------
-- Called by BattleTableServer
---------------------------------------------------------------------
function Spectate.Update(index, battle, info)
	if type(index) ~= "number" or not battle then
		return
	end
	local ok, err = pcall(function()
		info = info or {}
		local t = getTable(index)
		if t.Battle ~= battle then
			t.Battle = battle
			t.Ticker = {}
			t.UidCards = {}
		end
		local snapshot = buildSnapshot(index, t, battle, info)
		if snapshot then
			t.Snapshot = snapshot
			setLive(t, true)
			broadcast(index)
		end
	end)
	if not ok then
		warn("Spectate: couldn't update table " .. tostring(index) .. ": " .. tostring(err))
	end
end

function Spectate.Closed(index)
	if type(index) ~= "number" then
		return
	end
	local t = getTable(index)
	t.Battle = nil
	t.Ticker = {}
	t.UidCards = {}
	t.Snapshot = idleSnapshot(index)
	setLive(t, false)
	broadcast(index)
end

-- Builds the TVs for tables 1..count right away (so they show "open table")
function Spectate.Setup(count)
	for index = 1, count do
		getTable(index)
	end
end

---------------------------------------------------------------------
-- Requests from players
---------------------------------------------------------------------
local function allSnapshots()
	local out = {}
	for index, t in pairs(tables) do
		t.Snapshot.Watchers = watcherCount(index)
		out["T" .. index] = t.Snapshot
	end
	return out
end

request.OnServerInvoke = function(player, kind, index)
	if kind == "All" then
		return allSnapshots()
	elseif kind == "Watch" then
		if type(index) ~= "number" or not tables[index] then
			return false
		end
		local before = watching[player]
		watching[player] = index
		if before and before ~= index and tables[before] then
			broadcast(before)
		end
		broadcast(index)
		return true
	elseif kind == "Stop" then
		local before = watching[player]
		watching[player] = nil
		if before and tables[before] then
			broadcast(before)
		end
		return true
	end
	return nil
end

Players.PlayerRemoving:Connect(function(player)
	local before = watching[player]
	watching[player] = nil
	if before and tables[before] then
		broadcast(before)
	end
end)

-- Build the four shop TVs as soon as this module loads
local ok, Building = pcall(function()
	return require(ServerScriptService:WaitForChild("CardShopBuilding", 5))
end)
if ok and type(Building) == "table" and Building.TablePositions then
	Spectate.Setup(#Building.TablePositions)
end

return Spectate
