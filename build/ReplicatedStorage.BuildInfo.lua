--[[
	BuildInfo (ModuleScript)
	Location: ReplicatedStorage > BuildInfo

	Which version of the game this is. Every analytics event, error report and
	match record carries it, so launch patches can be compared.
	Bump BuildVersion every time you publish an update.
]]

local BuildInfo = {}

BuildInfo.BuildVersion = "2026-10-05.1"

return BuildInfo
