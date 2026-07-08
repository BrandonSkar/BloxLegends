local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Champions = require(Shared:WaitForChild("Champions"))
local Config = require(Shared:WaitForChild("Config"))
local Runes = require(Shared:WaitForChild("Runes"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AbilityHandler = {}
AbilityHandler.__index = AbilityHandler

-- Top-down XZ distance. Ability hit detection ignores height so a chest-high
-- projectile still clips a short minion (root ~1.8 above ground). Without this
-- a width-2 line skillshot like Piercing Arrow would always whiff on minions.
local function flatDist(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function makeVisualPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

-- ===== VFX helpers =====

-- A PointLight that brightens the area around a part for that "glow" feel.
local function attachLight(part, color, brightness, range)
	local light = Instance.new("PointLight")
	light.Color = color or part.Color
	light.Brightness = brightness or 2
	light.Range = range or 12
	light.Shadows = false
	light.Parent = part
	return light
end

-- A trailing streak behind a moving part. Returns the Trail instance.
local function attachTrail(part, color, lifetime, width0, width1)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, part.Size.Z / 2)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, -part.Size.Z / 2)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = lifetime or 0.35
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, width0 or 1),
		NumberSequenceKeypoint.new(1, width1 or 0),
	})
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Parent = part
	return trail
end

-- One-shot ParticleEmitter burst at a position (no parent visible — uses a
-- hidden helper part). Emits N particles, then cleans up shortly after.
local function emitBurstAt(pos, color, count, size)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.Position = pos
	p.Parent = workspace

	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(color)
	em.LightEmission = 1
	em.Lifetime = NumberRange.new(0.4, 0.7)
	em.Speed = NumberRange.new(8, 14)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-200, 200)
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size or 1.0),
		NumberSequenceKeypoint.new(1, 0),
	})
	em.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	em.Rate = 0
	em.Parent = p
	em:Emit(count or 20)
	Debris:AddItem(p, 1.5)
end

