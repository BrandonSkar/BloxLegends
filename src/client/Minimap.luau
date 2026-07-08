-- Minimap — bottom-right overview of the arena. Everything is read straight
-- off replicated world state (attributes the server already stamps), so no
-- extra remotes are needed:
--   • champions → workspace characters with a Team attribute (dots; you get
--     a white ring)
--   • lane minions / jungle monsters → workspace.Minions models
--   • towers → BaseParts with a live TowerId attribute (squares; dead towers
--     lose the attribute and vanish from the map)
-- Static backdrop: the lane centerline, base pads, camp pads, and the pit.
--
-- No fog of war — this is a casual MOBA; seeing the whole fight helps new
-- players understand the map.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local Responsive = require(script.Parent:WaitForChild("Responsive"))
local P = UIStyle.Palette

local Minimap = {}
Minimap.__index = Minimap

local MAP_W = 216
local MAP_H = 110
local REFRESH = 0.15

local TEAM_COLOR = {
	Blue = Color3.fromRGB(100, 180, 255),
	Red = Color3.fromRGB(255, 110, 100),
	Jungle = Color3.fromRGB(190, 140, 255),
	Pit = Color3.fromRGB(255, 140, 70), -- sparring bots in The Pit
}

function Minimap.new()
	local self = setmetatable({}, Minimap)
	self.player = Players.LocalPlayer
	self.enabled = false
	self.markers = {} -- key -> Frame (pooled between refreshes)
	return self
end

-- World XZ → map pixel offset. The arena spans ±HalfLength (x) / ±HalfWidth
-- (z); north (+z) points up on the map.
local function worldToMap(pos)
	local hx = Config.Arena.HalfLength
	local hz = Config.Arena.HalfWidth
	local u = math.clamp((pos.X + hx) / (2 * hx), 0, 1)
	local v = math.clamp(1 - (pos.Z + hz) / (2 * hz), 0, 1)
	return UDim2.fromOffset(math.floor(u * MAP_W + 0.5), math.floor(v * MAP_H + 0.5))
end

