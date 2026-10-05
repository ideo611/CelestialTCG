--[[
	BinderClient (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > BinderClient

	Card binders:
	  - "My Binder" opens your own binder: a front page you choose (click any
	    card, then "Put on front page"), then every card you own, sorted by
	    faction with divider tabs to jump around. "Full set" mode shows empty
	    sleeves for the cards you're still missing.
	  - "Pull out binder" makes your character hold it. Other players walk up
	    and use the prompt on it to flip through your pages (your binder
	    opens in your hands while they look).
	  - Flip with the arrows on screen, the arrow keys, or Q / E.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CardDatabase = require(ReplicatedStorage:WaitForChild("CardDatabase"))
local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local UiAssets = require(ReplicatedStorage:WaitForChild("UiAssets"))
local UiTheme = require(ReplicatedStorage:WaitForChild("UiTheme"))
local HudDock = require(ReplicatedStorage:WaitForChild("HudDock"))
local SoundAssets = require(ReplicatedStorage:WaitForChild("SoundAssets"))
local remotes = ReplicatedStorage:WaitForChild("BinderRemotes")
local request = remotes:WaitForChild("BinderRequest")
local binderEvent = remotes:WaitForChild("BinderEvent")

local player = Players.LocalPlayer

local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(185, 178, 210)
local GOLD = Color3.fromRGB(240, 205, 120)
local PAGE = Color3.fromRGB(20, 19, 27)
local PANEL = Color3.fromRGB(34, 30, 52)
local GREY = Color3.fromRGB(80, 80, 92)
local GREEN = Color3.fromRGB(60, 140, 90)
local CARD_ASPECT = 1060 / 1484
local POCKETS = 9

local COVER_COLORS = { Black = Color3.fromRGB(34, 32, 44) }
for faction, color in pairs(CardVisuals.FactionColors) do
	COVER_COLORS[faction] = color
end
local COVERS = { "Black", "Solar", "Lunar", "Nebula", "Void", "Comet" }
local SECTIONS = { "Solar", "Lunar", "Nebula", "Void", "Comet", "Neutral" }
local TYPE_ORDER = { Commander = 1, Celestial = 2, Unit = 3, Spell = 4, Anomaly = 5 }
local FINISH_ORDER = { "Base", "Holo", "Textured", "3D", "Mythic" }
local FINISH_RANK = { Base = 1, Holo = 2, Textured = 3, ["3D"] = 4, Mythic = 5 }

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------
local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function label(parent, name, position, size, text, maxSize, extra)
	local l = make("TextLabel", {
		Name = name,
		Position = position,
		Size = size,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextWrapped = true,
	}, parent)
	for key, value in pairs(extra or {}) do
		l[key] = value
	end
	make("UITextSizeConstraint", { MaxTextSize = maxSize or 20, MinTextSize = 9 }, l)
	return l
end

local function button(parent, name, text, position, size, color)
	local b = make("TextButton", {
		Name = name,
		Text = text,
		Position = position,
		Size = size,
		BackgroundColor3 = color or PANEL,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		AutoButtonColor = true,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, b)
	make("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 10 }, b)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, b)
	return UiTheme.Button(b)
end

local function clear(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if not child:GetAttribute("ThemePart") then -- (keeps the menu's border and plate)
			child:Destroy()
		end
	end
end

local function sortIds(ids)
	table.sort(ids, function(a, b)
		local ca, cb = CardDatabase.GetCard(a), CardDatabase.GetCard(b)
		if TYPE_ORDER[ca.Type] ~= TYPE_ORDER[cb.Type] then
			return TYPE_ORDER[ca.Type] < TYPE_ORDER[cb.Type]
		end
		if (ca.EnergyCost or 0) ~= (cb.EnergyCost or 0) then
			return (ca.EnergyCost or 0) < (cb.EnergyCost or 0)
		end
		return ca.Name < cb.Name
	end)
	return ids
end

local function ask(kind, args)
	local ok, a, b = pcall(function()
		return request:InvokeServer(kind, args or {})
	end)
	if not ok then
		return false, "Couldn't reach the server."
	end
	return a, b
end

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local binder = nil        -- the binder being looked at (from the server)
local mine = false        -- true when it's your own binder
local mode = "Owned"      -- "Owned" or "Set"
local spread = 0          -- which two pages are open (0 = inside cover + front page)
local pages = {}          -- built from the binder: { Title, Section, Pockets = { ... } } or { Kind = "Title" }
local sectionStart = {}   -- [section] = page index
local isOut = false
local message = ""
local render
local flipping = false

---------------------------------------------------------------------
-- Building the pages
---------------------------------------------------------------------
local function countOf(entry)
	local total = 0
	for _, count in pairs(entry or {}) do
		total = total + count
	end
	return total
end

local function bestFinish(entry)
	local best = "Base"
	for finish, count in pairs(entry or {}) do
		if count > 0 and (FINISH_RANK[finish] or 0) > FINISH_RANK[best] then
			best = finish
		end
	end
	return best
end

local function buildPages()
	pages, sectionStart = {}, {}
	local collection = binder.Collection or {}
	-- page 1: inside cover (stats); page 2: the front page (showcase)
	table.insert(pages, { Kind = "Title" })
	local showcase = {}
	for _, entry in ipairs(binder.Showcase or {}) do
		table.insert(showcase, { CardId = entry.CardId, Finish = entry.Finish, Count = 0, Showcase = true })
	end
	table.insert(pages, { Kind = "Showcase", Title = "Front page", Section = "Front", Pockets = showcase })
	sectionStart.Front = 1

	local bySection = {}
	for _, card in ipairs(CardDatabase.GetAllCards()) do
		-- switched-off Anomalies only show if you own one
		if card.Type ~= "Anomaly" or CardDatabase.IsMainDeckType(card.Type) or countOf(collection[card.Id]) > 0 then
			local section = card.Faction
			bySection[section] = bySection[section] or {}
			table.insert(bySection[section], card.Id)
		end
	end
	for _, section in ipairs(SECTIONS) do
		local pockets = {}
		for _, id in ipairs(sortIds(bySection[section] or {})) do
			local entry = collection[id]
			if mode == "Set" then
				local total = countOf(entry)
				table.insert(pockets, {
					CardId = id,
					Finish = bestFinish(entry),
					Count = total,
					Missing = total == 0,
				})
			else
				for _, finish in ipairs(FINISH_ORDER) do
					local count = entry and entry[finish] or 0
					if count > 0 then
						table.insert(pockets, { CardId = id, Finish = finish, Count = count })
					end
				end
			end
		end
		if #pockets > 0 then
			sectionStart[section] = #pages
			for i = 1, #pockets, POCKETS do
				local page = { Kind = "Cards", Title = section, Section = section, Pockets = {} }
				for j = i, math.min(i + POCKETS - 1, #pockets) do
					table.insert(page.Pockets, pockets[j])
				end
				table.insert(pages, page)
			end
		end
	end
end

local function spreadCount()
	return math.max(1, math.ceil(#pages / 2))
end

local function stats()
	local collection = binder.Collection or {}
	local have, foils, total = 0, 0, 0
	local perFaction, finishes = {}, {}
	for _, card in ipairs(CardDatabase.GetAllCards()) do
		-- switched-off card types (Anomalies) don't count toward the set
		if card.Type ~= "Anomaly" or CardDatabase.IsMainDeckType(card.Type) then
			local entry = collection[card.Id]
			total = total + 1
			local f = perFaction[card.Faction] or { Have = 0, Total = 0 }
			perFaction[card.Faction] = f
			f.Total = f.Total + 1
			if countOf(entry) > 0 then
				have = have + 1
				f.Have = f.Have + 1
			end
			for finish, count in pairs(entry or {}) do
				finishes[finish] = (finishes[finish] or 0) + count
				if finish ~= "Base" then
					foils = foils + count
				end
			end
		end
	end
	return { Have = have, Total = total, Foils = foils, PerFaction = perFaction, Finishes = finishes }
end

---------------------------------------------------------------------
-- Screens
---------------------------------------------------------------------
local playerGui = player:WaitForChild("PlayerGui")

-- HUD buttons (under "My Cards")
local hud = make("ScreenGui", { Name = "BinderButtonGui", ResetOnSpawn = false, DisplayOrder = 1 }, playerGui)
local openButton = button(hud, "OpenMyBinder", "My Binder", UDim2.new(0, 10, 0.45, 52), UDim2.fromOffset(120, 44))
local outButton = button(hud, "ToggleBinderOut", "Pull out binder", UDim2.new(0, 10, 0.45, 102), UDim2.fromOffset(120, 34), GREY)
HudDock.Add(openButton, 40)
HudDock.Add(outButton, 41)
local viewersLabel = label(hud, "BinderViewers", UDim2.new(0, 136, 0.45, 102), UDim2.fromOffset(260, 34), "", 16,
	{ TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD, TextStrokeTransparency = 0.5 })
HudDock.Popup(viewersLabel, outButton) -- (beside "Pull out binder")

local gui = make("ScreenGui", {
	Name = "BinderGui",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
	DisplayOrder = 4,
	Enabled = false,
}, playerGui)
local backdrop = make("Frame", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(6, 5, 14),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
}, gui)
UiTheme.Backdrop(backdrop, { Seed = 31 })
UiTheme.FitScreen(backdrop)
local title = UiTheme.Title(label(backdrop, "BinderTitle", UDim2.new(0.03, 0, 0, 14), UDim2.new(0.45, 0, 0, 40), "", 32,
	{ TextXAlignment = Enum.TextXAlignment.Left }))
local subtitle = label(backdrop, "BinderStats", UDim2.new(0.03, 0, 0, 54), UDim2.new(0.45, 0, 0, 22), "", 18,
	{ TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = MUTED, Font = Enum.Font.Gotham })
local closeButton = button(backdrop, "CloseBinder", "Close", UDim2.new(0.87, 0, 0, 14), UDim2.new(0.1, 0, 0, 40), GREY)
local modeOwned = button(backdrop, "Mode_Owned", "My cards", UDim2.new(0.5, 0, 0, 14), UDim2.new(0.1, 0, 0, 40))
local modeSet = button(backdrop, "Mode_Set", "Full set", UDim2.new(0.61, 0, 0, 14), UDim2.new(0.1, 0, 0, 40))
local coverButton = button(backdrop, "CoverButton", "", UDim2.new(0.72, 0, 0, 14), UDim2.new(0.14, 0, 0, 40))

-- The binder itself: two pages and a spine with rings
local binderFrame = make("Frame", {
	Name = "Binder",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.47, 0.53),
	Size = UDim2.fromScale(0.82, 0.76),
	BackgroundColor3 = COVER_COLORS.Black,
	BorderSizePixel = 0,
}, backdrop)
make("UIAspectRatioConstraint", { AspectRatio = 1.5 }, binderFrame)
make("UICorner", { CornerRadius = UDim.new(0.02, 0) }, binderFrame)
local coverGradient = make("UIGradient", { Rotation = 90 }, binderFrame)
-- leather cover texture (a grey image, tinted to the cover color)
local coverTexture = UiAssets.BinderCover and make("ImageLabel", {
	Name = "CoverTexture",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = UiAssets.BinderCover,
	ScaleType = Enum.ScaleType.Crop,
	ZIndex = 0,
}, binderFrame)
if coverTexture then
	make("UICorner", { CornerRadius = UDim.new(0.02, 0) }, coverTexture)
end
make("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Thickness = 3, Transparency = 0.3 }, binderFrame)

local function pageFrame(name, x)
	local f = make("Frame", {
		Name = name,
		Position = UDim2.fromScale(x, 0.03),
		Size = UDim2.fromScale(0.455, 0.94),
		BackgroundColor3 = PAGE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, binderFrame)
	make("UICorner", { CornerRadius = UDim.new(0.015, 0) }, f)
	return f
end
local leftPage = pageFrame("LeftPage", 0.022)
local rightPage = pageFrame("RightPage", 0.523)
local spine = make("Frame", {
	Name = "Spine",
	Position = UDim2.fromScale(0.477, 0),
	Size = UDim2.fromScale(0.046, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.55,
	BorderSizePixel = 0,
}, binderFrame)
for i, y in ipairs({ 0.18, 0.5, 0.82 }) do
	local ring = make("Frame", {
		Name = "Ring" .. i,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, y),
		Size = UDim2.fromScale(1.6, 0.075),
		BackgroundColor3 = Color3.fromRGB(205, 205, 215),
		BorderSizePixel = 0,
		ZIndex = 4,
	}, spine)
	make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, ring)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(120, 120, 130), Color3.fromRGB(245, 245, 250)),
		Rotation = 90,
	}, ring)
end

-- Divider tabs sticking out of the right edge
local dividers = make("Frame", {
	Name = "Dividers",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.new(0.075, 0, 0.9, 0),
	BackgroundTransparency = 1,
}, binderFrame)
make("UIListLayout", { Padding = UDim.new(0.012, 0), SortOrder = Enum.SortOrder.LayoutOrder }, dividers)

-- Page turning
local prevButton = button(backdrop, "PrevPage", "<  Prev", UDim2.new(0.25, 0, 1, -58), UDim2.new(0.12, 0, 0, 42))
local pageLabel = label(backdrop, "PageLabel", UDim2.new(0.38, 0, 1, -54), UDim2.new(0.2, 0, 0, 34), "", 18)
local nextButton = button(backdrop, "NextPage", "Next  >", UDim2.new(0.59, 0, 1, -58), UDim2.new(0.12, 0, 0, 42))
local pullButton = button(backdrop, "PullOut", "", UDim2.new(0.78, 0, 1, -58), UDim2.new(0.19, 0, 0, 42), GREEN)
local messageLabel = label(backdrop, "BinderMessage", UDim2.new(0.03, 0, 1, -54), UDim2.new(0.21, 0, 0, 34), "", 16,
	{ TextColor3 = GOLD, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left })

-- Close-up of one card
local zoom = make("TextButton", {
	Name = "BinderZoom",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.25,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 20,
}, gui)

---------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------
local function isShowcased(cardId, finish)
	for _, entry in ipairs(binder.Showcase or {}) do
		if entry.CardId == cardId and entry.Finish == finish then
			return true
		end
	end
	return false
end

local function setShowcase(list)
	local ok, result = ask("SetShowcase", { Cards = list })
	if ok then
		binder.Showcase = result
		message = "Front page updated."
	else
		message = result
	end
	render()
end

local function showZoom(pocket)
	clear(zoom)
	local big = make("Frame", {
		Name = "BigCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.3, 0.45),
		Size = UDim2.fromScale(0.45, 0.72),
		BackgroundTransparency = 1,
		ZIndex = 20,
	}, zoom)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, big)
	CardVisuals.Draw(big, pocket.CardId, { Finish = pocket.Finish, Dim = pocket.Missing })
	CardVisuals.MakeHandheld(big) -- hold the mouse on it to move the light around
	for _, d in ipairs(big:GetDescendants()) do
		if d:IsA("GuiObject") then
			d.ZIndex = d.ZIndex + 20
		end
	end
	local card = CardDatabase.GetCard(pocket.CardId)
	-- what the card is and what its keywords mean
	CardVisuals.DrawInfoPanel(zoom, pocket.CardId, {
		Position = UDim2.fromScale(0.55, 0.08),
		Size = UDim2.fromScale(0.41, 0.72),
		ZIndex = 21,
		Finish = (not pocket.Missing) and pocket.Finish or nil,
	})
	local info
	if pocket.Missing then
		info = card.Name .. ": not in this binder yet"
	else
		local finishName = CardVisuals.FinishNames[pocket.Finish] or pocket.Finish
		info = ("%s  |  %s%s"):format(card.Name, finishName, pocket.Count > 1 and ("  |  x" .. pocket.Count) or "")
	end
	label(zoom, "ZoomInfo", UDim2.fromScale(0.05, 0.83), UDim2.fromScale(0.5, 0.045), info, 22, { ZIndex = 21 })
	if mine and not pocket.Missing then
		local on = isShowcased(pocket.CardId, pocket.Finish)
		local full = #(binder.Showcase or {}) >= POCKETS
		local text = on and "Take off front page" or (full and "Front page is full (9)" or "Put on front page")
		local b = button(zoom, "ShowcaseToggle", text, UDim2.fromScale(0.39, 0.885), UDim2.fromScale(0.22, 0.055),
			on and GREY or GREEN)
		b.ZIndex = 21
		b.Activated:Connect(function()
			local list = {}
			for _, entry in ipairs(binder.Showcase or {}) do
				if not (entry.CardId == pocket.CardId and entry.Finish == pocket.Finish) then
					table.insert(list, { CardId = entry.CardId, Finish = entry.Finish })
				end
			end
			if not on then
				if full then
					return
				end
				table.insert(list, { CardId = pocket.CardId, Finish = pocket.Finish })
			end
			zoom.Visible = false
			setShowcase(list)
		end)
	end
	label(zoom, "ZoomHint", UDim2.fromScale(0.3, 0.95), UDim2.fromScale(0.4, 0.035), "Hold the card to move the light  |  tap anywhere else to close", 16,
		{ ZIndex = 21, TextColor3 = MUTED, Font = Enum.Font.Gotham })
	zoom.Visible = true
end
zoom.Activated:Connect(function()
	zoom.Visible = false
end)

local function drawPocket(page, index, pocket)
	local col, row = (index - 1) % 3, math.floor((index - 1) / 3)
	local slot = make("TextButton", {
		Name = "Pocket_" .. index,
		Text = "",
		AutoButtonColor = false,
		Position = UDim2.fromScale(0.03 + col * 0.322, 0.02 + row * 0.312),
		Size = UDim2.fromScale(0.296, 0.296),
		BackgroundColor3 = Color3.fromRGB(32, 31, 42),
		BorderSizePixel = 0,
	}, page)
	make("UICorner", { CornerRadius = UDim.new(0.04, 0) }, slot)
	make("UIStroke", { Color = Color3.fromRGB(150, 150, 170), Transparency = 0.7, Thickness = 1 }, slot)
	if not pocket then
		return slot
	end
	local holder = make("Frame", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.94),
		BackgroundTransparency = 1,
	}, slot)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, holder)
	if pocket.Missing then
		-- an empty sleeve with the card's number, like a collector's checklist
		local card = CardDatabase.GetCard(pocket.CardId)
		label(slot, "MissingName", UDim2.fromScale(0.08, 0.32), UDim2.fromScale(0.84, 0.2), card.Name, 16,
			{ TextColor3 = Color3.fromRGB(110, 105, 130) })
		label(slot, "MissingId", UDim2.fromScale(0.08, 0.54), UDim2.fromScale(0.84, 0.1), card.Id, 12,
			{ TextColor3 = Color3.fromRGB(85, 80, 100), Font = Enum.Font.Gotham })
	else
		CardVisuals.Draw(holder, pocket.CardId, { Finish = pocket.Finish })
		if pocket.Count > 1 then
			local badge = make("Frame", {
				Name = "CountBadge",
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(0.97, 0.98),
				Size = UDim2.fromScale(0.3, 0.13),
				BackgroundColor3 = Color3.fromRGB(10, 10, 16),
				ZIndex = 12,
			}, slot)
			make("UICorner", { CornerRadius = UDim.new(0.4, 0) }, badge)
			label(badge, "Count", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), "x" .. pocket.Count, 16, { ZIndex = 12 })
		end
	end
	-- the plastic sleeve: a faint sheen across the pocket
	local sleeve = make("Frame", {
		Name = "Sleeve",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		ZIndex = 11,
	}, slot)
	make("UICorner", { CornerRadius = UDim.new(0.04, 0) }, sleeve)
	make("UIGradient", {
		Rotation = 35,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.3, 1),
			NumberSequenceKeypoint.new(0.62, 1),
			NumberSequenceKeypoint.new(0.7, 0.4),
			NumberSequenceKeypoint.new(0.78, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}, sleeve)
	slot.Activated:Connect(function()
		showZoom(pocket)
	end)
	return slot
end

local function drawTitlePage(page)
	local s = stats()
	local color = COVER_COLORS[binder.Cover] or COVER_COLORS.Black
	label(page, "OwnerName", UDim2.fromScale(0.08, 0.08), UDim2.fromScale(0.84, 0.1), binder.OwnerName, 40,
		{ Font = Enum.Font.GothamBlack })
	label(page, "BinderWord", UDim2.fromScale(0.2, 0.18), UDim2.fromScale(0.6, 0.045), "CARD BINDER", 20,
		{ TextColor3 = GOLD })
	label(page, "Completion", UDim2.fromScale(0.08, 0.27), UDim2.fromScale(0.84, 0.07),
		("%d of %d cards collected (%d%%)"):format(s.Have, s.Total, math.floor(s.Have / math.max(1, s.Total) * 100 + 0.5)),
		24, { TextColor3 = color:Lerp(WHITE, 0.5) })
	-- one bar per faction
	for i, section in ipairs(SECTIONS) do
		local f = s.PerFaction[section] or { Have = 0, Total = 0 }
		local y = 0.38 + (i - 1) * 0.07
		local emblem = UiAssets.Icon(UiAssets.Emblems[section], UDim2.fromScale(0.06, 0.05), UDim2.fromScale(0.07, y), page)
		label(page, "FactionName_" .. section, UDim2.fromScale(emblem and 0.14 or 0.08, y), UDim2.fromScale(0.2, 0.05),
			section, 18, { TextXAlignment = Enum.TextXAlignment.Left })
		local bar = make("Frame", {
			Name = "Bar_" .. section,
			Position = UDim2.fromScale(0.34, y + 0.01),
			Size = UDim2.fromScale(0.42, 0.03),
			BackgroundColor3 = Color3.fromRGB(45, 43, 58),
			BorderSizePixel = 0,
		}, page)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, bar)
		local fill = make("Frame", {
			Name = "Fill",
			Size = UDim2.fromScale(f.Total > 0 and f.Have / f.Total or 0, 1),
			BackgroundColor3 = CardVisuals.FactionColors[section] or GREY,
			BorderSizePixel = 0,
		}, bar)
		make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, fill)
		label(page, "FactionCount_" .. section, UDim2.fromScale(0.78, y), UDim2.fromScale(0.16, 0.05),
			("%d/%d"):format(f.Have, f.Total), 16, { Font = Enum.Font.Gotham, TextColor3 = MUTED })
	end
	local parts = {}
	for _, finish in ipairs({ "Holo", "Textured", "3D", "Mythic" }) do
		table.insert(parts, ("%s %d"):format(CardVisuals.FinishNames[finish] or finish, s.Finishes[finish] or 0))
	end
	label(page, "FinishCounts", UDim2.fromScale(0.08, 0.83), UDim2.fromScale(0.84, 0.05), table.concat(parts, "   "), 16,
		{ TextColor3 = GOLD, Font = Enum.Font.Gotham })
