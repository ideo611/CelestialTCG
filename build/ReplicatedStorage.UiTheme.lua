--[[
	UiTheme (ModuleScript)
	Location: ReplicatedStorage > UiTheme

	One look for every menu, so the shop, collection, binder, starter decks,
	guide and spectator screens all match the battle board:

	  UiTheme.Button(button)   metal plate button (tinted by the button's
	                           BackgroundColor3, which code can still change),
	                           with a little lift on hover and a press-in
	  UiTheme.Panel(frame)     a menu window: deep gradient + the star-cornered
	                           frame border (UiAssets.PanelFrame)
	  UiTheme.List(frame)      a list / scroll box inside a window: gradient
	                           and a thin gold edge (lighter than a window)
	  UiTheme.Backdrop(frame)  a full-screen menu background: cosmic gradient,
	                           soft nebula glows and a starfield
	  UiTheme.Title(label)     gold heading text

	Every function is safe to call twice and returns what it was given.
	Set a button's "NoTheme" attribute to keep it plain.
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiAssets = require(ReplicatedStorage:WaitForChild("UiAssets"))

local UiTheme = {}

UiTheme.Colors = {
	Backdrop = Color3.fromRGB(46, 34, 92),  -- (the gradient darkens it toward the bottom)
	Panel = Color3.fromRGB(30, 25, 56),
	List = Color3.fromRGB(22, 18, 42),
	Gold = Color3.fromRGB(236, 196, 110),
	GoldLight = Color3.fromRGB(255, 240, 196),
	GoldDeep = Color3.fromRGB(214, 150, 58),
	Text = Color3.fromRGB(255, 255, 255),
}

local CORNER_SOURCE = 96 -- source pixels in each corner of the button plate image

local function brighten(color)
	-- the plate is mid-grey metal, so dark button colors are lifted until
	-- their brightest channel is near full (dark greys stay greyish)
	local top = math.max(color.R, color.G, color.B, 0.01)
	local scale = math.min(0.98 / top, 2.1)
	return Color3.new(math.min(color.R * scale, 1), math.min(color.G * scale, 1), math.min(color.B * scale, 1))
end
UiTheme.PlateTint = brighten

-- Everything the theme adds is marked ThemePart, so a menu that empties a
-- frame to redraw it can keep the decoration (see UiTheme.Clear).
local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object:SetAttribute("ThemePart", true)
	object.Parent = parent
	return object
end

-- Removes a frame's contents but keeps the theme's decoration
function UiTheme.Clear(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:GetAttribute("ThemePart") then
			child:Destroy()
		end
	end
end

---------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------
-- (Hover and press only on the client)
local function addPressFeel(b, plate, tint)
	if not RunService:IsClient() then
		return
	end
	local scale = b:FindFirstChild("ThemeScale") or make("UIScale", { Name = "ThemeScale" }, b)
	local hovering = false
	local function set(value, t)
		TweenService:Create(scale, TweenInfo.new(t or 0.08, Enum.EasingStyle.Quad), { Scale = value }):Play()
	end
	local function glow(on)
		if plate.Parent then
			plate.ImageColor3 = on and tint():Lerp(Color3.new(1, 1, 1), 0.22) or tint()
		end
	end
	b.MouseEnter:Connect(function()
		hovering = true
		set(1.04)
		glow(true)
	end)
	b.MouseLeave:Connect(function()
		hovering = false
		set(1)
		glow(false)
	end)
	b.MouseButton1Down:Connect(function()
		set(0.95, 0.05)
	end)
	b.MouseButton1Up:Connect(function()
		set(hovering and 1.04 or 1)
	end)
end

function UiTheme.Button(b, options)
	if not b or b:GetAttribute("Themed") or b:GetAttribute("NoTheme") then
		return b
	end
	options = options or {}
	b:SetAttribute("Themed", true)
	local plateImage = UiAssets.ButtonPlate
	if not plateImage then
		-- no plate uploaded: a gradient bevel and a gold edge instead
		make("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 160)),
		}, b)
		if not b:FindFirstChildOfClass("UIStroke") then
			make("UIStroke", { Color = UiTheme.Colors.Gold, Transparency = 0.45, Thickness = 1.5,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		end
		return b
	end

	local baseColor = b.BackgroundColor3
	local function tint()
		return brighten(baseColor)
	end
	local plate = make("ImageLabel", {
		Name = "Plate",
		BackgroundTransparency = 1,
		Image = plateImage,
		ImageColor3 = tint(),
		ImageTransparency = b.BackgroundTransparency < 1 and b.BackgroundTransparency or 0,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = UiAssets.ButtonPlateSlice,
		SliceScale = (options.Corner or 9) / CORNER_SOURCE,
		Size = UDim2.fromScale(1, 1),
		ZIndex = b.ZIndex,
	}, b)
	b.BackgroundTransparency = 1

	-- A TextButton draws its text under its children, so the words move to a
	-- label on top of the plate. Code can keep setting b.Text, TextColor3...
	local isText = b:IsA("TextButton")
	local textLabel
	if isText then
		local constraint = b:FindFirstChildOfClass("UITextSizeConstraint")
		textLabel = make("TextLabel", {
			Name = "PlateText",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = b.Text,
			TextColor3 = b.TextColor3,
			Font = b.Font,
			TextScaled = b.TextScaled,
			TextSize = b.TextSize,
			TextWrapped = b.TextWrapped,
			RichText = b.RichText,
			TextXAlignment = b.TextXAlignment,
			TextYAlignment = b.TextYAlignment,
			TextStrokeTransparency = 0.45,
			TextStrokeColor3 = Color3.fromRGB(10, 6, 20),
			ZIndex = b.ZIndex,
		}, b)
		if constraint then
			constraint:Clone().Parent = textLabel
		end
		b.TextTransparency = 1
		for _, prop in ipairs({ "Text", "TextColor3", "Font", "RichText", "TextXAlignment" }) do
			b:GetPropertyChangedSignal(prop):Connect(function()
				textLabel[prop] = b[prop]
			end)
		end
		b:GetPropertyChangedSignal("TextTransparency"):Connect(function()
			-- code fading the text (not this theme hiding it)
			if b.TextTransparency < 1 then
				textLabel.TextTransparency = b.TextTransparency
				b.TextTransparency = 1
			end
		end)
	end

	b:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		baseColor = b.BackgroundColor3
		plate.ImageColor3 = tint()
	end)
	b:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		local value = b.BackgroundTransparency
		if value < 1 then
			plate.ImageTransparency = value
			b.BackgroundTransparency = 1
		end
	end)
	b:GetPropertyChangedSignal("ZIndex"):Connect(function()
		plate.ZIndex = b.ZIndex
		if textLabel then
			textLabel.ZIndex = b.ZIndex
		end
	end)
	addPressFeel(b, plate, tint)
	return b
end

---------------------------------------------------------------------
-- Windows and lists
---------------------------------------------------------------------
local function gradient(frame, top, bottom)
	if frame:FindFirstChild("ThemeGradient") then
		return
	end
	make("UIGradient", {
		Name = "ThemeGradient",
		Rotation = 90,
		Color = ColorSequence.new(top, bottom),
	}, frame)
end

function UiTheme.Panel(frame, options)
	if not frame or frame:GetAttribute("ThemedPanel") then
		return frame
	end
	options = options or {}
	frame:SetAttribute("ThemedPanel", true)
	if options.Color ~= false then
		frame.BackgroundColor3 = options.Color or UiTheme.Colors.Panel
	end
	if frame.BackgroundTransparency > 0.3 and options.Solid ~= false then
		frame.BackgroundTransparency = 0.04
	end
	gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 140, 175))
	if not frame:FindFirstChildOfClass("UICorner") then
		make("UICorner", { CornerRadius = UDim.new(0, 12) }, frame)
	end
	if options.Border ~= false and not frame:FindFirstChild("PanelFrame") then
		if UiAssets.PanelFrame then
			local border = UiAssets.FramePanel(frame, options.Thickness)
			if border then
				border:SetAttribute("ThemePart", true)
			end
		else
			local stroke = frame:FindFirstChildOfClass("UIStroke") or make("UIStroke", {}, frame)
			stroke.Color = UiTheme.Colors.Gold
			stroke.Thickness = 2
		end
	end
	return frame
