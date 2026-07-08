local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Champions = require(Shared:WaitForChild("Champions"))

local CameraController = require(script:WaitForChild("CameraController"))
local MovementController = require(script:WaitForChild("MovementController"))
local AbilityCaster = require(script:WaitForChild("AbilityCaster"))
local TargetingController = require(script:WaitForChild("TargetingController"))
local HUD = require(script:WaitForChild("HUD"))
local LobbyUI = require(script:WaitForChild("LobbyUI"))
local BushController = require(script:WaitForChild("BushController"))
local ChampionSelectUI = require(script:WaitForChild("ChampionSelectUI"))
local DamageFX = require(script:WaitForChild("DamageFX"))
local AutoAttackFX = require(script:WaitForChild("AutoAttackFX"))
local TargetReticle = require(script:WaitForChild("TargetReticle"))
local HPBarVisibility = require(script:WaitForChild("HPBarVisibility"))
local AttackRangeIndicator = require(script:WaitForChild("AttackRangeIndicator"))
local TowerHUD = require(script:WaitForChild("TowerHUD"))
local RecallController = require(script:WaitForChild("RecallController"))
local ShopUI = require(script:WaitForChild("ShopUI"))
local SoundFX = require(script:WaitForChild("SoundFX"))
local ScoreboardUI = require(script:WaitForChild("ScoreboardUI"))
local Minimap = require(script:WaitForChild("Minimap"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local camera = CameraController.new()
camera:start()

local movement = MovementController.new(camera)
movement:start()

local caster = AbilityCaster.new(camera)
caster:start()

local targeting = TargetingController.new(camera)
targeting:start()
caster:setTargetingController(targeting)
-- TargetingController needs the BushController (for hidden-enemy filtering)
-- — both are created below; we wire after construction.

local hud = HUD.create(playerGui)
hud:setVisible(false)
-- HUD ability slots support drag-aim: press to start, drag to move the
-- ground-ring indicator, release to fire at that spot. A quick tap
-- (no meaningful drag) falls through to camera-forward aim so simple
-- taps still cast in the direction the player is facing.
hud:setOnAimStart(function(slot, x, y)
	caster:aimStart(slot, x, y)
end)
hud:setOnAimUpdate(function(x, y)
	caster:aimUpdate(x, y)
end)
hud:setOnAimEnd(function(x, y, cancel)
	caster:aimEnd(x, y, cancel)
end)

local lobbyUI = LobbyUI.create(playerGui)
lobbyUI:start()

-- If we were teleported straight into a match (reserved match server), the join
-- data carries the team map. Suppress the lobby UI right away so it doesn't
-- flash before the server's "in_match" state push arrives.
do
	local td = TeleportService:GetLocalPlayerTeleportData()
	if type(td) == "table" and td.teams then
		lobbyUI:setState("in_match")
	end
end

local bushController = BushController.new()
bushController:start()
targeting:setBushController(bushController)

local damageFX = DamageFX.new()
damageFX:start()

local autoAttackFX = AutoAttackFX.new()
autoAttackFX:start()

local hpBarVisibility = HPBarVisibility.new()
hpBarVisibility:start()

local attackRangeIndicator = AttackRangeIndicator.new()
attackRangeIndicator:start()

local towerHUD = TowerHUD.new()
towerHUD:attach(playerGui)
towerHUD:start()

local reticle = TargetReticle.new()

local recall = RecallController.new()
recall:start(playerGui)

local championSelect = ChampionSelectUI.create(playerGui)
championSelect:setOnPick(function(key)
	Remotes.get("SelectChampion"):FireServer(key)
end)

-- =====================================================================
-- Scoreboard (hold Tab / tap the score bar), minimap, sounds
-- =====================================================================

-- We render our own scoreboard — hide Roblox's default player list so Tab
-- doesn't fight it.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

local scoreboard = ScoreboardUI.create(playerGui)
local minimap = Minimap.new()
minimap:attach(playerGui)

local myTeam = nil
local clientInMatch = false

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Tab and clientInMatch then
		scoreboard:setVisible(true)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Tab then
		scoreboard:setVisible(false)
	end
end)
hud:setOnScoreBarTap(function()
	if clientInMatch then
		scoreboard:toggle()
	end
end)

targeting:onChanged(function(target)
	hud:setTarget(target)
	reticle:setTarget(target)
end)

-- =====================================================================
-- In-match item shop
-- =====================================================================

local shopUI = ShopUI.create(playerGui)
shopUI:setOnBuy(function(itemKey)
	Remotes.get("BuyItem"):FireServer(itemKey)
end)

-- Tracks whether we're standing in base (the shop is gated to the base zone).
local clientInBase = false

-- Recall button mirrors pressing B.
hud:setOnRecall(function()
	Remotes.get("RecallStart"):FireServer()
end)
-- Shop button toggles the panel. The button is disabled out of base and the
-- panel auto-closes when you leave, so this only does anything in base.
hud:setOnShop(function()
	shopUI:toggle()
end)
-- P is a keyboard shortcut for the same toggle while in base.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.P and clientInBase then
		shopUI:toggle()
	end
end)

