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

	-- ===== Team score + match timer (top-center, below the tower strip) =====
	local scoreBar = Instance.new("Frame")
	scoreBar.Name = "ScoreBar"
	scoreBar.AnchorPoint = Vector2.new(0.5, 0)
	scoreBar.Position = UDim2.new(0.5, 0, 0, Responsive.topInset() + 50)
	scoreBar.Size = UDim2.fromOffset(240, 40)
	scoreBar.BackgroundColor3 = P.bg
	scoreBar.BackgroundTransparency = 0.15
	scoreBar.BorderSizePixel = 0
	-- Sinks clicks so tapping the scoreboard toggle doesn't also click-target
	-- something in the world behind it.
	scoreBar.Active = true
	scoreBar.Parent = screen
	UIStyle.corner(scoreBar, 10)
	UIStyle.stroke(scoreBar, { Color = Color3.fromRGB(0, 0, 0), Thickness = 1.5, Transparency = 0.4 })
	self.scoreBar = scoreBar

	self.blueScoreText = newLabel(scoreBar, "0", P.blueTeam, {
		Size = UDim2.new(0, 60, 1, 0),
		Position = UDim2.fromOffset(8, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	self.clockText = newLabel(scoreBar, "0:00", P.text, {
		Size = UDim2.new(1, -140, 0.8, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
	})
	self.redScoreText = newLabel(scoreBar, "0", P.redTeam, {
		Size = UDim2.new(0, 60, 1, 0),
		Position = UDim2.new(1, -68, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	self.clockStart = nil
	-- Tapping the score bar toggles the scoreboard (the touch path; PC holds Tab).
	scoreBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			if self._onScoreBarTap then
				self._onScoreBarTap()
			end
		end
	end)

	-- ===== Kill feed (top-right, under the gold panel) =====
	local feed = Instance.new("Frame")
	feed.Name = "KillFeed"
	feed.AnchorPoint = Vector2.new(1, 0)
	feed.Position = UDim2.new(1, -16, 0, 112)
	feed.Size = UDim2.fromOffset(250, 160)
	feed.BackgroundTransparency = 1
	feed.Parent = screen
	local feedLayout = Instance.new("UIListLayout")
	feedLayout.FillDirection = Enum.FillDirection.Vertical
	feedLayout.Padding = UDim.new(0, 4)
	feedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
	feedLayout.Parent = feed
	self.killFeed = feed
	self._feedOrder = 0

	-- ===== Center announcement (FIRST BLOOD! / DOUBLE KILL! / objectives) =====
	local announce = Instance.new("TextLabel")
	announce.Name = "Announcement"
	announce.AnchorPoint = Vector2.new(0.5, 0.5)
	announce.Position = UDim2.fromScale(0.5, 0.28)
	announce.Size = UDim2.fromOffset(700, 52)
	announce.BackgroundTransparency = 1
	announce.Font = Enum.Font.GothamBlack
	announce.Text = ""
	announce.TextColor3 = P.accent
	announce.TextSize = 40
	announce.TextStrokeTransparency = 0.2
	announce.TextTransparency = 1
	-- Above the death overlay (ZIndex 9) so VICTORY/kill banners read while dead.
	announce.ZIndex = 11
	announce.Parent = screen
	self.announceLabel = announce
	self._announceGen = 0

	-- ===== Level badge + XP bar (attached to the HP bar) =====
	local levelBadge = Instance.new("Frame")
	levelBadge.AnchorPoint = Vector2.new(1, 1)
	levelBadge.Position = UDim2.new(0.5, -166, 1, -114)
	levelBadge.Size = UDim2.fromOffset(36, 36)
	levelBadge.BackgroundColor3 = P.panel
	levelBadge.BorderSizePixel = 0
	levelBadge.Parent = screen
	UIStyle.corner(levelBadge, 18)
	UIStyle.stroke(levelBadge, { Color = P.accent, Thickness = 2, Transparency = 0.3 })
	self.levelText = newLabel(levelBadge, "1", P.accent)
	self.levelBadge = levelBadge

	local xpHolder = Instance.new("Frame")
	xpHolder.AnchorPoint = Vector2.new(0.5, 1)
	xpHolder.Position = UDim2.new(0.5, 0, 1, -110)
	xpHolder.Size = UDim2.fromOffset(320, 6)
	xpHolder.BackgroundColor3 = P.bg
	xpHolder.BorderSizePixel = 0
	xpHolder.Parent = screen
	UIStyle.corner(xpHolder, 3)
	local xpFill = Instance.new("Frame")
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = Color3.fromRGB(170, 120, 255)
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpHolder
	UIStyle.corner(xpFill, 3)
	self.xpFill = xpFill

	-- ===== Death overlay (respawn countdown) =====
	local deathOverlay = Instance.new("Frame")
	deathOverlay.Name = "DeathOverlay"
	deathOverlay.Size = UDim2.fromScale(1, 1)
	deathOverlay.BackgroundColor3 = Color3.fromRGB(10, 5, 8)
	deathOverlay.BackgroundTransparency = 0.45
	deathOverlay.BorderSizePixel = 0
	deathOverlay.Visible = false
	deathOverlay.ZIndex = 9
	deathOverlay.Active = false
	deathOverlay.Parent = screen
	local slainLabel = newLabel(deathOverlay, "YOU HAVE BEEN SLAIN", P.bad, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromOffset(600, 44),
		ZIndex = 10,
	})
	slainLabel.Font = Enum.Font.GothamBlack
	slainLabel.TextScaled = false
	slainLabel.TextSize = 36
	local slainByLabel = newLabel(deathOverlay, "", P.textDim, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.445),
		Size = UDim2.fromOffset(600, 24),
		ZIndex = 10,
	})
	slainByLabel.TextScaled = false
	slainByLabel.TextSize = 18
	local respawnLabel = newLabel(deathOverlay, "", P.text, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.54),
		Size = UDim2.fromOffset(300, 56),
		ZIndex = 10,
	})
	respawnLabel.Font = Enum.Font.GothamBlack
	respawnLabel.TextScaled = false
	respawnLabel.TextSize = 48
	self.deathOverlay = deathOverlay
	self.slainByLabel = slainByLabel
	self.respawnLabel = respawnLabel
	self.deathEndsAt = nil

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

	-- ===== Recall (Base) + Shop buttons, just right of the ability bar =====
	local utilHolder = Instance.new("Frame")
	utilHolder.Name = "UtilButtons"
	utilHolder.AnchorPoint = Vector2.new(0, 1)
	utilHolder.Position = UDim2.new(0.5, 120, 1, -32) -- repositioned per-champion in setChampion
	utilHolder.Size = UDim2.fromOffset(64 * 2 + 10, 64)
	utilHolder.BackgroundTransparency = 1
	utilHolder.Parent = screen
	self.utilHolder = utilHolder
	local utilLayout = Instance.new("UIListLayout")
	utilLayout.FillDirection = Enum.FillDirection.Horizontal
	utilLayout.Padding = UDim.new(0, 10)
	utilLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	utilLayout.SortOrder = Enum.SortOrder.LayoutOrder
	utilLayout.Parent = utilHolder

	-- Frame (not TextButton) + Active=false so right-click still passes through to
	-- the camera mouse-look, same rationale as the ability slots. We act on the
	-- MB1 / touch press; an optional `gate` blocks the press when false.
	local function makeUtilButton(order, title, keyHint, accent, onPress, gate)
		local frame = Instance.new("Frame")
		frame.LayoutOrder = order
		frame.Size = UDim2.fromOffset(64, 64)
		frame.BackgroundColor3 = P.panel
		frame.BorderSizePixel = 0
		frame.Active = false
		frame.Parent = utilHolder
		UIStyle.corner(frame, 12)
		UIStyle.stroke(frame, { Color = accent, Thickness = 2, Transparency = 0.35 })
		local titleLabel = newLabel(frame, title, accent, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 10),
			Size = UDim2.new(1, -8, 0, 22),
		})
		titleLabel.TextScaled = false
		titleLabel.TextSize = 15
		local keyChip = Instance.new("Frame")
		keyChip.AnchorPoint = Vector2.new(0.5, 1)
		keyChip.Position = UDim2.new(0.5, 0, 1, -6)
		keyChip.Size = UDim2.fromOffset(40, 20)
		keyChip.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		keyChip.BackgroundTransparency = 0.35
		keyChip.BorderSizePixel = 0
		keyChip.Parent = frame
		UIStyle.corner(keyChip, 6)
		local kl = newLabel(keyChip, keyHint, P.text)
		kl.TextScaled = false
		kl.TextSize = 12
		frame.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			if gate and not gate() then
				return
			end
			onPress()
		end)
		return frame
	end

	makeUtilButton(1, "BASE", "B", Color3.fromRGB(140, 200, 255), function()
		if self._onRecall then
			self._onRecall()
		end
	end)
	self.shopBtn = makeUtilButton(2, "SHOP", "P", P.accent, function()
		if self._onShop then
			self._onShop()
		end
	end, function()
		return self._shopEnabled
	end)
	-- Dim overlay shown while NOT in base (shop is gated to the base zone).
	local shopDim = Instance.new("Frame")
	shopDim.Size = UDim2.fromScale(1, 1)
	shopDim.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	shopDim.BackgroundTransparency = 0.5
	shopDim.BorderSizePixel = 0
	shopDim.ZIndex = 5
	shopDim.Active = false
	shopDim.Parent = self.shopBtn
	UIStyle.corner(shopDim, 12)
	self.shopDim = shopDim
	self._shopEnabled = false

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
		self.scoreBar.Position = UDim2.new(0.5, 0, 0, Responsive.topInset() + 50)
	end)

	return self
