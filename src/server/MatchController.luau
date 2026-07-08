local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local MatchController = {}
MatchController.__index = MatchController

function MatchController.new()
	local self = setmetatable({}, MatchController)
	self.teams = {} -- userId -> "Blue" | "Red"
	self.gold = {} -- userId -> number
	return self
end

function MatchController:teamOf(player)
	return self.teams[player.UserId]
end

function MatchController:removePlayer(player)
	self.teams[player.UserId] = nil
	self.gold[player.UserId] = nil
end

function MatchController:getGold(player)
	return self.gold[player.UserId] or 0
end

function MatchController:addGold(player, amount)
	if not self.teams[player.UserId] then
		return
	end
	self.gold[player.UserId] = (self.gold[player.UserId] or 0) + amount
	-- Track lifetime gold earned for the scoreboard (spending doesn't count).
	if self.scoreService and amount > 0 then
		self.scoreService:onGoldEarned(player, amount)
	end
	Remotes.get("GoldChanged"):FireClient(player, self.gold[player.UserId])
end

-- Award `amount` gold to every registered player on `team`. Used for the
-- per-minion-death team share so allies who didn't last-hit still earn.
function MatchController:addTeamGold(team, amount)
	if amount <= 0 then
		return
	end
	for userId, t in pairs(self.teams) do
		if t == team then
			local p = Players:GetPlayerByUserId(userId)
			if p then
				self:addGold(p, amount)
			end
		end
	end
end

function MatchController:sendStateTo(player)
	Remotes.get("GoldChanged"):FireClient(player, self:getGold(player))
end

return MatchController
