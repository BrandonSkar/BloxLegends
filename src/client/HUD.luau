local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Champions = require(Shared:WaitForChild("Champions"))

local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local Responsive = require(script.Parent:WaitForChild("Responsive"))
local P = UIStyle.Palette

local HUD = {}
HUD.__index = HUD

local SLOT_LABEL = {
	Q = "Q",
	E = "E",
	F = "F",
	R = "R",
	Space = "SPACE",
	Shift = "SHIFT",
}

local function newLabel(parent, text, color, props)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = text or ""
	lbl.TextColor3 = color or P.text
	lbl.Font = UIStyle.Font
	lbl.TextScaled = true
	lbl.TextStrokeTransparency = 0.5
	if props then
		for k, v in pairs(props) do
			lbl[k] = v
		end
	end
	lbl.Parent = parent
	return lbl
end

function HUD.create(playerGui)
	local self = setmetatable({}, HUD)
	self.cooldowns = {}
	self.slotFrames = {}
	self.maxHP = 500

	local screen = Instance.new("ScreenGui")
	screen.Name = "BloxLegendsHUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = playerGui
	self.screen = screen

	-- Root UIScale — every child frame in this ScreenGui is rendered relative
	-- to this. Responsive.onChanged keeps it in sync with the current viewport
	-- so a phone shrinks the whole HUD instead of clipping it.
	local rootScale = Instance.new("UIScale")
	rootScale.Scale = Responsive.scale()
	rootScale.Parent = screen
	self.rootScale = rootScale

	-- ===== HP bar =====
	local hpHolder = Instance.new("Frame")
	hpHolder.AnchorPoint = Vector2.new(0.5, 1)
	hpHolder.Position = UDim2.new(0.5, 0, 1, -118)
	hpHolder.Size = UDim2.fromOffset(320, 26)
	hpHolder.BackgroundColor3 = P.bg
	hpHolder.BorderSizePixel = 0
	hpHolder.Parent = screen
	UIStyle.corner(hpHolder, 8)
	UIStyle.stroke(hpHolder, { Color = Color3.fromRGB(0, 0, 0), Thickness = 1.5, Transparency = 0.3 })

	local hpFill = Instance.new("Frame")
	hpFill.Size = UDim2.fromScale(1, 1)
	hpFill.BackgroundColor3 = P.good
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpHolder
	UIStyle.corner(hpFill, 8)
	UIStyle.gradient(hpFill, {
		Color3.fromRGB(120, 240, 150),
		Color3.fromRGB(60, 180, 100),
	}, 90)
	self.hpFill = hpFill

	self.hpText = newLabel(hpHolder, "500 / 500", P.text, {
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		TextStrokeTransparency = 0.2,
	})

	-- ===== Shield bar (above HP) =====
	local shieldHolder = Instance.new("Frame")
	shieldHolder.AnchorPoint = Vector2.new(0.5, 1)
	shieldHolder.Position = UDim2.new(0.5, 0, 1, -148)
	shieldHolder.Size = UDim2.fromOffset(320, 12)
	shieldHolder.BackgroundColor3 = P.bg
	shieldHolder.BorderSizePixel = 0
	shieldHolder.Visible = false
	shieldHolder.Parent = screen
	UIStyle.corner(shieldHolder, 6)
	UIStyle.stroke(shieldHolder, { Color = Color3.fromRGB(0, 0, 0), Thickness = 1, Transparency = 0.3 })
	local shieldFill = Instance.new("Frame")
	shieldFill.Size = UDim2.fromScale(0, 1)
	shieldFill.BackgroundColor3 = Color3.fromRGB(170, 220, 255)
	shieldFill.BorderSizePixel = 0
	shieldFill.Parent = shieldHolder
	UIStyle.corner(shieldFill, 6)
	UIStyle.gradient(shieldFill, {
		Color3.fromRGB(200, 235, 255),
		Color3.fromRGB(110, 180, 240),
	}, 90)
	self.shieldHolder = shieldHolder
	self.shieldFill = shieldFill

	-- ===== Status indicator =====
	local statusLabel = Instance.new("TextLabel")
	statusLabel.AnchorPoint = Vector2.new(0.5, 1)
	statusLabel.Position = UDim2.new(0.5, 0, 1, -175)
	statusLabel.Size = UDim2.fromOffset(220, 22)
	statusLabel.BackgroundColor3 = P.bg
	statusLabel.BackgroundTransparency = 0.2
	statusLabel.BorderSizePixel = 0
	statusLabel.Font = UIStyle.Font
	statusLabel.TextColor3 = P.caution
	statusLabel.TextScaled = true
	statusLabel.TextStrokeTransparency = 0.5
	statusLabel.Text = ""
	statusLabel.Visible = false
	statusLabel.Parent = screen
	UIStyle.corner(statusLabel, 6)
	self.statusLabel = statusLabel
	self.activeStatuses = {}

	-- ===== Gold (top-right) =====
	local goldHolder = Instance.new("Frame")
	goldHolder.AnchorPoint = Vector2.new(1, 0)
	goldHolder.Position = UDim2.new(1, -16, 0, 60)
	goldHolder.Size = UDim2.fromOffset(160, 44)
	goldHolder.BackgroundColor3 = P.panel
	goldHolder.BorderSizePixel = 0
	goldHolder.Parent = screen
	UIStyle.corner(goldHolder, 10)
	UIStyle.stroke(goldHolder, { Color = P.accent, Thickness = 1.5, Transparency = 0.5 })
	self.goldText = newLabel(goldHolder, "Gold: 0", P.accent)

	-- ===== Target indicator (top-center) =====
	local targetHolder = Instance.new("Frame")
	targetHolder.AnchorPoint = Vector2.new(0.5, 0)
	targetHolder.Position = UDim2.new(0.5, 0, 0, 60)
	targetHolder.Size = UDim2.fromOffset(240, 38)
	targetHolder.BackgroundColor3 = P.panel
	targetHolder.BackgroundTransparency = 0.15
	targetHolder.BorderSizePixel = 0
	targetHolder.Visible = false
	targetHolder.Parent = screen
	UIStyle.corner(targetHolder, 10)
	UIStyle.stroke(targetHolder, { Color = P.bad, Thickness = 1.5, Transparency = 0.4 })
	self.targetHolder = targetHolder
	self.targetText = newLabel(targetHolder, "", P.text)

	-- ===== Ability bar (built in setChampion) =====
	local bar = Instance.new("Frame")
	bar.Name = "AbilityBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -32)
	bar.BackgroundTransparency = 1
	bar.Parent = screen
	self.bar = bar
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = bar

	RunService.RenderStepped:Connect(function()
		self:_tick()
	end)

	-- Keep the root scale in sync with the current viewport. Responsive fires
	-- immediately on subscribe so we don't need to set the initial value
	-- twice. The listener stays alive for the HUD's lifetime — the ScreenGui
	-- is recreated on character respawn, so leaks aren't a concern.
	Responsive.start()
	self._unsubResponsive = Responsive.onChanged(function(_class, scale)
		self.rootScale.Scale = scale
	end)

	return self
