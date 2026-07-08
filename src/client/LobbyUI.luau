-- LobbyUI — every 2D panel shown while in the lobby: the queue-zone list, the
-- in-zone waiting card, the pad access prompt, the lobby timer, the action
-- buttons (Start Now / Enter The Pit), the Pit portal prompt, and the rune
-- shop. Styled through UIStyle so it matches the in-match HUD.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Runes = require(Shared:WaitForChild("Runes"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local Responsive = require(script.Parent:WaitForChild("Responsive"))
local P = UIStyle.Palette

local ZONE_PAD_RADIUS = 22 -- show the zone prompt within this many studs of a pad center
local PIT_PORTAL_RADIUS = 18 -- show the Pit prompt within this many studs of the portal

local EMBER = Color3.fromRGB(255, 120, 60)

-- Mirrors LobbyBuilder's pad colors so the zone list rows match the world.
local ZONE_ROW_COLORS = {
	Color3.fromRGB(80, 140, 220),
	Color3.fromRGB(220, 100, 100),
	Color3.fromRGB(120, 200, 110),
	Color3.fromRGB(220, 200, 90),
	Color3.fromRGB(180, 120, 220),
	Color3.fromRGB(220, 150, 90),
}

local LobbyUI = {}
LobbyUI.__index = LobbyUI

local FONT = UIStyle.Font

local function newFrame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = P.panel
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
	l.TextColor3 = color or P.text
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
	b.BackgroundColor3 = color or P.panelLight
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = P.text
	b.Font = FONT
	b.TextScaled = true
	if props then
		for k, v in pairs(props) do
			b[k] = v
		end
	end
	b.Parent = parent
	UIStyle.corner(b, 10)
	UIStyle.textBounds(b, 10, 22)
	UIStyle.makeButtonInteractive(b, b.BackgroundColor3)
	return b
end

-- Dresses a container as a standard lobby card: dark rounded panel + stroke.
local function styleCard(frame)
	frame.BackgroundColor3 = P.bg
	frame.BackgroundTransparency = 0.06
	UIStyle.corner(frame, 14)
	UIStyle.stroke(frame, { Color = P.panelLight, Thickness = 1.5, Transparency = 0.25 })
end

-- A slim accent bar under a card's title.
local function accentBar(parent, color, y, width)
	local bar = newFrame(parent, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.fromOffset(width or 60, 3),
		BackgroundColor3 = color,
	})
	UIStyle.corner(bar, 2)
	return bar
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
	self.pitMode = false -- true while we're in The Pit (relabels the leave button)

	local screen = Instance.new("ScreenGui")
	screen.Name = "BloxLegendsLobby"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Parent = playerGui
	self.screen = screen

	-- Root UIScale: shrinks the entire lobby UI to fit the actual viewport.
	local rootScale = Instance.new("UIScale")
	rootScale.Scale = Responsive.scale()
	rootScale.Parent = screen
	self.rootScale = rootScale

	-- ---------------- Lobby panel (zones overview) ----------------
	local lobbyPanel = newFrame(screen, {
		Name = "LobbyPanel",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 16, 0.5, 0),
		Size = UDim2.fromOffset(280, 470),
	})
	styleCard(lobbyPanel)
	newLabel(lobbyPanel, "QUEUE ZONES", P.accent, {
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.fromOffset(0, 8),
	})
	accentBar(lobbyPanel, P.accent, 42)
	newLabel(lobbyPanel, "Stand on a pad to host or join", P.textDim, {
		Size = UDim2.new(1, -16, 0, 18),
		Position = UDim2.fromOffset(8, 50),
	})
	local zoneList = newFrame(lobbyPanel, {
		Name = "ZoneList",
		Size = UDim2.new(1, -16, 1, -84),
		Position = UDim2.fromOffset(8, 76),
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
		Visible = false,
	})
	styleCard(zonePanel)
	self.zonePanel = zonePanel
	self.zoneTitleLabel = newLabel(zonePanel, "Zone ?", P.text, {
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 10),
	})
	accentBar(zonePanel, P.accent, 48)
	self.zonePlayersLabel = newLabel(zonePanel, "0 / 3", P.textDim, {
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 58),
	})
	self.zoneMembersLabel = newLabel(zonePanel, "", P.text, {
		Size = UDim2.new(1, -32, 0, 120),
		Position = UDim2.fromOffset(16, 92),
	})
	self.zoneMembersLabel.TextWrapped = true
	self.zoneMembersLabel.TextYAlignment = Enum.TextYAlignment.Top
	self.zoneMembersLabel.TextScaled = false
	self.zoneMembersLabel.TextSize = 18
	self.zoneAccessLabel = newLabel(zonePanel, "Access: Open", P.textDim, {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 1, -116),
	})
	local leaveBtn = newButton(zonePanel, "Leave Zone", Color3.fromRGB(160, 70, 70), {
		Size = UDim2.new(1, -32, 0, 40),
		Position = UDim2.new(0, 16, 1, -52),
	})
	self.leaveZoneBtn = leaveBtn

	-- ---------------- Access selection prompt (appears near a pad) ----------------
	local accessPrompt = newFrame(screen, {
		Name = "AccessPrompt",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(440, 180),
		Visible = false,
	})
	styleCard(accessPrompt)
	self.accessPrompt = accessPrompt
	self.accessPromptTitle = newLabel(accessPrompt, "Zone ?", P.accent, {
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.fromOffset(0, 10),
	})
	self.accessPromptSubtitle = newLabel(accessPrompt, "Choose access:", P.textDim, {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.fromOffset(0, 44),
	})
	-- Three-mode panel (shown when the zone is empty)
	local modePanel = newFrame(accessPrompt, {
		Name = "ModePanel",
		Position = UDim2.new(0, 12, 1, -80),
		Size = UDim2.new(1, -24, 0, 64),
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
		Size = UDim2.new(1, -24, 0, 58),
		Position = UDim2.new(0, 12, 1, -74),
		Visible = false,
	})

	-- ---------------- Pit portal prompt (appears near the portal) ----------------
	local pitPrompt = newFrame(screen, {
		Name = "PitPrompt",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(440, 150),
		Visible = false,
	})
	styleCard(pitPrompt)
	UIStyle.stroke(pitPrompt, { Color = EMBER, Thickness = 1.5, Transparency = 0.35 })
	self.pitPrompt = pitPrompt
	newLabel(pitPrompt, "🔥 THE PIT", EMBER, {
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.fromOffset(0, 8),
	})
	newLabel(pitPrompt, "Free-for-all warm-up: sparring bots, rivals, and a target dummy", P.textDim, {
		Size = UDim2.new(1, -24, 0, 20),
		Position = UDim2.fromOffset(12, 42),
	})
	self.pitEnterBtn = newButton(pitPrompt, "ENTER THE PIT", EMBER, {
		Size = UDim2.new(1, -24, 0, 56),
		Position = UDim2.new(0, 12, 1, -70),
		TextColor3 = Color3.fromRGB(30, 18, 10),
	})

	-- ---------------- Lobby timer (top-center pill) ----------------
	local timerFrame = newFrame(screen, {
		Name = "LobbyTimer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(240, 44),
		Visible = false,
	})
	styleCard(timerFrame)
	self.timerFrame = timerFrame
	self.timerLabel = newLabel(timerFrame, "Match in 2:00", P.text, {
		Size = UDim2.new(1, -20, 1, -12),
		Position = UDim2.fromOffset(10, 6),
	})

	-- ---------------- Action buttons (top-center column) ----------------
	local startNowBtn = newButton(screen, "⚔  START MATCH NOW", Color3.fromRGB(150, 105, 55), {
		Name = "StartNowBtn",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 66),
		Size = UDim2.fromOffset(230, 38),
	})
	self.startNowBtn = startNowBtn

	-- Quick entry to The Pit (same as walking to the portal).
	local practiceBtn = newButton(screen, "🔥  ENTER THE PIT", Color3.fromRGB(150, 75, 45), {
		Name = "PracticeBtn",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 110),
		Size = UDim2.fromOffset(230, 38),
	})
	self.practiceBtn = practiceBtn

	-- ---------------- In-Match leave button ----------------
	local matchBtn = newButton(screen, "Leave Match (Esc)", Color3.fromRGB(160, 70, 70), {
		Name = "LeaveMatchBtn",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 16),
		Size = UDim2.fromOffset(180, 36),
	})
	matchBtn.Visible = false
	self.leaveMatchBtn = matchBtn

	-- ---------------- Shop panel ----------------
	local shop = newFrame(screen, {
		Name = "ShopPanel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(360, 560),
		Visible = false,
	})
	styleCard(shop)
	self.shopPanel = shop
	newLabel(shop, "RUNE SHOP", P.accent, {
		Size = UDim2.new(1, 0, 0, 32),
		Position = UDim2.fromOffset(0, 8),
	})
	accentBar(shop, P.accent, 42)
	self.shopGoldLabel = newLabel(shop, "Gold: 0", Color3.fromRGB(240, 210, 90), {
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 50),
	})

	local catList = newFrame(shop, {
		Size = UDim2.new(1, -16, 0, 290),
		Position = UDim2.fromOffset(8, 84),
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
			BackgroundColor3 = P.panel,
		})
		UIStyle.corner(row, 8)
		UIStyle.stroke(row, { Color = P.panelLight, Thickness = 1, Transparency = 0.5 })
		local titleLabel = newLabel(row, rune.Name, P.text, {
			Size = UDim2.fromScale(0.5, 0.5),
			Position = UDim2.fromOffset(10, 4),
		})
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		local descLabel = newLabel(row, "", P.textDim, {
			Size = UDim2.new(0.5, -8, 0.5, -4),
			Position = UDim2.new(0, 10, 0.5, 0),
		})
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		local buyBtn = newButton(row, "Buy T1 (50g)", Color3.fromRGB(70, 110, 70), {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(130, 40),
		})
		self.runeRows[runeKey] = { row = row, desc = descLabel, buyBtn = buyBtn }
	end

	newLabel(shop, "SUMMONER SPELL", P.accent, {
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 384),
	})
	local spellRow = newFrame(shop, {
		Size = UDim2.new(1, -16, 0, 140),
		Position = UDim2.fromOffset(8, 414),
		BackgroundTransparency = 1,
	})
	local spellLayout = Instance.new("UIListLayout")
	spellLayout.FillDirection = Enum.FillDirection.Vertical
	spellLayout.Padding = UDim.new(0, 4)
	spellLayout.Parent = spellRow
	self.spellButtons = {}
	self.spellStrokes = {}
	for _, key in ipairs(Runes.SummonerSpellOrder) do
		local spell = Runes.SummonerSpells[key]
		local btn = newButton(spellRow, spell.Name .. " — " .. spell.Description, spell.Color, {
			Size = UDim2.new(1, 0, 0, 40),
			TextColor3 = Color3.fromRGB(20, 20, 20),
		})
		btn:SetAttribute("SpellKey", key)
		-- Selection ring, toggled in _renderShop.
		self.spellStrokes[key] = UIStyle.stroke(btn, { Color = Color3.fromRGB(255, 255, 255), Thickness = 3, Transparency = 1 })
		self.spellButtons[key] = btn
	end

	local hint = newLabel(screen, "Press B for Rune Shop", P.textDim, {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -16),
		Size = UDim2.fromOffset(220, 24),
	})
	hint.TextXAlignment = Enum.TextXAlignment.Right
	self.shopToggleHint = hint

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

	-- Start Now button: start a match immediately if a legal pairing exists.
	self.startNowBtn.MouseButton1Click:Connect(function()
		Remotes.get("StartNow"):FireServer()
	end)

	-- Both Pit entries fire the same remote.
	self.practiceBtn.MouseButton1Click:Connect(function()
		Remotes.get("StartPractice"):FireServer()
	end)
	self.pitEnterBtn.MouseButton1Click:Connect(function()
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
			local affordable = self.gold >= tierData.Cost
			ui.buyBtn.Text = ("Buy T%d (%dg)"):format(nextTier, tierData.Cost)
			ui.buyBtn.BackgroundColor3 = affordable and Color3.fromRGB(70, 110, 70) or Color3.fromRGB(60, 60, 60)
			ui.buyBtn.Active = affordable
			local bonusText = ("+%d"):format(tierData.Bonus)
			ui.desc.Text = "Owned: T" .. owned .. "  •  Next: " .. bonusText
		else
			ui.buyBtn.Text = "MAX"
			ui.buyBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 60)
			ui.buyBtn.Active = false
			ui.desc.Text = "Owned: T" .. owned .. " (maxed)"
		end
	end
	for key, stroke in pairs(self.spellStrokes) do
		stroke.Transparency = (key == self.summonerSpell) and 0 or 1
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
		local zoneColor = ZONE_ROW_COLORS[((id - 1) % #ZONE_ROW_COLORS) + 1]
		local row = newFrame(self.zoneListFrame, {
			LayoutOrder = id,
			Size = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = P.panel,
		})
		UIStyle.corner(row, 8)
		UIStyle.stroke(row, { Color = P.panelLight, Thickness = 1, Transparency = 0.55 })

		-- Colored identity dot matching the pad in the world.
		local dot = newFrame(row, {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 10, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = zoneColor,
		})
		UIStyle.corner(dot, 6)

		local title = newLabel(row, "Zone " .. id, P.text, {
			Size = UDim2.new(1, -40, 0, 22),
			Position = UDim2.fromOffset(30, 5),
		})
		title.TextXAlignment = Enum.TextXAlignment.Left

		local count = zone and zone.count or 0
		local max = (zone and zone.max) or Config.Matchmaking.MaxPerZone
		local status = zone and zone.status or "open"
		local statusStr, statusColor
		if status == "in_match" then
			statusStr = "in match"
			statusColor = P.textDim
		elseif count >= max then
			statusStr = ("%d / %d  •  full"):format(count, max)
			statusColor = P.bad
		elseif count > 0 then
			statusStr = ("%d / %d  •  waiting"):format(count, max)
			statusColor = P.good
		else
			statusStr = ("%d / %d  •  open"):format(count, max)
			statusColor = P.textDim
		end
		if zone and zone.accessMode == "friends" then
			statusStr = statusStr .. "  •  friends"
		elseif zone and zone.accessMode == "solo" then
			statusStr = statusStr .. "  •  solo"
		end
		local sub = newLabel(row, statusStr, statusColor, {
			Size = UDim2.new(1, -40, 0, 18),
			Position = UDim2.fromOffset(30, 29),
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
	self.zonePlayersLabel.Text = ("%d player(s) in zone — waiting for the timer or Start Now"):format(zone.count)
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

function LobbyUI:_renderPitPrompt()
	self.pitPrompt.Visible = (self.state == "lobby") and self.nearPitPortal == true
end

function LobbyUI:_render()
	self.lobbyPanel.Visible = (self.state == "lobby")
	self.zonePanel.Visible = (self.state == "in_zone")
	self.leaveMatchBtn.Visible = (self.state == "in_match")
	self.leaveMatchBtn.Text = self.pitMode and "Leave the Pit (Esc)" or "Leave Match (Esc)"
	self.shopToggleHint.Visible = (self.state == "lobby")
	self.startNowBtn.Visible = (self.state == "lobby")
	self.practiceBtn.Visible = (self.state == "lobby")
	if self.state ~= "lobby" then
		self.shopPanel.Visible = false
		self.accessPrompt.Visible = false
		self.hoveredZoneId = nil
		self.nearPitPortal = false
	end
	if self.state == "lobby" then
		self:_renderLobby()
	elseif self.state == "in_zone" then
		self:_renderZone()
	end
	self:_renderAccessPrompt()
	self:_renderPitPrompt()
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
	self.timerLabel.Text = ("⚔  Match in %d:%02d"):format(mm, ss)
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

-- The Pit portal gate part (tagged with the PitPortal attribute, lives in
-- Lobby.Decor). Cached after the first successful find.
function LobbyUI:_findPitPortal()
	if self._pitPortal and self._pitPortal.Parent then
		return self._pitPortal
	end
	local lobby = Workspace:FindFirstChild("Lobby")
	if not lobby then
		return nil
	end
	for _, inst in ipairs(lobby:GetDescendants()) do
		if inst:IsA("BasePart") and inst:GetAttribute("PitPortal") then
			self._pitPortal = inst
			return inst
		end
	end
	return nil
end

-- Heartbeat-driven proximity check: when the local character is standing on a
-- pad (or by the Pit portal) while in the lobby, show the matching prompt.
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

	local function nearPortal()
		local char = self.player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			return false
		end
		local portal = self:_findPitPortal()
		if not portal then
			return false
		end
		local dx = root.Position.X - portal.Position.X
		local dz = root.Position.Z - portal.Position.Z
		return (dx * dx + dz * dz) <= PIT_PORTAL_RADIUS * PIT_PORTAL_RADIUS
	end

	RunService.Heartbeat:Connect(function()
		self:_tickTimer()
		if self.state ~= "lobby" then
			if self.accessPrompt.Visible then
				self.accessPrompt.Visible = false
			end
			if self.pitPrompt.Visible then
				self.pitPrompt.Visible = false
			end
			self.hoveredZoneId = nil
			self.nearPitPortal = false
			return
		end
		local id = nearestPad()
		if id ~= self.hoveredZoneId then
			self.hoveredZoneId = id
			self:_renderAccessPrompt()
		end
		local near = nearPortal()
		if near ~= self.nearPitPortal then
			self.nearPitPortal = near
			self:_renderPitPrompt()
		end
	end)
end

function LobbyUI:setState(state, zoneId)
	self.state = state
	self.zoneId = zoneId
	if state ~= "in_match" then
		self.pitMode = false
	end
	self:_render()
end

-- Called (via init.client) when the server confirms we entered The Pit.
function LobbyUI:setPitMode(on)
	self.pitMode = on and true or false
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

	-- Keep the root scale in sync with viewport size changes.
	Responsive.start()
	self._unsubResponsive = Responsive.onChanged(function(_class, scale)
		self.rootScale.Scale = scale
	end)
end

return LobbyUI
