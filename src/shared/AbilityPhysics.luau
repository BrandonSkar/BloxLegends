local AbilityPhysics = {}

-- ============================================================================
-- Mathematical & Geometric Helpers (XZ / flat space)
-- ============================================================================

function AbilityPhysics.checkCircle(point: Vector3, center: Vector3, radius: number): boolean
	return Vector3.new(point.X - center.X, 0, point.Z - center.Z).Magnitude <= radius
end

function AbilityPhysics.checkLine(point: Vector3, start: Vector3, direction: Vector3, length: number, width: number): boolean
	local flatStart = Vector3.new(start.X, 0, start.Z)
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude < 0.01 then
		return false
	end
	flatDirection = flatDirection.Unit

	local flatPoint = Vector3.new(point.X, 0, point.Z)
	local offset = flatPoint - flatStart
	local proj = offset:Dot(flatDirection)

	if proj < 0 or proj > length then
		return false
	end

	local perp = offset - flatDirection * proj
	return perp.Magnitude <= (width / 2)
end

local function clampTargetPos(origin: Vector3, targetPos: Vector3, maxRange: number): Vector3
	local offset = Vector3.new(targetPos.X - origin.X, 0, targetPos.Z - origin.Z)
	if offset.Magnitude > maxRange then
		offset = offset.Unit * maxRange
	end
	return Vector3.new(origin.X + offset.X, targetPos.Y, origin.Z + offset.Z)
end

-- ============================================================================
-- Implementation Class: Projectile
-- ============================================================================

local ProjectileSim = {}
ProjectileSim.__index = ProjectileSim

function ProjectileSim.new(ability, origin, direction, targetPos, targetType, targetId)
	local self = setmetatable({}, ProjectileSim)
	self.ability = ability
	self.type = "projectile"
	self.origin = origin

	local flatDir = Vector3.new(direction.X, 0, direction.Z)
	self.direction = flatDir.Magnitude > 0.01 and flatDir.Unit or Vector3.new(0, 0, 1)

	self.radius = ability.ProjectileRadius or 1.5
	self.speed = ability.Speed or 80
	self.maxRange = ability.Range or 60
	self.lifespan = self.maxRange / self.speed

	self.targetPos = clampTargetPos(origin, targetPos, self.maxRange)
	self.elapsed = 0
	self.alive = true
	self.hitRegister = {}

	return self
end

function ProjectileSim:update(dt)
	if not self.alive then
		return
	end
	self.elapsed = self.elapsed + dt
	if self.elapsed >= self.lifespan then
		self.alive = false
	end
end

function ProjectileSim:getStateAt(t)
	local dist = math.min(self.speed * t, self.maxRange)
	local pos = self.origin + self.direction * dist
	return {
		alive = t < self.lifespan,
		pos = pos,
		shape = "ball",
		size = Vector3.new(self.radius * 2, self.radius * 2, self.radius * 2),
		cframe = CFrame.new(pos),
	}
end

function ProjectileSim:checkHits(potentialTargets, t)
	local hits = {}
	if not self.alive and not t then
		return hits
	end
	local checkTime = t or self.elapsed
	local state = self:getStateAt(checkTime)

	for _, target in ipairs(potentialTargets) do
		if not self.hitRegister[target] then
			local char = target:IsA("Player") and target.Character or target
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and AbilityPhysics.checkCircle(root.Position, state.pos, self.radius + 2) then
				self.hitRegister[target] = true
				table.insert(hits, target)
				if not t then
					self.alive = false
				end
				break
			end
		end
	end
	return hits
end

-- ============================================================================
-- Implementation Class: Line Skillshot
-- ============================================================================

local LineSkillshotSim = {}
LineSkillshotSim.__index = LineSkillshotSim

function LineSkillshotSim.new(ability, origin, direction, targetPos, targetType, targetId)
	local self = setmetatable({}, LineSkillshotSim)
	self.ability = ability
	self.type = "line_skillshot"
	self.origin = origin

	local flatDir = Vector3.new(direction.X, 0, direction.Z)
	self.direction = flatDir.Magnitude > 0.01 and flatDir.Unit or Vector3.new(0, 0, 1)

	self.width = ability.Width or 3
	self.speed = ability.Speed or 80
	self.length = ability.Length or 40
	self.lifespan = self.length / self.speed

	self.targetPos = clampTargetPos(origin, targetPos, self.length)
	self.elapsed = 0
	self.alive = true
	self.hitRegister = {}

	return self
end

function LineSkillshotSim:update(dt)
	if not self.alive then
		return
	end
	self.elapsed = self.elapsed + dt
	if self.elapsed >= self.lifespan then
		self.alive = false
	end
end

function LineSkillshotSim:getStateAt(t)
	local dist = math.min(self.speed * t, self.length)
	local pos = self.origin + self.direction * dist
	return {
		alive = t < self.lifespan,
		pos = pos,
		shape = "block",
		size = Vector3.new(self.width, 2, 4),
		cframe = CFrame.lookAt(pos, pos + self.direction),
	}
