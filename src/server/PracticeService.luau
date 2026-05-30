-- Owns the practice-room target dummy. The dummy is registered as a special
-- "minion" inside MinionService so the existing auto-attack / ability damage
-- paths work without changes — we just flag it `isDummy = true` so the minion
-- AI tick skips it and `applyDamage` reschedules respawn instead of permanently
-- destroying the entry on death.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PracticeBuilder = require(script.Parent:WaitForChild("PracticeBuilder"))

local PracticeService = {}
PracticeService.__index = PracticeService

function PracticeService.new(minionService)
	local self = setmetatable({}, PracticeService)
	self.minionService = minionService
	self.dummyEntry = nil
	return self
end

local function buildDummyModel(spawnPos, maxHP)
	local model = Instance.new("Model")
	model.Name = "PracticeDummy"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Anchored = true
	root.CanCollide = true
	root.CanQuery = true
	root.CanTouch = false
	root.Size = Vector3.new(3, 4, 3)
	root.CFrame = CFrame.new(spawnPos + Vector3.new(0, 2, 0))
	root.Color = Color3.fromRGB(220, 90, 90)
	root.Material = Enum.Material.SmoothPlastic
	root.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Anchored = true
	head.CanCollide = false
	head.CanQuery = true
	head.Size = Vector3.new(1.6, 1.6, 1.6)
	head.CFrame = root.CFrame + Vector3.new(0, 2.8, 0)
	head.Color = Color3.fromRGB(220, 90, 90)
	head.Material = Enum.Material.SmoothPlastic
	head.Parent = model
	model.PrimaryPart = root

	-- HP billboard above the head.
	local gui = Instance.new("BillboardGui")
	gui.Name = "HPBar"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(100, 14)
	gui.StudsOffset = Vector3.new(0, 1.6, 0)
	gui.AlwaysOnTop = true
	gui.Parent = head
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 2)
	bgCorner.Parent = bg
	-- Dummy is registered on team Red — red border so practice plays the
	-- same way as fighting an enemy minion.
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 100, 100)
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = bg
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 2)
	fillCorner.Parent = fill

	return model, root, fill
end

-- Spawn the dummy into the practice room. Reuses MinionService.minions so the
-- existing damage flow finds it via `minionService:getMinion(id)`.
function PracticeService:_spawnDummy()
	-- Reuse the next-id sequence from MinionService — peek-and-bump.
	local ms = self.minionService
	local maxHP = Config.PracticeDummyMaxHP
	local pos = PracticeBuilder.getDummyPos()
	local model, root, hpFill = buildDummyModel(pos, maxHP)
	-- Pick an ID that won't collide with future minions. Use a large negative
	-- so it stays well outside the normal range.
	local id = -1
	model:SetAttribute("MinionId", id)
	model:SetAttribute("Team", "Red") -- enemy-side so any team can attack
	root:SetAttribute("MinionId", id)
	root:SetAttribute("Team", "Red")
	-- Find or create the standard Minions bin in Workspace.
	local bin = workspace:FindFirstChild("Minions")
	if not bin then
		bin = Instance.new("Folder")
		bin.Name = "Minions"
		bin.Parent = workspace
	end
	model.Parent = bin

	local entry = {
		id = id,
		team = "Red",
		typeKey = "Dummy",
		model = model,
		root = root,
		hpFill = hpFill,
		maxHP = maxHP,
		hp = maxHP,
		walkSpeed = 0,
		attackDamage = 0,
		attackRange = 0,
		attackInterval = 99,
		aggroRadius = 0,
		goldReward = 0,
		useProjectile = false,
		path = { pos },
		pathIndex = 999, -- exhaust path so AI just stands
		alive = true,
		nextAttackAt = math.huge,
		spawnPos = pos,
		-- Captured at spawn so MinionService can return the dummy to the floor
		-- after a knockup parabola finishes.
		baseY = root.Position.Y,
		-- Flag for MinionService to skip AI and to respawn on death.
		isDummy = true,
	}
	ms.minions[id] = entry
	self.dummyEntry = entry
	return entry
end

function PracticeService:ensureDummy()
	if self.dummyEntry and self.dummyEntry.alive and self.dummyEntry.model and self.dummyEntry.model.Parent then
		return
	end
	self:_spawnDummy()
end

-- Called from MinionService.applyDamage when a dummy hits 0 HP.
function PracticeService:onDummyKilled(entry)
	-- Hide the model (don't destroy — we'll restore it on respawn).
	if entry.model then
		entry.model:Destroy()
	end
	self.minionService.minions[entry.id] = nil
	self.dummyEntry = nil
	task.delay(Config.PracticeDummyRespawnDelay, function()
		self:ensureDummy()
	end)
end

return PracticeService
