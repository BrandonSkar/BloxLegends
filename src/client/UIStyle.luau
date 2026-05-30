-- Small library of helpers to apply polish primitives — rounded corners,
-- strokes, gradients, drop shadows, hover/press tweens — used by every UI
-- module so the look stays consistent.

local TweenService = game:GetService("TweenService")

local UIStyle = {}

UIStyle.Palette = {
	bg = Color3.fromRGB(18, 20, 28),
	panel = Color3.fromRGB(28, 30, 42),
	panelLight = Color3.fromRGB(40, 44, 60),
	accent = Color3.fromRGB(255, 195, 80),
	good = Color3.fromRGB(96, 220, 130),
	bad = Color3.fromRGB(240, 90, 90),
	caution = Color3.fromRGB(255, 200, 80),
	text = Color3.fromRGB(238, 240, 245),
	textDim = Color3.fromRGB(160, 165, 180),
	blueTeam = Color3.fromRGB(80, 160, 255),
	redTeam = Color3.fromRGB(255, 90, 90),
}

UIStyle.Font = Enum.Font.GothamBold

function UIStyle.corner(instance, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = instance
	return c
end

function UIStyle.stroke(instance, props)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = (props and props.Color) or Color3.fromRGB(255, 255, 255)
	s.Thickness = (props and props.Thickness) or 1
	s.Transparency = (props and props.Transparency) or 0.4
	s.Parent = instance
	return s
end

function UIStyle.gradient(instance, colors, rotation)
	local g = Instance.new("UIGradient")
	if typeof(colors) == "table" then
		local seq = {}
		for i, c in ipairs(colors) do
			table.insert(seq, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), c))
		end
		g.Color = ColorSequence.new(seq)
	end
	g.Rotation = rotation or 90
	g.Parent = instance
	return g
end

function UIStyle.padding(instance, amount)
	local p = Instance.new("UIPadding")
	local u = UDim.new(0, amount or 8)
	p.PaddingTop = u
	p.PaddingBottom = u
	p.PaddingLeft = u
	p.PaddingRight = u
	p.Parent = instance
	return p
end

-- Add a soft glow/shadow behind a Frame by parenting a darker, slightly larger
-- frame behind it. Doesn't need image assets.
function UIStyle.shadow(instance, depth)
	depth = depth or 8
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.AnchorPoint = Vector2.new(0.5, 0.5)
	shadow.Position = UDim2.fromScale(0.5, 0.5) + UDim2.fromOffset(0, depth / 2)
	shadow.Size = UDim2.new(1, depth * 2, 1, depth * 2)
	shadow.BackgroundColor3 = Color3.new(0, 0, 0)
	shadow.BackgroundTransparency = 0.55
	shadow.BorderSizePixel = 0
	shadow.ZIndex = (instance.ZIndex or 1) - 1
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, depth)
	c.Parent = shadow
	shadow.Parent = instance.Parent
	-- Track the parent's position with a property change since parent layout may move
	return shadow
end

local HOVER_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Make a button feel responsive: lighter background on hover, subtle scale on click.
function UIStyle.makeButtonInteractive(button, originalColor)
	originalColor = originalColor or button.BackgroundColor3
	local hoverColor = Color3.fromRGB(
		math.clamp(originalColor.R * 255 + 22, 0, 255),
		math.clamp(originalColor.G * 255 + 22, 0, 255),
		math.clamp(originalColor.B * 255 + 22, 0, 255)
	)
	button.AutoButtonColor = false
	button.MouseEnter:Connect(function()
		TweenService:Create(button, HOVER_TWEEN, { BackgroundColor3 = hoverColor }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, HOVER_TWEEN, { BackgroundColor3 = originalColor }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, HOVER_TWEEN, { Size = button.Size - UDim2.fromOffset(4, 4) }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, HOVER_TWEEN, { Size = button.Size + UDim2.fromOffset(4, 4) }):Play()
	end)
end

return UIStyle
