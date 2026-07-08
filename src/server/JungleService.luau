-- JungleService — neutral jungle monsters + the boss objective.
--
-- Each camp pad (Config.JungleCamps) hosts one brute; the pit (Config.BossLair)
-- hosts the Overlord. Monsters are registered inside MinionService.minions
-- (team "Jungle", isJungle = true) so every existing damage path — auto-attacks,
-- projectiles, AoEs, DoTs, click-targeting — works on them unchanged.
-- MinionService skips their AI tick; this service drives them instead:
--
--   idle      → stand at home, rapidly heal to full
--   fighting  → chase + melee whoever damaged them last (aggro on damage only)
--   leashed   → walked too far from home → drop aggro, return, heal
--
-- Rewards on kill:
--   camp → killer gets gold + a timed buff (STORM north / MIGHT south),
--          nearby teammates share the XP
--   boss → the killer's whole team gets gold + XP + the OVERLORD buff
--
-- Camps respawn on a timer; the boss respawns a few minutes after each kill.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local JungleService = {}
JungleService.__index = JungleService

local CAMP_ID_BASE = -100 -- camp ids: -101, -102, ... (negative → never collides with lane minions)
local BOSS_ID = -200

local JUNGLE_BODY = Color3.fromRGB(90, 80, 110)
local BOSS_BODY = Color3.fromRGB(60, 40, 80)

function JungleService.new(minionService, combatService, matchController, scoreService)
	local self = setmetatable({}, JungleService)
	self.minionService = minionService
	self.combatService = combatService
	self.matchController = matchController
	self.scoreService = scoreService
	self.entries = {} -- id -> entry (also present in minionService.minions)
	-- Bumped on every startSpawns/stopAndClear so stale respawn timers from a
	-- previous match can't spawn monsters into the next one.
	self.generation = 0
	self.running = false
	self.connections = {}
	return self
end

local function getBin()
	local bin = workspace:FindFirstChild("Minions")
	if not bin then
		bin = Instance.new("Folder")
		bin.Name = "Minions"
		bin.Parent = workspace
	end
	return bin
end

-- ===== Model building ==================================================

local function addPart(model, props)
	local p = Instance.new("Part")
	p.Anchored = true
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
	p.Parent = model
	return p
end

local function attachHPBar(head, accent)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HPBar"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(90, 12)
	gui.StudsOffset = Vector3.new(0, 1.6, 0)
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
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
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
	return fill
end

-- A hulking neutral brute. `accent` is the buff color (STORM cyan / MIGHT
-- ember / OVERLORD purple) so players can read the reward from the monster.
local function buildMonsterModel(name, spawnPos, size, bodyColor, accent)
	local model = Instance.new("Model")
	model.Name = name

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.CanCollide = true
	root.CanQuery = true
	root.CanTouch = false
	root.Size = size
	root.CFrame = CFrame.new(spawnPos + Vector3.new(0, size.Y / 2, 0))
	root.Color = bodyColor
	root.Material = Enum.Material.Slate
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model
	model.PrimaryPart = root

	local headD = size.X * 0.55
	local head = addPart(model, {
		Name = "Head",
		Shape = Enum.PartType.Ball,
		CanQuery = true,
		Size = Vector3.new(headD, headD, headD),
		CFrame = root.CFrame + Vector3.new(0, size.Y / 2 + headD / 2, 0),
		Color = bodyColor,
		Material = Enum.Material.Slate,
	})

	-- Glowing eyes + accent horns keyed to the buff color.
	local headCenterY = size.Y / 2 + headD / 2
	local eyeD = headD * 0.26
	local details = {}
	for _, sgn in ipairs({ -1, 1 }) do
		table.insert(details, addPart(model, {
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(eyeD, eyeD, eyeD),
			CFrame = root.CFrame * CFrame.new(sgn * headD * 0.24, headCenterY + headD * 0.06, -headD * 0.42),
			Color = accent,
			Material = Enum.Material.Neon,
		}))
		table.insert(details, addPart(model, {
			Name = "Horn",
			Size = Vector3.new(headD * 0.16, headD * 0.75, headD * 0.16),
			CFrame = root.CFrame * CFrame.new(sgn * headD * 0.42, headCenterY + headD * 0.5, 0)
				* CFrame.Angles(0, 0, sgn * math.rad(-24)),
			Color = accent,
			Material = Enum.Material.Neon,
		}))
	end
	-- Broad shoulder slabs for the brute silhouette.
	for _, sgn in ipairs({ -1, 1 }) do
		table.insert(details, addPart(model, {
			Name = "Shoulder",
			Size = Vector3.new(size.X * 0.34, size.Y * 0.4, size.Z * 0.9),
			CFrame = root.CFrame * CFrame.new(sgn * size.X * 0.6, size.Y * 0.26, 0),
			Color = bodyColor:Lerp(Color3.new(0, 0, 0), 0.35),
			Material = Enum.Material.Slate,
		}))
	end

	local hpFill = attachHPBar(head, accent)
	return model, root, head, details, hpFill
end

-- ===== Spawning =========================================================