function Minimap:attach(playerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name = "Minimap"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 4
	screen.Enabled = false
	screen.Parent = playerGui
	self.screen = screen

	local rootScale = Instance.new("UIScale")
	rootScale.Scale = Responsive.scale()
	rootScale.Parent = screen
	Responsive.start()
	self._unsubResponsive = Responsive.onChanged(function(_class, scale)
		rootScale.Scale = scale
	end)

	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.new(1, -14, 1, -14)
	frame.Size = UDim2.fromOffset(MAP_W, MAP_H)
	frame.BackgroundColor3 = Color3.fromRGB(14, 18, 16)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Active = false
	frame.Parent = screen
	UIStyle.corner(frame, 8)
	UIStyle.stroke(frame, { Color = P.panelLight, Thickness = 1.5, Transparency = 0.3 })
	self.frame = frame

	self:_drawStatic()
	return self
end

local function staticDot(parent, pos, size, color, transparency, round)
	local d = Instance.new("Frame")
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = worldToMap(pos)
	d.Size = UDim2.fromOffset(size, size)
	d.BackgroundColor3 = color
	d.BackgroundTransparency = transparency or 0
	d.BorderSizePixel = 0
	d.ZIndex = 2
	d.Parent = parent
	if round then
		UIStyle.corner(d, math.ceil(size / 2))
	end
	return d
end

function Minimap:_drawStatic()
	-- Lane centerline: a dot every few studs between waypoints.
	local wps = Config.LaneWaypoints
	local laneColor = Color3.fromRGB(70, 78, 70)
	for i = 1, #wps - 1 do
		local a, b = wps[i], wps[i + 1]
		local segLen = (b - a).Magnitude
		local steps = math.max(1, math.floor(segLen / 18))
		for s = 0, steps do
			staticDot(self.frame, a + (b - a) * (s / steps), 5, laneColor, 0.25, true)
		end
	end
	-- Base pads.
	staticDot(self.frame, Config.Teams.Blue.SpawnPosition, 12, TEAM_COLOR.Blue, 0.55, true)
	staticDot(self.frame, Config.Teams.Red.SpawnPosition, 12, TEAM_COLOR.Red, 0.55, true)
	-- Jungle camp pads.
	for _, camp in ipairs(Config.JungleCamps) do
		staticDot(self.frame, camp.position, 6, Color3.fromRGB(120, 110, 80), 0.4, true)
	end
	-- Boss pit.
	staticDot(self.frame, Config.BossLair.position, 10, TEAM_COLOR.Jungle, 0.5, true)
end

-- Fetch-or-create a pooled marker for this refresh pass. Markers are wrapped
-- in { frame, seen } records — Instances can't carry ad-hoc fields.
function Minimap:_marker(key, size, color, zIndex, round)
	local rec = self.markers[key]
	if not rec then
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.Parent = self.frame
		if round then
			UIStyle.corner(f, 12)
		end
		rec = { frame = f }
		self.markers[key] = rec
	end
	rec.frame.Size = UDim2.fromOffset(size, size)
	rec.frame.BackgroundColor3 = color
	rec.frame.ZIndex = zIndex or 5
	rec.seen = true
	return rec.frame
end

function Minimap:_refresh()
	for _, rec in pairs(self.markers) do
		rec.seen = false
	end

	-- Champions.
	for _, other in ipairs(Players:GetPlayers()) do
		local char = other.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local team = char and char:GetAttribute("Team")
		if root and team then
			local isMe = other == self.player
			local m = self:_marker("p" .. other.UserId, isMe and 9 or 7, TEAM_COLOR[team] or P.text, 7, true)
			m.Position = worldToMap(root.Position)
			-- White ring on the local player's dot.
			if isMe and not m:FindFirstChildOfClass("UIStroke") then
				local stroke = Instance.new("UIStroke")
				stroke.Color = Color3.fromRGB(255, 255, 255)
				stroke.Thickness = 1.5
				stroke.Parent = m
			end
		end
	end

	-- Minions + jungle monsters.
	local bin = Workspace:FindFirstChild("Minions")
	if bin then
		for _, model in ipairs(bin:GetChildren()) do
			local id = model:GetAttribute("MinionId")
			local team = model:GetAttribute("Team")
			local root = model:FindFirstChild("HumanoidRootPart")
			if id and team and root then
				local isJungle = team == "Jungle"
				local m = self:_marker(
					"m" .. tostring(id),
					isJungle and 6 or 3,
					TEAM_COLOR[team] or P.textDim,
					isJungle and 6 or 4,
					isJungle
				)
				m.Position = worldToMap(root.Position)
			end
		end
	end

	-- Towers (live ones carry a TowerId attribute; squares read as buildings).
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("BasePart") then
			local id = inst:GetAttribute("TowerId")
			local team = inst:GetAttribute("Team")
			if typeof(id) == "number" and (team == "Blue" or team == "Red") then
				local m = self:_marker("t" .. tostring(id), 7, TEAM_COLOR[team], 5, false)
				m.Position = worldToMap(inst.Position)
			end
		end
	end

	-- Drop markers for anything that disappeared this pass.
	for key, rec in pairs(self.markers) do
		if not rec.seen then
			rec.frame:Destroy()
			self.markers[key] = nil
		end
	end
end

function Minimap:setEnabled(enabled)
	self.enabled = enabled and true or false
	if self.screen then
		self.screen.Enabled = self.enabled
	end
	if self.enabled and not self._loopRunning then
		self._loopRunning = true
		task.spawn(function()
			while self.enabled and self.screen and self.screen.Parent do
				self:_refresh()
				task.wait(REFRESH)
			end
			self._loopRunning = false
		end)
	end
end

return Minimap
