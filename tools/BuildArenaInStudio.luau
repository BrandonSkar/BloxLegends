--!nocheck
-- ===========================================================================
-- BuildArenaInStudio.luau — STANDALONE
-- Paste this entire script into Studio's Command Bar (View → Command Bar)
-- while in Edit Mode (not Play). It will delete any existing "Arena" folder
-- in Workspace and rebuild the full map: ground, lane, bases, jungle camps,
-- boss pit, bushes, and the 6 detailed towers.
--
-- After it finishes, save the place so the arena is baked into the .rbxl.
-- ===========================================================================

local Workspace = game:GetService("Workspace")

-- =========== Constants (mirrors src/shared/Config.luau) ===========
local GROUND_Y = 0
local LANE_WIDTH = 50

local ARENA_HALF_LENGTH = 360
local ARENA_HALF_WIDTH = 170

local LANE_WAYPOINTS = {
	Vector3.new(-280, 0, 0),
	Vector3.new(-200, 0, -20),
	Vector3.new(-100, 0, -30),
	Vector3.new(0, 0, -35),
	Vector3.new(100, 0, -30),
	Vector3.new(200, 0, -20),
	Vector3.new(280, 0, 0),
}

local TEAMS = {
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

local JUNGLE_CAMPS = {
	{ name = "BlueCampNorth", team = "Blue", position = Vector3.new(-160, 0, 50) },
	{ name = "BlueCampSouth", team = "Blue", position = Vector3.new(-160, 0, -95) },
	{ name = "RedCampNorth", team = "Red", position = Vector3.new(160, 0, 50) },
	{ name = "RedCampSouth", team = "Red", position = Vector3.new(160, 0, -95) },
}

local BOSS_POSITION = Vector3.new(0, 0, 80)
local BOSS_PIT_RADIUS = 22

-- Mirror around x=0 — each entry gets placed at both (x, z) and (-x, z).
-- Positions sit clear of the 50-stud-wide lane.
local BUSH_OFFSETS = {
	Vector3.new(60, 0, 8), Vector3.new(60, 0, -75),
	Vector3.new(140, 0, 22), Vector3.new(140, 0, -65),
	Vector3.new(230, 0, 35), Vector3.new(230, 0, -78),
	Vector3.new(70, 0, 60), Vector3.new(40, 0, 105),
	Vector3.new(90, 0, -115),
}

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

-- Nexus on the lane centerline; T1 / T2 offset 13 studs perpendicular to the
-- lane so that, from each team's POV walking toward mid, T1 is on the right
-- and T2 is on the left. (Roblox: facing +X RightVector = +Z; facing -X = -Z.)
local TOWER_SPECS = {
	{ name = "BlueTowerT1", team = "Blue", tier = 1, basePos = Vector3.new(-100, 0, -17), maxHP = 1500 },
	{ name = "BlueTowerT2", team = "Blue", tier = 2, basePos = Vector3.new(-200, 0, -33), maxHP = 2200 },
	{ name = "BlueTowerT3", team = "Blue", tier = 3, basePos = Vector3.new(-280, 0, 0), maxHP = 3000 },
	{ name = "RedTowerT1", team = "Red", tier = 1, basePos = Vector3.new(100, 0, -43), maxHP = 1500 },
	{ name = "RedTowerT2", team = "Red", tier = 2, basePos = Vector3.new(200, 0, -7), maxHP = 2200 },
	{ name = "RedTowerT3", team = "Red", tier = 3, basePos = Vector3.new(280, 0, 0), maxHP = 3000 },
}

-- =========== Part helper ===========
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

-- =========== Build steps ===========

local function buildGround(parent)
	makePart(parent, "JungleFloor", {
		Size = Vector3.new(ARENA_HALF_LENGTH * 2, 1, ARENA_HALF_WIDTH * 2),
		Position = Vector3.new(0, GROUND_Y - 0.5, 0),
		Color = Color3.fromRGB(55, 95, 60),
		Material = Enum.Material.Grass,
	})
end

local function buildLane(parent)
	local lane = Instance.new("Folder")
	lane.Name = "Lane"
	lane.Parent = parent
	for i = 1, #LANE_WAYPOINTS - 1 do
		local p1 = LANE_WAYPOINTS[i]
		local p2 = LANE_WAYPOINTS[i + 1]
		local mid = (p1 + p2) / 2 + Vector3.new(0, GROUND_Y - 0.2, 0)
		local diff = p2 - p1
		local length = diff.Magnitude
		makePart(lane, "LaneFloor", {
			Size = Vector3.new(LANE_WIDTH, 0.6, length + 0.2),
			CFrame = CFrame.lookAt(mid, mid - diff),
			Color = Color3.fromRGB(180, 155, 110),
			Material = Enum.Material.Sand,
		})
	end
end

local function buildBase(parent, teamData)
	local folder = Instance.new("Folder")
	folder.Name = teamData.Name .. "Base"
	folder.Parent = parent

	local sp = teamData.SpawnPosition

	-- Raised stone platform — thickness 2, top at y=2.
	makePart(folder, "BasePlatform", {
		Size = Vector3.new(70, 2, 110),
		Position = Vector3.new(sp.X, GROUND_Y + 1, sp.Z),
		Color = Color3.fromRGB(100, 105, 115),
		Material = Enum.Material.Slate,
	})

	-- Spawn pad on top of the platform — top at y=3 so the player's feet land
	-- flush on it from SpawnPosition.Y = 6 (HRP) → feet y=3.
	makePart(folder, "SpawnPad", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1, 22, 22),
		CFrame = CFrame.new(sp.X, GROUND_Y + 2.5, sp.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = teamData.Color,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
	})

	makePart(folder, "SpawnRing", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 30, 30),
		CFrame = CFrame.new(sp.X, GROUND_Y + 3.1, sp.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = teamData.Color,
		Material = Enum.Material.Neon,
		Transparency = 0.4,
		CanCollide = false,
	})

	local wallX = sp.X + (teamData.SpawnFacing.X * -1) * 28
	makePart(folder, "BackWall", {
		Size = Vector3.new(4, 22, 90),
		Position = Vector3.new(wallX, GROUND_Y + 11, sp.Z),
		Color = Color3.fromRGB(80, 85, 95),
		Material = Enum.Material.Slate,
	})
