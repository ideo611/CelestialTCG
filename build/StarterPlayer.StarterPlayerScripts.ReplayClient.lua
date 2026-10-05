--[[
	ReplayClient (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > ReplayClient

	Studio only: the "Replays" panel for recording videos. Lists the recorded
	games in ReplayLibrary (tools/replays.py picks close, dramatic games that
	show off specific cards) and plays one on the real battle screen.

	While a replay plays, everything except the battle screen is hidden
	(clean footage), and the keyboard controls it:
	  Space   pause / resume
	  Right   one move at a time (pauses)
	  [ / ]   slower / faster
	  H       show / hide the rest of the screen (and the replay status)
	The battle screen's Leave button stops it.
]]

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("ReplayRemotes", 15)
if not remotes then
	return
end
local request = remotes:WaitForChild("ReplayRequest")

local WHITE = Color3.new(1, 1, 1)
local GOLD = Color3.fromRGB(255, 205, 90)

local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function ask(kind, args)
	local ok, a, b = pcall(function()
		return request:InvokeServer(kind, args or {})
	end)
	if not ok then
		return false, tostring(a)
	end
	return a, b
end

local gui = make("ScreenGui", { Name = "ReplayGui", ResetOnSpawn = false, DisplayOrder = 30,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)

local toggle = make("TextButton", {
	Name = "ReplaysToggle", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -126, 0, 78),
	Size = UDim2.fromOffset(100, 24), BackgroundColor3 = Color3.fromRGB(60, 50, 110), TextColor3 = WHITE,
	Font = Enum.Font.GothamBold, TextSize = 12, Text = "Replays  v",
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, toggle)

local panel = make("Frame", {
	Name = "ReplayPanel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(720, 520), BackgroundColor3 = Color3.fromRGB(22, 18, 44), Visible = false,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0, 12) }, panel)
make("UIStroke", { Color = GOLD, Thickness = 1.5, Transparency = 0.3 }, panel)
make("TextLabel", {
	Name = "Title", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 10), Size = UDim2.new(1, -80, 0, 30),
	Font = Enum.Font.GothamBlack, TextSize = 22, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Replays for videos",
}, panel)
make("TextLabel", {
	Name = "Help", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 40), Size = UDim2.new(1, -36, 0, 34),
	Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(210, 210, 230), TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "While it plays: Space pause, Right arrow one move, [ ] speed, H show/hide everything else. "
		.. "Leave on the battle screen stops it. Everything but the battle screen is hidden for clean footage.",
}, panel)
local closeButton = make("TextButton", {
	Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(36, 30),
	BackgroundColor3 = Color3.fromRGB(170, 60, 60), TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 16, Text = "X",
}, panel)
make("UICorner", { CornerRadius = UDim.new(0, 6) }, closeButton)

local speed = 1
local speedLabel = make("TextLabel", {
	Name = "SpeedLabel", BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 78), Size = UDim2.fromOffset(160, 26),
	Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left,
	Text = "Start speed: 1x",
}, panel)
local function speedButton(name, text, x, change)
	local b = make("TextButton", {
		Name = name, Position = UDim2.fromOffset(x, 78), Size = UDim2.fromOffset(34, 26),
		BackgroundColor3 = Color3.fromRGB(70, 70, 110), TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 16, Text = text,
	}, panel)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	b.Activated:Connect(function()
		local steps = { 0.5, 0.75, 1, 1.25, 1.5, 2 }
		local at = 3
		for i, v in ipairs(steps) do
			if v == speed then
				at = i
			end
		end
		speed = steps[math.clamp(at + change, 1, #steps)]
		speedLabel.Text = ("Start speed: %sx"):format(tostring(speed))
	end)
end
speedButton("Slower", "-", 180, -1)
speedButton("Faster", "+", 218, 1)
local statusLabel = make("TextLabel", {
	Name = "PanelStatus", BackgroundTransparency = 1, Position = UDim2.fromOffset(264, 78), Size = UDim2.new(1, -282, 0, 26),
	Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(255, 150, 140), TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
}, panel)

local list = make("ScrollingFrame", {
	Name = "List", Position = UDim2.fromOffset(12, 112), Size = UDim2.new(1, -24, 1, -124),
	BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 6,
}, panel)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)

---------------------------------------------------------------------
-- Clean footage: hide everything but the battle screen while it plays
---------------------------------------------------------------------
local KEEP = { BattleGui = true, ReplayGui = true }
local hidden = {}
local clean = false
local status -- the corner status (only when the rest of the screen is shown)

local function setClean(on)
	if on == clean then
		return
	end
	clean = on
	if on then
		for _, g in ipairs(playerGui:GetChildren()) do
			if g:IsA("ScreenGui") and not KEEP[g.Name] and g.Enabled then
				hidden[g] = true
				g.Enabled = false
			end
		end
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
		end)
	else
		for g in pairs(hidden) do
			if g.Parent then
				g.Enabled = true
			end
		end
		hidden = {}
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
		end)
	end
	toggle.Visible = not on
	status.Visible = not on
