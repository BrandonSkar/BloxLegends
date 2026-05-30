local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Runes = require(Shared:WaitForChild("Runes"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ZONE_PAD_RADIUS = 22 -- show the prompt when within this many studs of a pad center.

local LobbyUI = {}
LobbyUI.__index = LobbyUI

local FONT = Enum.Font.GothamBold

local function newFrame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	for k, v in pairs(props) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

local function newLabel(parent, text, color, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or Color3.fromRGB(240, 240, 240)
	l.Font = FONT
	l.TextScaled = true
	l.TextStrokeTransparency = 0.5
	if props then
		for k, v in pairs(props) do
			l[k] = v
		end
	end
	l.Parent = parent
	return l
end

local function newButton(parent, text, color, props)
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = color or Color3.fromRGB(70, 70, 80)
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = Color3.fromRGB(240, 240, 240)
	b.Font = FONT
	b.TextScaled = true
	b.AutoButtonColor = true
	if props then
		for k, v in pairs(props) do
			b[k] = v
		end
	end
	b.Parent = parent
	return b
end

function LobbyUI.create(playerGui)
	local self = setmetatable({}, LobbyUI)
	self.player = Players.LocalPlayer
	self.state = "lobby"
	self.zoneId = nil
	self.zones = {}
	self.gold = 0
	self.runes = {}
	self.summonerSpell = Runes.DefaultSummonerSpell

	local screen = Instance.new("ScreenGui")
	screen.Name = "BloxLegendsLobby"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = playerGui
	self.screen = screen

	-- ---------------- Lobby panel (zones overview) ----------------
	local lobbyPanel = newFrame(screen, {
		Name = "LobbyPanel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(280, 480),
		BackgroundTransparency = 0.15,
	})
	newLabel(lobbyPanel, "QUEUE ZONES", Color3.fromRGB(240, 220, 120), {
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.new(0, 0, 0, 4),
	})
	local zoneList = newFrame(lobbyPanel, {
		Name = "ZoneList",
		Size = UDim2.new(1, -16, 1, -50),
		Position = UDim2.new(0, 8, 0, 44),
		BackgroundTransparency = 1,
	})
	local zoneLayout = Instance.new("UIListLayout")
	zoneLayout.FillDirection = Enum.FillDirection.Vertical
	zoneLayout.Padding = UDim.new(0, 6)
	zoneLayout.SortOrder = Enum.SortOrder.LayoutOrder
	zoneLayout.Parent = zoneList
	self.lobbyPanel = lobbyPanel
	self.zoneListFrame = zoneList

	-- ---------------- In-Zone panel (waiting room) ----------------
	local zonePanel = newFrame(screen, {
		Name = "ZonePanel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 360),
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	self.zonePanel = zonePanel
	self.zoneTitleLabel = newLabel(zonePanel, "Zone ?", Color3.fromRGB(240, 240, 240), {
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.new(0, 0, 0, 6),
	})
	self.zonePlayersLabel = newLabel(zonePanel, "0 / 3", Color3.fromRGB(200, 200, 200), {
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.new(0, 0, 0, 44),
	})
	self.zoneMembersLabel = newLabel(zonePanel, "", Color3.fromRGB(220, 220, 220), {
		Size = UDim2.new(1, -16, 0, 120),
		Position = UDim2.new(0, 8, 0, 76),
	})
	self.zoneMembersLabel.TextWrapped = true
	self.zoneMembersLabel.TextYAlignment = Enum.TextYAlignment.Top
	self.zoneAccessLabel = newLabel(zonePanel, "Access: Open", Color3.fromRGB(200, 200, 200), {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 1, -120),
	})
	local leaveBtn = newButton(zonePanel, "Leave Zone", Color3.fromRGB(160, 70, 70), {
		Size = UDim2.new(1, -32, 0, 38),
		Position = UDim2.new(0, 16, 1, -48),
	})
	self.leaveZoneBtn = leaveBtn

	-- ---------------- Access selection prompt (appears near a pad) ----------------
	local accessPrompt = newFrame(screen, {
		Name = "AccessPrompt",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -120),
		Size = UDim2.fromOffset(440, 190),
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	self.accessPrompt = accessPrompt
	self.accessPromptTitle = newLabel(accessPrompt, "Zone ?", Color3.fromRGB(240, 220, 120), {
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.new(0, 0, 0, 6),
	})
	self.accessPromptSubtitle = newLabel(accessPrompt, "Choose access:", Color3.fromRGB(220, 220, 220), {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 42),
	})
	-- Three-mode panel (shown when the zone is empty)
	local modePanel = newFrame(accessPrompt, {
		Name = "ModePanel",
		Position = UDim2.new(0, 12, 1, -86),
		Size = UDim2.new(1, -24, 0, 70),
		BackgroundTransparency = 1,
	})
	self.accessFriendsBtn = newButton(modePanel, "Friends", Color3.fromRGB(60, 110, 150), {
		Size = UDim2.new(1 / 3, -8, 1, 0),
		Position = UDim2.fromScale(0, 0),
	})
	self.accessAnyoneBtn = newButton(modePanel, "Anyone", Color3.fromRGB(70, 130, 70), {
		Size = UDim2.new(1 / 3, -8, 1, 0),
		Position = UDim2.new(1 / 3, 4, 0, 0),
	})
	self.accessSoloBtn = newButton(modePanel, "Solo", Color3.fromRGB(140, 90, 70), {
		Size = UDim2.new(1 / 3, -8, 1, 0),
		Position = UDim2.new(2 / 3, 8, 0, 0),
	})
	self.modePanel = modePanel
	-- Single Join button (shown when the zone is hosted and joinable)
	self.accessJoinBtn = newButton(accessPrompt, "Join Zone", Color3.fromRGB(70, 140, 90), {
		Size = UDim2.new(1, -24, 0, 64),
		Position = UDim2.new(0, 12, 1, -80),
		Visible = false,
	})

	-- ---------------- Lobby timer (top-center) ----------------
	local timerFrame = newFrame(screen, {
		Name = "LobbyTimer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(260, 48),
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	self.timerFrame = timerFrame
	self.timerLabel = newLabel(timerFrame, "Match in 2:00", Color3.fromRGB(240, 240, 240), {
		Size = UDim2.fromScale(1, 1),
	})

	-- ---------------- Start Now button (testing) ----------------
	local startNowBtn = newButton(screen, "Start Now (test)", Color3.fromRGB(140, 100, 60), {
		Name = "StartNowBtn",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(220, 36),
	})
	self.startNowBtn = startNowBtn

	-- ---------------- Practice button (testing) ----------------
	-- Solo practice room with a respawning target dummy — used to feel out auto-attacks.
	local practiceBtn = newButton(screen, "Practice", Color3.fromRGB(80, 120, 160), {
		Name = "PracticeBtn",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 112),
		Size = UDim2.fromOffset(220, 36),
	})
	self.practiceBtn = practiceBtn

	-- ---------------- In-Match leave button ----------------
	local matchBtn = newButton(screen, "Leave Match (Esc)", Color3.fromRGB(160, 70, 70), {
		Name = "LeaveMatchBtn",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(180, 36),
		Visible = false,
	})
	self.leaveMatchBtn = matchBtn

	-- ---------------- Shop panel ----------------
	local shop = newFrame(screen, {
		Name = "ShopPanel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(360, 540),
		BackgroundTransparency = 0.1,
		Visible = false,
	})
	self.shopPanel = shop
	newLabel(shop, "RUNE SHOP", Color3.fromRGB(240, 220, 120), {
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.new(0, 0, 0, 4),
	})
	self.shopGoldLabel = newLabel(shop, "Gold: 0", Color3.fromRGB(240, 210, 90), {
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.new(0, 0, 0, 42),
	})

	local catList = newFrame(shop, {
		Size = UDim2.new(1, -16, 0, 290),
		Position = UDim2.new(0, 8, 0, 78),
		BackgroundTransparency = 1,
	})
	local catLayout = Instance.new("UIListLayout")
	catLayout.Padding = UDim.new(0, 6)
	catLayout.Parent = catList

	-- Build one row per rune category
	self.runeRows = {}
	for _, runeKey in ipairs(Runes.CatalogOrder) do
		local rune = Runes.Catalog[runeKey]
		local row = newFrame(catList, {
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = Color3.fromRGB(45, 45, 55),
		})
		local titleLabel = newLabel(row, rune.Name, Color3.fromRGB(240, 240, 240), {
			Size = UDim2.new(0.5, 0, 0.5, 0),
			Position = UDim2.fromOffset(8, 4),
		})
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		local descLabel = newLabel(row, "", Color3.fromRGB(180, 180, 180), {
			Size = UDim2.new(0.5, -8, 0.5, -4),
			Position = UDim2.new(0, 8, 0.5, 0),
		})
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		local buyBtn = newButton(row, "Buy T1 (50g)", Color3.fromRGB(70, 110, 70), {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(140, 40),
		})
		self.runeRows[runeKey] = { row = row, desc = descLabel, buyBtn = buyBtn }
	end

	newLabel(shop, "SUMMONER SPELL", Color3.fromRGB(240, 220, 120), {
		Size = UDim2.new(1, 0, 0, 28),
		Position = UDim2.new(0, 0, 0, 380),
	})
	local spellRow = newFrame(shop, {
		Size = UDim2.new(1, -16, 0, 140),
		Position = UDim2.new(0, 8, 0, 412),
		BackgroundTransparency = 1,
	})
	local spellLayout = Instance.new("UIListLayout")
	spellLayout.FillDirection = Enum.FillDirection.Vertical
	spellLayout.Padding = UDim.new(0, 4)
	spellLayout.Parent = spellRow
	self.spellButtons = {}
	for _, key in ipairs(Runes.SummonerSpellOrder) do
		local spell = Runes.SummonerSpells[key]
		local btn = newButton(spellRow, spell.Name .. " — " .. spell.Description, spell.Color, {
			Size = UDim2.new(1, 0, 0, 40),
			TextColor3 = Color3.fromRGB(20, 20, 20),
		})
		btn:SetAttribute("SpellKey", key)
		self.spellButtons[key] = btn
	end

	self.shopToggleHint = newLabel(screen, "Press B for Rune Shop", Color3.fromRGB(220, 220, 220), {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(220, 24),
	})

	self:_wireInputs()
	self:_render()
	return self
end

function LobbyUI:_wireInputs()
	-- Shop toggle (B)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.B and self.state == "lobby" then
			self.shopPanel.Visible = not self.shopPanel.Visible
		end
		if input.KeyCode == Enum.KeyCode.Escape and self.state == "in_match" then
			Remotes.get("LeaveMatch"):FireServer()
		end
	end)

	-- Zone leave button (kicks everyone in the zone — server enforces).
	self.leaveZoneBtn.MouseButton1Click:Connect(function()
		Remotes.get("LeaveZone"):FireServer()
	end)

	-- Start Now button (testing): start a match immediately, no timer.
	self.startNowBtn.MouseButton1Click:Connect(function()
		Remotes.get("StartNow"):FireServer()
	end)

	-- Practice button: teleport into the practice room with a target dummy.
	self.practiceBtn.MouseButton1Click:Connect(function()
		Remotes.get("StartPractice"):FireServer()
	end)

	-- Access selection: host an empty zone with one of three modes.
	self.accessFriendsBtn.MouseButton1Click:Connect(function()
		if self.state == "lobby" and self.hoveredZoneId then
			Remotes.get("JoinZone"):FireServer(self.hoveredZoneId, "friends")
		end
	end)
	self.accessAnyoneBtn.MouseButton1Click:Connect(function()
		if self.state == "lobby" and self.hoveredZoneId then
			Remotes.get("JoinZone"):FireServer(self.hoveredZoneId, "anyone")
		end
	end)
	self.accessSoloBtn.MouseButton1Click:Connect(function()
		if self.state == "lobby" and self.hoveredZoneId then
			Remotes.get("JoinZone"):FireServer(self.hoveredZoneId, "solo")
		end
	end)
	-- Join an already-hosted zone.
	self.accessJoinBtn.MouseButton1Click:Connect(function()
		if self.state == "lobby" and self.hoveredZoneId then
			-- accessMode is ignored once the zone has an owner — server keeps the existing mode.
			Remotes.get("JoinZone"):FireServer(self.hoveredZoneId, "anyone")
		end
	end)

	-- Leave match button
	self.leaveMatchBtn.MouseButton1Click:Connect(function()
		Remotes.get("LeaveMatch"):FireServer()
	end)

	-- Summoner spell buttons
	for key, btn in pairs(self.spellButtons) do
		btn.MouseButton1Click:Connect(function()
			Remotes.get("SetSummonerSpell"):FireServer(key)
		end)
	end
end

local function tierToBuy(ownedTier)
	return (ownedTier or 0) + 1
end

function LobbyUI:_renderShop()
	self.shopGoldLabel.Text = "Gold: " .. tostring(self.gold)
	for runeKey, ui in pairs(self.runeRows) do
		local rune = Runes.Catalog[runeKey]
		local owned = self.runes[runeKey] or 0
		local nextTier = tierToBuy(owned)
		local tierData = rune.Tiers[nextTier]
		if tierData then
			ui.buyBtn.Text = ("Buy T%d (%dg)"):format(nextTier, tierData.Cost)
			ui.buyBtn.AutoButtonColor = self.gold >= tierData.Cost
			ui.buyBtn.BackgroundColor3 = (self.gold >= tierData.Cost) and Color3.fromRGB(70, 110, 70) or Color3.fromRGB(60, 60, 60)
			ui.buyBtn.Active = self.gold >= tierData.Cost
			local bonusText = ("+%d"):format(tierData.Bonus)
			ui.desc.Text = "Owned: T" .. owned .. "  •  Next: " .. bonusText
		else
			ui.buyBtn.Text = "MAX"
			ui.buyBtn.AutoButtonColor = false
			ui.buyBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 60)
			ui.buyBtn.Active = false
			ui.desc.Text = "Owned: T" .. owned .. " (maxed)"
		end
	end
	for key, btn in pairs(self.spellButtons) do
		if key == self.summonerSpell then
			btn.BorderSizePixel = 4
			btn.BorderColor3 = Color3.fromRGB(255, 255, 255)
		else
			btn.BorderSizePixel = 0
		end
	end
end

local function wireRuneButtons(self)
	for runeKey, ui in pairs(self.runeRows) do
		ui.buyBtn.MouseButton1Click:Connect(function()
			local owned = self.runes[runeKey] or 0
			Remotes.get("BuyRune"):FireServer(runeKey, owned + 1)
		end)
	end
end

function LobbyUI:_renderLobby()
	-- Clear existing children except layout
	for _, child in ipairs(self.zoneListFrame:GetChildren()) do
		if not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	for id = 1, Config.Matchmaking.ZoneCount do
		local zone = self.zones[id]
		local row = newFrame(self.zoneListFrame, {
			LayoutOrder = id,
			Size = UDim2.new(1, 0, 0, 56),
			BackgroundColor3 = Color3.fromRGB(40, 40, 50),
		})
		local title = newLabel(row, "Zone " .. id, Color3.fromRGB(240, 220, 120), {
			Size = UDim2.new(1, -8, 0, 24),
			Position = UDim2.fromOffset(8, 2),
		})
		title.TextXAlignment = Enum.TextXAlignment.Left
		local count = zone and zone.count or 0
		local max = Config.Matchmaking.MaxPerZone
		local status = "open"
		if zone then
			status = zone.status
		end
		local statusStr = ("%d / %d  •  %s"):format(count, max, status)
		if zone and zone.accessMode == "friends" then
			statusStr = statusStr .. "  •  friends only"
		end
		local sub = newLabel(row, statusStr, Color3.fromRGB(200, 200, 200), {
			Size = UDim2.new(1, -8, 0, 24),
			Position = UDim2.new(0, 8, 0, 26),
		})
		sub.TextXAlignment = Enum.TextXAlignment.Left
	end
end

function LobbyUI:_renderZone()
	local zone = self.zones[self.zoneId]
	if not zone then
		return
	end
	self.zoneTitleLabel.Text = "Zone " .. self.zoneId
	self.zonePlayersLabel.Text = ("%d player(s) in zone"):format(zone.count)
	self.zoneMembersLabel.Text = "Members:\n" .. table.concat(zone.players or {}, "\n")
	local modeText = "Anyone"
	if zone.accessMode == "solo" then
		modeText = "Solo (locked)"
	elseif zone.accessMode == "friends" then
		modeText = "Friends Only"
	end
	self.zoneAccessLabel.Text = "Access: " .. modeText
end

-- Populate the access prompt according to the hovered zone's current state.
-- Three layouts: empty zone → 3-mode buttons; joinable hosted zone → single
-- Join button; locked zone → status message only.
function LobbyUI:_renderAccessPrompt()
	local id = self.hoveredZoneId
	if not id or self.state ~= "lobby" then
		self.accessPrompt.Visible = false
		return
	end
	local zone = self.zones[id]
	self.accessPrompt.Visible = true
	self.accessPromptTitle.Text = "Zone " .. id
	local empty = not zone or (zone.count or 0) == 0
	local mode = zone and zone.accessMode
	local full = zone and ((zone.count or 0) >= (zone.max or 3))

	if empty then
		self.accessPromptSubtitle.Text = "Choose access mode:"
		self.modePanel.Visible = true
		self.accessJoinBtn.Visible = false
	else
		self.modePanel.Visible = false
		if mode == "solo" then
			self.accessPromptSubtitle.Text = ("Solo — locked by %s"):format(zone.ownerName or "host")
			self.accessJoinBtn.Visible = false
		elseif full then
			self.accessPromptSubtitle.Text = ("Full (%d/%d)"):format(zone.count, zone.max)
			self.accessJoinBtn.Visible = false
		elseif mode == "friends" then
			self.accessPromptSubtitle.Text = ("Friends only — host: %s"):format(zone.ownerName or "?")
			self.accessJoinBtn.Visible = true
			self.accessJoinBtn.Text = ("Join (%d/%d)"):format(zone.count, zone.max)
		else -- anyone
			self.accessPromptSubtitle.Text = ("Open — host: %s"):format(zone.ownerName or "?")
			self.accessJoinBtn.Visible = true
			self.accessJoinBtn.Text = ("Join (%d/%d)"):format(zone.count, zone.max)
		end
	end
end

function LobbyUI:_render()
	self.lobbyPanel.Visible = (self.state == "lobby")
	self.zonePanel.Visible = (self.state == "in_zone")
	self.leaveMatchBtn.Visible = (self.state == "in_match")
	self.shopToggleHint.Visible = (self.state == "lobby")
	self.startNowBtn.Visible = (self.state == "lobby")
	self.practiceBtn.Visible = (self.state == "lobby")
	if self.state ~= "lobby" then
		self.shopPanel.Visible = false
	end
	-- Access prompt is only relevant in the lobby state while standing on a pad.
	if self.state ~= "lobby" then
		self.accessPrompt.Visible = false
		self.hoveredZoneId = nil
	end
	if self.state == "lobby" then
		self:_renderLobby()
	elseif self.state == "in_zone" then
		self:_renderZone()
	end
	self:_renderAccessPrompt()
	self:_renderShop()
end

-- Server pushes timer state via LobbyTimerChanged.
function LobbyUI:setLobbyTimer(payload)
	self.lobbyTimer = payload
end

-- Render the timer label each tick from the current `lobbyTimer` payload.
function LobbyUI:_tickTimer()
	local p = self.lobbyTimer
	if not p or not p.active then
		self.timerFrame.Visible = false
		return
	end
	-- The server sends `remaining` as the snapshot value when the event fired;
	-- locally we count down from that anchor.
	if not self._timerAnchor or self._timerAnchorPayload ~= p then
		self._timerAnchor = os.clock()
		self._timerRemaining = p.remaining or 0
		self._timerAnchorPayload = p
	end
	local elapsed = os.clock() - self._timerAnchor
	local remaining = math.max(0, self._timerRemaining - elapsed)
	local mm = math.floor(remaining / 60)
	local ss = math.floor(remaining % 60)
	self.timerLabel.Text = ("Match in %d:%02d"):format(mm, ss)
	self.timerFrame.Visible = true
end

-- Find every zone pad placed by LobbyBuilder (tagged with the ZoneId attribute).
function LobbyUI:_collectZonePads()
	local pads = {}
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return pads
	end
	for _, child in ipairs(lobby:GetChildren()) do
		if child:IsA("BasePart") then
			local id = child:GetAttribute("ZoneId")
			if id then
				pads[id] = child
			end
		end
	end
	return pads
end

-- Heartbeat-driven proximity check: when the local character is standing on a
-- pad (and we're still in the lobby), show the Open/Private prompt for that zone.
function LobbyUI:_startProximityWatch()
	local function nearestPad()
		local char = self.player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			return nil
		end
		local pads = self:_collectZonePads()
		local bestId, bestDist = nil, ZONE_PAD_RADIUS
		for id, pad in pairs(pads) do
			local dx = root.Position.X - pad.Position.X
			local dz = root.Position.Z - pad.Position.Z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist < bestDist then
				bestDist = dist
				bestId = id
			end
		end
		return bestId
	end

	RunService.Heartbeat:Connect(function()
		self:_tickTimer()
		if self.state ~= "lobby" then
			if self.accessPrompt.Visible then
				self.accessPrompt.Visible = false
			end
			self.hoveredZoneId = nil
			return
		end
		local id = nearestPad()
		if id ~= self.hoveredZoneId then
			self.hoveredZoneId = id
			self:_renderAccessPrompt()
		end
	end)
end

function LobbyUI:setState(state, zoneId)
	self.state = state
	self.zoneId = zoneId
	self:_render()
end

function LobbyUI:setZones(zones)
	self.zones = zones
	self:_render()
end

function LobbyUI:setPlayerData(data)
	self.gold = data.gold or 0
	self.runes = data.runes or {}
	self.summonerSpell = data.summonerSpell or self.summonerSpell
	self:_renderShop()
end

function LobbyUI:start()
	wireRuneButtons(self)
	self:_startProximityWatch()
end

return LobbyUI
