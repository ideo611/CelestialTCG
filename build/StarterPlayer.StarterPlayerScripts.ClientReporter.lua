--[[
	ClientReporter (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > ClientReporter

	Tells the server two things for launch analytics:
	  - once: what kind of device this is (touch / keyboard / gamepad and the
	    screen size), so every event can be split by Phone / Tablet / PC
	  - any error in this player's scripts (ErrorLog saves them)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")
local UserInputService = game:GetService("UserInputService")

local analyticsRemotes = ReplicatedStorage:WaitForChild("AnalyticsRemotes")
local track = analyticsRemotes:WaitForChild("Track")

task.delay(2, function()
	local camera = workspace.CurrentCamera
	local view = camera and camera.ViewportSize or Vector2.new(0, 0)
	track:FireServer("Device", {
		Touch = UserInputService.TouchEnabled,
		Keyboard = UserInputService.KeyboardEnabled,
		Gamepad = UserInputService.GamepadEnabled,
		ViewX = math.floor(view.X),
		ViewY = math.floor(view.Y),
	})
end)

local reportRemote = ReplicatedStorage:WaitForChild("ErrorRemotes"):WaitForChild("ReportError")
local sent = 0
ScriptContext.Error:Connect(function(message, trace)
	sent = sent + 1
	if sent <= 20 then -- a broken loop shouldn't flood the server
		reportRemote:FireServer(tostring(message), tostring(trace))
	end
end)