-- Expanding ring at a position — looks like an impact shockwave.
local function expandingRing(pos, color, finalRadius, duration)
	local ring = makeVisualPart({
		Name = "ImpactRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 1, 1),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.1,
	})
	ring.Parent = workspace
	local goal = { Size = Vector3.new(0.4, finalRadius * 2, finalRadius * 2), Transparency = 1 }
	game:GetService("TweenService"):Create(ring, TweenInfo.new(duration or 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	Debris:AddItem(ring, (duration or 0.4) + 0.1)
end

function AbilityHandler.new(combatService, minionService, matchController)
	local self = setmetatable({}, AbilityHandler)
	self.combatService = combatService
	self.minionService = minionService
	self.matchController = matchController
	self.towerService = nil
	Remotes.get("CastAbility").OnServerEvent:Connect(function(player, slot, _origin, direction, targetPos, targetType, targetId)
		self:_handleCast(player, slot, direction, targetPos, targetType, targetId)
	end)
	return self
end

function AbilityHandler:setTowerService(svc)
	self.towerService = svc
end

function AbilityHandler:setRecallService(svc)
	self.recallService = svc
end

-- ============================================================================
-- Status-effect application helpers
-- ============================================================================

local function applyStatusOnHit(self, targetPlayer, status, casterPos, attackerPlayer)
	if not status then
		return
	end
	local t = status.type
	if t == "slow" then
		self.combatService:applySlow(targetPlayer, status.magnitude, status.duration)
	elseif t == "stun" then
		self.combatService:applyStun(targetPlayer, status.duration)
	elseif t == "root" then
		self.combatService:applyRoot(targetPlayer, status.duration)
	elseif t == "dot" then
		-- Pass the caster through as the DoT source so a burn that finishes a
		-- champion credits the kill (and cancels their recall correctly).
		self.combatService:applyDoT(targetPlayer, status.damagePerTick, status.interval, status.ticks, attackerPlayer)
	elseif t == "knockup" then
		self.combatService:applyKnockup(targetPlayer, status.height, status.duration)
	elseif t == "knockback" and casterPos then
		self.combatService:applyKnockback(targetPlayer, casterPos, status.distance)
	elseif t == "pull" and casterPos then
		self.combatService:applyPull(targetPlayer, casterPos, status.distance)
	end
end

-- Mirror of applyStatusOnHit for minion targets. Displacement CC affects the
-- practice dummy + pit bots (no-op on lane/jungle minions so their pathing is
-- undisturbed); stun/slow/root land on pit bots only, so every kind of crowd
-- control can be practiced on something that moves. DoT ticks on any minion.
local function applyStatusToMinion(self, entry, status, casterPos, attackerPlayer)
	if not status or not entry then
		return
	end
	local t = status.type
	if t == "knockup" then
		self.minionService:applyKnockupToMinion(entry, status.height, status.duration)
	elseif t == "knockback" and casterPos then
		self.minionService:applyKnockbackToMinion(entry, casterPos, status.distance)
	elseif t == "pull" and casterPos then
		self.minionService:applyPullToMinion(entry, casterPos, status.distance)
	elseif t == "stun" then
		self.minionService:applyStunToMinion(entry, status.duration)
	elseif t == "slow" then
		self.minionService:applySlowToMinion(entry, status.magnitude, status.duration)
	elseif t == "root" then
		self.minionService:applyRootToMinion(entry, status.duration)
	elseif t == "dot" then
		self.minionService:applyDoTToMinion(entry, status.damagePerTick, status.interval, status.ticks, attackerPlayer)
	end
end

-- ============================================================================
-- AoE damage helper (existing pattern, with on-hit status support)
-- ============================================================================

local function applyAreaDamage(self, attackerPlayer, attackerTeam, center, radius, damage, statusOnHit, healAlliesAmount, shieldAlliesAmount, shieldAlliesDuration)
	-- Support items amplify the heals / shields the caster lands on allies.
	if (healAlliesAmount or shieldAlliesAmount) and attackerPlayer then
		local ce = self.combatService:getEntry(attackerPlayer)
		local hsp = (ce and ce.itemBonuses and ce.itemBonuses.HealShieldPowerPct) or 0
		if hsp > 0 then
			local mult = 1 + hsp / 100
			if healAlliesAmount then
				healAlliesAmount = healAlliesAmount * mult
			end
			if shieldAlliesAmount then
				shieldAlliesAmount = shieldAlliesAmount * mult
			end
		end
	end
	-- Enemy minions
	for _, entry in pairs(self.minionService:allMinions()) do
		if entry.alive and entry.team ~= attackerTeam then
			local d = flatDist(entry.root.Position, center)
			if d <= radius then
				self.minionService:applyDamage(entry, damage, attackerPlayer)
				applyStatusToMinion(self, entry, statusOnHit, center, attackerPlayer)
			end
		end
	end
	-- Champions: damage enemies, optionally heal/shield allies
	for _, player in ipairs(Players:GetPlayers()) do
		local team = self.matchController:teamOf(player)
		if team and self.combatService:isAlive(player) then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and flatDist(root.Position, center) <= radius then
				if team ~= attackerTeam then
					if damage and damage > 0 then
						self.combatService:damagePlayer(player, damage, attackerPlayer)
					end
					applyStatusOnHit(self, player, statusOnHit, center, attackerPlayer)
				else
					if healAlliesAmount and healAlliesAmount > 0 then
						self.combatService:healPlayer(player, healAlliesAmount)
					end
					if shieldAlliesAmount and shieldAlliesAmount > 0 then
						self.combatService:applyShield(player, shieldAlliesAmount, shieldAlliesDuration or 4)
					end
				end
			end
		end
	end
	-- Towers
	if self.towerService then
		for _, tower in pairs(self.towerService:allTowers()) do
			if tower.alive and tower.team ~= attackerTeam then
				if flatDist(tower.root.Position, center) <= radius then
					self.towerService:applyDamage(tower, damage, attackerPlayer)
				end
			end
		end
	end
end

-- ============================================================================
-- Projectile (single target)
-- ============================================================================

local function fireProjectile(self, attackerPlayer, attackerTeam, ability, origin, direction)
	local radius = ability.ProjectileRadius or 1.5
	local color = ability.Color or Color3.fromRGB(200, 200, 200)
	local part = makeVisualPart({
		Name = "Projectile",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(radius * 2, radius * 2, radius * 2),
		Color = color,
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(origin + Vector3.new(0, 2, 0)),
	})
	part.Parent = workspace
	attachLight(part, color, 3, 14)
	attachTrail(part, color, 0.35, radius * 1.5, 0)

	local speed = ability.Speed or 80
	local maxRange = ability.Range or 60
	local hitRadius = radius + 2
	local traveled = 0
	local alive = true
	local statusOnHit = ability.StatusOnHit

	local function tryHitPlayer(p)
		if not (self.matchController:teamOf(p) and self.matchController:teamOf(p) ~= attackerTeam and self.combatService:isAlive(p)) then
			return false
		end
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and flatDist(root.Position, part.Position) <= hitRadius then
			self.combatService:damagePlayer(p, ability.Damage, attackerPlayer)
			-- Caster position for knockback/pull origin.
			local casterChar = attackerPlayer.Character
			local casterRoot = casterChar and casterChar:FindFirstChild("HumanoidRootPart")
			local casterPos = casterRoot and casterRoot.Position or origin
			applyStatusOnHit(self, p, statusOnHit, casterPos, attackerPlayer)
			return true
		end
		return false
	end

	local function impactFX(pos)
		emitBurstAt(pos, color, 16, radius)
		expandingRing(pos, color, radius * 3, 0.3)
	end

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not alive or not part.Parent then
			conn:Disconnect()
			return
		end
		local step = speed * dt
		traveled = traveled + step
		part.CFrame = part.CFrame + direction * step

		for _, entry in pairs(self.minionService:allMinions()) do
			if entry.alive and entry.team ~= attackerTeam then
				if flatDist(entry.root.Position, part.Position) <= hitRadius then
					self.minionService:applyDamage(entry, ability.Damage, attackerPlayer)
					applyStatusToMinion(self, entry, statusOnHit, part.Position, attackerPlayer)
					alive = false
					conn:Disconnect()
					impactFX(part.Position)
					part:Destroy()
					return
				end
			end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= attackerPlayer and tryHitPlayer(p) then
				alive = false
				conn:Disconnect()
				impactFX(part.Position)
				part:Destroy()
				return
			end
		end
		if self.towerService then
			for _, tower in pairs(self.towerService:allTowers()) do
				if tower.alive and tower.team ~= attackerTeam then
					if flatDist(tower.root.Position, part.Position) <= hitRadius then
						self.towerService:applyDamage(tower, ability.Damage, attackerPlayer)
						alive = false
						conn:Disconnect()
						impactFX(part.Position)
						part:Destroy()
						return
					end
				end
			end
		end

		if traveled >= maxRange then
			alive = false
			conn:Disconnect()
			part:Destroy()
		end
	end)
	Debris:AddItem(part, maxRange / speed + 2)
end

-- ============================================================================
-- Line skillshot (pierces, hits all enemies in a swept rectangle)
-- ============================================================================

local function fireLineSkillshot(self, attackerPlayer, attackerTeam, ability, origin, direction)
	local length = ability.Length or 40
	local width = ability.Width or 3
	local speed = ability.Speed or 80
	local statusOnHit = ability.StatusOnHit

	local color = ability.Color or Color3.fromRGB(220, 220, 220)
	-- Visual: a flat box stretched along the travel direction, shrinks each tick.
	local part = makeVisualPart({
		Name = "LineSkillshot",
		Size = Vector3.new(width, 2, 6),
		Material = Enum.Material.Neon,
		Color = color,
		Transparency = 0.2,
		CFrame = CFrame.lookAt(origin + Vector3.new(0, 1.5, 0), origin + direction),
	})
	part.Parent = workspace
	attachLight(part, color, 3, 12)
	attachTrail(part, color, 0.45, width * 1.5, 0)

	local traveled = 0
	local hitMinions = {}
	local hitChampions = {}
	local hitTowers = {}

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not part.Parent then
			conn:Disconnect()
			return
		end
		local step = speed * dt
		traveled = traveled + step
		part.CFrame = part.CFrame + direction * step

		local pos = part.Position
		-- Minions
		for id, entry in pairs(self.minionService:allMinions()) do
			if entry.alive and entry.team ~= attackerTeam and not hitMinions[id] then
				if flatDist(entry.root.Position, pos) <= width then
					self.minionService:applyDamage(entry, ability.Damage, attackerPlayer)
					applyStatusToMinion(self, entry, statusOnHit, origin, attackerPlayer)
					hitMinions[id] = true
				end
			end
		end
		-- Champions (pierce)
		for _, p in ipairs(Players:GetPlayers()) do
			local team = self.matchController:teamOf(p)
			if team and team ~= attackerTeam and not hitChampions[p.UserId] and self.combatService:isAlive(p) then
				local char = p.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root and flatDist(root.Position, pos) <= width then
					self.combatService:damagePlayer(p, ability.Damage, attackerPlayer)
					applyStatusOnHit(self, p, statusOnHit, origin, attackerPlayer)
					hitChampions[p.UserId] = true
				end
			end
		end
		-- Towers
		if self.towerService then
			for _, tower in pairs(self.towerService:allTowers()) do
				if tower.alive and tower.team ~= attackerTeam and not hitTowers[tower.id] then
					if flatDist(tower.root.Position, pos) <= width then
						self.towerService:applyDamage(tower, ability.Damage, attackerPlayer)
						hitTowers[tower.id] = true
					end
				end
			end
		end

		if traveled >= length then
			conn:Disconnect()
			part:Destroy()
		end
	end)
	Debris:AddItem(part, length / speed + 1)
