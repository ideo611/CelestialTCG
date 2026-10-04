-- Works out where every GUI object lands on a screen of the given size
-- (Position/Size/AnchorPoint, UIAspectRatioConstraint, UIPadding) and
-- returns a flat list for render_gui.py to draw.
local M = ...

local function abs(udim2, w, h)
	return udim2.X.Scale * w + udim2.X.Offset, udim2.Y.Scale * h + udim2.Y.Offset
end

local function prop(o, k)
	return rawget(o, "__props")[k]
end

local function color(c)
	if not c then return nil end
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

return function(root, width, height)
	local out = {}
	local function walk(o, px, py, pw, ph, depth, zbase, clip)
		-- layouts place children themselves
		local list = o:FindFirstChildOfClass("UIListLayout")
		local grid = o:FindFirstChildOfClass("UIGridLayout")
		local placed = {}
		if list or grid then
			local kids = {}
			for i, c in ipairs(o:GetChildren()) do
				if c:IsA("GuiObject") and prop(c, "Visible") ~= false then table.insert(kids, { c, i }) end
			end
			table.sort(kids, function(a, b)
				local la, lb = prop(a[1], "LayoutOrder") or 0, prop(b[1], "LayoutOrder") or 0
				if la ~= lb then return la < lb end
				return a[2] < b[2]
			end)
			if list then
				local horizontal = prop(list, "FillDirection") and prop(list, "FillDirection").Name == "Horizontal"
				local pad = prop(list, "Padding") or UDim.new(0, 0)
				local cursor = 0
				for _, k in ipairs(kids) do
					local c = k[1]
					local w, h = abs(prop(c, "Size") or UDim2.fromOffset(100, 100), pw, ph)
					if horizontal then
						placed[c] = { px + cursor, py, w, h }
						cursor = cursor + w + pad.Scale * pw + pad.Offset
					else
						placed[c] = { px, py + cursor, w, h }
						cursor = cursor + h + pad.Scale * ph + pad.Offset
					end
				end
			else
				local cw, ch = abs(prop(grid, "CellSize") or UDim2.fromOffset(100, 100), pw, ph)
				local gp = prop(grid, "CellPadding") or UDim2.fromOffset(5, 5)
				local gx, gy = abs(gp, pw, ph)
				local perRow = math.max(1, math.floor((pw + gx) / (cw + gx)))
				for i, k in ipairs(kids) do
					local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
					placed[k[1]] = { px + col * (cw + gx), py + row * (ch + gy), cw, ch }
				end
			end
		end
		for _, child in ipairs(o:GetChildren()) do
			local cls = child.ClassName
			if child:IsA("GuiObject") and prop(child, "Visible") ~= false then
				local size = prop(child, "Size") or UDim2.fromOffset(100, 100)
				local pos = prop(child, "Position") or UDim2.new(0, 0, 0, 0)
				local anchor = prop(child, "AnchorPoint") or Vector2.new(0, 0)
				-- padding of the parent
				local w, h = abs(size, pw, ph)
				local aspect = child:FindFirstChildOfClass("UIAspectRatioConstraint")
				if aspect then
					local ratio = prop(aspect, "AspectRatio") or 1
					if w / math.max(h, 0.001) > ratio then w = h * ratio else h = w / ratio end
				end
				local x, y = abs(pos, pw, ph)
				x = px + x - anchor.X * w
				y = py + y - anchor.Y * h
				if placed[child] then
					x, y, w, h = placed[child][1], placed[child][2], placed[child][3], placed[child][4]
				end
				local entry = {
					Name = child.Name, Class = cls, X = x, Y = y, W = w, H = h, Depth = depth,
					Z = zbase + (prop(child, "ZIndex") or 1),
					Bg = color(prop(child, "BackgroundColor3") or Color3.fromRGB(163, 162, 165)),
					BgT = prop(child, "BackgroundTransparency") or 0,
					Clip = clip,
				}
				if cls == "TextLabel" or cls == "TextButton" then
					entry.Text = prop(child, "Text") or (cls == "TextButton" and "Button" or "Label")
					entry.TextColor = color(prop(child, "TextColor3") or Color3.new(0, 0, 0))
					local constraint = child:FindFirstChildOfClass("UITextSizeConstraint")
					entry.MaxText = constraint and prop(constraint, "MaxTextSize") or (prop(child, "TextScaled") and 100 or (prop(child, "TextSize") or 14))
					entry.Scaled = prop(child, "TextScaled") or false
					local xa = prop(child, "TextXAlignment")
					local ya = prop(child, "TextYAlignment")
					entry.XAlign = xa and xa.Name or "Center"
					entry.YAlign = ya and ya.Name or "Center"
					local font = prop(child, "Font")
					entry.Bold = not font or font.Name:find("Bold") ~= nil or font.Name:find("Black") ~= nil
					entry.TextT = prop(child, "TextTransparency") or 0
				end
				if cls == "ImageLabel" or cls == "ImageButton" then
					entry.Image = prop(child, "Image")
					entry.ImageT = prop(child, "ImageTransparency") or 0
					entry.ImageColor = color(prop(child, "ImageColor3") or Color3.new(1, 1, 1))
					local st = prop(child, "ScaleType")
					if st and st.Name == "Slice" then
						local r = prop(child, "SliceCenter")
						if r then
							entry.Slice = { r.Min.X, r.Min.Y, r.Max.X, r.Max.Y }
							entry.SliceScale = prop(child, "SliceScale") or 1
						end
					end
				end
				local corner = child:FindFirstChildOfClass("UICorner")
				if corner then
					local r = prop(corner, "CornerRadius") or UDim.new(0, 8)
					entry.Corner = r.Scale * math.min(w, h) + r.Offset
				end
				local stroke = child:FindFirstChildOfClass("UIStroke")
				if stroke and prop(stroke, "Enabled") ~= false then
					entry.Stroke = color(prop(stroke, "Color") or Color3.new(0, 0, 0))
					entry.StrokeT = prop(stroke, "Transparency") or 0
					entry.StrokeW = prop(stroke, "Thickness") or 1
				end
				local grad = child:FindFirstChildOfClass("UIGradient")
				if grad and prop(grad, "Transparency") then
					local kp = prop(grad, "Transparency").Keypoints
					local total = 0
					for _, k in ipairs(kp) do total = total + k.Value end
					entry.GradT = total / #kp
				end
				if grad and prop(grad, "Color") then
					local kp = prop(grad, "Color").Keypoints
					entry.Grad = { color(kp[1].Value), color(kp[#kp].Value) }
					entry.GradRot = prop(grad, "Rotation") or 0
				end
				table.insert(out, entry)
				local pad = child:FindFirstChildOfClass("UIPadding")
				local cx, cy, cw, ch = x, y, w, h
				if pad then
					local l = prop(pad, "PaddingLeft") or UDim.new(0, 0)
					local r = prop(pad, "PaddingRight") or UDim.new(0, 0)
					local t = prop(pad, "PaddingTop") or UDim.new(0, 0)
					local b = prop(pad, "PaddingBottom") or UDim.new(0, 0)
					cx = x + l.Scale * w + l.Offset
					cw = w - (l.Scale + r.Scale) * w - l.Offset - r.Offset
					cy = y + t.Scale * h + t.Offset
					ch = h - (t.Scale + b.Scale) * h - t.Offset - b.Offset
				end
				local childClip = clip
				if prop(child, "ClipsDescendants") or cls == "CanvasGroup" then
					childClip = { x, y, w, h }
				end
				walk(child, cx, cy, cw, ch, depth + 1, entry.Z * 0, childClip)
			end
		end
	end
	walk(root, 0, 0, width, height, 0, 0, nil)
	return out
end
