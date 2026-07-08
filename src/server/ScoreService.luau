-- ScoreService — the match's reward + feedback loop. Owns per-player match
-- stats (K/D/A, creep score, gold earned), team kill counters, the match
-- clock, and every kill-related payout: kill/assist gold, first blood,
-- shutdown bounties, multikill + spree labels, and XP from minions, towers,
-- and takedowns. Everything resets per match via resetMatch().
--
-- Broadcast surface (see Remotes.luau): KillFeed, TeamScoreChanged,
-- MatchClock, MatchStats, YouDied, Announce.

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ScoreService = {}
ScoreService.__index = ScoreService

local MULTIKILL_LABEL = {
	[2] = "DOUBLE KILL!",
	[3] = "TRIPLE KILL!",
	[4] = "QUADRA KILL!",
	[5] = "PENTA KILL!",
}

local SPREE_LABEL = {
	[3] = "KILLING SPREE",
	[5] = "RAMPAGE",
	[7] = "UNSTOPPABLE",
}

function ScoreService.new(matchController, combatService)
	local self = setmetatable({}, ScoreService)
	self.matchController = matchController
	self.combatService = combatService
	self:resetMatch()
	return self
end

function ScoreService:resetMatch()
	self.stats = {} -- userId -> { name, team, champion, kills, deaths, assists, cs, gold }
	self.teamKills = { Blue = 0, Red = 0 }
	self.firstBloodTaken = false
	self.sprees = {} -- userId -> current kill streak (resets on death)
	self.multikills = {} -- userId -> { count, lastAt }
	self.matchStartAt = nil -- os.clock() when combat actually began
	self.startServerTime = nil -- GetServerTimeNow() equivalent, for client clocks
	self._statsDirty = false
end

-- Called when the match's combat actually kicks off (towers + waves started).
function ScoreService:onMatchBegin()
	self.matchStartAt = os.clock()
	self.startServerTime = workspace:GetServerTimeNow()
	Remotes.get("MatchClock"):FireAllClients(self.startServerTime)
	self:_broadcastScore()
	self:_broadcastStats()
end

-- Late arrivals (reserved-server stragglers) need the clock + current state.
function ScoreService:sendSnapshotTo(player)
	if self.startServerTime then
		Remotes.get("MatchClock"):FireClient(player, self.startServerTime)
	end
	Remotes.get("TeamScoreChanged"):FireClient(player, {
		Blue = self.teamKills.Blue,
		Red = self.teamKills.Red,
	})
	Remotes.get("MatchStats"):FireClient(player, self:_statsArray())
end

function ScoreService:elapsed()
	if not self.matchStartAt then
		return 0
	end
	return os.clock() - self.matchStartAt
end

-- Death timer for a death happening right now (grows with match time).
function ScoreService:currentRespawnDelay()
	local minutes = self:elapsed() / 60
	return math.min(Config.RespawnDelay + Config.Respawn.PerMinute * minutes, Config.Respawn.Max)
end

function ScoreService:_entryFor(player)
	local s = self.stats[player.UserId]
	if not s then
		s = {
			userId = player.UserId,
			name = player.DisplayName,
			team = nil,
			champion = nil,
			kills = 0,
			deaths = 0,
			assists = 0,
			cs = 0,
			gold = 0,
		}
		self.stats[player.UserId] = s
	end
	s.team = self.matchController:teamOf(player) or s.team
	return s
end

function ScoreService:setChampion(player, championKey)
	self:_entryFor(player).champion = championKey
	self:_markStatsDirty()
end

-- Called by MatchController on every positive gold award so the scoreboard's
-- "gold earned" column stays truthful.
function ScoreService:onGoldEarned(player, amount)
	self:_entryFor(player).gold = self:_entryFor(player).gold + amount
	self:_markStatsDirty()
end

function ScoreService:_statsArray()
	local out = {}
	for _, s in pairs(self.stats) do
		table.insert(out, s)
	end
	return out
end

function ScoreService:_broadcastScore()
	Remotes.get("TeamScoreChanged"):FireAllClients({
		Blue = self.teamKills.Blue,
		Red = self.teamKills.Red,
	})
end

function ScoreService:_broadcastStats()
	self._statsDirty = false
	Remotes.get("MatchStats"):FireAllClients(self:_statsArray())
end

-- Debounced stats push — gold trickles in constantly; one broadcast per
-- second is plenty for a scoreboard.
function ScoreService:_markStatsDirty()
	if self._statsDirty then
		return
	end
	self._statsDirty = true
	task.delay(1, function()
		if self._statsDirty then
			self:_broadcastStats()
		end
	end)
end

function ScoreService:announce(text, color, duration)
	Remotes.get("Announce"):FireAllClients(text, color, duration)
end

-- =====================================================================
-- Champion takedowns
-- =====================================================================

