local Items = {}

-- =====================================================================
-- IN-MATCH ITEM SHOP — League-style component builds.
--
-- Items are gated to your champion's CLASS ("Attack" / "Support" / "Tank").
-- Each class has cheap COMPONENTS (single-stat basics) that combine into
-- COMPLETED items. A completed item lists the components it BuildsFrom; when
-- you buy it you only pay its Cost minus the value of the recipe components you
-- already own (those components are consumed). Buy it with no components and you
-- just pay the full Cost. Everything resets each match.
--
-- Bonus stat keys (all optional, summed across owned items):
--   AttackPower, AbilityPowerPct, AttackSpeedPct, MoveSpeedPct,
--   BonusMaxHP, DamageReductionPct, HealShieldPowerPct
-- =====================================================================

-- Per-class accent for the UI / card strokes.
Items.ClassColor = {
	Attack = Color3.fromRGB(255, 140, 80),
	Support = Color3.fromRGB(120, 230, 170),
	Tank = Color3.fromRGB(150, 180, 215),
}
Items.ClassLabel = {
	Attack = "Damage",
	Support = "Support",
	Tank = "Tank",
}

Items.Catalog = {
	-- =================================================================
	-- ATTACK (damage)
	-- =================================================================
	-- Components
	BladeShard = { Name = "Blade Shard", Class = "Attack", Component = true, Cost = 300, Description = "+8 attack damage.", Color = Color3.fromRGB(255, 150, 90), Bonuses = { AttackPower = 8 } },
	SpellDust = { Name = "Spell Dust", Class = "Attack", Component = true, Cost = 300, Description = "+8% ability damage.", Color = Color3.fromRGB(200, 130, 255), Bonuses = { AbilityPowerPct = 8 } },
	SwiftTrigger = { Name = "Swift Trigger", Class = "Attack", Component = true, Cost = 300, Description = "+10% attack speed.", Color = Color3.fromRGB(255, 200, 110), Bonuses = { AttackSpeedPct = 10 } },
	-- Completed
	Cinderblade = { Name = "Cinderblade", Class = "Attack", Cost = 800, Description = "+22 attack damage.", Color = Color3.fromRGB(255, 120, 70), Bonuses = { AttackPower = 22 }, BuildsFrom = { "BladeShard", "BladeShard" } },
	HuntersEdge = { Name = "Hunter's Edge", Class = "Attack", Cost = 850, Description = "+12 attack dmg, +18% attack speed.", Color = Color3.fromRGB(255, 180, 80), Bonuses = { AttackPower = 12, AttackSpeedPct = 18 }, BuildsFrom = { "BladeShard", "SwiftTrigger" } },
	ArcaneCore = { Name = "Arcane Core", Class = "Attack", Cost = 850, Description = "+22% ability damage.", Color = Color3.fromRGB(190, 120, 255), Bonuses = { AbilityPowerPct = 22 }, BuildsFrom = { "SpellDust", "SpellDust" } },
	Spellblade = { Name = "Spellblade", Class = "Attack", Cost = 850, Description = "+12 attack dmg, +12% ability dmg.", Color = Color3.fromRGB(235, 140, 160), Bonuses = { AttackPower = 12, AbilityPowerPct = 12 }, BuildsFrom = { "BladeShard", "SpellDust" } },
	TempestFang = { Name = "Tempest Fang", Class = "Attack", Cost = 800, Description = "+25% attack speed, +8 attack dmg.", Color = Color3.fromRGB(255, 215, 120), Bonuses = { AttackSpeedPct = 25, AttackPower = 8 }, BuildsFrom = { "SwiftTrigger", "SwiftTrigger" } },
	SunfireLance = { Name = "Sunfire Lance", Class = "Attack", Cost = 1400, Description = "+18 attack dmg, +15% ability dmg, +12% attack speed.", Color = Color3.fromRGB(255, 100, 50), Bonuses = { AttackPower = 18, AbilityPowerPct = 15, AttackSpeedPct = 12 }, BuildsFrom = { "BladeShard", "SpellDust", "SwiftTrigger" } },

	-- =================================================================
	-- SUPPORT
	-- =================================================================
	-- Components
	MendingHerb = { Name = "Mending Herb", Class = "Support", Component = true, Cost = 300, Description = "+10% heal & shield power.", Color = Color3.fromRGB(140, 235, 180), Bonuses = { HealShieldPowerPct = 10 } },
	TravelCharm = { Name = "Travel Charm", Class = "Support", Component = true, Cost = 250, Description = "+6% move speed.", Color = Color3.fromRGB(150, 210, 255), Bonuses = { MoveSpeedPct = 6 } },
	VitalPearl = { Name = "Vital Pearl", Class = "Support", Component = true, Cost = 300, Description = "+80 max HP.", Color = Color3.fromRGB(160, 220, 200), Bonuses = { BonusMaxHP = 80 } },
	-- Completed
	MendersCharm = { Name = "Mender's Charm", Class = "Support", Cost = 750, Description = "+24% heal & shield power.", Color = Color3.fromRGB(120, 235, 170), Bonuses = { HealShieldPowerPct = 24 }, BuildsFrom = { "MendingHerb", "MendingHerb" } },
	GuardianLocket = { Name = "Guardian Locket", Class = "Support", Cost = 850, Description = "+110 HP, +12% heal & shield power.", Color = Color3.fromRGB(150, 230, 200), Bonuses = { BonusMaxHP = 110, HealShieldPowerPct = 12 }, BuildsFrom = { "VitalPearl", "MendingHerb" } },
	SwiftBanner = { Name = "Swift Banner", Class = "Support", Cost = 800, Description = "+10% move speed, +10% heal & shield power.", Color = Color3.fromRGB(150, 210, 255), Bonuses = { MoveSpeedPct = 10, HealShieldPowerPct = 10 }, BuildsFrom = { "TravelCharm", "MendingHerb" } },
	BastionCrest = { Name = "Bastion Crest", Class = "Support", Cost = 800, Description = "+160 HP, +8% move speed.", Color = Color3.fromRGB(170, 220, 220), Bonuses = { BonusMaxHP = 160, MoveSpeedPct = 8 }, BuildsFrom = { "VitalPearl", "TravelCharm" } },
	AegisStandard = { Name = "Aegis Standard", Class = "Support", Cost = 800, Description = "+180 HP, take 6% less damage.", Color = Color3.fromRGB(140, 200, 210), Bonuses = { BonusMaxHP = 180, DamageReductionPct = 6 }, BuildsFrom = { "VitalPearl", "VitalPearl" } },
	RadiantAegis = { Name = "Radiant Aegis", Class = "Support", Cost = 1400, Description = "+130 HP, +20% heal & shield power, +8% move speed.", Color = Color3.fromRGB(180, 245, 210), Bonuses = { BonusMaxHP = 130, HealShieldPowerPct = 20, MoveSpeedPct = 8 }, BuildsFrom = { "VitalPearl", "MendingHerb", "TravelCharm" } },

	-- =================================================================
	-- TANK
	-- =================================================================
	-- Components
	IronPlate = { Name = "Iron Plate", Class = "Tank", Component = true, Cost = 300, Description = "+90 max HP.", Color = Color3.fromRGB(170, 180, 200), Bonuses = { BonusMaxHP = 90 } },
	ScaleMail = { Name = "Scale Mail", Class = "Tank", Component = true, Cost = 350, Description = "Take 5% less damage.", Color = Color3.fromRGB(140, 175, 205), Bonuses = { DamageReductionPct = 5 } },
	HeavyBoots = { Name = "Heavy Boots", Class = "Tank", Component = true, Cost = 250, Description = "+5% move speed.", Color = Color3.fromRGB(160, 170, 185), Bonuses = { MoveSpeedPct = 5 } },
	-- Completed
	BulwarkPlate = { Name = "Bulwark Plate", Class = "Tank", Cost = 800, Description = "+200 max HP.", Color = Color3.fromRGB(160, 170, 190), Bonuses = { BonusMaxHP = 200 }, BuildsFrom = { "IronPlate", "IronPlate" } },
	AegisHeart = { Name = "Aegis Heart", Class = "Tank", Cost = 900, Description = "+120 HP, take 9% less damage.", Color = Color3.fromRGB(140, 180, 210), Bonuses = { BonusMaxHP = 120, DamageReductionPct = 9 }, BuildsFrom = { "IronPlate", "ScaleMail" } },
	SpikedCarapace = { Name = "Spiked Carapace", Class = "Tank", Cost = 950, Description = "Take 12% less damage.", Color = Color3.fromRGB(120, 160, 195), Bonuses = { DamageReductionPct = 12 }, BuildsFrom = { "ScaleMail", "ScaleMail" } },
	JuggernautGreaves = { Name = "Juggernaut Greaves", Class = "Tank", Cost = 800, Description = "+140 HP, +8% move speed.", Color = Color3.fromRGB(175, 185, 200), Bonuses = { BonusMaxHP = 140, MoveSpeedPct = 8 }, BuildsFrom = { "IronPlate", "HeavyBoots" } },
	WardenMail = { Name = "Warden Mail", Class = "Tank", Cost = 850, Description = "+110 HP, take 6% less dmg, +5% move speed.", Color = Color3.fromRGB(150, 175, 200), Bonuses = { BonusMaxHP = 110, DamageReductionPct = 6, MoveSpeedPct = 5 }, BuildsFrom = { "ScaleMail", "HeavyBoots" } },
	ColossusCore = { Name = "Colossus Core", Class = "Tank", Cost = 1500, Description = "+300 HP, take 8% less damage.", Color = Color3.fromRGB(120, 150, 180), Bonuses = { BonusMaxHP = 300, DamageReductionPct = 8 }, BuildsFrom = { "IronPlate", "IronPlate", "ScaleMail" } },
}

