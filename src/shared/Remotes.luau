local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local REMOTE_NAMES = {
	-- =========== Gameplay (in-match) ===========
	-- Client → Server
	CastAbility = "RemoteEvent", -- (slot, origin, direction, targetPos, targetType?, targetId?)
	SetTarget = "RemoteEvent",
	SelectChampion = "RemoteEvent", -- (championKey) — sent during champion-select
	-- Server → Client
	AbilityCooldownChanged = "RemoteEvent",
	HPChanged = "RemoteEvent",
	GoldChanged = "RemoteEvent",
	TargetCleared = "RemoteEvent",
	AutoAttackFired = "RemoteEvent",
	ChampionSelectStart = "RemoteEvent", -- (championKeysList) — open the select UI
	ChampionSelected = "RemoteEvent", -- (championKey) — close the select UI
	-- Server pushes the set of champions already locked by THIS player's
	-- teammates. Payload: { [championKey] = pickerDisplayName }. Sent on
	-- pick changes and when the player's own select UI first opens.
	TeamChampionPicks = "RemoteEvent",
	StatusEffectChanged = "RemoteEvent", -- (statusType, payload) — visual indicators
	ShieldChanged = "RemoteEvent", -- (shieldAmount)
	DamageDealt = "RemoteEvent", -- (position, amount, victimUserId?) — all clients, drives damage numbers + hit flash
	-- Recall ("Base" ability): client presses B → server starts channel.
	-- Server cancels on damage, movement, ability cast, or another RecallStart.
	RecallStart = "RemoteEvent", -- C→S: start channel
	RecallCancel = "RemoteEvent", -- C↔S: client requests cancel / server announces cancel (reason)
	RecallState = "RemoteEvent", -- S→C: ("channeling"|"complete"|"cancelled", duration?) — drives UI bar + FX
	InBaseChanged = "RemoteEvent", -- S→C: (bool) — for HUD shop hint / shop gate
	-- In-match item shop (spends MATCH gold, only while in the base regen zone).
	BuyItem = "RemoteEvent", -- C→S: (itemKey)
	ItemsChanged = "RemoteEvent", -- S→C: ({ [itemKey] = count }) — owned items
	BuyItemResult = "RemoteEvent", -- S→C: (ok, reason)
	-- Score / kills / progression (all S→C, fired by ScoreService).
	KillFeed = "RemoteEvent", -- ({ killerId?, killerName?, killerTeam?, victimId, victimName, victimTeam, gold, label?, spree })
	TeamScoreChanged = "RemoteEvent", -- ({ Blue = kills, Red = kills })
	MatchClock = "RemoteEvent", -- (serverStartTime from GetServerTimeNow) — drives the HUD match timer
	MatchStats = "RemoteEvent", -- (array of { userId, name, team, champion, kills, deaths, assists, cs, gold }) — scoreboard
	XPChanged = "RemoteEvent", -- (level, xp, xpToNext) — own XP bar
	LevelUp = "RemoteEvent", -- (userId, newLevel) — all clients, level-up flash/sound
	YouDied = "RemoteEvent", -- (respawnSeconds, killerName?) — death overlay + countdown
	Announce = "RemoteEvent", -- (text, color?, duration?) — objective banners (boss, towers)

	-- =========== Lobby / matchmaking ===========
	-- Client → Server
	JoinZone = "RemoteEvent", -- (zoneId, accessMode "anyone"|"friends"|"solo")
	LeaveZone = "RemoteEvent",
	StartNow = "RemoteEvent", -- testing button: skip the 2-min timer
	StartPractice = "RemoteEvent", -- testing button: solo practice room with respawning dummy
	LeaveMatch = "RemoteEvent",
	BuyRune = "RemoteEvent", -- (runeKey, tier)
	SetSummonerSpell = "RemoteEvent", -- (spellKey)
	-- Server → Client (state pushes)
	PlayerStateChanged = "RemoteEvent", -- ("lobby" | "in_zone" | "in_match", zoneId?)
	ZonesUpdated = "RemoteEvent", -- (table of zone snapshots)
	LobbyTimerChanged = "RemoteEvent", -- ({ active, remaining }) — broadcast on changes
	PlayerDataChanged = "RemoteEvent", -- ({ gold, runes, summonerSpell })
	BuyRuneResult = "RemoteEvent", -- (ok, reason)
	MatchStarted = "RemoteEvent", -- (team)
	MatchEnded = "RemoteEvent", -- (reason)
}

local function getOrCreate(folder, name, className)
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = folder
	return inst
end

function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init must be called on the server")
	local folder = getOrCreate(ReplicatedStorage, "Remotes", "Folder")
	for name, className in pairs(REMOTE_NAMES) do
		getOrCreate(folder, name, className)
	end
	return folder
end

function Remotes.get(name)
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name)
end

return Remotes