end

function LineSkillshotSim:checkHits(potentialTargets, t)
	local hits = {}
	if not self.alive and not t then
		return hits
	end
	local checkTime = t or self.elapsed
	local state = self:getStateAt(checkTime)

	for _, target in ipairs(potentialTargets) do
		if not self.hitRegister[target] then
			local char = target:IsA("Player") and target.Character or target
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and AbilityPhysics.checkCircle(root.Position, state.pos, self.width) then
				self.hitRegister[target] = true
				table.insert(hits, target)
			end
		end
	end
	return hits
end

-- ============================================================================
-- Implementation Class: Ground AoE
-- ============================================================================

local GroundAoESim = {}
GroundAoESim.__index = GroundAoESim

function GroundAoESim.new(ability, origin, direction, targetPos, targetType, targetId)
	local self = setmetatable({}, GroundAoESim)
	self.ability = ability
	self.type = "ground_aoe"
	self.origin = origin
	self.radius = ability.Radius or 8
	self.delay = ability.ImpactDelay or 1.0
	self.lifespan = self.delay

	self.targetPos = clampTargetPos(origin, targetPos, ability.Range or 40)
	self.elapsed = 0
	self.alive = true
	self.hitRegister = {}

	return self
end

function GroundAoESim:update(dt)
	if not self.alive then
		return
	end
	self.elapsed = self.elapsed + dt
	if self.elapsed >= self.lifespan then
		self.alive = false
	end
end

function GroundAoESim:getStateAt(t)
	return {
		alive = t < self.lifespan,
		pos = self.targetPos,
		shape = "cylinder",
		size = Vector3.new(0.2, self.radius * 2, self.radius * 2),
		cframe = CFrame.new(self.targetPos) * CFrame.Angles(0, 0, math.rad(90)),
	}
end

function GroundAoESim:checkHits(potentialTargets, t)
	local hits = {}
	local checkTime = t or self.elapsed
	if checkTime >= self.delay then
		for _, target in ipairs(potentialTargets) do
			if not self.hitRegister[target] then
				local char = target:IsA("Player") and target.Character or target
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and AbilityPhysics.checkCircle(root.Position, self.targetPos, self.radius) then
					self.hitRegister[target] = true
					table.insert(hits, target)
				end
			end
		end
	end
	return hits
end

-- ============================================================================
-- Implementation Class: Volley (Repeated ticks)
-- ============================================================================

local VolleySim = {}
VolleySim.__index = VolleySim

function VolleySim.new(ability, origin, direction, targetPos, targetType, targetId)
	local self = setmetatable({}, VolleySim)
	self.ability = ability
	self.type = "volley"
	self.origin = origin
	self.radius = ability.Radius or 10
	self.ticks = ability.Ticks or 5
	self.tickInterval = ability.TickInterval or 0.5
	self.delay = ability.ImpactDelay or 0.3
	self.lifespan = self.delay + self.ticks * self.tickInterval

	self.targetPos = clampTargetPos(origin, targetPos, ability.Range or 55)
	self.elapsed = 0
	self.alive = true
	self.lastTickCount = 0

	return self
end

function VolleySim:update(dt)
	if not self.alive then
		return
	end
	self.elapsed = self.elapsed + dt
	if self.elapsed >= self.lifespan then
		self.alive = false
	end
end

function VolleySim:getStateAt(t)
	return {
		alive = t < self.lifespan,
		pos = self.targetPos,
		shape = "cylinder",
		size = Vector3.new(0.4, self.radius * 2, self.radius * 2),
		cframe = CFrame.new(self.targetPos) * CFrame.Angles(0, 0, math.rad(90)),
	}
end

function VolleySim:checkHits(potentialTargets, t)
	local checkTime = t or self.elapsed
	if checkTime >= self.delay then
		local currentTickCount = math.floor((checkTime - self.delay) / self.tickInterval) + 1
		currentTickCount = math.clamp(currentTickCount, 1, self.ticks)
		if t or currentTickCount > self.lastTickCount then
			if not t then
				self.lastTickCount = currentTickCount
			end
			local tickHits = {}
			for _, target in ipairs(potentialTargets) do
				local char = target:IsA("Player") and target.Character or target
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and AbilityPhysics.checkCircle(root.Position, self.targetPos, self.radius) then
					table.insert(tickHits, target)
				end
			end
			return tickHits
		end
	end
	return {}
end

-- ============================================================================
-- Implementation Class: Dash
-- ============================================================================

local DashSim = {}
DashSim.__index = DashSim