end

-- ============================================================================
-- Ground AoE (existing pattern with status + heal-allies extension)
-- ============================================================================

local function groundAoE(self, attackerPlayer, attackerTeam, ability, targetPos)
	local radius = ability.Radius or 8
	local delay = ability.ImpactDelay or 1.0

	local marker = makeVisualPart({
		Name = "AoEMarker",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		CFrame = CFrame.new(targetPos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = ability.Color or Color3.fromRGB(180, 90, 70),
		Transparency = 0.4,
	})
	marker.Parent = workspace

	task.delay(delay, function()
		if marker.Parent then
			marker:Destroy()
		end
		local color = ability.Color or Color3.fromRGB(220, 110, 80)
		applyAreaDamage(
			self, attackerPlayer, attackerTeam, targetPos, radius,
			ability.Damage or 0, ability.StatusOnHit,
			ability.HealAlliesAmount, ability.ShieldAlliesAmount, ability.ShieldAlliesDuration
		)
		-- Punchy impact: bright flash + expanding ring + particle burst.
		local flash = makeVisualPart({
			Name = "AoEImpact",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, radius * 2, radius * 2),
			CFrame = CFrame.new(targetPos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = Enum.Material.Neon,
			Transparency = 0.05,
		})
		flash.Parent = workspace
		game:GetService("TweenService"):Create(
			flash,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1, Size = Vector3.new(0.6, radius * 2.4, radius * 2.4) }
		):Play()
		Debris:AddItem(flash, 0.45)
		expandingRing(targetPos, color, radius * 1.4, 0.5)
		emitBurstAt(targetPos + Vector3.new(0, 1, 0), color, 30, 1.4)
	end)
