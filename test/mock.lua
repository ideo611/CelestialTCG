-- A small Roblox stand-in for testing scripts outside Studio.
-- Properties are whitelisted per class (only real Roblox properties), so
-- setting a property Roblox doesn't have fails here the same way it would
-- in Studio.

local M = {}
M.errors = {}
M.warnings = {}
M.now = 0

---------------------------------------------------------------------
-- Luau extras
---------------------------------------------------------------------
math.clamp = function(x, a, b) return math.max(a, math.min(b, x)) end
math.round = function(x) return math.floor(x + 0.5) end
math.sign = function(x) return x > 0 and 1 or (x < 0 and -1 or 0) end
table.find = function(t, v) for i, x in ipairs(t) do if x == v then return i end end return nil end
table.clear = function(t) for k in pairs(t) do t[k] = nil end end
table.clone = function(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
string.split = function(s, sep)
	local out = {}
	for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do table.insert(out, part) end
	return out
end
unpack = unpack or table.unpack
function warn(...) local parts = {} for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end table.insert(M.warnings, table.concat(parts, " ")) print("WARN: " .. table.concat(parts, " ")) end
function tick() return M.now end
os.clock = function() return M.now end

---------------------------------------------------------------------
-- Datatypes
---------------------------------------------------------------------
local function datatype(name, mt)
	mt.__index = mt.__index or mt
	mt.__type = name
	return mt
end

local V3 = {}
V3.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) return Vector3.new(v.X / m, v.Y / m, v.Z / m) end
	return V3[k]
end
V3.__type = "Vector3"
V3.Lerp = function(a, b, t) return Vector3.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
V3.Dot = function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
V3.Cross = function(a, b) return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
V3.__add = function(a, b) return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	if type(b) == "number" then return Vector3.new(a.X * b, a.Y * b, a.Z * b) end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b) return Vector3.new(a.X / b, a.Y / b, a.Z / b) end
V3.__unm = function(a) return Vector3.new(-a.X, -a.Y, -a.Z) end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__tostring = function(v) return ("%g, %g, %g"):format(v.X, v.Y, v.Z) end
Vector3 = { new = function(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end }
Vector3.zero = Vector3.new(0, 0, 0)
Vector3.one = Vector3.new(1, 1, 1)
Vector3.yAxis = Vector3.new(0, 1, 0)

local V2 = datatype("Vector2", {})
V2.__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end
V2.__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end
V2.__mul = function(a, b) if type(b) == "number" then return Vector2.new(a.X * b, a.Y * b) end return Vector2.new(a.X * b.X, a.Y * b.Y) end
Vector2 = { new = function(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2) end }
Vector2.zero = Vector2.new(0, 0)

local CF = {}
CF.__type = "CFrame"
CF.__index = function(c, k)
	if k == "Position" or k == "p" then return Vector3.new(c.X, c.Y, c.Z) end
	if k == "LookVector" then return Vector3.new(0, 0, -1) end
	if k == "Rotation" then return CFrame.new() end
	if k == "UpVector" then return Vector3.new(0, 1, 0) end
	if k == "RightVector" then return Vector3.new(1, 0, 0) end
	return CF[k]
end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then return CFrame.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
	if getmetatable(b) == V3 then return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
	error("bad CFrame multiply")
end
CF.__add = function(a, b) return CFrame.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
CF.__tostring = function(c) return ("CFrame(%g, %g, %g)"):format(c.X, c.Y, c.Z) end
CFrame = {
	new = function(x, y, z, ...)
		if type(x) == "table" and getmetatable(x) == V3 then x, y, z = x.X, x.Y, x.Z end
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, CF)
	end,
	Angles = function() return setmetatable({ X = 0, Y = 0, Z = 0 }, CF) end,
	lookAt = function(at) return CFrame.new(at) end,
	fromEulerAnglesXYZ = function() return setmetatable({ X = 0, Y = 0, Z = 0 }, CF) end,
}
CFrame.identity = CFrame.new()

local UD = datatype("UDim", {})
UDim = { new = function(s, o) return setmetatable({ Scale = s or 0, Offset = o or 0 }, UD) end }
local UD2 = datatype("UDim2", {})
UD2.__add = function(a, b) return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
UDim2 = {
	new = function(xs, xo, ys, yo) return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, UD2) end,
	fromScale = function(x, y) return setmetatable({ X = UDim.new(x, 0), Y = UDim.new(y, 0) }, UD2) end,
	fromOffset = function(x, y) return setmetatable({ X = UDim.new(0, x), Y = UDim.new(0, y) }, UD2) end,
}

local C3 = datatype("Color3", {})
C3.Lerp = function(a, b, t) return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end
C3.ToHSV = function(c) return 0, 0, math.max(c.R, c.G, c.B) end
C3.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
Color3 = {
	new = function(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3) end,
	fromRGB = function(r, g, b) return setmetatable({ R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }, C3) end,
	fromHSV = function(h, s, v)
		local i = math.floor(h * 6); local f = h * 6 - i
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		local r, g, b = ({ { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } })[i % 6 + 1][1], nil, nil
		local row = ({ { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } })[i % 6 + 1]
		return Color3.new(row[1], row[2], row[3])
	end,
}

