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

-- Commander voice lines at the start of a match: { line 1, line 2 } (one is
-- picked at random; 0 = not uploaded yet). Played one after the other, so the
-- two Commanders answer each other instead of talking at once.
SoundAssets.CommanderVoice = {
	["CMD-SOL-01"] = { 92033142575633, 77819878553800 }, -- Captain Sol Varro (vo_solvarro_1, vo_solvarro_2)
	["CMD-SOL-02"] = { 127823690781061, 105256894820470 }, -- Ignara (vo_ignara_1, vo_ignara_2)
	["CMD-LUN-01"] = { 109318856826549, 105572474923882 }, -- Tidekeeper Selene (vo_selene_1, vo_selene_2)
	["CMD-LUN-02"] = { 88078514887539, 115739841065339 }, -- Lyra (vo_lyra_1, vo_lyra_2)
	["CMD-NEB-01"] = { 81149779928736, 107204080491863 }, -- Seraphine (vo_seraphine_1, vo_seraphine_2)
	["CMD-NEB-02"] = { 110279195953707, 135028848296850 }, -- Orion (vo_orion_1, vo_orion_2)
	["CMD-VOI-01"] = { 136997322399459, 98210413407506 }, -- Malakar (vo_malakar_1, vo_malakar_2)
	["CMD-VOI-02"] = { 74362900531249, 84224818983884 }, -- Nyx (vo_nyx_1, vo_nyx_2)
	["CMD-COM-01"] = { 114818365823581, 136245591710516 }, -- Halley Voss (vo_halley_1, vo_halley_2)
	["CMD-COM-02"] = { 116628649784258, 75996365425467 }, -- Kessa Frostwake (vo_kessa_1, vo_kessa_2)
}
SoundAssets.VoiceVolume = 0.9
SoundAssets.VoiceGap = 0.45 -- seconds between the first Commander's line and the reply

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

-- The match-start exchange: the first player's Commander speaks, then the
-- other replies once the first line has finished. A new call (the next game)
-- cancels an exchange still playing.
local introRun = 0
function SoundAssets.PlayIntro(firstCommanderId, secondCommanderId, delaySeconds)
	if not RunService:IsClient() then
		return
	end
	introRun = introRun + 1
	local run = introRun
	task.spawn(function()
		task.wait(delaySeconds or 0.8)
		for i, commanderId in ipairs({ firstCommanderId, secondCommanderId }) do
			if run ~= introRun or not soundOn() then
				return
			end
			local lines = SoundAssets.CommanderVoice[commanderId]
			local choices = {}
			for _, id in ipairs(lines or {}) do
				if id ~= 0 then
					table.insert(choices, id)
				end
			end
			if #choices > 0 then
				if not folder then
					folder = Instance.new("Folder")
					folder.Name = "GameSounds"
					folder.Parent = SoundService
				end
				local sound = Instance.new("Sound")
				sound.Name = "CommanderVoice"
				sound.SoundId = "rbxassetid://" .. choices[math.random(1, #choices)]
				sound.Volume = SoundAssets.VoiceVolume
				sound.Parent = folder
				local finished = false
				sound.Ended:Connect(function()
					finished = true
				end)
				sound:Play()
				-- wait for the line to end (a missing or slow-loading sound can't hold things up)
				local started = os.clock()
				while not finished and run == introRun and os.clock() - started < 6 do
					task.wait(0.1)
				end
				if run ~= introRun then
					sound:Stop()
				end
				task.delay(1, function()
					sound:Destroy()
				end)
				if i == 1 then
					task.wait(SoundAssets.VoiceGap)
				end
			end
		end
	end)
end

return SoundAssets