-- =====================================================================
-- Server state → client UI mode
-- =====================================================================

local function applyState(state, _zoneId)
	clientInMatch = state == "in_match"
	if state == "in_match" then
		hud:setVisible(true)
		targeting:setEnabled(true)
		attackRangeIndicator:setEnabled(true)
		towerHUD:setVisible(true)
		recall:setEnabled(true)
		minimap:setEnabled(true)
	else
		hud:setVisible(false)
		targeting:setEnabled(false)
		attackRangeIndicator:setEnabled(false)
		towerHUD:setVisible(false)
		recall:setEnabled(false)
		championSelect:hide()
		shopUI:close()
		hud:setShopEnabled(false)
		clientInBase = false
		minimap:setEnabled(false)
		scoreboard:setVisible(false)
		hud:setMatchClock(nil)
		hud:hideDeath()
	end
end

Remotes.get("PlayerStateChanged").OnClientEvent:Connect(function(state, zoneId)
	applyState(state, zoneId)
	lobbyUI:setState(state, zoneId)
end)

Remotes.get("ZonesUpdated").OnClientEvent:Connect(function(zones)
	lobbyUI:setZones(zones)
end)

Remotes.get("LobbyTimerChanged").OnClientEvent:Connect(function(payload)
	lobbyUI:setLobbyTimer(payload)
end)

Remotes.get("PlayerDataChanged").OnClientEvent:Connect(function(data)
	lobbyUI:setPlayerData(data)
end)

Remotes.get("BuyRuneResult").OnClientEvent:Connect(function(ok, reason)
	if not ok then
		print("[Client] Couldn't buy rune:", reason)
	end
end)

Remotes.get("MatchStarted").OnClientEvent:Connect(function(team)
	myTeam = team
	hud:setTeam(team)
	print("[Client] Match started — team:", team)
end)

Remotes.get("MatchEnded").OnClientEvent:Connect(function(reason)
	-- Big VICTORY/DEFEAT banner (+ jingle) based on which team the reason names.
	local blueWon = string.match(reason or "", "^Blue wins") ~= nil
	local redWon = string.match(reason or "", "^Red wins") ~= nil
	if myTeam and (blueWon or redWon) then
		local iWon = (myTeam == "Blue" and blueWon) or (myTeam == "Red" and redWon)
		if iWon then
			hud:announce("VICTORY!", Color3.fromRGB(255, 215, 100), 5)
			SoundFX.victory()
		else
			hud:announce("DEFEAT", Color3.fromRGB(220, 90, 90), 5)
			SoundFX.defeat()
		end
	end
	print("[Client] Match ended:", reason)
end)

-- =====================================================================
-- Score / progression remotes
-- =====================================================================

Remotes.get("KillFeed").OnClientEvent:Connect(function(info)
	hud:addKillFeed(info)
	local teamColor = (info.killerTeam == "Blue" and Color3.fromRGB(120, 190, 255))
		or (info.killerTeam == "Red" and Color3.fromRGB(255, 130, 120))
		or nil
	if info.label then
		hud:announce(info.label, teamColor, 2.5)
		SoundFX.play("announce")
	end
	if info.killerId == player.UserId then
		SoundFX.play("kill")
	end
end)

