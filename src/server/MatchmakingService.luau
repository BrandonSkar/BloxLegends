local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MatchmakingService = {}
MatchmakingService.__index = MatchmakingService

local STATE_LOBBY = "lobby"
local STATE_IN_ZONE = "in_zone"
local STATE_IN_MATCH = "in_match"

function MatchmakingService.new(lobby)
	local self = setmetatable({}, MatchmakingService)
	self.lobby = lobby -- { spawnPos, zones = {[id]={pad, statusLabel,...}} }
	self.zones = {} -- zoneId -> { id, players = {userId, ...}, accessMode, ownerId, status = "open"|"ready"|"in_match" }
	self.playerStates = {} -- userId -> { state, zoneId }
	for id in pairs(lobby.zones) do
		self.zones[id] = {
			id = id,
			players = {},
			accessMode = "open",
			ownerId = nil,
			status = "open",
			-- Monotonic clock time when the zone last went from empty → occupied.
			-- Used as the FIFO key for matchmaking ("first come first served").
			firstJoinedAt = nil,
		}
	end
	self.matchInProgress = false
	self.matchTeams = nil -- { Blue = {userId,..}, Red = {userId,..} }
	self.callbacks = {
		onMatchStart = nil, -- function(blueIds, redIds)
		onMatchEnd = nil, -- function()
	}
	return self
end

function MatchmakingService:_zoneSnapshot()
	local snap = {}
	for id, zone in pairs(self.zones) do
		local names = {}
		for _, uid in ipairs(zone.players) do
			local player = Players:GetPlayerByUserId(uid)
			table.insert(names, player and player.DisplayName or "?")
		end
		local ownerName
		if zone.ownerId then
			local ownerPlayer = Players:GetPlayerByUserId(zone.ownerId)
			ownerName = ownerPlayer and ownerPlayer.DisplayName or nil
		end
		snap[id] = {
			id = id,
			count = #zone.players,
			max = Config.Matchmaking.MaxPerZone,
			accessMode = zone.accessMode,
			status = zone.status,
			players = names,
			ownerId = zone.ownerId,
			ownerName = ownerName,
		}
	end
	return snap
end

