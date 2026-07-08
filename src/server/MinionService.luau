local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local MinionService = {}
MinionService.__index = MinionService

local nextMinionId = 1
local BIN_NAME = "Minions"

local function getBin()
	local bin = workspace:FindFirstChild(BIN_NAME)
	if not bin then
		bin = Instance.new("Folder")
		bin.Name = BIN_NAME
		bin.Parent = workspace
	end
	return bin
end

function MinionService.new(matchController, combatService)
	local self = setmetatable({}, MinionService)
	self.matchController = matchController
	self.combatService = combatService
	self.towerService = nil
	self.practiceService = nil -- wired after construction
	self.minions = {}
	self.connections = {}
	return self
end

function MinionService:setTowerService(svc)
	self.towerService = svc
end

function MinionService:setPracticeService(svc)
	self.practiceService = svc
end

function MinionService:setScoreService(svc)
	self.scoreService = svc
end

function MinionService:setJungleService(svc)
	self.jungleService = svc
end

function MinionService:getMinion(id)
	return self.minions[id]
end

function MinionService:allMinions()
	return self.minions
end

-- Scale a color toward black (m<1) or white-clamped (m>1) for shading accents.
local function shade(color, m)
	return Color3.new(
		math.clamp(color.R * m, 0, 1),
		math.clamp(color.G * m, 0, 1),
		math.clamp(color.B * m, 0, 1)
	)
end

-- Bright team-colored glow for eyes / crest / caster orbs.
local TEAM_GLOW = {
	Blue = Color3.fromRGB(150, 220, 255),
	Red = Color3.fromRGB(255, 150, 150),
}