end

local function drawPage(frame, index)
	clear(frame)
	make("UICorner", { CornerRadius = UDim.new(0.015, 0) }, frame)
	local page = pages[index + 1]
	if not page then
		return
	end
	if page.Kind == "Title" then
		drawTitlePage(frame)
	else
		for i = 1, POCKETS do
			drawPocket(frame, i, page.Pockets[i])
		end
		if page.Kind == "Showcase" and #page.Pockets == 0 then
			label(frame, "ShowcaseEmpty", UDim2.fromScale(0.1, 0.4), UDim2.fromScale(0.8, 0.15),
				mine and "Your front page is empty.\nClick any card in your binder to put it here."
					or "Nothing on the front page yet.", 22, { TextColor3 = MUTED })
		end
	end
	local footer = page.Kind == "Title" and "" or (page.Title .. "  |  page " .. index)
	label(frame, "PageFooter", UDim2.fromScale(0.1, 0.955), UDim2.fromScale(0.8, 0.035), footer, 14,
		{ TextColor3 = MUTED, Font = Enum.Font.Gotham })
end

local function drawDividers()
	clear(dividers)
	make("UIListLayout", { Padding = UDim.new(0.012, 0), SortOrder = Enum.SortOrder.LayoutOrder }, dividers)
	local order = { "Front" }
	for _, section in ipairs(SECTIONS) do
		table.insert(order, section)
	end
	for i, section in ipairs(order) do
		local start = sectionStart[section]
		if start then
			local here = math.floor(start / 2) == spread
			local tab = button(dividers, "Divider_" .. section, section, UDim2.new(), UDim2.fromScale(here and 1 or 0.85, 0.11),
				CardVisuals.FactionColors[section] or Color3.fromRGB(150, 120, 60))
			tab.LayoutOrder = i
			local emblem = UiAssets.Emblems[section]
			if emblem then
				tab.Text = ""
				UiAssets.Icon(emblem, UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.1, 0.1), tab, tab.ZIndex + 1)
					:SetAttribute("Section", section)
			end
			tab.Activated:Connect(function()
				local target = math.floor(start / 2)
				if target ~= spread then
					spread = target
					render()
				end
			end)
		end
	end
