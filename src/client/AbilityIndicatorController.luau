local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AbilityPhysics = require(Shared:WaitForChild("AbilityPhysics"))
local Champions = require(Shared:WaitForChild("Champions"))

local AbilityIndicatorController = {}
AbilityIndicatorController.__index = AbilityIndicatorController

function AbilityIndicatorController.new(cameraController, targetingController)
	local self = setmetatable({}, AbilityIndicatorController)
	self.player = Players.LocalPlayer
	self.camera = cameraController
	self.targeting = targetingController
	self.activePreview = nil
	self.activeAbility = nil
	self.connections = {}

	-- Visual parts folder
	self.folder = Workspace:FindFirstChild("LocalAbilityIndicators")
	if not self.folder then
		local f = Instance.new("Folder")
		f.Name = "LocalAbilityIndicators"
		f.Parent = Workspace
		self.folder = f
	end

	-- Target Painting highlights
	self.highlights = {}

	-- Indicator parts
	self.rangePart = nil
	self.impactPart = nil
	self.trailParts = {}
	self.pulseParts = {}
	self.beamPart = nil

	return self
end

local function cleanPart(part)
	if part then
		part:Destroy()
	end
	return nil
end

function AbilityIndicatorController:clearPreview()
	self.activePreview = nil
	self.activeAbility = nil

	-- Clean up parts
	self.rangePart = cleanPart(self.rangePart)
	self.impactPart = cleanPart(self.impactPart)
	self.beamPart = cleanPart(self.beamPart)

	for _, p in ipairs(self.trailParts) do
		p:Destroy()
	end
	self.trailParts = {}

	for _, p in ipairs(self.pulseParts) do
		p:Destroy()
	end
	self.pulseParts = {}

	-- Clear highlights
	self:clearHighlights()
end

function AbilityIndicatorController:clearHighlights()
	for model, hl in pairs(self.highlights) do
		if hl then
			hl:Destroy()
		end
	end
	self.highlights = {}
end

local function buildHologramPart(shape, color, size, parent)
	local p = Instance.new("Part")
	p.Name = "HologramPart"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.ForceField
	p.Color = color or Color3.fromRGB(0, 170, 255)
	p.Transparency = 0.55

	if shape == "cylinder" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = size or Vector3.new(0.2, 10, 10)
	elseif shape == "ball" then
		p.Shape = Enum.PartType.Ball
		p.Size = size or Vector3.new(3, 3, 3)
	else
		p.Shape = Enum.PartType.Block
		p.Size = size or Vector3.new(3, 2, 20)
	end

	p.Parent = parent
	return p
end

-- Collects all potential targets in workspace (Minions and Players)
function AbilityIndicatorController:_getPotentialTargets()
	local list = {}
	local localTeam = nil
	if self.player.Character then
		localTeam = self.player.Character:GetAttribute("Team")
	end

	-- Add enemy players
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= self.player and other.Character then
			local char = other.Character
			local team = char:GetAttribute("Team")
			if team and team ~= localTeam then
				table.insert(list, other)
			end
		end
	end

	-- Add enemy minions
	local minionBin = Workspace:FindFirstChild("Minions")
	if minionBin then
		for _, mModel in ipairs(minionBin:GetChildren()) do
			local team = mModel:GetAttribute("Team")
			local id = mModel:GetAttribute("MinionId")
			if team and team ~= localTeam and typeof(id) == "number" then
				table.insert(list, mModel)
			end
		end
	end

	return list
end



function AbilityIndicatorController:setAbilityCaster(caster)
	self.caster = caster
end

-- Paints targets using a single-frame simulated dry run of the ability physics
function AbilityIndicatorController:_runTargetPainting(ability, origin, direction, targetPos, targetType, targetId, customColor)
	local mockSim = AbilityPhysics.new(ability, origin, direction, targetPos, targetType, targetId)
	local potential = self:_getPotentialTargets()
	local predicted = {}

	local dt = 0.05
	local elapsed = 0
	while mockSim.alive and elapsed < 3.0 do -- failsafe limit
		mockSim:update(dt)
		elapsed = elapsed + dt
		local hits = mockSim:checkHits(potential, elapsed)
		for _, hit in ipairs(hits) do
			predicted[hit] = true
		end
	end

	-- Apply highlights to predicted targets
	local nextHighlights = {}
	local highlightColor = customColor or ability.Color or Color3.fromRGB(255, 70, 70)

	for target, _ in pairs(predicted) do
		local model = target:IsA("Player") and target.Character or target
		if model then
			local hl = self.highlights[model]
			if not hl then
				hl = Instance.new("Highlight")
				hl.FillColor = highlightColor
				hl.FillTransparency = 0.55
				hl.OutlineColor = Color3.fromRGB(255, 255, 255)
				hl.OutlineTransparency = 0.2
				hl.Adornee = model
				hl.Parent = model
			else
				hl.FillColor = highlightColor
			end
			nextHighlights[model] = hl
			self.highlights[model] = nil -- keep in next map
		end
	end

	-- Clean up targets that are no longer hit
	for model, hl in pairs(self.highlights) do
		if hl then
			hl:Destroy()
		end
	end

	self.highlights = nextHighlights