-- Add an unanchored cosmetic part welded rigidly to the (anchored, code-moved)
-- root, placed at `localCFrame` in the root's local space. Because the root is
-- anchored and we drive it by CFrame, the weld carries the cosmetics along for
-- free — so _tick still only has to move the root (+ head), never these.
local function addWelded(model, root, name, localCFrame, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	p.CFrame = root.CFrame * localCFrame
	p.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	return p
end

-- Build the visible minion model: a torso + head + name/HP billboard.
-- `typeData` carries per-type Size and ColorMul so the three minion classes
-- look visually distinct (small ranged, medium melee, big cannon).
local function buildMinionModel(team, typeKey, typeData, spawnPos)
	local teamColor = Config.Teams[team].Color
	local mul = typeData.ColorMul or 1
	local r = math.clamp(teamColor.R * mul, 0, 1)
	local g = math.clamp(teamColor.G * mul, 0, 1)
	local b = math.clamp(teamColor.B * mul, 0, 1)
	local bodyColor = Color3.new(r, g, b)
	local size = typeData.Size or Vector3.new(2.4, 3.6, 2)

	local model = Instance.new("Model")
	model.Name = team .. typeKey .. "Minion"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.CanCollide = true -- anchored so they can't be pushed; CanCollide on so players bump them
	root.CanQuery = true
	root.CanTouch = false
	root.Size = size
	root.CFrame = CFrame.new(spawnPos + Vector3.new(0, size.Y / 2, 0))
	root.Color = bodyColor
	root.Material = Enum.Material.SmoothPlastic
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model

	local headD = size.X * 0.62
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Anchored = true
	head.CanCollide = false
	head.CanQuery = true
	head.Size = Vector3.new(headD, headD, headD)
	head.CFrame = root.CFrame + Vector3.new(0, size.Y / 2 + head.Size.Y / 2, 0)
	head.Color = shade(bodyColor, 0.82)
	head.Material = Enum.Material.SmoothPlastic
	head.Parent = model

	model.PrimaryPart = root

	-- ===== Cosmetic detailing (welded to root; front is the root's -Z) =====
	local sx, sy, sz = size.X, size.Y, size.Z
	local darkColor = shade(bodyColor, 0.6)
	local glow = TEAM_GLOW[team] or Color3.fromRGB(220, 220, 220)
	local headCenterY = sy / 2 + headD / 2 -- matches the head's follow offset

	-- Glowing eyes on the head's front face.
	local eyeD = headD * 0.24
	for _, sgn in ipairs({ -1, 1 }) do
		addWelded(model, root, "Eye", CFrame.new(sgn * headD * 0.23, headCenterY + headD * 0.05, -headD * 0.42), {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(eyeD, eyeD, eyeD),
			Color = glow,
			Material = Enum.Material.Neon,
		})
	end

	-- Team-colored crest fin on top of the head — strong team read from afar.
	addWelded(model, root, "Crest", CFrame.new(0, headCenterY + headD * 0.55, 0), {
		Size = Vector3.new(headD * 0.14, headD * 0.5, headD * 0.8),
		Color = glow,
		Material = Enum.Material.Neon,
	})

	-- Shoulder pads for a chunkier silhouette.
	for _, sgn in ipairs({ -1, 1 }) do
		addWelded(model, root, "Shoulder", CFrame.new(sgn * (sx * 0.58), sy * 0.28, 0), {
			Size = Vector3.new(sx * 0.3, sy * 0.34, sz * 0.8),
			Color = darkColor,
		})
	end

	-- Per-class flair.
	if typeKey == "Cannon" then
		-- Stubby barrel jutting forward.
		addWelded(model, root, "Barrel", CFrame.new(0, sy * 0.08, -(sz / 2 + sx * 0.35)) * CFrame.Angles(0, math.rad(90), 0), {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(sx * 0.8, sx * 0.5, sx * 0.5),
			Color = shade(bodyColor, 0.45),
			Material = Enum.Material.Metal,
		})
	elseif typeKey == "Ranged" then
		-- Floating focus orb in front of the chest.
		addWelded(model, root, "Orb", CFrame.new(0, sy * 0.12, -(sz / 2 + sx * 0.32)), {
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(sx * 0.45, sx * 0.45, sx * 0.45),
			Color = glow,
			Material = Enum.Material.Neon,
		})
	else
		-- Melee: a pair of forward-swept horns on the head.
		for _, sgn in ipairs({ -1, 1 }) do
			addWelded(model, root, "Horn", CFrame.new(sgn * headD * 0.3, headCenterY + headD * 0.32, -headD * 0.18) * CFrame.Angles(math.rad(-32), 0, 0), {
				Size = Vector3.new(headD * 0.12, headD * 0.5, headD * 0.12),
				Color = darkColor,
			})
		end
	end

	-- HP billboard above the head.
	local gui = Instance.new("BillboardGui")
	gui.Name = "HPBar"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(80, 10)
	gui.StudsOffset = Vector3.new(0, 1.4, 0)
	gui.AlwaysOnTop = true
	gui.Parent = head

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 2)
	bgCorner.Parent = bg
	-- Team-colored border so ally vs enemy minions read at a glance.
	local borderColor = (team == "Blue") and Color3.fromRGB(100, 180, 255) or Color3.fromRGB(255, 100, 100)
	local stroke = Instance.new("UIStroke")
	stroke.Color = borderColor
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 2)
	fillCorner.Parent = fill

	return model, root, fill
end

-- The path each minion follows is the lane centerline (reversed for Red).
-- Lateral spread between minions is handled dynamically by separation in
-- _tick — no per-slot offset paths. Keeps minions on the road since they
-- only ever walk toward centerline waypoints and we clamp lateral drift.
local function buildPath(team)
	local out = {}
	if team == "Blue" then
		for _, wp in ipairs(Config.LaneWaypoints) do
			table.insert(out, wp)
		end
	else
		for i = #Config.LaneWaypoints, 1, -1 do
			table.insert(out, Config.LaneWaypoints[i])
		end
	end
	return out
end