Remotes.get("TeamScoreChanged").OnClientEvent:Connect(function(score)
	hud:setTeamScore(score)
end)

Remotes.get("MatchClock").OnClientEvent:Connect(function(serverStartTime)
	hud:setMatchClock(serverStartTime)
end)

Remotes.get("MatchStats").OnClientEvent:Connect(function(stats)
	scoreboard:setStats(stats)
end)

Remotes.get("XPChanged").OnClientEvent:Connect(function(level, xp, xpToNext)
	hud:setXP(level, xp, xpToNext)
end)

Remotes.get("LevelUp").OnClientEvent:Connect(function(userId, _level)
	if userId == player.UserId then
		hud:flashLevelUp()
		SoundFX.play("levelup")
	end
end)

Remotes.get("YouDied").OnClientEvent:Connect(function(respawnSeconds, killerName)
	hud:showDeath(respawnSeconds, killerName)
	SoundFX.play("death")
end)

Remotes.get("Announce").OnClientEvent:Connect(function(text, color, duration)
	hud:announce(text, color, duration)
	SoundFX.play("objective")
end)

Remotes.get("ChampionSelectStart").OnClientEvent:Connect(function(_keys)
	championSelect:show()
end)

Remotes.get("TeamChampionPicks").OnClientEvent:Connect(function(locked)
	championSelect:setLockedChampions(locked)
end)

Remotes.get("ChampionSelected").OnClientEvent:Connect(function(championKey)
	championSelect:hide()
	hud:setChampion(championKey)
	caster:setChampion(championKey)
	targeting:setChampion(championKey)
	attackRangeIndicator:setChampion(championKey)
	-- Stock the shop with this champion's class items.
	local champ = Champions.Roster[championKey]
	if champ then
		shopUI:setClass(champ.Class)
	end
end)

-- =====================================================================
-- In-match gameplay remotes
-- =====================================================================

Remotes.get("HPChanged").OnClientEvent:Connect(function(hp, maxHP, alive)
	hud:setHP(hp, maxHP)
	-- Respawned (or healed back to life) → drop the death overlay.
	if alive and hp > 0 then
		hud:hideDeath()
	end
end)

Remotes.get("ShieldChanged").OnClientEvent:Connect(function(amount)
	hud:setShield(amount)
end)

Remotes.get("StatusEffectChanged").OnClientEvent:Connect(function(statusType, payload)
	hud:setStatus(statusType, payload)
end)

Remotes.get("AbilityCooldownChanged").OnClientEvent:Connect(function(slot, duration)
	hud:setCooldown(slot, duration)
	caster:setCooldown(slot, duration)
	-- The cooldown push only happens on a successful cast — perfect cast cue.
	SoundFX.play("ability")
end)

-- Soft whoosh/slash on the local player's own auto-attacks.
Remotes.get("AutoAttackFired").OnClientEvent:Connect(function(attackerType, attackerId, _tt, _ti, style)
	if attackerType == "player" and attackerId == player.UserId then
		SoundFX.play(style == "melee" and "castMelee" or "castRanged")
	end
end)

-- Recall completion chime (RecallController renders the channel bar itself).
Remotes.get("RecallState").OnClientEvent:Connect(function(state)
	if state == "complete" then
		SoundFX.play("recall")
	end
end)

Remotes.get("GoldChanged").OnClientEvent:Connect(function(amount)
	hud:setGold(amount)
	shopUI:setGold(amount)
end)

-- In-base state gates the shop button + auto-closes the panel when you leave.
Remotes.get("InBaseChanged").OnClientEvent:Connect(function(inBase)
	clientInBase = inBase and true or false
	hud:setShopEnabled(clientInBase)
	if not clientInBase then
		shopUI:close()
	end
end)

-- Owned-item counts pushed by the server after each purchase / on (re)spawn.
Remotes.get("ItemsChanged").OnClientEvent:Connect(function(owned)
	shopUI:setOwned(owned)
end)

Remotes.get("BuyItemResult").OnClientEvent:Connect(function(ok, reason)
	if ok then
		SoundFX.play("buy")
	else
		SoundFX.play("deny")
		print("[Client] Couldn't buy item:", reason)
	end
end)

print("[Client] BloxLegends client ready.")
