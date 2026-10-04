--[[
	FactionInfo (ModuleScript)
	Location: ReplicatedStorage > FactionInfo

	Player-facing descriptions of each faction, shown at the starter deck
	table (and anywhere else that explains the factions).
]]

local FactionInfo = {}

FactionInfo.Order = { "Solar", "Lunar", "Nebula", "Void", "Comet" }

FactionInfo.Factions = {
	Solar = {
		Tagline = "Strike first, strike hard.",
		Description = "Solar is the faction of the sun-forges: knights, fire beasts and burning spells. "
			.. "It wins by hitting early and often, buffing its attackers and burning away anything in its path "
			.. "before the other side gets going.",
		Style = "Aggressive",
		Difficulty = "Easy",
		GoodFor = "Players who like fast games and big attacks.",
		Keywords = {
			{ "Rush", "Can attack the turn it's played." },
			{ "Ignite", "When played, hits the unit across from it." },
		},
	},
	Lunar = {
		Tagline = "Hold the line, then turn the tide.",
		Description = "Lunar guardians fight under the moon with shields, healing and patience. "
			.. "It outlasts the opponent: its units are hard to remove and its Commander heals, "
			.. "so long games favor Lunar.",
		Style = "Defensive",
		Difficulty = "Easy",
		GoodFor = "Players who like to protect their units and win slowly.",
		Keywords = {
			{ "Shield", "Blocks the next hit completely." },
			{ "Regen", "Heals at the end of each of your turns." },
			{ "Intercept", "Streak units can't fly past it." },
		},
	},
	Nebula = {
		Tagline = "Small seeds, giant stars.",
		Description = "Nebula is life itself: star gardeners, cosmic creatures and newborn stars. "
			.. "Its units start small and get stronger every turn they survive. "
			.. "Protect them early and they'll outgrow anything.",
		Style = "Growth",
		Difficulty = "Medium",
		GoodFor = "Players who like building up a board that gets scarier every turn.",
		Keywords = {
			{ "Grow", "Gets more Power at the start of each of your turns, for good (starting the turn after it arrives)." },
		},
	},
	Void = {
		Tagline = "Everything has a price.",
		Description = "Void draws power from black holes and the dark between stars. "
			.. "Its units slowly wear down whatever stands across from them, and its strongest cards "
			.. "cost some of your own Commander's HP. Spend wisely and nothing survives.",
		Style = "Control",
		Difficulty = "Hard",
		GoodFor = "Players who like removing threats and making risky trades.",
		Keywords = {
			{ "Decay", "At the end of your turn, the enemy unit across takes damage." },
			{ "HP cost", "Some cards also cost your Commander's HP when played." },
		},
	},
	Comet = {
		Tagline = "Too fast to block.",
		Description = "Comet riders race on ice and starlight. Their units are fragile, but many "
			.. "fly straight past blockers to hit the enemy Commander. "
			.. "Comet can also bounce units back to hand to replay them or slow the enemy down.",
		Style = "Speed",
		Difficulty = "Medium",
		GoodFor = "Players who like racing the opponent and dodging their defenses.",
		Keywords = {
			{ "Streak", "Hits the enemy Commander directly, past the unit across (which doesn't hit back). A unit with Streak or Intercept across stops it." },
			{ "Rush", "Can attack the turn it's played." },
		},
	},
}

function FactionInfo.Get(faction)
	return FactionInfo.Factions[faction]
end

return FactionInfo