end

function render()
	if not binder then
		return
	end
	local s = stats()
	title.Text = mine and "My Binder" or (binder.OwnerName .. "'s Binder")
	subtitle.Text = ("%d of %d cards (%d%%)  |  %d foils  |  %s"):format(s.Have, s.Total,
		s.Total > 0 and math.floor(s.Have / s.Total * 100) or 0, s.Foils,
		mine and (isOut and "Your binder is out: others can look through it" or "Pull it out to let others look")
			or "Flip with the arrows, Q / E, or the tabs")
	local color = COVER_COLORS[binder.Cover] or COVER_COLORS.Black
	binderFrame.BackgroundColor3 = color
	if coverTexture then
		coverTexture.ImageColor3 = color:Lerp(WHITE, 0.2)
	end
	coverGradient.Color = ColorSequence.new(color:Lerp(WHITE, 0.12), color:Lerp(Color3.new(0, 0, 0), 0.45))
	modeOwned.BackgroundColor3 = mode == "Owned" and Color3.fromRGB(90, 76, 160) or PANEL
	modeSet.BackgroundColor3 = mode == "Set" and Color3.fromRGB(90, 76, 160) or PANEL
	coverButton.Visible = mine
	coverButton.Text = "Cover: " .. (binder.Cover or "Black")
	pullButton.Visible = mine
	pullButton.Text = isOut and "Put binder away" or "Pull out binder"
	pullButton.BackgroundColor3 = isOut and GREY or GREEN
	buildPages()
	spread = math.clamp(spread, 0, spreadCount() - 1)
	drawPage(leftPage, spread * 2)
	drawPage(rightPage, spread * 2 + 1)
	drawDividers()
	pageLabel.Text = ("Pages %d-%d of %d"):format(spread * 2, spread * 2 + 1, #pages - 1)
	prevButton.Visible = spread > 0
	nextButton.Visible = spread < spreadCount() - 1
	messageLabel.Text = message
end

-- A blank sheet sweeps over the spine, then the new pages show
local function flip(direction)
	local target = spread + direction
	if flipping or not binder or target < 0 or target > spreadCount() - 1 then
		return
	end
	flipping = true
	SoundAssets.Play("PageTurn", 0.95 + math.random() * 0.1)
	local from = direction > 0 and rightPage or leftPage
	local to = direction > 0 and leftPage or rightPage
	local sheet = make("Frame", {
		Name = "FlipSheet",
		AnchorPoint = Vector2.new(direction > 0 and 0 or 1, 0),
		Position = direction > 0 and UDim2.fromScale(0.5, 0.03) or UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromScale(0.455, 0.94),
		BackgroundColor3 = Color3.fromRGB(44, 42, 56),
		BorderSizePixel = 0,
		ZIndex = 15,
	}, binderFrame)
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(110, 108, 125), Color3.fromRGB(40, 38, 50)),
		Rotation = direction > 0 and 0 or 180,
	}, sheet)
	spread = target
	message = ""
	render()
	local half = 0.11
	local first = TweenService:Create(sheet, TweenInfo.new(half, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ Size = UDim2.fromScale(0, 0.94) })
	first.Completed:Connect(function()
		-- second half: the sheet lands on the other side
		sheet.AnchorPoint = Vector2.new(direction > 0 and 1 or 0, 0)
		local second = TweenService:Create(sheet, TweenInfo.new(half, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(0.455, 0.94), BackgroundTransparency = 1 })
		second.Completed:Connect(function()
			sheet:Destroy()
			flipping = false
		end)
		second:Play()
	end)
	first:Play()
	local _ = from and to