function MinionService:spawn(team, typeKey, slotIndex, hpMult, dmgMult)
	typeKey = typeKey or "Melee"
	hpMult = hpMult or 1
	dmgMult = dmgMult or 1
	local typeData = Config.MinionTypes[typeKey]
	assert(typeData, "Unknown minion type: " .. tostring(typeKey))
	-- A tiny initial offset based on slot so the spawn doesn't put two minions
	-- on the exact same XZ pixel (separation handles the rest in flight).
	local initialOffsetX = ((slotIndex or 1) - 1) * 0.4 - 1.2
	local id = nextMinionId
	nextMinionId = nextMinionId + 1

	local path = buildPath(team)
	-- Spawn slightly offset along X so the first frame of two same-tick spawns
	-- aren't pixel-identical (separation takes over thereafter).
	local spawnAt = path[1] + Vector3.new(initialOffsetX, 0, 0)
	local model, root, hpFill = buildMinionModel(team, typeKey, typeData, spawnAt)
	model:SetAttribute("MinionId", id)
	model:SetAttribute("Team", team)
	model:SetAttribute("MinionType", typeKey)
	root:SetAttribute("MinionId", id)
	root:SetAttribute("Team", team)
	root:SetAttribute("MinionType", typeKey)
	model.Parent = getBin()

	local entry = {
		id = id,
		team = team,
		typeKey = typeKey,
		model = model,
		root = root,
		hpFill = hpFill,
		-- Per-type stats copied into the entry so a buff on this one minion
		-- wouldn't mutate Config. hpMult/dmgMult apply late-game wave scaling.
		maxHP = math.floor(typeData.MaxHP * hpMult + 0.5),
		hp = math.floor(typeData.MaxHP * hpMult + 0.5),
		walkSpeed = typeData.WalkSpeed,
		attackDamage = typeData.AttackDamage * dmgMult,
		attackRange = typeData.AttackRange,
		attackInterval = typeData.AttackInterval,
		aggroRadius = typeData.AggroRadius,
		lastHitGold = typeData.LastHitGold,
		useProjectile = typeData.Projectile,
		projectileSpeed = typeData.ProjectileSpeed,
		projectileRadius = typeData.ProjectileRadius,
		path = path,
		pathIndex = 2,
		alive = true,
		nextAttackAt = 0,
		currentTargetId = nil,
		currentTargetType = nil,
		spawnPos = path[1],
	}
	self.minions[id] = entry
	return entry
end

-- ===== Displacement / status CC (practice dummy + pit bots only) =====
-- No-ops on lane/jungle minions so we don't disturb their pathing. The dummy's
-- displacement is animated by _tick below; pit bots read the same cc* fields
-- from their own AI tick in PracticeService.
local DISPLACE_DURATION = 0.25

local function acceptsDisplacement(entry)
	return entry and entry.alive and (entry.isDummy or entry.isPitBot)
end

function MinionService:applyKnockbackToMinion(entry, fromPos, distance)
	if not acceptsDisplacement(entry) then
		return
	end
	local pos = entry.root.Position
	local dir = Vector3.new(pos.X - fromPos.X, 0, pos.Z - fromPos.Z)
	if dir.Magnitude < 0.01 then
		return
	end
	entry.ccHVel = dir.Unit * (distance / DISPLACE_DURATION)
	entry.ccHEndAt = os.clock() + DISPLACE_DURATION
end

function MinionService:applyPullToMinion(entry, towardPos, distance)
	if not acceptsDisplacement(entry) then
		return
	end
	local pos = entry.root.Position
	local dir = Vector3.new(towardPos.X - pos.X, 0, towardPos.Z - pos.Z)
	if dir.Magnitude < 0.01 then
		return
	end
	-- Apply the full pull distance to match knockback behavior. The room-edge
	-- clamp (dummy: _tick below; bots: PracticeService) keeps the target inside
	-- the practice arena even if the pull would overshoot.
	entry.ccHVel = dir.Unit * (distance / DISPLACE_DURATION)
	entry.ccHEndAt = os.clock() + DISPLACE_DURATION
end

function MinionService:applyKnockupToMinion(entry, height, duration)
	if not acceptsDisplacement(entry) then
		return
	end
	entry.ccVStartAt = os.clock()
	entry.ccVDuration = math.max(0.1, duration or 0.6)
	entry.ccVHeight = height or 8
end

