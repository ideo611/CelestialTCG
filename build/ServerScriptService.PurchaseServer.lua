--[[
	PurchaseServer (Script)
	Location: ServerScriptService > PurchaseServer

	Robux purchases (Developer Products: Booster Pack Tickets and Booster
	Boxes, set up in EconomyConfig.Products).

	The one rule that matters: a purchase is only confirmed to Roblox
	(PurchaseGranted) after it's been saved in the player's data. Until then
	Roblox keeps the purchase open and asks again later (when they rejoin),
	so a failed save never loses something they paid for. Each purchase id is
	recorded in their save, so asking again never grants it twice.

	(Only this script may set MarketplaceService.ProcessReceipt.)
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local Analytics = require(ServerScriptService:WaitForChild("Analytics"))

local shopEvent = ReplicatedStorage:WaitForChild("ShopRemotes"):WaitForChild("ShopEvent")

local LOAD_WAIT_SECONDS = 20 -- how long a purchase waits for the buyer's cards to load

local function waitForData(player)
	local started = os.clock()
	while player.Parent and not PlayerData.IsLoaded(player) and os.clock() - started < LOAD_WAIT_SECONDS do
		task.wait(0.5)
	end
	return player.Parent ~= nil and PlayerData.IsLoaded(player)
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- they left: Roblox asks again next time
	end
	local key = EconomyConfig.ProductKeyForId(receipt.ProductId)
	if not key then
		warn("PurchaseServer: unknown product id " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not waitForData(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local status, problem = PlayerData.GrantPurchase(player, receipt.PurchaseId, key)
	if not status then
		warn("PurchaseServer: couldn't grant " .. key .. ": " .. tostring(problem))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- confirmed only once it's saved
	if not PlayerData.Save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if status == "granted" then
		local product = EconomyConfig.Products[key]
		Analytics.Event(player, "robux_purchase", key, product.Robux)
		shopEvent:FireClient(player, { Kind = "PurchaseDone", Product = key, Name = product.Name })
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = function(receipt)
	local ok, result = pcall(processReceipt, receipt)
	if not ok then
		warn("PurchaseServer: " .. tostring(result))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return result
end