function ScoreService:onChampionDeath(victim, killer, assistIds, respawnDelay)
	local vs = self:_entryFor(victim)
	vs.deaths = vs.deaths + 1

	-- Shutdown bounty is based on the spree the victim WAS on.
	local victimSpree = self.sprees[victim.UserId] or 0
	self.sprees[victim.UserId] = 0

	local killGold = 0
	local label = nil
	local killerSpree = 0

	if killer then
		local ks = self:_entryFor(killer)
		ks.kills = ks.kills + 1
		local killerTeam = self.matchController:teamOf(killer)
		if killerTeam and self.teamKills[killerTeam] then
			self.teamKills[killerTeam] = self.teamKills[killerTeam] + 1
		end

		killGold = Config.Kill.Gold
		if not self.firstBloodTaken then
			self.firstBloodTaken = true
			killGold = killGold + Config.Kill.FirstBloodBonus
			label = "FIRST BLOOD!"
		end
		if victimSpree >= 3 then
			killGold = killGold + math.min(victimSpree * Config.Kill.ShutdownPerStreak, Config.Kill.ShutdownMax)
			label = label or "SHUTDOWN!"
		end
		self.matchController:addGold(killer, killGold)

		-- Spree + multikill labels. Multikill outranks spree text.
		killerSpree = (self.sprees[killer.UserId] or 0) + 1
		self.sprees[killer.UserId] = killerSpree
		local now = os.clock()
		local mk = self.multikills[killer.UserId]
		if mk and (now - mk.lastAt) <= Config.Kill.MultikillWindow then
			mk.count = mk.count + 1
			mk.lastAt = now
		else
			mk = { count = 1, lastAt = now }
			self.multikills[killer.UserId] = mk
		end
		if mk.count >= 2 then
			label = MULTIKILL_LABEL[math.min(mk.count, 5)]
		elseif not label and SPREE_LABEL[killerSpree] then
			label = killer.DisplayName .. " IS ON A " .. SPREE_LABEL[killerSpree] .. "!"
		end

		-- Kill XP scales with the victim's level (worth more to slay the fed).
		local victimEntry = self.combatService:getEntry(victim)
		local victimLevel = (victimEntry and victimEntry.level) or 1
		local killXP = Config.XP.ChampionKillBase + Config.XP.ChampionKillPerLevel * victimLevel
		self.combatService:addXP(killer, killXP)

		-- Assists: gold + a share of the kill XP.
		for _, uid in ipairs(assistIds or {}) do
			local p = Players:GetPlayerByUserId(uid)
			if p then
				local as = self:_entryFor(p)
				as.assists = as.assists + 1
				self.matchController:addGold(p, Config.Kill.AssistGold)
				self.combatService:addXP(p, math.floor(killXP * Config.XP.AssistXPPct / 100 + 0.5))
			end
		end
	end

	-- Feed + death screen + score updates.
	Remotes.get("KillFeed"):FireAllClients({
		killerId = killer and killer.UserId or nil,
		killerName = killer and killer.DisplayName or nil,
		killerTeam = killer and self.matchController:teamOf(killer) or nil,
		victimId = victim.UserId,
		victimName = victim.DisplayName,
		victimTeam = self.matchController:teamOf(victim),
		gold = killGold,
		label = label,
		spree = killerSpree,
	})
	Remotes.get("YouDied"):FireClient(victim, respawnDelay, killer and killer.DisplayName or nil)
	self:_broadcastScore()
	self:_broadcastStats()
end

-- =====================================================================
-- Minions (CS + lane XP)
-- =====================================================================

-- Called by MinionService when a LANE minion dies. Last-hitter gets CS +
-- guaranteed XP; every enemy-team champion near the death shares the XP.
function ScoreService:onMinionKilled(entry, killerPlayer, position)
	local enemyTeam = (entry.team == "Blue") and "Red" or "Blue"
	local xp = Config.XP.Minion[entry.typeKey] or 25

	if killerPlayer and self.matchController:teamOf(killerPlayer) == enemyTeam then
		local ks = self:_entryFor(killerPlayer)
		ks.cs = ks.cs + 1
		self:_markStatsDirty()
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if self.matchController:teamOf(player) == enemyTeam and self.combatService:isAlive(player) then
			local isKiller = killerPlayer == player
			local near = false
			if not isKiller and position then
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				near = root and (root.Position - position).Magnitude <= Config.XP.ShareRadius or false
			end
			if isKiller or near then
				self.combatService:addXP(player, xp)
			end
		end
	end
end

-- =====================================================================
-- Towers
-- =====================================================================

function ScoreService:onTowerDestroyed(towerEntry, killerPlayer)
	local winningTeam = (towerEntry.team == "Blue") and "Red" or "Blue"
	-- Team-wide payout (the killer already got the tower's own gold reward).
	self.matchController:addTeamGold(winningTeam, Config.Tower.TeamGoldReward or 0)
	for _, player in ipairs(Players:GetPlayers()) do
		if self.matchController:teamOf(player) == winningTeam then
			self.combatService:addXP(player, Config.XP.Tower)
		end
	end

	local tierName = (towerEntry.tier == 3) and "NEXUS" or ("tier-" .. tostring(towerEntry.tier) .. " tower")
	local who = killerPlayer and killerPlayer.DisplayName or (winningTeam .. " minions")
	local color = (winningTeam == "Blue") and Color3.fromRGB(120, 190, 255) or Color3.fromRGB(255, 130, 120)
	if towerEntry.tier ~= 3 then
		self:announce(("%s destroyed a %s %s!"):format(who, towerEntry.team, tierName), color, 3)
	end
	self:_markStatsDirty()
end

return ScoreService
