local Champions = {}

Champions.SlotOrder = { "Q", "E", "R", "F", "Space", "Shift" }

-- Class identity drives auto-attack feel: ranged vs melee, attack speed,
-- damage tuning, and what kit they expect from abilities.
Champions.Classes = {
	Attack = {
		Label = "ATTACKER",
		Color = Color3.fromRGB(255, 200, 70),
		Description = "Ranged poke and burst — disengage + stun kits.",
	},
	Support = {
		Label = "SUPPORT",
		Color = Color3.fromRGB(120, 220, 160),
		Description = "Ranged but soft damage — keep allies alive, peel with knockback.",
	},
	Tank = {
		Label = "TANK",
		Color = Color3.fromRGB(200, 130, 80),
		Description = "Melee bruiser — fast auto-attacks, keep enemies locked down.",
	},
}

-- Class auto-attack baselines. Per-champion overrides win if set.
Champions.ClassAutoAttack = {
	Attack = { Damage = 65, Interval = 1.0, WindUp = 0.25, Range = 45, Style = "ranged", TravelTime = 0.2 },
	Support = { Damage = 25, Interval = 1.5, WindUp = 0.40, Range = 40, Style = "ranged", TravelTime = 0.22 },
	Tank = { Damage = 40, Interval = 0.85, WindUp = 0.15, Range = 9, Style = "melee", TravelTime = 0 },
}

-- Passive HP regen by class. The amount is applied as a single discrete tick
-- every Champions.ClassRegenInterval seconds — not smoothed per-frame — so
-- you see a clean lump heal in the HUD instead of a slow drift.
Champions.ClassRegen = {
	Attack = 2,
	Support = 4,
	Tank = 8,
}
Champions.ClassRegenInterval = 5

