-- PracticeService — runs "The Pit": the lobby's shared free-for-all warm-up
-- arena. Owns three things:
--
--   1. The target dummy (as before): registered as a special minion inside
--      MinionService so every existing damage path works unchanged; respawns
--      a few seconds after each kill.
--   2. Sparring bots: AI brawlers registered the same way (isPitBot = true,
--      team "Pit"). MinionService skips their AI tick; this service drives
--      them jungle-style — proximity-aggro onto Pit players, chase, attack
--      (melee or projectile), leash back home, heal while idle. They respect
--      the CC that abilities apply through MinionService (stun / slow / root /
--      knockback / pull / knockup) so crowd control can be practiced on a
--      moving target. Bot count scales with how many players are in the Pit.
--   3. FFA bookkeeping: Pit players are each their own one-man team, so all
--      combat paths already treat them as mutual enemies. Deaths in the Pit
--      are routed here by CombatService (instead of ScoreService) — kills pay
--      gold/XP, feed only Pit players' kill feeds, and rank on the in-world
--      PIT RANKINGS board that PracticeBuilder mounts on the arena wall.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PracticeBuilder = require(script.Parent:WaitForChild("PracticeBuilder"))

local PracticeService = {}
PracticeService.__index = PracticeService

local DUMMY_ID = -1
local BOT_ID_BASE = -300 -- bot ids: -301, -302, ... (never collides with lane/jungle ids)

local BOT_BODY = Color3.fromRGB(48, 44, 58)
local BOT_ACCENT = Color3.fromRGB(255, 140, 70)

local SPREE_LABEL = {
	[3] = "IS HEATING UP",
	[5] = "IS ON FIRE",
	[7] = "OWNS THE PIT",
}