end

-- ============================================================================
-- Volley (repeating ground AoE ticks)
-- ============================================================================

local function volley(self, attackerPlayer, attackerTeam, ability, targetPos)
	local radius = ability.Radius or 10
	local ticks = ability.Ticks or 5
	local tickInterval = ability.TickInterval or 0.5
	local startDelay = ability.ImpactDelay or 0.3

	-- Persistent marker
	local marker = makeVisualPart({
		Name = "VolleyMarker",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, radius * 2, radius * 2),
		CFrame = CFrame.new(targetPos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = ability.Color or Color3.fromRGB(220, 200, 140),
		Material = Enum.Material.Neon,
		Transparency = 0.5,
	})
	marker.Parent = workspace
	Debris:AddItem(marker, startDelay + tickInterval * ticks + 0.5)

	task.spawn(function()
		task.wait(startDelay)
		for _ = 1, ticks do
			applyAreaDamage(self, attackerPlayer, attackerTeam, targetPos, radius, ability.Damage or 0, ability.StatusOnHit, nil)
			task.wait(tickInterval)
		end
	end)
end

-- ============================================================================
-- Target-cast (single target, optionally with execute bonus damage)
-- ============================================================================

local function targetCast(self, attackerPlayer, attackerTeam, ability, targetType, targetId, originPos)
	local targetRoot, victimPlayer, minionEntry
	if targetType == "player" then
		local victim = Players:GetPlayerByUserId(targetId)
		if not victim or victim == attackerPlayer then
			return false
		end
		local victimTeam = self.matchController:teamOf(victim)
		if victimTeam == attackerTeam then
			return false
		end
		if not self.combatService:isAlive(victim) then
			return false
		end
		local char = victim.Character
		targetRoot = char and char:FindFirstChild("HumanoidRootPart")
		if not targetRoot then
			return false
		end
		victimPlayer = victim
	elseif targetType == "minion" then
		minionEntry = self.minionService:getMinion(targetId)
		if not minionEntry or not minionEntry.alive or minionEntry.team == attackerTeam then
			return false
		end
		targetRoot = minionEntry.root
	else
		return false
	end
	-- Range check
	local range = ability.Range or 25
	if (targetRoot.Position - originPos).Magnitude > range then
		return false
	end
	-- Damage (with Execute bonus if applicable — players only).
	local damage = ability.Damage or 0
	if victimPlayer and ability.ExecuteThresholdPct then
		local victimEntry = self.combatService:getEntry(victimPlayer)
		if victimEntry and (victimEntry.hp / victimEntry.maxHP) * 100 <= ability.ExecuteThresholdPct then
			damage = damage + (ability.ExecuteBonusDamage or 0)
		end
	end
	if victimPlayer then
		if damage > 0 then
			self.combatService:damagePlayer(victimPlayer, damage, attackerPlayer)
		end
		applyStatusOnHit(self, victimPlayer, ability.StatusOnHit, originPos, attackerPlayer)
	else
		if damage > 0 then
			self.minionService:applyDamage(minionEntry, damage, attackerPlayer)
		end
		applyStatusToMinion(self, minionEntry, ability.StatusOnHit, originPos, attackerPlayer)
	end
	-- Visual: brief connecting beam between caster and target.
	local from = originPos + Vector3.new(0, 2, 0)
	local to = targetRoot.Position
	local diff = to - from
	local mid = (from + to) / 2
	local beam = makeVisualPart({
		Name = "TargetCastBeam",
		Size = Vector3.new(0.4, 0.4, diff.Magnitude),
		CFrame = CFrame.lookAt(mid, to),
		Color = ability.Color or Color3.fromRGB(220, 220, 220),
		Material = Enum.Material.Neon,
	})
	beam.Parent = workspace
	Debris:AddItem(beam, 0.25)
	return true