end

---------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------
local lookingAt = nil -- UserId of the binder you're looking at (not yours)

local function openBinder(view, isMine)
	pcall(function() ReplicatedStorage.AnalyticsRemotes.Track:FireServer("binder_opened", isMine and "mine" or "other") end) -- launch analytics
	if lookingAt and lookingAt ~= view.OwnerUserId then
		ask("StopLooking", { UserId = lookingAt })
	end
	binder = view
	mine = isMine
	lookingAt = (not isMine) and view.OwnerUserId or nil
	spread = isMine and 0 or 0
	mode = "Owned"
	message = ""
	zoom.Visible = false
	if not gui.Enabled then
		SoundAssets.Play("MenuOpen")
	end
	gui.Enabled = true
	render()
end

local function closeBinder()
	if gui.Enabled then
		SoundAssets.Play("MenuClose")
	end
	gui.Enabled = false
	zoom.Visible = false
	if lookingAt then
		local id = lookingAt
		lookingAt = nil
		ask("StopLooking", { UserId = id })
	end
end

local function openMine()
	local ok, result = ask("GetMine")
	if ok and result and result.Binder then
		isOut = result.Out
		openBinder(result.Binder, true)
	end
end

local function setOut(out)
	local ok, result = ask("SetOut", { Out = out })
	if ok then
		isOut = result == true
		message = isOut and "Binder out! Other players can walk up and look through it." or "Binder put away."
	else
		message = result
	end
	outButton.Text = isOut and "Put binder away" or "Pull out binder"
	outButton.BackgroundColor3 = isOut and GREEN or GREY
	if gui.Enabled then
		render()
	end
	return ok
