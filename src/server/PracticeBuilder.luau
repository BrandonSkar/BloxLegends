-- PracticeBuilder — builds "The Pit", the lobby's shared free-for-all warm-up
-- arena: a walled brawl floor with scattered player spawn plates, glowing bot
-- home pads, a corner target dummy, cover pillars, and a wall-mounted rankings
-- board (PracticeService writes the text).
--
-- Versioned rebuild: the folder carries a PitBuildVersion attribute. If an
-- older PracticeRoom is baked into the place, it's destroyed and rebuilt so
-- layout changes here always take effect. (The room is fully procedural —
-- unlike the Lobby there's nothing hand-edited to preserve.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PracticeBuilder = {}

local BUILD_VERSION = 2

local COLOR_FLOOR = Color3.fromRGB(38, 40, 52)
local COLOR_WALL = Color3.fromRGB(52, 55, 72)
local COLOR_TRIM = Color3.fromRGB(255, 120, 60) -- ember accent, the Pit's signature color
local COLOR_TRIM_SOFT = Color3.fromRGB(200, 95, 50)

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

-- Flat glowing disc inlaid into the floor (spawn plates, bot pads, center ring).
local function makeFloorDisc(parent, name, pos, diameter, color, transparency)
	return makePart(parent, name, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, diameter, diameter),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = transparency or 0.35,
		CanCollide = false,
		CanQuery = false,
	})
end

-- ===== Layout ===========================================================
-- Everything is placed relative to Config.PracticeOrigin on the floor plane.

-- Player spawn plates: a wide ring so respawns don't dump players on top of
-- each other. (PracticeService picks one at random per spawn.)
local SPAWN_OFFSETS = {
	Vector3.new(-62, 4, 0),
	Vector3.new(62, 4, 0),
	Vector3.new(0, 4, -62),
	Vector3.new(0, 4, 62),
	Vector3.new(-48, 4, -48),
	Vector3.new(48, 4, 48),
}

-- Bot home pads: an inner ring the sparring bots idle on and leash back to.
local BOT_HOME_OFFSETS = {
	Vector3.new(-30, 0, 22),
	Vector3.new(30, 0, 22),
	Vector3.new(-30, 0, -26),
	Vector3.new(30, 0, -26),
	Vector3.new(0, 0, 34),
	Vector3.new(0, 0, -38),
}

-- Cover pillars — break sightlines so ranged practice has dodge geometry.
local PILLAR_OFFSETS = {
	Vector3.new(-18, 0, 0),
	Vector3.new(18, 0, 0),
	Vector3.new(0, 0, 16),
	Vector3.new(0, 0, -18),
}