local SEQ = datatype("ColorSequence", {})
ColorSequenceKeypoint = { new = function(t, c) return { Time = t, Value = c } end }
ColorSequence = { new = function(a, b)
	if getmetatable(a) == C3 then return setmetatable({ Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } }, SEQ) end
	return setmetatable({ Keypoints = a }, SEQ)
end }
local NSEQ = datatype("NumberSequence", {})
NumberSequenceKeypoint = { new = function(t, v, e) return { Time = t, Value = v, Envelope = e or 0 } end }
NumberSequence = { new = function(a, b)
	if type(a) == "number" then return setmetatable({ Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) } }, NSEQ) end
	return setmetatable({ Keypoints = a }, NSEQ)
end }
NumberRange = { new = function(a, b) return { Min = a, Max = b or a } end }
Rect = { new = function(a, b, c, d) return { Min = Vector2.new(a, b), Max = Vector2.new(c, d) } end }
TweenInfo = { new = function(t, ...) return { Time = t or 1 } end }
BrickColor = { new = function(n) return { Name = n } end }
Font = { new = function(f) return { Family = f } end, fromEnum = function(e) return { Family = e } end }
PhysicalProperties = { new = function() return {} end }

local RNG = {}
RNG.__index = RNG
RNG.__type = "Random"
Random = { new = function(seed)
	local r = setmetatable({ State = math.floor(seed or (os.time() + math.random(1, 1e6))) % 2147483647 }, RNG)
	if r.State <= 0 then r.State = r.State + 2147483646 end
	return r
end }
function RNG:_next()
	self.State = (self.State * 48271) % 2147483647
	return self.State / 2147483647
end
function RNG:NextInteger(a, b) return a + math.floor(self:_next() * (b - a + 1)) end
function RNG:NextNumber(a, b) a = a or 0 b = b or 1 return a + self:_next() * (b - a) end

function typeof(v)
	local mt = getmetatable(v)
	if type(mt) == "table" and mt.__type then return mt.__type end
	if type(v) == "table" and rawget(v, "__instance") then return "Instance" end
	if type(v) == "table" and rawget(v, "EnumType") then return "EnumItem" end
	return type(v)
end

---------------------------------------------------------------------
-- Enums (only listed items are valid where the list is complete)
---------------------------------------------------------------------
local ENUMS = {
	NormalId = { "Front", "Back", "Top", "Bottom", "Left", "Right" },
	SurfaceGuiSizingMode = { "FixedSize", "PixelsPerStud" },
	TextXAlignment = { "Left", "Right", "Center" },
	TextYAlignment = { "Top", "Center", "Bottom" },
	ZIndexBehavior = { "Global", "Sibling" },
	ScaleType = { "Stretch", "Slice", "Tile", "Fit", "Crop" },
	ApplyStrokeMode = { "Contextual", "Border" },
	AspectType = { "FitWithinMaxSize", "ScaleWithParentSize" },
	DominantAxis = { "Width", "Height" },
	SurfaceType = { "Smooth", "Glue", "Weld", "Studs", "Inlet", "Universal", "Hinge", "Motor", "SteppingMotor", "SmoothNoOutlines" },
	FillDirection = { "Horizontal", "Vertical" },
	SortOrder = { "Name", "Custom", "LayoutOrder" },
	HorizontalAlignment = { "Center", "Left", "Right" },
	VerticalAlignment = { "Center", "Top", "Bottom" },
	EasingStyle = { "Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic", "Exponential", "Circular", "Cubic" },
	EasingDirection = { "In", "Out", "InOut" },
	AutomaticSize = { "None", "X", "Y", "XY" },
	ProximityPromptExclusivity = { "OnePerButton", "OneGlobally", "AlwaysShow" },
	PartType = { "Ball", "Block", "Cylinder", "Wedge", "CornerWedge" },
	LineJoinMode = { "Round", "Bevel", "Miter" },
	ResamplerMode = { "Default", "Pixelated" },
	UserInputType = { "MouseButton1", "MouseButton2", "Touch", "Keyboard", "MouseMovement", "MouseWheel", "Gamepad1" },
	AnalyticsCustomFieldKeys = { "CustomField01", "CustomField02", "CustomField03" },
	-- open lists (any name accepted)
	Font = false, KeyCode = false, Material = false,
}
local enumCache = {}
Enum = setmetatable({}, { __index = function(_, typeName)
	local items = ENUMS[typeName]
	if items == nil then error("Enum." .. tostring(typeName) .. " isn't known to the mock", 2) end
	if enumCache[typeName] then return enumCache[typeName] end
	local valid = {}
	if items then for i, n in ipairs(items) do valid[n] = i end end
	local e = setmetatable({}, { __index = function(t, name)
		if items and not valid[name] then error("Enum." .. typeName .. "." .. tostring(name) .. " is not a valid EnumItem", 2) end
		local item = { EnumType = typeName, Name = name, Value = valid[name] or 0 }
		rawset(t, name, item)
		return item
	end })
	enumCache[typeName] = e
	return e
end })