-- Hard CC on pit bots so stuns/slows/roots can be practiced on something that
-- actually moves. The dummy never moves, so these are bot-only.
function MinionService:applyStunToMinion(entry, duration)
	if not (entry and entry.alive and entry.isPitBot) then
		return
	end
	entry.ccStunUntil = math.max(entry.ccStunUntil or 0, os.clock() + (duration or 1))
end

function MinionService:applySlowToMinion(entry, magnitude, duration)
	if not (entry and entry.alive and entry.isPitBot) then
		return
	end
	entry.ccSlow = { magnitude = math.clamp(magnitude or 0.3, 0, 1), expiresAt = os.clock() + (duration or 2) }
end

function MinionService:applyRootToMinion(entry, duration)
	if not (entry and entry.alive and entry.isPitBot) then
		return
	end
	entry.ccRootUntil = math.max(entry.ccRootUntil or 0, os.clock() + (duration or 1))
end

-- DoT for minion targets (used so Ignite-style abilities tick on the practice
-- dummy). No stacking dedup — every fresh application starts its own ticker;
-- if that becomes a problem we can add per-source bookkeeping later.
function MinionService:applyDoTToMinion(entry, damagePerTick, interval, ticks, source)
	if not (entry and entry.alive and damagePerTick and interval and ticks) then
		return
	end
	task.spawn(function()
		for _ = 1, ticks do
			task.wait(interval)
			if not (entry.alive and entry.model and entry.model.Parent) then
				return
			end
			self:applyDamage(entry, damagePerTick, source)
		end
	end)
end

function MinionService:applyDamage(entry, amount, killerPlayer)
	if not entry.alive then
		return
	end
	-- Jungle monsters aggro whoever last damaged them (JungleService AI).
	if entry.isJungle and killerPlayer then
		entry.aggroUserId = killerPlayer.UserId
	end
	entry.hp = math.max(0, entry.hp - amount)
	local pct = entry.hp / math.max(entry.maxHP, 1)
	entry.hpFill.Size = UDim2.fromScale(math.clamp(pct, 0, 1), 1)
	if pct > 0.5 then
		entry.hpFill.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
	elseif pct > 0.25 then
		entry.hpFill.BackgroundColor3 = Color3.fromRGB(220, 180, 60)
	else
		entry.hpFill.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	end
	if entry.hp <= 0 then
		entry.alive = false
		local deathPos = entry.root and entry.root.Position
		-- Practice dummies don't pay out gold — they're a training target.
		-- Jungle monsters and pit bots have their own reward flows.
		if not entry.isDummy and not entry.isJungle and not entry.isPitBot then
			-- Team share: every member of the enemy team gets MinionTeamGold
			-- regardless of who landed the killing blow.
			local enemyTeam = (entry.team == "Blue") and "Red" or "Blue"
			self.matchController:addTeamGold(enemyTeam, Config.MinionTeamGold or 0)
			-- Last-hit bonus: only the killer gets this, and only when they're
			-- on the enemy team (no friendly-fire payouts).
			if killerPlayer and entry.lastHitGold and entry.lastHitGold > 0 then
				if self.matchController:teamOf(killerPlayer) == enemyTeam then
					self.matchController:addGold(killerPlayer, entry.lastHitGold)
				end
			end
			-- Creep score + lane XP (last-hitter always, nearby allies share).
			if self.scoreService then
				self.scoreService:onMinionKilled(entry, killerPlayer, deathPos)
			end
		end
		if self.combatService then
			self.combatService:onTargetRemoved("minion", entry.id)
		end
		if entry.isDummy and self.practiceService then
			-- Practice dummy: hand off to PracticeService for respawn timing.
			self.practiceService:onDummyKilled(entry)
		elseif entry.isPitBot and self.practiceService then
			-- Pit bot: kill reward + respawn scheduling live in PracticeService.
			self.practiceService:onBotKilled(entry, killerPlayer)
		elseif entry.isJungle and self.jungleService then
			-- Jungle monster: rewards (gold/XP/buff) + respawn scheduling.
			self.jungleService:onJungleKilled(entry, killerPlayer)
		else
			entry.model:Destroy()
			self.minions[entry.id] = nil
		end
	end