end

function HUD:setChampion(championKey)
	local champ = Champions.Roster[championKey]
	if not champ then
		return
	end
	self.maxHP = champ.MaxHP
	for _, child in ipairs(self.bar:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	self.slotFrames = {}
	self.cooldowns = {}
	local slotsCount = 0
	for _, slot in ipairs(Champions.SlotOrder) do
		if champ.Abilities[slot] then
			slotsCount = slotsCount + 1
		end
	end
	local slotSize = 72
	local pad = 10
	self.bar.Size = UDim2.fromOffset(slotSize * slotsCount + pad * math.max(slotsCount - 1, 0), slotSize + 12)

	for i, slot in ipairs(Champions.SlotOrder) do
		local ability = champ.Abilities[slot]
		if ability then
			-- Frame (not TextButton). TextButton sinks ALL mouse input over it,
			-- including right-click — which would silently break the camera
			-- mouse-look gesture since CameraController gates MB2 on the
			-- `processed` flag. Frame with Active=false still emits InputBegan
			-- for the drag-aim flow but lets non-MB1 input pass through to
			-- UserInputService.
			local frame = Instance.new("Frame")
			frame.LayoutOrder = i
			frame.Size = UDim2.fromOffset(slotSize, slotSize)
			frame.BackgroundColor3 = ability.Color or Color3.fromRGB(80, 80, 80)
			frame.BorderSizePixel = 0
			frame.Active = false
			frame.Parent = self.bar
			-- Drag-aim: press → drag → release. The press fires onAimStart, the
			-- subsequent drag (anywhere on the screen) fires onAimUpdate, and
			-- the release fires onAimEnd. We track the originating InputObject
			-- across the whole window via UserInputService because GuiButton
			-- input events only fire while the cursor is over the button —
			-- once the player drags off the slot we'd lose all updates.
			frame.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1
					and input.UserInputType ~= Enum.UserInputType.Touch
				then
					return
				end
				local screenX = input.Position.X
				local screenY = input.Position.Y
				if self._onAimStart then
					self._onAimStart(slot, screenX, screenY)
				end
				local moveConn, endConn
				moveConn = UserInputService.InputChanged:Connect(function(moveInput)
					-- Touch fires on the same InputObject; mouse uses MouseMovement.
					if moveInput == input
						or moveInput.UserInputType == Enum.UserInputType.MouseMovement
					then
						if self._onAimUpdate then
							self._onAimUpdate(moveInput.Position.X, moveInput.Position.Y)
						end
					end
				end)
				endConn = UserInputService.InputEnded:Connect(function(endInput)
					local matches = endInput == input
						or (input.UserInputType == Enum.UserInputType.MouseButton1
							and endInput.UserInputType == Enum.UserInputType.MouseButton1)
					if matches then
						if moveConn then
							moveConn:Disconnect()
							moveConn = nil
						end
						if endConn then
							endConn:Disconnect()
							endConn = nil
						end
						if self._onAimEnd then
							self._onAimEnd(endInput.Position.X, endInput.Position.Y, false)
						end
					end
				end)
			end)
			UIStyle.corner(frame, 12)
			UIStyle.stroke(frame, { Color = Color3.fromRGB(0, 0, 0), Thickness = 2, Transparency = 0.4 })
			UIStyle.gradient(frame, {
				Color3.fromRGB(
					math.clamp(ability.Color.R * 255 + 30, 0, 255),
					math.clamp(ability.Color.G * 255 + 30, 0, 255),
					math.clamp(ability.Color.B * 255 + 30, 0, 255)
				),
				ability.Color,
			}, 90)

			local nameLabel = newLabel(frame, ability.Name, Color3.fromRGB(20, 20, 20), {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 6),
				Size = UDim2.new(1, -8, 0, 20),
				TextStrokeTransparency = 1,
			})
			nameLabel.TextScaled = false
			nameLabel.TextSize = 11

			-- Key chip
			local keyChip = Instance.new("Frame")
			keyChip.AnchorPoint = Vector2.new(0.5, 1)
			keyChip.Position = UDim2.new(0.5, 0, 1, -6)
			keyChip.Size = UDim2.fromOffset(slotSize - 24, 22)
			keyChip.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			keyChip.BackgroundTransparency = 0.35
			keyChip.BorderSizePixel = 0
			keyChip.Parent = frame
			UIStyle.corner(keyChip, 6)
			newLabel(keyChip, SLOT_LABEL[slot], P.text)

			-- Cooldown overlay (dark fill that shrinks as the CD expires).
			local overlay = Instance.new("Frame")
			overlay.AnchorPoint = Vector2.new(0.5, 1)
			overlay.Position = UDim2.fromScale(0.5, 1)
			overlay.Size = UDim2.fromScale(1, 0)
			overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			overlay.BackgroundTransparency = 0.35
			overlay.BorderSizePixel = 0
			overlay.ZIndex = 3
			overlay.Parent = frame
			UIStyle.corner(overlay, 12)

			local cdText = newLabel(overlay, "", P.text, { ZIndex = 4 })
			cdText.TextScaled = false
			cdText.TextSize = 22

			self.slotFrames[slot] = { overlay = overlay, text = cdText, duration = 0, frame = frame }
		end
	end
