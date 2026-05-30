-- Renders the visual half of an auto-attack on every client. The server
-- runs the damage clock; we just make it look snappy.
--
-- Listens to AutoAttackFired(attackerType, attackerId, targetType, targetId,
-- style, color, travelTime) and either:
--   ranged → spawns a small homing projectile that flies to the target
--   melee  → spawns a quick slash arc at the target's position

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local AutoAttackFX = {}
AutoAttackFX.__index = AutoAttackFX

function AutoAttackFX.new(minionService, towerService)
	local self = setmetatable({}, AutoAttackFX)
	self.minionService = minionService -- optional; not used yet
	self.towerService = towerService -- optional; not used yet
	self.connections = {}
	return self
end

-- Find a world position for an attacker / target combo by inspecting Workspace.
-- Players: look up character's HRP. Minions / towers: find the part with the
-- matching attribute set by their respective server-side spawners.
local function findAttackerPos(attackerType, attackerId)
	if attackerType == "player" then
		local p = Players:GetPlayerByUserId(attackerId)
		local char = p and p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			return root.Position + Vector3.new(0, 1.5, 0), root
		end
	end
	return nil
end

local function findTargetPos(targetType, targetId)
	if targetType == "player" then
		local p = Players:GetPlayerByUserId(targetId)
		local char = p and p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root then
			return root.Position, root
		end
	elseif targetType == "minion" then
		-- Scan workspace.Minions for the right id (rare lookup; acceptable cost).
		local bin = workspace:FindFirstChild("Minions")
		if bin then
			for _, model in ipairs(bin:GetChildren()) do
				if model:GetAttribute("MinionId") == targetId then
					local root = model:FindFirstChild("HumanoidRootPart")
					if root then
						return root.Position, root
					end
				end
			end
		end
	elseif targetType == "tower" then
		for _, inst in ipairs(workspace:GetDescendants()) do
			if inst:IsA("BasePart") and inst:GetAttribute("TowerId") == targetId then
				return inst.Position, inst
			end
		end
	end
	return nil
end

-- Ranged: spawn a glowing ball that tweens from attacker → target with a Trail.
local function spawnRangedFX(fromPos, targetPart, color, travelTime)
	local proj = Instance.new("Part")
	proj.Name = "AutoAttackProjectile"
	proj.Shape = Enum.PartType.Ball
	proj.Size = Vector3.new(0.8, 0.8, 0.8)
	proj.Material = Enum.Material.Neon
	proj.Color = color
	proj.Anchored = true
	proj.CanCollide = false
	proj.CanQuery = false
	proj.CanTouch = false
	proj.Position = fromPos
	proj.Parent = workspace

	-- Trail behind the projectile.
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, 0.4)
	a0.Parent = proj
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, -0.4)
	a1.Parent = proj
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.Color = ColorSequence.new(color)
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.LightEmission = 0.9
	trail.FaceCamera = true
	trail.Parent = proj

	-- A tiny PointLight for glow.
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2
	light.Range = 8
	light.Parent = proj

	-- Tween toward target — re-checks target position each step so a moving
	-- minion / player still gets hit visually. We use a Heartbeat loop with
	-- a fixed total duration to support live-tracking.
	local startTime = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startTime
		local t = math.min(elapsed / math.max(travelTime, 0.01), 1)
		local toPos
		if targetPart and targetPart.Parent then
			toPos = targetPart.Position
		else
			-- Target gone — fly out a little farther in the same direction and despawn.
			toPos = proj.Position + (proj.Position - fromPos)
		end
		proj.Position = fromPos:Lerp(toPos, t)
		if t >= 1 then
			conn:Disconnect()
			-- Tiny impact flash
			local flash = Instance.new("Part")
			flash.Anchored = true
			flash.CanCollide = false
			flash.CanQuery = false
			flash.Material = Enum.Material.Neon
			flash.Color = color
			flash.Shape = Enum.PartType.Ball
			flash.Size = Vector3.new(1.6, 1.6, 1.6)
			flash.Position = proj.Position
			flash.Parent = workspace
			TweenService:Create(
				flash,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(2.6, 2.6, 2.6), Transparency = 1 }
			):Play()
			Debris:AddItem(flash, 0.25)
			proj:Destroy()
		end
	end)
	Debris:AddItem(proj, travelTime + 0.4)
end

-- Melee: a quick wedge "slash" arc that appears at the target.
local function spawnMeleeFX(targetPart, color)
	if not targetPart or not targetPart.Parent then
		return
	end
	local slash = Instance.new("Part")
	slash.Anchored = true
	slash.CanCollide = false
	slash.CanQuery = false
	slash.CanTouch = false
	slash.Material = Enum.Material.Neon
	slash.Color = color
	slash.Size = Vector3.new(4, 0.4, 0.6)
	slash.CFrame = targetPart.CFrame * CFrame.new(0, 1, -1.5) * CFrame.Angles(0, 0, math.rad(45))
	slash.Transparency = 0
	slash.Parent = workspace

	TweenService:Create(
		slash,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			CFrame = slash.CFrame * CFrame.Angles(0, 0, math.rad(-90)),
			Transparency = 1,
		}
	):Play()
	Debris:AddItem(slash, 0.22)
end

function AutoAttackFX:_onAutoAttackFired(attackerType, attackerId, targetType, targetId, style, color, travelTime)
	color = color or Color3.fromRGB(255, 230, 200)
	style = style or "ranged"
	travelTime = travelTime or 0.15

	local fromPos = findAttackerPos(attackerType, attackerId)
	local _, targetPart = findTargetPos(targetType, targetId)

	if style == "melee" then
		spawnMeleeFX(targetPart, color)
	else
		if fromPos then
			spawnRangedFX(fromPos, targetPart, color, travelTime)
		end
	end
end

function AutoAttackFX:start()
	table.insert(
		self.connections,
		Remotes.get("AutoAttackFired").OnClientEvent:Connect(function(...)
			self:_onAutoAttackFired(...)
		end)
	)
end

function AutoAttackFX:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return AutoAttackFX
