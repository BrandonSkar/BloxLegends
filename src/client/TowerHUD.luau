-- A sticky top-of-screen HUD strip showing every tower's HP. Always visible
-- regardless of camera angle, so the player can read all 6 tower healths at
-- a glance — no need to look at each tower in the world.
--
-- HP is read off the server-replicated TowerHPBar BillboardGui (the Fill
-- Frame's Size encodes HP%), so no extra remotes are needed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Responsive = require(script.Parent:WaitForChild("Responsive"))

local TowerHUD = {}
TowerHUD.__index = TowerHUD

local TEAM_COLOR = {
	Blue = Color3.fromRGB(100, 180, 255),
	Red = Color3.fromRGB(255, 100, 100),
}

local TIER_LABEL = { [1] = "T1", [2] = "T2", [3] = "NEXUS" }

local SLOT_W = 110
local SLOT_H = 44
local SLOT_PAD = 6

function TowerHUD.new()
	local self = setmetatable({}, TowerHUD)
	self.player = Players.LocalPlayer
	self.towers = {} -- towerId -> { part, frame, fill, label, lastInvuln }
	self.screen = nil
	self.connections = {}
	return self
end

function TowerHUD:attach(playerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name = "TowerHUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 5
	screen.Enabled = false
	screen.Parent = playerGui
	self.screen = screen

	-- Root UIScale so the strip shrinks on tablet/phone instead of clipping.
	local rootScale = Instance.new("UIScale")
	rootScale.Scale = Responsive.scale()
	rootScale.Parent = screen
	self.rootScale = rootScale

	-- Outer container split into Blue (left) / Red (right) groups so towers
	-- align by team regardless of discovery order. Pushed down by topInset so
	-- it never tucks behind the Roblox chat strip.
	local container = Instance.new("Frame")
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.Position = UDim2.new(0.5, 0, 0, Responsive.topInset())
	container.Size = UDim2.fromOffset(SLOT_W * 6 + SLOT_PAD * 7, SLOT_H)
	container.BackgroundTransparency = 1
	container.Parent = screen
	self.container = container

	local function makeGroup(alignment)
		local g = Instance.new("Frame")
		g.Size = UDim2.new(0.5, -SLOT_PAD, 1, 0)
		g.BackgroundTransparency = 1
		g.Parent = container
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.Padding = UDim.new(0, SLOT_PAD)
		layout.HorizontalAlignment = alignment
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = g
		return g
	end
	self.blueGroup = makeGroup(Enum.HorizontalAlignment.Left)
	self.redGroup = makeGroup(Enum.HorizontalAlignment.Right)
	self.blueGroup.Position = UDim2.fromOffset(0, 0)
	self.redGroup.Position = UDim2.new(0.5, SLOT_PAD, 0, 0)
end

function TowerHUD:setVisible(visible)
	if self.screen then
		self.screen.Enabled = visible
	end
end

local function teamColor(team)
	return TEAM_COLOR[team] or Color3.fromRGB(200, 200, 200)
end

function TowerHUD:_createSlot(id, rootPart)
	local team = rootPart:GetAttribute("Team")
	local tier = rootPart:GetAttribute("TowerTier") or 1
	local color = teamColor(team)
	local parent = (team == "Blue") and self.blueGroup or self.redGroup

	local frame = Instance.new("Frame")
	frame.Name = "Tower" .. id
	frame.Size = UDim2.fromOffset(SLOT_W, SLOT_H)
	frame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	-- T1 on the outside (left for blue, right for red); higher tiers toward
	-- the center so the row reads as "team's outer/inner/nexus".
	frame.LayoutOrder = (team == "Blue") and (4 - tier) or tier
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -8, 0, 16)
	label.Position = UDim2.fromOffset(4, 2)
	label.BackgroundTransparency = 1
	label.Text = (team or "?") .. " " .. (TIER_LABEL[tier] or "?")
	label.TextColor3 = color
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextStrokeTransparency = 0.4
	label.Parent = frame

	local bg = Instance.new("Frame")
	bg.Size = UDim2.new(1, -8, 0, 18)
	bg.Position = UDim2.fromOffset(4, 22)
	bg.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	bg.BorderSizePixel = 0
	bg.Parent = frame
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 3)
	bgCorner.Parent = bg

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	-- Overlay text for "INVULN" when a barrier is up.
	local invulnLabel = Instance.new("TextLabel")
	invulnLabel.Size = UDim2.fromScale(1, 1)
	invulnLabel.BackgroundTransparency = 1
	invulnLabel.Text = "INVULN"
	invulnLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
	invulnLabel.Font = Enum.Font.GothamBold
	invulnLabel.TextSize = 11
	invulnLabel.TextStrokeTransparency = 0.3
	invulnLabel.Visible = false
	invulnLabel.Parent = bg

	self.towers[id] = {
		part = rootPart,
		frame = frame,
		fill = fill,
		bg = bg,
		invulnLabel = invulnLabel,
		team = team,
		tier = tier,
	}
end

function TowerHUD:_discover()
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst:GetAttribute("TowerId") then
			local id = inst:GetAttribute("TowerId")
			if typeof(id) == "number" and not self.towers[id] then
				self:_createSlot(id, inst)
			end
		end
	end
end

function TowerHUD:_tick()
	for id, entry in pairs(self.towers) do
		local part = entry.part
		if not part.Parent then
			-- Tower model destroyed (e.g. arena rebuild) — drop the slot.
			entry.frame:Destroy()
			self.towers[id] = nil
		else
			local model = part.Parent
			local hpAnchor = model and model:FindFirstChild("HPAnchor")
			local bar = hpAnchor and hpAnchor:FindFirstChild("TowerHPBar")
			-- bar.Enabled = false means tower is invuln (server side flips this
			-- when a barrier goes up). Use it to drive the slot's INVULN overlay.
			local invuln = bar and not bar.Enabled or false
			if invuln ~= entry.lastInvuln then
				entry.lastInvuln = invuln
				entry.invulnLabel.Visible = invuln
				entry.fill.Visible = not invuln
			end
			if not invuln and bar then
				local serverFill = bar:FindFirstChild("Fill", true)
				if serverFill then
					entry.fill.Size = serverFill.Size
					entry.fill.BackgroundColor3 = serverFill.BackgroundColor3
				end
			end
			-- Dead tower: TowerId attribute gets cleared. Mark the slot dim.
			if part:GetAttribute("TowerId") == nil then
				entry.fill.Size = UDim2.fromScale(0, 1)
				entry.fill.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
				entry.invulnLabel.Visible = false
				entry.frame.BackgroundTransparency = 0.55
			end
		end
	end
end

function TowerHUD:start()
	-- Live-rescale + topbar-clear on viewport changes.
	Responsive.start()
	self._unsubResponsive = Responsive.onChanged(function(_class, scale)
		self.rootScale.Scale = scale
		self.container.Position = UDim2.new(0.5, 0, 0, Responsive.topInset())
	end)

	-- First-time discovery and slot wiring.
	self:_discover()

	-- Re-discover periodically — towers may be created after the client starts
	-- (ArenaBuilder happens before clients connect, but initTowers runs at
	-- match start and is what stamps the TowerId attribute).
	table.insert(self.connections, RunService.RenderStepped:Connect(function()
		self:_tick()
	end))
	task.spawn(function()
		while self.screen and self.screen.Parent do
			task.wait(1.5)
			self:_discover()
		end
	end)
end

function TowerHUD:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return TowerHUD
