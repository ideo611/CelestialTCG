--[[
	LongPress (ModuleScript)
	Location: ReplicatedStorage > LongPress

	Touch screens: hold a finger on something to do its "inspect" action
	(the same thing right-click does with a mouse).

	  LongPress.Attach(button, onHold)  hold about half a second without
	                                    sliding away: onHold() runs
	  LongPress.Swallowed()             true while the finger that just
	                                    long-pressed is lifting: the button's
	                                    normal tap (Activated) should do nothing
]]

local LongPress = {}

LongPress.HoldSeconds = 0.45
LongPress.MoveTolerance = 14 -- pixels the finger may drift and still count as holding

local swallowUntil = 0

function LongPress.Swallowed()
	return os.clock() < swallowUntil
end

function LongPress.Attach(button, onHold)
	button.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local start = input.Position
		local holding, held = true, false
		local connection
		connection = input.Changed:Connect(function(property)
			if property == "UserInputState" and input.UserInputState == Enum.UserInputState.End then
				holding = false
				connection:Disconnect()
				if held then
					swallowUntil = os.clock() + 0.25 -- (the tap that ends the hold)
				end
			elseif property == "Position" and (input.Position - start).Magnitude > LongPress.MoveTolerance then
				holding = false -- a drag or a scroll, not a hold
			end
		end)
		task.delay(LongPress.HoldSeconds, function()
			if holding then -- (even if the screen redrew that card meanwhile: the card is the same)
				held = true
				swallowUntil = math.huge -- until the finger lifts
				task.delay(3, function()
					if swallowUntil == math.huge then
						swallowUntil = 0
					end
				end)
				onHold()
			end
		end)
	end)
	return button
end

return LongPress
