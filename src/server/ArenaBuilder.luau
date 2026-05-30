local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ArenaBuilder = {}

local function makePart(parent, name, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- One big grass plane covering the whole arena. The lane and other features
-- are laid on top — keeps the silhouette clean and the floor seamless.
local function buildGround(parent)
	makePart(parent, "JungleFloor", {
		Size = Vector3.new(Config.Arena.HalfLength * 2, 1, Config.Arena.HalfWidth * 2),
		Position = Vector3.new(0, Config.GroundY - 0.5, 0),
		Color = Color3.fromRGB(55, 95, 60),
		Material = Enum.Material.Grass,
	})
end

-- Flat slab between two waypoints, oriented along the segment.
local function makeLaneSegment(parent, p1, p2)
	local mid = (p1 + p2) / 2 + Vector3.new(0, Config.GroundY - 0.2, 0)
	local diff = p2 - p1
	local length = diff.Magnitude
	local cf = CFrame.lookAt(mid, mid - diff)
	makePart(parent, "LaneFloor", {
		Size = Vector3.new(Config.LaneWidth, 0.6, length + 0.2),
		CFrame = cf,
		Color = Color3.fromRGB(180, 155, 110),
		Material = Enum.Material.Sand,
	})
end

local function buildLane(parent)
	local lane = Instance.new("Folder")
	lane.Name = "Lane"
	lane.Parent = parent
	local waypoints = Config.LaneWaypoints
	for i = 1, #waypoints - 1 do
		makeLaneSegment(lane, waypoints[i], waypoints[i + 1])
	end
end

-- A team base: a wide stone platform behind the nexus with a spawn pad in
-- the center. Players spawn at teamData.SpawnPosition (HRP at y=6, feet at
-- y=3), so the spawn pad's TOP must be at y=3 — that way the character lands
-- directly on the pad without falling.
local function buildBase(parent, teamData)
	local folder = Instance.new("Folder")
	folder.Name = teamData.Name .. "Base"
	folder.Parent = parent

	local sp = teamData.SpawnPosition
	-- Raised stone base platform — thickness 2, top at y=2.
	makePart(folder, "BasePlatform", {
		Size = Vector3.new(70, 2, 110),
		Position = Vector3.new(sp.X, Config.GroundY + 1, sp.Z),
		Color = Color3.fromRGB(100, 105, 115),
		Material = Enum.Material.Slate,
	})

	-- Spawn pad — cylinder on top of the platform. Center at y=2.5, top at y=3
	-- so player feet (at sp.Y - 3 = 3) land flush on the pad.
	makePart(folder, "SpawnPad", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 22, 22),
		CFrame = CFrame.new(sp.X, Config.GroundY + 2.5, sp.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = teamData.Color,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
	})

	-- Glowing team-colored ring around the spawn pad — slightly above the pad
	-- surface so it reads as a halo.
	makePart(folder, "SpawnRing", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 30, 30),
		CFrame = CFrame.new(sp.X, Config.GroundY + 3.1, sp.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = teamData.Color,
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
	})

	-- Decorative back wall behind the spawn.
	local wallX = sp.X + (teamData.SpawnFacing.X * -1) * 28
	makePart(folder, "BackWall", {
		Size = Vector3.new(4, 22, 90),
		Position = Vector3.new(wallX, Config.GroundY + 11, sp.Z),
		Color = Color3.fromRGB(80, 85, 95),
		Material = Enum.Material.Slate,
	})
end

