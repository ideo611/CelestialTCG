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

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local Packs = require(ReplicatedStorage:WaitForChild("Packs"))
local Singles = require(ReplicatedStorage:WaitForChild("Singles"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local RateLimit = require(ServerScriptService:WaitForChild("RateLimit"))
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

-- The singles case: today's stock in the case, and a prompt to browse it
local singlesPrompt = Instance.new("ProximityPrompt")
singlesPrompt.Name = "SinglesPrompt"
singlesPrompt.ActionText = "Browse singles"
singlesPrompt.ObjectText = "Singles case"
singlesPrompt.HoldDuration = 0
singlesPrompt.MaxActivationDistance = 12
singlesPrompt.RequiresLineOfSight = false
singlesPrompt.Parent = Building.SinglesCase
singlesPrompt.Triggered:Connect(function(player)
	shopEvent:FireClient(player, { Kind = "OpenShop", Tab = "Singles" })
end)

-- The starter deck table: browse every faction's starter, then claim one
local starterPrompt = Instance.new("ProximityPrompt")
starterPrompt.Name = "StarterPrompt"
starterPrompt.ActionText = "Browse starter decks"
starterPrompt.ObjectText = "Starter deck table"
starterPrompt.HoldDuration = 0
starterPrompt.MaxActivationDistance = 12
starterPrompt.RequiresLineOfSight = false
starterPrompt.Parent = Building.StarterTable
starterPrompt.Triggered:Connect(function(player)
	shopEvent:FireClient(player, { Kind = "OpenStarters" })
end)

-- Nova the shop cat: anyone can pet her (hearts float up for everyone to see)
if Building.Cat then
	local petPrompt = Instance.new("ProximityPrompt")
	petPrompt.Name = "PetPrompt"
	petPrompt.ActionText = "Pet"
	petPrompt.ObjectText = "Nova the shop cat"
	petPrompt.HoldDuration = 0.4
	petPrompt.MaxActivationDistance = 8
	petPrompt.RequiresLineOfSight = false
	petPrompt.Parent = Building.Cat
	local hearts = Instance.new("BillboardGui")
	hearts.Name = "CatHearts"
	hearts.Size = UDim2.fromScale(3, 1.6)
	hearts.StudsOffset = Vector3.new(0, 1.6, 0)
	hearts.MaxDistance = 50
	hearts.AlwaysOnTop = false
	hearts.Enabled = false
	local heartsText = Instance.new("TextLabel")
	heartsText.Name = "HeartsText"
	heartsText.Size = UDim2.fromScale(1, 1)
	heartsText.BackgroundTransparency = 1
	heartsText.TextScaled = true
	heartsText.Font = Enum.Font.GothamBold
	heartsText.TextColor3 = Color3.fromRGB(255, 120, 170)
	heartsText.TextStrokeTransparency = 0.4
	heartsText.Text = ""
	heartsText.Parent = hearts
	hearts.Parent = Building.Cat
	local PURRS = { "purr...", "prrrrr", "mrrp?", "*slow blink*", "purr purr" }
	local petCount = 0
	petPrompt.Triggered:Connect(function(player)
		petCount = petCount + 1
		local mine = petCount
		heartsText.Text = utf8.char(0x2665) .. " " .. PURRS[petCount % #PURRS + 1] .. " " .. utf8.char(0x2665)
		hearts.Enabled = true
		task.delay(2.5, function()
			if petCount == mine then
				hearts.Enabled = false
			end
		end)
	end)
end

local stockedDay = nil
local function restockCase()
	local day = Singles.Today()
	if day ~= stockedDay then
		stockedDay = day
		Building.ShowSingles(Singles.StockForDay(day))
	end
end
restockCase()
task.spawn(function()
	while true do
		task.wait(30)
		restockCase()
	end
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
	local tier = pull.Finish == "Mythic" and "Mythic" or ANNOUNCE_POOLS[pull.Pool]
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
		if ANNOUNCE_POOLS[pull.Pool] or pull.Finish == "Mythic" then
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
local offers = {} -- [player] = { PackType, Fronts = { cardId, ... } }: the packs a player was offered

Players.PlayerRemoving:Connect(function(player)
	restrictedCache[player] = nil
	offers[player] = nil
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

function handlers.GetOdds(player, args)
	local packType = type(args.PackType) == "string" and EconomyConfig.GetPackType(args.PackType)
	return true, Packs.GetOddsTable(packType and packType.Id or nil)
end

-- Buying a pack: first the shop offers a few packs to pick from (each with a
-- random card's art on the front), then the player buys the one they pick.
-- The front is only a look: contents are rolled when the pack is opened, with
-- the same odds whichever pack is picked.
local frontRandom = Random.new()
local function frontRng(n)
	return frontRandom:NextInteger(1, n)
end

function handlers.PackOffer(player, args)
	local packType = type(args.PackType) == "string" and EconomyConfig.GetPackType(args.PackType)
	if not packType then
		return false, "Pick a pack."
	end
	-- the same coin check OpenPack makes, so nobody picks a pack they can't buy
	if args.Currency == "Coins" and EconomyConfig.CoinsSoldForRobux and PlayerData.IsRestricted(player) then
		return false, "Packs can't be bought with coins in your region. You can still open packs with Star Shards."
	end
	local fronts = Packs.PickFronts(packType.Id, frontRng, EconomyConfig.PackChoices)
	offers[player] = { PackType = packType.Id, Fronts = fronts }
	return true, { PackType = packType.Id, Fronts = fronts }
end

function handlers.BuyPack(player, args)
	local packTypeId = type(args.PackType) == "string" and args.PackType or EconomyConfig.DefaultPackType
	if not EconomyConfig.GetPackType(packTypeId) then
		return false, "Pick a pack."
	end
	-- the front comes from the offer the player was shown (if any)
	local front
	local offer = offers[player]
	if offer and offer.PackType == packTypeId and type(args.Choice) == "number" then
		front = offer.Fronts[args.Choice]
	end
	local ok, pulls = PlayerData.OpenPack(player, args.Currency, packTypeId)
	if not ok then
		return false, pulls
	end
	offers[player] = nil
	return true, { PackType = packTypeId, Front = front, Pulls = pulls }
end

-- Robux products: what's for sale and whether this player can buy them
-- (tickets and boxes hold random cards, so they're blocked where paid random
-- items are restricted)
-- The price Roblox will actually charge (set on the Creator Dashboard),
-- looked up once per server; EconomyConfig's number is only a fallback.
local livePrices = {}
local function priceOf(product)
	if product.ProductId == 0 then
		return product.Robux
	end
	if livePrices[product.ProductId] == nil then
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(product.ProductId, Enum.InfoType.Product)
		end)
		livePrices[product.ProductId] = (ok and type(info) == "table" and tonumber(info.PriceInRobux)) or false
	end
	return livePrices[product.ProductId] or product.Robux
end

function handlers.GetProducts(player)
	local restricted = PlayerData.IsRestricted(player)
	local list = {}
	for _, key in ipairs(EconomyConfig.ProductOrder) do
		local product = EconomyConfig.Products[key]
		table.insert(list, {
			Key = key,
			Name = product.Name,
			Robux = priceOf(product),
			Ready = product.ProductId ~= 0,
		})
	end
	return true, { Products = list, Restricted = restricted }
end

function handlers.BuyProduct(player, args)
	local product = type(args.Product) == "string" and EconomyConfig.Products[args.Product]
	if not product then
		return false, "Unknown item."
	end
	if product.ProductId == 0 then
		return false, "Coming soon!"
	end
	if PlayerData.IsRestricted(player) then
		return false, "Booster tickets and boxes can't be bought in your region. You can still earn packs by playing."
	end
	MarketplaceService:PromptProductPurchase(player, product.ProductId)
	return true
end

-- The launch gift: tell them (once the screen has had a moment to load)
PlayerData.GiftGiven = function(player, faction)
	task.wait(4)
	if player.Parent then
		shopEvent:FireClient(player, { Kind = "Announcement", Tier = "Legendary",
			Text = ("Launch gift! A free %s Booster Box is waiting at the Card Shop."):format(faction) })
	end
end

function handlers.OpenBox(player, args)
	return PlayerData.OpenBox(player, args.PackType)
end

function handlers.GetSingles(player)
	local day = Singles.Today()
	return true, {
		Day = day,
		Stock = Singles.StockForDay(day),
		Bought = PlayerData.SinglesBoughtToday(player),
		RestockIn = Singles.SecondsUntilRestock(),
	}
end

function handlers.BuySingle(player, args)
	return PlayerData.BuySingle(player, args.CardId)
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
	if not RateLimit.Allow(player, "Shop", 12, 2) then
		return false, "Slow down a little."
	end
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
