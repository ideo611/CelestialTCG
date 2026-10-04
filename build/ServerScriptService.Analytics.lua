--[[
	Analytics (ModuleScript)
	Location: ServerScriptService > Analytics

	Sends launch analytics to Roblox (Creator Dashboard > Analytics). Events
	only go out from published games; in Studio they're kept in Analytics.Recent
	(and printed if Analytics.PrintInStudio is true) so you can check them.

	Three kinds:
	  Analytics.Event(player, name, detail, value)
	      a custom event (Custom Events dashboard)
	  Analytics.Onboarding(player, name, detail)
	      a step of the new-player funnel (Onboarding Funnel dashboard),
	      sent once per player ever. Steps are listed in ONBOARDING below.
	  Analytics.Funnel(player, funnelName, sessionId, step, stepName, detail)
	      a step of a repeatable funnel (the tutorial uses "Tutorial")

	Every event carries three custom fields:
	  CustomField01 = device class (Phone / Tablet / PC / Console / Unknown)
	  CustomField02 = detail (faction, match type, result... whatever fits)
	  CustomField03 = build version (ReplicatedStorage > BuildInfo)

	Device class: each player's screen reports its input and size once
	(AnalyticsRemotes.Track, "Device"); it's kept as the DeviceClass attribute.
	Players' screens can also report a few UI events with Analytics.Track
	(only the names in CLIENT_EVENTS are accepted).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local BuildInfo = require(ReplicatedStorage:WaitForChild("BuildInfo"))
local RateLimit = require(ServerScriptService:WaitForChild("RateLimit"))

local Analytics = {}
Analytics.Recent = {}          -- last events (Studio and tests)
Analytics.PrintInStudio = false
Analytics.GetData = nil        -- set by PlayerData: returns the player's save (onboarding is sent once ever)

-- The new-player funnel, in order. Steps can be skipped (Roblox counts later
-- steps as completing earlier ones).
local ONBOARDING = {
	"load_complete",
	"starter_screen_view",
	"starter_claimed",
	"tutorial_started",
	"tutorial_finished",      -- completed or skipped
	"first_match_started",
	"first_match_completed",
	"second_match_started",
	"first_pack_opened",
}
local ONBOARDING_STEP = {}
for i, name in ipairs(ONBOARDING) do
	ONBOARDING_STEP[name] = i
end
Analytics.OnboardingSteps = ONBOARDING

-- UI events players' screens may report
local CLIENT_EVENTS = {
	starter_screen_view = true,
	deck_editor_opened = true,
	binder_opened = true,
	shop_opened = true,
	collection_opened = true,
	rulebook_opened = true,
}

local service = nil
pcall(function()
	service = game:GetService("AnalyticsService")
end)
local sending = service ~= nil and not RunService:IsStudio()

local fieldKeys = nil
pcall(function()
	fieldKeys = {
		Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
		Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
		Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
	}
end)

function Analytics.DeviceOf(player)
	return player and player:GetAttribute("DeviceClass") or "Unknown"
end

local function fields(player, detail)
	if not fieldKeys then
		return nil
	end
	return {
		[fieldKeys[1]] = Analytics.DeviceOf(player),
		[fieldKeys[2]] = detail ~= nil and tostring(detail) or "",
		[fieldKeys[3]] = BuildInfo.BuildVersion,
	}
end

local function remember(entry)
	table.insert(Analytics.Recent, entry)
	if #Analytics.Recent > 300 then
		table.remove(Analytics.Recent, 1)
	end
	if Analytics.PrintInStudio and RunService:IsStudio() then
		print(("[Analytics] %s %s %s"):format(entry.Kind, entry.Name, tostring(entry.Detail or "")))
	end
end

-- Sends an event. Right after joining, the player's device class may not be
-- known yet (their screen reports it within a moment): wait up to 5 seconds
-- for it so early funnel steps can be split by device too.
local function send(fn, player)
	if not sending then
		return
	end
	local function go()
		local ok, err = pcall(fn)
		if not ok then
			warn("Analytics: " .. tostring(err))
		end
	end
	if player and player:GetAttribute("DeviceClass") == nil then
		task.spawn(function()
			local started = os.clock()
			while player.Parent and player:GetAttribute("DeviceClass") == nil and os.clock() - started < 5 do
				task.wait(0.25)
			end
			go()
		end)
	else
		go()
	end
end

-- A custom event (value defaults to 1)
function Analytics.Event(player, name, detail, value)
	if not player then
		return
	end
	remember({ Kind = "Event", Player = player.UserId, Name = name, Detail = detail })
	send(function()
		service:LogCustomEvent(player, name, value or 1, fields(player, detail))
	end, player)
end

-- A new-player funnel step; sent once per player (also kept as a custom event)
function Analytics.Onboarding(player, name, detail)
	local step = ONBOARDING_STEP[name]
	if not player or not step then
		return
	end
	local data = Analytics.GetData and Analytics.GetData(player)
	if data then
		data.Onboarding = data.Onboarding or {}
		data.Onboarding.Logged = data.Onboarding.Logged or {}
		if data.Onboarding.Logged[name] then
			return
		end
		data.Onboarding.Logged[name] = true
	end
	remember({ Kind = "Onboarding", Player = player.UserId, Name = name, Step = step, Detail = detail })
	send(function()
		service:LogOnboardingFunnelStepEvent(player, step, name, fields(player, detail))
	end, player)
	Analytics.Event(player, name, detail)
end

-- A step of a named funnel (e.g. each tutorial step)
function Analytics.Funnel(player, funnelName, sessionId, step, stepName, detail)
	if not player then
		return
	end
	remember({ Kind = "Funnel", Player = player.UserId, Name = funnelName .. ":" .. stepName, Step = step, Detail = detail })
	send(function()
		service:LogFunnelStepEvent(player, funnelName, sessionId or "", step, stepName, fields(player, detail))
	end, player)
end

---------------------------------------------------------------------
-- Reports from players' screens
---------------------------------------------------------------------
local function classify(info)
	if type(info) ~= "table" then
		return "Unknown"
	end
	local touch, keyboard, gamepad = info.Touch == true, info.Keyboard == true, info.Gamepad == true
	local x, y = tonumber(info.ViewX) or 0, tonumber(info.ViewY) or 0
	if gamepad and not touch and not keyboard then
		return "Console"
	end
	if touch and not keyboard then
		return math.min(x, y) < 600 and "Phone" or "Tablet"
	end
	return "PC"
end
Analytics.Classify = classify

local remotes = Instance.new("Folder")
remotes.Name = "AnalyticsRemotes"
local track = Instance.new("RemoteEvent")
track.Name = "Track"
track.Parent = remotes
remotes.Parent = ReplicatedStorage

track.OnServerEvent:Connect(function(player, name, info)
	if type(name) ~= "string" or not RateLimit.Allow(player, "Track", 20, 10) then
		return
	end
	if name == "Device" then
		if player:GetAttribute("DeviceClass") == nil then
			player:SetAttribute("DeviceClass", classify(info))
			Analytics.Event(player, "device_reported", classify(info))
		end
		return
	end
	if not CLIENT_EVENTS[name] then
		return
	end
	local detail = type(info) == "string" and info:sub(1, 40) or nil
	if ONBOARDING_STEP[name] then
		Analytics.Onboarding(player, name, detail)
	else
		Analytics.Event(player, name, detail)
	end
end)

-- Session length (seconds) when a player leaves
local joined = {}
Players.PlayerAdded:Connect(function(player)
	joined[player] = os.clock()
end)
for _, player in ipairs(Players:GetPlayers()) do
	joined[player] = joined[player] or os.clock()
end
Players.PlayerRemoving:Connect(function(player)
	local started = joined[player]
	joined[player] = nil
	if started then
		Analytics.Event(player, "session_end", nil, math.floor(os.clock() - started))
	end
end)

return Analytics
