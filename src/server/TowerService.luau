local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local TowerService = {}
TowerService.__index = TowerService

local nextTowerId = 1

function TowerService.new(matchController, combatService, minionService)
	local self = setmetatable({}, TowerService)
	self.matchController = matchController
	self.combatService = combatService
	self.minionService = minionService
	self.towers = {} -- towerId -> entry
	self.connections = {}
	-- Optional callback fired with (winningTeam) when a nexus (tier 3) is destroyed.
	self.onNexusDestroyed = nil
	return self
end

function TowerService:setMinionService(svc)
	self.minionService = svc
end

function TowerService:setScoreService(svc)
	self.scoreService = svc
end

-- Normalize whatever the user typed into the TowerTeam attribute.
-- Accepts "Blue", "blue", "BLUE", " Blue " etc.; returns "Blue" / "Red" / nil.
local function normalizeTeam(raw)
	if typeof(raw) ~= "string" then
		return nil
	end
	local trimmed = raw:gsub("^%s+", ""):gsub("%s+$", ""):lower()
	if trimmed == "blue" then
		return "Blue"
	elseif trimmed == "red" then
		return "Red"
	end
	return nil
end

-- Scan Workspace for any BasePart with a TowerTeam attribute. Walking the
-- descendants lets users keep towers inside whatever folder they want.
local function discoverTowerParts()
	local found = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") then
			local team = normalizeTeam(inst:GetAttribute("TowerTeam"))
			if team then
				table.insert(found, { part = inst, team = team })
			end
		end
	end
	return found
end

local TEAM_BORDER = {
	Blue = Color3.fromRGB(100, 180, 255),
	Red = Color3.fromRGB(255, 100, 100),
}

local function attachHPBar(towerPart, entry)
	-- Adornee to a separate non-rotated "HPAnchor" part if the tower model has
	-- one. The base cylinder is rotated 90° around Z which makes StudsOffset
	-- behave weirdly (bar ends up to the side of the tower); a clean, axis-
	-- aligned anchor placed above the tower fixes the position with no offset
	-- math.
	local adornee = towerPart
	if towerPart.Parent and towerPart.Parent:IsA("Model") then
		local anchor = towerPart.Parent:FindFirstChild("HPAnchor")
		if anchor and anchor:IsA("BasePart") then
			adornee = anchor
		end
	end

	-- Remove any old bar (carried over from a previous match or rebuild).
	local old = adornee:FindFirstChild("TowerHPBar")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "TowerHPBar"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(140, 14)
	gui.AlwaysOnTop = true
	gui.Parent = adornee

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 3)
	bgCorner.Parent = bg
	local stroke = Instance.new("UIStroke")
	stroke.Color = TEAM_BORDER[entry.team] or Color3.fromRGB(200, 200, 200)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	entry.hpFill = fill
	entry.hpBar = gui
end

-- Wrap an invuln tower in a translucent blue dome. Replaces the previous
-- "make the base cylinder semi-transparent" trick which made the upper half
-- look like it was floating.
local function attachBarrier(entry)
	local model = entry.root and entry.root.Parent
	if not model or not model:IsA("Model") then
		return
	end
	-- Idempotent: if we already have a live barrier on this entry, keep it.
	if entry.barrier and entry.barrier.Parent then
		return
	end
	-- Defensive: tear down any orphan InvulnBarrier on the model from a
	-- previous match / re-init so we never end up with two stacked domes.
	for _, child in ipairs(model:GetChildren()) do
		if child.Name == "InvulnBarrier" then
			child:Destroy()
		end
	end
	-- Nexus is wider/taller — bigger barrier.
	local radius = (entry.tier == 3) and 34 or 26
	local center = entry.root.Position
	local barrier = Instance.new("Part")
	barrier.Name = "InvulnBarrier"
	barrier.Shape = Enum.PartType.Ball
	barrier.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	barrier.Position = Vector3.new(center.X, center.Y + 14, center.Z)
	barrier.Color = Color3.fromRGB(120, 180, 255)
	barrier.Material = Enum.Material.ForceField
	barrier.Transparency = 0.4
	barrier.Anchored = true
	barrier.CanCollide = false
	barrier.CanQuery = false
	barrier.CanTouch = false
	barrier.Parent = model
	entry.barrier = barrier
end