end

openButton.Activated:Connect(openMine)
outButton.Activated:Connect(function()
	setOut(not isOut)
end)
closeButton.Activated:Connect(closeBinder)
prevButton.Activated:Connect(function()
	flip(-1)
end)
nextButton.Activated:Connect(function()
	flip(1)
end)
modeOwned.Activated:Connect(function()
	mode = "Owned"
	spread = 0
	render()
end)
modeSet.Activated:Connect(function()
	mode = "Set"
	spread = 0
	render()
end)
coverButton.Activated:Connect(function()
	if not mine then
		return
	end
	local index = table.find(COVERS, binder.Cover) or 1
	local nextCover = COVERS[index % #COVERS + 1]
	local ok, result = ask("SetCover", { Cover = nextCover })
	if ok then
		binder.Cover = result
	else
		message = result
	end
	render()
end)
pullButton.Activated:Connect(function()
	if setOut(not isOut) and isOut then
		closeBinder() -- straight back to the world so people can walk up
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not gui.Enabled or zoom.Visible then
		return
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.Right or key == Enum.KeyCode.E then
		flip(1)
	elseif key == Enum.KeyCode.Left or key == Enum.KeyCode.Q then
		flip(-1)
	end
end)

---------------------------------------------------------------------
-- Server events
---------------------------------------------------------------------
binderEvent.OnClientEvent:Connect(function(payload)
	if payload.Kind == "OpenBinder" then
		openBinder(payload.Binder, false)
	elseif payload.Kind == "BinderUpdated" then
		if binder and not mine and binder.OwnerUserId == payload.Binder.OwnerUserId then
			binder = payload.Binder
			render()
		end
	elseif payload.Kind == "BinderClosed" then
		if binder and not mine and binder.OwnerUserId == payload.UserId then
			lookingAt = nil
			gui.Enabled = false
			zoom.Visible = false
			viewersLabel.Text = ""
			binder = nil
		end
		viewersLabel.Text = ("%s %s."):format(payload.Name, payload.Reason or "put their binder away")
		task.delay(4, function()
			if viewersLabel.Text:find(payload.Name, 1, true) then
				viewersLabel.Text = ""
			end
		end)
	elseif payload.Kind == "BinderMessage" then
		viewersLabel.Text = payload.Text
		task.delay(4, function()
			if viewersLabel.Text == payload.Text then
				viewersLabel.Text = ""
			end
		end)
	elseif payload.Kind == "Viewers" then
		local names = payload.Names or {}
		if #names == 0 then
			viewersLabel.Text = ""
		elseif #names == 1 then
			viewersLabel.Text = names[1] .. " is looking at your binder"
		else
			viewersLabel.Text = ("%s and %d more are looking at your binder"):format(names[1], #names - 1)
		end
	elseif payload.Kind == "BinderOut" then
		isOut = payload.Out
		outButton.Text = isOut and "Put binder away" or "Pull out binder"
		outButton.BackgroundColor3 = isOut and GREEN or GREY
		if gui.Enabled and mine then
			render()
		end
	end
end)

-- Hide the "Look through binder" prompt on your own binder (only on your screen)
local function hideOwnPrompt(character)
	character.ChildAdded:Connect(function(child)
		if child.Name == "HeldBinder" then
			local pages = child:WaitForChild("Pages", 5)
			local prompt = pages and pages:WaitForChild("BinderPrompt", 5)
			if prompt then
				prompt.Enabled = false
			end
		end
	end)
end
if player.Character then
	hideOwnPrompt(player.Character)
end
player.CharacterAdded:Connect(hideOwnPrompt)

-- In a match (the battle screen is up), the binder buttons and other players'
-- "Look through binder" prompts get out of the way (they covered the board on phones)
do
	local ownPrompts = {}
	local prompts = {}
	local function track(d)
		if d:IsA("ProximityPrompt") and d.Name == "BinderPrompt" then
			prompts[d] = true
			local character = player.Character
			if character and d:IsDescendantOf(character) then
				ownPrompts[d] = true
			end
		end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		track(d)
	end
	workspace.DescendantAdded:Connect(track)

	local wasInMatch = false
	task.spawn(function()
		while true do
			local battle = playerGui:FindFirstChild("BattleGui")
			local inMatch = battle ~= nil and battle.Enabled
			if inMatch ~= wasInMatch then
				wasInMatch = inMatch
				openButton.Visible = not inMatch
				outButton.Visible = not inMatch
				if inMatch then
					viewersLabel.Visible = false
				end
				for prompt in pairs(prompts) do
					if prompt.Parent then
						prompt.Enabled = not inMatch and not ownPrompts[prompt]
					else
						prompts[prompt] = nil
						ownPrompts[prompt] = nil
					end
				end
			elseif inMatch then
				-- (binders pulled out mid-match stay hidden too)
				for prompt in pairs(prompts) do
					if prompt.Parent and prompt.Enabled then
						prompt.Enabled = false
					end
				end
			end
			task.wait(0.3)
		end
	end)
end
