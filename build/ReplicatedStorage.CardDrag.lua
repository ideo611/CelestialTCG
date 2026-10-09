--[[
	CardDrag (ModuleScript)
	Location: ReplicatedStorage > CardDrag

	Drag a card from your hand onto the board (mouse or finger), the way most
	card games work. Tap-then-tap still works too; a drag only starts once the
	pointer has moved a little, so a tap stays a tap.

	  CardDrag.Attach(button, {
	      Layer     = the frame the dragged copy is drawn in,
	      CanDrag   = function() -> true if this card may be dragged right now,
	      MakeGhost = function(parent) -> a frame drawing the card (sized like the
	                  button, or GhostSize = a UDim2 when the button isn't card-shaped),
	      OnStart   = function() (the drag began),
	      OnDrop    = function(point) (released: point = Vector2 in the same
	                  space as GuiObject.AbsolutePosition),
	  })
	  CardDrag.Swallowed()   true right after a drop: the button's own tap
	                         (Activated) should do nothing
	  CardDrag.Dragging()    true while a card is being dragged
]]

local UserInputService = game:GetService("UserInputService")

local CardDrag = {}
CardDrag.Threshold = 14 -- pixels the pointer must move before it's a drag

local swallowUntil = 0
local dragging = false

function CardDrag.Swallowed()
	return os.clock() < swallowUntil
end

function CardDrag.Dragging()
	return dragging
end

local function point(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

function CardDrag.Attach(button, opts)
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		if dragging or (opts.CanDrag and not opts.CanDrag()) then
			return
		end
		local start = point(input)
		local size = button.AbsoluteSize
		local layer = opts.Layer
		local started, ghost = false, nil
		local changedConnection, endedConnection

		local function place(p)
			if ghost and layer then
				local origin = layer.AbsolutePosition
				ghost.Position = UDim2.fromOffset(p.X - origin.X, p.Y - origin.Y)
			end
		end

		local function stop()
			if changedConnection then
				changedConnection:Disconnect()
			end
			if endedConnection then
				endedConnection:Disconnect()
			end
			if ghost then
				ghost:Destroy()
				ghost = nil
			end
			dragging = false
		end

		changedConnection = UserInputService.InputChanged:Connect(function(moved)
			if kind == Enum.UserInputType.Touch then
				if moved ~= input then
					return
				end
			elseif moved.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			local p = point(moved)
			local dx, dy = p.X - start.X, p.Y - start.Y
			if not started and dx * dx + dy * dy >= CardDrag.Threshold * CardDrag.Threshold then
				if opts.CanDrag and not opts.CanDrag() then
					stop() -- (e.g. the hold already opened the card's details)
					return
				end
				started = true
				dragging = true
				if layer and opts.MakeGhost then
					ghost = Instance.new("Frame")
					ghost.Name = "DraggedCard"
					ghost.AnchorPoint = Vector2.new(0.5, 0.6)
					ghost.Size = opts.GhostSize
						or UDim2.fromOffset(math.max(size.X, 60) * 1.1, math.max(size.Y, 84) * 1.1)
					ghost.BackgroundTransparency = 1
					ghost.ZIndex = 40
					ghost.Parent = layer
					opts.MakeGhost(ghost)
					for _, d in ipairs(ghost:GetDescendants()) do
						if d:IsA("GuiObject") then
							d.ZIndex = d.ZIndex + 40
						end
					end
				end
				if opts.OnStart then
					opts.OnStart()
				end
			end
			if started then
				place(p)
			end
		end)

		endedConnection = UserInputService.InputEnded:Connect(function(released)
			local mine = (kind == Enum.UserInputType.Touch and released == input)
				or (kind == Enum.UserInputType.MouseButton1 and released.UserInputType == Enum.UserInputType.MouseButton1)
			if not mine then
				return
			end
			local wasDrag = started
			local p = point(released)
			stop()
			if wasDrag then
				swallowUntil = os.clock() + 0.3
				if opts.OnDrop then
					opts.OnDrop(p)
				end
			end
		end)
	end)
	return button
end

return CardDrag
