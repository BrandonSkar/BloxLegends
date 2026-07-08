-- LobbyBuilder — builds the lobby hub: a central spawn plaza, the queue-zone
-- pad row, a shop pavilion, and the glowing portal to The Pit, ringed by
-- banner-lined walkways and perimeter pylons.
--
-- Two build paths, one look:
--   • Fresh build: everything is generated from scratch.
--   • Baked lobby (Workspace.Lobby already exists, e.g. via
--     tools/BakeWorldInStudio): the structural pieces (floor, pads, kiosk) are
--     reused, and ALL cosmetics are rebuilt idempotently into a "Decor"
--     folder — so visual upgrades here always show up, baked or not.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LobbyBuilder = {}

-- ===== Palette ==========================================================

local COLOR_FLOOR = Color3.fromRGB(44, 47, 62)
local COLOR_STONE = Color3.fromRGB(58, 62, 82)
local COLOR_STONE_DARK = Color3.fromRGB(36, 39, 52)
local COLOR_GOLD = Color3.fromRGB(255, 195, 80) -- lobby accent (matches the UI palette)
local COLOR_EMBER = Color3.fromRGB(255, 120, 60) -- The Pit's signature color
local COLOR_CYAN = Color3.fromRGB(110, 200, 255)

local ZONE_COLORS = {
	Color3.fromRGB(80, 140, 220),
	Color3.fromRGB(220, 100, 100),
	Color3.fromRGB(120, 200, 110),
	Color3.fromRGB(220, 200, 90),
	Color3.fromRGB(180, 120, 220),
	Color3.fromRGB(220, 150, 90),
}

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

-- Thin glowing disc laid flat on the floor.
local function makeFloorDisc(parent, name, pos, diameter, color, transparency)
	return makePart(parent, name, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.25, diameter, diameter),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = transparency or 0.4,
		CanCollide = false,
		CanQuery = false,
	})
end

-- Flat glowing strip on the floor from `fromPos` to `toPos` (XZ).
local function makeWalkStrip(parent, name, fromPos, toPos, width, color)
	local mid = (fromPos + toPos) / 2
	local len = (toPos - fromPos).Magnitude
	return makePart(parent, name, {
		Size = Vector3.new(width, 0.15, len),
		CFrame = CFrame.lookAt(mid, toPos),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.62,
		CanCollide = false,
		CanQuery = false,
	})
end

local function attachLight(part, color, brightness, range)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness or 1.5
	light.Range = range or 20
	light.Shadows = false
	light.Parent = part
	return light
end

-- Soft ambient ember/sparkle column (client-simulated → free motion).
local function attachAmbientParticles(part, color, rate)
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	em.Color = ColorSequence.new(color)
	em.LightEmission = 0.9
	em.Lifetime = NumberRange.new(1.6, 2.6)
	em.Speed = NumberRange.new(2, 5)
	em.SpreadAngle = Vector2.new(14, 14)
	em.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	em.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	em.Rate = rate or 6
	em.Parent = part
	return em
end

-- ===== Zone-pad row layout =====
-- The zone pads sit in a straight row (left → right along X), evenly spaced
-- with a small gap, centered on the lobby origin's X and pushed out ROW_Z in
-- front. Both the procedural builder and the baked-lobby reuse path place pads
-- here so the arrangement is identical either way.
local PAD_SIZE = 18
local PAD_GAP = 6 -- studs of empty space between adjacent pads
local ROW_Z = 40 -- how far in front of the plaza the row sits

-- Landmark positions (relative to the lobby origin).
local SHOP_OFFSET = Vector3.new(-52, 0, -10)
local PORTAL_OFFSET = Vector3.new(0, 0, -60)

