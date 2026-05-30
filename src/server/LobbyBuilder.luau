local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LobbyBuilder = {}

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

local ZONE_COLORS = {
	Color3.fromRGB(80, 140, 220),
	Color3.fromRGB(220, 100, 100),
	Color3.fromRGB(120, 200, 110),
	Color3.fromRGB(220, 200, 90),
	Color3.fromRGB(180, 120, 220),
	Color3.fromRGB(220, 150, 90),
}

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

-- Locate references inside an existing Workspace.Lobby (hand-edited in Studio
-- or baked from a previous build). Returns the same shape as build() so the
-- rest of the server doesn't care which path was taken.
local function findReferences(existing)
	local origin = Config.LobbyOrigin
	local shopBase = existing:FindFirstChild("ShopKiosk")
	local shopClick = shopBase and shopBase:FindFirstChildOfClass("ClickDetector")
	local zones = {}
	for _, child in ipairs(existing:GetDescendants()) do
		if child:IsA("BasePart") then
			local zoneId = child:GetAttribute("ZoneId")
			if typeof(zoneId) == "number" then
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
	return {
		spawnPos = origin,
		shopKiosk = shopBase,
		shopClick = shopClick,
		zones = zones,
	}
end

-- Build the lobby and return { spawnPoint, shopPosition, zones = { [zoneId] = { pad, billboardLabel } } }
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
		Color = Color3.fromRGB(60, 60, 70),
		Material = Enum.Material.SmoothPlastic,
	})

	-- Shop kiosk in the middle
	local shopBase = makePart(lobby, "ShopKiosk", {
		Size = Vector3.new(14, 6, 14),
		Position = origin + Vector3.new(0, 3, 0),
		Color = Color3.fromRGB(80, 70, 50),
		Material = Enum.Material.SmoothPlastic,
	})
	-- Shop billboard sign
	local shopSignAttach = Instance.new("Attachment")
	shopSignAttach.Position = Vector3.new(0, 4, 0)
	shopSignAttach.Parent = shopBase
	local shopGui = Instance.new("BillboardGui")
	shopGui.Adornee = shopBase
	shopGui.Size = UDim2.fromOffset(280, 50)
	shopGui.StudsOffset = Vector3.new(0, 5, 0)
	shopGui.AlwaysOnTop = true
	shopGui.Parent = shopBase
	local shopLabel = Instance.new("TextLabel")
	shopLabel.Size = UDim2.fromScale(1, 1)
	shopLabel.BackgroundTransparency = 1
	shopLabel.Text = "RUNE SHOP\n(press B)"
	shopLabel.TextColor3 = Color3.fromRGB(240, 220, 120)
	shopLabel.Font = Enum.Font.GothamBold
	shopLabel.TextScaled = true
	shopLabel.TextStrokeTransparency = 0.3
	shopLabel.Parent = shopGui

	-- Click detector on shop kiosk
	local shopClick = Instance.new("ClickDetector")
	shopClick.Name = "ShopClick"
	shopClick.MaxActivationDistance = 30
	shopClick.Parent = shopBase

	-- Spawn area (also a flat pad you stand on after arriving)
	local spawnY = origin.Y
	local spawnPos = origin + Vector3.new(0, 0, 0)

	-- Zones around the ring
	local zones = {}
	local zoneCount = Config.Matchmaking.ZoneCount
	local radius = Config.LobbyRadius
	for i = 1, zoneCount do
		local angle = (i - 1) * (math.pi * 2 / zoneCount)
		local zonePos = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local color = ZONE_COLORS[((i - 1) % #ZONE_COLORS) + 1]

		local pad = makePart(lobby, "Zone" .. i, {
			Size = Vector3.new(18, 0.5, 18),
			Position = zonePos - Vector3.new(0, 0.25, 0),
			Color = color,
			Material = Enum.Material.Neon, -- only "glow" in the lobby — looks like a portal
		})
		pad:SetAttribute("ZoneId", i)

		-- Click detector on the pad
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
		title.Position = UDim2.new(0, 0, 0, 4)
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
		status.Position = UDim2.new(0, 0, 0, 44)
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

	return {
		spawnPos = spawnPos,
		shopKiosk = shopBase,
		shopClick = shopClick,
		zones = zones,
	}
end

return LobbyBuilder