end

-- ===== Team score + match clock =====

function HUD:setTeam(team)
	self.myTeam = team
end

function HUD:setOnScoreBarTap(fn)
	self._onScoreBarTap = fn
end

function HUD:setTeamScore(score)
	self.blueScoreText.Text = tostring(score.Blue or 0)
	self.redScoreText.Text = tostring(score.Red or 0)
end

-- `serverStartTime` is workspace:GetServerTimeNow()-based (or nil to hide).
function HUD:setMatchClock(serverStartTime)
	self.clockStart = serverStartTime
	if not serverStartTime then
		self.clockText.Text = "0:00"
	end
end

-- ===== Kill feed =====

local TEAM_HEX = {
	Blue = "#64B4FF",
	Red = "#FF6E6E",
}

-- Display names go into RichText markup — escape the markup characters.
local function escapeRich(s)
	s = tostring(s or "?")
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	return s
end

function HUD:addKillFeed(info)
	local killerHex = TEAM_HEX[info.killerTeam] or "#CCCCCC"
	local victimHex = TEAM_HEX[info.victimTeam] or "#CCCCCC"
	local text
	if info.killerName then
		text = ('<font color="%s">%s</font>  ⚔  <font color="%s">%s</font>'):format(
			killerHex, escapeRich(info.killerName), victimHex, escapeRich(info.victimName)
		)
	else
		text = ('<font color="%s">%s</font> was executed'):format(victimHex, escapeRich(info.victimName))
	end

	local row = Instance.new("TextLabel")
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundColor3 = P.bg
	row.BackgroundTransparency = 0.25
	row.BorderSizePixel = 0
	row.RichText = true
	row.Text = text
	row.TextColor3 = P.text
	row.Font = UIStyle.Font
	row.TextSize = 14
	row.TextXAlignment = Enum.TextXAlignment.Center
	self._feedOrder = self._feedOrder + 1
	row.LayoutOrder = self._feedOrder
	row.Parent = self.killFeed
	UIStyle.corner(row, 6)

	-- Cap the visible rows, oldest out first.
	local rows = {}
	for _, child in ipairs(self.killFeed:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(rows, child)
		end
	end
	table.sort(rows, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #rows - 5 do
		rows[i]:Destroy()
	end

	task.delay(8, function()
		if row.Parent then
			TweenService:Create(row, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			task.wait(0.4)
			if row.Parent then
				row:Destroy()
			end
		end
	end)
end

-- ===== Center announcements =====

function HUD:announce(text, color, duration)
	duration = duration or 2.5
	self._announceGen = self._announceGen + 1
	local gen = self._announceGen
	local label = self.announceLabel
	label.Text = text
	label.TextColor3 = color or P.accent
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.2
	-- Pop-in scale effect via text size.
	label.TextSize = 52
	TweenService:Create(label, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		TextSize = 40,
	}):Play()
	task.delay(duration, function()
		if self._announceGen ~= gen then
			return
		end
		TweenService:Create(label, TweenInfo.new(0.5), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
	end)
end

-- ===== Level / XP =====

function HUD:setXP(level, xp, xpToNext)
	self.levelText.Text = tostring(level)
	if xpToNext and xpToNext > 0 then
		self.xpFill.Size = UDim2.fromScale(math.clamp(xp / xpToNext, 0, 1), 1)
	else
		self.xpFill.Size = UDim2.fromScale(1, 1) -- max level
	end
end

-- Quick golden flash on the badge when we level up.
function HUD:flashLevelUp()
	local stroke = self.levelBadge:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
		stroke.Thickness = 4
		TweenService:Create(stroke, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 0.3,
			Thickness = 2,
		}):Play()
	end
end

-- ===== Death overlay =====

function HUD:showDeath(respawnSeconds, killerName)
	self.deathEndsAt = os.clock() + (respawnSeconds or 5)
	self.slainByLabel.Text = killerName and ("Slain by " .. killerName) or ""
	self.deathOverlay.Visible = true
end

function HUD:hideDeath()
	self.deathEndsAt = nil
	self.deathOverlay.Visible = false
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
	local barWidth = slotSize * slotsCount + pad * math.max(slotsCount - 1, 0)
	self.bar.Size = UDim2.fromOffset(barWidth, slotSize + 12)
	-- Park the recall/shop buttons just past the bar's right edge.
	if self.utilHolder then
		self.utilHolder.Position = UDim2.new(0.5, barWidth / 2 + 12, 1, -32)
	end

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

function HUD:setOnRecall(fn)
	self._onRecall = fn
end

function HUD:setOnShop(fn)
	self._onShop = fn
end

-- Enable/disable the shop button (and toggle its dimmed look). Driven by the
-- InBaseChanged remote — you can only shop while standing in your base.
function HUD:setShopEnabled(enabled)
	self._shopEnabled = enabled and true or false
	if self.shopDim then
		self.shopDim.Visible = not self._shopEnabled
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
	-- Show the SOONEST-expiring status so a 1s stun isn't hidden behind a
	-- 75-second jungle buff.
	local active, soonest
	for k, s in pairs(self.activeStatuses) do
		if s.expiresAt > now then
			if not soonest or s.expiresAt < soonest then
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

	-- Match clock (server-time based so every client agrees).
	if self.clockStart then
		local elapsed = math.max(0, workspace:GetServerTimeNow() - self.clockStart)
		local m = math.floor(elapsed / 60)
		local s = math.floor(elapsed % 60)
		self.clockText.Text = string.format("%d:%02d", m, s)
	end

	-- Death overlay countdown.
	if self.deathEndsAt then
		local remaining = self.deathEndsAt - now
		if remaining <= 0 then
			self:hideDeath()
		else
			self.respawnLabel.Text = string.format("%d", math.ceil(remaining))
		end
	end
end

return HUD