end

-- Wire the slot button taps. Called once from init.client.luau so the HUD
-- doesn't need to know about AbilityCaster directly. The HUD reports three
-- phases — start (initial press), update (drag), end (release) — so the
-- caster can render an aim indicator and fire at the final position.
function HUD:setOnAbilityPressed(fn)
	self._onAbilityPressed = fn
end

function HUD:setOnAimStart(fn)
	self._onAimStart = fn
end

function HUD:setOnAimUpdate(fn)
	self._onAimUpdate = fn
end

function HUD:setOnAimEnd(fn)
	self._onAimEnd = fn
end

function HUD:setHP(hp, maxHP)
	self.maxHP = maxHP
	local pct = math.clamp(hp / math.max(maxHP, 1), 0, 1)
	-- Animate the fill change for a less jarring update.
	TweenService:Create(
		self.hpFill,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(pct, 1) }
	):Play()
	self.hpText.Text = math.floor(hp + 0.5) .. " / " .. maxHP
	-- HP color shift uses gradient; we also tint the base color for clarity.
	if pct > 0.5 then
		self.hpFill.BackgroundColor3 = P.good
	elseif pct > 0.25 then
		self.hpFill.BackgroundColor3 = P.caution
	else
		self.hpFill.BackgroundColor3 = P.bad
	end