function JungleService:_register(entry)
	entry.model:SetAttribute("MinionId", entry.id)
	entry.model:SetAttribute("Team", "Jungle")
	entry.root:SetAttribute("MinionId", entry.id)
	entry.root:SetAttribute("Team", "Jungle")
	entry.model.Parent = getBin()
	self.minionService.minions[entry.id] = entry
	self.entries[entry.id] = entry
end

function JungleService:_spawnCamp(campIndex, camp)
	local creep = Config.Jungle.Creep
	local buffKey = string.find(camp.name, "North") and "Storm" or "Might"
	local buff = Config.Jungle.Buffs[buffKey]
	local home = Vector3.new(camp.position.X, Config.GroundY, camp.position.Z)
	local size = Vector3.new(4.2, 6, 3.4)
	local model, root, head, _, hpFill = buildMonsterModel(buffKey .. "Brute", home, size, JUNGLE_BODY, buff.Color)

	local entry = {
		id = CAMP_ID_BASE - campIndex,
		team = "Jungle",
		typeKey = "JungleBrute",
		isJungle = true,
		model = model,
		root = root,
		head = head,
		hpFill = hpFill,
		maxHP = creep.MaxHP,
		hp = creep.MaxHP,
		walkSpeed = creep.WalkSpeed,
		attackDamage = creep.AttackDamage,
		attackRange = creep.AttackRange,
		attackInterval = creep.AttackInterval,
		aggroRadius = 0, -- never proximity-aggros; damage sets aggroUserId
		lastHitGold = 0,
		useProjectile = false,
		path = { home },
		pathIndex = 999,
		alive = true,
		nextAttackAt = 0,
		spawnPos = home,
		home = home,
		campIndex = campIndex,
		buffKey = buffKey,
		isBoss = false,
		aggroUserId = nil,
	}
	self:_register(entry)
	return entry
end

function JungleService:_spawnBoss()
	local bossCfg = Config.Boss
	local home = Vector3.new(Config.BossLair.position.X, Config.GroundY, Config.BossLair.position.Z)
	local size = Vector3.new(6.5, 9, 5)
	local model, root, head, _, hpFill = buildMonsterModel("Overlord", home, size, BOSS_BODY, bossCfg.Buff.Color)

	local entry = {
		id = BOSS_ID,
		team = "Jungle",
		typeKey = "Boss",
		isJungle = true,
		model = model,
		root = root,
		head = head,
		hpFill = hpFill,
		maxHP = bossCfg.MaxHP,
		hp = bossCfg.MaxHP,
		walkSpeed = bossCfg.WalkSpeed,
		attackDamage = bossCfg.AttackDamage,
		attackRange = bossCfg.AttackRange,
		attackInterval = bossCfg.AttackInterval,
		aggroRadius = 0,
		lastHitGold = 0,
		useProjectile = false,
		path = { home },
		pathIndex = 999,
		alive = true,
		nextAttackAt = 0,
		spawnPos = home,
		home = home,
		isBoss = true,
		aggroUserId = nil,
		nextSlamAt = 0,
	}
	self:_register(entry)
	if self.scoreService then
		self.scoreService:announce("The OVERLORD has awakened in the pit!", bossCfg.Buff.Color, 4)
	end
	return entry
end

-- Spawn everything for a fresh match. Boss arrives later (Config.Boss.SpawnDelay).
function JungleService:startSpawns()
	self:stopAndClear()
	self.generation = self.generation + 1
	self.running = true
	local gen = self.generation
	for i, camp in ipairs(Config.JungleCamps) do
		self:_spawnCamp(i, camp)
	end
	task.delay(Config.Boss.SpawnDelay, function()
		if self.running and self.generation == gen then
			self:_spawnBoss()
		end
	end)
end

function JungleService:stopAndClear()
	self.generation = self.generation + 1
	self.running = false
	for id, entry in pairs(self.entries) do
		if entry.model and entry.model.Parent then
			entry.model:Destroy()
		end
		self.minionService.minions[id] = nil
	end
	self.entries = {}
end

-- ===== Death + rewards ==================================================

function JungleService:onJungleKilled(entry, killerPlayer)
	if entry.model and entry.model.Parent then
		entry.model:Destroy()
	end
	self.minionService.minions[entry.id] = nil
	self.entries[entry.id] = nil

	local killerTeam = killerPlayer and self.matchController:teamOf(killerPlayer)
	if entry.isBoss then
		if killerTeam then
			local buff = Config.Boss.Buff
			for _, player in ipairs(Players:GetPlayers()) do
				if self.matchController:teamOf(player) == killerTeam then
					self.matchController:addGold(player, Config.Boss.GoldEach)
					self.combatService:addXP(player, Config.Boss.XPEach)
					self.combatService:applyTempBuff(player, buff.Label, buff.Stats, buff.Duration)
				end
			end
			if self.scoreService then
				self.scoreService:announce(
					("%s has slain the OVERLORD!"):format(killerTeam),
					buff.Color,
					4
				)
			end
		end
	elseif killerPlayer and killerTeam then
		local buff = Config.Jungle.Buffs[entry.buffKey]
		self.matchController:addGold(killerPlayer, Config.Jungle.Creep.Gold)
		self.combatService:applyTempBuff(killerPlayer, buff.Label, buff.Stats, buff.Duration)
		-- XP for the killer + any teammates near the camp.
		local pos = entry.home
		for _, player in ipairs(Players:GetPlayers()) do
			if self.matchController:teamOf(player) == killerTeam then
				local isKiller = player == killerPlayer
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				local near = root and (root.Position - pos).Magnitude <= Config.XP.ShareRadius
				if isKiller or near then
					self.combatService:addXP(player, Config.Jungle.Creep.XP)
				end
			end
		end
	end

	-- Respawn (guarded so a match reset cancels pending timers).
	local gen = self.generation
	local delay = entry.isBoss and Config.Boss.RespawnDelay or Config.Jungle.RespawnDelay
	task.delay(delay, function()
		if not self.running or self.generation ~= gen then
			return
		end
		if entry.isBoss then
			self:_spawnBoss()
		else
			local camp = Config.JungleCamps[entry.campIndex]
			if camp then
				self:_spawnCamp(entry.campIndex, camp)
			end
		end
	end)
