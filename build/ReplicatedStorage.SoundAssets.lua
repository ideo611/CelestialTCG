--[[
	SoundAssets (ModuleScript)
	Every sound effect and ambience loop outside the battle screen's own
	list, plus SoundAssets.Play for players' screens.

	To swap a sound: upload the new one and paste its Asset ID here.
	0 = no sound (stays silent). Volumes even out loud and quiet files.
	The battle screen's Sound: On / Off button mutes all of these too
	(the BattleSound setting is saved with your cards).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local SoundAssets = {}

-- { Asset ID, volume }
SoundAssets.Sounds = {
	-- pack opening
	PackTear = { 87147696129686, 0.6 },
	CardFlip = { 71147989250991, 0.5 },
	RevealRare = { 74932798978773, 0.45 },
	RevealEpic = { 109210160302250, 0.5 },
	RevealLegendary = { 107861132661589, 0.6 },
	RevealMythic = { 129180683462130, 0.65 },
	-- shop and menus
	Purchase = { 113279887190802, 0.5 },
	Coins = { 111294442506262, 0.5 },
	NotEnough = { 70411087340211, 0.45 },
	MenuOpen = { 128556282367801, 0.35 },
	MenuClose = { 115996945693635, 0.3 },
	PageTurn = { 83356392079946, 0.5 },
	DeckSave = { 106807629791835, 0.5 },
	TokenTrade = { 90008433196212, 0.55 },
	Shuffle = { 94170282943509, 0.5 },
	-- sky events
	ShootingStar = { 74518525809875, 0.25 },
	MeteorShower = { 102632368386515, 0.45 },
	CometFlyby = { 119199864839189, 0.5 },
	ShipLanding = { 130576785578072, 0.5 },
}

-- Background loops: { Asset ID, volume }
SoundAssets.Ambience = {
	Shop = { 135829693733632, 0.35 },
	Space = { 87791088224766, 0.35 },
	Battle = { 107332846714120, 0.25 },
}

local folder
local cache = {}

local function soundOn()
	local player = Players.LocalPlayer
	return not player or player:GetAttribute("BattleSound") ~= false
end
SoundAssets.SoundOn = soundOn

-- Plays a sound once on this player's screen. pitch is optional (1 = normal).
function SoundAssets.Play(name, pitch, volumeScale)
	if not RunService:IsClient() or not soundOn() then
		return
	end
	local entry = SoundAssets.Sounds[name]
	if not entry or entry[1] == 0 then
		return
	end
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "GameSounds"
		folder.Parent = SoundService
	end
	local sound = cache[name]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = "rbxassetid://" .. entry[1]
		sound.Parent = folder
		cache[name] = sound
	end
	sound.Volume = entry[2] * (volumeScale or 1)
	sound.PlaybackSpeed = pitch or 1
	-- a copy for each play, so quick repeats (card flips) overlap instead of cutting off
	if sound.IsPlaying then
		local copy = sound:Clone()
		copy.Parent = folder
		copy:Play()
		copy.Ended:Connect(function()
			copy:Destroy()
		end)
	else
		sound:Play()
	end
end

return SoundAssets
