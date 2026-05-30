local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Champions = require(Shared:WaitForChild("Champions"))
local Remotes = require(Shared:WaitForChild("Remotes"))

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

function AbilityCaster:_cast(slot)
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

	local direction = self.camera:getCameraForward()
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
	local targetPos = self.camera:getGroundTarget(groundY)

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