-- Pad-center position (at the origin's floor height) for zone `id` in a row of
-- `count` pads. id=1 is the far-left pad, id=count the far-right.
local function rowPadPosition(origin, id, count)
	local spacing = PAD_SIZE + PAD_GAP
	local xOffset = (id - 1 - (count - 1) / 2) * spacing
	return origin + Vector3.new(xOffset, 0, ROW_Z)
end

-- Build a ring of 4 translucent ForceField walls around a zone pad so players
-- can't walk into the zone — they have to use the proximity prompt to join.
-- Idempotent: removes any existing ZoneWalls folder and rebuilds.
local function buildZoneWalls(pad)
	local existing = pad:FindFirstChild("ZoneWalls")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "ZoneWalls"
	folder.Parent = pad

	local center = pad.Position
	local sx, sz = pad.Size.X, pad.Size.Z
	local wallHeight = 14
	local wallThickness = 1
	local hx = sx / 2 + 0.5
	local hz = sz / 2 + 0.5

	local function makeWall(name, size, offset)
		local w = Instance.new("Part")
		w.Name = name
		w.Anchored = true
		w.CanCollide = true
		w.CanQuery = false
		w.Size = size
		w.Position = center + offset + Vector3.new(0, wallHeight / 2, 0)
		w.Color = pad.Color
		w.Material = Enum.Material.ForceField
		w.Transparency = 0.4
		w.Parent = folder
	end
	makeWall("North", Vector3.new(hx * 2 + wallThickness * 2, wallHeight, wallThickness), Vector3.new(0, 0, hz))
	makeWall("South", Vector3.new(hx * 2 + wallThickness * 2, wallHeight, wallThickness), Vector3.new(0, 0, -hz))
	makeWall("East", Vector3.new(wallThickness, wallHeight, hz * 2), Vector3.new(hx, 0, 0))
	makeWall("West", Vector3.new(wallThickness, wallHeight, hz * 2), Vector3.new(-hx, 0, 0))
end

-- Perimeter walls around the whole lobby floor (200×200, centered on origin) so
-- players can't walk off the edge. Idempotent — rebuilds the LobbyWalls folder,
-- so it applies whether the lobby is freshly built or reused from the place.
local LOBBY_HALF = 100
local function buildLobbyWalls(lobby, origin)
	local existing = lobby:FindFirstChild("LobbyWalls")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "LobbyWalls"
	folder.Parent = lobby
	local h = LOBBY_HALF
	local height = 20
	local t = 2 -- wall thickness
	local walls = {
		{ size = Vector3.new(h * 2 + t * 2, height, t), pos = Vector3.new(0, height / 2, h) },
		{ size = Vector3.new(h * 2 + t * 2, height, t), pos = Vector3.new(0, height / 2, -h) },
		{ size = Vector3.new(t, height, h * 2), pos = Vector3.new(h, height / 2, 0) },
		{ size = Vector3.new(t, height, h * 2), pos = Vector3.new(-h, height / 2, 0) },
	}
	for _, w in ipairs(walls) do
		makePart(folder, "Wall", {
			Size = w.size,
			Position = origin + w.pos,
			Color = Color3.fromRGB(70, 75, 95),
			Material = Enum.Material.ForceField,
			Transparency = 0.4,
			CanQuery = false,
		})
	end
end

-- =====================================================================
-- Decor — every cosmetic in the lobby. Rebuilt from scratch on each boot
-- (destroy + recreate the Decor folder) so it's identical on fresh and
-- baked lobbies alike.
-- =====================================================================

-- Central spawn plaza: concentric glow rings + a gold emblem where players land.
local function buildPlaza(decor, origin)
	makeFloorDisc(decor, "PlazaRingOuter", origin + Vector3.new(0, 0.04, 0), 44, COLOR_GOLD, 0.82)
	makeFloorDisc(decor, "PlazaRingMid", origin + Vector3.new(0, 0.05, 0), 30, COLOR_GOLD, 0.72)
	makeFloorDisc(decor, "PlazaCore", origin + Vector3.new(0, 0.06, 0), 10, COLOR_GOLD, 0.25)
	local beacon = makePart(decor, "PlazaBeacon", {
		Size = Vector3.new(0.6, 0.6, 0.6),
		Position = origin + Vector3.new(0, 4, 0),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})
	attachAmbientParticles(beacon, COLOR_GOLD, 4)
end

-- Glowing floor strips leading from the plaza to each landmark.
local function buildWalkways(decor, origin)
	makeWalkStrip(decor, "WalkToZones", origin + Vector3.new(0, 0.08, 9), origin + Vector3.new(0, 0.08, ROW_Z - 11), 6, COLOR_GOLD)
	makeWalkStrip(decor, "WalkToPit", origin + Vector3.new(0, 0.08, -9), origin + Vector3.new(0, 0.08, PORTAL_OFFSET.Z + 12), 6, COLOR_EMBER)
	makeWalkStrip(
		decor,
		"WalkToShop",
		origin + Vector3.new(-9, 0.08, -2),
		origin + Vector3.new(SHOP_OFFSET.X + 10, 0.08, SHOP_OFFSET.Z + 2),
		5,
		COLOR_CYAN
	)
end

-- Dress each zone pad: corner pylons in the pad's color + a glow ring on the
-- floor around it. Positions come from the live pad parts, so this works for
-- baked pads too.
local function dressZonePads(decor, zones)
	for _, rec in pairs(zones) do
		local pad = rec.pad
		if pad then
			local c = pad.Position
			local half = pad.Size.X / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local base = c + Vector3.new(sx * (half + 1.6), 0, sz * (half + 1.6))
					makePart(decor, "ZonePylon", {
						Size = Vector3.new(1.6, 9, 1.6),
						Position = Vector3.new(base.X, c.Y + 4.5, base.Z),
						Color = COLOR_STONE,
						Material = Enum.Material.Slate,
						CanQuery = false,
					})
					local cap = makePart(decor, "ZonePylonCap", {
						Size = Vector3.new(2, 0.7, 2),
						Position = Vector3.new(base.X, c.Y + 9.4, base.Z),
						Color = rec.color or pad.Color,
						Material = Enum.Material.Neon,
						CanCollide = false,
						CanQuery = false,
					})
					attachLight(cap, cap.Color, 1.2, 14)
				end
			end
		end
	end
end

-- Shop pavilion cosmetics around wherever the kiosk actually stands: four
-- columns holding a floating roof slab, plus a slowly sparkling gold crystal.
local function dressShopKiosk(decor, kiosk)
	if not kiosk then
		return
	end
	local c = kiosk.Position -- kiosk is 14×6×14; c is its center
	local floorY = c.Y - kiosk.Size.Y / 2
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			makePart(decor, "ShopColumn", {
				Size = Vector3.new(2, 14, 2),
				Position = Vector3.new(c.X + sx * 10, floorY + 7, c.Z + sz * 10),
				Color = COLOR_STONE,
				Material = Enum.Material.Slate,
				CanQuery = false,
			})
		end
	end
	makePart(decor, "ShopRoof", {
		Size = Vector3.new(24, 1.2, 24),
		Position = Vector3.new(c.X, floorY + 14.6, c.Z),
		Color = COLOR_STONE_DARK,
		Material = Enum.Material.Slate,
		CanQuery = false,
	})
	makePart(decor, "ShopRoofTrim", {
		Size = Vector3.new(24.6, 0.5, 24.6),
		Position = Vector3.new(c.X, floorY + 15.4, c.Z),
		Color = COLOR_GOLD,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
	})
	-- Floating crystal above the kiosk (particles supply the motion).
	local crystal = makePart(decor, "ShopCrystal", {
		Size = Vector3.new(2.2, 3.4, 2.2),
		CFrame = CFrame.new(c.X, floorY + 11, c.Z) * CFrame.Angles(math.rad(45), math.rad(30), math.rad(45)),
		Color = COLOR_GOLD,
		Material = Enum.Material.Neon,
		CanCollide = false,
		CanQuery = false,
	})
	attachLight(crystal, COLOR_GOLD, 2, 26)
	attachAmbientParticles(crystal, COLOR_GOLD, 5)
end

-- The Pit portal: dais, twin pillars, lintel, a glowing ember gateway disc,
-- and a big sign. The disc carries the PitPortal attribute LobbyUI's proximity
-- prompt looks for.
local function buildPitPortal(decor, origin)
	local base = origin + PORTAL_OFFSET
	makePart(decor, "PitDais", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.6, 24, 24),
		CFrame = CFrame.new(base + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COLOR_STONE_DARK,
		Material = Enum.Material.Slate,
	})
	makeFloorDisc(decor, "PitDaisRing", base + Vector3.new(0, 0.65, 0), 20, COLOR_EMBER, 0.55)
	for _, sx in ipairs({ -1, 1 }) do
		local pillar = makePart(decor, "PitPillar", {
			Size = Vector3.new(3, 17, 3),
			Position = base + Vector3.new(sx * 8.5, 9, 0),
			Color = COLOR_STONE,
			Material = Enum.Material.Slate,
		})
		makePart(decor, "PitPillarCap", {
			Size = Vector3.new(3.6, 0.8, 3.6),
			Position = pillar.Position + Vector3.new(0, 9, 0),
			Color = COLOR_EMBER,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
	end
	makePart(decor, "PitLintel", {
		Size = Vector3.new(21, 2.4, 3.4),
		Position = base + Vector3.new(0, 18.7, 0),
		Color = COLOR_STONE_DARK,
		Material = Enum.Material.Slate,
	})

	-- The gateway itself: a vertical ember disc you can walk through.
	local gate = makePart(decor, "PitGate", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.8, 14, 14),
		CFrame = CFrame.new(base + Vector3.new(0, 9.4, 0)) * CFrame.Angles(0, math.rad(90), 0),
		Color = COLOR_EMBER,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		CanQuery = false,
	})
	gate:SetAttribute("PitPortal", true)
	attachLight(gate, COLOR_EMBER, 2.5, 34)
	attachAmbientParticles(gate, COLOR_EMBER, 14)

	-- Sign above the arch.
	local gui = Instance.new("BillboardGui")
	gui.Adornee = gate
	gui.Size = UDim2.fromOffset(320, 74)
	gui.StudsOffset = Vector3.new(0, 12, 0)
	gui.AlwaysOnTop = true
	gui.Parent = gate
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 44)
	title.BackgroundTransparency = 1
	title.Text = "🔥 THE PIT 🔥"
	title.TextColor3 = COLOR_EMBER
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextStrokeTransparency = 0.2
	title.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(1, 0, 0, 26)
	sub.Position = UDim2.fromOffset(0, 46)
	sub.BackgroundTransparency = 1
	sub.Text = "Brawl bots & rivals while you wait"
	sub.TextColor3 = Color3.fromRGB(240, 220, 200)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextStrokeTransparency = 0.4
	sub.Parent = gui