local function detachBarrier(entry)
	if entry.barrier then
		entry.barrier:Destroy()
		entry.barrier = nil
	end
	-- Belt-and-suspenders: if the entry's `.barrier` reference ever drifts
	-- out of sync (e.g. the Studio script re-baked the arena, or a previous
	-- match left a stale dome behind), sweep the model for any leftover
	-- InvulnBarrier and remove it. This is what guarantees that a tower that
	-- is NOT invulnerable can never visually show a shield.
	local model = entry.root and entry.root.Parent
	if model and model:IsA("Model") then
		for _, child in ipairs(model:GetChildren()) do
			if child.Name == "InvulnBarrier" then
				child:Destroy()
			end
		end
	end
end

local function readNumber(part, attr, default)
	local v = part:GetAttribute(attr)
	if typeof(v) == "number" and v > 0 then
		return v
	end
	return default
end

-- Look for an optional sibling part named "Turret" inside the same Model.
-- If found, the tick loop will rotate it to face the current target and
-- draw a red beam from it to the target.
local function findTurretFor(basePart)
	local parent = basePart.Parent
	if parent and parent:IsA("Model") then
		for _, child in ipairs(parent:GetDescendants()) do
			if child ~= basePart and child:IsA("BasePart") and child.Name == "Turret" then
				return child
			end
		end
	end
	return nil
end

local function setupTargetBeam(entry)
	if not entry.turret then
		return
	end
	-- Anchor every BasePart in the tower model so nothing can be shoved.
	local turret = entry.turret
	turret.Anchored = true
	-- Origin attachment lives on the turret (moves with it).
	local a0 = Instance.new("Attachment")
	a0.Name = "TowerBeamStart"
	a0.Parent = turret
	-- Endpoint attachment — we reparent it to the current target each tick.
	local a1 = Instance.new("Attachment")
	a1.Name = "TowerBeamEnd"
	a1.Parent = turret -- temporary parent; updated when target changes
	local beam = Instance.new("Beam")
	beam.Name = "TowerBeam"
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 40, 40))
	beam.Width0 = 0.12
	beam.Width1 = 0.12
	beam.LightEmission = 0.8
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(0.25)
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Enabled = false
	beam.Parent = turret
	entry.beam = beam
	entry.beamStart = a0
	entry.beamEnd = a1
end

local function teardownTargetBeam(entry)
	if entry.beam then
		entry.beam:Destroy()
	end
	if entry.beamStart then
		entry.beamStart:Destroy()
	end
	if entry.beamEnd then
		entry.beamEnd:Destroy()
	end
	entry.beam, entry.beamStart, entry.beamEnd = nil, nil, nil
end

