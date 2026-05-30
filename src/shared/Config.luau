local Config = {}

-- =====================================================================
-- TEAMS
-- =====================================================================

Config.TeamSize = 3
Config.Teams = {
	Blue = {
		Name = "Blue",
		Color = Color3.fromRGB(70, 140, 255),
		SpawnPosition = Vector3.new(-320, 6, 0),
		SpawnFacing = Vector3.new(1, 0, 0),
	},
	Red = {
		Name = "Red",
		Color = Color3.fromRGB(255, 90, 90),
		SpawnPosition = Vector3.new(320, 6, 0),
		SpawnFacing = Vector3.new(-1, 0, 0),
	},
}

-- =====================================================================
-- ARENA — single curved lane, bilaterally mirrored across the X axis.
-- The lane bows south. Jungle on both sides of the lane houses 2 camps
-- per team (one north, one south of the lane) and a central boss pit.
-- =====================================================================

Config.GroundY = 0
-- Wide enough that the tower base (22 studs for T1/T2, 34 for the nexus) sits
-- comfortably in the middle of the lane with room for minion waves to flow
-- past on either side and engage the tower.
Config.LaneWidth = 50

-- Blue-side → Red-side waypoints (Red minions traverse this list reversed).
-- Mirror around x=0: positions at (-x, 0, z) and (x, 0, z) are paired.
Config.LaneWaypoints = {
	Vector3.new(-280, 0, 0),
	Vector3.new(-200, 0, -20),
	Vector3.new(-100, 0, -30),
	Vector3.new(0, 0, -35),
	Vector3.new(100, 0, -30),
	Vector3.new(200, 0, -20),
	Vector3.new(280, 0, 0),
}

Config.Arena = {
	HalfLength = 360,
	HalfWidth = 170,
}

-- Jungle camp markers. Bilaterally mirrored — each team has one north and
-- one south of the lane. (Visual pads only for now; creep AI comes later.)
Config.JungleCamps = {
	{ name = "BlueCampNorth", team = "Blue", position = Vector3.new(-160, 0, 50) },
	{ name = "BlueCampSouth", team = "Blue", position = Vector3.new(-160, 0, -95) },
	{ name = "RedCampNorth", team = "Red", position = Vector3.new(160, 0, 50) },
	{ name = "RedCampSouth", team = "Red", position = Vector3.new(160, 0, -95) },
}

-- Single shared boss in the deep north jungle, equidistant from both nexuses.
Config.BossLair = {
	position = Vector3.new(0, 0, 80),
	pitRadius = 22,
}

-- =====================================================================
-- MINIONS
-- =====================================================================

-- A wave spawns one of each type in the sequence below per side, staggered.
Config.Wave = {
	StartDelay = 8, -- seconds after match start before first wave
	Interval = 30,
	Stagger = 0.7, -- seconds between each minion in the sequence
	Sequence = {
		"Melee", "Melee", "Melee",
		"Cannon",
		"Ranged", "Ranged", "Ranged",
	},
}

-- Stats per minion type. The minion's currently-held entry copies these so
-- per-minion tweaks (e.g. buffs) wouldn't pollute the shared config.
--
-- Gold: every enemy minion death awards Config.MinionTeamGold to each member
-- of the killer's team (passive lane gold). LastHitGold is an extra bonus
-- given ONLY to the player who lands the killing blow.
Config.MinionTypes = {
	Melee = {
		MaxHP = 110,
		WalkSpeed = 9,
		AttackDamage = 3,
		AttackRange = 6,
		AttackInterval = 1.1,
		AggroRadius = 14,
		LastHitGold = 15,
		Size = Vector3.new(2.4, 3.6, 2),
		ColorMul = 1.0, -- multiplier applied to team color
		Projectile = false,
	},
	Ranged = {
		MaxHP = 60,
		WalkSpeed = 9,
		AttackDamage = 6,
		AttackRange = 24,
		AttackInterval = 1.6,
		AggroRadius = 28,
		LastHitGold = 10,
		Size = Vector3.new(1.8, 3.2, 1.8),
		ColorMul = 1.3, -- lighter
		Projectile = true,
		ProjectileSpeed = 60,
		ProjectileRadius = 1.0,
	},
	Cannon = {
		MaxHP = 350,
		WalkSpeed = 9,
		AttackDamage = 12,
		AttackRange = 18,
		AttackInterval = 2.0,
		AggroRadius = 22,
		LastHitGold = 25,
		Size = Vector3.new(3.4, 4.8, 3.0),
		ColorMul = 0.7, -- darker
		Projectile = true,
		ProjectileSpeed = 50,
		ProjectileRadius = 1.4,
	},
}

-- Gold awarded to every member of the team whose enemy minion just died,
-- regardless of who got the killing blow.
Config.MinionTeamGold = 5

Config.Minion = {
	WaypointReachDistance = 3,
}

-- =====================================================================
-- COMBAT (champion auto-attacks)
-- =====================================================================

Config.AutoAttack = {
	Damage = 55,
	Range = 9,
	Interval = 1.1,
}

Config.RespawnDelay = 6

-- =====================================================================
-- RECALL ("Base") — channeled teleport back to your team's spawn pad.
-- Cancels on damage taken, movement (humanoid MoveDirection > epsilon),
-- ability cast, or death. While standing inside the base regen radius
-- the player heals RegenPctPerSecond of their max HP each second.
-- =====================================================================
Config.Recall = {
	ChannelTime = 8,
	-- Radius around the team's SpawnPosition that counts as "in base".
	BaseRadius = 28,
	-- Fraction of max HP regen'd per second while in base (0.2 = 20%/s).
	RegenPctPerSecond = 0.20,
	-- How often the regen tick fires. 0.25s feels smooth without spamming HP replication.
	RegenTickInterval = 0.25,
}

-- =====================================================================
-- TOWERS (defense structures). Place any BasePart in Workspace with
-- attribute TowerTeam = "Blue" or "Red" to register it as a tower.
-- Optional per-tower attribute overrides: TowerRange, TowerDamage,
-- TowerInterval, TowerMaxHP, TowerGoldReward.
-- =====================================================================
Config.Tower = {
	DefaultRange = 50,
	DefaultDamage = 80,
	DefaultInterval = 1.5,
	DefaultMaxHP = 1500,
	DefaultGoldReward = 200,
	-- League-style backdoor protection: when a CHAMPION attacks a tower with no
	-- attacker-team minions in tower range, damage is multiplied by this.
	BackdoorDamageMult = 0.20,
}

-- =====================================================================
-- LOBBY / MATCHMAKING
-- =====================================================================

-- For solo testing, set RequiredPerTeam = 1. For real 3v3, set to 3.
Config.Matchmaking = {
	ZoneCount = 6,
	MaxPerZone = 3,
	RequiredPerTeam = 1, -- TEMP: 1 for solo testing; bump to 3 for production
	StartCountdown = 3, -- seconds after pairing before match begins
	LobbyTimerDuration = 120, -- 2 minutes, ticks down once any zone is hosted
}

Config.LobbyOrigin = Vector3.new(0, 600, 0) -- placed far from arena
Config.LobbyRadius = 70 -- ring radius for zone pads

-- =====================================================================
-- PRACTICE ROOM — quick test arena with a respawning target dummy.
-- =====================================================================
Config.PracticeOrigin = Vector3.new(0, 1200, 0)
Config.PracticeRoomSize = Vector3.new(180, 1, 180)
Config.PracticeDummyOffset = Vector3.new(30, 4, 0) -- relative to PracticeOrigin
Config.PracticeDummyMaxHP = 1000
Config.PracticeDummyRespawnDelay = 5

return Config
