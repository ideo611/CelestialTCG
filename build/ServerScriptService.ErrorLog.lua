--[[
	ErrorLog (Script)
	Location: ServerScriptService > ErrorLog

	Catches script errors in the live game so launch bugs can be found:
	  - server errors (ScriptContext.Error)
	  - players' screen errors, reported by ClientReporter (rate limited)
	Identical errors are counted instead of repeated. Every few minutes (and
	when the server shuts down) the batch is saved to the "ErrorLog" data store
	under e_YYYYMMDD_<server>_<batch #>, with the build version, so you can see
	which update an error came from. Errors from players' screens also count as
	an "error" analytics event (CustomField02 = "Client").

	In Studio nothing is saved (errors show in Output anyway).
	Also check Creator Dashboard > Error Report after each update.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local ServerScriptService = game:GetService("ServerScriptService")

local BuildInfo = require(ReplicatedStorage:WaitForChild("BuildInfo"))
local RateLimit = require(ServerScriptService:WaitForChild("RateLimit"))
local Analytics = require(ServerScriptService:WaitForChild("Analytics"))

local STORE_NAME = "ErrorLog"
local SAVE_EVERY = 300   -- seconds
local MAX_DISTINCT = 100 -- distinct errors kept per batch

local pending = {}   -- [key] = entry
local count = 0
local batchNumber = 0

local function record(source, message, trace, player)
	message = tostring(message or ""):sub(1, 300)
	trace = tostring(trace or ""):sub(1, 500)
	local key = source .. "|" .. message
	local entry = pending[key]
	if entry then
		entry.Count = entry.Count + 1
		return
	end
	if count >= MAX_DISTINCT then
		return
	end
	count = count + 1
	pending[key] = {
		Source = source,
		Message = message,
		Trace = trace,
		Count = 1,
		Device = player and Analytics.DeviceOf(player) or nil,
		Build = BuildInfo.BuildVersion,
		Time = os.time(),
	}
	if player then
		Analytics.Event(player, "error", source)
	end
end

ScriptContext.Error:Connect(function(message, trace)
	record("Server", message, trace)
end)

-- Players' screens report their own errors here
local remotes = Instance.new("Folder")
remotes.Name = "ErrorRemotes"
local report = Instance.new("RemoteEvent")
report.Name = "ReportError"
report.Parent = remotes
remotes.Parent = ReplicatedStorage

report.OnServerEvent:Connect(function(player, message, trace)
	if type(message) ~= "string" or not RateLimit.Allow(player, "ErrorReport", 10, 60) then
		return
	end
	record("Client", message, type(trace) == "string" and trace or "", player)
end)

local function save()
	if count == 0 then
		return
	end
	local batch = {}
	for _, entry in pairs(pending) do
		table.insert(batch, entry)
	end
	pending, count = {}, 0
	if RunService:IsStudio() then
		return
	end
	batchNumber = batchNumber + 1
	local server = game.JobId ~= "" and game.JobId:sub(1, 8) or "local"
	local key = ("e_%s_%s_%d"):format(os.date("!%Y%m%d"), server, batchNumber)
	local ok, err = pcall(function()
		DataStoreService:GetDataStore(STORE_NAME):SetAsync(key, { Build = BuildInfo.BuildVersion, Errors = batch })
	end)
	if not ok then
		warn("ErrorLog: couldn't save: " .. tostring(err))
	end
end

task.spawn(function()
	while true do
		task.wait(SAVE_EVERY)
		save()
	end
end)

game:BindToClose(save)
