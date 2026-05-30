-- Floating damage numbers + a brief red hit-flash on champions.
-- Listens to the DamageDealt remote (fired by CombatService / MinionService /
-- TowerService) and renders feedback on every client that sees the world.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local DamageFX = {}
DamageFX.__index = DamageFX

function DamageFX.new()
	local self = setmetatable({}, DamageFX)
	self.connections = {}
	return self
end

local function spawnNumber(pos, amount)
	-- Anchor part holds the BillboardGui so it can drift up in world space.
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = pos + Vector3.new(math.random(-15, 15) / 10, 0, math.random(-15, 15) / 10)
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(120, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = tostring(math.floor(amount + 0.5))
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = (amount >= 100) and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(255, 230, 220)
	label.TextStrokeColor3 = Color3.fromRGB(60, 0, 0)
	label.TextStrokeTransparency = 0.1
	label.TextScaled = true
	label.Parent = gui

	-- Drift up while fading out.
	local risen = 4
	TweenService:Create(anchor, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = anchor.Position + Vector3.new(0, risen, 0),
	}):Play()
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	Debris:AddItem(anchor, 1.0)
end

local function flashChampion(victimUserId)
	local player = Players:GetPlayerByUserId(victimUserId)
	local char = player and player.Character
	if not char then
		return
	end
	-- Use a Highlight overlay rather than mutating each part's Color, so
	-- overlapping flashes can't leak state into the character's real color.
	-- Reuse the same Highlight if one is already attached (resets its timer).
	local hl = char:FindFirstChild("HitFlash")
	if not hl then
		hl = Instance.new("Highlight")
		hl.Name = "HitFlash"
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.OutlineTransparency = 1
		hl.Adornee = char
		hl.Parent = char
	end
	hl.FillColor = Color3.fromRGB(255, 80, 80)
	hl.FillTransparency = 0.4
	hl.Enabled = true
	-- Each flash schedules its own clear; we use a stamp to make sure only
	-- the latest one disables the highlight.
	local stamp = os.clock()
	hl:SetAttribute("LastFlash", stamp)
	task.delay(0.14, function()
		if hl and hl.Parent and hl:GetAttribute("LastFlash") == stamp then
			hl.Enabled = false
		end
	end)
end

function DamageFX:start()
	table.insert(
		self.connections,
		Remotes.get("DamageDealt").OnClientEvent:Connect(function(pos, amount, victimUserId)
			spawnNumber(pos, amount)
			if victimUserId then
				flashChampion(victimUserId)
			end
		end)
	)
end

function DamageFX:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return DamageFX
