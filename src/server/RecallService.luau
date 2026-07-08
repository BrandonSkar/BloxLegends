local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PracticeBuilder = require(script.Parent:WaitForChild("PracticeBuilder"))

local RecallService = {}
RecallService.__index = RecallService

local MOVE_EPSILON = 0.05

function RecallService.new(matchController, combatService, matchmaking)
	local self = setmetatable({}, RecallService)
	self.matchController = matchController
	self.combatService = combatService
	self.matchmaking = matchmaking
	-- userId -> { startedAt, endsAt, startPos }
	self.active = {}
	-- userId -> bool — last known "in base" state, so we only fire InBaseChanged on transitions.
	self.inBaseState = {}
	self.connections = {}

	Remotes.get("RecallStart").OnServerEvent:Connect(function(player)
		self:tryStart(player)
	end)
	Remotes.get("RecallCancel").OnServerEvent:Connect(function(player)
		self:cancel(player, "manual")
	end)
	return self
end

local function getBasePos(self, player)
	-- Practice-room players recall to the practice spawn, not the arena base
	-- (which may not even exist on this server).
	local entry = self.combatService:getEntry(player)
	if entry and entry.practiceMode then
		return PracticeBuilder.getSpawnPos()
	end
	local team = self.matchController:teamOf(player)
	if not team then
		return nil
	end
	local teamData = Config.Teams[team]
	return teamData and teamData.SpawnPosition
end

function RecallService:isChanneling(player)
	return self.active[player.UserId] ~= nil
end

-- Authoritative "is this player standing in their base regen zone?" — used by
-- the shop to gate purchases. Mirrors the InBaseChanged state pushed to clients.
function RecallService:isInBase(player)
	return self.inBaseState[player.UserId] or false
end

-- Forget the cached in-base state so the next tick re-emits InBaseChanged. Called
-- when a player (re)enters a match so the client's shop gate re-syncs even if
-- they happened to be "in base" at the end of the previous match.
function RecallService:clearInBaseState(player)
	self.inBaseState[player.UserId] = nil
end

function RecallService:tryStart(player)
	if self.matchmaking and self.matchmaking:getState(player) ~= "in_match" then
		return
	end
	local entry = self.combatService:getEntry(player)
	if not entry or not entry.alive or entry.selectingChampion then
		return
	end
	-- Already channeling — silently ignore. Movement/damage/ability/death are
	-- the only cancel paths; pressing B again does nothing.
	if self.active[player.UserId] then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local now = os.clock()
	local duration = Config.Recall.ChannelTime
	self.active[player.UserId] = {
		startedAt = now,
		endsAt = now + duration,
		startPos = root.Position,
	}
	Remotes.get("RecallState"):FireClient(player, "channeling", duration)
end

function RecallService:cancel(player, _reason)
	if not self.active[player.UserId] then
		return
	end
	self.active[player.UserId] = nil
	Remotes.get("RecallState"):FireClient(player, "cancelled")
end

-- Called by CombatService when a player takes damage.
function RecallService:onDamageTaken(player)
	self:cancel(player, "damage")
end

-- Called by AbilityHandler before processing an ability cast.
function RecallService:onAbilityCast(player)
	self:cancel(player, "ability")
end

function RecallService:_complete(player)
	self.active[player.UserId] = nil
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local basePos = getBasePos(self, player)
	if root and basePos then
		root.CFrame = CFrame.new(basePos)
		-- Full heal on successful recall arrival is too strong; the base regen
		-- (20% / s) handles top-up, so we only refresh HP here if at low HP via
		-- the normal regen tick. No instant heal — players still pay channel time.
	end
	Remotes.get("RecallState"):FireClient(player, "complete")
end

function RecallService:_tick()
	local now = os.clock()
	for userId, info in pairs(self.active) do
		local player = Players:GetPlayerByUserId(userId)
		if not player then
			self.active[userId] = nil
			continue
		end
		local entry = self.combatService:getEntry(player)
		if not entry or not entry.alive then
			self:cancel(player, "death")
			continue
		end
		-- Movement cancel: any input on the humanoid (W/A/S/D translates to
		-- MoveDirection > epsilon). The CombatService auto-attack wind-up uses
		-- the same trick, so behavior is consistent.
		local char = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.MoveDirection.Magnitude > MOVE_EPSILON then
			self:cancel(player, "movement")
			continue
		end
		if now >= info.endsAt then
			self:_complete(player)
		end
	end

	-- In-base regen + InBase state broadcast.
	for _, player in ipairs(Players:GetPlayers()) do
		if self.matchmaking and self.matchmaking:getState(player) ~= "in_match" then
			continue
		end
		local entry = self.combatService:getEntry(player)
		if not entry or not entry.alive then
			-- Treat as not in base (clear state if it was set).
			if self.inBaseState[player.UserId] then
				self.inBaseState[player.UserId] = false
				Remotes.get("InBaseChanged"):FireClient(player, false)
			end
			continue
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local basePos = getBasePos(self, player)
		local inBase = false
		if entry.practiceMode then
			-- The Pit counts as "in base" everywhere so builds can be bought and
			-- tested on the spot. Regen is gated separately below — healing
			-- 20%/s mid-duel would make Pit PvP unkillable.
			inBase = true
		elseif root and basePos then
			local d = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(basePos.X, 0, basePos.Z)).Magnitude
			inBase = d <= Config.Recall.BaseRadius
		end
		if inBase ~= (self.inBaseState[player.UserId] or false) then
			self.inBaseState[player.UserId] = inBase
			Remotes.get("InBaseChanged"):FireClient(player, inBase)
		end
		local canRegen = inBase
		if entry.practiceMode then
			-- Out-of-combat only: no damage taken for the last few seconds.
			canRegen = (now - (entry.lastDamagedAt or 0)) >= 5
		end
		if canRegen and entry.hp < entry.maxHP then
			-- Tick-based: heal RegenPctPerSecond * maxHP * tickInterval each tick.
			entry.nextBaseRegenAt = entry.nextBaseRegenAt or (now + Config.Recall.RegenTickInterval)
			if now >= entry.nextBaseRegenAt then
				entry.nextBaseRegenAt = now + Config.Recall.RegenTickInterval
				local amount = entry.maxHP * Config.Recall.RegenPctPerSecond * Config.Recall.RegenTickInterval
				self.combatService:healPlayer(player, amount)
			end
		else
			entry.nextBaseRegenAt = nil
		end
	end
end

function RecallService:start()
	table.insert(self.connections, RunService.Heartbeat:Connect(function()
		self:_tick()
	end))
end

function RecallService:destroy()
	for _, c in ipairs(self.connections) do
		c:Disconnect()
	end
	self.connections = {}
end

return RecallService