end

-- Team banners flanking the walk to the queue zones.
local function buildBanners(decor, origin)
	local defs = {
		{ pos = origin + Vector3.new(-14, 0, 22), color = Color3.fromRGB(70, 140, 255) },
		{ pos = origin + Vector3.new(14, 0, 22), color = Color3.fromRGB(255, 90, 90) },
		{ pos = origin + Vector3.new(-14, 0, -22), color = COLOR_EMBER },
		{ pos = origin + Vector3.new(14, 0, -22), color = COLOR_EMBER },
	}
	for i, d in ipairs(defs) do
		makePart(decor, "BannerPole" .. i, {
			Size = Vector3.new(0.7, 15, 0.7),
			Position = d.pos + Vector3.new(0, 7.5, 0),
			Color = COLOR_STONE_DARK,
			Material = Enum.Material.Metal,
			CanQuery = false,
		})
		local cloth = makePart(decor, "Banner" .. i, {
			Size = Vector3.new(4, 8.5, 0.3),
			Position = d.pos + Vector3.new(0, 10.2, 0),
			Color = d.color,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
		})
		makePart(decor, "BannerTrim" .. i, {
			Size = Vector3.new(4.2, 0.5, 0.4),
			Position = cloth.Position + Vector3.new(0, -4.4, 0),
			Color = COLOR_GOLD,
			Material = Enum.Material.Neon,
			Transparency = 0.2,
			CanCollide = false,
			CanQuery = false,
		})
	end
