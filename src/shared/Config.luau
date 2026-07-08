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

-- Waves grow stronger over the match so games escalate and end. Multipliers
-- apply to minion HP and damage per wave beyond the first, capped.
Config.WaveScaling = {
	HPPerWavePct = 5,
	DamagePerWavePct = 4,
	MaxMult = 2.5,
}

-- =====================================================================
-- JUNGLE — each camp pad (Config.JungleCamps) hosts one neutral brute.
-- Killing it pays gold + XP and grants the killer a timed buff:
--   North camps → STORM  (move + attack speed)
--   South camps → MIGHT  (attack power + ability power)
-- =====================================================================
Config.Jungle = {
	RespawnDelay = 75,
	-- A brute that chases beyond this distance from its pad resets home
	-- and rapidly heals to full.
	LeashRange = 45,
	Creep = {
		MaxHP = 900,
		WalkSpeed = 13,
		AttackDamage = 25,
		AttackRange = 9,
		AttackInterval = 1.2,
		Gold = 60,
		XP = 80,
	},
	Buffs = {
		Storm = {
			Label = "storm",
			Duration = 75,
			Stats = { MoveSpeedPct = 15, AttackSpeedPct = 20 },
			Color = Color3.fromRGB(120, 220, 255),
		},
		Might = {
			Label = "might",
			Duration = 75,
			Stats = { AttackPower = 15, AbilityPowerPct = 15 },
			Color = Color3.fromRGB(255, 120, 90),
		},
	},
}

-- =====================================================================
-- BOSS ("the Overlord") — single neutral boss in the north-jungle pit.
-- Slaying it grants the whole killing team gold, XP, and a strong timed
-- buff. Spawns a few minutes in; respawns a while after each kill.
-- =====================================================================
Config.Boss = {
	SpawnDelay = 180,
	RespawnDelay = 240,
	MaxHP = 3500,
	WalkSpeed = 10,
	AttackDamage = 50,
	AttackRange = 11,
	AttackInterval = 1.6,
	-- Periodic ground slam while in combat: damages every enemy in radius.
	SlamInterval = 5,
	SlamRadius = 14,
	SlamDamage = 70,
	LeashRange = 55,
	GoldEach = 150,
	XPEach = 150,
	Buff = {
		Label = "overlord",
		Duration = 90,
		Stats = { AttackPower = 20, AbilityPowerPct = 20, MoveSpeedPct = 8 },
		Color = Color3.fromRGB(200, 120, 255),
	},
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

-- Death timers grow with match time (League-style) so late-game deaths hurt
-- more. Actual delay = RespawnDelay + PerMinute × minutes-elapsed, capped.
Config.Respawn = {
	PerMinute = 1.5,
	Max = 24,
}

-- =====================================================================
-- KILL REWARDS — champion takedowns pay gold to the killer and assists.
-- A victim on a killing spree is worth a shutdown bonus. All windows in
-- seconds.
-- =====================================================================
Config.Kill = {
	Gold = 300,
	AssistGold = 150,
	FirstBloodBonus = 100,
	-- Shutdown: extra gold per kill the victim had on their spree (3+ spree).
	ShutdownPerStreak = 75,
	ShutdownMax = 450,
	-- Damaging a champion within this window before their death = assist.
	AssistWindow = 10,
	-- Consecutive kills inside this window chain into DOUBLE/TRIPLE/... kills.
	MultikillWindow = 10,
}

-- =====================================================================
-- XP / LEVELING — champions level up during a match, gaining max HP and
-- damage. XP comes from nearby minion deaths, takedowns, towers, jungle.
-- =====================================================================
Config.XP = {
	-- Minion XP is shared with every enemy-team champion within this radius
	-- of the dying minion (the last-hitter always gets it, distance or not).
	ShareRadius = 70,
	Minion = { Melee = 32, Ranged = 26, Cannon = 60 },
	ChampionKillBase = 120,
	ChampionKillPerLevel = 20,
	-- Assists earn this % of the kill XP.
	AssistXPPct = 60,
	-- Every member of the team that destroys a tower gets this.
	Tower = 90,
}

Config.Leveling = {
	MaxLevel = 15,
	-- Per level beyond 1: max HP × (1 + pct/100 × (level-1)), same for damage.
	HPPerLevelPct = 7,
	DamagePerLevelPct = 4,
	-- XP needed to go from level N to N+1 = XPBase + XPGrowth × (N-1).
	XPBase = 150,
	XPGrowth = 60,
}

function Config.xpToNext(level)
	return Config.Leveling.XPBase + Config.Leveling.XPGrowth * (level - 1)
end

function Config.levelHPMult(level)
	return 1 + (Config.Leveling.HPPerLevelPct / 100) * ((level or 1) - 1)
end

function Config.levelDamageMult(level)
	return 1 + (Config.Leveling.DamagePerLevelPct / 100) * ((level or 1) - 1)
end

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
	-- On top of the killer's reward, every member of the destroying team gets
	-- this (League-style global tower gold).
	TeamGoldReward = 100,
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

-- =====================================================================
-- THE PIT — the lobby's warm-up brawl. One shared free-for-all arena
-- where waiting players (1–5+) fight sparring bots, each other, and a
-- target dummy. Every player in the Pit is their own one-man team
-- ("FFA<userId>"), which is what makes all the existing "enemy = other
-- team" checks treat everyone as hostile.
-- =====================================================================
Config.PracticeOrigin = Vector3.new(0, 1200, 0)
Config.PracticeRoomSize = Vector3.new(180, 1, 180)
Config.PracticeDummyOffset = Vector3.new(45, 4, 45) -- relative to PracticeOrigin
Config.PracticeDummyMaxHP = 1000
Config.PracticeDummyRespawnDelay = 5

Config.Pit = {
	-- Enough to buy a real item build against the dummy/bots; kills top it up.
	StartingGold = 5000,
	BotKillGold = 100,
	BotKillXP = 45, -- bots feed XP so leveling can be practiced too
	PlayerKillGold = 250, -- Pit PvP pays out here (Pit deaths skip ScoreService)
	PlayerKillXP = 120,
	RespawnDelay = 4, -- fixed + short — the Pit is for action, not death timers
	SpawnProtection = 2, -- seconds of invulnerability after (re)spawning in

	-- Sparring bots. Live count = BotBaseCount + (players-in-pit − 1), capped.
	BotBaseCount = 2,
	BotMaxCount = 6,
	BotRespawnDelay = 5,
	-- A bot chasing beyond this distance from its home pad gives up, walks
	-- back, and rapidly heals (same idea as jungle leashing).
	LeashRange = 85,
	Bots = {
		-- Melee chaser. Tanky-ish so it survives long enough to pressure you.
		Bruiser = {
			MaxHP = 700,
			WalkSpeed = 13,
			AttackDamage = 16,
			AttackRange = 8,
			AttackInterval = 1.1,
			AggroRadius = 45,
			Size = Vector3.new(3.2, 4.6, 2.6),
			Projectile = false,
		},
		-- Ranged poker. Squishier, keeps its distance, teaches dodging.
		Slinger = {
			MaxHP = 420,
			WalkSpeed = 11,
			AttackDamage = 12,
			AttackRange = 26,
			AttackInterval = 1.5,
			AggroRadius = 45,
			Size = Vector3.new(2.4, 4.0, 2.2),
			Projectile = true,
			ProjectileSpeed = 55,
			ProjectileRadius = 0.9,
		},
	},
	-- Bots spawn cycling through this sequence.
	BotSequence = { "Bruiser", "Slinger", "Bruiser", "Bruiser", "Slinger", "Bruiser" },
}

return Config
