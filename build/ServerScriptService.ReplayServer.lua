--[[
	ReplayServer (Script)
	Location: ServerScriptService > ReplayServer

	Studio only: the server side of the replay panel (ReplayClient). Lists the
	recorded games in ReplayLibrary (made by tools/replays.py) and plays one
	on the real battle screen through BattleTableServer, with live controls
	(pause, step, speed) for recording videos. Does nothing in the live game.
]]

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ReplayControl = require(ServerScriptService:WaitForChild("ReplayControl"))

local library
local function getLibrary()
	if not library then
		local ok, result = pcall(function()
			return require(ServerScriptService:WaitForChild("ReplayLibrary", 5))
		end)
		library = ok and type(result) == "table" and result or {}
	end
	return library
end

local function find(id)
	for _, replay in ipairs(getLibrary()) do
		if replay.Id == id then
			return replay
		end
	end
	return nil
end

local remotes = Instance.new("Folder")
remotes.Name = "ReplayRemotes"
local request = Instance.new("RemoteFunction")
request.Name = "ReplayRequest"
request.Parent = remotes
remotes.Parent = ReplicatedStorage

local SPEEDS = { 0.5, 0.75, 1, 1.25, 1.5, 2 }

local handlers = {}

function handlers.List()
	local list = {}
	for _, replay in ipairs(getLibrary()) do
		table.insert(list, { Id = replay.Id, Title = replay.Title, Blurb = replay.Blurb, Summary = replay.Summary,
			Score = replay.Score })
	end
	return true, list
end

function handlers.Play(player, args)
	local replay = find(args.Id)
	if not replay then
		return false, "That replay isn't in the library."
	end
	local seat = args.Seat == 2 and 2 or 1
	local names = { "Opponent", "Opponent" }
	names[seat] = player.DisplayName
	if type(args.OpponentName) == "string" and args.OpponentName ~= "" then
		names[3 - seat] = args.OpponentName:sub(1, 20)
	end
	ReplayControl.Sessions[player] = {
		Data = replay, Seat = seat, Speed = tonumber(args.Speed) or 1, Paused = false, Step = false,
		Names = names, Index = 0, Total = #replay.Actions,
	}
	if not ReplayControl.Start then
		return false, "The battle server isn't ready."
	end
	local ok = ReplayControl.Start(player)
	return ok, ok and "playing" or "Couldn't start the replay (see Output)."
end

local function session(player)
	return ReplayControl.Sessions[player]
end

function handlers.Pause(player)
	local s = session(player)
	if s then
		s.Paused = not s.Paused
	end
	return true, s and s.Paused
end

function handlers.Step(player)
	local s = session(player)
	if s then
		s.Paused = true
		s.Step = true
	end
	return true
end

function handlers.Speed(player, args)
	local s = session(player)
	if not s then
		return false
	end
	local at = 3
	for i, v in ipairs(SPEEDS) do
		if math.abs(v - s.Speed) < 0.01 then
			at = i
		end
	end
	at = math.clamp(at + (args.Change or 0), 1, #SPEEDS)
	s.Speed = SPEEDS[at]
	return true, s.Speed
end

function handlers.Status(player)
	local s = session(player)
	if not s then
		return true, nil
	end
	return true, { Index = s.Index, Total = s.Total, Paused = s.Paused, Speed = s.Speed, Problem = s.Problem,
		Done = s.Done, Title = s.Data.Title }
end

request.OnServerInvoke = function(player, kind, args)
	local handler = handlers[kind]
	if not handler then
		return false, "Unknown request."
	end
	if type(args) ~= "table" then
		args = {}
	end
	local ok, a, b = pcall(handler, player, args)
	if not ok then
		warn("ReplayServer: " .. tostring(a))
		return false, "Something went wrong (see Output)."
	end
	return a, b
end

Players.PlayerRemoving:Connect(function(player)
	ReplayControl.Sessions[player] = nil
end)
