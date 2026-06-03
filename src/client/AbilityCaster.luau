local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Champions = require(Shared:WaitForChild("Champions"))
local Remotes = require(Shared:WaitForChild("Remotes"))

-- Project a screen-space point onto a horizontal ground plane (y=groundY).
-- Returns nil if the ray points up. Used to translate a finger / mouse
-- position on the HUD into a world-space target for drag-to-aim.
local function screenToGround(screenX, screenY, groundY)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(screenX, screenY)
	if math.abs(ray.Direction.Y) < 0.0001 then
		return nil
	end
	local t = (groundY - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

local AbilityCaster = {}
AbilityCaster.__index = AbilityCaster

local SLOT_KEYS = {
	[Enum.KeyCode.Q] = "Q",
	[Enum.KeyCode.E] = "E",
	[Enum.KeyCode.F] = "F",
	[Enum.KeyCode.R] = "R",
	[Enum.KeyCode.Space] = "Space",
	[Enum.KeyCode.LeftShift] = "Shift",
	[Enum.KeyCode.RightShift] = "Shift",
}

function AbilityCaster.new(cameraController)
	local self = setmetatable({}, AbilityCaster)
	self.player = Players.LocalPlayer
	self.camera = cameraController
	self.championKey = nil
	self.targetingController = nil -- set via setTargetingController for target-cast pickup
	self.localCooldowns = {}
	self.connections = {}
	return self
end

function AbilityCaster:setChampion(championKey)
	self.championKey = championKey
end

function AbilityCaster:setTargetingController(tc)
	self.targetingController = tc
end

function AbilityCaster:setCooldown(slot, duration)
	self.localCooldowns[slot] = os.clock() + duration
end

function AbilityCaster:_isReady(slot)
	return (self.localCooldowns[slot] or 0) <= os.clock()
end

function AbilityCaster:_cast(slot, aimWorldPos)
	if not self.championKey then
		return
	end
	local champ = Champions.Roster[self.championKey]
	local ability = champ and champ.Abilities[slot]
	if not ability or not self:_isReady(slot) then
		return
	end
	local char = self.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- Use the actual floor Y under the player (raycast down) so AoE markers
	-- land on the ground instead of hovering at HRP/chest height. Falls back
	-- to HRP - 2.5 if nothing is below (e.g. mid-air).
	local groundY = root.Position.Y - 2.5
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { char }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -50, 0), rayParams)
	if hit then
		groundY = hit.Position.Y
	end

	-- aimWorldPos comes from a drag-aim release: the player chose where the
	-- ability should land. Without it (keyboard cast, or just-a-tap on a HUD
	-- slot), fall back to the camera's center-of-screen ground intersection.
	local targetPos
	local direction
	if aimWorldPos then
		targetPos = Vector3.new(aimWorldPos.X, groundY, aimWorldPos.Z)
		local flat = Vector3.new(targetPos.X - root.Position.X, 0, targetPos.Z - root.Position.Z)
		if flat.Magnitude > 0.01 then
			direction = flat.Unit
		else
			direction = self.camera:getCameraForward()
		end
	else
		direction = self.camera:getCameraForward()
		targetPos = self.camera:getGroundTarget(groundY)
	end

	-- For target-cast / leap_to_target, include the locked target id so the
	-- server can resolve the enemy without an extra round trip. Minion targets
	-- are allowed for target_cast so practice dummies are valid Ignite targets;
	-- leap_to_target stays player-only (no gap-closing onto minions).
	local targetType, targetId
	if ability.Type == "target_cast" then
		local t = self.targetingController and self.targetingController:getTarget()
		if t and (t.type == "player" or t.type == "minion") then
			targetType, targetId = t.type, t.id
		else
			return
		end
	elseif ability.Type == "leap_to_target" then
		local t = self.targetingController and self.targetingController:getTarget()
		if t and t.type == "player" then
			targetType, targetId = t.type, t.id
		else
			return
		end
	end

	Remotes.get("CastAbility"):FireServer(slot, root.Position, direction, targetPos, targetType, targetId)
end

-- Public entry for triggering a cast by slot, used by the on-screen HUD
-- buttons on touch devices (and as a backup on desktop). Same gating as the
-- keyboard path — runs through _cast which handles cooldowns, target
-- locking, and remote firing.
function AbilityCaster:castSlot(slot)
	self:_cast(slot)
end

-- ============================================================================
-- Drag-aim flow (touch + mouse)
-- ----------------------------------------------------------------------------
-- HUD slot buttons emit press → drag → release. While dragging we render a
-- ground ring so the player can see where the ability will fire. On release,
-- we cast at the last aim point. A "tap without meaningful drag" (under
-- DRAG_THRESHOLD pixels) falls back to camera-forward aim so quick taps still
-- feel snappy.
-- ============================================================================

local DRAG_THRESHOLD = 10 -- pixels

-- Pick which indicator shape best previews an ability:
--   "line"   — projectile / line_skillshot / dash (rectangle from caster
--              along the aim direction, sized to the ability's range × width)
--   "ring"   — ground_aoe / volley (cylinder at the cursor position,
--              sized to the ability's radius)
--   nil      — self-buffs, target-cast, etc. (no preview, just the cast)
local function indicatorShapeFor(ability)
	local t = ability and ability.Type
	if t == "projectile" or t == "line_skillshot" or t == "dash" then
		return "line"
	elseif t == "ground_aoe" or t == "volley" then
		return "ring"
	end
	return nil
end

local function ensureRing(self)
	if self.aimRing and self.aimRing.Parent then
		return self.aimRing
	end
	local p = Instance.new("Part")
	p.Name = "AbilityAimRing"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.2, 6, 6)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 220, 100)
	p.Transparency = 0.4
	p.Parent = Workspace
	self.aimRing = p
	return p
