local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Champions = require(Shared:WaitForChild("Champions"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local TargetingController = {}
TargetingController.__index = TargetingController

function TargetingController.new(cameraController)
	local self = setmetatable({}, TargetingController)
	self.player = Players.LocalPlayer
	self.camera = cameraController
	self.currentTarget = nil
	self.changedListeners = {}
	self.connections = {}
	self.enabled = false
	-- BushController provides hiddenPlayers map so smart-target picking can
	-- skip enemies you can't see.
	self.bushController = nil
	-- ChampionKey is updated when we receive ChampionSelected — used to pick
	-- the right auto-attack range for smart targeting.
	self.championKey = nil
	return self
end

function TargetingController:setEnabled(enabled)
	self.enabled = enabled
	if not enabled then
		self.currentTarget = nil
		self:_notify()
	end
end

function TargetingController:setBushController(bc)
	self.bushController = bc
end

function TargetingController:setChampion(key)
	self.championKey = key
end

function TargetingController:onChanged(fn)
	table.insert(self.changedListeners, fn)
end

function TargetingController:_notify()
	for _, fn in ipairs(self.changedListeners) do
		task.spawn(fn, self.currentTarget)
	end
end

function TargetingController:getTarget()
	return self.currentTarget
end

local function ancestorWithAttribute(part, attr)
	local cur = part
	while cur do
		if cur:GetAttribute(attr) ~= nil then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

-- Is the given enemy player currently hidden from this client (in a bush
-- I'm not in, or invisible from Smoke Bomb)? Filters smart-target picks
-- and direct clicks alike — you can't damage what you can't see.
function TargetingController:_isHidden(otherPlayer)
	if not self.bushController then
		return false
	end
	local id = otherPlayer.UserId
	return (self.bushController.hiddenPlayers or {})[id] or false
end

-- Local team — used to filter out allies from smart-target picking.
function TargetingController:_localTeam()
	local char = self.player.Character
	if char then
		return char:GetAttribute("Team")
	end
	return nil
end

function TargetingController:_localPos()
	local char = self.player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.Position
end

-- Raycast-based pick: was the cursor over something hittable?
function TargetingController:_pickByCursor()
	local mouseLocation = UserInputService:GetMouseLocation()
	if self.camera:isMouseLook() then
		local viewport = Workspace.CurrentCamera.ViewportSize
		mouseLocation = Vector2.new(viewport.X / 2, viewport.Y / 2)
	end

	local camera = Workspace.CurrentCamera
	local unitRay = camera:ScreenPointToRay(mouseLocation.X, mouseLocation.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	if self.player.Character then
		table.insert(exclude, self.player.Character)
	end
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)
	if not result then
		return nil
	end
	local part = result.Instance
	local minionRoot = ancestorWithAttribute(part, "MinionId")
	if minionRoot then
		local id = minionRoot:GetAttribute("MinionId")
		local team = minionRoot:GetAttribute("Team")
		if typeof(id) == "number" then
			return { type = "minion", id = id, team = team, name = team .. " Minion" }
		end
	end
	local playerRoot = ancestorWithAttribute(part, "PlayerId")
	if playerRoot then
		local id = playerRoot:GetAttribute("PlayerId")
		local team = playerRoot:GetAttribute("Team")
		if typeof(id) == "number" and id ~= self.player.UserId then
			local other = Players:GetPlayerByUserId(id)
			-- Can't attack things in bushes / under Smoke Bomb.
			if other and self:_isHidden(other) then
				return nil
			end
			return { type = "player", id = id, team = team, name = other and other.DisplayName or "Enemy" }
		end
	end
	local towerRoot = ancestorWithAttribute(part, "TowerId")
	if towerRoot then
		local id = towerRoot:GetAttribute("TowerId")
		local team = towerRoot:GetAttribute("Team")
		if typeof(id) == "number" then
			return { type = "tower", id = id, team = team, name = (team or "?") .. " Tower" }
		end
	end
	return nil
end

-- Smart-target fallback: pick the best target in the local player's auto-attack
-- range. Priority: nearest enemy Champion > nearest enemy Minion > nearest
-- enemy Tower. Skips hidden enemies. Returns nil if nothing valid is in range.
function TargetingController:_pickByPriority()
	local localPos = self:_localPos()
	if not localPos then
		return nil
	end
	local team = self:_localTeam()
	if not team then
		return nil
	end
	local range
	if self.championKey then
		range = Champions.getAutoAttackProfile(self.championKey).Range
	else
		range = 45 -- placeholder
	end
	-- A slightly larger "consideration radius" for smart picks, so they don't
	-- feel finicky right at the edge of range.
	local consider = range * 1.15

	-- 1) Closest enemy champion in range.
	local bestPlayer, bestPlayerDist
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= self.player then
			local oChar = other.Character
			local oRoot = oChar and oChar:FindFirstChild("HumanoidRootPart")
			local oTeam = oChar and oChar:GetAttribute("Team")
			if oRoot and oTeam and oTeam ~= team and not self:_isHidden(other) then
				local d = (oRoot.Position - localPos).Magnitude
				if d <= consider and (not bestPlayerDist or d < bestPlayerDist) then
					bestPlayer = { type = "player", id = other.UserId, team = oTeam, name = other.DisplayName }
					bestPlayerDist = d
				end
			end
		end
	end
	if bestPlayer then
		return bestPlayer
	end

	-- 2) Closest enemy minion in range.
	local bestMinion, bestMinionDist
	local minionBin = Workspace:FindFirstChild("Minions")
	if minionBin then
		for _, model in ipairs(minionBin:GetChildren()) do
			local mTeam = model:GetAttribute("Team")
			local mId = model:GetAttribute("MinionId")
			local root = model:FindFirstChild("HumanoidRootPart")
			if mTeam and mTeam ~= team and typeof(mId) == "number" and root then
				local d = (root.Position - localPos).Magnitude
				if d <= consider and (not bestMinionDist or d < bestMinionDist) then
					bestMinion = { type = "minion", id = mId, team = mTeam, name = mTeam .. " Minion" }
					bestMinionDist = d
				end
			end
		end
	end
	if bestMinion then
		return bestMinion
	end

	-- 3) Closest enemy tower in range (and not invulnerable; invuln towers
	--    have their TowerId attribute cleared by TowerService when shielded,
	--    so they naturally fail this check).
	local bestTower, bestTowerDist
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("BasePart") then
			local tTeam = inst:GetAttribute("Team")
			local tId = inst:GetAttribute("TowerId")
			if tTeam and tTeam ~= team and typeof(tId) == "number" then
				local d = (inst.Position - localPos).Magnitude
				if d <= consider and (not bestTowerDist or d < bestTowerDist) then
					bestTower = { type = "tower", id = tId, team = tTeam, name = tTeam .. " Tower" }
					bestTowerDist = d
				end
			end
		end
	end
	return bestTower
end

function TargetingController:_setTarget(target)
	self.currentTarget = target
	if target then
		Remotes.get("SetTarget"):FireServer(target.type, target.id)
	else
		Remotes.get("SetTarget"):FireServer(nil, nil)
	end
	self:_notify()
end

function TargetingController:start()
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(input, processed)
			if processed then
				return
			end
			if not self.enabled then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			-- 1) Did the click land on a target directly? If so, attack that.
			local picked = self:_pickByCursor()
			-- 2) Otherwise fall back to smart-target by priority.
			if not picked then
				picked = self:_pickByPriority()
			end
			self:_setTarget(picked)
		end)
	)

	table.insert(
		self.connections,
		Remotes.get("TargetCleared").OnClientEvent:Connect(function()
			self.currentTarget = nil
			self:_notify()
		end)
	)
end

function TargetingController:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return TargetingController