end

-- Distance from `fromPos` to the surface of a tower's base cylinder. The base
-- is 22 studs wide for T1/T2 and 34 for the nexus, so using center distance
-- would put a melee attacker (range 6) far outside attack range even when
-- standing flush against the tower. Subtracting Size.Y / 2 (the base radius
-- after the 90° Z rotation) gives the "skin distance" instead.
local function towerEdgeDistance(tower, fromPos)
	local centerD = (tower.root.Position - fromPos).Magnitude
	local radius = tower.root.Size.Y / 2
	return math.max(0, centerD - radius)
end

-- Find the closest enemy target within aggro. Priority: minion/champion first,
-- and only fall back to enemy towers if no minion/champion is around — so
-- minions still attack each other in lane and only siege towers afterwards.
local function findNearestEnemyTarget(self, entry)
	local pos = entry.root.Position
	local best, bestDist
	-- Enemy minions (lane minions ignore neutral jungle monsters + pit bots)
	for otherId, other in pairs(self.minions) do
		if other.alive and other.team ~= entry.team and not other.isJungle and not other.isDummy and not other.isPitBot then
			local d = (other.root.Position - pos).Magnitude
			if d <= entry.aggroRadius then
				if not bestDist or d < bestDist then
					best = { type = "minion", id = otherId, entry = other }
					bestDist = d
				end
			end
		end
	end
	-- Enemy champions
	for _, player in ipairs(Players:GetPlayers()) do
		if self.matchController:teamOf(player) and self.matchController:teamOf(player) ~= entry.team then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0 then
				local d = (root.Position - pos).Magnitude
				if d <= entry.aggroRadius then
					if not bestDist or d < bestDist then
						best = { type = "player", id = player.UserId, player = player, root = root }
						bestDist = d
					end
				end
			end
		end
	end
	-- Enemy towers (fallback only — minion/champion targets win the tie).
	if not best and self.towerService then
		for _, tower in pairs(self.towerService:allTowers()) do
			if tower.alive and not tower.invulnerable and tower.team ~= entry.team then
				local d = towerEdgeDistance(tower, pos)
				if d <= entry.aggroRadius then
					if not bestDist or d < bestDist then
						best = { type = "tower", id = tower.id, entry = tower }
						bestDist = d
					end
				end
			end
		end
	end
	return best, bestDist
end

-- Try to keep using the minion's existing locked target. Returns (target, dist)
-- if the lock is still valid (alive, not invuln for towers, still inside aggro
-- range), or (nil, nil) if the lock is no longer good and a fresh search is
-- needed. This is what gives minions "stick to a target until it dies or
-- escapes" behavior — a closer enemy walking up doesn't poach the lock.
local function validateLock(self, entry)
	local locked = entry.lockedTarget
	if not locked then
		return nil, nil
	end
	local pos = entry.root.Position
	local d
	if locked.type == "minion" then
		local m = locked.entry
		if not m or not m.alive then
			return nil, nil
		end
		d = (m.root.Position - pos).Magnitude
	elseif locked.type == "player" then
		local p = locked.player
		if not p or not p.Parent or not self.combatService:isAlive(p) then
			return nil, nil
		end
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			return nil, nil
		end
		-- Refresh the cached root part in case the player respawned.
		locked.root = root
		d = (root.Position - pos).Magnitude
	elseif locked.type == "tower" then
		local t = locked.entry
		if not t or not t.alive or t.invulnerable then
			return nil, nil
		end
		d = towerEdgeDistance(t, pos)
	else
		return nil, nil
	end
	if d > entry.aggroRadius then
		return nil, nil
	end
	return locked, d
end

-- Resolve a target's current world position, or nil if it's gone/dead.
local function resolveTargetPos(self, target)
	if target.type == "minion" or target.type == "tower" then
		local e = target.entry
		if e.alive then
			return e.root.Position
		end
		return nil
	end
	if target.type == "player" then
		local char = target.player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and self.combatService:isAlive(target.player) then
			return root.Position
		end
	end
	return nil
