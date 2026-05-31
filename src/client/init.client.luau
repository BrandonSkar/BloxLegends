local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local CameraController = require(script:WaitForChild("CameraController"))
local MovementController = require(script:WaitForChild("MovementController"))
local AbilityCaster = require(script:WaitForChild("AbilityCaster"))
local TargetingController = require(script:WaitForChild("TargetingController"))
local AbilityIndicatorController = require(script:WaitForChild("AbilityIndicatorController"))
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

local indicatorController = AbilityIndicatorController.new(camera, targeting)
indicatorController:setAbilityCaster(caster)
indicatorController:start()
caster:setIndicatorController(indicatorController)
-- TargetingController needs the BushController (for hidden-enemy filtering)
-- — both are created below; we wire after construction.

local hud = HUD.create(playerGui)
hud:setCameraController(camera)
hud:setVisible(false)

local lobbyUI = LobbyUI.create(playerGui)
lobbyUI:start()

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

targeting:onChanged(function(target)
	hud:setTarget(target)
	reticle:setTarget(target)
end)

hud.abilityInputBegan = function(slot)
	caster:startTouchPreview(slot)
end

hud.abilityInputChanged = function(slot, direction, rangePct, isCancelled)
	caster:updateTouchAim(slot, direction, rangePct, isCancelled)
end

hud.abilityInputEnded = function(slot, shouldCast)
	caster:endTouchPreview(slot, shouldCast)
end

-- =====================================================================
-- Server state → client UI mode
-- =====================================================================

local function applyState(state, _zoneId)
	if state == "in_match" then
		hud:setVisible(true)
		targeting:setEnabled(true)
		attackRangeIndicator:setEnabled(true)
		towerHUD:setVisible(true)
		recall:setEnabled(true)
	else
		hud:setVisible(false)
		targeting:setEnabled(false)
		attackRangeIndicator:setEnabled(false)
		towerHUD:setVisible(false)
		recall:setEnabled(false)
		championSelect:hide()
		indicatorController:clearPreview()
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
	print("[Client] Match started — team:", team)
end)

Remotes.get("MatchEnded").OnClientEvent:Connect(function(reason)
	print("[Client] Match ended:", reason)
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
end)

-- =====================================================================
-- In-match gameplay remotes
-- =====================================================================

Remotes.get("HPChanged").OnClientEvent:Connect(function(hp, maxHP, _alive)
	hud:setHP(hp, maxHP)
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
end)

Remotes.get("GoldChanged").OnClientEvent:Connect(function(amount)
	hud:setGold(amount)
end)

print("[Client] BloxLegends client ready.")
