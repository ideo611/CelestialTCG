--[[
	PlayerDataServer (Script)
	Location: ServerScriptService > PlayerDataServer

	Loads each player's cards when they join, saves when they leave (and
	every few minutes), and handles requests from the player's screen:
	opening packs, breaking down extras, trading Star Tokens.
	In Studio it also allows a few testing shortcuts (never in the live game).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TextService = game:GetService("TextService")

local Packs = require(ReplicatedStorage:WaitForChild("Packs"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local RateLimit = require(ServerScriptService:WaitForChild("RateLimit"))
local Analytics = require(ServerScriptService:WaitForChild("Analytics"))

local AUTOSAVE_SECONDS = 180

local busy = {} -- players with a request in progress

---------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "EconomyRemotes"

local walletUpdate = Instance.new("RemoteEvent")
walletUpdate.Name = "WalletUpdate"
walletUpdate.Parent = remotes

local request = Instance.new("RemoteFunction")
request.Name = "EconomyRequest"
request.Parent = remotes

remotes.Parent = ReplicatedStorage

local function pushSummary(player)
	local summary = PlayerData.GetSummary(player)
	if summary then
		walletUpdate:FireClient(player, summary)
	end
end
PlayerData.Changed = pushSummary

---------------------------------------------------------------------
-- Joining and leaving
---------------------------------------------------------------------
local function onJoin(player)
	if PlayerData.Load(player) then
		PlayerData.GrantLaunchGift(player) -- (players who already had a starter)
		pushSummary(player)
	end
end

Players.PlayerAdded:Connect(onJoin)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onJoin, player)
end

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
	PlayerData.Release(player)
end)

-- Save everyone when the server shuts down
game:BindToClose(function()
	-- save and let go of everyone's save, and wait for saves still running
	-- for players who just left (shutdown allows about 30 seconds)
	PlayerData.ReleaseAll(25)
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			PlayerData.Save(player)
		end
	end
end)

---------------------------------------------------------------------
-- Requests from players (checked here; the client can only ask)
---------------------------------------------------------------------
local handlers = {}

function handlers.GetOdds()
	return true, Packs.GetOddsTable()
end

function handlers.GetSummary(player)
	return true, PlayerData.GetSummary(player)
end

function handlers.OpenPack(player, args)
	return PlayerData.OpenPack(player, args.Currency)
end

function handlers.GetExtras(player)
	local extras, total = PlayerData.GetExtras(player)
	return true, { Extras = extras, Shards = total }
end

function handlers.BreakDownExtras(player)
	return PlayerData.BreakDownExtras(player)
end

function handlers.ExchangeTokens(player, args)
	return PlayerData.ExchangeTokens(player, args.CardId)
end

-- Deck names are typed by players, so Roblox requires filtering them.
-- Filtered for everyone, since opponents and binder visitors may see them.
local function filterName(player, name)
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		return result
	end
	if RunService:IsStudio() then
		return name -- filtering can be unavailable in Studio; only you see it there
	end
	return nil
end

function handlers.SaveDeck(player, args)
	local name = type(args.Name) == "string" and args.Name or ""
	name = name:gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		return false, "Give your deck a name."
	end
	if #name > PlayerData.MaxDeckNameLength then
		return false, ("Deck names can be up to %d letters."):format(PlayerData.MaxDeckNameLength)
	end
	local filtered = filterName(player, name)
	if not filtered then
		return false, "Couldn't check that name right now. Try again."
	end
	local ok, result = PlayerData.SaveDeck(player, args, filtered)
	if ok then
		Analytics.Event(player, "deck_saved", args.Format)
	end
	return ok, result
end

function handlers.DeleteDeck(player, args)
	return PlayerData.DeleteDeck(player, args.Id)
end

function handlers.SaveSettings(player, args)
	return PlayerData.SaveSettings(player, args)
end

-- Studio-only testing shortcuts
local studioHandlers = {}

function studioHandlers.DevGrantCoins(player)
	return true, PlayerData.GrantCoins(player, 500)
end

-- (lets you try tickets and boxes in Studio without spending Robux)
function studioHandlers.DevGrantTickets(player)
	return PlayerData.DevGrantTickets(player)
end

function studioHandlers.DevGrantAllFinishes(player)
	return PlayerData.DevGrantAllFinishes(player)
end

-- wipes this account's save back to a brand-new player's (to test onboarding),
-- then sends them out so every screen starts fresh on the next Play
function studioHandlers.DevResetProgress(player)
	local ok = PlayerData.DevReset(player)
	if ok then
		task.delay(1, function()
			if player.Parent then
				player:Kick("Progress reset. Press Play again to start as a new player.")
			end
		end)
	end
	return ok, ok and "reset" or "Couldn't save the reset. Try again."
end

function studioHandlers.DevGrantStarter(player, args)
	return PlayerData.GrantStarter(player, args.Deck)
end

request.OnServerInvoke = function(player, kind, args)
	if not RateLimit.Allow(player, "Economy", 12, 2) then
		return false, "Slow down a little."
	end
	if type(kind) ~= "string" then
		return false, "Bad request."
	end
	if type(args) ~= "table" then
		args = {}
	end
	local handler = handlers[kind]
	if not handler and RunService:IsStudio() then
		handler = studioHandlers[kind]
	end
	if not handler then
		return false, "Unknown request."
	end
	if not PlayerData.IsLoaded(player) then
		return false, "Your cards haven't loaded yet."
	end
	if busy[player] then
		return false, "One moment..."
	end
	busy[player] = true
	local ok, okResult, result = pcall(handler, player, args)
	busy[player] = nil
	if not ok then
		warn("PlayerDataServer: " .. kind .. " failed: " .. tostring(okResult))
		return false, "Something went wrong. Try again."
	end
	return okResult, result
end