end

function HUD:setShield(amount)
	if amount and amount > 0 then
		self.shieldHolder.Visible = true
		local pct = math.clamp(amount / math.max(self.maxHP, 1), 0, 1)
		TweenService:Create(
			self.shieldFill,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(pct, 1) }
		):Play()
	else
		self.shieldHolder.Visible = false
	end
end

function HUD:setStatus(statusType, payload)
	if payload and payload.ended then
		self.activeStatuses[statusType] = nil
	else
		local duration = payload and payload.duration or 1
		self.activeStatuses[statusType] = { expiresAt = os.clock() + duration }
	end
end

function HUD:setGold(amount)
	self.goldText.Text = "Gold: " .. tostring(amount)
end

function HUD:setTarget(target)
	if not target then
		self.targetHolder.Visible = false
		return
	end
	self.targetHolder.Visible = true
	self.targetText.Text = target.name or "?"
end

function HUD:setVisible(visible)
	if self.screen then
		self.screen.Enabled = visible
	end
end

function HUD:setCooldown(slot, duration)
	local rec = self.slotFrames[slot]
	if not rec then
		return
	end
	rec.duration = duration
	self.cooldowns[slot] = os.clock() + duration
end

function HUD:_tick()
	local now = os.clock()
	for slot, rec in pairs(self.slotFrames) do
		local readyAt = self.cooldowns[slot]
		if readyAt and readyAt > now then
			local remaining = readyAt - now
			local pct = math.clamp(remaining / math.max(rec.duration, 0.01), 0, 1)
			rec.overlay.Size = UDim2.fromScale(1, pct)
			rec.text.Text = string.format("%.1f", remaining)
		else
			rec.overlay.Size = UDim2.fromScale(1, 0)
			rec.text.Text = ""
		end
	end
	local active, soonest
	for k, s in pairs(self.activeStatuses) do
		if s.expiresAt > now then
			if not soonest or s.expiresAt > soonest then
				soonest = s.expiresAt
				active = k
			end
		else
			self.activeStatuses[k] = nil
		end
	end
	if active then
		self.statusLabel.Visible = true
		self.statusLabel.Text = string.upper(active) .. string.format("  %.1fs", soonest - now)
	else
		self.statusLabel.Visible = false
	end
end

return HUD