end

local function dealDamage(self, target, damage)
	if target.type == "minion" then
		self:applyDamage(target.entry, damage, nil)
	elseif target.type == "player" then
		self.combatService:damagePlayer(target.player, damage, nil)
	elseif target.type == "tower" and self.towerService then
		self.towerService:applyDamage(target.entry, damage, nil)
	end
end

-- Spawn a homing projectile from this minion to its current target. The ball
-- tracks live target position and deals the minion's damage on impact.
-- Used by Ranged and Cannon minions; Melee deals instant damage.
local function spawnMinionProjectile(self, entry, target)
	local origin = entry.root.Position + Vector3.new(0, 0.5, 0)
	local proj = Instance.new("Part")
	proj.Name = "MinionProjectile"
	proj.Shape = Enum.PartType.Ball
	local r = entry.projectileRadius or 1
	proj.Size = Vector3.new(r * 2, r * 2, r * 2)
	proj.Material = Enum.Material.Neon
	-- Pit bots aren't on a Config.Teams team — they carry their own color.
	local teamData = Config.Teams[entry.team]
	proj.Color = entry.projectileColor or (teamData and teamData.Color) or Color3.fromRGB(230, 230, 230)
	proj.Anchored = true
	proj.CanCollide = false
	proj.CanQuery = false
	proj.CanTouch = false
	proj.Position = origin
	proj.Parent = workspace

	local speed = entry.projectileSpeed or 50
	local hitRadius = r + 1.2
	local damage = entry.attackDamage
	local maxLife = 5
	local elapsed = 0
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed = elapsed + dt
		local curPos = resolveTargetPos(self, target)
		if elapsed > maxLife or not proj.Parent or not curPos then
			if proj.Parent then
				proj:Destroy()
			end
			conn:Disconnect()
			return
		end
		local toTarget = curPos - proj.Position
		local dist = toTarget.Magnitude
		if dist <= hitRadius then
			dealDamage(self, target, damage)
			proj:Destroy()
			conn:Disconnect()
			return
		end
		local step = math.min(dist, speed * dt)
		proj.Position = proj.Position + toTarget.Unit * step
	end)
end

-- Public wrapper so PracticeService's ranged bots reuse the homing-projectile
-- visual + damage flow (tracks the live target, applies damage on impact).
function MinionService:fireBotProjectile(entry, targetPlayer)
	local char = targetPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	spawnMinionProjectile(self, entry, {
		type = "player",
		id = targetPlayer.UserId,
		player = targetPlayer,
		root = root,
	})
end

-- Boids-style separation. Returns a flat XZ vector pushing this minion away
-- from any nearby same-team minion. Magnitude scales with proximity (closer →
-- stronger push). We don't separate from enemies so attack-range positioning
-- doesn't oscillate.
local function computeSeparation(self, entry, radius)
	local pos = entry.root.Position
	local accum = Vector3.new(0, 0, 0)
	for _, other in pairs(self.minions) do
		if other ~= entry and other.alive and other.team == entry.team then
			local delta = pos - other.root.Position
			delta = Vector3.new(delta.X, 0, delta.Z)
			local d = delta.Magnitude
			if d > 0.001 and d < radius then
				local strength = (1 - d / radius)
				accum = accum + delta.Unit * strength
			end
		end
	end
	return accum
end

-- Closest point on the line segment [a, b] to point p (XZ plane only).
local function closestPointOnSegmentXZ(p, a, b)
	local ab = b - a
	local abFlat = Vector3.new(ab.X, 0, ab.Z)
	local lenSq = abFlat:Dot(abFlat)
	if lenSq < 0.0001 then
		return a
	end
	local apFlat = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local t = math.clamp(apFlat:Dot(abFlat) / lenSq, 0, 1)
	return a + ab * t
end

