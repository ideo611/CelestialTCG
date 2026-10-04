--[[
	ShopServer (Script)
	Location: ServerScriptService > ShopServer

	The Card Shop:
	  - Puts the "Open the Card Shop" prompt on the counter inside the shop
	    building (built by CardShopBuilding).
	  - Handles buying and opening packs, starter decks, Star Token trades,
	    breaking down extras, and buying/equipping playmats.
	  - When someone opens a pack, their cards flip one by one above their head
	    so nearby players can watch. Big pulls are announced to the whole server.
]]

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local Packs = require(ReplicatedStorage:WaitForChild("Packs"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local Building = require(ServerScriptService:WaitForChild("CardShopBuilding"))

local REVEAL_SECONDS = 0.8      -- time between cards flipping for watchers
local DISPLAY_AFTER_SECONDS = 6 -- how long the pulls stay up afterwards
local ANNOUNCE_POOLS = {
	LegendaryDeckCard = "Legendary",
	CommanderOrCelestial = "Legendary",
	Mythic = "Mythic",
}

---------------------------------------------------------------------
-- Remotes
---------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "ShopRemotes"
local shopEvent = Instance.new("RemoteEvent")
shopEvent.Name = "ShopEvent"
shopEvent.Parent = remotes
local shopRequest = Instance.new("RemoteFunction")
shopRequest.Name = "ShopRequest"
shopRequest.Parent = remotes
remotes.Parent = ReplicatedStorage

---------------------------------------------------------------------
-- The shop in the world (the building itself is CardShopBuilding)
---------------------------------------------------------------------
local counter = Building.Counter

local prompt = Instance.new("ProximityPrompt")
prompt.Name = "ShopPrompt"
prompt.ActionText = "Open the Card Shop"
prompt.ObjectText = "Checkout counter"
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 12
prompt.RequiresLineOfSight = false
prompt.Parent = counter

prompt.Triggered:Connect(function(player)
	shopEvent:FireClient(player, { Kind = "OpenShop" })
end)

---------------------------------------------------------------------
-- Paid random items check (only matters once coins are sold for Robux)
---------------------------------------------------------------------
local restrictedCache = {}

PlayerData.IsRestricted = function(player)
	if restrictedCache[player] ~= nil then
		return restrictedCache[player]
	end
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	-- If the check fails, play it safe and treat the player as restricted
	local restricted = not ok or info.ArePaidRandomItemsRestricted == true
	restrictedCache[player] = restricted
	return restricted
end

---------------------------------------------------------------------
-- Watching pulls: cards flip above the opener's head
---------------------------------------------------------------------
local activeDisplays = {}

local function announce(player, pull)
	local card = CardDatabase.GetCard(pull.CardId)
	local tier = ANNOUNCE_POOLS[pull.Pool]
	local finish = CardVisuals.FinishNames[pull.Finish] or pull.Finish
	shopEvent:FireAllClients({
		Kind = "Announcement",
		Tier = tier,
		Text = ("%s pulled %s (%s)!"):format(player.DisplayName, card.Name, finish),
	})
end

PlayerData.PackOpened = function(player, pulls)
	local character = player.Character
	local anchor = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))

	-- Big pulls get announced when that card flips, so nobody spoils the reveal
	for index, pull in ipairs(pulls) do
		if ANNOUNCE_POOLS[pull.Pool] then
			task.delay(index * REVEAL_SECONDS, announce, player, pull)
		end
	end

	if not anchor then
		return
	end
	if activeDisplays[player] then
		activeDisplays[player]:Destroy()
	end
	local board = Instance.new("BillboardGui")
	board.Name = "PackReveal"
	board.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	board.Size = UDim2.fromScale(10, 2.8)
	board.StudsOffset = Vector3.new(0, 4.5, 0)
	board.MaxDistance = 80
	local slots = {}
	for i = 1, #pulls do
		local slot = Instance.new("Frame")
		slot.Name = "Reveal_" .. i
		slot.Position = UDim2.new((i - 1) / #pulls, 2, 0, 0)
		slot.Size = UDim2.new(1 / #pulls, -4, 1, 0)
		CardVisuals.DrawFaceDown(slot, "?")
		slot.Parent = board
		slots[i] = slot
	end
	board.Parent = anchor
	activeDisplays[player] = board

	for i, pull in ipairs(pulls) do
		task.wait(REVEAL_SECONDS)
		if board.Parent == nil then
			return
		end
		local slot = slots[i]
		for _, child in ipairs(slot:GetChildren()) do
			child:Destroy()
		end
		CardVisuals.Draw(slot, pull.CardId, { Finish = pull.Finish, HideCost = true })
	end
	task.wait(DISPLAY_AFTER_SECONDS)
	if activeDisplays[player] == board then
		board:Destroy()
		activeDisplays[player] = nil
	end
end

local busy = {}

Players.PlayerRemoving:Connect(function(player)
	restrictedCache[player] = nil
	busy[player] = nil
	if activeDisplays[player] then
		activeDisplays[player]:Destroy()
		activeDisplays[player] = nil
	end
end)

---------------------------------------------------------------------
-- Requests from the shop screen
---------------------------------------------------------------------
local handlers = {}

function handlers.GetOdds()
	return true, Packs.GetOddsTable()
end

function handlers.BuyPack(player, args)
	return PlayerData.OpenPack(player, args.Currency)
end

function handlers.ClaimStarter(player, args)
	return PlayerData.ClaimStarter(player, args.Deck)
end

function handlers.ExchangeTokens(player, args)
	return PlayerData.ExchangeTokens(player, args.CardId)
end

function handlers.GetExtras(player)
	local extras, total = PlayerData.GetExtras(player)
	return true, { Extras = extras, Shards = total }
end

function handlers.BreakDownExtras(player)
	return PlayerData.BreakDownExtras(player)
end

function handlers.BuyMat(player, args)
	return PlayerData.BuyMat(player, args.MatId)
end

function handlers.EquipMat(player, args)
	return PlayerData.EquipMat(player, args.MatId)
end

shopRequest.OnServerInvoke = function(player, kind, args)
	if type(kind) ~= "string" or not handlers[kind] then
		return false, "Unknown request."
	end
	if type(args) ~= "table" then
		args = {}
	end
	if not PlayerData.IsLoaded(player) then
		return false, "Your cards haven't loaded yet."
	end
	if busy[player] then
		return false, "One moment..."
	end
	busy[player] = true
	local ok, okResult, result = pcall(handlers[kind], player, args)
	busy[player] = nil
	if not ok then
		warn("ShopServer: " .. kind .. " failed: " .. tostring(okResult))
		return false, "Something went wrong. Try again."
	end
	return okResult, result
end