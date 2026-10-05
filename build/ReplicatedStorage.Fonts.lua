--[[
	Fonts (ModuleScript)
	Location: ReplicatedStorage > Fonts

	The game's type, one font per job (Roblox's built-in fonts; custom fonts
	can't be uploaded):

	  Fonts.Title   Audiowide        big screen titles ("Rulebook", "Shop")
	  Fonts.Button  Rajdhani Bold    buttons and tabs
	  Fonts.Name    Rajdhani Bold    card names
	  Fonts.Number  Sarpanch Bold    Power / HP, costs, HP badges, damage pop-ups, wallet
	  Fonts.Label   Michroma         small tags (series score, zone labels)
	  everything else (rules text, descriptions, the rulebook) stays Gotham:
	  plain and easy to read, on a phone too.

	  Fonts.Style(object)     gives a text object its role's font, picked by
	                          its Name (see ROLE_BY_NAME), and returns it
	  Fonts.Set(object, role) gives it a role directly ("Title", "Number"...)
	  Fonts.Watch(container)  styles everything in it, now and later
	                          (the FontStyler script watches the player's screens)

	Rajdhani and Sarpanch run a little smaller than Gotham at the same size,
	so text with a fixed TextSize gets a small boost (TextScaled text just fits).
]]

local Fonts = {}

local AUDIOWIDE = "rbxassetid://12187360881"
local RAJDHANI = "rbxassetid://12187375422"
local SARPANCH = "rbxasset://fonts/families/Sarpanch.json"
local MICHROMA = "rbxasset://fonts/families/Michroma.json"

local function font(family, weight)
	local ok, result = pcall(function()
		if weight then
			return Font.new(family, weight)
		end
		return Font.new(family)
	end)
	return ok and result or nil
end

local BOLD = Enum.FontWeight.Bold

Fonts.Title = font(AUDIOWIDE)
Fonts.Button = font(RAJDHANI, BOLD)
Fonts.Name = font(RAJDHANI, BOLD)
Fonts.Number = font(SARPANCH, BOLD)
Fonts.Label = font(MICHROMA)

-- how much bigger a fixed-size text should be to look as big as Gotham did
local SIZE_BOOST = {
	Button = 1.15,
	Name = 1.15,
	Number = 1.05,
	Title = 0.95, -- (Audiowide is wide: a touch smaller so titles keep their room)
	Label = 0.85, -- (Michroma is very wide)
}

-- Text objects get their role from their Name
local ROLE_BY_NAME = {
	-- card names
	CardName = "Name", CardInfoTitle = "Name", InspectTitle = "Name", DeckName = "Name",
	PickName = "Name", SingleName = "Name",
	-- numbers
	Cost = "Number", Stats = "Number", Amount = "Number", HPBadge = "Number", PopText = "Number",
	CountBadge = "Number", CardCount = "Number", CountTag = "Number", Power = "Number", HP = "Number",
	-- screen titles
	PageTitle = "Title", GraveyardTitle = "Title", MulliganTitle = "Title", PickerTitle = "Title",
	SettingsTitle = "Title", AnomalyBanner = "Title", WinnerBanner = "Title", DevTitle = "Title",
	-- small tags
	SeriesInfo = "Label", TurnPill = "Label", ZoneLabel = "Label",
}
Fonts.RoleByName = ROLE_BY_NAME

local function isText(object)
	return object:IsA("TextLabel") or object:IsA("TextButton")
end

function Fonts.Set(object, role)
	local face = role and Fonts[role]
	if not face or not object or not isText(object) or object:GetAttribute("FontRole") then
		return object
	end
	object:SetAttribute("FontRole", role)
	object.FontFace = face
	local boost = SIZE_BOOST[role]
	if boost and not object.TextScaled then
		object.TextSize = math.floor(object.TextSize * boost + 0.5)
	end
	return object
end

function Fonts.Style(object)
	if object and not object:GetAttribute("NoFont") then
		local role = ROLE_BY_NAME[object.Name]
		if role then
			Fonts.Set(object, role)
		end
	end
	return object
end

function Fonts.Watch(container)
	for _, d in ipairs(container:GetDescendants()) do
		Fonts.Style(d)
	end
	container.DescendantAdded:Connect(function(d)
		Fonts.Style(d)
	end)
end

return Fonts