function MinionService:_tick(dt)
	local now = os.clock()
	for _, entry in pairs(self.minions) do
		if not entry.alive then
			continue
		end
		-- Jungle monsters and pit bots are driven by their own services' AI ticks.
		if entry.isJungle or entry.isPitBot then
			continue
		end
		-- Practice dummies don't run AI, but they react to displacement CC
		-- (knockback / pull move them horizontally over a short window;
		-- knockup adds a parabolic vertical offset above their floor Y).
		if entry.isDummy then
			local pos = entry.root.Position
			local newX, newZ = pos.X, pos.Z
			if entry.ccHEndAt and now < entry.ccHEndAt and entry.ccHVel then
				newX = newX + entry.ccHVel.X * dt
				newZ = newZ + entry.ccHVel.Z * dt
				local hx = Config.PracticeRoomSize.X / 2 - 2
				local hz = Config.PracticeRoomSize.Z / 2 - 2
				local ox = Config.PracticeOrigin.X
				local oz = Config.PracticeOrigin.Z
				newX = math.clamp(newX, ox - hx, ox + hx)
				newZ = math.clamp(newZ, oz - hz, oz + hz)
			end
			local baseY = entry.baseY or pos.Y
			local newY = baseY
			if entry.ccVStartAt and entry.ccVDuration and entry.ccVDuration > 0 then
				local elapsed = now - entry.ccVStartAt
				if elapsed < entry.ccVDuration then
					-- Parabola peaking at t = duration/2: y = 4h * t * (1 - t)
					local t = elapsed / entry.ccVDuration
					newY = baseY + 4 * (entry.ccVHeight or 0) * t * (1 - t)
				else
					entry.ccVStartAt = nil
				end
			end
			if newX ~= pos.X or newY ~= pos.Y or newZ ~= pos.Z then
				local look = entry.root.CFrame.LookVector
				local flat = Vector3.new(look.X, 0, look.Z)
				if flat.Magnitude < 0.01 then
					flat = Vector3.new(0, 0, -1)
				end
				local newPos = Vector3.new(newX, newY, newZ)
				entry.root.CFrame = CFrame.lookAt(newPos, newPos + flat.Unit)
				local head = entry.model:FindFirstChild("Head")
				if head then
					head.CFrame = entry.root.CFrame + Vector3.new(0, entry.root.Size.Y / 2 + head.Size.Y / 2, 0)
				end
			end
			continue
		end

		-- Pick / refresh target. Lock-on rule: once a target is locked, stay on
		-- it until it dies, leaves aggro radius, or (for towers) becomes invuln.
		-- Only then do we look for the next-nearest enemy. This is why a player
		-- walking up to a minion that's already attacking another minion does
		-- not steal aggro — the lock persists.
		local target, dist = validateLock(self, entry)
		if not target then
			target, dist = findNearestEnemyTarget(self, entry)
			entry.lockedTarget = target
		end
		entry.currentTarget = target

		local inAttackRange = target and dist and dist <= entry.attackRange

		-- Helper: move the minion one step toward `destPos`, blending in
		-- separation from nearby allies and clamping perpendicular travel to the
		-- current lane segment. Shared by waypoint-following and target-chasing.
		local function stepToward(destPos)
			local pos = entry.root.Position
			local toDest = Vector3.new(destPos.X - pos.X, 0, destPos.Z - pos.Z)
			if toDest.Magnitude < 0.001 then
				return
			end
			local moveDir = toDest.Unit
			local sep = computeSeparation(self, entry, 4.5)
			local combined = moveDir + sep * 0.9
			local mag = Vector3.new(combined.X, 0, combined.Z).Magnitude
			if mag > 0.001 then
				combined = Vector3.new(combined.X / mag, 0, combined.Z / mag)
			else
				combined = moveDir
			end
			local step = combined * entry.walkSpeed * dt
			local newPos = pos + Vector3.new(step.X, 0, step.Z)

			-- Clamp to the current lane segment so chase doesn't pull minions
			-- into the jungle.
			local cur_wp = entry.path[entry.pathIndex]
			if cur_wp then
				local segFrom = entry.path[entry.pathIndex - 1] or entry.spawnPos
				local segTo = cur_wp
				local onSeg = closestPointOnSegmentXZ(newPos, segFrom, segTo)
				local perp = Vector3.new(newPos.X - onSeg.X, 0, newPos.Z - onSeg.Z)
				local perpMag = perp.Magnitude
				local halfLane = Config.LaneWidth / 2 - 1
				if perpMag > halfLane then
					local clamped = onSeg + perp.Unit * halfLane
					newPos = Vector3.new(clamped.X, newPos.Y, clamped.Z)
				end
			end

			entry.root.CFrame = CFrame.lookAt(newPos, newPos + moveDir)
		end

		if inAttackRange then
			-- Stop and attack
			if now >= entry.nextAttackAt then
				entry.nextAttackAt = now + entry.attackInterval
				if entry.useProjectile then
					spawnMinionProjectile(self, entry, target)
				else
					dealDamage(self, target, entry.attackDamage)
				end
			end
			-- Face the target
			local facePos
			if target.type == "minion" or target.type == "tower" then
				facePos = target.entry.root.Position
			else
				facePos = target.root.Position
			end
			local pos = entry.root.Position
			entry.root.CFrame = CFrame.lookAt(pos, Vector3.new(facePos.X, pos.Y, facePos.Z))
		elseif target then
			-- Have a target (in aggro radius) but not yet in attack range —
			-- pursue. This is what lets minions break off the lane centerline
			-- to engage towers that are offset to the side.
			local targetPos
			if target.type == "minion" or target.type == "tower" then
				targetPos = target.entry.root.Position
			else
				targetPos = target.root.Position
			end
			stepToward(targetPos)
		else
			-- Walk toward the next waypoint, blending in a separation force
			-- to dodge nearby allies. Final position is clamped perpendicular
			-- to the current lane segment so they never wander off the road.
			local target_wp = entry.path[entry.pathIndex]
			if target_wp then
				local pos = entry.root.Position
				local toWp = Vector3.new(target_wp.X - pos.X, 0, target_wp.Z - pos.Z)
				if toWp.Magnitude < Config.Minion.WaypointReachDistance then
					entry.pathIndex = entry.pathIndex + 1
				else
					stepToward(target_wp)
				end
			end
		end

		-- Move head to follow torso (offset scales with body size).
		local head = entry.model:FindFirstChild("Head")
		if head and entry.root then
			head.CFrame = entry.root.CFrame + Vector3.new(0, entry.root.Size.Y / 2 + head.Size.Y / 2, 0)
		end
	end