end

-- A flat box from the caster along the aim direction. Has an outline frame
-- (semi-transparent neon body) so the player can read range AND width at a
-- glance — Kate's branch did the same thing in her larger indicator system.
local function ensureLine(self)
	if self.aimLine and self.aimLine.Parent then
		return self.aimLine
	end
	local p = Instance.new("Part")
	p.Name = "AbilityAimLine"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 220, 100)
	p.Transparency = 0.55
	p.Size = Vector3.new(2, 0.2, 30)
	p.Parent = Workspace
	self.aimLine = p
	return p
end

local function hideAimVisuals(self)
	if self.aimRing then
		self.aimRing.Parent = nil
	end
	if self.aimLine then
		self.aimLine.Parent = nil
	end
end

-- Snap the line indicator so one short edge sits at the caster and the long
-- axis points toward `worldAim`. Length is clamped to the ability's range so
-- the preview matches what the server will actually do on cast.
local function placeLine(self, ability, originPos, worldAim, groundY)
	local p = ensureLine(self)
	p.Color = ability.Color or p.Color
	local flat = Vector3.new(worldAim.X - originPos.X, 0, worldAim.Z - originPos.Z)
	if flat.Magnitude < 0.01 then
		p.Parent = nil
		return
	end
	local dir = flat.Unit
	local length
	if ability.Type == "line_skillshot" then
		length = ability.Length or 30
	elseif ability.Type == "dash" then
		length = ability.Distance or 24
	else
		length = ability.Range or 30
	end
	-- For projectiles, the ability has ProjectileRadius (radius), so width = 2r.
	local width
	if ability.Type == "line_skillshot" then
		width = (ability.Width or 3) * 2
	elseif ability.Type == "projectile" then
		width = (ability.ProjectileRadius or 1.0) * 2
		-- Bare minimum visual thickness so a tiny projectile still reads.
		if width < 1.4 then
			width = 1.4
		end
	else
		width = 3
	end
	local mid = originPos + dir * (length / 2)
	mid = Vector3.new(mid.X, groundY + 0.15, mid.Z)
	p.Size = Vector3.new(width, 0.2, length)
	p.CFrame = CFrame.lookAt(mid, mid + dir)
	p.Parent = Workspace
end

function AbilityCaster:aimStart(slot, screenX, screenY)
	local champ = Champions.Roster[self.championKey]
	local ability = champ and champ.Abilities[slot]
	if not ability then
		return
	end
	local char = self.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local groundY = root.Position.Y - 2.5
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { char }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -50, 0), rayParams)
	if hit then
		groundY = hit.Position.Y
	end
	self._aimState = {
		slot = slot,
		ability = ability,
		shape = indicatorShapeFor(ability),
		originPos = root.Position,
		startX = screenX,
		startY = screenY,
		groundY = groundY,
		lastWorld = screenToGround(screenX, screenY, groundY),
		dragged = false,
	}
	-- Freeze the camera so a drag on the slot doesn't also pan the camera —
	-- they'd fight and the aim indicator would jitter. Released in aimEnd.
	if self.camera and self.camera.setSuspended then
		self.camera:setSuspended(true)
	end
	-- Hide both indicators until the player actually drags — quick taps don't
	-- need a ring/line flash. The shape is decided here, but only made visible
	-- inside aimUpdate once we've crossed DRAG_THRESHOLD.
	hideAimVisuals(self)
end

function AbilityCaster:aimUpdate(screenX, screenY)
	local s = self._aimState
	if not s then
		return
	end
	local dx = screenX - s.startX
	local dy = screenY - s.startY
	if not s.dragged and (dx * dx + dy * dy) >= (DRAG_THRESHOLD * DRAG_THRESHOLD) then
		s.dragged = true
	end
	local world = screenToGround(screenX, screenY, s.groundY)
	if world then
		s.lastWorld = world
	end
	if s.dragged and world then
		if s.shape == "ring" then
			local p = ensureRing(self)
			p.Color = s.ability.Color or p.Color
			local radius = s.ability.Radius or 6
			p.Size = Vector3.new(0.2, radius * 2, radius * 2)
			p.CFrame = CFrame.new(world.X, s.groundY + 0.1, world.Z) * CFrame.Angles(0, 0, math.rad(90))
			p.Parent = Workspace
		elseif s.shape == "line" then
			placeLine(self, s.ability, s.originPos, world, s.groundY)
		end
		-- For other ability types (target_cast, self_buff, etc.) we don't show
		-- an aim indicator — they ignore the aim point and fire on whatever
		-- target is locked / on the caster.
	end
end

function AbilityCaster:aimEnd(screenX, screenY, cancel)
	local s = self._aimState
	self._aimState = nil
	hideAimVisuals(self)
	if self.camera and self.camera.setSuspended then
		self.camera:setSuspended(false)
	end
	if not s or cancel then
		return
	end
	local world = screenToGround(screenX, screenY, s.groundY) or s.lastWorld
	if s.dragged and world then
		self:_cast(s.slot, world)
	else
		-- Quick tap: keyboard-style aim (camera forward).
		self:_cast(s.slot)
	end
end

function AbilityCaster:start()
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			local slot = SLOT_KEYS[input.KeyCode]
			if slot then
				self:_cast(slot)
			end
		end)
	)
end

function AbilityCaster:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return AbilityCaster
