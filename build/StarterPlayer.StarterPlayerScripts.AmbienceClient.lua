--[[
	AmbienceClient (LocalScript)
	Location: StarterPlayer > StarterPlayerScripts > AmbienceClient

	Background loops on this player's screen, crossfading as you move:
	  - inside the card shop: the cozy shop hum
	  - outside on the planet: the space wind
	  - during a match (the battle screen is open): a quiet tension bed,
	    with the room sound turned down underneath it
	The battle screen's Sound: Off button turns all of it off.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local SoundAssets = require(ReplicatedStorage:WaitForChild("SoundAssets"))

local player = Players.LocalPlayer
local FADE = TweenInfo.new(1.5, Enum.EasingStyle.Sine)
local SHOP_MARGIN = 2 -- studs past the shop's walls that still count as inside

local folder = Instance.new("Folder")
folder.Name = "Ambience"
folder.Parent = SoundService

local loops = {}
for name, entry in pairs(SoundAssets.Ambience) do
	if entry[1] ~= 0 then
		local sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = "rbxassetid://" .. entry[1]
		sound.Looped = true
		sound.Volume = 0
		sound.Parent = folder
		loops[name] = { Sound = sound, Full = entry[2], Target = -1 }
	end
end

local function setTarget(name, volume)
	local loop = loops[name]
	if not loop or loop.Target == volume then
		return
	end
	loop.Target = volume
	if volume > 0 and not loop.Sound.IsPlaying then
		loop.Sound:Play()
	end
	TweenService:Create(loop.Sound, FADE, { Volume = volume }):Play()
end

-- Is this point inside the card shop building?
local shopBox
local function insideShop(position)
	if not shopBox then
		local shop = workspace:FindFirstChild("CardShop")
		if not shop then
			return false
		end
		local ok, cframe, size = pcall(function()
			return shop:GetBoundingBox()
		end)
		if not ok then
			return false
		end
		shopBox = { CFrame = cframe, Size = size }
	end
	local localPoint = shopBox.CFrame:PointToObjectSpace(position)
	local half = shopBox.Size / 2
	return math.abs(localPoint.X) <= half.X + SHOP_MARGIN and math.abs(localPoint.Z) <= half.Z + SHOP_MARGIN
		and localPoint.Y <= half.Y + SHOP_MARGIN
end

while true do
	local on = SoundAssets.SoundOn()
	local battleGui = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("BattleGui")
	local inBattle = battleGui and battleGui.Enabled
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local inShop = root and insideShop(root.Position)
	local room = inBattle and 0.4 or 1 -- the room quiets down under a match
	setTarget("Shop", on and inShop and loops.Shop and loops.Shop.Full * room or 0)
	setTarget("Space", on and not inShop and loops.Space and loops.Space.Full * room or 0)
	setTarget("Battle", on and inBattle and loops.Battle and loops.Battle.Full or 0)
	task.wait(0.5)
end
