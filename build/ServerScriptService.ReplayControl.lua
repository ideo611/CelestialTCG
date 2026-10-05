--[[
	ReplayControl (ModuleScript)
	Location: ServerScriptService > ReplayControl

	Shared between ReplayServer (the Studio replay panel's server side) and
	BattleTableServer (which plays the replay on the battle screen):
	  Sessions[player] = { Data = replay, Seat, Speed, Paused, Step, Names,
	                       Index, Total, Problem, Done }
	  Start(player)        set by BattleTableServer: starts the player's session
]]

return { Sessions = {}, Start = nil }