end

function MinionService:start()
	-- AI loop is always on (cheap if no minions exist).
	table.insert(self.connections, RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end))
end

function MinionService:startWaves()
	if self.waveTaskRunning then
		return
	end
	self.waveTaskRunning = true
	self.waveNumber = 0
	task.spawn(function()
		task.wait(Config.Wave.StartDelay)
		while self.waveTaskRunning do
			-- Waves scale up over the match so the game escalates toward an end.
			self.waveNumber = self.waveNumber + 1
			local grown = self.waveNumber - 1
			local hpMult = math.min(1 + (Config.WaveScaling.HPPerWavePct / 100) * grown, Config.WaveScaling.MaxMult)
			local dmgMult = math.min(1 + (Config.WaveScaling.DamagePerWavePct / 100) * grown, Config.WaveScaling.MaxMult)
			local seq = Config.Wave.Sequence
			for i, typeKey in ipairs(seq) do
				if not self.waveTaskRunning then
					return
				end
				self:spawn("Blue", typeKey, i, hpMult, dmgMult)
				self:spawn("Red", typeKey, i, hpMult, dmgMult)
				if i < #seq then
					task.wait(Config.Wave.Stagger)
				end
			end
			task.wait(Config.Wave.Interval - Config.Wave.Stagger * (#Config.Wave.Sequence - 1))
		end
	end)
end

function MinionService:stopWaves()
	self.waveTaskRunning = false
end

function MinionService:clearAll()
	for _, entry in pairs(self.minions) do
		if entry.model and entry.model.Parent then
			entry.model:Destroy()
		end
	end
	self.minions = {}
end

function MinionService:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return MinionService