end

-- Perimeter pylons: rhythm posts along the lobby edge with glowing caps, so
-- the boundary reads as architecture instead of an invisible box.
local function buildPerimeter(decor, origin)
	local h = LOBBY_HALF - 3
	local step = 25
	local positions = {}
	for x = -h, h, step do
		table.insert(positions, Vector3.new(x, 0, -h))
		table.insert(positions, Vector3.new(x, 0, h))
	end
	for z = -h + step, h - step, step do
		table.insert(positions, Vector3.new(-h, 0, z))
		table.insert(positions, Vector3.new(h, 0, z))
	end
	for i, off in ipairs(positions) do
		makePart(decor, "EdgePylon" .. i, {
			Size = Vector3.new(2.2, 11, 2.2),
			Position = origin + off + Vector3.new(0, 5.5, 0),
			Color = COLOR_STONE,
			Material = Enum.Material.Slate,
			CanQuery = false,
		})
		makePart(decor, "EdgePylonCap" .. i, {
			Size = Vector3.new(2.6, 0.6, 2.6),
			Position = origin + off + Vector3.new(0, 11.3, 0),
			Color = COLOR_GOLD,
			Material = Enum.Material.Neon,
			Transparency = 0.3,
			CanCollide = false,
			CanQuery = false,
		})
	end
