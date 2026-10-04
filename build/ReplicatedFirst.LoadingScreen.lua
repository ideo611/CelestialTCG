--[[
	LoadingScreen (LocalScript)
	Location: ReplicatedFirst > LoadingScreen

	The first thing a player sees: the space-shop painting with the game's
	logo, until the game has loaded and their cards are ready (the server
	sets the DataLoaded attribute). Then it fades away.

	This runs before ReplicatedStorage arrives, so the two image IDs live
	here (they match UiAssets.Loading and UiAssets.Logo).
]]

local BACKGROUND = "rbxassetid://90104731234541" -- ui-loading
local LOGO = "rbxassetid://77126253690698"       -- logo
local MIN_SECONDS = 2.5  -- long enough to see it
local MAX_SECONDS = 20   -- never trap anyone behind it

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local player = Players.LocalPlayer
local started = os.clock()

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local back = Instance.new("ImageLabel")
back.Name = "Background"
back.Size = UDim2.fromScale(1, 1)
back.BackgroundColor3 = Color3.fromRGB(12, 8, 26)
back.Image = BACKGROUND
back.ScaleType = Enum.ScaleType.Crop
back.Parent = gui

local logo = Instance.new("ImageLabel")
logo.Name = "Logo"
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.44)
logo.Size = UDim2.fromScale(0.55, 0.42)
logo.BackgroundTransparency = 1
logo.Image = LOGO
logo.ScaleType = Enum.ScaleType.Fit
logo.Parent = back

local status = Instance.new("TextLabel")
status.Name = "Status"
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.fromScale(0.5, 0.72)
status.Size = UDim2.new(0.6, 0, 0, 30)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamBold
status.TextSize = 22
status.TextColor3 = Color3.fromRGB(255, 225, 150)
status.TextStrokeTransparency = 0.4
status.Text = "Loading your cards..."
status.Parent = back

-- three twinkling stars under the status line
local stars = {}
for i = 1, 3 do
	local star = Instance.new("TextLabel")
	star.Name = "Star" .. i
	star.AnchorPoint = Vector2.new(0.5, 0)
	star.Position = UDim2.new(0.5, (i - 2) * 34, 0.72, 38)
	star.Size = UDim2.fromOffset(30, 30)
	star.BackgroundTransparency = 1
	star.Font = Enum.Font.GothamBold
	star.TextSize = 26
	star.TextColor3 = Color3.fromRGB(255, 225, 150)
	star.Text = utf8.char(0x2726)
	star.Parent = back
	stars[i] = star
end

gui.Parent = player:WaitForChild("PlayerGui")
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({ back, logo })
	end)
end)

local done = false
task.spawn(function()
	local t = 0
	while not done do
		t = t + 1
		for i, star in ipairs(stars) do
			star.TextTransparency = (t + i) % 3 == 0 and 0 or 0.6
		end
		task.wait(0.3)
	end
end)

-- wait for the game, then for the player's cards
if not game:IsLoaded() then
	game.Loaded:Wait()
end
while not player:GetAttribute("DataLoaded") and os.clock() - started < MAX_SECONDS do
	task.wait(0.2)
end
while os.clock() - started < MIN_SECONDS do
	task.wait(0.1)
end

done = true
local fade = TweenInfo.new(0.6)
TweenService:Create(back, fade, { BackgroundTransparency = 1, ImageTransparency = 1 }):Play()
TweenService:Create(logo, fade, { ImageTransparency = 1 }):Play()
TweenService:Create(status, fade, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
for _, star in ipairs(stars) do
	TweenService:Create(star, fade, { TextTransparency = 1 }):Play()
end
task.wait(0.7)
gui:Destroy()