end

local function buildJungleCamps(parent)
	local folder = Instance.new("Folder")
	folder.Name = "JungleCamps"
	folder.Parent = parent

	for _, camp in ipairs(JUNGLE_CAMPS) do
		local pos = camp.position
		local pad = makePart(folder, camp.name .. "Pad", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.6, 18, 18),
			CFrame = CFrame.new(pos.X, GROUND_Y + 0.1, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(80, 82, 92),
			Material = Enum.Material.Slate,
		})
		pad:SetAttribute("JungleCamp", camp.name)
		pad:SetAttribute("Team", camp.team)

		local ringColor = (camp.team == "Blue")
			and Color3.fromRGB(120, 180, 255)
			or Color3.fromRGB(255, 130, 120)
		makePart(folder, camp.name .. "Ring", {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 20, 20),
			CFrame = CFrame.new(pos.X, GROUND_Y + 0.2, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = ringColor,
			Material = Enum.Material.Neon,
			Transparency = 0.4,
		})

		for i = 1, 4 do
			local angle = (i - 1) * (math.pi / 2) + math.pi / 4
			local r = 9
			makePart(folder, camp.name .. "Pillar", {
				Size = Vector3.new(1.4, 4.5, 1.4),
				Position = Vector3.new(pos.X + math.cos(angle) * r, GROUND_Y + 2.25, pos.Z + math.sin(angle) * r),
				Color = Color3.fromRGB(95, 95, 105),
				Material = Enum.Material.Slate,
			})
		end
	end
end