-- Display order: components first, then completed items, per class.
Items.ComponentsByClass = {
	Attack = { "BladeShard", "SpellDust", "SwiftTrigger" },
	Support = { "MendingHerb", "TravelCharm", "VitalPearl" },
	Tank = { "IronPlate", "ScaleMail", "HeavyBoots" },
}
Items.CompletedByClass = {
	Attack = { "Cinderblade", "HuntersEdge", "ArcaneCore", "Spellblade", "TempestFang", "SunfireLance" },
	Support = { "MendersCharm", "GuardianLocket", "SwiftBanner", "BastionCrest", "AegisStandard", "RadiantAegis" },
	Tank = { "BulwarkPlate", "AegisHeart", "SpikedCarapace", "JuggernautGreaves", "WardenMail", "ColossusCore" },
}

-- Sum the bonuses of an owned-items map { [key] = count } into stat totals.
function Items.combineBonuses(owned)
	local total = {
		AttackPower = 0,
		AbilityPowerPct = 0,
		AttackSpeedPct = 0,
		MoveSpeedPct = 0,
		BonusMaxHP = 0,
		DamageReductionPct = 0,
		HealShieldPowerPct = 0,
	}
	if not owned then
		return total
	end
	for key, count in pairs(owned) do
		local item = Items.Catalog[key]
		if item and count and count > 0 then
			for stat, amount in pairs(item.Bonuses) do
				total[stat] = (total[stat] or 0) + amount * count
			end
		end
	end
	return total
