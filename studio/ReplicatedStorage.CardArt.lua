--[[
	CardArt (ModuleScript)
	Location: ReplicatedStorage > CardArt

	Image IDs for card frames and card art. To add art for a card:
	upload the image, copy its Asset ID, and paste the number next to the
	card's ID below. Cards without art show a placeholder.

	Frames: one per faction, Commander frames, and Celestial frames (one per
	faction pair). A card with no frame for its faction yet uses the plain
	placeholder look.
]]

local CardArt = {}

CardArt.Frames = {
	Solar = 79746835811021,
	Lunar = 102668499743179,
	Neutral = 120677589782616,
}

CardArt.CommanderFrames = {
	Solar = 77326985301896,
	Lunar = 85661220983840,
}

-- Celestial frames, one per faction pair. The key is the two factions in
-- alphabetical order joined by "+". A Celestial whose pair has no frame yet
-- uses its first faction's frame.
CardArt.CelestialFrames = {
	["Comet+Solar"] = 120784808544612,   -- Flare Stallion
	["Lunar+Nebula"] = 116820367760757,  -- Moonveil Jellyfish
}

local function pairKey(factions)
	local sorted = {}
	for i, faction in ipairs(factions) do
		sorted[i] = faction
	end
	table.sort(sorted)
	return table.concat(sorted, "+")
end
CardArt.PairKey = pairKey

CardArt.Art = {
	["CMD-SOL-01"] = 83792005053121,      -- Captain Sol Varro
	["CMD-LUN-01"] = 111007143043644,     -- Tidekeeper Selene
	["CEL-04"] = 72858623282065,          -- Flare Stallion
	["CEL-05"] = 89521475383976,          -- Moonveil Jellyfish
	["SOL-001"] = 74941966178493,         -- Ember Scout
	["SOL-002"] = 75543544177633,         -- Kindle
	["SOL-003"] = 87100241827591,         -- Sunforge Cadet
	["SOL-004"] = 130032222460905,        -- Flarecat
	["SOL-005"] = 125129541407758,        -- Solar Flare
	["SOL-006"] = 121870336565708,        -- Cinder Guard
	["SOL-007"] = 70974335617220,         -- Solar Lancer
	["SOL-008"] = 127414806233082,        -- Blazewing Hawk
	["SOL-009"] = 71599889382968,         -- Heat Wave
	["SOL-010"] = 119307832683182,        -- Corona Knight
	["SOL-011"] = 119211835919734,        -- Dawnbreaker Titan
	["SOL-012"] = 86290242118858,         -- Varro's Rally
	["SOL-013"] = 129985873476391,        -- Heart of the Sun
	["SOL-014"] = 129369069459921, -- Spark Sprite
	["SOL-015"] = 120036589162678, -- Sunburst
	["SOL-016"] = 87245204531914, -- Forge Hound
	["SOL-017"] = 95853107702209, -- Ember Drummer
	["SOL-018"] = 108919318603064, -- Magma Brute
	["SOL-019"] = 109416342774310, -- Sunstrike
	["SOL-020"] = 115302491491624, -- Solar Phoenix
	["SOL-021"] = 136099288779727, -- Nova Burst
	["SOL-022"] = 118823487152591, -- Blaze Marshal
	["LUN-001"] = 83555516985417,         -- Moonlit Wisp
	["LUN-002"] = 129333504553457,        -- Tidal Blessing
	["LUN-003"] = 134137973924981,        -- Silver Barrier
	["LUN-004"] = 122109741882017,        -- Crescent Archer
	["LUN-005"] = 103093993937214,        -- Tide Sentinel
	["LUN-006"] = 72970664627712,         -- Moonbeam
	["LUN-007"] = 96354206560758,         -- Harbor Warden
	["LUN-008"] = 134307548598907,        -- Lunar Priestess
	["LUN-009"] = 129265261660031,        -- Eclipse Veil
	["LUN-010"] = 113758665881643,        -- Silver Knight
	["LUN-011"] = 124292719373290,        -- Tide Colossus
	["LUN-012"] = 82814880508891,         -- Selene's Tide
	["LUN-013"] = 74306276121042,         -- Moon Leviathan
	["LUN-014"] = 76453621306050, -- Pearl Crab
	["LUN-015"] = 70963954431091, -- Stargazer's Chart
	["LUN-016"] = 85720349863731, -- Reef Guardian
	["LUN-017"] = 118691191614125, -- Silver Mender
	["LUN-018"] = 79779161132084, -- Tide Caller
	["LUN-019"] = 135270211339096, -- Undertow
	["LUN-020"] = 112220932543488, -- Crescent Warden
	["LUN-021"] = 91963237965400, -- Riptide
	["LUN-022"] = 92523214092552, -- Moonlight Oracle
	-- ["NEU-001"] = 0,                   -- Star Map (not uploaded yet)
}

-- Full-art frames for Mythic Commanders and Celestials (no text plates).
-- One per faction; a Mythic without a frame for its faction uses the normal look.
CardArt.MythicFrames = {
	Solar = 130074440800190, -- sol-mythic_frame
	Lunar = 77963875568896, -- lun-mythic_frame
}

local function asset(id)
	if type(id) == "number" and id > 0 then
		return "rbxassetid://" .. id
	end
	return nil
end

function CardArt.FrameFor(card)
	if card.Type == "Commander" then
		return asset(CardArt.CommanderFrames[card.Faction])
	end
	if card.Type == "Celestial" and card.PairsWith then
		local frame = asset(CardArt.CelestialFrames[pairKey(card.PairsWith)])
		if frame then
			return frame
		end
	end
	return asset(CardArt.Frames[card.Faction])
end

-- The full-art Mythic frame for a Commander or Celestial, or nil
function CardArt.MythicFrameFor(card)
	if card.Type ~= "Commander" and card.Type ~= "Celestial" then
		return nil
	end
	return asset(CardArt.MythicFrames[card.Faction])
end

function CardArt.ArtFor(cardId)
	return asset(CardArt.Art[cardId])
end

return CardArt