end

-- Rebuild every cosmetic. Idempotent: nukes the previous Decor folder.
local function buildDecor(lobby, origin, zones, shopKiosk)
	local existing = lobby:FindFirstChild("Decor")
	if existing then
		existing:Destroy()
	end
	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = lobby

	buildPlaza(decor, origin)
	buildWalkways(decor, origin)
	dressZonePads(decor, zones)
	dressShopKiosk(decor, shopKiosk)
	buildPitPortal(decor, origin)
	buildBanners(decor, origin)
	buildPerimeter(decor, origin)
	return decor
end

-- =====================================================================
-- Structural pieces
-- =====================================================================

local function buildShopKiosk(lobby, origin)
	local pos = origin + SHOP_OFFSET
	local shopBase = makePart(lobby, "ShopKiosk", {
		Size = Vector3.new(14, 6, 14),
		Position = Vector3.new(pos.X, origin.Y + 3, pos.Z),
		Color = Color3.fromRGB(74, 62, 44),
		Material = Enum.Material.Slate,
	})
	local shopGui = Instance.new("BillboardGui")
	shopGui.Adornee = shopBase
	shopGui.Size = UDim2.fromOffset(280, 50)
	shopGui.StudsOffset = Vector3.new(0, 14, 0)
	shopGui.AlwaysOnTop = true
	shopGui.Parent = shopBase
	local shopLabel = Instance.new("TextLabel")
	shopLabel.Size = UDim2.fromScale(1, 1)
	shopLabel.BackgroundTransparency = 1
	shopLabel.Text = "RUNE SHOP\n(press B)"
	shopLabel.TextColor3 = COLOR_GOLD
	shopLabel.Font = Enum.Font.GothamBold
	shopLabel.TextScaled = true
	shopLabel.TextStrokeTransparency = 0.3
	shopLabel.Parent = shopGui

	local shopClick = Instance.new("ClickDetector")
	shopClick.Name = "ShopClick"
	shopClick.MaxActivationDistance = 30
	shopClick.Parent = shopBase
	return shopBase, shopClick
end

