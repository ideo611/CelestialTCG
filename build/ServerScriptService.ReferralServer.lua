--[[
	ReferralServer (Script)
	Location: ServerScriptService > ReferralServer

	Invite a friend (EconomyConfig.Referral): when a brand-new player who
	joined from your invite (Roblox's invite prompt or invite menu: their
	GetJoinData().ReferredByPlayerId) finishes their first full match vs the
	bot, you both get Booster Pack Tickets.

	  - The friend's tickets are paid right away (PlayerData.RecordMatch).
	  - The inviter may be offline or in another server, so their tickets are
	    recorded in the "Referrals" DataStore under the inviter's UserId:
	      { Earned = tickets earned in total, Count = friends rewarded,
	        Friends = { [friendUserId] = true } }
	    The inviter collects what they're owed when they join, or right away
	    if they're online (MessagingService tells their server). Collecting
	    is safe to repeat: PlayerData.ReferralClaimed remembers what's been paid.
	  - Each friend counts once, and only MaxFriends friends pay an inviter.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")

local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))
local PlayerData = require(ServerScriptService:WaitForChild("PlayerData"))
local Analytics = require(ServerScriptService:WaitForChild("Analytics"))
local RateLimit = require(ServerScriptService:WaitForChild("RateLimit"))

local CONFIG = EconomyConfig.Referral
local STORE_NAME = "Referrals_v1"
local TOPIC = "ReferralEarned"

local store
pcall(function()
	store = DataStoreService:GetDataStore(STORE_NAME)
end)

local MessagingService
pcall(function()
	MessagingService = game:GetService("MessagingService")
end)

---------------------------------------------------------------------
-- Remotes: the Invite window asks for the player's progress
---------------------------------------------------------------------
local remotes = Instance.new("Folder")
remotes.Name = "ReferralRemotes"
local request = Instance.new("RemoteFunction")
request.Name = "ReferralRequest"
request.Parent = remotes
remotes.Parent = ReplicatedStorage

local function announce(player, text)
	local shopRemotes = ReplicatedStorage:FindFirstChild("ShopRemotes")
	local shopEvent = shopRemotes and shopRemotes:FindFirstChild("ShopEvent")
	if shopEvent and player.Parent then
		shopEvent:FireClient(player, { Kind = "Announcement", Tier = "Legendary", Text = text })
	end
end

local function nameOf(userId)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	return ok and name or "your friend"
end

local function retry(fn, tries)
	for attempt = 1, tries or 4 do
		local ok, a, b = pcall(fn)
		if ok then
			return true, a, b
		end
		warn("ReferralServer: " .. tostring(a))
		task.wait(2 * attempt)
	end
	return false
end

---------------------------------------------------------------------
-- Inviter side: collect what friends have earned them
---------------------------------------------------------------------
local collecting = {}
local function collect(player)
	if not store or collecting[player] or not PlayerData.IsLoaded(player) then
		return
	end
	collecting[player] = true
	local ok, entry = retry(function()
		return store:GetAsync(tostring(player.UserId))
	end, 3)
	collecting[player] = nil
	if ok and type(entry) == "table" and player.Parent then
		local paid = PlayerData.CollectReferralTickets(player, entry.Earned or 0)
		if paid > 0 then
			announce(player, ("A friend you invited finished their first match! +%d Booster Pack Tickets."):format(paid))
		end
	end
end

---------------------------------------------------------------------
-- Friend side: their first full match vs the bot is done (they're paid
-- already); record the inviter's tickets
---------------------------------------------------------------------
local function credit(friend, inviterId)
	if not store then
		return
	end
	local result -- "added", "already" or "full"
	local ok = retry(function()
		store:UpdateAsync(tostring(inviterId), function(entry)
			entry = type(entry) == "table" and entry or { Earned = 0, Count = 0, Friends = {} }
			entry.Friends = entry.Friends or {}
			local key = tostring(friend.UserId)
			if entry.Friends[key] then
				result = "already"
				return nil -- (no change)
			end
			if (entry.Count or 0) >= CONFIG.MaxFriends then
				result = "full"
				return nil
			end
			entry.Friends[key] = true
			entry.Count = (entry.Count or 0) + 1
			entry.Earned = (entry.Earned or 0) + CONFIG.Tickets
			result = "added"
			return entry
		end)
	end)
	if not ok then
		return -- stays un-credited: tried again next time they join
	end
	PlayerData.MarkReferralCredited(friend)
	Analytics.Event(friend, "referral_credit", result or "?", inviterId)
	if result ~= "added" then
		return
	end
	local inviter = Players:GetPlayerByUserId(inviterId)
	if inviter then
		collect(inviter)
	elseif MessagingService then
		pcall(function()
			MessagingService:PublishAsync(TOPIC, inviterId)
		end)
	end
end

PlayerData.ReferralDone = function(friend, inviterId)
	announce(friend, ("First match done! You and %s each get %d Booster Pack Tickets."):format(
		nameOf(inviterId), CONFIG.Tickets))
	credit(friend, inviterId)
end

if MessagingService then
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message)
				local player = Players:GetPlayerByUserId(tonumber(message.Data) or 0)
				if player then
					collect(player)
				end
			end)
		end)
	end)
end

---------------------------------------------------------------------
-- Joining
---------------------------------------------------------------------
local function onJoin(player)
	local started = os.clock()
	while player.Parent and not PlayerData.IsLoaded(player) and os.clock() - started < 60 do
		task.wait(0.5)
	end
	if not player.Parent or not PlayerData.IsLoaded(player) then
		return
	end
	local data = PlayerData.Get(player)
	-- a brand-new player who came from someone's invite
	local inviterId = 0
	pcall(function()
		inviterId = tonumber(player:GetJoinData().ReferredByPlayerId) or 0
	end)
	if inviterId ~= 0 and PlayerData.SetReferredBy(player, inviterId) then
		Analytics.Event(player, "referral_joined", tostring(inviterId))
		task.delay(6, function()
			announce(player, ("Invited by %s! Finish your first match vs the bot and you both get %d Booster Pack Tickets."):format(
				nameOf(inviterId), CONFIG.Tickets))
		end)
	end
	-- their first match was done but the inviter's tickets weren't recorded yet
	if data and data.Referral.By ~= 0 and data.Referral.Done and not data.Referral.Credited then
		task.spawn(credit, player, data.Referral.By)
	end
	collect(player)
end

Players.PlayerAdded:Connect(onJoin)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onJoin, player)
end
Players.PlayerRemoving:Connect(function(player)
	collecting[player] = nil
end)

---------------------------------------------------------------------
-- The Invite window: progress
---------------------------------------------------------------------
request.OnServerInvoke = function(player, kind)
	if not RateLimit.Allow(player, "Referral", 10, 10) then
		return false, "Slow down a moment."
	end
	if kind ~= "Status" then
		return false, "Unknown request."
	end
	local data = PlayerData.Get(player)
	local count = 0
	if store then
		local ok, entry = pcall(function()
			return store:GetAsync(tostring(player.UserId))
		end)
		if ok and type(entry) == "table" then
			count = entry.Count or 0
		end
	end
	return true, {
		Friends = count,
		MaxFriends = CONFIG.MaxFriends,
		Tickets = CONFIG.Tickets,
		InvitedBy = data and data.Referral.By ~= 0 and not data.Referral.Done and nameOf(data.Referral.By) or nil,
	}
end