local function buildBossLair(parent)
	local folder = Instance.new("Folder")
	folder.Name = "BossLair"
	folder.Parent = parent

	local pos = BOSS_POSITION
	local radius = BOSS_PIT_RADIUS

	makePart(folder, "BossPit", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(1.2, radius * 2, radius * 2),
		CFrame = CFrame.new(pos.X, GROUND_Y - 0.6, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(50, 40, 70),
		Material = Enum.Material.Slate,
	})

	makePart(folder, "BossRune", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, radius * 2 + 2, radius * 2 + 2),
		CFrame = CFrame.new(pos.X, GROUND_Y + 0.1, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(200, 60, 220),
		Material = Enum.Material.Neon,
		Transparency = 0.4,
	})

	for i = 1, 4 do
		local angle = (i - 1) * (math.pi / 2) + math.pi / 4
		local r = radius + 1
		makePart(folder, "BossObelisk", {
			Size = Vector3.new(3, 16, 3),
			Position = Vector3.new(pos.X + math.cos(angle) * r, GROUND_Y + 7, pos.Z + math.sin(angle) * r),
			Color = Color3.fromRGB(70, 55, 90),
			Material = Enum.Material.Slate,
		})
	end

	local crystal = makePart(folder, "BossMarker", {
		Size = Vector3.new(3.5, 7, 3.5),
		CFrame = CFrame.new(pos.X, GROUND_Y + 3, pos.Z) * CFrame.Angles(math.rad(12), math.rad(30), 0),
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

local function buildBushes(parent)
	local folder = Instance.new("Folder")
	folder.Name = "Bushes"
	folder.Parent = parent

	local n = 0
	for _, off in ipairs(BUSH_OFFSETS) do
		for _, sign in ipairs({ 1, -1 }) do
			n = n + 1
			local bush = makePart(folder, "Bush" .. n, {
				Size = Vector3.new(12, 6, 12),
				Position = Vector3.new(off.X * sign, GROUND_Y + 3, off.Z),
				Color = Color3.fromRGB(40, 80, 50),
				Material = Enum.Material.Grass,
				Transparency = 0.45,
				CanCollide = false,
			})
			bush:SetAttribute("IsBush", true)
		end
	end
end

-- =========== Tower builders ===========

local function newTowerPart(model, name, props)
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

local function newCylinder(model, name, height, diameter, yBottom, color, material, cx, cz)
	return newTowerPart(model, name, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(cx, GROUND_Y + yBottom + height / 2, cz)
			* CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material or Enum.Material.Slate,
	})
end

local function buildTurretTower(parent, spec)
	local model = Instance.new("Model")
	model.Name = spec.name
	model.Parent = parent

	local colors = TOWER_TEAM_COLORS[spec.team]
	local cx, cz = spec.basePos.X, spec.basePos.Z

	local base = newCylinder(model, "Base", 4, 22, 0, STONE_DARK, nil, cx, cz)
	base:SetAttribute("TowerTeam", spec.team)
	base:SetAttribute("TowerTier", spec.tier)
	base:SetAttribute("TowerMaxHP", spec.maxHP)

	newCylinder(model, "BaseTier2", 3, 18, 4, STONE_MID, nil, cx, cz)
	newCylinder(model, "BaseTier3", 2, 15, 7, STONE_LIGHT, nil, cx, cz)
	newCylinder(model, "GoldRim", 0.5, 15.5, 9, GOLD, Enum.Material.Metal, cx, cz)

	newTowerPart(model, "Body", {
		Size = Vector3.new(9, 12, 9),
		Position = Vector3.new(cx, GROUND_Y + 15.5, cz),
		Color = STONE_LIGHT,
		Material = Enum.Material.Slate,
	})

	local FACE_NORMALS = {
		Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
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
		newTowerPart(model, "ArmorPlate", {
			Size = plateSize,
			Position = Vector3.new(cx + n.X * 4.65, GROUND_Y + 15.5, cz + n.Z * 4.65),
			Color = colors.plate,
			Material = Enum.Material.Metal,
		})
		newTowerPart(model, "GoldTrim", {
			Size = trimSize,
			Position = Vector3.new(cx + n.X * 4.7, GROUND_Y + 18.3, cz + n.Z * 4.7),
			Color = GOLD,
			Material = Enum.Material.Metal,
		})
		newTowerPart(model, "GoldTrim", {
			Size = trimSize,
			Position = Vector3.new(cx + n.X * 4.7, GROUND_Y + 12.7, cz + n.Z * 4.7),
			Color = GOLD,
			Material = Enum.Material.Metal,
		})
	end

	newCylinder(model, "TopPlatform", 2, 11, 21.5, STONE_DARK, nil, cx, cz)
	newCylinder(model, "TopRim", 0.4, 12, 23.5, GOLD, Enum.Material.Metal, cx, cz)

	for i = 1, 6 do
		local angle = (i - 1) * (math.pi * 2 / 6)
		local r = 5.2
		newTowerPart(model, "Spike", {
			Size = Vector3.new(0.7, 3.5, 0.7),
			Position = Vector3.new(cx + math.cos(angle) * r, GROUND_Y + 25, cz + math.sin(angle) * r),
			Color = GOLD,
			Material = Enum.Material.Metal,
		})
	end

	newTowerPart(model, "Turret", {
		Size = Vector3.new(1.6, 1.6, 3.2),
		Position = Vector3.new(cx, GROUND_Y + 27, cz),
		Color = STONE_DARK,
		Material = Enum.Material.Metal,
	})

	local crystal = newTowerPart(model, "Crystal", {
		Size = Vector3.new(2.4, 5, 2.4),
		CFrame = CFrame.new(cx, GROUND_Y + 30, cz)
			* CFrame.Angles(math.rad(12), math.rad(30), math.rad(0)),
		Color = colors.crystal,
		Material = Enum.Material.Neon,
	})
	newTowerPart(model, "CrystalSmall", {
		Size = Vector3.new(1.3, 3, 1.3),
		CFrame = CFrame.new(cx + 1.4, GROUND_Y + 29, cz - 0.9)
			* CFrame.Angles(math.rad(-22), math.rad(-15), math.rad(8)),
		Color = colors.crystal,
		Material = Enum.Material.Neon,
	})

	local light = Instance.new("PointLight")
	light.Color = colors.light
	light.Brightness = 3
	light.Range = 18
	light.Parent = crystal

	newTowerPart(model, "HPAnchor", {
		Size = Vector3.new(0.1, 0.1, 0.1),
		Position = Vector3.new(cx, GROUND_Y + 36, cz),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end

local function buildNexusTower(parent, spec)
	local model = Instance.new("Model")
	model.Name = spec.name
	model.Parent = parent

	local colors = TOWER_TEAM_COLORS[spec.team]
	local cx, cz = spec.basePos.X, spec.basePos.Z

	local base = newCylinder(model, "Base", 5, 34, 0, STONE_DARK, nil, cx, cz)
	base:SetAttribute("TowerTeam", spec.team)
	base:SetAttribute("TowerTier", spec.tier)
	base:SetAttribute("TowerMaxHP", spec.maxHP)

	newCylinder(model, "BaseTier2", 3, 28, 5, STONE_MID, nil, cx, cz)
	newCylinder(model, "BaseTier3", 2, 22, 8, STONE_LIGHT, nil, cx, cz)
	newCylinder(model, "GoldRim", 0.6, 22.4, 10, GOLD, Enum.Material.Metal, cx, cz)

	newTowerPart(model, "Pedestal", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3, 14, 14),
		CFrame = CFrame.new(cx, GROUND_Y + 12, cz) * CFrame.Angles(0, 0, math.rad(90)),
		Color = STONE_LIGHT,
		Material = Enum.Material.Slate,
	})

	for i = 1, 4 do
		local angle = (i - 1) * (math.pi / 2)
		local n = Vector3.new(math.cos(angle), 0, math.sin(angle))
		newTowerPart(model, "PedestalPlate", {
			Size = Vector3.new(4, 2.2, 0.6),
			CFrame = CFrame.new(cx + n.X * 7.1, GROUND_Y + 12, cz + n.Z * 7.1)
				* CFrame.fromMatrix(Vector3.zero, Vector3.new(n.Z, 0, -n.X), Vector3.new(0, 1, 0)),
			Color = colors.plate,
			Material = Enum.Material.Metal,
		})
	end

	local nexusCore = newTowerPart(model, "NexusCore", {
		Size = Vector3.new(5, 12, 5),
		CFrame = CFrame.new(cx, GROUND_Y + 20, cz)
			* CFrame.Angles(math.rad(8), math.rad(25), 0),
		Color = colors.crystal,
		Material = Enum.Material.Neon,
	})

	newTowerPart(model, "NexusShardA", {
		Size = Vector3.new(2.2, 7, 2.2),
		CFrame = CFrame.new(cx + 2.5, GROUND_Y + 17, cz - 1.5)
			* CFrame.Angles(math.rad(-25), math.rad(15), math.rad(15)),
		Color = colors.crystal,
		Material = Enum.Material.Neon,
	})
	newTowerPart(model, "NexusShardB", {
		Size = Vector3.new(1.8, 6, 1.8),
		CFrame = CFrame.new(cx - 2.2, GROUND_Y + 16, cz + 1.8)
			* CFrame.Angles(math.rad(18), math.rad(-20), math.rad(-12)),
		Color = colors.crystal,
		Material = Enum.Material.Neon,
	})

	local light = Instance.new("PointLight")
	light.Color = colors.light
	light.Brightness = 5
	light.Range = 30
	light.Parent = nexusCore

	for i = 1, 8 do
		local angle = (i - 1) * (math.pi * 2 / 8)
		local r = 9
		newTowerPart(model, "Spike", {
			Size = Vector3.new(0.8, 4.5, 0.8),
			Position = Vector3.new(cx + math.cos(angle) * r, GROUND_Y + 13.5, cz + math.sin(angle) * r),
			Color = GOLD,
			Material = Enum.Material.Metal,
		})
	end

	newTowerPart(model, "Turret", {
		Size = Vector3.new(1.4, 1.4, 2.4),
		Position = Vector3.new(cx, GROUND_Y + 13.5, cz),
		Color = STONE_DARK,
		Material = Enum.Material.Metal,
	})

	newTowerPart(model, "HPAnchor", {
		Size = Vector3.new(0.1, 0.1, 0.1),
		Position = Vector3.new(cx, GROUND_Y + 32, cz),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end

local function buildTowers(parent)
	local folder = Instance.new("Folder")
	folder.Name = "Towers"
	folder.Parent = parent
	for _, spec in ipairs(TOWER_SPECS) do
		if spec.tier == 3 then
			buildNexusTower(folder, spec)
		else
			buildTurretTower(folder, spec)
		end
	end
end

local function buildBoundary(parent)
	local folder = Instance.new("Folder")
	folder.Name = "Boundary"
	folder.Parent = parent
	local hl = ARENA_HALF_LENGTH + 20
	local hw = ARENA_HALF_WIDTH + 20
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

-- =========== Entry point ===========

local existing = Workspace:FindFirstChild("Arena")
if existing then
	existing:Destroy()
end

local arena = Instance.new("Folder")
arena.Name = "Arena"
arena.Parent = Workspace

buildGround(arena)
buildLane(arena)
buildBase(arena, TEAMS.Blue)
buildBase(arena, TEAMS.Red)
buildJungleCamps(arena)
buildBossLair(arena)
buildBushes(arena)
buildTowers(arena)
buildBoundary(arena)

print("[BuildArenaInStudio] Arena built — save the place to bake it in.")
