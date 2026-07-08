local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Champions = require(Shared:WaitForChild("Champions"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local CombatService = {}
CombatService.__index = CombatService

function CombatService.new(matchController)
	local self = setmetatable({}, CombatService)
	self.matchController = matchController
	self.minionService = nil
	self.towerService = nil
	self.players = {}
	self.connections = {}
	return self
end

function CombatService:setMinionService(svc)
	self.minionService = svc
end

function CombatService:setTowerService(svc)
	self.towerService = svc
end

function CombatService:setRecallService(svc)
	self.recallService = svc
end

function CombatService:setScoreService(svc)
	self.scoreService = svc
end

function CombatService:setPracticeService(svc)
	self.practiceService = svc
end

local function newEntry(maxHP, walkSpeed)
	return {
		hp = maxHP,
		maxHP = maxHP,
		baseSpeed = walkSpeed,
		speedMult = 1,
		speedUntil = 0,
		cooldowns = {},
		deadUntil = 0,
		alive = true,
		target = nil,
		nextAutoAttackAt = 0,

		-- Champion-select gate. While true, ability casts and movement are
		-- blocked until the player picks a champion.
		selectingChampion = false,
		championKey = nil,

		-- In-match progression. Level scales max HP and damage (see
		-- Config.Leveling); XP is intra-level progress toward xpToNext.
		level = 1,
		xp = 0,

		-- Timed stat buffs (jungle camps, boss). Each: { key, stats, expiresAt }.
		-- Expired entries are pruned lazily inside bonusOf/tempStat.
		tempBuffs = {},

		-- Kill attribution: enemies who damaged this player recently
		-- ([userId] = window-expiry clock time) + who hit them last. Drives
		-- kill credit for tower/minion/DoT deaths and assist payouts.
		recentDamagers = {},
		lastDamager = nil,
		-- Respawn delay captured at the moment of death (scales with match time).
		respawnDelay = nil,
		-- Set for players in the practice room (changes recall destination /
		-- shop gating).
		practiceMode = false,

		-- Status effects:
		statuses = {
			-- slow = { magnitude=0..1, expiresAt },
			-- stun = { expiresAt },
			-- root = { expiresAt },
			-- invisible = { expiresAt },
			-- damageReduction = { multiplier, expiresAt },
		},
		shield = 0, -- absorb pool
		shieldUntil = 0,
		dots = {}, -- list of { damagePerTick, interval, ticksLeft, nextTickAt, source }
		hots = {}, -- list of { healPerTick, interval, ticksLeft, nextTickAt }
		attackBuff = nil, -- { bonusMult, expiresAt } — empowers next auto-attack
	}
end

-- Sum a stat across ONLY the timed buffs (jungle/boss). Prunes expired
-- entries as it walks. Kept separate from bonusOf because MoveSpeedPct from
-- runes/items is already baked into baseSpeed — temp move speed must not be.
local function tempStat(e, key)
	local buffs = e.tempBuffs
	if not buffs or #buffs == 0 then
		return 0
	end
	local now = os.clock()
	local total = 0
	for i = #buffs, 1, -1 do
		local b = buffs[i]
		if b.expiresAt <= now then
			table.remove(buffs, i)
		elseif b.stats[key] then
			total = total + b.stats[key]
		end
	end
	return total
end

-- Sum a stat across a player's rune bonuses (entry.bonuses), item bonuses
-- (entry.itemBonuses, set by ShopService), and timed buffs. All optional.
local function bonusOf(e, key)
	local r = (e.bonuses and e.bonuses[key]) or 0
	local i = (e.itemBonuses and e.itemBonuses[key]) or 0
	return r + i + tempStat(e, key)
end

function CombatService:register(player, maxHP, walkSpeed)
	self.players[player.UserId] = newEntry(maxHP, walkSpeed)
end

function CombatService:unregister(player)
	self.players[player.UserId] = nil
end

function CombatService:getEntry(player)
	return self.players[player.UserId]
end

function CombatService:isAlive(player)
	local e = self.players[player.UserId]
	return e and e.alive or false
end

-- Public stat lookup for other services (AbilityHandler reads AbilityPowerPct
-- here so runes + items + timed buffs all funnel through one place).
function CombatService:statBonus(player, key)
	local e = self.players[player.UserId]
	if not e then
		return 0
	end
	return bonusOf(e, key)
end

-- Grant a timed stat buff (jungle camp / boss). Re-applying the same key
-- refreshes rather than stacks. Fires StatusEffectChanged so the HUD shows a
-- labeled countdown.
function CombatService:applyTempBuff(player, key, stats, duration)
	local e = self.players[player.UserId]
	if not e or not e.alive then
		return
	end
	for _, b in ipairs(e.tempBuffs) do
		if b.key == key then
			b.stats = stats
			b.expiresAt = os.clock() + duration
			Remotes.get("StatusEffectChanged"):FireClient(player, key, { duration = duration })
			return
		end
	end
	table.insert(e.tempBuffs, { key = key, stats = stats, expiresAt = os.clock() + duration })
	Remotes.get("StatusEffectChanged"):FireClient(player, key, { duration = duration })
end

-- Recompute stats derived from champion + level + items + runes (max HP and
-- base walk speed). Called on champion pick, level up, and item purchase.
-- Raising max HP also heals the gain so you never "lose" the HP you earned.
function CombatService:recomputeDerived(player)
	local e = self.players[player.UserId]
	local champ = e and e.championKey and Champions.Roster[e.championKey]
	if not champ then
		return
	end
	local ib = e.itemBonuses or {}
	local runeMS = (e.bonuses and e.bonuses.MoveSpeedPct) or 0
	local newMax = math.floor(champ.MaxHP * Config.levelHPMult(e.level) + (ib.BonusMaxHP or 0) + 0.5)
	local oldMax = e.maxHP or newMax
	if newMax ~= oldMax then
		e.maxHP = newMax
		if e.alive then
			e.hp = math.min(newMax, e.hp + math.max(0, newMax - oldMax))
		else
			e.hp = math.min(e.hp, newMax)
		end
		self:replicateHP(player)
	end
	e.baseSpeed = champ.WalkSpeed * (1 + (runeMS + (ib.MoveSpeedPct or 0)) / 100)
end

-- Update the level shown in the server-built nameplate billboard.
local function updateNameplateLevel(player, level)
	local char = player.Character
	if not char then
		return
	end
	char:SetAttribute("Level", level)
	local head = char:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("TeamTag")
	local label = tag and tag:FindFirstChildOfClass("TextLabel")
	if label then
		label.Text = ("[%d] %s"):format(level, player.DisplayName)
	end
end

-- Award XP, handling level-ups (stat growth + broadcast). XP past the level
-- cap is discarded.
function CombatService:addXP(player, amount)
	local e = self.players[player.UserId]
	if not e or not amount or amount <= 0 then
		return
	end
	local maxLevel = Config.Leveling.MaxLevel
	if e.level >= maxLevel then
		return
	end
	e.xp = e.xp + amount
	local leveled = false
	while e.level < maxLevel and e.xp >= Config.xpToNext(e.level) do
		e.xp = e.xp - Config.xpToNext(e.level)
		e.level = e.level + 1
		leveled = true
	end
	if e.level >= maxLevel then
		e.xp = 0
	end
	if leveled then
		self:recomputeDerived(player)
		updateNameplateLevel(player, e.level)
		Remotes.get("LevelUp"):FireAllClients(player.UserId, e.level)
	end
	local toNext = (e.level >= maxLevel) and 0 or Config.xpToNext(e.level)
	Remotes.get("XPChanged"):FireClient(player, e.level, e.xp, toNext)
end

function CombatService:isLocked(player)
	-- Champion-select / stun / root all prevent movement & casts.
	local e = self.players[player.UserId]
	if not e then
		return false
	end
	if e.selectingChampion then
		return true
	end
	local now = os.clock()
	if e.statuses.stun and e.statuses.stun.expiresAt > now then
		return true
	end
	return false
end

function CombatService:replicateHP(player)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	Remotes.get("HPChanged"):FireClient(player, e.hp, e.maxHP, e.alive)
end

function CombatService:replicateShield(player)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	Remotes.get("ShieldChanged"):FireClient(player, e.shield)
end

function CombatService:setTarget(player, targetType, targetId)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	if targetType == nil or targetId == nil then
		e.target = nil
		return
	end
	if targetType ~= "minion" and targetType ~= "player" and targetType ~= "tower" then
		return
	end
	e.target = { type = targetType, id = targetId }
end

function CombatService:onTargetRemoved(targetType, targetId)
	for _, e in pairs(self.players) do
		if e.target and e.target.type == targetType and e.target.id == targetId then
			e.target = nil
		end
	end
end

-- ===== Damage and healing =====

function CombatService:damagePlayer(target, amount, attackerPlayer)
	local e = self.players[target.UserId]
	if not e or not e.alive then
		return
	end
	-- Champion-select is a safe pause: the player can't move or fight back yet
	-- (matters in The Pit, where hostile players/bots share the room).
	if e.selectingChampion then
		return
	end
	-- Damage reduction (e.g. Iron Skin)
	local now = os.clock()
	if e.statuses.damageReduction and e.statuses.damageReduction.expiresAt > now then
		amount = amount * e.statuses.damageReduction.multiplier
	end
	-- Flat-percent armor from tank items (stacks multiplicatively with the above).
	local drPct = math.clamp(bonusOf(e, "DamageReductionPct"), 0, 80)
	if drPct > 0 then
		amount = amount * (1 - drPct / 100)
	end
	-- Shield absorbs first.
	if e.shield > 0 and e.shieldUntil > now then
		local absorbed = math.min(e.shield, amount)
		e.shield = e.shield - absorbed
		amount = amount - absorbed
		self:replicateShield(target)
	end
	if amount <= 0 then
		return
	end
	-- Out-of-combat marker (drives the Pit's regen gating).
	e.lastDamagedAt = now
	-- Kill/assist attribution: remember enemy champions who damaged this
	-- player recently. Tower/minion/DoT executions credit the last of these.
	if attackerPlayer and attackerPlayer ~= target and self.matchController then
		local aTeam = self.matchController:teamOf(attackerPlayer)
		local vTeam = self.matchController:teamOf(target)
		if aTeam and vTeam and aTeam ~= vTeam then
			e.recentDamagers[attackerPlayer.UserId] = now + Config.Kill.AssistWindow
			e.lastDamager = attackerPlayer.UserId
		end
	end
	e.hp = math.max(0, e.hp - amount)
	self:replicateHP(target)
	-- Taking damage cancels an in-progress recall channel.
	if self.recallService then
		self.recallService:onDamageTaken(target)
	end
	-- Broadcast for damage-number / hit-flash visualization.
	local char = target.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		Remotes.get("DamageDealt"):FireAllClients(root.Position + Vector3.new(0, 3, 0), amount, target.UserId)
	end
	if attackerPlayer and self.towerService then
		self.towerService:onPlayerAttackedPlayer(attackerPlayer, target)
	end
	if e.hp <= 0 then
		e.alive = false
		-- Kill credit: the direct attacker if it was a champion, otherwise the
		-- last champion who damaged them recently (tower/minion/DoT executes).
		local killer = attackerPlayer
		if not killer and e.lastDamager and (e.recentDamagers[e.lastDamager] or 0) > now then
			killer = Players:GetPlayerByUserId(e.lastDamager)
		end
		local assistIds = {}
		for uid, expiresAt in pairs(e.recentDamagers) do
			if expiresAt > now and (not killer or uid ~= killer.UserId) then
				table.insert(assistIds, uid)
			end
		end
		e.recentDamagers = {}
		e.lastDamager = nil
		-- Death timer scales with match time; captured now so the death screen
		-- countdown and the actual respawn agree. Pit deaths use a short fixed
		-- timer instead — the Pit is for action, not waiting.
		if e.practiceMode then
			e.respawnDelay = Config.Pit.RespawnDelay
		else
			e.respawnDelay = (self.scoreService and self.scoreService:currentRespawnDelay()) or Config.RespawnDelay
		end
		e.deadUntil = now + e.respawnDelay
		-- Clear all statuses (and timed buffs — you lose those on death).
		e.statuses = {}
		e.dots = {}
		e.hots = {}
		e.shield = 0
		e.shieldUntil = 0
		e.attackBuff = nil
		e.tempBuffs = {}
		if char then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = 0
			end
		end
		self:onTargetRemoved("player", target.UserId)
		-- Pit deaths route to PracticeService (Pit-only kill feed + rankings
		-- board) so a lobby brawl never pollutes real match stats.
		if e.practiceMode and self.practiceService then
			self.practiceService:onPitPlayerDeath(target, killer, assistIds, e.respawnDelay)
		elseif self.scoreService then
			self.scoreService:onChampionDeath(target, killer, assistIds, e.respawnDelay)
		end
	end
end

function CombatService:healPlayer(target, amount)
	local e = self.players[target.UserId]
	if not e or not e.alive then
		return
	end
	e.hp = math.min(e.maxHP, e.hp + amount)
	self:replicateHP(target)
end

-- ===== Status-effect application =====

function CombatService:applySlow(player, magnitude, duration)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	e.statuses.slow = { magnitude = magnitude, expiresAt = os.clock() + duration }
	Remotes.get("StatusEffectChanged"):FireClient(player, "slow", { magnitude = magnitude, duration = duration })
end

function CombatService:applyStun(player, duration)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	e.statuses.stun = { expiresAt = os.clock() + duration }
	Remotes.get("StatusEffectChanged"):FireClient(player, "stun", { duration = duration })
end

function CombatService:applyRoot(player, duration)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	e.statuses.root = { expiresAt = os.clock() + duration }
	Remotes.get("StatusEffectChanged"):FireClient(player, "root", { duration = duration })
end

function CombatService:applyShield(player, amount, duration)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	e.shield = amount
	e.shieldUntil = os.clock() + duration
	self:replicateShield(player)
end

function CombatService:applyInvisibility(player, duration)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	e.statuses.invisible = { expiresAt = os.clock() + duration }
	Remotes.get("StatusEffectChanged"):FireClient(player, "invisible", { duration = duration })
	-- Replicate via an attribute on the character so clients can hide it.
	local char = player.Character
	if char then
		char:SetAttribute("Invisible", true)
		task.delay(duration, function()
			if char and char.Parent then
				char:SetAttribute("Invisible", false)
			end
		end)
	end
end

function CombatService:applyDamageReduction(player, multiplier, duration)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	e.statuses.damageReduction = { multiplier = multiplier, expiresAt = os.clock() + duration }
	Remotes.get("StatusEffectChanged"):FireClient(player, "damageReduction", {
		multiplier = multiplier,
		duration = duration,
	})
end

function CombatService:applyDoT(target, damagePerTick, interval, ticks, source)
	local e = self.players[target.UserId]
	if not e or not e.alive then
		return
	end
	table.insert(e.dots, {
		damagePerTick = damagePerTick,
		interval = interval,
		ticksLeft = ticks,
		nextTickAt = os.clock() + interval,
		source = source,
	})
end

function CombatService:applyHoT(player, healPerTick, interval, ticks)
	local e = self.players[player.UserId]
	if not e or not e.alive then
		return
	end
	table.insert(e.hots, {
		healPerTick = healPerTick,
		interval = interval,
		ticksLeft = ticks,
		nextTickAt = os.clock() + interval,
	})
end

function CombatService:setAttackBuff(player, bonusMult, duration)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	e.attackBuff = { bonusMult = bonusMult, expiresAt = os.clock() + duration }
end

function CombatService:applyKnockup(target, height, duration)
	-- Knockup = brief stun + vertical velocity blip. Anchored characters don't
	-- exist here (Humanoid-controlled), so we use AssemblyLinearVelocity.
	self:applyStun(target, duration)
	local char = target.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, height / math.max(duration, 0.01), 0)
	end
end

function CombatService:applyKnockback(target, fromPos, distance)
	-- Push target away from fromPos by `distance` studs over a short duration.
	local char = target.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local dir = root.Position - fromPos
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then
		return
	end
	dir = dir.Unit
	local duration = 0.25
	root.AssemblyLinearVelocity = Vector3.new(dir.X, 0.5, dir.Z) * (distance / duration)
	self:applyStun(target, duration)
end

function CombatService:applyPull(target, towardPos, distance)
	-- Inverse of knockback — pull target toward `towardPos`.
	local char = target.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local dir = towardPos - root.Position
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.01 then
		return
	end
	dir = dir.Unit
	local duration = 0.25
	root.AssemblyLinearVelocity = Vector3.new(dir.X, 0.5, dir.Z) * (distance / duration)
	self:applyStun(target, duration * 0.5)
end

-- ===== Cooldowns =====

function CombatService:applySpeedBuff(player, multiplier, duration)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	e.speedMult = multiplier
	e.speedUntil = os.clock() + duration
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = e.baseSpeed * e.speedMult
	end
end

function CombatService:startCooldown(player, slot, duration)
	local e = self.players[player.UserId]
	if not e then
		return
	end
	e.cooldowns[slot] = os.clock() + duration
	Remotes.get("AbilityCooldownChanged"):FireClient(player, slot, duration)
end

function CombatService:isReady(player, slot)
	local e = self.players[player.UserId]
	if not e then
		return false
	end
	return (e.cooldowns[slot] or 0) <= os.clock()
end

-- ===== Tick =====

local function resolveTargetPos(self, target)
	if target.type == "minion" then
		local m = self.minionService and self.minionService:getMinion(target.id)
		if not m or not m.alive then
			return nil
		end
		return m.root.Position, m
	elseif target.type == "player" then
		local player = Players:GetPlayerByUserId(target.id)
		if not player then
			return nil
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local e = self.players[target.id]
		if not root or not e or not e.alive then
			return nil
		end
		return root.Position, { player = player }
	elseif target.type == "tower" then
		local t = self.towerService and self.towerService:getTower(target.id)
		if not t or not t.alive then
			return nil
		end
		return t.root.Position, t
	end
	return nil
end

-- Compute the WalkSpeed a player's humanoid should be set to, given current
-- statuses (stun/root/slow) and active buffs. Returns 0 if hard-locked.
-- Auto-attack wind-up DOES NOT lock movement — it's a charge timer that
-- the player can interrupt by moving (see the tick body).
local function effectiveWalkSpeed(e, now)
	if e.selectingChampion then
		return 0
	end
	if e.statuses.stun and e.statuses.stun.expiresAt > now then
		return 0
	end
	if e.statuses.root and e.statuses.root.expiresAt > now then
		return 0
	end
	local base = e.baseSpeed * e.speedMult
	-- Timed buffs only — rune/item move speed is already baked into baseSpeed.
	local buffMS = tempStat(e, "MoveSpeedPct")
	if buffMS ~= 0 then
		base = base * (1 + buffMS / 100)
	end
	if e.statuses.slow and e.statuses.slow.expiresAt > now then
		base = base * (1 - e.statuses.slow.magnitude)
	end
	return base
end

function CombatService:_tick(dt)
	local now = os.clock()
	dt = dt or 0
	for userId, e in pairs(self.players) do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			continue
		end

		-- Expire transient statuses.
		for k, status in pairs(e.statuses) do
			if status.expiresAt and now >= status.expiresAt then
				e.statuses[k] = nil
				Remotes.get("StatusEffectChanged"):FireClient(player, k, { ended = true })
			end
		end
		if e.shield > 0 and now >= e.shieldUntil then
			e.shield = 0
			self:replicateShield(player)
		end

		-- Speed buff (Sprint summoner) expiry.
		if e.speedMult ~= 1 and now >= e.speedUntil then
			e.speedMult = 1
		end

		-- Expire attack buffs that no auto-attack got to consume (e.g. Headshot
		-- ran out before the next shot landed).
		if e.attackBuff and now >= e.attackBuff.expiresAt then
			e.attackBuff = nil
		end

		-- Apply current effective walk speed to the humanoid.
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid and e.alive then
			humanoid.WalkSpeed = effectiveWalkSpeed(e, now)
		end

		-- Damage-over-time
		for i = #e.dots, 1, -1 do
			local dot = e.dots[i]
			while now >= dot.nextTickAt and dot.ticksLeft > 0 and e.alive do
				dot.ticksLeft = dot.ticksLeft - 1
				dot.nextTickAt = dot.nextTickAt + dot.interval
				self:damagePlayer(player, dot.damagePerTick, dot.source)
			end
			if dot.ticksLeft <= 0 then
				table.remove(e.dots, i)
			end
		end
		-- Heal-over-time
		for i = #e.hots, 1, -1 do
			local hot = e.hots[i]
			while now >= hot.nextTickAt and hot.ticksLeft > 0 and e.alive do
				hot.ticksLeft = hot.ticksLeft - 1
				hot.nextTickAt = hot.nextTickAt + hot.interval
				self:healPlayer(player, hot.healPerTick)
			end
			if hot.ticksLeft <= 0 then
				table.remove(e.hots, i)
			end
		end

		-- Passive HP regen by champion class — one discrete tick every
		-- Champions.ClassRegenInterval seconds. The regen always adds the full
		-- class amount and caps at maxHP via math.min, so 498/500 + tank's 8
		-- regen → 500/500 (the extra 6 is just absorbed by the cap). Players
		-- never get "stuck" near full HP; the last few points always heal in.
		if e.alive and e.championKey then
			local champ = Champions.Roster[e.championKey]
			local regenAmount = (champ and Champions.ClassRegen[champ.Class]) or 0
			if regenAmount > 0 then
				local interval = Champions.ClassRegenInterval or 5
				if not e.nextRegenAt then
					-- First tick after spawn / champion pick fires `interval`
					-- seconds from now.
					e.nextRegenAt = now + interval
				elseif now >= e.nextRegenAt then
					e.nextRegenAt = now + interval
					if e.hp < e.maxHP then
						local before = e.hp
						e.hp = math.min(e.maxHP, e.hp + regenAmount)
						if e.hp ~= before then
							self:replicateHP(player)
						end
					end
				end
			end
		end

		-- Auto-attack on locked target. Class-driven baseline stats with
		-- per-champion overrides (range / style / travel / color).
		if e.alive and e.target and not e.selectingChampion then
			local pos, ref = resolveTargetPos(self, e.target)
			if not pos then
				e.target = nil
				Remotes.get("TargetCleared"):FireClient(player)
			else
				local championKey = e.championKey or "Pyromancer"
				local profile = Champions.getAutoAttackProfile(championKey)
				local style = profile.Style
				local color = profile.Color
				local travelTime = profile.TravelTime or 0
				local attackRange = profile.Range or Config.AutoAttack.Range
				local attackInterval = profile.Interval or Config.AutoAttack.Interval
				-- Attack-speed bonus (runes + items) shortens the interval.
				local asPct = math.clamp(bonusOf(e, "AttackSpeedPct"), 0, 60)
				if asPct > 0 then
					attackInterval = attackInterval * (1 - asPct / 100)
				end
				local windUpDuration = profile.WindUp or 0.2
				-- Champion level scales the base hit; flat attack power (runes +
				-- items + buffs) is added on top.
				local baseDamage = (profile.Damage or Config.AutoAttack.Damage) * Config.levelDamageMult(e.level)
					+ bonusOf(e, "AttackPower")
				local root = char and char:FindFirstChild("HumanoidRootPart")
				-- Wind-up is a CHARGE timer: starts when the player stops moving,
				-- cancels the moment they start moving again. Only when stillness
				-- has been held for the full wind-up AND the cooldown is up does
				-- the attack actually fire. There's no movement lock — the player
				-- can interrupt their own attack at any time by walking.
				local moveDir = humanoid and humanoid.MoveDirection or Vector3.new()
				local isStill = moveDir.Magnitude < 0.05
				if not isStill then
					e.attackChargingSince = nil
				elseif not e.attackChargingSince then
					e.attackChargingSince = now
				end

				-- Measure to the SURFACE of a tower base, not its center, so a
				-- melee champion (range 9) can hit a tower whose base cylinder is
				-- 11–17 studs in radius. Without this subtraction the melee tank's
				-- attack range never reaches the tower's hit point.
				local rawDist = root and (pos - root.Position).Magnitude or math.huge
				if e.target.type == "tower" and ref and ref.root then
					rawDist = math.max(0, rawDist - ref.root.Size.Y / 2)
				end
				local inRange = root and rawDist <= attackRange
				local charged = e.attackChargingSince and (now - e.attackChargingSince) >= windUpDuration
				if inRange and isStill and charged then
					if now >= e.nextAutoAttackAt then
						e.nextAutoAttackAt = now + attackInterval
						-- Restart the charge timer — the next attack also needs
						-- its own full wind-up of stillness.
						e.attackChargingSince = now
						local dmg = baseDamage
						-- Attack buff (e.g. Headshot) empowers and consumes itself on next shot.
						if e.attackBuff and e.attackBuff.expiresAt > now then
							dmg = dmg * e.attackBuff.bonusMult
							e.attackBuff = nil
						end
						-- Fire the visual event NOW so the projectile/slash starts immediately on every client.
						Remotes.get("AutoAttackFired"):FireAllClients(
							"player",
							userId,
							e.target.type,
							e.target.id,
							style,
							color,
							travelTime
						)

						-- Apply damage after the travel-time delay so HP drops
						-- when the visual "arrives". Re-validates target still
						-- exists and the attacker isn't dead — otherwise drop.
						local target = e.target
						local snapshotRef = ref
						local applyDamageNow = function()
							if not self.players[userId] or not self.players[userId].alive then
								return
							end
							if target.type == "minion" then
								if snapshotRef.alive then
									self.minionService:applyDamage(snapshotRef, dmg, player)
								end
							elseif target.type == "player" then
								if snapshotRef.player and snapshotRef.player.Parent then
									self:damagePlayer(snapshotRef.player, dmg, player)
								end
							elseif target.type == "tower" then
								if snapshotRef.alive then
									self.towerService:applyDamage(snapshotRef, dmg, player)
								end
							end
						end
						if travelTime <= 0 then
							applyDamageNow()
						else
							task.delay(travelTime, applyDamageNow)
						end
					end
				end
			end
		end
	end
end

function CombatService:start()
	table.insert(self.connections, RunService.Heartbeat:Connect(function(dt)
		self:_tick(dt)
	end))
end

function CombatService:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return CombatService
