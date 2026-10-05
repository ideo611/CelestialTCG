--[[
	FontStyler (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > FontStyler

	Gives every screen's text its font by job (see the Fonts module): card
	names, numbers, titles and small tags get their display fonts, everything
	else keeps the plain, easy-to-read one. Works on screens made later too.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fonts = require(ReplicatedStorage:WaitForChild("Fonts"))

Fonts.Watch(Players.LocalPlayer:WaitForChild("PlayerGui"))