-- Locate references inside an existing Workspace.Lobby (hand-edited in Studio
-- or baked from a previous build). Returns the same shape as build() so the
-- rest of the server doesn't care which path was taken.
local function findReferences(existing)
	local origin = Config.LobbyOrigin
	local shopBase = existing:FindFirstChild("ShopKiosk")
	-- Lobbies baked before the plaza redesign have the kiosk dead-center —
	-- exactly where the old builder put it, so it's safe to slide it to the
	-- new pavilion spot (a hand-moved kiosk won't be at the center and is
	-- left alone).
	if shopBase and (shopBase.Position - (origin + Vector3.new(0, 3, 0))).Magnitude < 2 then
		local pos = origin + SHOP_OFFSET
		shopBase.Position = Vector3.new(pos.X, origin.Y + 3, pos.Z)
	end
	local shopClick = shopBase and shopBase:FindFirstChildOfClass("ClickDetector")
	local zones = {}
	for _, child in ipairs(existing:GetDescendants()) do
		if child:IsA("BasePart") then
			local zoneId = child:GetAttribute("ZoneId")
			if typeof(zoneId) == "number" then
				-- Force the baked pad into the straight-row layout so a lobby baked
				-- with the old ring arrangement still lines up. Only X/Z move (keep
				-- the pad's baked height); the billboard is adornee'd so it follows,
				-- and the walls are rebuilt below around the new position.
				local pos = rowPadPosition(origin, zoneId, Config.Matchmaking.ZoneCount)
				child.Position = Vector3.new(pos.X, child.Position.Y, pos.Z)
				local statusLabel
				local gui = child:FindFirstChildOfClass("BillboardGui")
				if gui then
					statusLabel = gui:FindFirstChild("Status", true)
				end
				buildZoneWalls(child)
				zones[zoneId] = {
					id = zoneId,
					pad = child,
					clickDetector = child:FindFirstChildOfClass("ClickDetector"),
					statusLabel = statusLabel,
					color = child.Color,
				}
			end
		end
	end
	buildLobbyWalls(existing, origin)
	buildDecor(existing, origin, zones, shopBase)
	return {
		spawnPos = origin,
		shopKiosk = shopBase,
		shopClick = shopClick,
		zones = zones,
	}
end

-- Build the lobby and return { spawnPos, shopKiosk, shopClick, zones }.
function LobbyBuilder.build()
	-- If a Lobby folder already exists (baked into the place), use it as-is.
	local existing = workspace:FindFirstChild("Lobby")
	if existing then
		return findReferences(existing)
	end
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = workspace

	local origin = Config.LobbyOrigin

	-- Floor
	makePart(lobby, "LobbyFloor", {
		Size = Vector3.new(200, 1, 200),
		Position = origin - Vector3.new(0, 1, 0),
		Color = COLOR_FLOOR,
		Material = Enum.Material.Slate,
	})

	-- Perimeter walls so players can't walk off the lobby floor.
	buildLobbyWalls(lobby, origin)

	-- Shop kiosk (off-center — the plaza middle is the spawn).
	local shopBase, shopClick = buildShopKiosk(lobby, origin)

	-- Zones in a straight row — positions come from rowPadPosition (see above).
	local zones = {}
	local zoneCount = Config.Matchmaking.ZoneCount
	for i = 1, zoneCount do
		local zonePos = rowPadPosition(origin, i, zoneCount)
		local color = ZONE_COLORS[((i - 1) % #ZONE_COLORS) + 1]

		local pad = makePart(lobby, "Zone" .. i, {
			Size = Vector3.new(PAD_SIZE, 0.5, PAD_SIZE),
			Position = zonePos - Vector3.new(0, 0.25, 0),
			Color = color,
			Material = Enum.Material.Neon, -- glowing pad reads as a portal
		})
		pad:SetAttribute("ZoneId", i)

		local click = Instance.new("ClickDetector")
		click.Name = "ZoneClick"
		click.MaxActivationDistance = 30
		click.Parent = pad

		-- Billboard above the pad
		local gui = Instance.new("BillboardGui")
		gui.Adornee = pad
		gui.Size = UDim2.fromOffset(220, 90)
		gui.StudsOffset = Vector3.new(0, 4, 0)
		gui.AlwaysOnTop = true
		gui.Parent = pad

		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		frame.BackgroundTransparency = 0.2
		frame.BorderSizePixel = 0
		frame.Parent = gui

		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 36)
		title.Position = UDim2.fromOffset(0, 4)
		title.BackgroundTransparency = 1
		title.Text = "Zone " .. i
		title.TextColor3 = color
		title.Font = Enum.Font.GothamBold
		title.TextScaled = true
		title.TextStrokeTransparency = 0.3
		title.Parent = frame

		local status = Instance.new("TextLabel")
		status.Name = "Status"
		status.Size = UDim2.new(1, 0, 0, 36)
		status.Position = UDim2.fromOffset(0, 44)
		status.BackgroundTransparency = 1
		status.Text = "0 / " .. Config.Matchmaking.MaxPerZone
		status.TextColor3 = Color3.fromRGB(240, 240, 240)
		status.Font = Enum.Font.GothamBold
		status.TextScaled = true
		status.TextStrokeTransparency = 0.3
		status.Parent = frame

		buildZoneWalls(pad)

		zones[i] = {
			id = i,
			pad = pad,
			clickDetector = click,
			statusLabel = status,
			color = color,
		}
	end

	buildDecor(lobby, origin, zones, shopBase)

	return {
		spawnPos = origin,
		shopKiosk = shopBase,
		shopClick = shopClick,
		zones = zones,
	}
end

return LobbyBuilder
