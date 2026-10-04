--[[
	MobileSupport (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > MobileSupport

	Phones and tablets only (does nothing with a mouse and keyboard):
	  - Hides Roblox's thumbstick and jump button while a full-screen menu or
	    the battle screen is open, so they can't cover End Turn or the hand
	    (they come back as soon as you're walking around again).
	  - Keeps full-screen menus out from under Roblox's top bar buttons
	    (IgnoreGuiInset off), so the top-left info and top-right Leave/Close
	    buttons stay tappable.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

if not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled then
	return
end

local GuiService = nil
pcall(function()
	GuiService = game:GetService("GuiService")
end)

local FULL_SCREEN = {
	BattleGui = true,
	ShopGui = true,
	CollectionGui = true,
	BinderGui = true,
	StarterBrowserGui = true,
	SpectateGui = true,
	SpectateInspectGui = true,
}

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local adjusted = {}

while true do
	local anyOpen = false
	for _, g in ipairs(playerGui:GetChildren()) do
		if FULL_SCREEN[g.Name] and g:IsA("ScreenGui") then
			if not adjusted[g] then
				adjusted[g] = true
				g.IgnoreGuiInset = false
			end
			if g.Enabled then
				anyOpen = true
			end
		end
	end
	if GuiService then
		pcall(function()
			GuiService.TouchControlsEnabled = not anyOpen
		end)
	end
	task.wait(0.3)
end