end

function AbilityIndicatorController:startPreview(slot, ability)
	self:clearPreview()
	self.activeAbility = ability
	self.activePreview = slot
end

function AbilityIndicatorController:updatePreview()
	if not self.activeAbility or not self.activePreview then
		return
	end

	local char = self.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		self:clearPreview()
		return
	end

	local origin = root.Position
	local direction = self.camera:getCameraForward()
	local groundY = origin.Y - 2.5
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { char, self.folder }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local hit = Workspace:Raycast(origin, Vector3.new(0, -50, 0), rayParams)
	if hit then
		groundY = hit.Position.Y
	end
	local targetPos = self.camera:getGroundTarget(groundY)

	-- Overrides for Touch Aiming Joystick if active
	local customDirection, customTargetPos, isCancelled = nil, nil, false
	if self.activePreview and self.caster and self.caster.touchAimActive[self.activePreview] then
		customDirection = self.caster.aimedDirection[self.activePreview]
		customTargetPos = self.caster.aimedPosition[self.activePreview]
		isCancelled = self.caster.isCancelledTouch[self.activePreview] or false
	end

	if customDirection then
		direction = customDirection
	end
	if customTargetPos then
		targetPos = customTargetPos
	end

	-- Check autotarget locked targets
	local targetType, targetId
	local activeTarget = self.targeting and self.targeting:getTarget()
	if activeTarget then
		targetType, targetId = activeTarget.type, activeTarget.id
	end

	-- Create simulation to query coordinates
	local sim = AbilityPhysics.new(self.activeAbility, origin, direction, targetPos, targetType, targetId)
	
	local color = self.activeAbility.Color or Color3.fromRGB(0, 170, 255)
	if isCancelled then
		color = Color3.fromRGB(255, 60, 60)
	end

	-- 1) Draw Range Ring around Caster (for circular or target casts)
	local maxRange = self.activeAbility.Range or self.activeAbility.Length or 40
	if not self.rangePart then
		self.rangePart = buildHologramPart("cylinder", color, Vector3.new(0.08, maxRange * 2, maxRange * 2), self.folder)
		self.rangePart.Name = "RangeIndicator"
	end
	self.rangePart.Color = color
	self.rangePart.Size = Vector3.new(0.08, maxRange * 2, maxRange * 2)
	-- Offset Y to groundY + 0.08 to avoid Z-fighting with ground floor geometry
	self.rangePart.CFrame = CFrame.new(Vector3.new(origin.X, groundY + 0.08, origin.Z)) * CFrame.Angles(0, 0, math.rad(90))

	-- 2) Draw Shape indicator based on Ability type
	if self.type == "projectile" or self.activeAbility.Type == "projectile" or self.activeAbility.Type == "line_skillshot" then
		-- Linear sweep lane
		local width = self.activeAbility.Width or (self.activeAbility.ProjectileRadius and self.activeAbility.ProjectileRadius * 2) or 3
		local length = self.activeAbility.Length or self.activeAbility.Range or 40

		if not self.impactPart then
			self.impactPart = buildHologramPart("block", color, Vector3.new(width, 0.12, length), self.folder)
			self.impactPart.Name = "LineIndicator"
		end
		self.impactPart.Color = color
		self.impactPart.Size = Vector3.new(width, 0.12, length)

		-- Center is half length forward. Offset Y to groundY + 0.16 to stack on top of the range ring.
		local centerPos = origin + sim.direction * (length / 2)
		self.impactPart.CFrame = CFrame.lookAt(Vector3.new(centerPos.X, groundY + 0.16, centerPos.Z), Vector3.new(centerPos.X, groundY + 0.16, centerPos.Z) + sim.direction)

	elseif self.activeAbility.Type == "ground_aoe" or self.activeAbility.Type == "volley" then
		-- Ground circle
		local radius = self.activeAbility.Radius or 8
		if not self.impactPart then
			self.impactPart = buildHologramPart("cylinder", color, Vector3.new(0.12, radius * 2, radius * 2), self.folder)
			self.impactPart.Name = "AoEIndicator"
		end
		self.impactPart.Color = color
		self.impactPart.Size = Vector3.new(0.12, radius * 2, radius * 2)
		-- Offset Y to groundY + 0.16 to prevent Z-fighting overlaps.
		self.impactPart.CFrame = CFrame.new(Vector3.new(sim.targetPos.X, groundY + 0.16, sim.targetPos.Z)) * CFrame.Angles(0, 0, math.rad(90))

	elseif self.activeAbility.Type == "dash" then
		-- Arrow path
		local dist = self.activeAbility.Distance or 30
		if not self.impactPart then
			self.impactPart = buildHologramPart("block", color, Vector3.new(4, 0.12, dist), self.folder)
			self.impactPart.Name = "DashIndicator"
		end
		self.impactPart.Color = color
		self.impactPart.Size = Vector3.new(4, 0.12, dist)
		local centerPos = origin + sim.direction * (dist / 2)
		-- Offset Y to groundY + 0.16.
		self.impactPart.CFrame = CFrame.lookAt(Vector3.new(centerPos.X, groundY + 0.16, centerPos.Z), Vector3.new(centerPos.X, groundY + 0.16, centerPos.Z) + sim.direction)

	elseif self.activeAbility.Type == "target_cast" or self.activeAbility.Type == "leap_to_target" then
		-- Target highlight
		local targetModel = nil
		if activeTarget then
			if activeTarget.type == "player" then
				local p = Players:GetPlayerByUserId(activeTarget.id)
				targetModel = p and p.Character
			elseif activeTarget.type == "minion" then
				local bin = Workspace:FindFirstChild("Minions")
				if bin then
					for _, mModel in ipairs(bin:GetChildren()) do
						if mModel:GetAttribute("MinionId") == activeTarget.id then
							targetModel = mModel
							break
						end
					end
				end
			end
		end

		if targetModel then
			local tRoot = targetModel:FindFirstChild("HumanoidRootPart")
			if tRoot then
				-- Snapped circle under target feet
				local tPos = tRoot.Position
				if not self.impactPart then
					self.impactPart = buildHologramPart("cylinder", color, Vector3.new(0.2, 8, 8), self.folder)
					self.impactPart.Name = "TargetLockRing"
				end
				self.impactPart.Color = color
				self.impactPart.CFrame = CFrame.new(Vector3.new(tPos.X, tPos.Y - 2.5, tPos.Z)) * CFrame.Angles(0, 0, math.rad(90))

				-- Connecting vector beam
				local from = origin + Vector3.new(0, 1.5, 0)
				local to = tPos
				local diff = to - from
				local mid = (from + to) / 2
				if not self.beamPart then
					self.beamPart = buildHologramPart("cylinder", color, Vector3.new(0.25, 0.25, diff.Magnitude), self.folder)
					self.beamPart.Material = Enum.Material.Neon
					pcall(function() self.beamPart.Transparency = 0.4 end)
					self.beamPart.Name = "TargetLockBeam"
				end
				self.beamPart.Color = color
				self.beamPart.Size = Vector3.new(0.25, 0.25, diff.Magnitude)
				self.beamPart.CFrame = CFrame.lookAt(mid, to)
			else
				self.impactPart = cleanPart(self.impactPart)
				self.beamPart = cleanPart(self.beamPart)
			end
		else
			self.impactPart = cleanPart(self.impactPart)
			self.beamPart = cleanPart(self.beamPart)
		end
	else
		-- Self buffs
		self.impactPart = cleanPart(self.impactPart)
		self.beamPart = cleanPart(self.beamPart)
	end

	-- 3) Run Predictive Target Painting (highlights all targets hit in simulation)
	self:_runTargetPainting(self.activeAbility, origin, direction, targetPos, targetType, targetId, color)
end

function AbilityIndicatorController:start()
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function()
			self:updatePreview()
		end)
	)
end

function AbilityIndicatorController:destroy()
	self:clearPreview()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
	if self.folder then
		self.folder:Destroy()
	end
end

return AbilityIndicatorController