end

-- ============================================================================
-- Leap to target (gap closer)
-- ============================================================================

local function leapToTarget(self, attackerPlayer, attackerTeam, ability, targetType, targetId, originPos)
	if targetType ~= "player" then
		return false
	end
	local victim = Players:GetPlayerByUserId(targetId)
	if not victim or victim == attackerPlayer then
		return false
	end
	local victimTeam = self.matchController:teamOf(victim)
	if victimTeam == attackerTeam then
		return false
	end
	if not self.combatService:isAlive(victim) then
		return false
	end
	local victimChar = victim.Character
	local victimRoot = victimChar and victimChar:FindFirstChild("HumanoidRootPart")
	if not victimRoot then
		return false
	end
	local range = ability.Range or 30
	if (victimRoot.Position - originPos).Magnitude > range then
		return false
	end
	-- Teleport the caster to a position next to the victim.
	local casterChar = attackerPlayer.Character
	local casterRoot = casterChar and casterChar:FindFirstChild("HumanoidRootPart")
	if not casterRoot then
		return false
	end
	local fromVictim = (casterRoot.Position - victimRoot.Position)
	fromVictim = Vector3.new(fromVictim.X, 0, fromVictim.Z)
	if fromVictim.Magnitude < 0.01 then
		fromVictim = Vector3.new(1, 0, 0)
	end
	local landPos = victimRoot.Position + fromVictim.Unit * 4
	casterRoot.CFrame = CFrame.new(landPos + Vector3.new(0, 2, 0))
	-- Then damage
	if ability.Damage and ability.Damage > 0 then
		self.combatService:damagePlayer(victim, ability.Damage, attackerPlayer)
	end
	applyStatusOnHit(self, victim, ability.StatusOnHit, casterRoot.Position, attackerPlayer)
	return true
