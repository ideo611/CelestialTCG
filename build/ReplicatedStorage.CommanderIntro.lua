--[[
	CommanderIntro (ModuleScript)
	Location: ReplicatedStorage > CommanderIntro

	The start of a match: the board goes dark and both Commanders appear big
	in the middle, one above the other (the opponent on top, you below).
	The top one says their line and flies to their zone, then the bottom one
	answers and flies to theirs, then the board lights up again and the
	opening hand (mulligan) appears.

	  CommanderIntro.Play({
	      Parent = the battle screen's root frame,
	      Top    = { CommanderId, Finish, Slot = the Commander zone it flies to },
	      Bottom = { CommanderId, Finish, Slot },
	      Visual = false to only play the voices (animations turned off),
	      OnDone = function() ... end,
	  })
	  CommanderIntro.Cancel()   stops one that's playing (a new game started)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CardVisuals = require(ReplicatedStorage:WaitForChild("CardVisuals"))
local SoundAssets = require(ReplicatedStorage:WaitForChild("SoundAssets"))

local CommanderIntro = {}

-- ON/OFF SWITCH for the intro and the Commander voice lines. Off: matches start
-- straight into the opening hand, with no voices (the server's mulligan timer and
-- replays also skip the intro's extra time).
CommanderIntro.Enabled = false

local CARD_ASPECT = 1060 / 1484
local Z = 60 -- above the board, hand and effects
local run = 0
local cleanupCurrent = nil

local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function tween(object, seconds, goal, style)
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- lifts everything CardVisuals drew above the dark backdrop
local function raise(frame)
	for _, d in ipairs(frame:GetDescendants()) do
		if d:IsA("GuiObject") and not d:GetAttribute("IntroRaised") then
			d:SetAttribute("IntroRaised", true)
			d.ZIndex = d.ZIndex + Z
		end
	end
end

local function bigCard(parent, info, y)
	local holder = make("Frame", {
		Name = "IntroCommander",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.44, y),
		Size = UDim2.fromScale(0.3, 0.42),
		BackgroundTransparency = 1,
		ZIndex = Z + 1,
	}, parent)
	make("UIAspectRatioConstraint", { AspectRatio = CARD_ASPECT }, holder)
	local scale = make("UIScale", { Scale = 0.6 }, holder)
	CardVisuals.Draw(holder, info.CommanderId, { Finish = info.Finish })
	raise(holder)
	return holder, scale
end

-- moves a card from the middle to its Commander zone (same size and place as the zone)
local function flyTo(holder, scale, slot, parent)
	if not slot or not slot.Parent then
		tween(scale, 0.3, { Scale = 0 })
		return
	end
	local origin = parent.AbsolutePosition
	local pos, size = slot.AbsolutePosition, slot.AbsoluteSize
	if size.X <= 0 then
		tween(scale, 0.3, { Scale = 0 })
		return
	end
	-- the zone keeps the card's shape; aim for its centre at its height
	tween(scale, 0.45, { Scale = 1 })
	tween(holder, 0.45, {
		Position = UDim2.fromOffset(pos.X - origin.X + size.X / 2, pos.Y - origin.Y + size.Y / 2),
		Size = UDim2.fromOffset(size.X, size.Y),
	}, Enum.EasingStyle.Cubic)
end

function CommanderIntro.Cancel()
	run = run + 1
	if cleanupCurrent then
		cleanupCurrent(false)
		cleanupCurrent = nil
	end
end

function CommanderIntro.Play(opts)
	CommanderIntro.Cancel()
	run = run + 1
	local myRun = run
	local function alive()
		return myRun == run
	end
	local parent = opts.Parent
	local made = {}
	local finished = false
	local function finish(callDone)
		if finished then
			return
		end
		finished = true
		for _, object in ipairs(made) do
			if object.Parent then
				object:Destroy()
			end
		end
		if callDone ~= false and opts.OnDone then
			task.spawn(opts.OnDone)
		end
	end
	cleanupCurrent = finish

	task.spawn(function()
		local visual = opts.Visual ~= false and parent ~= nil
		local dim, top, topScale, bottom, bottomScale
		if visual then
			-- the board goes dark (and soaks up clicks until it's over)
			dim = make("TextButton", {
				Name = "IntroDim", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = Color3.fromRGB(4, 3, 12), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = Z,
			}, parent)
			dim:SetAttribute("NoTheme", true)
			table.insert(made, dim)
			tween(dim, 0.35, { BackgroundTransparency = 0.2 })
			top, topScale = bigCard(parent, opts.Top, 0.27)
			bottom, bottomScale = bigCard(parent, opts.Bottom, 0.72)
			table.insert(made, top)
			table.insert(made, bottom)
			tween(topScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			task.wait(0.15)
			tween(bottomScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
			task.wait(0.6)
		else
			task.wait(0.6)
		end

		for i, side in ipairs({ { opts.Top, top, topScale }, { opts.Bottom, bottom, bottomScale } }) do
			if not alive() then
				return
			end
			local info, holder, scale = side[1], side[2], side[3]
			if holder then
				tween(scale, 0.25, { Scale = 1.08 }) -- the one speaking steps forward
			end
			SoundAssets.PlayVoice(info.CommanderId, alive)
			if not alive() then
				return
			end
			if holder then
				flyTo(holder, scale, info.Slot, parent)
				task.wait(0.5)
			end
			if i == 1 then
				task.wait(SoundAssets.VoiceGap or 0.4)
			end
		end
		if not alive() then
			return
		end
		if dim then
			tween(dim, 0.35, { BackgroundTransparency = 1 })
			task.wait(0.35)
		end
		finish()
	end)
end

return CommanderIntro
