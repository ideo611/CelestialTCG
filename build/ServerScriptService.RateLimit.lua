--[[
	RateLimit (ModuleScript)
	Location: ServerScriptService > RateLimit

	Stops a player (or an exploit) from spamming a remote. Each player gets a
	small allowance per bucket that refills over time:

	    if not RateLimit.Allow(player, "Shop", 10, 2) then return end
	    -- at most 10 requests every 2 seconds for "Shop"

	Normal play never comes close to these limits; they only cut off spam.
]]

local Players = game:GetService("Players")

local RateLimit = {}
RateLimit.Enabled = true -- (tests switch it off to hammer remotes on purpose)

local buckets = {} -- [player] = { [name] = { Count, WindowStart } }

function RateLimit.Allow(player, name, maxCount, windowSeconds)
	if not RateLimit.Enabled then
		return true
	end
	local now = os.clock()
	local mine = buckets[player]
	if not mine then
		mine = {}
		buckets[player] = mine
	end
	local bucket = mine[name]
	if not bucket or now - bucket.WindowStart >= windowSeconds then
		bucket = { Count = 0, WindowStart = now }
		mine[name] = bucket
	end
	bucket.Count = bucket.Count + 1
	if bucket.Count > maxCount then
		if bucket.Count == maxCount + 1 then
			warn(("RateLimit: %s is sending too many %s requests"):format(player.Name, name))
		end
		return false
	end
	return true
end

Players.PlayerRemoving:Connect(function(player)
	buckets[player] = nil
end)

return RateLimit