end

-- ============================================================================
-- Dash (extended: optional invuln + knockback-on-touch)
-- ============================================================================

local function dash(self, player, ability, direction)
	if typeof(direction) ~= "Vector3" then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	local dir = flat.Unit
	if ability.Backward then
		dir = -dir
	end
	local distance = ability.Distance or 30
	local duration = ability.Duration or 0.2
	local speed = distance / duration
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	-- Optional invuln during dash
	if ability.InvulnDuration then
		self.combatService:applyDamageReduction(player, 0, ability.InvulnDuration)
	end
	-- Track enemies touched along the dash for knockback abilities.
	local pushedSet = {}
	local attackerTeam = self.matchController:teamOf(player)
	local elapsed = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed = elapsed + dt
		if elapsed >= duration or not hrp.Parent then
			conn:Disconnect()
			return
		end
		local v = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(dir.X * speed, v.Y, dir.Z * speed)
		-- Knockback any enemies the dash sweeps near
		if ability.KnockbackOnHit then
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player and not pushedSet[p.UserId] then
					local pTeam = self.matchController:teamOf(p)
					if pTeam and pTeam ~= attackerTeam and self.combatService:isAlive(p) then
						local pChar = p.Character
						local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
						if pRoot and flatDist(pRoot.Position, hrp.Position) <= 4 then
							pushedSet[p.UserId] = true
							if ability.KnockbackDamage then
								self.combatService:damagePlayer(p, ability.KnockbackDamage, player)
							end
							-- applyKnockback also stuns briefly. Skip it for pure
							-- gap-closers (KnockbackOnHit = 0) so the dash only
							-- deals damage without incidental CC.
							if ability.KnockbackOnHit > 0 then
								self.combatService:applyKnockback(p, hrp.Position, ability.KnockbackOnHit)
							end
						end
					end
				end
			end
			-- Practice dummies + pit bots in the sweep (lane/jungle minions are
			-- not displaced).
			for _, mEntry in pairs(self.minionService:allMinions()) do
				local key = "m" .. tostring(mEntry.id)
				if mEntry.alive and (mEntry.isDummy or mEntry.isPitBot) and not pushedSet[key] then
					if flatDist(mEntry.root.Position, hrp.Position) <= 4 then
						pushedSet[key] = true
						if ability.KnockbackDamage then
							self.minionService:applyDamage(mEntry, ability.KnockbackDamage, player)
						end
						if ability.KnockbackOnHit > 0 then
							self.minionService:applyKnockbackToMinion(mEntry, hrp.Position, ability.KnockbackOnHit)
						end
					end
				end
			end
		end
	end)
end

-- ============================================================================
-- Self buffs (shield, invisibility, damage_reduction, attack_buff, hot)
-- ============================================================================

local function selfBuff(self, player, ability)
	local sub = ability.SubType
	if sub == "shield" then
		self.combatService:applyShield(player, ability.ShieldAmount or 100, ability.Duration or 4)
	elseif sub == "invisibility" then
		self.combatService:applyInvisibility(player, ability.Duration or 1.5)
	elseif sub == "damage_reduction" then
		self.combatService:applyDamageReduction(player, ability.Multiplier or 0.5, ability.Duration or 4)
	elseif sub == "attack_buff" then
		self.combatService:setAttackBuff(player, ability.BonusDamageMult or 2, ability.Duration or 8)
	elseif sub == "hot" then
		self.combatService:applyHoT(player, ability.HealPerTick or 30, ability.Interval or 1, ability.Ticks or 5)
	elseif ability.BuffStat == "WalkSpeed" then
		-- Legacy: old WalkSpeed self_buff (Sprint summoner)
		self.combatService:applySpeedBuff(player, ability.BuffMultiplier, ability.BuffDuration)
	end
end

-- ============================================================================
-- Cast dispatcher
-- ============================================================================

