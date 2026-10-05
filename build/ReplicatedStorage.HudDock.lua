--[[
	HudDock (ModuleScript)
	Location: ReplicatedStorage > HudDock

	One tidy column for the buttons you see while walking around (Play vs
	Bot, How to play, My Cards, My Binder, Pull out binder, Live games...),
	so they never overlap each other, on any screen:

	  HudDock.Add(item, order)        moves a button (or label) into the column;
	                                  lower order = higher up
	  HudDock.Popup(popup, anchor)    keeps a pop-out (e.g. the live games list)
	                                  next to its button in the column

	The column shrinks to fit short (phone) screens, and the whole thing hides
	while a battle or a full-screen menu is open. Each item still shows or
	hides itself with its own Visible, and the column closes the gap.
	(Client only.)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local HudDock = {}

local WIDTH = 150            -- column width in pixels (before shrinking)
local SHORT_SCREEN = 820     -- screens shorter than this shrink the column

-- While any of these is open, the column hides
local COVERING = {
	BattleGui = true,
	ShopGui = true,
	CollectionGui = true,
	BinderGui = true,
	StarterBrowserGui = true,
	SpectateGui = true,
	SpectateInspectGui = true,
	RulebookGui = true,
	InviteGui = true,
}

local gui, dock, scale
local popups = {}

local function ensure()
	if gui then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "HudDockGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	dock = Instance.new("Frame")
	dock.Name = "Dock"
	dock.AnchorPoint = Vector2.new(0, 0.5)
	dock.Position = UDim2.new(0, 10, 0.5, 10)
	dock.Size = UDim2.fromOffset(WIDTH, 0)
	dock.AutomaticSize = Enum.AutomaticSize.Y
	dock.BackgroundTransparency = 1
	dock.Parent = gui
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = dock
	scale = Instance.new("UIScale")
	scale.Parent = dock

	local function fit()
		local camera = workspace.CurrentCamera
		local height = camera and camera.ViewportSize.Y or SHORT_SCREEN
		scale.Scale = math.clamp(height / SHORT_SCREEN, 0.62, 1)
	end
	fit()

	-- hide under battles and full-screen menus; keep pop-outs beside their button
	task.spawn(function()
		while gui.Parent do
			local covered = false
			for _, g in ipairs(playerGui:GetChildren()) do
				if COVERING[g.Name] and g:IsA("ScreenGui") and g.Enabled then
					covered = true
					break
				end
			end
			dock.Visible = not covered
			fit()
			for popup, anchor in pairs(popups) do
				if not popup.Parent then
					popups[popup] = nil
				elseif covered or not anchor.Visible then
					popup.Visible = false
				elseif popup.Visible then
					local p, s = anchor.AbsolutePosition, anchor.AbsoluteSize
					popup.Position = UDim2.fromOffset(p.X + s.X + 8, p.Y)
				end
			end
			task.wait(RunService:IsStudio() and 0.2 or 0.3)
		end
	end)
end

function HudDock.Add(item, order)
	ensure()
	local height = item.Size.Y.Offset > 0 and item.Size.Y.Offset or 40
	item.AnchorPoint = Vector2.new(0, 0)
	item.Position = UDim2.new()
	item.Size = UDim2.fromOffset(WIDTH, height)
	item.LayoutOrder = order or 50
	item.Parent = dock
	return item
end

function HudDock.Popup(popup, anchor)
	ensure()
	popup.AnchorPoint = Vector2.new(0, 0)
	popups[popup] = anchor
	return popup
end

return HudDock
