-- In-match item shop panel (League-style). Shows only the local champion's
-- CLASS: a row of components and a grid of completed items that build from them.
-- Prices shown are the EFFECTIVE cost (full cost minus owned recipe components),
-- computed via Items.purchase so they match what the server charges. Spends
-- MATCH gold (pushed in via setGold); the server validates gold + in-base and
-- pushes owned counts back via ItemsChanged.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))

local UIStyle = require(script.Parent:WaitForChild("UIStyle"))
local Responsive = require(script.Parent:WaitForChild("Responsive"))
local P = UIStyle.Palette

local ShopUI = {}
ShopUI.__index = ShopUI

local function newLabel(parent, text, color, props)
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Text = text or ""
	lbl.TextColor3 = color or P.text
	lbl.Font = UIStyle.Font
	lbl.TextScaled = false
	lbl.TextSize = 15
	lbl.TextStrokeTransparency = 0.6
	lbl.Size = UDim2.fromScale(1, 1)
	if props then
		for k, v in pairs(props) do
			lbl[k] = v
		end
	end
	lbl.Parent = parent
	return lbl
end

function ShopUI.create(playerGui)
	local self = setmetatable({}, ShopUI)
	self.gold = 0
	self.owned = {}
	self.cards = {}
	self.classKey = nil
	self._onBuy = nil

	local screen = Instance.new("ScreenGui")
	screen.Name = "ShopUI"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 5
	screen.Enabled = false
	screen.Parent = playerGui
	self.screen = screen

	local rootScale = Instance.new("UIScale")
	rootScale.Scale = Responsive.scale()
	rootScale.Parent = screen
	self._unsub = Responsive.onChanged(function(_class, scale)
		rootScale.Scale = scale
	end)

	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Active = true -- modal: swallow clicks so you don't attack while shopping
	backdrop.Parent = screen

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(720, 520)
	panel.BackgroundColor3 = P.bg
	panel.BorderSizePixel = 0
	panel.Parent = screen
	UIStyle.corner(panel, 14)
	UIStyle.stroke(panel, { Color = P.accent, Thickness = 2, Transparency = 0.4 })

	-- ===== Header =====
	self.titleLabel = newLabel(panel, "ITEM SHOP", P.text, {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromOffset(18, 12),
		Size = UDim2.fromOffset(380, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 22,
	})
	self.goldLabel = newLabel(panel, "Gold: 0", P.accent, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -64, 0, 12),
		Size = UDim2.fromOffset(180, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 20,
	})
	local closeBtn = Instance.new("TextButton")
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -14, 0, 12)
	closeBtn.Size = UDim2.fromOffset(34, 30)
	closeBtn.BackgroundColor3 = P.panelLight
	closeBtn.Text = "✕"
	closeBtn.Font = UIStyle.Font
	closeBtn.TextSize = 18
	closeBtn.TextColor3 = P.text
	closeBtn.Parent = panel
	UIStyle.corner(closeBtn, 8)
	closeBtn.Activated:Connect(function()
		self:close()
	end)

	-- ===== Components row =====
	newLabel(panel, "COMPONENTS", P.textDim, {
		Position = UDim2.fromOffset(18, 50),
		Size = UDim2.fromOffset(300, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
	})
	local compRow = Instance.new("Frame")
	compRow.Position = UDim2.fromOffset(0, 74)
	compRow.Size = UDim2.new(1, 0, 0, 86)
	compRow.BackgroundTransparency = 1
	compRow.Parent = panel
	local compLayout = Instance.new("UIListLayout")
	compLayout.FillDirection = Enum.FillDirection.Horizontal
	compLayout.Padding = UDim.new(0, 12)
	compLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	compLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	compLayout.SortOrder = Enum.SortOrder.LayoutOrder
	compLayout.Parent = compRow
	self.compRow = compRow

	-- ===== Completed items grid =====
	newLabel(panel, "ITEMS", P.textDim, {
		Position = UDim2.fromOffset(18, 166),
		Size = UDim2.fromOffset(300, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
	})
	local itemGrid = Instance.new("Frame")
	itemGrid.AnchorPoint = Vector2.new(0.5, 0)
	itemGrid.Position = UDim2.new(0.5, 0, 0, 190)
	itemGrid.Size = UDim2.fromOffset(3 * 224 + 2 * 10, 2 * 112 + 10)
	itemGrid.BackgroundTransparency = 1
	itemGrid.Parent = panel
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.fromOffset(224, 112)
	gridLayout.CellPadding = UDim2.fromOffset(10, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = itemGrid
	self.itemGrid = itemGrid

	self:_refresh()
	return self
end

function ShopUI:setOnBuy(fn)
	self._onBuy = fn
end

-- Build (or rebuild) the card list for `classKey` (the local champion's class).
function ShopUI:setClass(classKey)
	if classKey == self.classKey then
		return
	end
	self.classKey = classKey
	self.cards = {}
	if self.titleLabel then
		local label = (Items.ClassLabel[classKey] or ""):upper()
		self.titleLabel.Text = label ~= "" and ("ITEM SHOP — " .. label) or "ITEM SHOP"
	end

	local function clear(container)
		for _, child in ipairs(container:GetChildren()) do
			if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") then
				child:Destroy()
			end
		end
	end
	clear(self.compRow)
	clear(self.itemGrid)
	if not classKey then
		return
	end

	for i, key in ipairs(Items.ComponentsByClass[classKey] or {}) do
		self:_buildCard(self.compRow, key, i, true)
	end
	for i, key in ipairs(Items.CompletedByClass[classKey] or {}) do
		self:_buildCard(self.itemGrid, key, i, false)
	end
	self:_refresh()
end

function ShopUI:_buildCard(parent, key, order, isComponent)
	local item = Items.Catalog[key]
	if not item then
		return
	end

	local card = Instance.new("Frame")
	card.LayoutOrder = order
	card.BackgroundColor3 = P.panel
	card.BorderSizePixel = 0
	if isComponent then
		card.Size = UDim2.fromOffset(150, 84)
	else
		card.Size = UDim2.fromScale(1, 1) -- fills its grid cell
	end
	card.Parent = parent
	UIStyle.corner(card, 10)
	UIStyle.stroke(card, { Color = item.Color, Thickness = 1.5, Transparency = 0.45 })
	UIStyle.padding(card, 8)

	newLabel(card, item.Name, item.Color, {
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, -46, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = isComponent and 14 or 15,
	})
	local ownedLabel = newLabel(card, "", P.good, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(44, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 13,
	})
	newLabel(card, item.Description, P.textDim, {
		Position = UDim2.fromOffset(0, 20),
		Size = UDim2.new(1, 0, 0, isComponent and 30 or 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		TextSize = 12,
	})
	if not isComponent then
		newLabel(card, "Builds: " .. Items.recipeText(key), P.textDim, {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -26),
			Size = UDim2.new(1, 0, 0, 14),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 11,
			TextTransparency = 0.25,
		})
	end

	local costLabel = newLabel(card, item.Cost .. "g", P.accent, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(72, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 15,
	})

	local buy = Instance.new("TextButton")
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Position = UDim2.fromScale(1, 1)
	buy.Size = UDim2.fromOffset(isComponent and 56 or 64, 26)
	buy.BackgroundColor3 = item.Color
	buy.Text = "BUY"
	buy.Font = UIStyle.Font
	buy.TextSize = 14
	buy.TextColor3 = Color3.fromRGB(20, 20, 24)
	buy.Parent = card
	UIStyle.corner(buy, 8)
	buy.Activated:Connect(function()
		local rec = self.cards[key]
		if rec and rec.affordable and self._onBuy then
			self._onBuy(key)
		end
	end)

	self.cards[key] = {
		buy = buy,
		costLabel = costLabel,
		ownedLabel = ownedLabel,
		affordable = false,
	}
end

function ShopUI:_refresh()
	for key, rec in pairs(self.cards) do
		local count = self.owned[key] or 0
		rec.ownedLabel.Text = count > 0 and ("x" .. count) or ""
		local cost = Items.purchase(key, self.owned) or (Items.Catalog[key] and Items.Catalog[key].Cost) or 0
		rec.costLabel.Text = cost .. "g"
		local affordable = self.gold >= cost
		rec.affordable = affordable
		rec.buy.AutoButtonColor = affordable
		rec.buy.BackgroundTransparency = affordable and 0 or 0.55
		rec.buy.TextTransparency = affordable and 0 or 0.45
		rec.costLabel.TextColor3 = affordable and P.accent or P.bad
	end
end

function ShopUI:setGold(amount)
	self.gold = amount or 0
	if self.goldLabel then
		self.goldLabel.Text = "Gold: " .. tostring(self.gold)
	end
	self:_refresh()
end

function ShopUI:setOwned(owned)
	self.owned = owned or {}
	self:_refresh()
end

function ShopUI:isOpen()
	return self.screen and self.screen.Enabled
end

function ShopUI:open()
	if self.screen then
		self.screen.Enabled = true
	end
end

function ShopUI:close()
	if self.screen then
		self.screen.Enabled = false
	end
end

function ShopUI:toggle()
	if self:isOpen() then
		self:close()
	else
		self:open()
	end
end

return ShopUI