function AbilityHandler:_handleCast(player, slot, direction, targetPos, targetType, targetId)
	if typeof(slot) ~= "string" then
		return
	end
	if self.isInMatch and not self.isInMatch(player) then
		return
	end
	local entry = self.combatService:getEntry(player)
	if not entry or not entry.alive then
		return
	end
	-- Locked players (champion select, stun, etc.) can't cast.
	if self.combatService:isLocked(player) then
		return
	end
	if not self.combatService:isReady(player, slot) then
		return
	end
	local team = self.matchController:teamOf(player)
	if not team then
		return
	end

	-- Champion lookup is per-player now.
	local championKey = entry.championKey or "Pyromancer"
	local champ = Champions.Roster[championKey]
	local ability = champ and champ.Abilities[slot]
	if slot == "Space" then
		local spellKey = entry.summonerSpell or Runes.DefaultSummonerSpell
		ability = Runes.SummonerSpells[spellKey]
	end
	if not ability then
		return
	end

	-- Ability-power scaling on Damage (runes + items + timed jungle buffs, all
	-- summed by CombatService), plus champion-level damage growth.
	local apBonus = self.combatService:statBonus(player, "AbilityPowerPct") / 100
	local levelMult = Config.levelDamageMult(entry.level or 1)
	local scaledAbility = ability
	if ability.Damage then
		scaledAbility = setmetatable({ Damage = ability.Damage * (1 + apBonus) * levelMult }, { __index = ability })
	end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local origin = root.Position

	local ok = false
	local t = ability.Type
	if t == "projectile" then
		if typeof(direction) ~= "Vector3" then
			return
		end
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude < 0.01 then
			return
		end
		fireProjectile(self, player, team, scaledAbility, origin, flat.Unit)
		ok = true
	elseif t == "line_skillshot" then
		if typeof(direction) ~= "Vector3" then
			return
		end
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude < 0.01 then
			return
		end
		fireLineSkillshot(self, player, team, scaledAbility, origin, flat.Unit)
		ok = true
	elseif t == "ground_aoe" then
		if typeof(targetPos) ~= "Vector3" then
			return
		end
		local offset = Vector3.new(targetPos.X - origin.X, 0, targetPos.Z - origin.Z)
		if offset.Magnitude > ability.Range then
			offset = offset.Unit * ability.Range
		end
		local clamped = Vector3.new(origin.X + offset.X, 0, origin.Z + offset.Z)
		groundAoE(self, player, team, scaledAbility, clamped)
		ok = true
	elseif t == "volley" then
		if typeof(targetPos) ~= "Vector3" then
			return
		end
		local offset = Vector3.new(targetPos.X - origin.X, 0, targetPos.Z - origin.Z)
		if offset.Magnitude > ability.Range then
			offset = offset.Unit * ability.Range
		end
		local clamped = Vector3.new(origin.X + offset.X, 0, origin.Z + offset.Z)
		volley(self, player, team, scaledAbility, clamped)
		ok = true
	elseif t == "target_cast" then
		if not targetType or not targetId then
			return
		end
		ok = targetCast(self, player, team, scaledAbility, targetType, targetId, origin)
		if not ok then
			return
		end
	elseif t == "leap_to_target" then
		if not targetType or not targetId then
			return
		end
		ok = leapToTarget(self, player, team, scaledAbility, targetType, targetId, origin)
		if not ok then
			return
		end
	elseif t == "dash" then
		dash(self, player, ability, direction)
		ok = true
	elseif t == "self_buff" then
		selfBuff(self, player, ability)
		ok = true
	elseif t == "self_heal" then
		local heal = ability.HealAmount or 0
		local hsp = (entry.itemBonuses and entry.itemBonuses.HealShieldPowerPct) or 0
		self.combatService:healPlayer(player, heal * (1 + hsp / 100))
		ok = true
	elseif t == "combo" then
		-- Summoner spell combo (existing): heal + speed
		if ability.HealAmount then
			self.combatService:healPlayer(player, ability.HealAmount)
		end
		if ability.BuffStat == "WalkSpeed" and ability.BuffMultiplier and ability.BuffDuration then
			self.combatService:applySpeedBuff(player, ability.BuffMultiplier, ability.BuffDuration)
		end
		ok = true
	end

	if ok then
		self.combatService:startCooldown(player, slot, ability.Cooldown or 0)
		-- Successfully casting any ability cancels a recall channel.
		if self.recallService then
			self.recallService:onAbilityCast(player)
		end
	end
end

return AbilityHandler