function MatchmakingService:_pushZoneUpdate()
	-- Update lobby billboards
	for id, zone in pairs(self.zones) do
		local rec = self.lobby.zones[id]
		if rec and rec.statusLabel then
			local txt = ("%d / %d"):format(#zone.players, Config.Matchmaking.MaxPerZone)
			if zone.status == "ready" then
				txt = txt .. " — READY"
			elseif zone.status == "in_match" then
				txt = txt .. " — IN MATCH"
			elseif zone.accessMode == "friends" then
				txt = txt .. "\n(friends only)"
			end
			rec.statusLabel.Text = txt
		end
	end
	Remotes.get("ZonesUpdated"):FireAllClients(self:_zoneSnapshot())
end

function MatchmakingService:_setPlayerState(player, state, zoneId)
	self.playerStates[player.UserId] = { state = state, zoneId = zoneId }
	Remotes.get("PlayerStateChanged"):FireClient(player, state, zoneId)
end

function MatchmakingService:getState(player)
	local s = self.playerStates[player.UserId]
	return s and s.state or STATE_LOBBY
end

function MatchmakingService:onPlayerJoined(player)
	self:_setPlayerState(player, STATE_LOBBY, nil)
	self:_pushZoneUpdate()
end

function MatchmakingService:onPlayerLeft(player)
	-- Remove from any zone they were in
	for _, zone in pairs(self.zones) do
		for i = #zone.players, 1, -1 do
			if zone.players[i] == player.UserId then
				table.remove(zone.players, i)
			end
		end
		if zone.ownerId == player.UserId then
			zone.ownerId = zone.players[1]
		end
		if zone.status == "ready" and #zone.players < Config.Matchmaking.RequiredPerTeam then
			zone.status = "open"
		end
	end
	self:_stopLobbyTimerIfEmpty()
	self.playerStates[player.UserId] = nil
	-- If they were in match, check if match should end
	if self.matchInProgress and self.matchTeams then
		self:_checkMatchEnd()
	end
	self:_pushZoneUpdate()
end

-- Server-side check: can `player` join `zone`?
local function canJoinZone(self, player, zone)
	if zone.status == "in_match" then
		return false, "zone in match"
	end
	if #zone.players >= Config.Matchmaking.MaxPerZone then
		return false, "full"
	end
	if zone.accessMode == "solo" and zone.ownerId and zone.ownerId ~= player.UserId then
		return false, "solo"
	end
	if zone.accessMode == "friends" and zone.ownerId and zone.ownerId ~= player.UserId then
		local owner = Players:GetPlayerByUserId(zone.ownerId)
		if not owner then
			return false, "owner gone"
		end
		local ok, isFriend = pcall(function()
			return player:IsFriendsWith(zone.ownerId)
		end)
		if not ok or not isFriend then
			return false, "not friends"
		end
	end
	return true
end

function MatchmakingService:joinZone(player, zoneId, accessMode)
	if self:getState(player) ~= STATE_LOBBY then
		return false
	end
	local zone = self.zones[zoneId]
	if not zone then
		return false
	end
	local ok, _reason = canJoinZone(self, player, zone)
	if not ok then
		return false
	end
	-- Setting access mode requires being the owner (first joiner) or zone being empty.
	if #zone.players == 0 then
		zone.ownerId = player.UserId
		zone.firstJoinedAt = os.clock()
		if accessMode == "friends" or accessMode == "anyone" or accessMode == "solo" then
			zone.accessMode = accessMode
		else
			zone.accessMode = "anyone"
		end
	end
	table.insert(zone.players, player.UserId)
	zone.status = "open"
	self:_setPlayerState(player, STATE_IN_ZONE, zoneId)
	self:_startLobbyTimerIfNeeded()
	self:_pushZoneUpdate()
	return true
end

-- =====================================================================
-- Global lobby timer (2 minutes from first zone host → match start).
-- =====================================================================

function MatchmakingService:_anyZoneOccupied()
	for _, z in pairs(self.zones) do
		if #z.players > 0 then
			return true
		end
	end
	return false
end

function MatchmakingService:_totalPlayersInZones()
	local n = 0
	for _, z in pairs(self.zones) do
		n = n + #z.players
	end
	return n
end

function MatchmakingService:_broadcastLobbyTimer()
	local payload
	if self.lobbyTimer and self.lobbyTimer.active then
		payload = {
			active = true,
			remaining = math.max(0, self.lobbyTimer.endsAt - os.clock()),
			duration = Config.Matchmaking.LobbyTimerDuration,
		}
	else
		payload = { active = false, remaining = 0, duration = Config.Matchmaking.LobbyTimerDuration }
	end
	Remotes.get("LobbyTimerChanged"):FireAllClients(payload)
end

function MatchmakingService:_startLobbyTimerIfNeeded()
	if self.lobbyTimer and self.lobbyTimer.active then
		return
	end
	if not self:_anyZoneOccupied() then
		return
	end
	self.lobbyTimer = {
		active = true,
		endsAt = os.clock() + Config.Matchmaking.LobbyTimerDuration,
	}
	self:_broadcastLobbyTimer()
end

function MatchmakingService:_stopLobbyTimerIfEmpty()
	if not self.lobbyTimer or not self.lobbyTimer.active then
		return
	end
	if self:_anyZoneOccupied() then
		return
	end
	self.lobbyTimer.active = false
	self:_broadcastLobbyTimer()
end

function MatchmakingService:_resetLobbyTimer()
	self.lobbyTimer = {
		active = true,
		endsAt = os.clock() + Config.Matchmaking.LobbyTimerDuration,
	}
	self:_broadcastLobbyTimer()
end

-- Called from the heartbeat tick (see :startTimerLoop()).
function MatchmakingService:_tickLobbyTimer()
	if not self.lobbyTimer or not self.lobbyTimer.active then
		return
	end
	if os.clock() < self.lobbyTimer.endsAt then
		return
	end
	-- Timer expired. Try to form a match using the group-aware FIFO algorithm.
	if self:_totalPlayersInZones() < 2 then
		self:_resetLobbyTimer()
		return
	end
	if self.matchInProgress then
		-- Wait until current match ends before pairing the next one.
		self:_resetLobbyTimer()
		return
	end
	local blueIds, redIds, usedZones = self:_findMatch()
	if not blueIds then
		-- No legal team composition (e.g. zones are [3,2]). Restart and wait
		-- for more players.
		self:_resetLobbyTimer()
		return
	end
	self.lobbyTimer.active = false
	self:_broadcastLobbyTimer()
	self:_startMatchWith(blueIds, redIds, usedZones)
end

function MatchmakingService:startTimerLoop()
	if self._timerConn then
		return
	end
	self._timerConn = RunService.Heartbeat:Connect(function()
		self:_tickLobbyTimer()
	end)
end

-- Push the current timer state to a single client (used when they join the server).
function MatchmakingService:sendLobbyTimerTo(player)
	local payload
	if self.lobbyTimer and self.lobbyTimer.active then
		payload = {
			active = true,
			remaining = math.max(0, self.lobbyTimer.endsAt - os.clock()),
			duration = Config.Matchmaking.LobbyTimerDuration,
		}
	else
		payload = { active = false, remaining = 0, duration = Config.Matchmaking.LobbyTimerDuration }
	end
	Remotes.get("LobbyTimerChanged"):FireClient(player, payload)
end

-- Anyone leaving a zone empties the entire zone (spec: "leaving will take
-- everyone in the zone out"). Useful so a stuck host can't trap others.
function MatchmakingService:leaveZone(player)
	local s = self.playerStates[player.UserId]
	if not s or s.state ~= STATE_IN_ZONE then
		return false
	end
	local zone = self.zones[s.zoneId]
	if not zone then
		return false
	end
	-- Move every occupant back to the lobby state.
	local kicked = {}
	for _, uid in ipairs(zone.players) do
		table.insert(kicked, uid)
	end
	for _, uid in ipairs(kicked) do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			self:_setPlayerState(p, STATE_LOBBY, nil)
		end
	end
	zone.players = {}
	zone.ownerId = nil
	zone.accessMode = "open"
	zone.status = "open"
	zone.firstJoinedAt = nil
	-- If no zone is occupied anymore, stop the global lobby timer.
	self:_stopLobbyTimerIfEmpty()
	self:_pushZoneUpdate()
	return true
end

-- =====================================================================
-- Matchmaking algorithm (group-aware, FIFO).
-- Each occupied zone is one indivisible "group". Groups never split across
-- teams. We try team sizes 3 → 2 → 1, picking the oldest groups first.
-- =====================================================================

-- Patterns tried in priority order. Each entry: { teamA_group_sizes, teamB_group_sizes }.
-- Higher = more ambitious match.
local MATCH_PATTERNS = {
	{ { 3 }, { 3 } },
	{ { 3 }, { 2, 1 } },
	{ { 2, 1 }, { 2, 1 } },
	{ { 3 }, { 1, 1, 1 } },
	{ { 2, 1 }, { 1, 1, 1 } },
	{ { 1, 1, 1 }, { 1, 1, 1 } },
	{ { 2 }, { 2 } },
	{ { 2 }, { 1, 1 } },
	{ { 1, 1 }, { 1, 1 } },
	{ { 1 }, { 1 } },
}

-- Try to satisfy a pattern using the available groups. Picks the oldest
-- available group for each required size. Returns (teamABlueIds, teamRedIds, usedZoneIds) or nil.
local function tryPattern(groups, teamASizes, teamBSizes)
	-- Collapse the two team needs into a single ordered list of (size, team) demands.
	local needs = {}
	for _, s in ipairs(teamASizes) do
		table.insert(needs, { size = s, team = "A" })
	end
	for _, s in ipairs(teamBSizes) do
		table.insert(needs, { size = s, team = "B" })
	end
	-- Satisfy largest-first so big slots get filled before scarce small ones.
	table.sort(needs, function(a, b)
		return a.size > b.size
	end)

	local used = {}
	local assignments = {}
	for _, need in ipairs(needs) do
		local pickedIdx
		for i, group in ipairs(groups) do
			if not used[i] and group.size == need.size then
				pickedIdx = i
				break
			end
		end
		if not pickedIdx then
			return nil
		end
		used[pickedIdx] = true
		table.insert(assignments, { groupIdx = pickedIdx, team = need.team })
	end

	local teamA, teamB, usedZones = {}, {}, {}
	for _, a in ipairs(assignments) do
		local g = groups[a.groupIdx]
		table.insert(usedZones, g.zoneId)
		local target = (a.team == "A") and teamA or teamB
		for _, uid in ipairs(g.players) do
			table.insert(target, uid)
		end
	end
	return teamA, teamB, usedZones
end

function MatchmakingService:_findMatch()
	local groups = {}
	for _, zone in pairs(self.zones) do
		if #zone.players > 0 and zone.status ~= "in_match" then
			local copy = {}
			for _, uid in ipairs(zone.players) do
				table.insert(copy, uid)
			end
			table.insert(groups, {
				zoneId = zone.id,
				size = #zone.players,
				players = copy,
				joinedAt = zone.firstJoinedAt or 0,
			})
		end
	end
	-- Oldest groups first (FIFO).
	table.sort(groups, function(a, b)
		return a.joinedAt < b.joinedAt
	end)
	for _, pattern in ipairs(MATCH_PATTERNS) do
		local teamA, teamB, usedZones = tryPattern(groups, pattern[1], pattern[2])
		if teamA then
			return teamA, teamB, usedZones
		end
	end
	return nil
end

-- Set up a match with the given player rosters. Zones used are emptied and
-- reopened; leftover players stay in their zones and the timer is restarted.
function MatchmakingService:_startMatchWith(blueIds, redIds, usedZoneIds)
	if self.matchInProgress then
		return false
	end
	if #blueIds == 0 or #redIds == 0 then
		return false
	end
	self.matchInProgress = true
	self.matchTeams = { Blue = {}, Red = {} }
	for _, uid in ipairs(blueIds) do
		table.insert(self.matchTeams.Blue, uid)
		local p = Players:GetPlayerByUserId(uid)
		if p then
			self:_setPlayerState(p, STATE_IN_MATCH, nil)
			Remotes.get("MatchStarted"):FireClient(p, "Blue")
		end
	end
	for _, uid in ipairs(redIds) do
		table.insert(self.matchTeams.Red, uid)
		local p = Players:GetPlayerByUserId(uid)
		if p then
			self:_setPlayerState(p, STATE_IN_MATCH, nil)
			Remotes.get("MatchStarted"):FireClient(p, "Red")
		end
	end
	-- Clear the zones that contributed to this match (their players are leaving the lobby).
	for _, zoneId in ipairs(usedZoneIds or {}) do
		local zone = self.zones[zoneId]
		if zone then
			zone.status = "in_match"
			zone.players = {}
			zone.ownerId = nil
			zone.accessMode = "open"
			zone.firstJoinedAt = nil
		end
	end
	-- Open in_match zones back up once the match starts so other players can host them again.
	-- (Zones reset fully on match end via onMatchEnd; this is just for the brief overlap.)
	self:_pushZoneUpdate()
	task.delay(Config.Matchmaking.StartCountdown, function()
		if self.callbacks.onMatchStart then
			self.callbacks.onMatchStart(self.matchTeams.Blue, self.matchTeams.Red)
		end
	end)
	-- Leftover players: their zones still have populations. Restart timer for them.
	if self:_anyZoneOccupied() then
		self:_resetLobbyTimer()
	end
	return true
end

-- Pull players from every occupied zone into a match. Each zone goes entirely
-- to one team — zone 1 → Blue, zone 2 → Red, then alternates for the rest,
-- preferring whichever team has fewer players. (Stub matchmaking; replace
-- once we have the real algorithm.)
function MatchmakingService:_startMatchFromAllZones()
	if self.matchInProgress then
		return false
	end
	-- Gather occupied zones in id order so the result is deterministic.
	local occupied = {}
	for _, zone in pairs(self.zones) do
		if #zone.players > 0 then
			table.insert(occupied, zone)
		end
	end
	table.sort(occupied, function(a, b)
		return a.id < b.id
	end)
	if #occupied == 0 then
		return false
	end
	self.matchInProgress = true
	self.matchTeams = { Blue = {}, Red = {} }
	for i, zone in ipairs(occupied) do
		local team
		if i == 1 then
			team = "Blue"
		elseif i == 2 then
			team = "Red"
		else
			team = (#self.matchTeams.Blue <= #self.matchTeams.Red) and "Blue" or "Red"
		end
		for _, uid in ipairs(zone.players) do
			table.insert(self.matchTeams[team], uid)
			local p = Players:GetPlayerByUserId(uid)
			if p then
				self:_setPlayerState(p, STATE_IN_MATCH, zone.id)
				Remotes.get("MatchStarted"):FireClient(p, team)
			end
		end
		-- Clear the zone now that its players have entered the match — otherwise
		-- _anyZoneOccupied keeps the lobby timer running on these phantom players.
		zone.status = "in_match"
		zone.players = {}
		zone.ownerId = nil
		zone.accessMode = "open"
		zone.firstJoinedAt = nil
	end
	self:_pushZoneUpdate()
	task.delay(Config.Matchmaking.StartCountdown, function()
		if self.callbacks.onMatchStart then
			self.callbacks.onMatchStart(self.matchTeams.Blue, self.matchTeams.Red)
		end
	end)
	return true
end

-- Public testing path: ignore the timer, ignore matchmaking rules, start
-- immediately. If the calling player is just standing in the lobby (not in any
-- zone), they get added to Blue solo. Otherwise zones split into teams by id.
function MatchmakingService:startNow(player)
	if self.matchInProgress then
		return false
	end
	-- Auto-add ONLY the calling player to an empty zone if they aren't in one
	-- already, so a solo developer test still produces a match. Other lobby
	-- players are NOT pulled in — they must opt in by walking into a zone.
	if player and self:getState(player) == STATE_LOBBY then
		for _, z in pairs(self.zones) do
			if #z.players == 0 then
				table.insert(z.players, player.UserId)
				z.ownerId = player.UserId
				z.accessMode = "anyone"
				z.firstJoinedAt = os.clock()
				self:_setPlayerState(player, STATE_IN_ZONE, z.id)
				break
			end
		end
	end
	if self:_totalPlayersInZones() == 0 then
		return false
	end
	if self.lobbyTimer and self.lobbyTimer.active then
		self.lobbyTimer.active = false
		self:_broadcastLobbyTimer()
	end
	return self:_startMatchFromAllZones()
end

function MatchmakingService:_checkMatchEnd()
	if not self.matchInProgress then
		return
	end
	local blueRemaining = 0
	local redRemaining = 0
	for _, uid in ipairs(self.matchTeams.Blue or {}) do
		local s = self.playerStates[uid]
		if s and s.state == STATE_IN_MATCH then
			blueRemaining = blueRemaining + 1
		end
	end
	for _, uid in ipairs(self.matchTeams.Red or {}) do
		local s = self.playerStates[uid]
		if s and s.state == STATE_IN_MATCH then
			redRemaining = redRemaining + 1
		end
	end
	if blueRemaining == 0 or redRemaining == 0 then
		self:endMatch(blueRemaining > 0 and "Blue wins (Red abandoned)" or (redRemaining > 0 and "Red wins (Blue abandoned)" or "Match abandoned"))
	end
end

-- Player chose to leave mid-match → back to lobby.
function MatchmakingService:leaveMatch(player)
	local s = self.playerStates[player.UserId]
	if not s or s.state ~= STATE_IN_MATCH then
		return false
	end
	self:_setPlayerState(player, STATE_LOBBY, nil)
	self:_checkMatchEnd()
	return true
end

-- Called by orchestrator when match logically ends.
function MatchmakingService:endMatch(reason)
	if not self.matchInProgress then
		return
	end
	self.matchInProgress = false
	-- Free the two zones and clear participants
	for _, zone in pairs(self.zones) do
		if zone.status == "in_match" then
			zone.players = {}
			zone.status = "open"
			zone.accessMode = "open"
			zone.ownerId = nil
		end
	end
	for _, uid in ipairs(self.matchTeams.Blue or {}) do
		local p = Players:GetPlayerByUserId(uid)
		if p and self.playerStates[uid] and self.playerStates[uid].state == STATE_IN_MATCH then
			self:_setPlayerState(p, STATE_LOBBY, nil)
		end
		if p then
			Remotes.get("MatchEnded"):FireClient(p, reason)
		end
	end
	for _, uid in ipairs(self.matchTeams.Red or {}) do
		local p = Players:GetPlayerByUserId(uid)
		if p and self.playerStates[uid] and self.playerStates[uid].state == STATE_IN_MATCH then
			self:_setPlayerState(p, STATE_LOBBY, nil)
		end
		if p then
			Remotes.get("MatchEnded"):FireClient(p, reason)
		end
	end
	self.matchTeams = nil
	if self.callbacks.onMatchEnd then
		self.callbacks.onMatchEnd()
	end
	self:_pushZoneUpdate()
end

function MatchmakingService:wireClickDetectors(onZoneClick, onShopClick)
	for id, rec in pairs(self.lobby.zones) do
		rec.clickDetector.MouseClick:Connect(function(player)
			onZoneClick(player, id)
		end)
	end
	if self.lobby.shopClick then
		self.lobby.shopClick.MouseClick:Connect(function(player)
			onShopClick(player)
		end)
	end
end

return MatchmakingService
