-- Renders a translucent disc on the ground around the LOCAL player at their
-- current auto-attack range. The part is created client-side and parented to
-- Workspace, so it does not replicate to other players — enemies never see it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Champions = require(Shared:WaitForChild("Champions"))

local AttackRangeIndicator = {}
AttackRangeIndicator.__index = AttackRangeIndicator

function AttackRangeIndicator.new()
	local self = setmetatable({}, AttackRangeIndicator)
	self.player = Players.LocalPlayer
	self.championKey = nil
	self.range = nil
	self.part = nil
	self.enabled = false
	self.connections = {}
	return self
end

local function buildPart()
	local p = Instance.new("Part")
	p.Name = "AttackRangeIndicator"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.ForceField
	p.Color = Color3.fromRGB(150, 220, 255)
	p.Transparency = 0.65
	p.Size = Vector3.new(0.2, 2, 2) -- updated when setChampion runs
	p.Parent = workspace
	return p
end

function AttackRangeIndicator:setChampion(key)
	self.championKey = key
	if not key then
		self.range = nil
		if self.part then
			self.part.Transparency = 1
		end
		return
	end
	local profile = Champions.getAutoAttackProfile(key)
	self.range = profile and profile.Range or nil
	if self.range and not self.part then
		self.part = buildPart()
	end
	if self.part and self.range then
		self.part.Size = Vector3.new(0.2, self.range * 2, self.range * 2)
		self.part.Transparency = self.enabled and 0.65 or 1
	end
end

-- Toggle visibility based on match state (called from init.client.luau).
function AttackRangeIndicator:setEnabled(enabled)
	self.enabled = enabled
	if self.part then
		self.part.Transparency = (enabled and self.range) and 0.65 or 1
	end
end

function AttackRangeIndicator:_tick()
	if not self.part or not self.enabled or not self.range then
		return
	end
	local char = self.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		self.part.Transparency = 1
		return
	end
	-- Cylinder shape's long axis is local +X. Rotating 90° around Z makes
	-- that axis point world-up, so Size.Y and Size.Z become the horizontal
	-- diameter (the actual range circle).
	local groundY = root.Position.Y - 2.5
	local pos = Vector3.new(root.Position.X, groundY, root.Position.Z)
	self.part.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	-- Re-affirm transparency in case it got muted last frame by missing HRP.
	if self.part.Transparency > 0.9 then
		self.part.Transparency = 0.65
	end
end

function AttackRangeIndicator:start()
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function()
			self:_tick()
		end)
	)
end

function AttackRangeIndicator:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	if self.part then
		self.part:Destroy()
		self.part = nil
	end
end

return AttackRangeIndicator