function PracticeService.new(minionService, combatService, matchController)
	local self = setmetatable({}, PracticeService)
	self.minionService = minionService
	self.combatService = combatService
	self.matchController = matchController
	self.dummyEntry = nil
	self.playersInPit = {} -- userId -> true
	self.pitStats = {} -- userId -> { name, kills, botKills, deaths, spree }
	-- Fixed bot slots; each owns a home pad. Slot i is only (re)filled while
	-- i <= desired count, so the bot population breathes with the player count.
	self.botSlots = {}
	local homes = PracticeBuilder.getBotHomes()
	local seq = Config.Pit.BotSequence
	for i = 1, Config.Pit.BotMaxCount do
		self.botSlots[i] = {
			index = i,
			home = homes[((i - 1) % #homes) + 1],
			typeKey = seq[((i - 1) % #seq) + 1],
			entry = nil,
			respawnAt = 0,
		}
	end
	self.connections = {}
	return self
end

-- =====================================================================
-- Target dummy (unchanged behavior)
-- =====================================================================

local function attachBarBillboard(head, accent)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HPBar"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(100, 14)
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

local function buildDummyModel(spawnPos)
	local model = Instance.new("Model")
	model.Name = "PracticeDummy"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.CanCollide = true
	root.CanQuery = true
	root.CanTouch = false
	root.Size = Vector3.new(3, 4, 3)
	root.CFrame = CFrame.new(spawnPos + Vector3.new(0, 2, 0))
	root.Color = Color3.fromRGB(220, 90, 90)
	root.Material = Enum.Material.SmoothPlastic
	root.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Anchored = true
	head.CanCollide = false
	head.CanQuery = true
	head.Size = Vector3.new(1.6, 1.6, 1.6)
	head.CFrame = root.CFrame + Vector3.new(0, 2.8, 0)
	head.Color = Color3.fromRGB(220, 90, 90)
	head.Material = Enum.Material.SmoothPlastic
	head.Parent = model
	model.PrimaryPart = root

	-- Dummy is registered on team Red — red border so practice plays the same
	-- way as fighting an enemy minion.
	local fill = attachBarBillboard(head, Color3.fromRGB(255, 100, 100))
	return model, root, fill
end

local function getMinionBin()
	local bin = workspace:FindFirstChild("Minions")
	if not bin then
		bin = Instance.new("Folder")
		bin.Name = "Minions"
		bin.Parent = workspace
	end
	return bin
end

-- Spawn the dummy into the practice room. Reuses MinionService.minions so the
-- existing damage flow finds it via `minionService:getMinion(id)`.
function PracticeService:_spawnDummy()
	local maxHP = Config.PracticeDummyMaxHP
	local pos = PracticeBuilder.getDummyPos()
	local model, root, hpFill = buildDummyModel(pos)
	model:SetAttribute("MinionId", DUMMY_ID)
	model:SetAttribute("Team", "Red") -- enemy-side so any team can attack
	root:SetAttribute("MinionId", DUMMY_ID)
	root:SetAttribute("Team", "Red")
	model.Parent = getMinionBin()

	local entry = {
		id = DUMMY_ID,
		team = "Red",
		typeKey = "Dummy",
		model = model,
		root = root,
		hpFill = hpFill,
		maxHP = maxHP,
		hp = maxHP,
		walkSpeed = 0,
		attackDamage = 0,
		attackRange = 0,
		attackInterval = 99,
		aggroRadius = 0,
		goldReward = 0,
		useProjectile = false,
		path = { pos },
		pathIndex = 999, -- exhaust path so lane AI just stands
		alive = true,
		nextAttackAt = math.huge,
		spawnPos = pos,
		-- Captured at spawn so MinionService can return the dummy to the floor
		-- after a knockup parabola finishes.
		baseY = root.Position.Y,
		isDummy = true,
	}
	self.minionService.minions[DUMMY_ID] = entry
	self.dummyEntry = entry
	return entry
end

function PracticeService:ensureDummy()
	if self.dummyEntry and self.dummyEntry.alive and self.dummyEntry.model and self.dummyEntry.model.Parent then
		return
	end
	self:_spawnDummy()
end

-- Called from MinionService.applyDamage when the dummy hits 0 HP.
function PracticeService:onDummyKilled(entry)
	if entry.model then
		entry.model:Destroy()
	end
	self.minionService.minions[entry.id] = nil
	self.dummyEntry = nil
	task.delay(Config.PracticeDummyRespawnDelay, function()
		self:ensureDummy()
	end)
end

-- =====================================================================
-- Pit membership + rankings board
-- =====================================================================

function PracticeService:_statsFor(player)
	local s = self.pitStats[player.UserId]
	if not s then
		s = { name = player.DisplayName, kills = 0, botKills = 0, deaths = 0, spree = 0 }
		self.pitStats[player.UserId] = s
	end
	s.name = player.DisplayName
	return s
end

function PracticeService:_playerCount()
	local n = 0
	for _ in pairs(self.playersInPit) do
		n = n + 1
	end
	return n
end

function PracticeService:onPlayerEnteredPit(player)
	self.playersInPit[player.UserId] = true
	self:_statsFor(player)
	self:ensureDummy()
	self:_updateBoard()
end

-- Covers both "left the Pit" and "left the game" — safe no-op for non-Pit players.
function PracticeService:onPlayerLeftPit(player)
	if not self.playersInPit[player.UserId] then
		return
	end
	self.playersInPit[player.UserId] = nil
	local s = self.pitStats[player.UserId]
	if s then
		s.spree = 0
	end
	-- Bots holding aggro on the departed player drop it next tick (target
	-- validation fails); dead slots above the new desired count stay empty.
end

function PracticeService:_updateBoard()
	local room = workspace:FindFirstChild("PracticeRoom")
	local label = room and room:FindFirstChild("BoardText", true)
	if not label then
		return
	end
	local rows = {}
	for _, s in pairs(self.pitStats) do
		if s.kills > 0 or s.botKills > 0 or s.deaths > 0 then
			table.insert(rows, s)
		end
	end
	table.sort(rows, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		return a.botKills > b.botKills
	end)
	if #rows == 0 then
		label.Text = "Slay bots and brawlers to claim a spot."
		return
	end
	local lines = {}
	for i = 1, math.min(#rows, 8) do
		local s = rows[i]
		table.insert(lines, ("%d.  %s   —   %d duels  •  %d bots"):format(i, s.name, s.kills, s.botKills))
	end
	label.Text = table.concat(lines, "\n")
end

-- =====================================================================
-- FFA deaths (routed here by CombatService for practiceMode players)
-- =====================================================================

function PracticeService:_fireToPit(remoteName, ...)
	local remote = Remotes.get(remoteName)
	for uid in pairs(self.playersInPit) do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			remote:FireClient(p, ...)
		end
	end
end

function PracticeService:onPitPlayerDeath(victim, killer, _assistIds, respawnDelay)
	local vs = self:_statsFor(victim)
	vs.deaths = vs.deaths + 1
	vs.spree = 0

	local label = nil
	local killerSpree = 0
	if killer and self.playersInPit[killer.UserId] then
		local ks = self:_statsFor(killer)
		ks.kills = ks.kills + 1
		ks.spree = ks.spree + 1
		killerSpree = ks.spree
		self.matchController:addGold(killer, Config.Pit.PlayerKillGold)
		self.combatService:addXP(killer, Config.Pit.PlayerKillXP)
		if SPREE_LABEL[killerSpree] then
			label = ("%s %s! (%d)"):format(killer.DisplayName, SPREE_LABEL[killerSpree], killerSpree)
		end
	end

	-- Feed only Pit players — a lobby FFA scrap shouldn't spam an unrelated
	-- match's kill feed on a Studio all-in-one server.
	self:_fireToPit("KillFeed", {
		killerId = killer and killer.UserId or nil,
		killerName = killer and killer.DisplayName or nil,
		killerTeam = nil, -- FFA: no team colors in the feed
		victimId = victim.UserId,
		victimName = victim.DisplayName,
		victimTeam = nil,
		gold = killer and Config.Pit.PlayerKillGold or 0,
		label = label,
		spree = killerSpree,
	})
	Remotes.get("YouDied"):FireClient(victim, respawnDelay, killer and killer.DisplayName or "a sparring bot")
	self:_updateBoard()
end

-- =====================================================================
-- Sparring bots
-- =====================================================================

local function addBotPart(model, props)
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

-- A boxy training automaton with an ember visor. `details` are cosmetic parts
-- the AI tick repositions relative to the root each frame (cheap: 3 parts).
local function buildBotModel(typeKey, spawnPos, size)
	local model = Instance.new("Model")
	model.Name = "PitBot" .. typeKey

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.CanCollide = true
	root.CanQuery = true
	root.CanTouch = false
	root.Size = size
	root.CFrame = CFrame.new(spawnPos + Vector3.new(0, size.Y / 2, 0))
	root.Color = BOT_BODY
	root.Material = Enum.Material.Metal
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Parent = model
	model.PrimaryPart = root

	local headD = size.X * 0.6
	local head = addBotPart(model, {
		Name = "Head",
		CanQuery = true,
		Size = Vector3.new(headD, headD * 0.8, headD),
		CFrame = root.CFrame + Vector3.new(0, size.Y / 2 + headD * 0.4, 0),
		Color = BOT_BODY,
		Material = Enum.Material.Metal,
	})
	-- Ember visor strip — the "eyes".
	local visor = addBotPart(model, {
		Name = "Visor",
		Size = Vector3.new(headD * 0.8, headD * 0.2, 0.2),
		CFrame = head.CFrame * CFrame.new(0, headD * 0.05, -headD / 2),
		Color = BOT_ACCENT,
		Material = Enum.Material.Neon,
	})
	-- Antenna with a glowing tip so bots read from across the arena.
	local antenna = addBotPart(model, {
		Name = "Antenna",
		Size = Vector3.new(0.2, headD * 0.9, 0.2),
		CFrame = head.CFrame * CFrame.new(headD * 0.28, headD * 0.75, 0),
		Color = BOT_ACCENT,
		Material = Enum.Material.Neon,
	})

	local hpFill = attachBarBillboard(head, BOT_ACCENT)
	-- Local-space offsets the AI tick uses to carry cosmetics with the root.
	local details = {
		{ part = head, offset = CFrame.new(0, size.Y / 2 + headD * 0.4, 0) },
		{ part = visor, offset = CFrame.new(0, size.Y / 2 + headD * 0.45, -headD / 2) },
		{ part = antenna, offset = CFrame.new(headD * 0.28, size.Y / 2 + headD * 1.15, 0) },
	}
	return model, root, head, details, hpFill
end

function PracticeService:_desiredBotCount()
	local players = self:_playerCount()
	if players == 0 then
		return 0
	end
	return math.min(Config.Pit.BotMaxCount, Config.Pit.BotBaseCount + players - 1)
end

function PracticeService:_spawnBot(slot)
	local cfg = Config.Pit.Bots[slot.typeKey]
	local id = BOT_ID_BASE - slot.index
	local model, root, head, details, hpFill = buildBotModel(slot.typeKey, slot.home, cfg.Size)
	model:SetAttribute("MinionId", id)
	model:SetAttribute("Team", "Pit")
	root:SetAttribute("MinionId", id)
	root:SetAttribute("Team", "Pit")
	model.Parent = getMinionBin()

	local entry = {
		id = id,
		team = "Pit",
		typeKey = "PitBot",
		isPitBot = true,
		model = model,
		root = root,
		head = head,
		details = details,
		hpFill = hpFill,
		maxHP = cfg.MaxHP,
		hp = cfg.MaxHP,
		walkSpeed = cfg.WalkSpeed,
		attackDamage = cfg.AttackDamage,
		attackRange = cfg.AttackRange,
		attackInterval = cfg.AttackInterval,
		aggroRadius = cfg.AggroRadius,
		useProjectile = cfg.Projectile,
		projectileSpeed = cfg.ProjectileSpeed,
		projectileRadius = cfg.ProjectileRadius,
		projectileColor = BOT_ACCENT,
		alive = true,
		nextAttackAt = 0,
		home = slot.home,
		floorY = slot.home.Y + cfg.Size.Y / 2,
		slotIndex = slot.index,
		aggroUserId = nil,
	}
	self.minionService.minions[id] = entry
	slot.entry = entry
	return entry
end

-- Called from MinionService.applyDamage when a bot hits 0 HP.
function PracticeService:onBotKilled(entry, killerPlayer)
	if entry.model and entry.model.Parent then
		entry.model:Destroy()
	end
	self.minionService.minions[entry.id] = nil
	local slot = self.botSlots[entry.slotIndex]
	if slot and slot.entry == entry then
		slot.entry = nil
		slot.respawnAt = os.clock() + Config.Pit.BotRespawnDelay
	end

	if killerPlayer and self.playersInPit[killerPlayer.UserId] then
		local ks = self:_statsFor(killerPlayer)
		ks.botKills = ks.botKills + 1
		self.matchController:addGold(killerPlayer, Config.Pit.BotKillGold)
		self.combatService:addXP(killerPlayer, Config.Pit.BotKillXP)
		self:_updateBoard()
	end
end

-- =====================================================================
-- Bot AI tick
-- =====================================================================

local function flatDist(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Clamp a position to the practice-room interior.
local function clampToRoom(pos)
	local hx = Config.PracticeRoomSize.X / 2 - 3
	local hz = Config.PracticeRoomSize.Z / 2 - 3
	local o = Config.PracticeOrigin
	return Vector3.new(math.clamp(pos.X, o.X - hx, o.X + hx), pos.Y, math.clamp(pos.Z, o.Z - hz, o.Z + hz))
end

local function syncBotCosmetics(entry)
	for _, d in ipairs(entry.details) do
		d.part.CFrame = entry.root.CFrame * d.offset
	end
end

-- Resolve the bot's current aggro target: an alive Pit player within leash.
function PracticeService:_resolveBotTarget(entry)
	local function validate(uid)
		if not uid or not self.playersInPit[uid] then
			return nil
		end
		local player = Players:GetPlayerByUserId(uid)
		if not player or not self.combatService:isAlive(player) then
			return nil
		end
		local ce = self.combatService:getEntry(player)
		if not ce or not ce.practiceMode then
			return nil
		end
		if ce.selectingChampion then
			return nil -- still picking a champion — leave them alone
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then
			return nil
		end
		if flatDist(root.Position, entry.home) > Config.Pit.LeashRange * 1.2 then
			return nil -- target fled beyond the leash circle
		end
		return player, root
	end

	-- Keep the existing lock while it's valid (no aggro ping-pong).
	local player, root = validate(entry.aggroUserId)
	if player then
		return player, root
	end
	entry.aggroUserId = nil

	-- Fresh search: nearest Pit player inside the aggro radius.
	local best, bestRoot, bestDist
	for uid in pairs(self.playersInPit) do
		local p, r = validate(uid)
		if p then
			local d = flatDist(r.Position, entry.root.Position)
			if d <= entry.aggroRadius and (not bestDist or d < bestDist) then
				best, bestRoot, bestDist = p, r, d
			end
		end
	end
	if best then
		entry.aggroUserId = best.UserId
	end
	return best, bestRoot
end

function PracticeService:_tickBot(entry, dt, now)
	local root = entry.root

	-- Knockup: parabolic vertical offset above the floor; suspends everything else.
	if entry.ccVStartAt and entry.ccVDuration then
		local elapsed = now - entry.ccVStartAt
		if elapsed < entry.ccVDuration then
			local t = elapsed / entry.ccVDuration
			local y = entry.floorY + 4 * (entry.ccVHeight or 0) * t * (1 - t)
			local pos = root.Position
			root.CFrame = CFrame.new(Vector3.new(pos.X, y, pos.Z)) * (root.CFrame - root.CFrame.Position)
			syncBotCosmetics(entry)
			return
		end
		entry.ccVStartAt = nil
		local pos = root.Position
		root.CFrame = CFrame.new(Vector3.new(pos.X, entry.floorY, pos.Z)) * (root.CFrame - root.CFrame.Position)
	end

	-- Knockback / pull displacement window.
	if entry.ccHEndAt and now < entry.ccHEndAt and entry.ccHVel then
		local pos = root.Position
		local newPos = clampToRoom(pos + Vector3.new(entry.ccHVel.X * dt, 0, entry.ccHVel.Z * dt))
		root.CFrame = CFrame.new(newPos) * (root.CFrame - root.CFrame.Position)
		syncBotCosmetics(entry)
		return
	end

	-- Stun: frozen in place.
	if entry.ccStunUntil and now < entry.ccStunUntil then
		syncBotCosmetics(entry)
		return
	end

	local target, targetRoot = self:_resolveBotTarget(entry)
	local homeDist = flatDist(root.Position, entry.home)

	-- Leash: wandered too far → drop aggro and go home.
	if target and homeDist > Config.Pit.LeashRange then
		entry.aggroUserId = nil
		target, targetRoot = nil, nil
	end

	local rooted = entry.ccRootUntil and now < entry.ccRootUntil
	local speed = entry.walkSpeed
	if entry.ccSlow then
		if entry.ccSlow.expiresAt <= now then
			entry.ccSlow = nil
		else
			speed = speed * (1 - entry.ccSlow.magnitude)
		end
	end

	local function stepToward(destPos, moveSpeed)
		local pos = root.Position
		local to = Vector3.new(destPos.X - pos.X, 0, destPos.Z - pos.Z)
		if to.Magnitude < 0.05 then
			return
		end
		local dir = to.Unit
		-- Light separation from other bots so they don't stack on one target.
		local sep = Vector3.zero
		for _, slot in ipairs(self.botSlots) do
			local other = slot.entry
			if other and other ~= entry and other.alive then
				local delta = pos - other.root.Position
				delta = Vector3.new(delta.X, 0, delta.Z)
				local d = delta.Magnitude
				if d > 0.001 and d < 5 then
					sep = sep + delta.Unit * (1 - d / 5)
				end
			end
		end
		local combined = dir + sep * 0.8
		if combined.Magnitude > 0.001 then
			combined = combined.Unit
		else
			combined = dir
		end
		local step = math.min(to.Magnitude, moveSpeed * dt)
		local newPos = clampToRoom(pos + combined * step)
		root.CFrame = CFrame.lookAt(newPos, newPos + dir)
	end

	if target then
		local dist = flatDist(root.Position, targetRoot.Position)
		if dist > entry.attackRange then
			if not rooted then
				stepToward(targetRoot.Position, speed)
			end
		else
			-- Face the target and swing.
			local pos = root.Position
			root.CFrame = CFrame.lookAt(pos, Vector3.new(targetRoot.Position.X, pos.Y, targetRoot.Position.Z))
			if now >= entry.nextAttackAt then
				entry.nextAttackAt = now + entry.attackInterval
				if entry.useProjectile then
					self.minionService:fireBotProjectile(entry, target)
				else
					self.combatService:damagePlayer(target, entry.attackDamage, nil)
				end
			end
		end
	else
		-- Idle: walk home and regenerate fast.
		if homeDist > 2 and not rooted then
			stepToward(entry.home, speed * 1.4)
		end
		if entry.hp < entry.maxHP then
			entry.hp = math.min(entry.maxHP, entry.hp + entry.maxHP * 0.25 * dt)
			entry.hpFill.Size = UDim2.fromScale(math.clamp(entry.hp / entry.maxHP, 0, 1), 1)
		end
	end

	syncBotCosmetics(entry)
end

function PracticeService:_tick(dt)
	local now = os.clock()
	local desired = self:_desiredBotCount()
	for i, slot in ipairs(self.botSlots) do
		local entry = slot.entry
		if entry and entry.alive then
			self:_tickBot(entry, dt, now)
		elseif i <= desired and now >= slot.respawnAt then
			self:_spawnBot(slot)
		end
	end
end

function PracticeService:start()
	table.insert(self.connections, RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end))
end

function PracticeService:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return PracticeService