function DashSim.new(ability, origin, direction, targetPos, targetType, targetId)
	local self = setmetatable({}, DashSim)
	self.ability = ability
	self.type = "dash"
	self.origin = origin

	local flatDir = Vector3.new(direction.X, 0, direction.Z)
	self.direction = flatDir.Magnitude > 0.01 and flatDir.Unit or Vector3.new(0, 0, 1)
	if ability.Backward then
		self.direction = -self.direction
	end

	self.distance = ability.Distance or 30
	self.duration = ability.Duration or 0.2
	self.speed = self.distance / self.duration
	self.lifespan = self.duration
	self.elapsed = 0
	self.alive = true
	self.hitRegister = {}

	return self
end

function DashSim:update(dt)
	if not self.alive then
		return
	end
	self.elapsed = self.elapsed + dt
	if self.elapsed >= self.lifespan then
		self.alive = false
	end
end

function DashSim:getStateAt(t)
	local dist = math.min(self.speed * t, self.distance)
	local pos = self.origin + self.direction * dist
	return {
		alive = t < self.lifespan,
		pos = pos,
		shape = "block",
		size = Vector3.new(5, 5, 5),
		cframe = CFrame.lookAt(pos, pos + self.direction),
	}
end

function DashSim:checkHits(potentialTargets, t)
	local hits = {}
	if not self.alive and not t then
		return hits
	end
	local checkTime = t or self.elapsed
	local state = self:getStateAt(checkTime)

	for _, target in ipairs(potentialTargets) do
		if not self.hitRegister[target] then
			local char = target:IsA("Player") and target.Character or target
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and AbilityPhysics.checkCircle(root.Position, state.pos, 4) then
				self.hitRegister[target] = true
				table.insert(hits, target)
			end
		end
	end
	return hits
end

-- ============================================================================
-- Implementation Class: Target Cast / Leap To Target
-- ============================================================================

local TargetCastSim = {}
TargetCastSim.__index = TargetCastSim

function TargetCastSim.new(ability, origin, direction, targetPos, targetType, targetId)
	local self = setmetatable({}, TargetCastSim)
	self.ability = ability
	self.type = ability.Type or "target_cast"
	self.origin = origin
	self.targetType = targetType
	self.targetId = targetId
	self.targetPos = targetPos -- fallback
	self.lifespan = 0.25
	self.elapsed = 0
	self.alive = true

	return self
end

function TargetCastSim:update(dt)
	if not self.alive then
		return
	end
	self.elapsed = self.elapsed + dt
	if self.elapsed >= self.lifespan then
		self.alive = false
	end
end

function TargetCastSim:getStateAt(t)
	return {
		alive = t < self.lifespan,
		pos = self.targetPos,
		shape = "beam",
		size = Vector3.new(0.25, 0.25, 10),
		cframe = CFrame.new(self.targetPos),
	}
end

function TargetCastSim:checkHits(potentialTargets, t)
	local hits = {}
	if self.targetId then
		for _, target in ipairs(potentialTargets) do
			local id = target:IsA("Player") and target.UserId or target:GetAttribute("MinionId")
			if id == self.targetId then
				table.insert(hits, target)
				break
			end
		end
	end
	return hits
end

-- ============================================================================
-- Implementation Class: Self Cast (Heal/Buff)
-- ============================================================================

local SelfCastSim = {}
SelfCastSim.__index = SelfCastSim

function SelfCastSim.new(ability, origin, direction, targetPos, targetType, targetId)
	local self = setmetatable({}, SelfCastSim)
	self.ability = ability
	self.type = "self_cast"
	self.origin = origin
	self.targetPos = origin
	self.lifespan = 0.1
	self.elapsed = 0
	self.alive = true

	return self
end

function SelfCastSim:update(dt)
	if not self.alive then
		return
	end
	self.elapsed = self.elapsed + dt
	if self.elapsed >= self.lifespan then
		self.alive = false
	end
end

function SelfCastSim:getStateAt(t)
	return {
		alive = t < self.lifespan,
		pos = self.origin,
		shape = "cylinder",
		size = Vector3.new(0.2, 8, 8),
		cframe = CFrame.new(self.origin) * CFrame.Angles(0, 0, math.rad(90)),
	}
end

function SelfCastSim:checkHits(potentialTargets, t)
	-- Self buffs instantly hit the caster
	return { Players.LocalPlayer }
end

-- ============================================================================
-- Unified Dispatch Factory mapping ability Types to subclass instances
-- ============================================================================

local classes = {
	projectile = ProjectileSim,
	line_skillshot = LineSkillshotSim,
	ground_aoe = GroundAoESim,
	volley = VolleySim,
	dash = DashSim,
	target_cast = TargetCastSim,
	leap_to_target = TargetCastSim,
	self_buff = SelfCastSim,
	self_heal = SelfCastSim,
	combo = SelfCastSim,
}

function AbilityPhysics.new(ability: table, origin: Vector3, direction: Vector3, targetPos: Vector3, targetType: string?, targetId: number?)
	local abilityType = ability.Type or "projectile"
	local class = classes[abilityType] or ProjectileSim
	return class.new(ability, origin, direction, targetPos, targetType, targetId)
end

return AbilityPhysics
