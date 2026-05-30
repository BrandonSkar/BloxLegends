local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PracticeBuilder = {}

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

-- Idempotent: returns the existing PracticeRoom folder if already built.
function PracticeBuilder.build()
	local existing = workspace:FindFirstChild("PracticeRoom")
	if existing then
		return existing
	end
	local origin = Config.PracticeOrigin
	local size = Config.PracticeRoomSize

	local room = Instance.new("Folder")
	room.Name = "PracticeRoom"
	room.Parent = workspace

	-- Floor
	makePart(room, "Floor", {
		Size = size,
		Position = origin - Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(70, 75, 90),
	})

	-- Wall ring (4 walls)
	local wallHeight = 18
	local wallThickness = 2
	local hx = size.X / 2
	local hz = size.Z / 2
	local walls = {
		{ size = Vector3.new(size.X + wallThickness * 2, wallHeight, wallThickness), pos = origin + Vector3.new(0, wallHeight / 2, hz) },
		{ size = Vector3.new(size.X + wallThickness * 2, wallHeight, wallThickness), pos = origin + Vector3.new(0, wallHeight / 2, -hz) },
		{ size = Vector3.new(wallThickness, wallHeight, size.Z), pos = origin + Vector3.new(hx, wallHeight / 2, 0) },
		{ size = Vector3.new(wallThickness, wallHeight, size.Z), pos = origin + Vector3.new(-hx, wallHeight / 2, 0) },
	}
	for _, w in ipairs(walls) do
		makePart(room, "Wall", {
			Size = w.size,
			Position = w.pos,
			Color = Color3.fromRGB(110, 115, 130),
			Material = Enum.Material.SmoothPlastic,
		})
	end

	-- Sign over the dummy spawn so it's obvious where to shoot.
	local signPos = origin + Config.PracticeDummyOffset + Vector3.new(0, 12, 0)
	local sign = makePart(room, "PracticeSign", {
		Size = Vector3.new(8, 0.4, 8),
		Position = signPos,
		Color = Color3.fromRGB(200, 80, 80),
		Material = Enum.Material.Neon,
		Transparency = 0.4,
	})
	local gui = Instance.new("BillboardGui")
	gui.Adornee = sign
	gui.Size = UDim2.fromOffset(180, 36)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "TARGET DUMMY"
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 230, 230)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui

	return room
end

function PracticeBuilder.getSpawnPos()
	return Config.PracticeOrigin + Vector3.new(-30, 4, 0)
end

function PracticeBuilder.getDummyPos()
	return Config.PracticeOrigin + Config.PracticeDummyOffset
end

return PracticeBuilder
