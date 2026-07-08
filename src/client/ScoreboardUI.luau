-- ScoreboardUI — the Tab scoreboard. Two team panels with one row per player:
-- champion, name, K / D / A, creep score, and gold earned. Data arrives via
-- the MatchStats remote (broadcast by ScoreService); this module just renders
-- the latest snapshot whenever it's visible.
--
-- PC: hold Tab. Touch: tap the HUD's team-score bar (wired in init.client).

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Champions = require(Shared:WaitForChild("Champions"))

local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local Responsive = require(script.Parent:WaitForChild("Responsive"))
local P = UIStyle.Palette

local ScoreboardUI = {}
ScoreboardUI.__index = ScoreboardUI

local PANEL_W = 460
local ROW_H = 30
local HEADER_H = 26

local TEAM_COLOR = {
	Blue = P.blueTeam,
	Red = P.redTeam,
}

function ScoreboardUI.create(playerGui)
	local self = setmetatable({}, ScoreboardUI)
	self.stats = {}
	self.localUserId = Players.LocalPlayer.UserId

	local screen = Instance.new("ScreenGui")
	screen.Name = "Scoreboard"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 20
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

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 120)
	panel.Size = UDim2.fromOffset(PANEL_W, 100) -- height set on rebuild
	panel.BackgroundColor3 = P.bg
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Parent = screen
	UIStyle.corner(panel, 12)
	UIStyle.stroke(panel, { Color = P.panelLight, Thickness = 1.5, Transparency = 0.3 })
	UIStyle.padding(panel, 10)
	self.panel = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel
	self.layout = layout

	return self
end

local function makeText(parent, text, color, x, w, opts)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position = UDim2.fromOffset(x, 0)
	lbl.Size = UDim2.new(0, w, 1, 0)
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.Font = UIStyle.Font
	lbl.TextSize = (opts and opts.size) or 14
	lbl.TextXAlignment = (opts and opts.align) or Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.Parent = parent
	return lbl
end

-- Column layout inside the 440px inner width:
--   [champ dot 16] [name 150] [K/D/A 90] [CS 60] [GOLD 90]
local COL = {
	dotX = 4,
	nameX = 28,
	nameW = 150,
	kdaX = 186,
	kdaW = 96,
	csX = 290,
	csW = 60,
	goldX = 356,
	goldW = 80,
}

function ScoreboardUI:_buildRow(order, s)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundColor3 = (s.userId == self.localUserId) and P.panelLight or P.panel
	row.BackgroundTransparency = 0.25
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = self.panel
	UIStyle.corner(row, 6)

	-- Champion color dot (grey until they've picked).
	local champ = s.champion and Champions.Roster[s.champion]
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0, 0.5)
	dot.Position = UDim2.new(0, COL.dotX, 0.5, 0)
	dot.Size = UDim2.fromOffset(16, 16)
	dot.BackgroundColor3 = champ and champ.Color or Color3.fromRGB(90, 90, 100)
	dot.BorderSizePixel = 0
	dot.Parent = row
	UIStyle.corner(dot, 8)

	local teamColor = TEAM_COLOR[s.team] or P.text
	makeText(row, s.name or "?", teamColor, COL.nameX, COL.nameW)
	makeText(
		row,
		("%d / %d / %d"):format(s.kills or 0, s.deaths or 0, s.assists or 0),
		P.text,
		COL.kdaX,
		COL.kdaW,
		{ align = Enum.TextXAlignment.Center }
	)
	makeText(row, tostring(s.cs or 0), P.textDim, COL.csX, COL.csW, { align = Enum.TextXAlignment.Center })
	makeText(row, tostring(s.gold or 0), P.accent, COL.goldX, COL.goldW, { align = Enum.TextXAlignment.Center })
end

function ScoreboardUI:_buildHeader(order, team)
	local header = Instance.new("Frame")
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.BackgroundTransparency = 1
	header.LayoutOrder = order
	header.Parent = self.panel
	local color = TEAM_COLOR[team] or P.text
	makeText(header, string.upper(team) .. " TEAM", color, COL.dotX, 180, { size = 15 })
	makeText(header, "K / D / A", P.textDim, COL.kdaX, COL.kdaW, { size = 12, align = Enum.TextXAlignment.Center })
	makeText(header, "CS", P.textDim, COL.csX, COL.csW, { size = 12, align = Enum.TextXAlignment.Center })
	makeText(header, "GOLD", P.textDim, COL.goldX, COL.goldW, { size = 12, align = Enum.TextXAlignment.Center })
end

function ScoreboardUI:_rebuild()
	for _, child in ipairs(self.panel:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	-- Sort rows: kills desc, then name, within each team.
	local byTeam = { Blue = {}, Red = {} }
	for _, s in ipairs(self.stats) do
		if byTeam[s.team] then
			table.insert(byTeam[s.team], s)
		end
	end
	local order = 0
	local totalRows = 0
	for _, team in ipairs({ "Blue", "Red" }) do
		local list = byTeam[team]
		table.sort(list, function(a, b)
			if (a.kills or 0) ~= (b.kills or 0) then
				return (a.kills or 0) > (b.kills or 0)
			end
			return (a.name or "") < (b.name or "")
		end)
		order = order + 1
		self:_buildHeader(order, team)
		totalRows = totalRows + 1
		for _, s in ipairs(list) do
			order = order + 1
			self:_buildRow(order, s)
			totalRows = totalRows + 1
		end
	end
	-- Resize the panel to content (headers + rows + padding + list gaps).
	local height = 0
	for _, child in ipairs(self.panel:GetChildren()) do
		if child:IsA("Frame") then
			height = height + child.Size.Y.Offset + 4
		end
	end
	self.panel.Size = UDim2.fromOffset(PANEL_W, height + 20)
end

function ScoreboardUI:setStats(stats)
	self.stats = stats or {}
	if self.screen.Enabled then
		self:_rebuild()
	end
end

function ScoreboardUI:setVisible(visible)
	if visible and not self.screen.Enabled then
		self:_rebuild()
	end
	self.screen.Enabled = visible and true or false
end

function ScoreboardUI:toggle()
	self:setVisible(not self.screen.Enabled)
end

return ScoreboardUI