end

-- ===== AI tick ==========================================================

local function flatDist(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Boss ground slam shockwave visual.
local function slamFX(pos, radius, color)
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.5, 2, 2)
	ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.1
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.5, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.6)
end

local function moveEntry(entry, targetPos, speed, dt)
	local pos = entry.root.Position
	local to = Vector3.new(targetPos.X - pos.X, 0, targetPos.Z - pos.Z)
	if to.Magnitude < 0.05 then
		return
	end
	local dir = to.Unit
	local step = math.min(to.Magnitude, speed * dt)
	local newPos = pos + dir * step
	entry.root.CFrame = CFrame.lookAt(newPos, newPos + dir)
end

local function syncHead(entry)
	if entry.head then
		entry.head.CFrame = entry.root.CFrame
			+ Vector3.new(0, entry.root.Size.Y / 2 + entry.head.Size.Y / 2, 0)
	end
end

local function updateHPFill(entry)
	local pct = math.clamp(entry.hp / math.max(entry.maxHP, 1), 0, 1)
	entry.hpFill.Size = UDim2.fromScale(pct, 1)
end

function JungleService:_tick(dt)
	local now = os.clock()
	for _, entry in pairs(self.entries) do
		if not entry.alive then
			continue
		end

		-- Resolve the current aggro target (must exist, be alive, in a match team).
		local target, targetRoot
		if entry.aggroUserId then
			local player = Players:GetPlayerByUserId(entry.aggroUserId)
			if player and self.matchController:teamOf(player) and self.combatService:isAlive(player) then
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root then
					target, targetRoot = player, root
				end
			end
			if not target then
				entry.aggroUserId = nil
			end
		end

		local homeDist = flatDist(entry.root.Position, entry.home)
		local leash = entry.isBoss and Config.Boss.LeashRange or Config.Jungle.LeashRange

		-- Leash: too far from home, or target ran outside the leash circle →
		-- give up, walk back, heal up.
		if target then
			local targetHomeDist = flatDist(targetRoot.Position, entry.home)
			if homeDist > leash or targetHomeDist > leash * 1.3 then
				entry.aggroUserId = nil
				target = nil
			end
		end

		if target then
			local dist = flatDist(entry.root.Position, targetRoot.Position)
			if dist > entry.attackRange then
				moveEntry(entry, targetRoot.Position, entry.walkSpeed, dt)
			else
				-- Face the target and swing.
				local pos = entry.root.Position
				entry.root.CFrame = CFrame.lookAt(pos, Vector3.new(targetRoot.Position.X, pos.Y, targetRoot.Position.Z))
				if now >= entry.nextAttackAt then
					entry.nextAttackAt = now + entry.attackInterval
					self.combatService:damagePlayer(target, entry.attackDamage, nil)
				end
			end
			-- Boss: periodic AoE slam on everyone nearby while in combat.
			if entry.isBoss and now >= (entry.nextSlamAt or 0) then
				entry.nextSlamAt = now + Config.Boss.SlamInterval
				slamFX(entry.root.Position, Config.Boss.SlamRadius, Config.Boss.Buff.Color)
				for _, player in ipairs(Players:GetPlayers()) do
					if self.matchController:teamOf(player) and self.combatService:isAlive(player) then
						local char = player.Character
						local root = char and char:FindFirstChild("HumanoidRootPart")
						if root and flatDist(root.Position, entry.root.Position) <= Config.Boss.SlamRadius then
							self.combatService:damagePlayer(player, Config.Boss.SlamDamage, nil)
						end
					end
				end
			end
		else
			-- No target: return home if away, and regenerate fast.
			if homeDist > 2 then
				moveEntry(entry, entry.home, entry.walkSpeed * 1.5, dt)
			end
			if entry.hp < entry.maxHP then
				entry.hp = math.min(entry.maxHP, entry.hp + entry.maxHP * 0.25 * dt)
				updateHPFill(entry)
			end
		end

		syncHead(entry)
	end
end

function JungleService:start()
	table.insert(self.connections, RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end))
end

function JungleService:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return JungleService
