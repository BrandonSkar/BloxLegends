-- In-match item shop. Spends MATCH gold (MatchController), only while the
-- player is standing in their base regen zone (RecallService:isInBase). Items
-- are per-match and reset on (re)spawn into a match. Bonuses are summed into
-- entry.itemBonuses, which CombatService / AbilityHandler read at their damage,
-- heal, and stat application points. Derived stats (max HP, walk speed) are
-- recomputed here on each purchase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Champions = require(Shared:WaitForChild("Champions"))
local Items = require(Shared:WaitForChild("Items"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ShopService = {}
ShopService.__index = ShopService

function ShopService.new(combatService, matchController, recallService)
	local self = setmetatable({}, ShopService)
	self.combatService = combatService
	self.matchController = matchController
	self.recallService = recallService
	self.owned = {} -- userId -> { [itemKey] = count }

	Remotes.get("BuyItem").OnServerEvent:Connect(function(player, itemKey)
		if typeof(itemKey) ~= "string" then
			return
		end
		local ok, reason = self:tryBuy(player, itemKey)
		Remotes.get("BuyItemResult"):FireClient(player, ok, reason)
	end)

	return self
end

function ShopService:_replicate(player)
	Remotes.get("ItemsChanged"):FireClient(player, self.owned[player.UserId] or {})
end

-- Fresh start for a match: clear owned items and zero the entry's item bonuses.
function ShopService:resetPlayer(player)
	self.owned[player.UserId] = {}
	local entry = self.combatService:getEntry(player)
	if entry then
		entry.itemBonuses = Items.combineBonuses(nil)
	end
	self:_replicate(player)
end

function ShopService:removePlayer(player)
	self.owned[player.UserId] = nil
end

-- Recompute the player's combined item bonuses; CombatService owns the
-- derived-stat math (max HP with level scaling, walk speed) so items, runes,
-- and level-ups all agree on one formula.
function ShopService:_applyBonuses(player, entry)
	entry.itemBonuses = Items.combineBonuses(self.owned[player.UserId])
	self.combatService:recomputeDerived(player)
end

function ShopService:tryBuy(player, itemKey)
	local item = Items.Catalog[itemKey]
	if not item then
		return false, "unknown-item"
	end
	local entry = self.combatService:getEntry(player)
	if not entry or not entry.alive or entry.selectingChampion then
		return false, "unavailable"
	end
	-- Class gate: you can only buy items for your champion's class.
	local champ = entry.championKey and Champions.Roster[entry.championKey]
	if not champ then
		return false, "no-champion"
	end
	if item.Class ~= champ.Class then
		return false, "wrong-class"
	end
	if self.recallService and not self.recallService:isInBase(player) then
		return false, "not-in-base"
	end

	local owned = self.owned[player.UserId] or {}
	-- League-style: pay the item's cost minus the value of recipe components you
	-- already own (those components are consumed into the build).
	local cost, consume = Items.purchase(itemKey, owned)
	if self.matchController:getGold(player) < cost then
		return false, "not-enough-gold"
	end

	self.matchController:addGold(player, -cost)
	for compKey, use in pairs(consume) do
		owned[compKey] = (owned[compKey] or 0) - use
		if owned[compKey] <= 0 then
			owned[compKey] = nil
		end
	end
	owned[itemKey] = (owned[itemKey] or 0) + 1
	self.owned[player.UserId] = owned
	self:_applyBonuses(player, entry)
	self:_replicate(player)
	return true, nil
end

return ShopService