-- Jungle camp pads — visual markers + Attributes the eventual creep AI can
-- query via Workspace descendant lookups (JungleCamp + Team attributes).
local function buildJungleCamps(parent)
	local folder = Instance.new("Folder")
	folder.Name = "JungleCamps"
	folder.Parent = parent

	for _, camp in ipairs(Config.JungleCamps) do
		local pos = camp.position
		local pad = makePart(folder, camp.name .. "Pad", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 18, 18),
			CFrame = CFrame.new(pos.X, Config.GroundY + 0.1, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(80, 82, 92),
			Material = Enum.Material.Slate,
		})
		pad:SetAttribute("JungleCamp", camp.name)
		pad:SetAttribute("Team", camp.team)

		-- Glowing team-colored rune ring so camps read as objectives from afar.
		local ringColor = (camp.team == "Blue")
			and Color3.fromRGB(120, 180, 255)
			or Color3.fromRGB(255, 130, 120)
		makePart(folder, camp.name .. "Ring", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 20, 20),
			CFrame = CFrame.new(pos.X, Config.GroundY + 0.2, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = ringColor,
			Material = Enum.Material.Neon,
			Transparency = 0.4,
		})

		-- Four little stone pillars marking the camp corners.
		for i = 1, 4 do
			local angle = (i - 1) * (math.pi / 2) + math.pi / 4
			local r = 9
			makePart(folder, camp.name .. "Pillar", {
				Size = Vector3.new(1.4, 4.5, 1.4),
				Position = Vector3.new(pos.X + math.cos(angle) * r, Config.GroundY + 2.25, pos.Z + math.sin(angle) * r),
				Color = Color3.fromRGB(95, 95, 105),
				Material = Enum.Material.Slate,
			})
		end
	end
end

-- Boss pit — recessed circular arena in the north jungle. Lower floor + dark
-- stone + glowing rune ring + four obelisks + a central crystal marker.
local function buildBossLair(parent)
	local folder = Instance.new("Folder")
	folder.Name = "BossLair"
	folder.Parent = parent

	local pos = Config.BossLair.position
	local radius = Config.BossLair.pitRadius

	-- Sunken pit floor.
	makePart(folder, "BossPit", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, radius * 2, radius * 2),
		CFrame = CFrame.new(pos.X, Config.GroundY - 0.6, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(50, 40, 70),
		Material = Enum.Material.Slate,
	})

	-- Glowing rune ring.
	makePart(folder, "BossRune", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, radius * 2 + 2, radius * 2 + 2),
		CFrame = CFrame.new(pos.X, Config.GroundY + 0.1, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(200, 60, 220),
		Material = Enum.Material.Neon,
		Transparency = 0.4,
	})

	-- Four obelisks around the pit.
	for i = 1, 4 do
		local angle = (i - 1) * (math.pi / 2) + math.pi / 4
		local r = radius + 1
		makePart(folder, "BossObelisk", {
			Size = Vector3.new(3, 16, 3),
			Position = Vector3.new(pos.X + math.cos(angle) * r, Config.GroundY + 7, pos.Z + math.sin(angle) * r),
			Color = Color3.fromRGB(70, 55, 90),
			Material = Enum.Material.Slate,
		})
	end

	-- Central glowing crystal — the boss spawn marker.
	local crystal = makePart(folder, "BossMarker", {
		Size = Vector3.new(3.5, 7, 3.5),
		CFrame = CFrame.new(pos.X, Config.GroundY + 3, pos.Z) * CFrame.Angles(math.rad(12), math.rad(30), 0),
		Color = Color3.fromRGB(220, 80, 240),
		Material = Enum.Material.Neon,
		Transparency = 0.15,
	})
	crystal:SetAttribute("BossSpawn", true)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(220, 80, 240)
	light.Brightness = 3
	light.Range = 28
	light.Parent = crystal
end

-- Bush positions in the jungle (XZ pairs, mirrored across x=0). Bushes carry
-- IsBush = true so the client BushController hides enemies standing in them.
-- Positions are kept clear of the 50-stud-wide lane — bushes inside the lane
-- would obscure gank entry from cover and break the lane reads.
local BUSH_OFFSETS = {
	-- Mid-lane flanks (both teams contest these for ganks)
	Vector3.new(60, 0, 8), Vector3.new(60, 0, -75),
	-- T1 jungle approaches
	Vector3.new(140, 0, 22), Vector3.new(140, 0, -65),
	-- T2 jungle approaches
	Vector3.new(230, 0, 35), Vector3.new(230, 0, -78),
	-- Deep north jungle near boss
	Vector3.new(70, 0, 60), Vector3.new(40, 0, 105),
	-- Deep south jungle
	Vector3.new(90, 0, -115),
}

