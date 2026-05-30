-- Recall ("Base") channel: B starts an 8s channel, sliding bar over the HUD
-- shows progress, and a cool ground-rune / pillar-of-light FX plays under the
-- player. Server owns cancel rules (damage / movement / ability) — the client
-- just visualizes whatever state the server sends.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local P = UIStyle.Palette

local RecallController = {}
RecallController.__index = RecallController

local CHANNEL_KEY = Enum.KeyCode.B
local RUNE_COLOR = Color3.fromRGB(140, 200, 255)
local RUNE_COLOR_DEEP = Color3.fromRGB(80, 140, 240)

function RecallController.new()
	local self = setmetatable({}, RecallController)
	self.player = Players.LocalPlayer
	self.enabled = false
	self.connections = {}
	self.fxConnection = nil
	self.fxFolder = nil
	self.highlight = nil
	self.channel = nil -- { startedAt, endsAt }
	self.inBase = false
	return self
end

-- ===== HUD: channel bar + base indicator =====

function RecallController:_buildUI(playerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name = "RecallUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = playerGui
	self.screen = screen

	-- Channel bar: large bar over the hotbar, slides as channel progresses.
	local barHolder = Instance.new("Frame")
	barHolder.AnchorPoint = Vector2.new(0.5, 1)
	barHolder.Position = UDim2.new(0.5, 0, 1, -210)
	barHolder.Size = UDim2.fromOffset(380, 30)
	barHolder.BackgroundColor3 = P.bg
	barHolder.BorderSizePixel = 0
	barHolder.Visible = false
	barHolder.Parent = screen
	UIStyle.corner(barHolder, 8)
	UIStyle.stroke(barHolder, { Color = RUNE_COLOR, Thickness = 2, Transparency = 0.2 })
	self.barHolder = barHolder

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = RUNE_COLOR
	barFill.BorderSizePixel = 0
	barFill.Parent = barHolder
	UIStyle.corner(barFill, 8)
	UIStyle.gradient(barFill, { Color3.fromRGB(200, 235, 255), RUNE_COLOR_DEEP }, 90)
	self.barFill = barFill

	local barLabel = Instance.new("TextLabel")
	barLabel.Size = UDim2.fromScale(1, 1)
	barLabel.BackgroundTransparency = 1
	barLabel.Font = UIStyle.Font
	barLabel.TextScaled = false
	barLabel.TextSize = 16
	barLabel.TextColor3 = P.text
	barLabel.TextStrokeTransparency = 0.3
	barLabel.Text = "Recalling 8.0s"
	barLabel.ZIndex = 2
	barLabel.Parent = barHolder
	self.barLabel = barLabel

	-- Base indicator: small chip top-left telling the player they're in base and regenerating.
	local baseChip = Instance.new("Frame")
	baseChip.AnchorPoint = Vector2.new(0, 0)
	baseChip.Position = UDim2.fromOffset(16, 60)
	baseChip.Size = UDim2.fromOffset(220, 36)
	baseChip.BackgroundColor3 = P.panel
	baseChip.BorderSizePixel = 0
	baseChip.Visible = false
	baseChip.Parent = screen
	UIStyle.corner(baseChip, 10)
	UIStyle.stroke(baseChip, { Color = P.good, Thickness = 1.5, Transparency = 0.3 })
	self.baseChip = baseChip
	local baseLabel = Instance.new("TextLabel")
	baseLabel.Size = UDim2.fromScale(1, 1)
	baseLabel.BackgroundTransparency = 1
	baseLabel.Font = UIStyle.Font
	baseLabel.TextScaled = false
	baseLabel.TextSize = 16
	baseLabel.TextColor3 = P.good
	baseLabel.Text = "IN BASE — Regenerating"
	baseLabel.Parent = baseChip
end

-- ===== Channel VFX =====
-- Builds a rune ring + pillar of light + sparkle particles + character highlight
-- under the player. The ring + glyphs spin via Heartbeat; the pillar + highlight
-- pulse via tweens. All cleaned up on cancel/complete.

local function makeVisualPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

function RecallController:_startFX(duration)
	self:_stopFX()
	local char = self.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = "RecallFX"
	folder.Parent = workspace
	self.fxFolder = folder

	-- Find ground Y under the player so the rune lies flat on the floor.
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { char, folder }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -50, 0), rayParams)
	local groundY = hit and hit.Position.Y or (root.Position.Y - 3)

	-- Outer rune ring (rotates slowly).
	local outerRing = makeVisualPart({
		Name = "OuterRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 14, 14),
		CFrame = CFrame.new(root.Position.X, groundY + 0.1, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = RUNE_COLOR,
		Transparency = 0.35,
	})
	outerRing.Parent = folder

	-- Inner rune ring (rotates the OTHER way for a magic-circle vibe).
	local innerRing = makeVisualPart({
		Name = "InnerRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 9, 9),
		CFrame = CFrame.new(root.Position.X, groundY + 0.15, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(220, 240, 255),
		Transparency = 0.3,
	})
	innerRing.Parent = folder

	-- Rune glyphs orbiting around the player (small bright cubes).
	local glyphs = {}
	for _ = 1, 6 do
		local g = makeVisualPart({
			Name = "Glyph",
			Size = Vector3.new(0.6, 0.6, 0.6),
			Color = RUNE_COLOR,
			Transparency = 0.05,
		})
		g.Parent = folder
		table.insert(glyphs, g)
	end

	-- Pillar of light: tall translucent cylinder around the player.
	local pillar = makeVisualPart({
		Name = "Pillar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(40, 5, 5),
		CFrame = CFrame.new(root.Position.X, groundY + 20, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = RUNE_COLOR,
		Transparency = 0.75,
	})
	pillar.Parent = folder

	-- Particle emitter for rising sparkles (parented to a tiny helper attachment at the player's feet).
	local emitterPart = makeVisualPart({
		Name = "SparkleSource",
		Size = Vector3.new(0.1, 0.1, 0.1),
		CFrame = CFrame.new(root.Position.X, groundY + 0.2, root.Position.Z),
		Transparency = 1,
		Material = Enum.Material.SmoothPlastic,
	})
	emitterPart.Parent = folder
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(RUNE_COLOR)
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.9, 1.4)
	emitter.Rate = 60
	emitter.Speed = NumberRange.new(6, 10)
	emitter.SpreadAngle = Vector2.new(15, 15)
	emitter.Acceleration = Vector3.new(0, 4, 0) -- rise upward
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent = emitterPart

	-- Pulse the pillar transparency on a tween loop.
	local pulse = TweenService:Create(
		pillar,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Transparency = 0.55 }
	)
	pulse:Play()

	-- Character highlight glow.
	local highlight = Instance.new("Highlight")
	highlight.FillColor = RUNE_COLOR
	highlight.OutlineColor = Color3.fromRGB(220, 240, 255)
	highlight.FillTransparency = 0.55
	highlight.OutlineTransparency = 0.1
	highlight.Adornee = char
	highlight.Parent = folder
	self.highlight = highlight

	-- A point light on the player for ambient ground glow.
	local lightPart = makeVisualPart({
		Name = "GlowAnchor",
		Size = Vector3.new(0.1, 0.1, 0.1),
		CFrame = CFrame.new(root.Position.X, groundY + 1, root.Position.Z),
		Transparency = 1,
		Material = Enum.Material.SmoothPlastic,
	})
	lightPart.Parent = folder
	local pointLight = Instance.new("PointLight")
	pointLight.Color = RUNE_COLOR
	pointLight.Range = 24
	pointLight.Brightness = 3
	pointLight.Parent = lightPart

	-- Heartbeat: spin rings + orbit glyphs + keep FX attached to the player.
	local startTime = os.clock()
	self.fxConnection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local t = now - startTime
		local charNow = self.player.Character
		local rootNow = charNow and charNow:FindFirstChild("HumanoidRootPart")
		local hpRayHit
		if rootNow then
			local rp = RaycastParams.new()
			rp.FilterDescendantsInstances = { charNow, folder }
			rp.FilterType = Enum.RaycastFilterType.Exclude
			hpRayHit = workspace:Raycast(rootNow.Position, Vector3.new(0, -50, 0), rp)
		end
		local gy = (hpRayHit and hpRayHit.Position.Y) or groundY
		if rootNow then
			local px, pz = rootNow.Position.X, rootNow.Position.Z
			outerRing.CFrame = CFrame.new(px, gy + 0.1, pz)
				* CFrame.Angles(0, t * 0.6, 0)
				* CFrame.Angles(0, 0, math.rad(90))
			innerRing.CFrame = CFrame.new(px, gy + 0.15, pz)
				* CFrame.Angles(0, -t * 1.2, 0)
				* CFrame.Angles(0, 0, math.rad(90))
			pillar.CFrame = CFrame.new(px, gy + 20, pz) * CFrame.Angles(0, 0, math.rad(90))
			emitterPart.CFrame = CFrame.new(px, gy + 0.2, pz)
			lightPart.CFrame = CFrame.new(px, gy + 1, pz)
			for i, g in ipairs(glyphs) do
				local angle = t * 1.5 + (i - 1) * (math.pi * 2 / #glyphs)
				local r = 6
				local bob = math.sin(t * 3 + i) * 0.4
				g.CFrame = CFrame.new(px + math.cos(angle) * r, gy + 2 + bob, pz + math.sin(angle) * r)
					* CFrame.Angles(t * 2, t * 2.5, 0)
			end
		end
	end)

	-- Auto-cleanup safety in case we miss a server signal.
	Debris:AddItem(folder, (duration or 8) + 1)
end

function RecallController:_stopFX()
	if self.fxConnection then
		self.fxConnection:Disconnect()
		self.fxConnection = nil
	end
	if self.fxFolder then
		-- Fade rings + pillar out for a smoother stop.
		for _, child in ipairs(self.fxFolder:GetDescendants()) do
			if child:IsA("BasePart") then
				TweenService:Create(child, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			elseif child:IsA("ParticleEmitter") then
				child.Enabled = false
			elseif child:IsA("Highlight") then
				TweenService:Create(child, TweenInfo.new(0.25), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
			elseif child:IsA("PointLight") then
				TweenService:Create(child, TweenInfo.new(0.25), { Brightness = 0 }):Play()
			end
		end
		local toClean = self.fxFolder
		task.delay(0.4, function()
			if toClean and toClean.Parent then
				toClean:Destroy()
			end
		end)
		self.fxFolder = nil
		self.highlight = nil
	end
end

-- ===== Wire-up =====

function RecallController:_onState(state, duration)
	if state == "channeling" then
		self.channel = { startedAt = os.clock(), endsAt = os.clock() + (duration or 8) }
		self.barHolder.Visible = true
		self.barFill.Size = UDim2.fromScale(0, 1)
		self.barLabel.Text = string.format("Recalling %.1fs", duration or 8)
		self:_startFX(duration or 8)
	elseif state == "complete" or state == "cancelled" then
		self.channel = nil
		self.barHolder.Visible = false
		self:_stopFX()
	end
end

function RecallController:_tick()
	if not self.channel then
		return
	end
	local now = os.clock()
	local total = self.channel.endsAt - self.channel.startedAt
	local elapsed = now - self.channel.startedAt
	local pct = math.clamp(elapsed / math.max(total, 0.001), 0, 1)
	self.barFill.Size = UDim2.fromScale(pct, 1)
	local remaining = math.max(0, self.channel.endsAt - now)
	self.barLabel.Text = string.format("Recalling %.1fs", remaining)
end

function RecallController:setEnabled(enabled)
	self.enabled = enabled
	if not enabled then
		-- Tell the server to drop any active channel for this player so the
		-- server's timer doesn't fire a teleport after we've left the match.
		if self.channel then
			Remotes.get("RecallCancel"):FireServer()
		end
		self.barHolder.Visible = false
		self.baseChip.Visible = false
		self:_stopFX()
		self.channel = nil
		self.inBase = false
	end
end

function RecallController:start(playerGui)
	self:_buildUI(playerGui)

	table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not self.enabled then
			return
		end
		if input.KeyCode == CHANNEL_KEY and not self.channel then
			Remotes.get("RecallStart"):FireServer()
		end
	end))

	table.insert(self.connections, Remotes.get("RecallState").OnClientEvent:Connect(function(state, duration)
		self:_onState(state, duration)
	end))

	table.insert(self.connections, Remotes.get("InBaseChanged").OnClientEvent:Connect(function(inBase)
		self.inBase = inBase and true or false
		self.baseChip.Visible = self.inBase
	end))

	table.insert(self.connections, RunService.RenderStepped:Connect(function()
		self:_tick()
	end))
end

function RecallController:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
	self:_stopFX()
end

return RecallController
