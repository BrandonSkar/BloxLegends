local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Runes = require(Shared:WaitForChild("Runes"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PlayerDataService = {}
PlayerDataService.__index = PlayerDataService

local STARTING_GOLD = 200 -- enough for one tier-1 rune on first join

function PlayerDataService.new()
	local self = setmetatable({}, PlayerDataService)
	self.data = {} -- userId -> { gold, runes = {key=tier}, summonerSpell }
	return self
end

function PlayerDataService:register(player)
	if self.data[player.UserId] then
		return self.data[player.UserId]
	end
	self.data[player.UserId] = {
		gold = STARTING_GOLD,
		runes = {},
		summonerSpell = Runes.DefaultSummonerSpell,
	}
	return self.data[player.UserId]
end

function PlayerDataService:unregister(player)
	self.data[player.UserId] = nil
end

function PlayerDataService:get(player)
	return self.data[player.UserId]
end

function PlayerDataService:addGold(player, amount)
	local d = self.data[player.UserId]
	if not d then
		return
	end
	d.gold = d.gold + amount
	self:_replicate(player)
end

function PlayerDataService:_replicate(player)
	local d = self.data[player.UserId]
	if not d then
		return
	end
	Remotes.get("PlayerDataChanged"):FireClient(player, {
		gold = d.gold,
		runes = d.runes,
		summonerSpell = d.summonerSpell,
	})
end

function PlayerDataService:replicate(player)
	self:_replicate(player)
end

function PlayerDataService:tryBuyRune(player, runeKey, tier)
	local d = self.data[player.UserId]
	if not d then
		return false, "no-data"
	end
	local rune = Runes.Catalog[runeKey]
	if not rune then
		return false, "unknown-rune"
	end
	tier = tonumber(tier)
	if not tier or not rune.Tiers[tier] then
		return false, "bad-tier"
	end
	local currentTier = d.runes[runeKey] or 0
	if tier ~= currentTier + 1 then
		return false, "buy-in-order"
	end
	local cost = rune.Tiers[tier].Cost
	if d.gold < cost then
		return false, "not-enough-gold"
	end
	d.gold = d.gold - cost
	d.runes[runeKey] = tier
	self:_replicate(player)
	return true, nil
end

function PlayerDataService:setSummonerSpell(player, spellKey)
	local d = self.data[player.UserId]
	if not d then
		return false
	end
	if not Runes.SummonerSpells[spellKey] then
		return false
	end
	d.summonerSpell = spellKey
	self:_replicate(player)
	return true
end

function PlayerDataService:computeBonuses(player)
	local d = self.data[player.UserId]
	if not d then
		return Runes.computeBonuses(nil)
	end
	return Runes.computeBonuses(d.runes)
end

function PlayerDataService:getSummonerSpell(player)
	local d = self.data[player.UserId]
	if not d then
		return Runes.DefaultSummonerSpell
	end
	return d.summonerSpell
end

return PlayerDataService