local function buildBushes(parent)
	local folder = Instance.new("Folder")
	folder.Name = "Bushes"
	folder.Parent = parent

	-- Each entry placed on both sides (x and -x) — bilateral mirror.
	local n = 0
	for _, off in ipairs(BUSH_OFFSETS) do
		for _, sign in ipairs({ 1, -1 }) do
			n = n + 1
			local bush = makePart(folder, "Bush" .. n, {
				Size = Vector3.new(12, 6, 12),
				Position = Vector3.new(off.X * sign, Config.GroundY + 3, off.Z),
				Color = Color3.fromRGB(40, 80, 50),
				Material = Enum.Material.Grass,
				Transparency = 0.45,
				CanCollide = false,
			})
			bush:SetAttribute("IsBush", true)
		end
	end
end

-- Tower specs (XZ + tier + HP). The Y in basePos is ignored — towers are anchored
-- to Config.GroundY so the visual stack starts at ground level regardless of how
-- tall the model gets. TowerService picks them up via the TowerTeam attribute.
local TOWER_TEAM_COLORS = {
	Blue = {
		plate = Color3.fromRGB(60, 110, 220),
		crystal = Color3.fromRGB(120, 200, 255),
		light = Color3.fromRGB(120, 180, 255),
	},
	Red = {
		plate = Color3.fromRGB(200, 50, 50),
		crystal = Color3.fromRGB(255, 70, 80),
		light = Color3.fromRGB(255, 90, 90),
	},
}

local STONE_DARK = Color3.fromRGB(70, 75, 85)
local STONE_MID = Color3.fromRGB(95, 100, 110)
local STONE_LIGHT = Color3.fromRGB(135, 140, 150)
local GOLD = Color3.fromRGB(220, 170, 60)

-- Tower positions. The nexus sits on the lane centerline. T1 / T2 are offset
-- ~13 studs perpendicular to the lane so that, from each team's perspective
-- walking toward the middle, T1 sits on the player's RIGHT and T2 on the LEFT.
-- (Roblox: facing +X, RightVector = +Z; facing -X, RightVector = -Z.)
-- The lane bows south for both teams, so Blue's right = +Z (north of lane),
-- Red's right = -Z (south of lane).
local TOWER_SPECS = {
	-- Blue side (walking +X toward mid). Lane waypoints: (-200, -20) and (-100, -30).
	{ name = "BlueTowerT1", team = "Blue", tier = 1, basePos = Vector3.new(-100, 0, -17), maxHP = 1500 }, -- right (+Z from lane z=-30)
	{ name = "BlueTowerT2", team = "Blue", tier = 2, basePos = Vector3.new(-200, 0, -33), maxHP = 2200 }, -- left (-Z from lane z=-20)
	{ name = "BlueTowerT3", team = "Blue", tier = 3, basePos = Vector3.new(-280, 0, 0), maxHP = 3000 }, -- center
	-- Red side (walking -X toward mid). Lane waypoints: (100, -30) and (200, -20).
	{ name = "RedTowerT1", team = "Red", tier = 1, basePos = Vector3.new(100, 0, -43), maxHP = 1500 }, -- right (-Z from lane z=-30)
	{ name = "RedTowerT2", team = "Red", tier = 2, basePos = Vector3.new(200, 0, -7), maxHP = 2200 }, -- left (+Z from lane z=-20)
	{ name = "RedTowerT3", team = "Red", tier = 3, basePos = Vector3.new(280, 0, 0), maxHP = 3000 }, -- center
}

