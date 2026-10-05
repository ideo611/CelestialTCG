--[[
	ConsoleSupport (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > ConsoleSupport

	Controllers (Xbox, PlayStation, or a controller on PC): the game is built
	for a mouse and touch, so with a controller Roblox's on-screen cursor
	(GamepadService) does the clicking:
	  - it turns on by itself whenever a menu or the battle screen is open,
	    and off again when you're back to walking around
	  - the View / Share button (ButtonSelect) turns it on or off anywhere,
	    e.g. to press the HUD buttons (Play vs Bot, My Cards...) in the world
	  - if you turn it off yourself inside a menu, it stays off until the
	    next menu opens
	A small hint bar shows the controls for a few seconds when a controller is
	picked up or a screen opens (so it never sits on top of the hand or End Turn).
	With a mouse, keyboard or touch, nothing here does anything.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local GamepadService
pcall(function()
	GamepadService = game:GetService("GamepadService")
end)
if not GamepadService then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- screens that need the cursor while they're open
local MENUS = {
	BattleGui = true,
	ShopGui = true,
	CollectionGui = true,
	BinderGui = true,
	StarterBrowserGui = true,
	SpectateGui = true,
	SpectateInspectGui = true,
	RulebookGui = true,
	InviteGui = true,
	GuideGui = false, -- (the tutorial box sits on the battle screen; the battle screen decides)
}

local GAMEPAD_TYPES = {}
for i = 1, 8 do
	pcall(function()
		GAMEPAD_TYPES[Enum.UserInputType["Gamepad" .. i]] = true
	end)
end

local function usingGamepad()
	local last
	pcall(function()
		last = UserInputService:GetLastInputType()
	end)
	if last then
		return GAMEPAD_TYPES[last] == true
	end
	-- (no input yet) a console has a gamepad and no keyboard
	return UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
end

local function openMenu()
	for _, g in ipairs(playerGui:GetChildren()) do
		if MENUS[g.Name] and g:IsA("ScreenGui") and g.Enabled then
			return g
		end
	end
	return nil
end

local function cursorOn()
	local on = false
	pcall(function()
		on = GamepadService.GamepadCursorEnabled
	end)
	return on
end

-- the first visible button on a screen: where the cursor starts
local function firstButton(gui)
	if not gui then
		return nil
	end
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("GuiButton") and d.Visible and d.Active ~= false then
			return d
		end
	end
	return nil
end

local function setCursor(on, menu)
	pcall(function()
		if on then
			GamepadService:EnableGamepadCursor(firstButton(menu))
		else
			GamepadService:DisableGamepadCursor()
		end
	end)
end

---------------------------------------------------------------------
-- Hint bar (bottom of the screen, only with a controller)
---------------------------------------------------------------------
local hintGui = Instance.new("ScreenGui")
hintGui.Name = "ControllerHints"
hintGui.ResetOnSpawn = false
hintGui.DisplayOrder = 20
hintGui.Enabled = false
hintGui.Parent = playerGui

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -8)
bar.Size = UDim2.fromOffset(0, 34)
bar.AutomaticSize = Enum.AutomaticSize.X
bar.BackgroundColor3 = Color3.fromRGB(15, 12, 30)
bar.BackgroundTransparency = 0.3
bar.Parent = hintGui
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0.5, 0)
corner.Parent = bar
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)
padding.Parent = bar
local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

local function hint(order, keyCode, fallback, text)
	local image
	pcall(function()
		image = UserInputService:GetImageForKeyCode(keyCode)
	end)
	if image and image ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon" .. order
		icon.LayoutOrder = order * 2
		icon.Size = UDim2.fromOffset(24, 24)
		icon.BackgroundTransparency = 1
		icon.Image = image
		icon.Parent = bar
	else
		text = fallback .. "  " .. text
	end
	local label = Instance.new("TextLabel")
	label.Name = "Hint" .. order
	label.LayoutOrder = order * 2 + 1
	label.Size = UDim2.fromOffset(0, 24)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text .. "   "
	label.Parent = bar
end
hint(1, Enum.KeyCode.Thumbstick1, "L-stick", "Move cursor")
hint(2, Enum.KeyCode.ButtonA, "A", "Select")
hint(3, Enum.KeyCode.ButtonSelect, "View", "Cursor on/off")

---------------------------------------------------------------------
-- Keeping the cursor in step with the screens
---------------------------------------------------------------------
local manual = false        -- turned on with View/Share while walking around
local suppressedFor = nil   -- the menu they turned the cursor off in
local weTurnedOn = false
local turnedOnAt = 0
local HINT_SECONDS = 6
local hintUntil = 0
local lastGamepad, lastMenu = false, nil

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.ButtonSelect then
		local menu = openMenu()
		if cursorOn() then
			manual = false
			suppressedFor = menu
			weTurnedOn = false
			setCursor(false)
		else
			manual = true
			suppressedFor = nil
			weTurnedOn = true
			turnedOnAt = os.clock()
			setCursor(true, menu)
		end
	end
end)

task.spawn(function()
	while true do
		local gamepad = usingGamepad()
		local menu = openMenu()
		if gamepad and (not lastGamepad or menu ~= lastMenu) then
			hintUntil = os.clock() + HINT_SECONDS
		end
		lastGamepad, lastMenu = gamepad, menu
		hintGui.Enabled = gamepad and os.clock() < hintUntil
		if suppressedFor and suppressedFor ~= menu then
			suppressedFor = nil -- a different screen now: back to automatic
		end
		local want = gamepad and (manual or (menu ~= nil and suppressedFor == nil))
		local on = cursorOn()
		if weTurnedOn and not on and want and os.clock() - turnedOnAt > 1 then
			-- they turned it off themselves (Roblox's own B/back): respect it here
			weTurnedOn = false
			manual = false
			suppressedFor = menu
			want = false
		end
		if want and not on then
			weTurnedOn = true
			turnedOnAt = os.clock()
			setCursor(true, menu)
		elseif not want and on and weTurnedOn then
			weTurnedOn = false
			setCursor(false)
		end
		if not gamepad then
			manual = false
		end
		task.wait(0.25)
	end
end)