function PracticeBuilder.getSpawnPos(seed)
	local origin = Config.PracticeOrigin
	local idx
	if seed then
		idx = (seed % #SPAWN_OFFSETS) + 1
	else
		idx = math.random(1, #SPAWN_OFFSETS)
	end
	return origin + SPAWN_OFFSETS[idx]
end

function PracticeBuilder.getBotHomes()
	local origin = Config.PracticeOrigin
	local out = {}
	for _, off in ipairs(BOT_HOME_OFFSETS) do
		table.insert(out, origin + off)
	end
	return out
end

function PracticeBuilder.getDummyPos()
	return Config.PracticeOrigin + Config.PracticeDummyOffset
end

-- ===== Build ============================================================

function PracticeBuilder.build()
	local existing = workspace:FindFirstChild("PracticeRoom")
	if existing then
		if existing:GetAttribute("PitBuildVersion") == BUILD_VERSION then
			return existing
		end
		existing:Destroy()
	end
	local origin = Config.PracticeOrigin
	local size = Config.PracticeRoomSize

	local room = Instance.new("Folder")
	room.Name = "PracticeRoom"
	room:SetAttribute("PitBuildVersion", BUILD_VERSION)
	room.Parent = workspace

	-- Floor
	makePart(room, "Floor", {
		Size = size,
		Position = origin - Vector3.new(0, 0.5, 0),
		Color = COLOR_FLOOR,
		Material = Enum.Material.Slate,
	})

	-- Center brawl ring inlay + soft glow.
	makeFloorDisc(room, "CenterRing", origin + Vector3.new(0, 0.06, 0), 46, COLOR_TRIM_SOFT, 0.75)
	makeFloorDisc(room, "CenterRingCore", origin + Vector3.new(0, 0.07, 0), 8, COLOR_TRIM, 0.3)

	-- Wall ring with an ember trim strip along the top.
	local wallHeight = 20
	local wallThickness = 3
	local hx = size.X / 2
	local hz = size.Z / 2
	local walls = {
		{ size = Vector3.new(size.X + wallThickness * 2, wallHeight, wallThickness), pos = origin + Vector3.new(0, wallHeight / 2, hz), face = "N" },
		{ size = Vector3.new(size.X + wallThickness * 2, wallHeight, wallThickness), pos = origin + Vector3.new(0, wallHeight / 2, -hz), face = "S" },
		{ size = Vector3.new(wallThickness, wallHeight, size.Z), pos = origin + Vector3.new(hx, wallHeight / 2, 0), face = "E" },
		{ size = Vector3.new(wallThickness, wallHeight, size.Z), pos = origin + Vector3.new(-hx, wallHeight / 2, 0), face = "W" },
	}
	for _, w in ipairs(walls) do
		makePart(room, "Wall", {
			Size = w.size,
			Position = w.pos,
			Color = COLOR_WALL,
			Material = Enum.Material.Slate,
		})
		-- Glowing trim strip at the wall's crown.
		local trimSize
		if w.face == "N" or w.face == "S" then
			trimSize = Vector3.new(w.size.X, 0.8, w.size.Z + 0.2)
		else
			trimSize = Vector3.new(w.size.X + 0.2, 0.8, w.size.Z)
		end
		makePart(room, "WallTrim", {
			Size = trimSize,
			Position = w.pos + Vector3.new(0, wallHeight / 2 + 0.4, 0),
			Color = COLOR_TRIM,
			Material = Enum.Material.Neon,
			Transparency = 0.15,
			CanCollide = false,
			CanQuery = false,
		})
	end

	-- Corner watch-pylons with ember caps + light.
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local base = origin + Vector3.new(sx * (hx - 6), 0, sz * (hz - 6))
			makePart(room, "CornerPylon", {
				Size = Vector3.new(4, 26, 4),
				Position = base + Vector3.new(0, 13, 0),
				Color = COLOR_WALL,
				Material = Enum.Material.Slate,
			})
			local cap = makePart(room, "CornerCap", {
				Size = Vector3.new(4.6, 1.4, 4.6),
				Position = base + Vector3.new(0, 26.7, 0),
				Color = COLOR_TRIM,
				Material = Enum.Material.Neon,
				CanCollide = false,
				CanQuery = false,
			})
			local light = Instance.new("PointLight")
			light.Color = COLOR_TRIM
			light.Brightness = 1.6
			light.Range = 26
			light.Parent = cap
		end
	end

	-- Cover pillars (collidable — dodge around them).
	for i, off in ipairs(PILLAR_OFFSETS) do
		makePart(room, "CoverPillar" .. i, {
			Size = Vector3.new(5, 9, 5),
			Position = origin + off + Vector3.new(0, 4.5, 0),
			Color = COLOR_WALL,
			Material = Enum.Material.Slate,
		})
		makePart(room, "CoverPillarCap" .. i, {
			Size = Vector3.new(5.4, 0.6, 5.4),
			Position = origin + off + Vector3.new(0, 9.3, 0),
			Color = COLOR_TRIM_SOFT,
			Material = Enum.Material.Neon,
			Transparency = 0.4,
			CanCollide = false,
			CanQuery = false,
		})
	end

	-- Player spawn plates (cool cyan so they read differently from bot pads).
	for i, off in ipairs(SPAWN_OFFSETS) do
		makeFloorDisc(room, "SpawnPlate" .. i, origin + Vector3.new(off.X, 0.08, off.Z), 8, Color3.fromRGB(110, 200, 255), 0.45)
	end

	-- Bot home pads (ember).
	for i, off in ipairs(BOT_HOME_OFFSETS) do
		makeFloorDisc(room, "BotPad" .. i, origin + Vector3.new(off.X, 0.08, off.Z), 7, COLOR_TRIM_SOFT, 0.5)
	end

	-- Target-dummy corner marker + sign.
	local dummyPos = PracticeBuilder.getDummyPos()
	makeFloorDisc(room, "DummyPad", Vector3.new(dummyPos.X, origin.Y + 0.08, dummyPos.Z), 12, Color3.fromRGB(220, 90, 90), 0.5)
	local sign = makePart(room, "PracticeSign", {
		Size = Vector3.new(8, 0.4, 8),
		Position = Vector3.new(dummyPos.X, origin.Y + 14, dummyPos.Z),
		Color = Color3.fromRGB(200, 80, 80),
		Material = Enum.Material.Neon,
		Transparency = 0.5,
		CanCollide = false,
		CanQuery = false,
	})
	local signGui = Instance.new("BillboardGui")
	signGui.Adornee = sign
	signGui.Size = UDim2.fromOffset(190, 36)
	signGui.StudsOffset = Vector3.new(0, 2.5, 0)
	signGui.AlwaysOnTop = true
	signGui.Parent = sign
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.fromScale(1, 1)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = "TARGET DUMMY"
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.fromRGB(255, 230, 230)
	signLabel.TextStrokeTransparency = 0.3
	signLabel.Parent = signGui

	-- ===== Rankings board on the north wall ============================
	-- PracticeService finds the "BoardText" label and rewrites it as kills
	-- happen. Server-side text changes replicate automatically.
	local board = makePart(room, "PitBoard", {
		Size = Vector3.new(34, 18, 1),
		Position = origin + Vector3.new(0, 12, hz - wallThickness - 0.6),
		Color = Color3.fromRGB(24, 26, 36),
		Material = Enum.Material.SmoothPlastic,
	})
	makePart(room, "PitBoardTrim", {
		Size = Vector3.new(35, 19, 0.6),
		Position = board.Position + Vector3.new(0, 0, 0.3),
		Color = COLOR_TRIM,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
	})
	local surface = Instance.new("SurfaceGui")
	surface.Name = "BoardGui"
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 24
	surface.Parent = board
	local boardTitle = Instance.new("TextLabel")
	boardTitle.Size = UDim2.new(1, 0, 0, 90)
	boardTitle.BackgroundTransparency = 1
	boardTitle.Text = "🔥 PIT RANKINGS 🔥"
	boardTitle.Font = Enum.Font.GothamBlack
	boardTitle.TextScaled = true
	boardTitle.TextColor3 = COLOR_TRIM
	boardTitle.Parent = surface
	local boardText = Instance.new("TextLabel")
	boardText.Name = "BoardText"
	boardText.Size = UDim2.new(1, -40, 1, -110)
	boardText.Position = UDim2.fromOffset(20, 100)
	boardText.BackgroundTransparency = 1
	boardText.Text = "Slay bots and brawlers to claim a spot."
	boardText.Font = Enum.Font.GothamBold
	boardText.TextSize = 34
	boardText.TextColor3 = Color3.fromRGB(235, 238, 245)
	boardText.TextXAlignment = Enum.TextXAlignment.Left
	boardText.TextYAlignment = Enum.TextYAlignment.Top
	boardText.Parent = surface

	return room
end

return PracticeBuilder