function TowerService:initTowers()
	-- Reset to a clean slate (in case a match ended dirty).
	self:reset()
	local discovered = discoverTowerParts()
	for _, info in ipairs(discovered) do
		local part = info.part
		local team = info.team
		local id = nextTowerId
		nextTowerId = nextTowerId + 1
		local maxHP = readNumber(part, "TowerMaxHP", Config.Tower.DefaultMaxHP)
		local tier = readNumber(part, "TowerTier", 1)
		tier = math.clamp(math.floor(tier), 1, 3)
		local entry = {
			id = id,
			team = team,
			tier = tier, -- 1 = T1 tower, 2 = T2 tower, 3 = nexus
			root = part,
			maxHP = maxHP,
			hp = maxHP,
			range = readNumber(part, "TowerRange", Config.Tower.DefaultRange),
			damage = readNumber(part, "TowerDamage", Config.Tower.DefaultDamage),
			interval = readNumber(part, "TowerInterval", Config.Tower.DefaultInterval),
			goldReward = readNumber(part, "TowerGoldReward", Config.Tower.DefaultGoldReward),
			nextAttackAt = 0,
			aggroPlayerId = nil,
			alive = true,
			invulnerable = false,
			originalTransparency = part.Transparency,
			originalCanCollide = part.CanCollide,
			originalAnchored = part.Anchored,
			originalMaterial = part.Material,
		}
		-- Force-anchor so players (or knockback) can't shove the tower around.
		part.Anchored = true
		part:SetAttribute("TowerId", id)
		part:SetAttribute("Team", team)
		attachHPBar(part, entry)
		-- Optional turret + red-line indicator
		entry.turret = findTurretFor(part)
		if entry.turret then
			entry.originalTurretAnchored = entry.turret.Anchored
			setupTargetBeam(entry)
		end
		-- Anchor any other parts in the same Model so the whole tower is rigid,
		-- and remember their original transparency / collidability so we can
		-- hide the WHOLE model on death and restore it on match end.
		entry.modelParts = {}
		local function collectParts(container)
			for _, p in ipairs(container:GetDescendants()) do
				if p:IsA("BasePart") then
					table.insert(entry.modelParts, {
						part = p,
						originalTransparency = p.Transparency,
						originalCanCollide = p.CanCollide,
					})
					p.Anchored = true
				end
			end
		end
		if part.Parent and part.Parent:IsA("Model") then
			collectParts(part.Parent)
		else
			table.insert(entry.modelParts, {
				part = part,
				originalTransparency = part.Transparency,
				originalCanCollide = part.CanCollide,
			})
		end
		self.towers[id] = entry
	end
	self:_recomputeInvulnerability()
	print(("[TowerService] Discovered %d tower(s):"):format(#discovered))
	for _, t in pairs(self.towers) do
		print(("  Tower %d  team=%s  tier=%d  HP=%d  range=%d  dmg=%d  interval=%.2f  invuln=%s"):format(
			t.id, t.team, t.tier, t.maxHP, t.range, t.damage, t.interval, tostring(t.invulnerable)
		))
	end
end

-- Are any minions from `attackerTeam` currently inside the tower's range?
-- Used to decide whether to apply the backdoor damage reduction.
function TowerService:_hasAlliedMinionNear(towerEntry, attackerTeam)
	if not self.minionService or not attackerTeam then
		return false
	end
	local pos = towerEntry.root.Position
	for _, m in pairs(self.minionService:allMinions()) do
		if m.alive and m.team == attackerTeam then
			if (m.root.Position - pos).Magnitude <= towerEntry.range then
				return true
			end
		end
	end
	return false
end

function TowerService:reset()
	for _, entry in pairs(self.towers) do
		-- Restore every part in the tower's model to its original look.
		for _, rec in ipairs(entry.modelParts or {}) do
			if rec.part and rec.part.Parent then
				rec.part.Transparency = rec.originalTransparency or 0
				rec.part.CanCollide = rec.originalCanCollide
			end
		end
		if entry.root and entry.root.Parent then
			if entry.originalAnchored ~= nil then
				entry.root.Anchored = entry.originalAnchored
			end
			entry.root:SetAttribute("TowerId", nil)
		end
		if entry.hpBar then
			entry.hpBar:Destroy()
			entry.hpBar = nil
		end
		detachBarrier(entry)
		teardownTargetBeam(entry)
	end
	self.towers = {}
end

function TowerService:getTower(id)
	return self.towers[id]
end

function TowerService:allTowers()
	return self.towers
end

-- Per team, the lowest tier with at least one alive tower. A tower is
-- invulnerable if its tier is higher than this number (i.e. there's still
-- a lower-tier tower of its team defending it).
function TowerService:_recomputeInvulnerability()
	local minTierAlive = { Blue = math.huge, Red = math.huge }
	for _, t in pairs(self.towers) do
		if t.alive and t.tier < minTierAlive[t.team] then
			minTierAlive[t.team] = t.tier
		end
	end
	for _, t in pairs(self.towers) do
		local shouldBeInvuln = t.alive and (t.tier > minTierAlive[t.team])
		t.invulnerable = shouldBeInvuln
		-- Always reconcile the barrier with the desired state instead of
		-- gating on a transition — that way a stale dome from a previous
		-- match or a desynced entry can never leave a shield on a tower that
		-- isn't actually invulnerable.
		if shouldBeInvuln then
			attachBarrier(t)
		else
			detachBarrier(t)
		end
		-- Hide the HP bar entirely while the tower can't be damaged.
		if t.hpBar then
			t.hpBar.Enabled = not shouldBeInvuln
		end
	end
end

local function updateHPFill(entry)
	if not entry.hpFill then
		return
	end
	local pct = math.clamp(entry.hp / math.max(entry.maxHP, 1), 0, 1)
	entry.hpFill.Size = UDim2.fromScale(pct, 1)
	if pct > 0.5 then
		entry.hpFill.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
	elseif pct > 0.25 then
		entry.hpFill.BackgroundColor3 = Color3.fromRGB(220, 180, 60)
	else
		entry.hpFill.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
	end
end

function TowerService:applyDamage(entry, amount, killerPlayer)
	if not entry.alive then
		return
	end
	if entry.invulnerable then
		return -- blocked by tier-cascade invulnerability
	end
	-- Backdoor protection: champion attacks with no allied minions nearby do 20% damage.
	if killerPlayer and self.matchController then
		local attackerTeam = self.matchController:teamOf(killerPlayer)
		if attackerTeam and attackerTeam ~= entry.team and not self:_hasAlliedMinionNear(entry, attackerTeam) then
			amount = amount * Config.Tower.BackdoorDamageMult
		end
	end
	entry.hp = math.max(0, entry.hp - amount)
	updateHPFill(entry)
	-- (Aggro on damage-to-tower removed by request — towers only aggro on a
	--  player who damages another player within range.)
	if entry.hp <= 0 then
		entry.alive = false
		if killerPlayer and self.matchController then
			self.matchController:addGold(killerPlayer, entry.goldReward)
		end
		-- Team-wide gold/XP + the "tower destroyed" announcement.
		if self.scoreService then
			self.scoreService:onTowerDestroyed(entry, killerPlayer)
		end
		-- Hide the WHOLE tower model (base + dome + turret + anything else
		-- under the same Model). We don't actually destroy the parts since
		-- they're user-placed in Studio — they get restored on match end.
		for _, rec in ipairs(entry.modelParts or {}) do
			if rec.part and rec.part.Parent then
				rec.part.Transparency = 1
				rec.part.CanCollide = false
			end
		end
		entry.root:SetAttribute("TowerId", nil)
		if entry.hpBar then
			entry.hpBar:Destroy()
			entry.hpBar = nil
		end
		detachBarrier(entry)
		teardownTargetBeam(entry)
		if self.combatService then
			self.combatService:onTargetRemoved("tower", entry.id)
		end
		self:_recomputeInvulnerability()
		-- If a nexus (tier 3) just fell, the opposing team wins.
		if entry.tier == 3 and self.onNexusDestroyed then
			local winningTeam = (entry.team == "Blue") and "Red" or "Blue"
			self.onNexusDestroyed(winningTeam)
		end
	end
end

-- Called by CombatService whenever a player damages another player.
-- For each ally-of-victim tower whose range contains the attacker, set aggro.
function TowerService:onPlayerAttackedPlayer(attacker, victim)
	if not attacker or not victim or attacker == victim then
		return
	end
	local attackerTeam = self.matchController:teamOf(attacker)
	local victimTeam = self.matchController:teamOf(victim)
	if not attackerTeam or not victimTeam or attackerTeam == victimTeam then
		return
	end
	local char = attacker.Character
	local attackerRoot = char and char:FindFirstChild("HumanoidRootPart")
	if not attackerRoot then
		return
	end
	local pos = attackerRoot.Position
	for _, tower in pairs(self.towers) do
		if tower.alive and tower.team == victimTeam then
			local d = (tower.root.Position - pos).Magnitude
			if d <= tower.range then
				tower.aggroPlayerId = attacker.UserId
			end
		end
	end
end

local function nearestEnemyMinion(self, tower)
	if not self.minionService then
		return nil, nil
	end
	local best, bestDist
	local towerPos = tower.root.Position
	for _, m in pairs(self.minionService:allMinions()) do
		if m.alive and m.team ~= tower.team and not m.isJungle and not m.isDummy then
			local d = (m.root.Position - towerPos).Magnitude
			if d <= tower.range then
				if not bestDist or d < bestDist then
					best = m
					bestDist = d
				end
			end
		end
	end
	return best, bestDist
end

-- Fallback target when no enemy minions are in range. Mirrors League's
-- "no-minion-shield" rule: with no minions to defend against, the tower
-- attacks the nearest enemy champion in range.
local function nearestEnemyChampion(self, tower)
	if not self.matchController or not self.combatService then
		return nil
	end
	local best, bestDist
	local towerPos = tower.root.Position
	for _, player in ipairs(Players:GetPlayers()) do
		local team = self.matchController:teamOf(player)
		if team and team ~= tower.team and self.combatService:isAlive(player) then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local d = (root.Position - towerPos).Magnitude
				if d <= tower.range then
					if not bestDist or d < bestDist then
						best = player
						bestDist = d
					end
				end
			end
		end
	end
	return best
end

-- Spawn a homing projectile from the turret tip toward the current target.
-- The ball follows the target part each Heartbeat until it hits (deal damage)
-- or fizzles (target lost / max lifetime reached).
local PROJECTILE_SPEED = 90
local PROJECTILE_HIT_RADIUS = 2.4
local PROJECTILE_MAX_LIFETIME = 4

local function spawnTowerProjectile(tower, targetType, targetRef, combatService, minionService)
	local turret = tower.turret
	local spawnPos
	if turret then
		spawnPos = turret.Position + turret.CFrame.LookVector * (turret.Size.Z / 2 + 0.5)
	else
		spawnPos = tower.root.Position + Vector3.new(0, tower.root.Size.Y / 2 + 2, 0)
	end

	local proj = Instance.new("Part")
	proj.Name = "TowerProjectile"
	proj.Shape = Enum.PartType.Ball
	proj.Size = Vector3.new(1.6, 1.6, 1.6)
	proj.Material = Enum.Material.Neon
	proj.Color = (tower.team == "Blue") and Color3.fromRGB(120, 200, 255) or Color3.fromRGB(255, 130, 120)
	proj.Anchored = true
	proj.CanCollide = false
	proj.CanQuery = false
	proj.CanTouch = false
	proj.Position = spawnPos
	proj.Parent = workspace

	local lifetime = 0
	local damage = tower.damage
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		lifetime = lifetime + dt
		if lifetime > PROJECTILE_MAX_LIFETIME or not proj.Parent then
			if proj.Parent then
				proj:Destroy()
			end
			conn:Disconnect()
			return
		end
		-- Look up current target position; bail out if target is gone.
		local curPos
		if targetType == "minion" then
			if targetRef.alive then
				curPos = targetRef.root.Position
			end
		elseif targetType == "player" then
			local char = targetRef.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root and combatService:isAlive(targetRef) then
				curPos = root.Position
			end
		end
		if not curPos then
			proj:Destroy()
			conn:Disconnect()
			return
		end
		local toTarget = curPos - proj.Position
		local dist = toTarget.Magnitude
		if dist <= PROJECTILE_HIT_RADIUS then
			if targetType == "minion" then
				minionService:applyDamage(targetRef, damage, nil)
			elseif targetType == "player" then
				combatService:damagePlayer(targetRef, damage, nil)
			end
			proj:Destroy()
			conn:Disconnect()
			return
		end
		local step = math.min(dist, PROJECTILE_SPEED * dt)
		proj.Position = proj.Position + toTarget.Unit * step
	end)
end

-- Update the red beam endpoint to follow the target in world space.
-- IMPORTANT: we do NOT reparent the end attachment onto the target part.
-- If we did, the attachment would be destroyed along with the target on
-- death, and any later WorldPosition / Parent write would throw
-- "Parent property is locked", crashing the tick loop and stopping the
-- tower from attacking anything further. Keeping both attachments on
-- the turret and moving the endpoint via WorldPosition is safe.
local function attachBeamTo(entry, targetPart)
	if not entry.beam or not entry.beamEnd then
		return
	end
	if not targetPart or not targetPart.Parent then
		entry.beam.Enabled = false
		return
	end
	entry.beamEnd.WorldPosition = targetPart.Position
	entry.beam.Enabled = true
end

local function disableBeam(entry)
	if entry.beam then
		entry.beam.Enabled = false
	end
end

function TowerService:_tick()
	local now = os.clock()
	for _, tower in pairs(self.towers) do
		if not tower.alive then
			continue
		end
		local towerPos = tower.root.Position

		-- Validate aggro: player still exists, alive, and in range.
		local aggroPlayer
		if tower.aggroPlayerId then
			aggroPlayer = Players:GetPlayerByUserId(tower.aggroPlayerId)
			if not aggroPlayer or not self.combatService:isAlive(aggroPlayer) then
				tower.aggroPlayerId = nil
				aggroPlayer = nil
			else
				local char = aggroPlayer.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if not root or (root.Position - towerPos).Magnitude > tower.range then
					tower.aggroPlayerId = nil
					aggroPlayer = nil
				end
			end
		end

		-- Pick the active target (player aggro wins; else nearest enemy minion).
		local targetType, targetRef, targetPart, targetPos
		if aggroPlayer then
			local char = aggroPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				targetType, targetRef, targetPart, targetPos = "player", aggroPlayer, root, root.Position
			end
		end
		if not targetType then
			local minion = nearestEnemyMinion(self, tower)
			if minion then
				targetType, targetRef, targetPart, targetPos = "minion", minion, minion.root, minion.root.Position
			else
				-- No minions in range → fall back to nearest enemy champion (League no-minion rule).
				local champ = nearestEnemyChampion(self, tower)
				if champ then
					local char = champ.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					if root then
						targetType, targetRef, targetPart, targetPos = "player", champ, root, root.Position
					end
				end
			end
		end

		-- Red-line indicator: just shows who the tower is currently aiming at.
		if targetPos then
			attachBeamTo(tower, targetPart)
		else
			disableBeam(tower)
		end

		-- Attack if cooldown is up — launches a homing ball; damage applies on impact.
		if targetType and now >= tower.nextAttackAt then
			tower.nextAttackAt = now + tower.interval
			spawnTowerProjectile(tower, targetType, targetRef, self.combatService, self.minionService)
		end
	end
end

function TowerService:start()
	table.insert(self.connections, RunService.Heartbeat:Connect(function()
		self:_tick()
	end))
end

function TowerService:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return TowerService
