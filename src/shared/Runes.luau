local Runes = {}

-- Tiered stat runes. Each tier replaces the previous (you only get the highest you've bought).
Runes.Catalog = {
	AttackPower = {
		Name = "Attack Power",
		Description = "+%d damage to auto-attacks",
		Tiers = {
			{ Cost = 50, Bonus = 6 },
			{ Cost = 150, Bonus = 14 },
			{ Cost = 350, Bonus = 28 },
		},
	},
	AbilityPower = {
		Name = "Ability Power",
		Description = "+%d%% damage to abilities",
		Tiers = {
			{ Cost = 60, Bonus = 6 },
			{ Cost = 180, Bonus = 14 },
			{ Cost = 400, Bonus = 25 },
		},
	},
	AttackSpeed = {
		Name = "Attack Speed",
		Description = "-%d%% auto-attack cooldown",
		Tiers = {
			{ Cost = 50, Bonus = 6 },
			{ Cost = 150, Bonus = 14 },
			{ Cost = 350, Bonus = 25 },
		},
	},
	MoveSpeed = {
		Name = "Move Speed",
		Description = "+%d%% walk speed",
		Tiers = {
			{ Cost = 50, Bonus = 5 },
			{ Cost = 150, Bonus = 10 },
			{ Cost = 350, Bonus = 18 },
		},
	},
}

Runes.CatalogOrder = { "AttackPower", "AbilityPower", "AttackSpeed", "MoveSpeed" }

-- Summoner spells: the player picks ONE. Replaces the Space slot in-match.
Runes.SummonerSpells = {
	Heal = {
		Name = "Heal",
		Description = "Instantly restore 220 HP.",
		Type = "self_heal",
		HealAmount = 220,
		Cooldown = 60,
		Color = Color3.fromRGB(120, 255, 160),
	},
	Sprint = {
		Name = "Sprint",
		Description = "+100% move speed for 2.5s.",
		Type = "self_buff",
		BuffStat = "WalkSpeed",
		BuffMultiplier = 2.0,
		BuffDuration = 2.5,
		Cooldown = 60,
		Color = Color3.fromRGB(120, 200, 255),
	},
	Barrier = {
		Name = "Barrier",
		Description = "Heal 140 HP and gain +50% move speed for 2s.",
		Type = "combo",
		HealAmount = 140,
		BuffStat = "WalkSpeed",
		BuffMultiplier = 1.5,
		BuffDuration = 2,
		Cooldown = 70,
		Color = Color3.fromRGB(200, 200, 255),
	},
}

Runes.SummonerSpellOrder = { "Heal", "Sprint", "Barrier" }
Runes.DefaultSummonerSpell = "Heal"

-- Compute the final stat modifiers from a player's owned runes table.
-- ownedRunes is a map { runeKey -> tierIndex } e.g. { AttackPower = 2, MoveSpeed = 1 }
function Runes.computeBonuses(ownedRunes)
	local bonus = {
		AttackPower = 0,
		AbilityPowerPct = 0,
		AttackSpeedPct = 0,
		MoveSpeedPct = 0,
	}
	if not ownedRunes then
		return bonus
	end
	for key, tier in pairs(ownedRunes) do
		local rune = Runes.Catalog[key]
		if rune and rune.Tiers[tier] then
			local b = rune.Tiers[tier].Bonus
			if key == "AttackPower" then
				bonus.AttackPower = bonus.AttackPower + b
			elseif key == "AbilityPower" then
				bonus.AbilityPowerPct = bonus.AbilityPowerPct + b
			elseif key == "AttackSpeed" then
				bonus.AttackSpeedPct = bonus.AttackSpeedPct + b
			elseif key == "MoveSpeed" then
				bonus.MoveSpeedPct = bonus.MoveSpeedPct + b
			end
		end
	end
	return bonus
end

return Runes
