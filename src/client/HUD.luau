local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Champions = require(Shared:WaitForChild("Champions"))

local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
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
	if game:GetService("UserInputService").TouchEnabled then
		bar.AnchorPoint = Vector2.new(1, 1)
		bar.Position = UDim2.new(1, -24, 1, -24)
	else
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -32)
	end
	bar.BackgroundTransparency = 1
	bar.Parent = screen
	self.bar = bar
	
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = bar

	self.abilityInputBegan = nil
	self.abilityInputChanged = nil
	self.abilityInputEnded = nil

	self.touchStartPos = {}
	self.dragActive = {}
	self.isCancelled = {}
	self.activeInput = {}

	local UserInputService = game:GetService("UserInputService")

	UserInputService.InputChanged:Connect(function(input, processed)
		for slot, activeInput in pairs(self.activeInput) do
			if input == activeInput then
				local startPos = self.touchStartPos[slot]
				if startPos then
					local currentPos = input.Position
					local dragVector = Vector2.new(currentPos.X - startPos.X, currentPos.Y - startPos.Y)
					local dist = dragVector.Magnitude

					if dist > 15 then
						self.dragActive[slot] = true
						local dragDir = dragVector.Unit

						-- Rotate aiming 2D screen coordinate by camera yaw
						local yaw = self.camera and self.camera:getYaw() or 0
						local local3D = Vector3.new(dragDir.X, 0, dragDir.Y)
						local aimedWorldDir = CFrame.fromOrientation(0, yaw, 0):VectorToWorldSpace(local3D)
						aimedWorldDir = Vector3.new(aimedWorldDir.X, 0, aimedWorldDir.Z)
						aimedWorldDir = aimedWorldDir.Magnitude > 0.01 and aimedWorldDir.Unit or Vector3.new(0, 0, 1)

						-- Aiming range factor clamped to max drag length of 90 pixels
						local rangePct = math.clamp(dist / 90, 0, 1)

						-- Check cancellation: Dragged extremely far (150+ px) OR dragged and returned back to button center (< 15 px)
						local cancelled = (dist > 150) or (self.dragActive[slot] and dist < 15)
						self.isCancelled[slot] = cancelled

						if self.abilityInputChanged then
							self.abilityInputChanged(slot, aimedWorldDir, rangePct, cancelled)
						end
					else
						-- Inside deadzone
						if self.dragActive[slot] then
							self.isCancelled[slot] = true
							if self.abilityInputChanged then
								self.abilityInputChanged(slot, Vector3.new(0, 0, 1), 0, true)
							end
						end
					end
				end
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input, processed)
		for slot, activeInput in pairs(self.activeInput) do
			if input == activeInput then
				self.activeInput[slot] = nil
				self.touchStartPos[slot] = nil
				local cancelled = self.isCancelled[slot] or false
				self.dragActive[slot] = nil
				self.isCancelled[slot] = nil

				if self.abilityInputEnded then
					self.abilityInputEnded(slot, not cancelled)
				end
			end
		end
	end)

	RunService.RenderStepped:Connect(function()
		self:_tick()
	end)

	return self
end

function HUD:setCameraController(cameraController)
	self.camera = cameraController
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
			local frame = Instance.new("Frame")
			frame.LayoutOrder = i
			frame.Size = UDim2.fromOffset(slotSize, slotSize)
			frame.BackgroundColor3 = ability.Color or Color3.fromRGB(80, 80, 80)
			frame.BorderSizePixel = 0
			frame.Parent = self.bar
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

			-- Mobile Interactive Touch Overlays (Radial drag-to-aim and drag-off/back-home cancellation)
			local touchBtn = Instance.new("ImageButton")
			touchBtn.Name = "TouchOverlay"
			touchBtn.Size = UDim2.fromScale(1, 1)
			touchBtn.BackgroundTransparency = 1
			touchBtn.ZIndex = 5
			touchBtn.Parent = frame

			touchBtn.InputBegan:Connect(function(input, processed)
				if processed then
					return
				end
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					self.activeInput[slot] = input
					self.touchStartPos[slot] = input.Position
					self.dragActive[slot] = false
					self.isCancelled[slot] = false
					if self.abilityInputBegan then
						self.abilityInputBegan(slot)
					end
				end
			end)
		end
	end
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