Champions.Roster = {

	-- ===========================================================
	-- ATTACK
	-- ===========================================================
	Pyromancer = {
		Name = "Pyromancer",
		Class = "Attack",
		Description = "Fire-mage burst — stun your prey with a meteor, melt them with DoT.",
		MaxHP = 500,
		WalkSpeed = 16,
		Color = Color3.fromRGB(255, 110, 60),
		AutoAttack = { Style = "ranged", Color = Color3.fromRGB(255, 140, 50), TravelTime = 0.2, Range = 45 },
		Abilities = {
			Q = {
				Name = "Fireball",
				Type = "projectile",
				Cooldown = 4,
				Damage = 80,
				Range = 70,
				Speed = 90,
				ProjectileRadius = 1.6,
				Color = Color3.fromRGB(255, 130, 40),
			},
			E = {
				Name = "Meteor",
				Type = "ground_aoe",
				Cooldown = 12,
				Damage = 110,
				Range = 50,
				Radius = 8,
				ImpactDelay = 1.0,
				-- Class signature: stun on hit.
				StatusOnHit = { type = "stun", duration = 1.0 },
				Color = Color3.fromRGB(255, 100, 60),
			},
			R = {
				Name = "Pyroclasm",
				Type = "ground_aoe",
				Cooldown = 80,
				Damage = 350,
				Range = 60,
				Radius = 16,
				ImpactDelay = 1.5,
				Color = Color3.fromRGB(255, 70, 30),
			},
			F = {
				Name = "Ignite",
				Type = "target_cast",
				Cooldown = 15,
				Damage = 30,
				Range = 35,
				StatusOnHit = { type = "dot", damagePerTick = 30, interval = 1, ticks = 4 },
				Color = Color3.fromRGB(255, 150, 80),
			},
			Shift = {
				Name = "Flame Dash",
				Type = "dash",
				Cooldown = 6,
				Distance = 32,
				Duration = 0.2,
				-- Disengage: dash backward away from camera.
				Backward = true,
				Color = Color3.fromRGB(255, 180, 120),
			},
			Space = {
				Name = "Heal",
				Type = "self_heal",
				Cooldown = 60,
				HealAmount = 220,
				Color = Color3.fromRGB(120, 255, 160),
			},
		},
	},

	Marksman = {
		Name = "Marksman",
		Class = "Attack",
		Description = "Long-range archer — piercing line stuns and DoT poison arrows.",
		MaxHP = 470,
		WalkSpeed = 16,
		Color = Color3.fromRGB(220, 180, 80),
		AutoAttack = { Style = "ranged", Color = Color3.fromRGB(240, 220, 160), TravelTime = 0.25, Range = 55 },
		Abilities = {
			Q = {
				Name = "Piercing Arrow",
				Type = "line_skillshot",
				Cooldown = 7,
				Damage = 70,
				Length = 70,
				Width = 2,
				Speed = 100,
				-- Class signature: stun on hit.
				StatusOnHit = { type = "stun", duration = 0.9 },
				Color = Color3.fromRGB(240, 220, 160),
			},
			E = {
				Name = "Poison Arrow",
				Type = "projectile",
				Cooldown = 8,
				Damage = 30,
				Range = 50,
				Speed = 80,
				ProjectileRadius = 1.0,
				StatusOnHit = { type = "dot", damagePerTick = 20, interval = 1, ticks = 4 },
				Color = Color3.fromRGB(150, 220, 120),
			},
			R = {
				Name = "Volley",
				Type = "volley",
				Cooldown = 80,
				Damage = 60,
				Range = 55,
				Radius = 12,
				ImpactDelay = 0.3,
				Ticks = 5,
				TickInterval = 0.6,
				Color = Color3.fromRGB(220, 200, 140),
			},
			F = {
				Name = "Headshot",
				Type = "self_buff",
				SubType = "attack_buff",
				Cooldown = 15,
				BonusDamageMult = 3.0,
				Duration = 8,
				Color = Color3.fromRGB(255, 230, 120),
			},
			Shift = {
				Name = "Combat Roll",
				Type = "dash",
				Cooldown = 5,
				Distance = 28,
				Duration = 0.2,
				-- Disengage.
				Backward = true,
				Color = Color3.fromRGB(220, 200, 160),
			},
			Space = {
				Name = "Heal",
				Type = "self_heal",
				Cooldown = 60,
				HealAmount = 220,
				Color = Color3.fromRGB(120, 255, 160),
			},
		},
	},

	-- ===========================================================
	-- SUPPORT
	-- ===========================================================
	Frostmage = {
		Name = "Frostmage",
		Class = "Support",
		Description = "Shield-and-knockback peel — protect allies, shove enemies off.",
		MaxHP = 460,
		WalkSpeed = 16,
		Color = Color3.fromRGB(120, 200, 255),
		AutoAttack = { Style = "ranged", Color = Color3.fromRGB(150, 220, 255), TravelTime = 0.22, Range = 40 },
		Abilities = {
			Q = {
				Name = "Frost Blast",
				Type = "projectile",
				Cooldown = 7,
				Damage = 40,
				Range = 50,
				Speed = 80,
				ProjectileRadius = 1.4,
				-- Class signature: knockback for peel.
				StatusOnHit = { type = "knockback", distance = 15 },
				Color = Color3.fromRGB(140, 220, 255),
			},
			E = {
				Name = "Healing Mist",
				Type = "ground_aoe",
				Cooldown = 14,
				Damage = 0,
				Range = 35,
				Radius = 10,
				ImpactDelay = 0.2,
				-- Heals allies inside the AoE instead of damaging anyone.
				HealAlliesAmount = 120,
				Color = Color3.fromRGB(200, 240, 255),
			},
			R = {
				Name = "Bastion",
				Type = "ground_aoe",
				Cooldown = 90,
				Damage = 0,
				Range = 30,
				Radius = 14,
				ImpactDelay = 0.4,
				HealAlliesAmount = 180,
				-- Allies in the radius also get the shield.
				ShieldAlliesAmount = 250,
				ShieldAlliesDuration = 5,
				Color = Color3.fromRGB(180, 220, 255),
			},
			F = {
				Name = "Frost Armor",
				Type = "self_buff",
				SubType = "shield",
				Cooldown = 25,
				ShieldAmount = 300,
				Duration = 5,
				Color = Color3.fromRGB(180, 220, 255),
			},
			Shift = {
				Name = "Glide",
				Type = "dash",
				Cooldown = 7,
				Distance = 28,
				Duration = 0.25,
				InvulnDuration = 0.3,
				Color = Color3.fromRGB(160, 220, 255),
			},
			Space = {
				Name = "Heal",
				Type = "self_heal",
				Cooldown = 60,
				HealAmount = 220,
				Color = Color3.fromRGB(120, 255, 160),
			},
		},
	},

	Druid = {
		Name = "Druid",
		Class = "Support",
		Description = "Nature healer — pull stragglers, root them, heal your party.",
		MaxHP = 480,
		WalkSpeed = 16,
		Color = Color3.fromRGB(100, 180, 90),
		AutoAttack = { Style = "ranged", Color = Color3.fromRGB(140, 220, 110), TravelTime = 0.22, Range = 40 },
		Abilities = {
			Q = {
				Name = "Thorn Whip",
				Type = "projectile",
				Cooldown = 8,
				Damage = 40,
				Range = 40,
				Speed = 60,
				ProjectileRadius = 1.5,
				-- Strong pull toward the caster (peel for allies behind you).
				StatusOnHit = { type = "pull", distance = 25 },
				Color = Color3.fromRGB(140, 200, 100),
			},
			E = {
				Name = "Bloom",
				Type = "ground_aoe",
				Cooldown = 12,
				Damage = 0,
				Range = 30,
				Radius = 9,
				ImpactDelay = 0.2,
				HealAlliesAmount = 140,
				Color = Color3.fromRGB(160, 230, 130),
			},
			R = {
				Name = "Wildgrowth",
				Type = "ground_aoe",
				Cooldown = 100,
				Damage = 100,
				Range = 30,
				Radius = 15,
				ImpactDelay = 0.5,
				HealAlliesAmount = 200,
				StatusOnHit = { type = "dot", damagePerTick = 30, interval = 1, ticks = 4 },
				Color = Color3.fromRGB(140, 220, 110),
			},
			F = {
				Name = "Regrowth",
				Type = "self_buff",
				SubType = "hot",
				Cooldown = 25,
				HealPerTick = 45,
				Interval = 1,
				Ticks = 6,
				Color = Color3.fromRGB(160, 230, 130),
			},
			Shift = {
				Name = "Pounce",
				Type = "dash",
				Cooldown = 6,
				Distance = 28,
				Duration = 0.25,
				Color = Color3.fromRGB(160, 200, 100),
			},
			Space = {
				Name = "Heal",
				Type = "self_heal",
				Cooldown = 60,
				HealAmount = 220,
				Color = Color3.fromRGB(120, 255, 160),
			},
		},
	},

	-- ===========================================================
	-- TANK
	-- ===========================================================
	Vanguard = {
		Name = "Vanguard",
		Class = "Tank",
		Description = "Front-line brute — knockups and damage shield to hold the line.",
		MaxHP = 650,
		WalkSpeed = 15,
		Color = Color3.fromRGB(180, 140, 80),
		AutoAttack = { Style = "melee", Color = Color3.fromRGB(220, 180, 110), TravelTime = 0, Range = 9 },
		Abilities = {
			Q = {
				Name = "Shockwave",
				Type = "line_skillshot",
				Cooldown = 9,
				Damage = 60,
				Length = 25,
				Width = 4,
				Speed = 50,
				-- Tank signature: root, not stun.
				StatusOnHit = { type = "root", duration = 1.5 },
				Color = Color3.fromRGB(240, 220, 120),
			},
			E = {
				Name = "Earthslam",
				Type = "ground_aoe",
				Cooldown = 11,
				Damage = 70,
				Range = 18,
				Radius = 8,
				ImpactDelay = 0.4,
				StatusOnHit = { type = "knockup", height = 8, duration = 0.8 },
				Color = Color3.fromRGB(180, 140, 90),
			},
			R = {
				Name = "Cataclysm",
				Type = "ground_aoe",
				Cooldown = 90,
				Damage = 220,
				Range = 40,
				Radius = 14,
				ImpactDelay = 1.0,
				StatusOnHit = { type = "knockup", height = 10, duration = 1.0 },
				Color = Color3.fromRGB(220, 160, 80),
			},
			F = {
				Name = "Iron Skin",
				Type = "self_buff",
				SubType = "damage_reduction",
				Cooldown = 25,
				Multiplier = 0.4, -- 60% reduction
				Duration = 5,
				Color = Color3.fromRGB(180, 180, 200),
			},
			Shift = {
				Name = "Charge",
				Type = "dash",
				Cooldown = 12,
				Distance = 30,
				Duration = 0.3,
				KnockbackOnHit = 12,
				KnockbackDamage = 40,
				Color = Color3.fromRGB(200, 160, 110),
			},
			Space = {
				Name = "Heal",
				Type = "self_heal",
				Cooldown = 60,
				HealAmount = 220,
				Color = Color3.fromRGB(120, 255, 160),
			},
		},
	},

	Assassin = {
		Name = "Assassin",
		Class = "Tank",
		Description = "Lockdown bruiser — chain-pull enemies and root them in place.",
		MaxHP = 600,
		WalkSpeed = 16,
		Color = Color3.fromRGB(170, 100, 220),
		AutoAttack = { Style = "melee", Color = Color3.fromRGB(200, 200, 220), TravelTime = 0, Range = 9 },
		Abilities = {
			Q = {
				Name = "Chain Hook",
				Type = "projectile",
				Cooldown = 9,
				Damage = 50,
				Range = 40,
				Speed = 90,
				ProjectileRadius = 1.2,
				-- Class signature: pull the target to you, then root briefly.
				StatusOnHit = { type = "pull", distance = 25 },
				Color = Color3.fromRGB(180, 130, 220),
			},
			E = {
				Name = "Ground Slam",
				Type = "ground_aoe",
				Cooldown = 11,
				Damage = 50,
				Range = 12,
				Radius = 7,
				ImpactDelay = 0.3,
				StatusOnHit = { type = "root", duration = 1.5 },
				Color = Color3.fromRGB(160, 110, 200),
			},
			R = {
				Name = "Earthen Prison",
				Type = "target_cast",
				Cooldown = 80,
				Damage = 80,
				Range = 30,
				StatusOnHit = { type = "stun", duration = 2.2 },
				Color = Color3.fromRGB(140, 90, 200),
			},
			F = {
				Name = "Bulwark",
				Type = "self_buff",
				SubType = "damage_reduction",
				Cooldown = 25,
				Multiplier = 0.5,
				Duration = 4,
				Color = Color3.fromRGB(180, 180, 200),
			},
			Shift = {
				Name = "Anchor Slam",
				Type = "dash",
				Cooldown = 10,
				Distance = 28,
				Duration = 0.25,
				KnockbackOnHit = 0, -- no knockback; pure gap close
				KnockbackDamage = 30,
				Color = Color3.fromRGB(160, 100, 220),
			},
			Space = {
				Name = "Heal",
				Type = "self_heal",
				Cooldown = 60,
				HealAmount = 220,
				Color = Color3.fromRGB(120, 255, 160),
			},
		},
	},
}

-- Order = display order in champion select, grouped by class.
Champions.RosterOrder = { "Pyromancer", "Marksman", "Frostmage", "Druid", "Vanguard", "Assassin" }

-- Helper: returns the effective AutoAttack profile for a champion, merging
-- class baseline with any per-champion overrides.
function Champions.getAutoAttackProfile(championKey)
	local champ = Champions.Roster[championKey]
	if not champ then
		return Champions.ClassAutoAttack.Attack
	end
	local baseline = Champions.ClassAutoAttack[champ.Class] or Champions.ClassAutoAttack.Attack
	local out = {
		Damage = baseline.Damage,
		Interval = baseline.Interval,
		WindUp = baseline.WindUp,
		Range = baseline.Range,
		Style = baseline.Style,
		TravelTime = baseline.TravelTime,
		Color = champ.Color,
	}
	if champ.AutoAttack then
		for k, v in pairs(champ.AutoAttack) do
			out[k] = v
		end
	end
	return out
end

return Champions
