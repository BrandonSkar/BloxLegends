local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Champions = require(Shared:WaitForChild("Champions"))

local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local P = UIStyle.Palette

local ChampionSelectUI = {}
ChampionSelectUI.__index = ChampionSelectUI

local function newLabel(parent, text, color, props)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Text = text
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

-- Class display order (left to right). Champions inside a class come from
-- Champions.RosterOrder, filtered to that class.
local CLASS_ORDER = { "Attack", "Support", "Tank" }

local function championsInClass(class)
	local list = {}
	for _, key in ipairs(Champions.RosterOrder) do
		local c = Champions.Roster[key]
		if c and c.Class == class then
			table.insert(list, key)
		end
	end
	return list
end

function ChampionSelectUI.create(playerGui)
	local self = setmetatable({}, ChampionSelectUI)
	self.player = Players.LocalPlayer
	self.onPick = nil

	local screen = Instance.new("ScreenGui")
	screen.Name = "ChampionSelect"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.Enabled = false
	screen.Parent = playerGui
	self.screen = screen

	-- Dark backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = P.bg
	backdrop.BackgroundTransparency = 0.05
	backdrop.BorderSizePixel = 0
	backdrop.Parent = screen
	UIStyle.gradient(backdrop, {
		Color3.fromRGB(8, 9, 14),
		Color3.fromRGB(20, 22, 32),
	}, 90)

	-- Title strip
	local titleHolder = Instance.new("Frame")
	titleHolder.AnchorPoint = Vector2.new(0.5, 0)
	titleHolder.Position = UDim2.new(0.5, 0, 0, 24)
	titleHolder.Size = UDim2.fromOffset(540, 64)
	titleHolder.BackgroundTransparency = 1
	titleHolder.Parent = screen
	local title = newLabel(titleHolder, "PICK YOUR CHAMPION", P.accent, {
		Size = UDim2.new(1, 0, 0, 44),
		TextStrokeTransparency = 0.2,
	})
	title.TextScaled = false
	title.TextSize = 36
	local subtitle = newLabel(titleHolder, "Choose a kit — locked in for this match", P.textDim, {
		Position = UDim2.new(0, 0, 0, 44),
		Size = UDim2.new(1, 0, 0, 18),
	})
	subtitle.TextScaled = false
	subtitle.TextSize = 14

	-- Container for the three class columns
	local columns = Instance.new("Frame")
	columns.AnchorPoint = Vector2.new(0.5, 0.5)
	columns.Position = UDim2.fromScale(0.5, 0.55)
	columns.Size = UDim2.fromOffset(1100, 580)
	columns.BackgroundTransparency = 1
	columns.Parent = screen
	local columnsLayout = Instance.new("UIListLayout")
	columnsLayout.FillDirection = Enum.FillDirection.Horizontal
	columnsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	columnsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	columnsLayout.Padding = UDim.new(0, 20)
	columnsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnsLayout.Parent = columns

	self.cards = {}
	-- Per-card extras for the lock overlay (disabled state shown when a
	-- teammate has already picked this champion).
	self.cardRecords = {}
	self.lockedChampions = {}
	for ci, classKey in ipairs(CLASS_ORDER) do
		local classInfo = Champions.Classes[classKey]
		local list = championsInClass(classKey)

		local column = Instance.new("Frame")
		column.LayoutOrder = ci
		column.Size = UDim2.fromOffset(340, 580)
		column.BackgroundTransparency = 1
		column.Parent = columns

		-- Class header bar
		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, 0, 0, 56)
		header.BackgroundColor3 = classInfo.Color
		header.BorderSizePixel = 0
		header.Parent = column
		UIStyle.corner(header, 12)
		UIStyle.gradient(header, {
			Color3.fromRGB(
				math.clamp(classInfo.Color.R * 255 + 30, 0, 255),
				math.clamp(classInfo.Color.G * 255 + 30, 0, 255),
				math.clamp(classInfo.Color.B * 255 + 30, 0, 255)
			),
			classInfo.Color,
		}, 90)
		local classLabel = newLabel(header, classInfo.Label, Color3.fromRGB(20, 20, 20), {
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 26),
			TextStrokeTransparency = 1,
		})
		classLabel.TextScaled = false
		classLabel.TextSize = 22
		local classDesc = newLabel(header, classInfo.Description, Color3.fromRGB(30, 30, 30), {
			Position = UDim2.fromOffset(8, 30),
			Size = UDim2.new(1, -16, 0, 22),
			TextStrokeTransparency = 1,
		})
		classDesc.TextScaled = false
		classDesc.TextSize = 12

		-- Stack of cards within this class
		local cardsContainer = Instance.new("Frame")
		cardsContainer.Position = UDim2.fromOffset(0, 68)
		cardsContainer.Size = UDim2.new(1, 0, 1, -68)
		cardsContainer.BackgroundTransparency = 1
		cardsContainer.Parent = column
		local cardsLayout = Instance.new("UIListLayout")
		cardsLayout.FillDirection = Enum.FillDirection.Vertical
		cardsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		cardsLayout.Padding = UDim.new(0, 12)
		cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cardsLayout.Parent = cardsContainer

		for i, key in ipairs(list) do
			local champ = Champions.Roster[key]
			local card = Instance.new("TextButton")
			card.LayoutOrder = i
			card.Size = UDim2.fromOffset(340, 248)
			card.BackgroundColor3 = P.panel
			card.AutoButtonColor = false
			card.BorderSizePixel = 0
			card.Text = ""
			card.Parent = cardsContainer
			UIStyle.corner(card, 12)
			local stroke = UIStyle.stroke(card, {
				Color = champ.Color,
				Thickness = 2,
				Transparency = 0.3,
			})

			-- Champion-color header band
			local band = Instance.new("Frame")
			band.Size = UDim2.new(1, 0, 0, 70)
			band.BackgroundColor3 = champ.Color
			band.BorderSizePixel = 0
			band.Parent = card
			UIStyle.gradient(band, {
				Color3.fromRGB(
					math.clamp(champ.Color.R * 255 + 30, 0, 255),
					math.clamp(champ.Color.G * 255 + 30, 0, 255),
					math.clamp(champ.Color.B * 255 + 30, 0, 255)
				),
				champ.Color,
			}, 90)
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 12)
			bc.Parent = band

			local name = newLabel(band, champ.Name, Color3.fromRGB(20, 20, 20), {
				Position = UDim2.fromOffset(12, 6),
				Size = UDim2.new(1, -24, 0, 30),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextStrokeTransparency = 1,
			})
			name.TextScaled = false
			name.TextSize = 22

			local tag = newLabel(band, champ.Description, Color3.fromRGB(30, 30, 30), {
				Position = UDim2.fromOffset(12, 38),
				Size = UDim2.new(1, -24, 0, 28),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextStrokeTransparency = 1,
			})
			tag.TextScaled = false
			tag.TextSize = 12
			tag.TextWrapped = true

			-- Compact ability list
			local listFrame = Instance.new("Frame")
			listFrame.Position = UDim2.fromOffset(12, 80)
			listFrame.Size = UDim2.new(1, -24, 1, -92)
			listFrame.BackgroundTransparency = 1
			listFrame.Parent = card
			local lay = Instance.new("UIListLayout")
			lay.FillDirection = Enum.FillDirection.Vertical
			lay.Padding = UDim.new(0, 4)
			lay.Parent = listFrame

			for _, slot in ipairs(Champions.SlotOrder) do
				local a = champ.Abilities[slot]
				if a and slot ~= "Space" and slot ~= "Shift" then
					local row = Instance.new("Frame")
					row.Size = UDim2.new(1, 0, 0, 22)
					row.BackgroundColor3 = P.panelLight
					row.BackgroundTransparency = 0.4
					row.BorderSizePixel = 0
					row.Parent = listFrame
					UIStyle.corner(row, 4)
					local chip = newLabel(row, "[" .. slot .. "]", a.Color or P.accent, {
						Position = UDim2.fromOffset(8, 0),
						Size = UDim2.new(0, 32, 1, 0),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextStrokeTransparency = 1,
					})
					chip.TextScaled = false
					chip.TextSize = 12
					local abil = newLabel(row, a.Name, P.text, {
						Position = UDim2.fromOffset(44, 0),
						Size = UDim2.new(1, -52, 1, 0),
						TextXAlignment = Enum.TextXAlignment.Left,
						TextStrokeTransparency = 1,
					})
					abil.TextScaled = false
					abil.TextSize = 13
				end
			end

			-- Lock overlay: darkens the card, draws a big red X, and shows
			-- "Picked by <displayName>". Hidden until setLockedChampions marks
			-- this champion locked by a teammate.
			local lockOverlay = Instance.new("Frame")
			lockOverlay.Size = UDim2.fromScale(1, 1)
			lockOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			lockOverlay.BackgroundTransparency = 0.35
			lockOverlay.BorderSizePixel = 0
			lockOverlay.Visible = false
			lockOverlay.ZIndex = 5
			lockOverlay.Parent = card
			UIStyle.corner(lockOverlay, 12)

			-- Diagonal red bar acting as the "X / not available" mark.
			local slash = Instance.new("Frame")
			slash.AnchorPoint = Vector2.new(0.5, 0.5)
			slash.Position = UDim2.fromScale(0.5, 0.5)
			slash.Size = UDim2.new(1, 40, 0, 8)
			slash.Rotation = -22
			slash.BackgroundColor3 = P.bad
			slash.BackgroundTransparency = 0.15
			slash.BorderSizePixel = 0
			slash.ZIndex = 6
			slash.Parent = lockOverlay
			UIStyle.corner(slash, 4)

			-- "Picked by NAME" chip across the middle.
			local pickedChip = Instance.new("Frame")
			pickedChip.AnchorPoint = Vector2.new(0.5, 0.5)
			pickedChip.Position = UDim2.fromScale(0.5, 0.5)
			pickedChip.Size = UDim2.new(0.85, 0, 0, 36)
			pickedChip.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
			pickedChip.BackgroundTransparency = 0.1
			pickedChip.BorderSizePixel = 0
			pickedChip.ZIndex = 7
			pickedChip.Parent = lockOverlay
			UIStyle.corner(pickedChip, 8)
			UIStyle.stroke(pickedChip, { Color = P.bad, Thickness = 2, Transparency = 0.2 })
			local pickedLabel = newLabel(pickedChip, "Picked by ?", P.text, {
				Size = UDim2.fromScale(1, 1),
				TextStrokeTransparency = 0.4,
				ZIndex = 8,
			})
			pickedLabel.TextScaled = false
			pickedLabel.TextSize = 16

			-- Hover / press. Capture original size once — reading card.Size inside
			-- the closures compounds across rapid enter/leave because in-flight
			-- tweens leave Size somewhere between original and original+6.
			local originalSize = card.Size
			local hoverSize = originalSize + UDim2.fromOffset(6, 6)
			card.MouseEnter:Connect(function()
				if self.lockedChampions[key] then
					return
				end
				TweenService:Create(
					stroke,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad),
					{ Thickness = 4, Transparency = 0 }
				):Play()
				TweenService:Create(
					card,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad),
					{ Size = hoverSize }
				):Play()
			end)
			card.MouseLeave:Connect(function()
				if self.lockedChampions[key] then
					return
				end
				TweenService:Create(
					stroke,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad),
					{ Thickness = 2, Transparency = 0.3 }
				):Play()
				TweenService:Create(
					card,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad),
					{ Size = originalSize }
				):Play()
			end)
			card.MouseButton1Click:Connect(function()
				if self.lockedChampions[key] then
					return
				end
				if self.onPick then
					self.onPick(key)
				end
			end)

			self.cards[key] = card
			self.cardRecords[key] = {
				card = card,
				originalSize = originalSize,
				stroke = stroke,
				lockOverlay = lockOverlay,
				pickedLabel = pickedLabel,
			}
		end
	end

	return self
end

-- Apply the per-team lock state. `locked` is a map { [championKey] = displayName }.
-- Champions in the map are visually disabled with "Picked by <name>".
function ChampionSelectUI:setLockedChampions(locked)
	locked = locked or {}
	self.lockedChampions = {}
	for key, rec in pairs(self.cardRecords) do
		local pickerName = locked[key]
		if pickerName then
			self.lockedChampions[key] = pickerName
			rec.lockOverlay.Visible = true
			rec.pickedLabel.Text = "Picked by " .. tostring(pickerName)
			-- Snap card back to baseline so a hover-then-lock doesn't strand
			-- the card at its enlarged size.
			rec.card.Size = rec.originalSize
			rec.stroke.Thickness = 2
			rec.stroke.Transparency = 0.3
		else
			rec.lockOverlay.Visible = false
		end
	end
end

function ChampionSelectUI:show()
	self.screen.Enabled = true
	-- Wipe any stale lock state from a previous match; the server will push
	-- the current locked list right after firing ChampionSelectStart.
	self:setLockedChampions({})
end

function ChampionSelectUI:hide()
	self.screen.Enabled = false
end

function ChampionSelectUI:setOnPick(fn)
	self.onPick = fn
end

return ChampionSelectUI