end

-- The recipe components an item needs, as { [componentKey] = count }.
local function recipeNeeds(item)
	local needed = {}
	for _, c in ipairs(item.BuildsFrom or {}) do
		needed[c] = (needed[c] or 0) + 1
	end
	return needed
end

-- What it actually costs to buy `itemKey` given the player's `owned` map, plus
-- which owned components get consumed. Owned recipe components discount the
-- price (and are eaten). Shared by the server (authoritative) and the client
-- (price display) so they never disagree.
-- Returns: cost (number), consume ({ [componentKey] = count }).
function Items.purchase(itemKey, owned)
	local item = Items.Catalog[itemKey]
	if not item then
		return nil, nil
	end
	local consume, discount = {}, 0
	for compKey, need in pairs(recipeNeeds(item)) do
		local use = math.min((owned and owned[compKey]) or 0, need)
		if use > 0 then
			consume[compKey] = use
			local comp = Items.Catalog[compKey]
			discount = discount + (comp and comp.Cost or 0) * use
		end
	end
	return math.max(0, item.Cost - discount), consume
end

-- Human-readable build path, e.g. "Blade Shard ×2" or "Iron Plate + Scale Mail".
function Items.recipeText(itemKey)
	local item = Items.Catalog[itemKey]
	if not item or not item.BuildsFrom or #item.BuildsFrom == 0 then
		return ""
	end
	local counts, order = {}, {}
	for _, c in ipairs(item.BuildsFrom) do
		if not counts[c] then
			table.insert(order, c)
		end
		counts[c] = (counts[c] or 0) + 1
	end
	local parts = {}
	for _, c in ipairs(order) do
		local comp = Items.Catalog[c]
		local nm = (comp and comp.Name) or c
		if counts[c] > 1 then
			nm = nm .. " ×" .. counts[c]
		end
		table.insert(parts, nm)
	end
	return table.concat(parts, " + ")
end

return Items
