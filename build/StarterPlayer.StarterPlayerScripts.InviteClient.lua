--[[
	InviteClient (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > InviteClient

	"Invite friends" in the HUD column: a small window that explains the
	reward (EconomyConfig.Referral: when a friend you invite finishes their
	first match vs the bot, you both get Booster Pack Tickets), shows how many
	friends have earned you tickets, and opens Roblox's invite prompt.
	(ReferralServer does the tracking and paying.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiTheme = require(ReplicatedStorage:WaitForChild("UiTheme"))
local HudDock = require(ReplicatedStorage:WaitForChild("HudDock"))
local EconomyConfig = require(ReplicatedStorage:WaitForChild("EconomyConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CONFIG = EconomyConfig.Referral

local SocialService
pcall(function()
	SocialService = game:GetService("SocialService")
end)

local WHITE = Color3.new(1, 1, 1)

local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function track(name, detail)
	pcall(function()
		ReplicatedStorage.AnalyticsRemotes.Track:FireServer(name, detail)
	end)
end

local function newButton(parent, name, text, position, size, color)
	local b = make("TextButton", {
		Name = name, Text = text, Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = WHITE,
		Position = position, Size = size, BackgroundColor3 = color, AutoButtonColor = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 10) }, b)
	return UiTheme.Button(b)
end

-- HUD button
local hud = make("ScreenGui", { Name = "InviteButtonGui", ResetOnSpawn = false, DisplayOrder = 1 }, playerGui)
local openButton = newButton(hud, "InviteFriends", "Invite friends", UDim2.new(), UDim2.fromOffset(120, 40),
	Color3.fromRGB(200, 140, 40))
HudDock.Add(openButton, 25)

-- The window
local gui = make("ScreenGui", {
	Name = "InviteGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 8,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false,
}, playerGui)
local dim = make("TextButton", {
	Name = "Dim", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
}, gui)
dim:SetAttribute("NoTheme", true)
local area = make("Frame", { Name = "Area", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) }, gui)
UiTheme.FitScreen(area, 640, 400)
local window = make("Frame", {
	Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(560, 330), BackgroundColor3 = Color3.fromRGB(20, 16, 40),
}, area)
make("UICorner", { CornerRadius = UDim.new(0, 14) }, window)
UiTheme.Panel(window)

UiTheme.Title(make("TextLabel", {
	Name = "InviteTitle", BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 14),
	Size = UDim2.new(1, -90, 0, 40), Font = Enum.Font.GothamBlack, TextSize = 30, Text = "Invite friends",
	TextXAlignment = Enum.TextXAlignment.Left,
}, window))
local close = newButton(window, "Close", "X", UDim2.new(1, -60, 0, 14), UDim2.fromOffset(44, 40), Color3.fromRGB(170, 60, 60))

make("TextLabel", {
	Name = "InviteInfo", BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 64),
	Size = UDim2.new(1, -48, 0, 110), Font = Enum.Font.Gotham, TextSize = 19, TextWrapped = true, RichText = true,
	TextColor3 = Color3.fromRGB(235, 235, 245), TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = ("Invite a friend who's new to Celestial TCG. When they finish their <b>first match vs the bot</b>, "
		.. "you <b>both</b> get <b>%d Booster Pack Tickets</b>.\nUp to %d friends."):format(CONFIG.Tickets, CONFIG.MaxFriends),
}, window)
local status = make("TextLabel", {
	Name = "InviteStatus", BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 178),
	Size = UDim2.new(1, -48, 0, 50), Font = Enum.Font.GothamBold, TextSize = 19, TextWrapped = true,
	TextColor3 = Color3.fromRGB(255, 205, 90), TextXAlignment = Enum.TextXAlignment.Left, Text = "",
}, window)
local inviteButton = newButton(window, "SendInvite", "Invite", UDim2.new(0.5, -110, 1, -76), UDim2.fromOffset(220, 54),
	Color3.fromRGB(70, 170, 90))

local function setStatus()
	status.Text = "Checking..."
	task.spawn(function()
		local remotes = ReplicatedStorage:FindFirstChild("ReferralRemotes")
		local ok, okResult, info = pcall(function()
			return remotes.ReferralRequest:InvokeServer("Status")
		end)
		if not (ok and okResult and info) then
			status.Text = ""
			return
		end
		local lines = {}
		table.insert(lines, ("Friends who've earned you tickets: %d / %d"):format(info.Friends, info.MaxFriends))
		if info.InvitedBy then
			table.insert(lines, ("%s invited you: finish a match vs the bot for your %d tickets!"):format(info.InvitedBy, info.Tickets))
		end
		status.Text = table.concat(lines, "\n")
	end)
end

local function closeWindow()
	gui.Enabled = false
end

openButton.Activated:Connect(function()
	gui.Enabled = true
	track("invite_opened")
	setStatus()
end)
close.Activated:Connect(closeWindow)
dim.Activated:Connect(closeWindow)

inviteButton.Activated:Connect(function()
	if not SocialService then
		status.Text = "Invites aren't available right now."
		return
	end
	local canSend = false
	pcall(function()
		canSend = SocialService:CanSendGameInviteAsync(player)
	end)
	if not canSend then
		status.Text = "Your account can't send invites right now (check your Roblox privacy settings)."
		return
	end
	local ok = pcall(function()
		local options = Instance.new("ExperienceInviteOptions")
		options.PromptMessage = ("Play Celestial TCG with me! Finish your first match vs the bot and we both get %d Booster Pack Tickets.")
			:format(CONFIG.Tickets)
		SocialService:PromptGameInvite(player, options)
	end)
	if ok then
		track("invite_sent")
		closeWindow()
	end
end)