-- Build a detailed turret model — stepped stone base, central column with red
-- armor plates and gold trim, decorative spike crown, and a glowing red crystal
-- on top. Tier 3 (the nexus) uses a bigger, distinct crystal-heavy variant.
local function buildTurretTower(parent, spec)
	local model = Instance.new("Model")
	model.Name = spec.name
	model.Parent = parent

	local colors = TOWER_TEAM_COLORS[spec.team]
	local groundY = Config.GroundY or 0
	local cx, cz = spec.basePos.X, spec.basePos.Z

	local function newPart(name, props)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.Slate
		for k, v in pairs(props) do
			p[k] = v
		end
		p.Parent = model
		return p
	end

	-- Cylinder helper: a vertical cylinder of `height` and `diameter`, sitting
	-- with its bottom at groundY + yBottom. Cylinder's long axis is local +X, so
	-- a 90° Z rotation makes local X point along world Y (i.e. "up").
	local function newCylinder(name, height, diameter, yBottom, color, material)
		return newPart(name, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, diameter, diameter),
			CFrame = CFrame.new(cx, groundY + yBottom + height / 2, cz)
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = material or Enum.Material.Slate,
		})
	end

	-- ===== Stepped stone platform =====
	-- The widest cylinder is the root (carries the TowerTeam attributes).
	local base = newCylinder("Base", 4, 22, 0, STONE_DARK)
	base:SetAttribute("TowerTeam", spec.team)
	base:SetAttribute("TowerTier", spec.tier)
	base:SetAttribute("TowerMaxHP", spec.maxHP)

	newCylinder("BaseTier2", 3, 18, 4, STONE_MID)
	newCylinder("BaseTier3", 2, 15, 7, STONE_LIGHT)

	-- A short ring of gold at the platform rim for decoration.
	newCylinder("GoldRim", 0.5, 15.5, 9, GOLD, Enum.Material.Metal)

	-- ===== Central armored column =====
	newPart("Body", {
		Size = Vector3.new(9, 12, 9),
		Position = Vector3.new(cx, groundY + 15.5, cz),
		Color = STONE_LIGHT,
		Material = Enum.Material.Slate,
	})

	-- ===== Armor plates on all four faces of the column =====
	-- Each face gets: a colored armor plate with gold trim above and below.
	local FACE_NORMALS = {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1),
	}
	for _, n in ipairs(FACE_NORMALS) do
		local plateSize, trimSize
		if n.X ~= 0 then
			plateSize = Vector3.new(0.7, 5, 6)
			trimSize = Vector3.new(0.8, 0.5, 6.6)
		else
			plateSize = Vector3.new(6, 5, 0.7)
			trimSize = Vector3.new(6.6, 0.5, 0.8)
		end
		local plateCenter = Vector3.new(cx + n.X * 4.65, groundY + 15.5, cz + n.Z * 4.65)
		newPart("ArmorPlate", {
			Size = plateSize,
			Position = plateCenter,
			Color = colors.plate,
			Material = Enum.Material.Metal,
		})
		-- Gold trim above and below the plate.
		newPart("GoldTrim", {
			Size = trimSize,
			Position = Vector3.new(cx + n.X * 4.7, groundY + 18.3, cz + n.Z * 4.7),
			Color = GOLD,
			Material = Enum.Material.Metal,
		})
		newPart("GoldTrim", {
			Size = trimSize,
			Position = Vector3.new(cx + n.X * 4.7, groundY + 12.7, cz + n.Z * 4.7),
			Color = GOLD,
			Material = Enum.Material.Metal,
		})
	end

	-- ===== Top platform =====
	newCylinder("TopPlatform", 2, 11, 21.5, STONE_DARK)
	newCylinder("TopRim", 0.4, 12, 23.5, GOLD, Enum.Material.Metal)

	-- ===== Decorative spike crown =====
	for i = 1, 6 do
		local angle = (i - 1) * (math.pi * 2 / 6)
		local r = 5.2
		newPart("Spike", {
			Size = Vector3.new(0.7, 3.5, 0.7),
			Position = Vector3.new(cx + math.cos(angle) * r, groundY + 25, cz + math.sin(angle) * r),
			Color = GOLD,
			Material = Enum.Material.Metal,
		})
	end

	-- ===== Turret block (used for the targeting beam endpoint) =====
	newPart("Turret", {
		Size = Vector3.new(1.6, 1.6, 3.2),
		Position = Vector3.new(cx, groundY + 27, cz),
		Color = STONE_DARK,
		Material = Enum.Material.Metal,
	})

	-- ===== Glowing crystal on top =====
	local crystal = newPart("Crystal", {
		Size = Vector3.new(2.4, 5, 2.4),
		CFrame = CFrame.new(cx, groundY + 30, cz)
			* CFrame.Angles(math.rad(12), math.rad(30), math.rad(0)),
		Color = colors.crystal,
		Material = Enum.Material.Neon,
	})
	newPart("CrystalSmall", {
		Size = Vector3.new(1.3, 3, 1.3),
		CFrame = CFrame.new(cx + 1.4, groundY + 29, cz - 0.9)
			* CFrame.Angles(math.rad(-22), math.rad(-15), math.rad(8)),
		Color = colors.crystal,
		Material = Enum.Material.Neon,
	})

	local light = Instance.new("PointLight")
	light.Color = colors.light
	light.Brightness = 3
	light.Range = 18
	light.Parent = crystal

	-- ===== Invisible HP anchor for the HP bar =====
	-- The base cylinder is rotated 90° around Z, which throws StudsOffset off
	-- (the bar ends up to the side of the tower). A non-rotated tiny anchor
	-- above the crystal lets TowerService adornee the bar in clean world space.
	newPart("HPAnchor", {
		Size = Vector3.new(0.1, 0.1, 0.1),
		Position = Vector3.new(cx, groundY + 36, cz),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end

-- The nexus is the team's tier-3 structure. Built bigger and more crystal-heavy
-- to read as "this is the win condition" at a glance.
local function buildNexusTower(parent, spec)
	local model = Instance.new("Model")
	model.Name = spec.name
	model.Parent = parent

	local colors = TOWER_TEAM_COLORS[spec.team]
	local groundY = Config.GroundY or 0
	local cx, cz = spec.basePos.X, spec.basePos.Z

	local function newPart(name, props)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.Slate
		for k, v in pairs(props) do
			p[k] = v
		end
		p.Parent = model
		return p
	end

	local function newCylinder(name, height, diameter, yBottom, color, material)
		return newPart(name, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, diameter, diameter),
			CFrame = CFrame.new(cx, groundY + yBottom + height / 2, cz)
				* CFrame.Angles(0, 0, math.rad(90)),
			Color = color,
			Material = material or Enum.Material.Slate,
		})
	end

	-- ===== Wider stepped platform =====
	local base = newCylinder("Base", 5, 34, 0, STONE_DARK)
	base:SetAttribute("TowerTeam", spec.team)
	base:SetAttribute("TowerTier", spec.tier)
	base:SetAttribute("TowerMaxHP", spec.maxHP)

	newCylinder("BaseTier2", 3, 28, 5, STONE_MID)
	newCylinder("BaseTier3", 2, 22, 8, STONE_LIGHT)
	newCylinder("GoldRim", 0.6, 22.4, 10, GOLD, Enum.Material.Metal)

	-- ===== Crystal pedestal: low cylinder with armor plates =====
	newPart("Pedestal", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 14, 14),
		CFrame = CFrame.new(cx, groundY + 12, cz) * CFrame.Angles(0, 0, math.rad(90)),
		Color = STONE_LIGHT,
		Material = Enum.Material.Slate,
	})

	-- Four armor panels around the pedestal.
	for i = 1, 4 do
		local angle = (i - 1) * (math.pi / 2)
		local n = Vector3.new(math.cos(angle), 0, math.sin(angle))
		newPart("PedestalPlate", {
			Size = Vector3.new(4, 2.2, 0.6),
			CFrame = CFrame.new(cx + n.X * 7.1, groundY + 12, cz + n.Z * 7.1)
				* CFrame.fromMatrix(Vector3.zero, Vector3.new(n.Z, 0, -n.X), Vector3.new(0, 1, 0)),
			Color = colors.plate,
			Material = Enum.Material.Metal,
		})
	end

	-- ===== Giant central crystal — the nexus core =====
	local nexusCore = newPart("NexusCore", {
		Size = Vector3.new(5, 12, 5),
		CFrame = CFrame.new(cx, groundY + 20, cz)
			* CFrame.Angles(math.rad(8), math.rad(25), 0),
		Color = colors.crystal,
		Material = Enum.Material.Neon,
	})

	-- Two satellite crystals tilted off the core for variety.
	newPart("NexusShardA", {
		Size = Vector3.new(2.2, 7, 2.2),
		CFrame = CFrame.new(cx + 2.5, groundY + 17, cz - 1.5)
			* CFrame.Angles(math.rad(-25), math.rad(15), math.rad(15)),
		Color = colors.crystal,
		Material = Enum.Material.Neon,
	})
	newPart("NexusShardB", {
		Size = Vector3.new(1.8, 6, 1.8),
		CFrame = CFrame.new(cx - 2.2, groundY + 16, cz + 1.8)
			* CFrame.Angles(math.rad(18), math.rad(-20), math.rad(-12)),
		Color = colors.crystal,
		Material = Enum.Material.Neon,
	})

	-- Big light from the central core.
	local light = Instance.new("PointLight")
	light.Color = colors.light
	light.Brightness = 5
	light.Range = 30
	light.Parent = nexusCore

	-- Ring of decorative spikes around the pedestal.
	for i = 1, 8 do
		local angle = (i - 1) * (math.pi * 2 / 8)
		local r = 9
		newPart("Spike", {
			Size = Vector3.new(0.8, 4.5, 0.8),
			Position = Vector3.new(cx + math.cos(angle) * r, groundY + 13.5, cz + math.sin(angle) * r),
			Color = GOLD,
			Material = Enum.Material.Metal,
		})
	end

	-- Turret child (used for the targeting beam endpoint). Tucked behind the core.
	newPart("Turret", {
		Size = Vector3.new(1.4, 1.4, 2.4),
		Position = Vector3.new(cx, groundY + 13.5, cz),
		Color = STONE_DARK,
		Material = Enum.Material.Metal,
	})

	-- HP anchor — above the giant crystal.
	newPart("HPAnchor", {
		Size = Vector3.new(0.1, 0.1, 0.1),
		Position = Vector3.new(cx, groundY + 32, cz),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end

local function buildTower(parent, spec)
	if spec.tier == 3 then
		buildNexusTower(parent, spec)
	else
		buildTurretTower(parent, spec)
	end
end

local function buildTowers(parent)
	-- Idempotent — wipe and rebuild so re-running the script picks up new towers.
	local old = parent:FindFirstChild("Towers")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Towers"
	folder.Parent = parent
	for _, spec in ipairs(TOWER_SPECS) do
		buildTower(folder, spec)
	end
end

local function buildBoundary(parent)
	local folder = Instance.new("Folder")
	folder.Name = "Boundary"
	folder.Parent = parent
	local hl = Config.Arena.HalfLength + 20
	local hw = Config.Arena.HalfWidth + 20
	local walls = {
		{ size = Vector3.new(hl * 2, 24, 2), pos = Vector3.new(0, 12, hw) },
		{ size = Vector3.new(hl * 2, 24, 2), pos = Vector3.new(0, 12, -hw) },
		{ size = Vector3.new(2, 24, hw * 2), pos = Vector3.new(hl, 12, 0) },
		{ size = Vector3.new(2, 24, hw * 2), pos = Vector3.new(-hl, 12, 0) },
	}
	for _, w in ipairs(walls) do
		makePart(folder, "Wall", {
			Size = w.size,
			Position = w.pos,
			Color = Color3.fromRGB(80, 80, 90),
			Transparency = 0.85,
		})
	end
end

function ArenaBuilder.build()
	-- The saved Arena in the place file is the source of truth — bake your
	-- layout via tools/BuildArenaInStudio.luau, save the place, and the runtime
	-- uses what's there verbatim. The script only builds from scratch as a
	-- fallback when no Arena exists (e.g. a fresh place file). TowerService
	-- picks up the towers by scanning for the TowerTeam attribute, so no need
	-- to call buildTowers separately when the saved arena already has them.
	local existing = workspace:FindFirstChild("Arena")
	if existing then
		return existing
	end

	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	arena.Parent = workspace

	buildGround(arena)
	buildLane(arena)
	buildBase(arena, Config.Teams.Blue)
	buildBase(arena, Config.Teams.Red)
	buildJungleCamps(arena)
	buildBossLair(arena)
	buildBushes(arena)
	buildTowers(arena)
	buildBoundary(arena)

	return arena
end

return ArenaBuilder