---------------------------------------------------------------------
-- Scheduler
---------------------------------------------------------------------
local queue = {}
local function push(time, co, args)
	table.insert(queue, { Time = time, Co = co, Args = args or {}, Seq = #queue + M.now })
end
local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		local message = debug.traceback(co, tostring(err))
		M.seen = M.seen or {}
		if not M.seen[message] then
			M.seen[message] = true
			table.insert(M.errors, message)
			print("ERROR: " .. message)
		end
	end
end
M.resume = resume

task = {}
function task.spawn(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	push(M.now, co, { ... })
	return co
end
function task.delay(t, f, ...)
	local co = coroutine.create(f)
	push(M.now + (t or 0), co, { ... })
	return co
end
function task.wait(t)
	local co, main = coroutine.running()
	if main or not co then error("task.wait called outside a coroutine", 2) end
	t = t or 0.03
	push(M.now + t, co, {})
	coroutine.yield()
	return t
end
function task.cancel() end
wait = task.wait
spawn = task.spawn
delay = task.delay

local heartbeats = {}
function M.run(seconds, step)
	step = step or 0.05
	local stop = M.now + seconds
	while true do
		table.sort(queue, function(a, b) if a.Time ~= b.Time then return a.Time < b.Time end return a.Seq < b.Seq end)
		local nextItem = queue[1]
		local nextBeat = M.now + step
		if nextItem and nextItem.Time <= nextBeat and nextItem.Time <= stop then
			table.remove(queue, 1)
			M.now = math.max(M.now, nextItem.Time)
			resume(nextItem.Co, unpack(nextItem.Args))
		else
			if nextBeat > stop then M.now = stop break end
			M.now = nextBeat
			for _, sig in ipairs(heartbeats) do sig:Fire(step) end
		end
	end
end

---------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------
local Signal = {}
Signal.__index = Signal
function Signal.new() return setmetatable({ Handlers = {} }, Signal) end
function Signal:Connect(fn)
	local entry = { Fn = fn, Connected = true }
	table.insert(self.Handlers, entry)
	return { Connected = true, Disconnect = function(c) entry.Connected = false c.Connected = false end }
end
Signal.connect = Signal.Connect
function Signal:Once(fn)
	local c
	c = self:Connect(function(...) c:Disconnect() fn(...) end)
	return c
end
function Signal:Fire(...)
	local args = table.pack(...)
	for _, entry in ipairs(self.Handlers) do
		if entry.Connected then
			task.spawn(entry.Fn, unpack(args, 1, args.n))
		end
	end
end
function Signal:Wait()
	local co = coroutine.running()
	self:Once(function(...) resume(co, ...) end)
	return coroutine.yield()
end
M.Signal = Signal

---------------------------------------------------------------------
-- Instances
---------------------------------------------------------------------
local BASE = { "Name", "Parent", "Archivable" }
local GUI_OBJECT = { "Position", "Size", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "BorderSizePixel",
	"BorderColor3", "BorderMode", "Visible", "ZIndex", "LayoutOrder", "ClipsDescendants", "Rotation", "Active", "AutomaticSize",
	"SizeConstraint", "Selectable", "Interactable" }
local TEXT = { "Text", "TextColor3", "TextSize", "Font", "FontFace", "TextScaled", "TextWrapped", "TextXAlignment",
	"TextYAlignment", "TextTransparency", "TextStrokeTransparency", "TextStrokeColor3", "RichText", "LineHeight",
	"TextTruncate", "MaxVisibleGraphemes" }
local IMAGE = { "Image", "ImageColor3", "ImageTransparency", "ScaleType", "SliceCenter", "SliceScale", "TileSize",
	"ImageRectOffset", "ImageRectSize", "ResampleMode" }
local BUTTON = { "AutoButtonColor", "Modal", "Selected" }
local LAYER = { "Enabled", "ResetOnSpawn", "ZIndexBehavior" }
local PART = { "Size", "CFrame", "Position", "Orientation", "Color", "BrickColor", "Material", "Anchored", "CanCollide",
	"CanTouch", "CanQuery", "CastShadow", "Transparency", "Reflectance", "TopSurface", "BottomSurface", "LeftSurface",
	"RightSurface", "FrontSurface", "BackSurface", "Locked", "Massless", "Rotation" }
local LIGHT = { "Brightness", "Range", "Color", "Shadows", "Enabled" }

local function merge(...)
	local set = {}
	for _, list in ipairs({ ... }) do for _, n in ipairs(list) do set[n] = true end end
	return set
end

local CLASSES = {
	Folder = merge(BASE),
	Model = merge(BASE, { "PrimaryPart", "WorldPivot" }),
	Part = merge(BASE, PART, { "Shape" }),
	WedgePart = merge(BASE, PART),
	CornerWedgePart = merge(BASE, PART),
	TrussPart = merge(BASE, PART),
	RemoteEvent = merge(BASE),
	RemoteFunction = merge(BASE),
	BindableEvent = merge(BASE),
	ProximityPrompt = merge(BASE, { "ActionText", "ObjectText", "KeyboardKeyCode", "GamepadKeyCode", "HoldDuration",
		"MaxActivationDistance", "RequiresLineOfSight", "Enabled", "Exclusivity", "UIOffset", "Style", "ClickablePrompt" }),
	SurfaceLight = merge(BASE, LIGHT, { "Face", "Angle" }),
	SpotLight = merge(BASE, LIGHT, { "Face", "Angle" }),
	PointLight = merge(BASE, LIGHT),
	Attachment = merge(BASE, { "Position", "CFrame", "Visible" }),
	Decal = merge(BASE, { "Texture", "Face", "Transparency", "Color3", "ZIndex" }),
	Texture = merge(BASE, { "Texture", "Face", "Transparency", "Color3", "StudsPerTileU", "StudsPerTileV", "OffsetStudsU", "OffsetStudsV" }),
	Sound = merge(BASE, { "SoundId", "Volume", "Looped", "PlaybackSpeed", "Playing", "RollOffMaxDistance", "IsPlaying", "TimePosition" }),
	ScreenGui = merge(BASE, LAYER, { "IgnoreGuiInset", "DisplayOrder", "ScreenInsets", "ClipToDeviceSafeArea" }),
	SurfaceGui = merge(BASE, LAYER, { "Adornee", "Face", "SizingMode", "PixelsPerStud", "CanvasSize", "LightInfluence",
		"Brightness", "MaxDistance", "AlwaysOnTop", "ClipsDescendants", "ZOffset", "ToolPunchThroughDistance", "Active" }),
	BillboardGui = merge(BASE, LAYER, { "Adornee", "Size", "StudsOffset", "StudsOffsetWorldSpace", "ExtentsOffset",
		"SizeOffset", "AlwaysOnTop", "MaxDistance", "LightInfluence", "Brightness", "ClipsDescendants", "Active" }),
	Frame = merge(BASE, GUI_OBJECT, { "Style" }),
	CanvasGroup = merge(BASE, GUI_OBJECT, { "GroupColor3", "GroupTransparency" }),
	ScrollingFrame = merge(BASE, GUI_OBJECT, { "CanvasSize", "ScrollBarThickness", "ScrollingDirection",
		"AutomaticCanvasSize", "CanvasPosition", "ScrollBarImageColor3", "ElasticBehavior", "ScrollingEnabled" }),
	TextLabel = merge(BASE, GUI_OBJECT, TEXT),
	TextButton = merge(BASE, GUI_OBJECT, TEXT, BUTTON),
	TextBox = merge(BASE, GUI_OBJECT, TEXT, { "PlaceholderText", "PlaceholderColor3", "ClearTextOnFocus", "MultiLine" }),
	ImageLabel = merge(BASE, GUI_OBJECT, IMAGE),
	ImageButton = merge(BASE, GUI_OBJECT, IMAGE, BUTTON, { "HoverImage", "PressedImage" }),
	UICorner = merge(BASE, { "CornerRadius" }),
	UIStroke = merge(BASE, { "Color", "Thickness", "Transparency", "ApplyStrokeMode", "LineJoinMode", "Enabled" }),
	UIGradient = merge(BASE, { "Color", "Transparency", "Rotation", "Offset", "Enabled" }),
	UITextSizeConstraint = merge(BASE, { "MaxTextSize", "MinTextSize" }),
	UIPadding = merge(BASE, { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" }),
	UIAspectRatioConstraint = merge(BASE, { "AspectRatio", "AspectType", "DominantAxis" }),
	UISizeConstraint = merge(BASE, { "MinSize", "MaxSize" }),
	UIScale = merge(BASE, { "Scale" }),
	UIListLayout = merge(BASE, { "FillDirection", "Padding", "SortOrder", "HorizontalAlignment", "VerticalAlignment", "Wraps" }),
	UIGridLayout = merge(BASE, { "CellSize", "CellPadding", "FillDirection", "SortOrder", "StartCorner",
		"HorizontalAlignment", "VerticalAlignment", "FillDirectionMaxCells" }),
	ParticleEmitter = merge(BASE, { "Texture", "Rate", "Lifetime", "Speed", "SpreadAngle", "Color", "Size", "Transparency",
		"LightEmission", "Enabled", "Acceleration", "Rotation", "RotSpeed", "EmissionDirection", "Drag" }),
	Weld = merge(BASE, { "Part0", "Part1", "C0", "C1", "Enabled" }),
	WeldConstraint = merge(BASE, { "Part0", "Part1", "Enabled" }),
	Sky = merge(BASE, { "StarCount", "CelestialBodiesShown", "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt",
		"SkyboxUp", "SunAngularSize", "MoonAngularSize", "SunTextureId", "MoonTextureId", "SkyboxOrientation" }),
	Atmosphere = merge(BASE, { "Density", "Offset", "Color", "Decay", "Glare", "Haze" }),
	BloomEffect = merge(BASE, { "Intensity", "Size", "Threshold", "Enabled" }),
	ColorCorrectionEffect = merge(BASE, { "Saturation", "Contrast", "Brightness", "TintColor", "Enabled" }),
	SunRaysEffect = merge(BASE, { "Intensity", "Spread", "Enabled" }),
	DepthOfFieldEffect = merge(BASE, { "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity", "Enabled" }),
	Lighting = merge(BASE, { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "EnvironmentDiffuseScale",
		"EnvironmentSpecularScale", "FogColor", "FogStart", "FogEnd", "GlobalShadows", "ExposureCompensation",
		"GeographicLatitude", "ColorShift_Top", "ColorShift_Bottom", "ShadowSoftness", "TimeOfDay" }),
	Humanoid = merge(BASE, { "WalkSpeed", "JumpPower", "Health", "MaxHealth", "DisplayName", "AutoRotate" }),
	SpawnLocation = merge(BASE, PART, { "Neutral", "Duration", "Enabled" }),
	-- services / special
	Player = merge(BASE, { "DisplayName", "UserId", "Character" }),
	PlayerGui = merge(BASE),
	Camera = merge(BASE, { "CFrame", "FieldOfView", "CameraType", "ViewportSize" }),
	Workspace = merge(BASE, { "CurrentCamera" }),
	Service = merge(BASE, { "TouchEnabled", "KeyboardEnabled", "GamepadEnabled", "MouseEnabled" }),
}
-- defaults that scripts read back
local DEFAULTS = {
	Enabled = true, Visible = true, Size = nil, BackgroundTransparency = 0, ZIndex = 1,
}

local Instance_ = {}
local instanceMeta = {}

local function isInstance(v) return type(v) == "table" and rawget(v, "__instance") == true end

local function childList(self) return rawget(self, "__children") end

local methods = {}
function methods:FindFirstChild(name, recursive)
	for _, c in ipairs(childList(self)) do
		if c.Name == name then return c end
	end
	if recursive then
		for _, c in ipairs(childList(self)) do
			local found = c:FindFirstChild(name, true)
			if found then return found end
		end
	end
	return nil
end
function methods:FindFirstChildOfClass(className)
	for _, c in ipairs(childList(self)) do if c.ClassName == className then return c end end
	return nil
end
function methods:FindFirstChildWhichIsA(className)
	for _, c in ipairs(childList(self)) do if c:IsA(className) then return c end end
	return nil
end
function methods:WaitForChild(name, timeout)
	local start = M.now
	while true do
		local found = self:FindFirstChild(name)
		if found then return found end
		if timeout and M.now - start >= timeout then return nil end
		local co, main = coroutine.running()
		if main or not co then error("WaitForChild(" .. name .. ") would block forever on the main thread", 2) end
		task.wait(0.05)
	end
end
function methods:GetChildren()
	local out = {}
	for i, c in ipairs(childList(self)) do out[i] = c end
	return out
end
function methods:GetDescendants()
	local out = {}
	local function walk(o) for _, c in ipairs(childList(o)) do table.insert(out, c) walk(c) end end
	walk(self)
	return out
end
function methods:IsDescendantOf(other)
	local p = rawget(self, "__props").Parent
	while p do if p == other then return true end p = rawget(p, "__props").Parent end
	return false
end
function methods:Destroy()
	for _, c in ipairs(self:GetChildren()) do c:Destroy() end
	self.Parent = nil
	rawset(self, "__destroyed", true)
end
function methods:ClearAllChildren()
	for _, c in ipairs(self:GetChildren()) do c:Destroy() end
end
function methods:IsA(className)
	local cn = self.ClassName
	if cn == className or className == "Instance" then return true end
	local families = {
		GuiObject = { Frame = 1, TextLabel = 1, TextButton = 1, TextBox = 1, ImageLabel = 1, ImageButton = 1, ScrollingFrame = 1, CanvasGroup = 1 },
		GuiButton = { TextButton = 1, ImageButton = 1 },
		BasePart = { Part = 1, WedgePart = 1, CornerWedgePart = 1, TrussPart = 1, SpawnLocation = 1 },
		PostEffect = { BloomEffect = 1, ColorCorrectionEffect = 1, SunRaysEffect = 1, DepthOfFieldEffect = 1 },
		LayerCollector = { ScreenGui = 1, SurfaceGui = 1, BillboardGui = 1 },
		Light = { PointLight = 1, SurfaceLight = 1, SpotLight = 1 },
	}
	return families[className] ~= nil and families[className][cn] ~= nil
end
function methods:SetAttribute(k, v) rawget(self, "__attrs")[k] = v
	local sig = rawget(self, "__attrSignals")[k]
	if sig then sig:Fire() end
end
function methods:GetAttribute(k) return rawget(self, "__attrs")[k] end
function methods:GetAttributes() return table.clone(rawget(self, "__attrs")) end
function methods:GetAttributeChangedSignal(k)
	local sigs = rawget(self, "__attrSignals")
	sigs[k] = sigs[k] or Signal.new()
	return sigs[k]
end
function methods:GetPropertyChangedSignal(k)
	local sigs = rawget(self, "__propSignals")
	sigs[k] = sigs[k] or Signal.new()
	return sigs[k]
end
function methods:GetFullName()
	local parts = {}
	local o = self
	while o do table.insert(parts, 1, o.Name) o = rawget(o, "__props").Parent end
	return table.concat(parts, ".")
end
function methods:PivotTo(cf) end
function methods:GetPivot() return CFrame.new() end
function methods:Clone()
	local copy = Instance.new(self.ClassName)
	for k, v in pairs(rawget(self, "__props")) do if k ~= "Parent" then rawget(copy, "__props")[k] = v end end
	for _, c in ipairs(childList(self)) do c:Clone().Parent = copy end
	return copy
end

-- class-specific methods and events
local EVENTS = {
	Sound = { "Ended" },
	TextButton = { "Activated", "MouseButton1Click", "MouseButton2Click", "MouseButton1Down", "MouseButton1Up", "MouseEnter", "MouseLeave", "InputBegan", "InputEnded" },
	ImageButton = { "Activated", "MouseButton1Click", "MouseButton2Click", "MouseButton1Down", "MouseButton1Up", "MouseEnter", "MouseLeave", "InputBegan", "InputEnded" },
	Frame = { "MouseEnter", "MouseLeave", "InputBegan" },
	ProximityPrompt = { "Triggered", "PromptShown", "PromptHidden" },
	RemoteEvent = { "OnServerEvent", "OnClientEvent" },
	BindableEvent = { "Event" },
	TextBox = { "FocusLost", "Focused" },
	Part = { "Touched" },
	Player = { "CharacterAdded", "CharacterRemoving" },
	Humanoid = { "Died" },
}

instanceMeta.__index = function(self, key)
	local props = rawget(self, "__props")
	if key == "ClassName" then return rawget(self, "__class") end
	if methods[key] then return methods[key] end
	local events = rawget(self, "__events")
	if events[key] then return events[key] end
	local extra = rawget(self, "__methods")
	if extra and extra[key] then return extra[key] end
	if props[key] ~= nil then return props[key] end
	local cls = CLASSES[rawget(self, "__class")]
	if cls[key] then
		if key == "Position" and rawget(self, "__class") ~= "Part" and props.CFrame == nil then return nil end
		if key == "Position" and props.CFrame then return props.CFrame.Position end
		return DEFAULTS[key]
	end
	-- children by name
	local child = self:FindFirstChild(key)
	if child then return child end
	-- on-screen size/position of GUI objects (a fixed 1600x900 screen in tests)
	if (key == "AbsoluteSize" or key == "AbsolutePosition") and cls.Size then
		return key == "AbsoluteSize" and Vector2.new(1600, 900) or Vector2.new(0, 0)
	end
	error(tostring(key) .. " is not a valid member of " .. rawget(self, "__class") .. " \"" .. tostring(props.Name) .. "\"", 2)
end

instanceMeta.__newindex = function(self, key, value)
	local cls = CLASSES[rawget(self, "__class")]
	local props = rawget(self, "__props")
	if key == "OnServerInvoke" or key == "OnClientInvoke" then
		if rawget(self, "__class") ~= "RemoteFunction" then error(key .. " is not a valid member", 2) end
		rawset(self, "__" .. key, value)
		return
	end
	if not cls[key] then
		error(tostring(key) .. " is not a valid member of " .. rawget(self, "__class") .. " \"" .. tostring(props.Name) .. "\"", 2)
	end
	if key == "Parent" then
		if value ~= nil and not isInstance(value) then error("Parent must be an Instance", 2) end
		local old = props.Parent
		if old then
			local list = childList(old)
			for i, c in ipairs(list) do if c == self then table.remove(list, i) break end end
		end
		props.Parent = value
		if value then
			table.insert(childList(value), self)
			local added = rawget(value, "__childAdded")
			if added then added:Fire(self) end
			-- DescendantAdded on every ancestor (only ones someone listens to)
			local a = value
			while a do
				local d = rawget(a, "__events") and rawget(a, "__events").DescendantAdded
				if d and #d.Handlers > 0 then d:Fire(self) end
				a = rawget(a, "__props") and rawget(a, "__props").Parent
			end
		end
		return
	end
	if key == "Position" and rawget(self, "__class") == "Part" then
		props.CFrame = CFrame.new(value)
		return
	end
	if key == "Name" and type(value) ~= "string" then error("Name must be a string", 2) end
	props[key] = value
	local sig = rawget(self, "__propSignals")[key]
	if sig then sig:Fire() end
end
instanceMeta.__tostring = function(self) return rawget(self, "__props").Name end

Instance = {}
function Instance.new(className, parent)
	if not CLASSES[className] then error("Unable to create an Instance of type \"" .. tostring(className) .. "\" (not in mock)", 2) end
	local self = setmetatable({
		__instance = true,
		__class = className,
		__props = { Name = className },
		__children = {},
		__attrs = {},
		__attrSignals = {},
		__propSignals = {},
		__events = {},
		__childAdded = Signal.new(),
	}, instanceMeta)
	rawget(self, "__events").ChildAdded = rawget(self, "__childAdded")
	rawget(self, "__events").Destroying = Signal.new()
	rawget(self, "__events").DescendantAdded = Signal.new()
	rawget(self, "__events").AncestryChanged = Signal.new()
	for _, e in ipairs(EVENTS[className] or {}) do rawget(self, "__events")[e] = Signal.new() end
	if className == "RemoteEvent" then
		rawset(self, "__methods", {
			FireClient = function(remote, player, ...)
				local args = table.pack(...)
				M.checkRemoteArgs(args)
				table.insert(M.remoteLog, { Remote = remote.Name, To = player, Args = args })
				if player == M.LocalPlayer then remote.OnClientEvent:Fire(unpack(args, 1, args.n)) end
			end,
			FireAllClients = function(remote, ...)
				local args = table.pack(...)
				M.checkRemoteArgs(args)
				table.insert(M.remoteLog, { Remote = remote.Name, To = "all", Args = args })
				remote.OnClientEvent:Fire(unpack(args, 1, args.n))
			end,
			FireServer = function(remote, ...)
				remote.OnServerEvent:Fire(M.LocalPlayer, ...)
			end,
		})
	elseif className == "RemoteFunction" then
		rawset(self, "__methods", {
			InvokeServer = function(remote, ...)
				local fn = rawget(remote, "__OnServerInvoke")
				if not fn then error("no OnServerInvoke") end
				return fn(M.LocalPlayer, ...)
			end,
		})
	elseif className == "BindableEvent" then
		rawset(self, "__methods", { Fire = function(b, ...) b.Event:Fire(...) end })
	elseif className == "Sound" then
		rawset(self, "__methods", { Play = function() end, Stop = function() end, Pause = function() end, Resume = function() end })
	elseif className == "ProximityPrompt" then
		rawset(self, "__methods", { InputHoldBegin = function() end })
	end
	if parent then self.Parent = parent end
	return self
end
M.isInstance = isInstance
-- A second player sending to the server (tests): M.fireAs(player, remoteEvent, ...)
function M.fireAs(player, remote, ...)
	remote.OnServerEvent:Fire(player, ...)
end

-- What Roblox can't send through a remote: mixed or holey arrays, functions, etc.
M.remoteLog = {}
M.remoteProblems = {}
function M.checkRemoteArgs(args)
	local function check(value, path, seen)
		if type(value) == "function" or type(value) == "thread" then
			table.insert(M.remoteProblems, path .. " is a " .. type(value)) return
		end
		if type(value) ~= "table" or isInstance(value) or getmetatable(value) then return end
		if seen[value] then table.insert(M.remoteProblems, path .. " is a cycle") return end
		seen[value] = true
		local numeric, strings, maxIndex, count = 0, 0, 0, 0
		for k, v in pairs(value) do
			count = count + 1
			if type(k) == "number" then
				numeric = numeric + 1
				if k > maxIndex then maxIndex = k end
				if k ~= math.floor(k) or k < 1 then table.insert(M.remoteProblems, path .. " has a non-array number key " .. k) end
			elseif type(k) == "string" then
				strings = strings + 1
			else
				table.insert(M.remoteProblems, path .. " has a " .. type(k) .. " key")
			end
			check(v, path .. "." .. tostring(k), seen)
		end
		if numeric > 0 and strings > 0 then table.insert(M.remoteProblems, path .. " mixes number and string keys") end
		if numeric > 0 and maxIndex ~= numeric then table.insert(M.remoteProblems, path .. " is an array with holes") end
		seen[value] = nil
	end
	for i = 1, args.n do check(args[i], "arg" .. i, {}) end
end

---------------------------------------------------------------------
-- Services
---------------------------------------------------------------------
local function service(name)
	local s = Instance.new("Service")
	s.Name = name
	return s
end

workspace = Instance.new("Workspace")
workspace.Name = "Workspace"
rawset(workspace, "__methods", {
	GetServerTimeNow = function() return 1790000000 + M.now end,
	Raycast = function() return nil end,
})
local camera = Instance.new("Camera")
camera.CFrame = CFrame.new(0, 10, 0)
camera.ViewportSize = Vector2.new(1600, 900)
camera.Parent = workspace
workspace.CurrentCamera = camera
Workspace = workspace

local services = {
	ReplicatedStorage = service("ReplicatedStorage"),
	ServerScriptService = service("ServerScriptService"),
	ServerStorage = service("ServerStorage"),
	Lighting = (function() local l = Instance.new("Lighting") l.Name = "Lighting" return l end)(),
	StarterGui = service("StarterGui"),
	SoundService = service("SoundService"),
	Workspace = workspace,
}
local players = service("Players")
local playerAdded, playerRemoving = Signal.new(), Signal.new()
rawget(players, "__events").PlayerAdded = playerAdded
rawget(players, "__events").PlayerRemoving = playerRemoving
local playerList = {}
rawset(players, "__methods", {
	GetPlayers = function() local o = {} for i, p in ipairs(playerList) do o[i] = p end return o end,
	GetPlayerByUserId = function(_, id) for _, p in ipairs(playerList) do if p.UserId == id then return p end end return nil end,
})
services.Players = players

function M.addPlayer(name, userId)
	local p = Instance.new("Player")
	p.Name = name
	p.DisplayName = name
	p.UserId = userId
	local gui = Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = p
	p.Parent = players
	table.insert(playerList, p)
	rawset(p, "__methods", { Kick = function() end, GetRankInGroup = function() return 0 end })
	playerAdded:Fire(p)
	return p
end
function M.giveCharacter(p)
	local char = Instance.new("Model")
	char.Name = p.Name
	for _, n in ipairs({ "HumanoidRootPart", "UpperTorso", "Head", "RightHand", "LeftHand" }) do
		local part = Instance.new("Part")
		part.Name = n
		part.Size = Vector3.new(2, 2, 1)
		part.CFrame = CFrame.new(0, 3, 0)
		part.Parent = char
	end
	local h = Instance.new("Humanoid")
	h.Name = "Humanoid"
	h.Parent = char
	char.Parent = workspace
	p.Character = char
	p.CharacterAdded:Fire(char)
	return char
end
function M.removePlayer(p)
	for i, q in ipairs(playerList) do if q == p then table.remove(playerList, i) end end
	playerRemoving:Fire(p)
	p.Parent = nil
end

local runService = service("RunService")
local renderStepped, heartbeat = Signal.new(), Signal.new()
rawget(runService, "__events").RenderStepped = renderStepped
rawget(runService, "__events").Heartbeat = heartbeat
rawget(runService, "__events").Stepped = Signal.new()
table.insert(heartbeats, renderStepped)
table.insert(heartbeats, heartbeat)
M.isClient = true
rawset(runService, "__methods", {
	IsStudio = function() return true end,
	IsClient = function() return M.isClient end,
	IsServer = function() return true end,
	BindToRenderStep = function() end,
})
services.RunService = runService

local uis = service("UserInputService")
rawget(uis, "__events").InputBegan = Signal.new()
rawget(uis, "__events").InputEnded = Signal.new()
rawget(uis, "__events").InputChanged = Signal.new()
uis.TouchEnabled = false
uis.KeyboardEnabled = true
uis.GamepadEnabled = false
uis.MouseEnabled = true
services.UserInputService = uis

local tweenService = service("TweenService")
rawset(tweenService, "__methods", {
	Create = function(_, object, info, goal)
		local tween = { Completed = Signal.new() }
		function tween:Play()
			for k, v in pairs(goal) do object[k] = v end
			task.delay(info.Time or 0, function() tween.Completed:Fire(Enum.EasingStyle.Linear) end)
		end
		function tween:Cancel() end
		function tween:Pause() end
		return tween
	end,
})
services.TweenService = tweenService

local stores = {}
M.dataStores = stores
local dss = service("DataStoreService")
rawset(dss, "__methods", {
	GetDataStore = function(_, name)
		stores[name] = stores[name] or { Data = {} }
		local st = stores[name]
		return {
			GetAsync = function(_, key) return st.Data[key] end,
			SetAsync = function(_, key, value) st.Data[key] = value end,
			UpdateAsync = function(_, key, fn) local v = fn(st.Data[key]) if v ~= nil then st.Data[key] = v end return v end,
			RemoveAsync = function(_, key) local v = st.Data[key] st.Data[key] = nil return v end,
			IncrementAsync = function(_, key, n) st.Data[key] = (st.Data[key] or 0) + (n or 1) return st.Data[key] end,
		}
	end,
	GetOrderedDataStore = function() return {} end,
})
services.DataStoreService = dss
local policy = service("PolicyService")
rawset(policy, "__methods", { GetPolicyInfoForPlayerAsync = function() return { ArePaidRandomItemsRestricted = false, IsPaidItemTradingAllowed = true } end })
services.PolicyService = policy
local textService = service("TextService")
rawset(textService, "__methods", { FilterStringAsync = function(_, text)
	return { GetNonChatStringForBroadcastAsync = function() return text end, GetNonChatStringForUserAsync = function() return text end }
end })
services.TextService = textService
local pps = service("ProximityPromptService")
rawget(pps, "__events").PromptTriggered = Signal.new()
rawget(pps, "__events").PromptShown = Signal.new()
rawget(pps, "__events").PromptHidden = Signal.new()
services.ProximityPromptService = pps

local replicatedFirst = service("ReplicatedFirst")
rawset(replicatedFirst, "__methods", { RemoveDefaultLoadingScreen = function() end })
services.ReplicatedFirst = replicatedFirst
local contentProvider = service("ContentProvider")
rawset(contentProvider, "__methods", { PreloadAsync = function() end })
services.ContentProvider = contentProvider

-- AnalyticsService: records every call so tests can check the funnel
M.analyticsLog = {}
local analyticsService = service("AnalyticsService")
local function logAnalytics(kind)
	return function(_, player, ...)
		table.insert(M.analyticsLog, { Kind = kind, Player = player and player.Name, Args = { ... } })
	end
end
rawset(analyticsService, "__methods", {
	LogCustomEvent = logAnalytics("Custom"),
	LogOnboardingFunnelStepEvent = logAnalytics("Onboarding"),
	LogFunnelStepEvent = logAnalytics("Funnel"),
	LogEconomyEvent = logAnalytics("Economy"),
	LogProgressionEvent = logAnalytics("Progression"),
})
services.AnalyticsService = analyticsService
local scriptContext = service("ScriptContext")
rawget(scriptContext, "__events").Error = Signal.new()
services.ScriptContext = scriptContext

local httpService = service("HttpService")
rawset(httpService, "__methods", { GenerateGUID = function() return tostring(math.random(1e9)) end })
services.HttpService = httpService

game = {
	JobId = "",
	PlaceId = 0,
	GetService = function(_, name)
		local s = services[name]
		if not s then error("GetService(" .. name .. ") not in mock", 2) end
		return s
	end,
	BindToClose = function() end,
	IsLoaded = function() return true end,
	Loaded = Signal.new(),
}
setmetatable(game, { __index = function(_, k) if services[k] then return services[k] end error("game." .. k .. " not in mock", 2) end })

---------------------------------------------------------------------
-- Loading scripts: ModuleScripts are registered by name under a
-- parent, and require() runs them once.
---------------------------------------------------------------------
local moduleSources = {} -- [instance] = { Source, Result, Loaded }
function M.addModule(parent, name, source)
	local holder = Instance.new("Folder")
	holder.Name = name
	rawset(holder, "__class", "Folder")
	moduleSources[holder] = { Source = source, Name = name }
	holder.Parent = parent
	return holder
end
local realRequire = require
function require(target)
	if type(target) == "string" then return realRequire(target) end
	local entry = moduleSources[target]
	if not entry then error("require: not a module", 2) end
	if not entry.Loaded then
		local chunk, err = load(entry.Source, "=" .. entry.Name)
		if not chunk then error(err, 0) end
		entry.Result = chunk()
		entry.Loaded = true
	end
	return entry.Result
end
function M.runScript(name, source)
	local chunk, err = load(source, "=" .. name)
	if not chunk then error(err, 0) end
	return task.spawn(chunk)
end

M.services = services
return M