end

function UiTheme.List(frame, options)
	if not frame or frame:GetAttribute("ThemedList") then
		return frame
	end
	options = options or {}
	frame:SetAttribute("ThemedList", true)
	if options.Color ~= false then
		frame.BackgroundColor3 = options.Color or UiTheme.Colors.List
	end
	gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 165, 190))
	if not frame:FindFirstChildOfClass("UICorner") then
		make("UICorner", { CornerRadius = UDim.new(0, 8) }, frame)
	end
	if not frame:FindFirstChildOfClass("UIStroke") then
		make("UIStroke", {
			Name = "ThemeEdge",
			Color = UiTheme.Colors.Gold,
			Transparency = 0.5,
			Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, frame)
	end
	if frame:IsA("ScrollingFrame") then
		frame.ScrollBarImageColor3 = UiTheme.Colors.Gold
		frame.ScrollBarImageTransparency = 0.25
	end
	return frame
end

-- Full-screen menu background. The stars sit in a "Backdrop" folder frame
-- drawn first, under everything else in the menu.
function UiTheme.Backdrop(frame, options)
	if not frame or frame:GetAttribute("ThemedBackdrop") then
		return frame
	end
	options = options or {}
	frame:SetAttribute("ThemedBackdrop", true)
	frame.BackgroundColor3 = options.Color or UiTheme.Colors.Backdrop
	frame.BackgroundTransparency = 0
	gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(42, 40, 70))
	local sky = make("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = frame.ZIndex,
	}, frame)
	-- soft nebula glows
	local glows = {
		{ 0.18, 0.25, 0.55, Color3.fromRGB(140, 90, 255), 0.86 },
		{ 0.82, 0.7, 0.6, Color3.fromRGB(60, 140, 255), 0.88 },
		{ 0.6, 0.12, 0.35, Color3.fromRGB(255, 150, 90), 0.92 },
	}
	for i, g in ipairs(glows) do
		local glow = make("Frame", {
			Name = "Glow" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(g[1], g[2]),
			Size = UDim2.fromScale(g[3], g[3] * 1.4),
			BackgroundColor3 = g[4],
			BackgroundTransparency = g[5],
			BorderSizePixel = 0,
			ZIndex = frame.ZIndex,
		}, sky)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, glow)
	end
	-- stars (the same pattern every time)
	local rng = Random.new(options.Seed or 7)
	for i = 1, options.Stars or 70 do
		local size = rng:NextNumber() < 0.15 and 3 or 2
		local star = make("Frame", {
			Name = "Star",
			Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber()),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = Color3.fromRGB(255, 250, 235),
			BackgroundTransparency = 0.25 + rng:NextNumber() * 0.6,
			BorderSizePixel = 0,
			ZIndex = frame.ZIndex,
		}, sky)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, star)
	end
	return frame
end

-- A window color leaning toward a faction (or any) color
function UiTheme.Tinted(color, amount)
	return UiTheme.Colors.Panel:Lerp(color, amount or 0.45)
end

function UiTheme.Title(label)
	if not label or label:FindFirstChild("TitleGold") then
		return label
	end
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.55
	label.TextStrokeColor3 = Color3.fromRGB(40, 20, 0)
	make("UIGradient", {
		Name = "TitleGold",
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, UiTheme.Colors.GoldLight),
			ColorSequenceKeypoint.new(0.55, UiTheme.Colors.Gold),
			ColorSequenceKeypoint.new(1, UiTheme.Colors.GoldDeep),
		}),
	}, label)
	return label
end

return UiTheme
