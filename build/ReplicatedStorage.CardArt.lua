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
	Nebula = 100053655681505,  -- frame_nebula
	Void = 81794904819004,     -- frame_void
	Comet = 79024688101286,    -- frame_comet
	Neutral = 120677589782616,
}

CardArt.CommanderFrames = {
	Solar = 77326985301896,
	Lunar = 85661220983840,
	Nebula = 100912005686788,  -- cmd_frame_nebula
	Void = 124165248303851,    -- cmd_frame_void
	Comet = 105694291603978,   -- cmd_frame_comet
}

-- Celestial frames, one per faction pair. The key is the two factions in
-- alphabetical order joined by "+". A Celestial whose pair has no frame yet
-- uses its first faction's frame.
CardArt.CelestialFrames = {
	["Comet+Solar"] = 120784808544612,   -- Flare Stallion
	["Lunar+Nebula"] = 116820367760757,  -- Moonveil Jellyfish
	["Lunar+Void"] = 101468902720408,    -- Umbra
	["Nebula+Solar"] = 87946117521214,   -- Protostar Colossus
	["Lunar+Solar"] = 130506906051774,   -- Equinox Seraph
	["Solar+Void"] = 126529862721958,    -- Black Sun Harbinger
	["Comet+Lunar"] = 105696675577767,   -- Tidewake Leviathan
	["Nebula+Void"] = 123266914719015,   -- Pulsar Remnant
	["Comet+Nebula"] = 136997684160894,  -- Aurora Skywhale
	["Comet+Void"] = 111884976441268,    -- Oort Reaper
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
	-- Neutral (uploaded Oct 1)
	["NEU-001"] = 138173220271760,   -- Star Map
	-- Commanders (uploaded Oct 1)
	["CMD-COM-01"] = 90269436455064, -- Halley Voss Comet Rider
	["CMD-COM-02"] = 93805674703386, -- Kessa Frostwake
	["CMD-LUN-02"] = 94803581915403, -- Lyra The Night Archivist
	["CMD-NEB-01"] = 119177939796231, -- Seraphine The Star Nursery
	["CMD-NEB-02"] = 75406486178912, -- Orion The Cloud Sage
	["CMD-SOL-02"] = 108741089311793, -- Ignara The Forge Mother
	["CMD-VOI-01"] = 98626262962941, -- Malakar The Hollow King
	["CMD-VOI-02"] = 112235019689900, -- Nyx The Event Horizon
	-- Celestials (uploaded Oct 1)
	["CEL-06"] = 133737820086806,    -- Umbra The Eclipse Wyrm
	["CEL-07"] = 109052257730987,    -- Protostar Colossus
	["CEL-08"] = 118221618029941,    -- Equinox Seraph
	["CEL-09"] = 121268795981685,    -- Black Sun Harbinger
	["CEL-10"] = 118116715337400,    -- Tidewake Leviathan
	["CEL-11"] = 100617207058079,    -- Pulsar Remnant
	["CEL-12"] = 105780313519138,    -- Aurora Skywhale
	["CEL-13"] = 124323167894287,    -- Oort Reaper
	-- Nebula (uploaded Oct 1)
	["NEB-001"] = 91912313068644,    -- Stardust Mote
	["NEB-002"] = 123409213514342,   -- Nursery Spark
	["NEB-003"] = 140101937275158,   -- Gasbloom Sprout
	["NEB-004"] = 103878911374908,   -- Prism Moth
	["NEB-005"] = 74235066039921,    -- Stellar Seedling
	["NEB-006"] = 113481407418319,   -- Cloud Shepherd
	["NEB-007"] = 113087266284816,   -- Spore Burst
	["NEB-008"] = 92529311092140,    -- Photon Gardener
	["NEB-009"] = 79257245502277,    -- Drift Grazer
	["NEB-010"] = 95238402727562,    -- Star Cradle
	["NEB-011"] = 79058379624049,    -- Coral Golem
	["NEB-012"] = 130096927975027,   -- Nova Hatchling
	["NEB-013"] = 71846309997741,    -- Gravity Bloom
	["NEB-014"] = 80743347243131,    -- Aurora Stag
	["NEB-015"] = 121693391265817,   -- Starseed Druid
	["NEB-016"] = 84424705748675,    -- Bloom Surge
	["NEB-017"] = 123006675180758,   -- Veil Ray
	["NEB-018"] = 108847268020919,   -- Pulse Of Creation
	["NEB-019"] = 116864697878790,   -- Pillar Titan
	["NEB-020"] = 88582687695273,    -- Genesis Bloom
	["NEB-021"] = 127050113180975,   -- Cradle Warden
	["NEB-022"] = 96999557990274,    -- The First Light
	-- Void (uploaded Oct 1)
	["VOI-001"] = 120548105078337,   -- Shade Wisp
	["VOI-002"] = 129381471314939,   -- Hollow Pact
	["VOI-003"] = 73495006456124,    -- Gravity Mite
	["VOI-004"] = 83930445758102,    -- Entropy Bolt
	["VOI-005"] = 110784513155447,   -- Duskforged Sentry
	["VOI-006"] = 108155935898459,   -- Null Acolyte
	["VOI-007"] = 108879313568105,   -- Wither
	["VOI-008"] = 73999365005413,    -- Event Skimmer
	["VOI-009"] = 137204226644259,   -- Rift Stalker
	["VOI-010"] = 95262713838798,    -- Obsidian Hulk
	["VOI-011"] = 72178822489596,    -- Dark Matter Shroud
	["VOI-012"] = 136165039526029,   -- Horizon Warden
	["VOI-013"] = 119884887457145,   -- Siphon
	["VOI-014"] = 87970500202811,    -- Accretion Knight
	["VOI-015"] = 104279201211597,   -- Collapse
	["VOI-016"] = 98883729263335,    -- Umbral Lantern Bearer
	["VOI-017"] = 70887374140922,    -- Graviton Lancer
	["VOI-018"] = 127798858576301,   -- Black Tide
	["VOI-019"] = 129837385847636,   -- Singularity Behemoth
	["VOI-020"] = 131238789767318,   -- Malakar's Bargain
	["VOI-021"] = 125065392311411,   -- Hollow Archon
	["VOI-022"] = 135081471100513,   -- Night Sovereign
	-- Comet (uploaded Oct 1)
	["COM-001"] = 126137518042124,   -- Frost Skipper
	["COM-002"] = 126101762084690,   -- Slipstream
	["COM-003"] = 113866905332512,   -- Ice Courier
	["COM-004"] = 106507802313136,   -- Tailwind Glider
	["COM-005"] = 81272990953114,    -- Rime Hound
	["COM-006"] = 74631009361458,    -- Recall Beacon
	["COM-007"] = 92319396012543,    -- Ice Shard
	["COM-008"] = 106472768234110,   -- Shard Racer
	["COM-009"] = 124486847438607,   -- Glacier Ward
	["COM-010"] = 120256770746174,   -- Frostbite Archer
	["COM-011"] = 108015462038448,   -- Deflect
	["COM-012"] = 103867307573640,   -- Kuiper Drifter
	["COM-013"] = 127126951569765,   -- Hailstorm
	["COM-014"] = 139759888415282,   -- Aurora Cavalier
	["COM-015"] = 100859830104477,   -- Starlance Interceptor
	["COM-016"] = 140358799370298,   -- Perihelion Dash
	["COM-017"] = 81693182165054,    -- Iceborn Sentinel
	["COM-018"] = 137749184251390,   -- Comet Fall
	["COM-019"] = 74282111143328,    -- Vanguard Of The Long Orbit
	["COM-020"] = 105935761270528,   -- Frostwake Tide
	["COM-021"] = 115223406015242,   -- Tailwind Herald
	["COM-022"] = 95025326125800,    -- The Great Comet
	-- Anomalies and the newest cards
	["VOI-026"] = 84603203827937, -- Event Horizon
	["VOI-025"] = 91284226771210, -- Null Echo
	["NEB-025"] = 75549814752809, -- Seedfall
	["VOI-024"] = 110524349397463, -- Gravity Well
	["NEB-023"] = 120119056506758, -- Petal Ward
	["LUN-026"] = 109895296976508, -- Moonlit Mirage
	["VOI-023"] = 96171288019653, -- Gravity Anchor
	["LUN-025"] = 99196719525831, -- Tidal Reflection
	["COM-025"] = 133490816078758, -- Slingshot Orbit
	["LUN-023"] = 135586647679046, -- Moontide Siren
	["NEB-024"] = 133576615905617, -- Spore Snare
	["SOL-024"] = 132286043137458, -- Backdraft
	["COM-023"] = 103936068000560, -- Cold Snap
	["NEU-002"] = 83060116757522, -- Static Mirage
	["LUN-024"] = 112925966257971, -- Silver Veil
	["COM-024"] = 128003872314705, -- Tripwire
	["SOL-023"] = 136559646292556, -- Sunflare Ambush
	["SOL-025"] = 95989855474552, -- Supernova Snare
	["NEB-026"] = 121091162373027, -- Bloom Burst
}

-- Full-art frames for Mythic Commanders and Celestials (no text plates).
-- One per faction; a Mythic without a frame for its faction uses the normal look.
CardArt.MythicFrames = {
	Solar = 130074440800190, -- sol-mythic_frame
	Lunar = 77963875568896, -- lun-mythic_frame
	Nebula = 108393835289834, -- neb-mythic_frame
	Void = 84354495947384, -- voi-mythic_frame
	Comet = 111052120176596, -- com-mythic_frame
}

-- Frames whose name/type/stats plates are DARK (so the words on them are drawn
-- light). Add any other frame's ID here if its plate words are hard to read.
CardArt.DarkPlateFrames = {
	[81794904819004] = true,  -- frame_void
	[124165248303851] = true, -- cmd_frame_void
}

-- true when a frame image ("rbxassetid://123") has dark plates
function CardArt.HasDarkPlates(frameImage)
	local id = tonumber(tostring(frameImage or ""):match("%d+$"))
	return id ~= nil and CardArt.DarkPlateFrames[id] == true
end

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