end

status = make("TextLabel", {
	Name = "ReplayStatus", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.fromOffset(420, 24),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Font = Enum.Font.GothamBold, TextSize = 13,
	TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, Text = "", Visible = false,
}, gui)

local playing = false
local playingSince = 0

local function play(id, seat)
	statusLabel.Text = "Starting..."
	local ok, result = ask("Play", { Id = id, Seat = seat, Speed = speed })
	if not ok then
		statusLabel.Text = tostring(result)
		return
	end
	statusLabel.Text = ""
	panel.Visible = false
	toggle.Text = "Replays  v"
	playing = true
	playingSince = os.clock()
	setClean(true)
end

local function row(entry, order)
	local frame = make("Frame", {
		Name = "Replay_" .. entry.Id, LayoutOrder = order, Size = UDim2.new(1, -10, 0, 74),
		BackgroundColor3 = Color3.fromRGB(36, 30, 70),
	}, list)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
	make("TextLabel", {
		Name = "ReplayTitle", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -250, 0, 22),
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left,
		Text = ("%s  (%d pts)"):format(entry.Title, entry.Score or 0),
	}, frame)
	make("TextLabel", {
		Name = "ReplaySummary", BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 26), Size = UDim2.new(1, -250, 0, 44),
		Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = Color3.fromRGB(220, 220, 235), TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Text = (entry.Summary or "") .. "\n" .. (entry.Blurb or ""),
	}, frame)
	local function button(name, text, x, seat, color)
		local b = make("TextButton", {
			Name = name, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, x, 0.5, 0), Size = UDim2.fromOffset(112, 32),
			BackgroundColor3 = color, TextColor3 = WHITE, Font = Enum.Font.GothamBold, TextSize = 13, Text = text,
		}, frame)
		make("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		b.Activated:Connect(function()
			play(entry.Id, seat)
		end)
	end
	button("PlayFeatured", "Play (winner)", -126, 1, Color3.fromRGB(70, 160, 90))
	button("PlayOther", "Other side", -8, 2, Color3.fromRGB(80, 80, 120))
end

local loaded = false
local function load()
	if loaded then
		return
	end
	local ok, entries = ask("List")
	if not ok or type(entries) ~= "table" then
		statusLabel.Text = "Couldn't load the replay library."
		return
	end
	loaded = true
	if #entries == 0 then
		statusLabel.Text = "No replays yet: run tools/replays.py."
	end
	for i, entry in ipairs(entries) do
		row(entry, i)
	end
end

toggle.Activated:Connect(function()
	panel.Visible = not panel.Visible
	toggle.Text = panel.Visible and "Replays  ^" or "Replays  v"
	if panel.Visible then
		load()
	end
end)
closeButton.Activated:Connect(function()
	panel.Visible = false
	toggle.Text = "Replays  v"
end)

-- keyboard controls while a replay plays
UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not playing then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.Space then
		ask("Pause")
	elseif key == Enum.KeyCode.Right then
		ask("Step")
	elseif key == Enum.KeyCode.LeftBracket then
		ask("Speed", { Change = -1 })
	elseif key == Enum.KeyCode.RightBracket then
		ask("Speed", { Change = 1 })
	elseif key == Enum.KeyCode.H then
		setClean(not clean)
	end
end)

-- follow along; tidy up when the battle screen closes
task.spawn(function()
	local battleGui = playerGui:WaitForChild("BattleGui", 30)
	while true do
		task.wait(0.5)
		if playing then
			local ok, s = ask("Status")
			if ok and s then
				status.Text = ("%s  move %d/%d  %sx%s%s"):format(s.Title or "", s.Index or 0, s.Total or 0,
					tostring(s.Speed or 1), s.Paused and "  PAUSED" or "", s.Problem and ("  ! " .. s.Problem) or "")
				if s.Problem then
					statusLabel.Text = s.Problem
				end
			end
			if battleGui and not battleGui.Enabled and os.clock() - playingSince > 4 then
				playing = false
				setClean(false)
			end
		end
		toggle.Visible = not clean and not (battleGui and battleGui.Enabled)
	end
end)
