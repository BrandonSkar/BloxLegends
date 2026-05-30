local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Champions = require(Shared:WaitForChild("Champions"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ArenaBuilder = require(script:WaitForChild("ArenaBuilder"))
local LobbyBuilder = require(script:WaitForChild("LobbyBuilder"))
local PracticeBuilder = require(script:WaitForChild("PracticeBuilder"))
local MatchController = require(script:WaitForChild("MatchController"))
local CombatService = require(script:WaitForChild("CombatService"))
local MinionService = require(script:WaitForChild("MinionService"))
local TowerService = require(script:WaitForChild("TowerService"))
local PracticeService = require(script:WaitForChild("PracticeService"))
local AbilityHandler = require(script:WaitForChild("AbilityHandler"))
local RecallService = require(script:WaitForChild("RecallService"))
local PlayerDataService = require(script:WaitForChild("PlayerDataService"))
local MatchmakingService = require(script:WaitForChild("MatchmakingService"))

Remotes.init()

-- Atmosphere / lighting polish. Doesn't need image assets — just nudges the
-- built-in Lighting/Atmosphere/ColorCorrection toward a more dramatic look.
do
	local Lighting = game:GetService("Lighting")
	Lighting.Brightness = 2.4
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 130, 150)
	Lighting.Ambient = Color3.fromRGB(70, 75, 95)
	Lighting.ClockTime = 14.5
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.5
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	-- A subtle atmosphere for a sense of depth.
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atmo = Instance.new("Atmosphere")
		atmo.Density = 0.32
		atmo.Offset = 0.25
		atmo.Color = Color3.fromRGB(199, 199, 199)
		atmo.Decay = Color3.fromRGB(106, 112, 125)
		atmo.Glare = 0.4
		atmo.Haze = 1.2
		atmo.Parent = Lighting
	end
	-- A faint color correction so the world feels punchier.
	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Brightness = 0.02
		cc.Contrast = 0.08
		cc.Saturation = 0.12
		cc.TintColor = Color3.fromRGB(255, 247, 235)
		cc.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.7
		bloom.Size = 24
		bloom.Threshold = 0.95
		bloom.Parent = Lighting
	end
end

ArenaBuilder.build()
local lobby = LobbyBuilder.build()
PracticeBuilder.build()

local matchController = MatchController.new()
local playerData = PlayerDataService.new()
local combatService = CombatService.new(matchController)
local minionService = MinionService.new(matchController, combatService)
combatService:setMinionService(minionService)
local towerService = TowerService.new(matchController, combatService, minionService)
combatService:setTowerService(towerService)
minionService:setTowerService(towerService)
local practiceService = PracticeService.new(minionService)
minionService:setPracticeService(practiceService)
local abilityHandler = AbilityHandler.new(combatService, minionService, matchController)
abilityHandler:setTowerService(towerService)
abilityHandler.playerData = playerData
local matchmaking = MatchmakingService.new(lobby)
towerService.onNexusDestroyed = function(winningTeam)
	matchmaking:endMatch(winningTeam .. " wins — Nexus destroyed!")
end

local recallService = RecallService.new(matchController, combatService, matchmaking)
combatService:setRecallService(recallService)
abilityHandler:setRecallService(recallService)

combatService:start()
minionService:start()
towerService:start()
recallService:start()

-- =====================================================================
-- Spawn flows: lobby vs match
-- =====================================================================

-- Forward declarations for per-team champion-pick helpers defined further
-- below. spawnInMatch / spawnInPractice need to push the current locked-
-- champion list to the client right after opening the select UI; the helpers
-- live with the SelectChampion handler for cohesion, but Lua's lexical
-- resolution requires the local name to exist above its first use.
local broadcastTeamPicksTo

local function spawnAt(player, position, facing)
	-- Bind to the NEW character produced by this LoadCharacter call — not
	-- whatever was already in player.Character. In Studio "Server + Clients"
	-- tests with 2 players, the 2nd player can come in with a pre-existing
	-- character (auto-loaded by the client place defaults, or stale from a
	-- prior teardown). Reading player.Character before the new body parents
	-- meant we CFrame-teleported the stale body and the brand-new body
	-- parented at world origin — which is inside the arena, since the arena
	-- ground is at y=0 and the lobby is at y=600. Subscribing to the next
	-- CharacterAdded BEFORE triggering LoadCharacter guarantees we bind to
	-- the right body.
	local nextChar
	local conn
	conn = player.CharacterAdded:Connect(function(c)
		nextChar = c
		if conn then
			conn:Disconnect()
			conn = nil
		end
	end)

	local desc
	pcall(function()
		desc = Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if desc then
		local ok = pcall(function()
			player:LoadCharacterWithHumanoidDescription(desc)
		end)
		if not ok then
			player:LoadCharacter()
		end
	else
		player:LoadCharacter()
	end

	-- Wait for the LoadCharacter we just triggered to actually parent the body.
	local waited = 0
	while not nextChar and waited < 5 do
		task.wait(0.05)
		waited = waited + 0.05
	end
	if conn then
		conn:Disconnect()
	end
	local char = nextChar or player.Character
	if not char then
		return nil, nil
	end
	local humanoid = char:WaitForChild("Humanoid")
	local root = char:WaitForChild("HumanoidRootPart")
	-- Teleport IMMEDIATELY so the character doesn't fall through the void at origin.
	local look = facing and (position + facing * 10) or (position + Vector3.new(1, 0, 0) * 10)
	root.CFrame = CFrame.lookAt(position, Vector3.new(look.X, position.Y, look.Z))
	return char, humanoid
end

local function spawnInLobby(player)
	-- HRP must clear the lobby floor top (at LobbyOrigin.Y) by more than the
	-- humanoid's HipHeight + leg length (~3 studs). 4 studs was on the edge
	-- and the 2nd test player intermittently clipped through and fell.
	local char, humanoid = spawnAt(player, Config.LobbyOrigin + Vector3.new(0, 6, 0), Vector3.new(1, 0, 0))
	humanoid.WalkSpeed = 16
	humanoid.JumpPower = 50
	humanoid.UseJumpPower = true
	humanoid.AutoRotate = true
	-- Detach any team tag from a previous match.
	local head = char:FindFirstChild("Head")
	if head then
		local tag = head:FindFirstChild("TeamTag")
		if tag then
			tag:Destroy()
		end
	end
	-- Bring them back if they die in the lobby (they shouldn't, but just in case).
	humanoid.Died:Connect(function()
		task.wait(2)
		if player.Parent and matchmaking:getState(player) == "lobby" then
			spawnInLobby(player)
		end
	end)
end

local function spawnInMatch(player, team)
	local teamData = Config.Teams[team]

	-- Initial registration uses Pyromancer baseline stats as a placeholder.
	-- The CombatService entry is updated when the player picks a champion.
	local bonuses = playerData:computeBonuses(player)
	local placeholder = Champions.Roster.Pyromancer
	local maxHP = placeholder.MaxHP
	local walkSpeed = placeholder.WalkSpeed * (1 + bonuses.MoveSpeedPct / 100)

	combatService:register(player, maxHP, walkSpeed)
	local entry = combatService:getEntry(player)
	if entry then
		entry.bonuses = bonuses
		entry.summonerSpell = playerData:getSummonerSpell(player)
		entry.alive = true
		entry.hp = maxHP
		entry.target = nil
		entry.selectingChampion = true -- locks movement + ability casts
	end

	-- Per-body setup: builds the character, tags it, attaches the Died handler.
	-- Recursively called from inside the Died handler so every respawned body
	-- gets its own Died binding (the previous code only bound the original
	-- humanoid, so the second death never respawned).
	local function spawnBody()
		local char, humanoid = spawnAt(player, teamData.SpawnPosition, teamData.SpawnFacing)
		humanoid.WalkSpeed = 0 -- CombatService tick will set this each frame based on status
		humanoid.JumpPower = 0
		humanoid.UseJumpPower = true
		humanoid.AutoRotate = false
		-- Suppress the default Roblox name+health text — we render our own
		-- team-colored TeamTag billboard. Without this both labels stack.
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

		-- Tag for click-targeting
		char:SetAttribute("PlayerId", player.UserId)
		char:SetAttribute("Team", team)
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				part:SetAttribute("PlayerId", player.UserId)
				part:SetAttribute("Team", team)
			end
		end

		-- Nameplate
		local head = char:FindFirstChild("Head")
		if head then
			local old = head:FindFirstChild("TeamTag")
			if old then
				old:Destroy()
			end
			local gui = Instance.new("BillboardGui")
			gui.Name = "TeamTag"
			gui.Size = UDim2.fromOffset(90, 16)
			gui.StudsOffset = Vector3.new(0, 2.2, 0)
			gui.AlwaysOnTop = true
			gui.Parent = head
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundColor3 = teamData.Color
			label.BackgroundTransparency = 0.3
			label.BorderSizePixel = 0
			label.Text = player.DisplayName
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextStrokeTransparency = 0.3
			label.Parent = gui
			-- Team-colored border so ally vs enemy nameplates don't blend together.
			local nameCorner = Instance.new("UICorner")
			nameCorner.CornerRadius = UDim.new(0, 3)
			nameCorner.Parent = label
			local nameStroke = Instance.new("UIStroke")
			nameStroke.Color = teamData.Color
			nameStroke.Thickness = 2
			nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			nameStroke.Parent = label
		end

		humanoid.Died:Connect(function()
			task.wait(Config.RespawnDelay)
			if player.Parent and matchmaking:getState(player) == "in_match" then
				local e = combatService:getEntry(player)
				if e then
					e.alive = true
					e.hp = e.maxHP
					e.target = nil
				end
				spawnBody() -- new body, fresh Died handler
				combatService:replicateHP(player)
			end
		end)
	end

	spawnBody()
	combatService:replicateHP(player)
	matchController:sendStateTo(player)
	-- Open the champion-select UI on this client. Until they pick, their
	-- entry.selectingChampion stays true and CombatService keeps WalkSpeed = 0.
	Remotes.get("ChampionSelectStart"):FireClient(player, Champions.RosterOrder)
	-- Sync the locked-champion list so a player who opens select late sees
	-- teammates' picks already greyed out.
	broadcastTeamPicksTo(player)
end

-- Practice mode: bypass matchmaking and put the player in the practice room
-- with a respawning target dummy. Treated as "in_match" state so the in-match
-- HUD shows; the player picks a champion via the normal Champion Select UI.
local function spawnInPractice(player)
	-- Put them on Blue so existing team-of checks (auto-attack, abilities) see
	-- the dummy (team Red) as enemy.
	matchController.teams[player.UserId] = "Blue"
	matchController.gold[player.UserId] = matchController.gold[player.UserId] or 0
	matchmaking:_setPlayerState(player, "in_match", nil)

	local bonuses = playerData:computeBonuses(player)
	local placeholder = Champions.Roster.Pyromancer
	local maxHP = placeholder.MaxHP
	local walkSpeed = placeholder.WalkSpeed * (1 + bonuses.MoveSpeedPct / 100)
	combatService:register(player, maxHP, walkSpeed)
	local entry = combatService:getEntry(player)
	if entry then
		entry.bonuses = bonuses
		entry.summonerSpell = playerData:getSummonerSpell(player)
		entry.alive = true
		entry.hp = maxHP
		entry.target = nil
		entry.selectingChampion = true
	end

	local spawnPos = PracticeBuilder.getSpawnPos()
	local function spawnBody()
		local char, humanoid = spawnAt(player, spawnPos, Vector3.new(1, 0, 0))
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.UseJumpPower = true
		humanoid.AutoRotate = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

		char:SetAttribute("PlayerId", player.UserId)
		char:SetAttribute("Team", "Blue")
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				part:SetAttribute("PlayerId", player.UserId)
				part:SetAttribute("Team", "Blue")
			end
		end

		humanoid.Died:Connect(function()
			task.wait(Config.RespawnDelay)
			if player.Parent and matchmaking:getState(player) == "in_match" then
				local e = combatService:getEntry(player)
				if e then
					e.alive = true
					e.hp = e.maxHP
					e.target = nil
				end
				spawnBody()
				combatService:replicateHP(player)
			end
		end)
	end

	spawnBody()
	practiceService:ensureDummy()
	combatService:replicateHP(player)
	matchController:sendStateTo(player)
	Remotes.get("ChampionSelectStart"):FireClient(player, Champions.RosterOrder)
	broadcastTeamPicksTo(player)
end

Remotes.get("StartPractice").OnServerEvent:Connect(function(player)
	-- Only allow from the lobby — anyone in a zone or already in a match is ignored.
	if matchmaking:getState(player) ~= "lobby" then
		return
	end
	spawnInPractice(player)
end)

-- ===== Per-team champion-pick tracking (uniqueness within a team) =====
-- championPicks[team][championKey] = pickerUserId. Cleared on match end / on
-- player leaving the match. Practice mode players are tagged team "Blue" but
-- act solo; their team list is naturally empty of other pickers so the
-- uniqueness check has no effect.
local championPicks = { Blue = {}, Red = {} }

-- Picks visible to `player` = champions locked by everyone ELSE on their team.
-- Returns { [championKey] = pickerDisplayName }.
local function picksVisibleTo(player)
	local team = matchController:teamOf(player)
	if not team then
		return {}
	end
	local out = {}
	for championKey, userId in pairs(championPicks[team]) do
		if userId ~= player.UserId then
			local p = Players:GetPlayerByUserId(userId)
			out[championKey] = p and p.DisplayName or "Teammate"
		end
	end
	return out
end

function broadcastTeamPicksTo(player)
	Remotes.get("TeamChampionPicks"):FireClient(player, picksVisibleTo(player))
end

local function broadcastTeamPicksToTeam(team)
	for _, p in ipairs(Players:GetPlayers()) do
		if matchController:teamOf(p) == team then
			broadcastTeamPicksTo(p)
		end
	end
end

local function clearPickForPlayer(player)
	local team = matchController:teamOf(player)
	if not team then
		return
	end
	local removed = false
	for championKey, userId in pairs(championPicks[team]) do
		if userId == player.UserId then
			championPicks[team][championKey] = nil
			removed = true
		end
	end
	if removed then
		broadcastTeamPicksToTeam(team)
	end
end

-- Handle a player's champion selection: apply the champion's MaxHP / WalkSpeed,
-- mark their entry as no-longer-locked, and tell the client to close the UI.
Remotes.get("SelectChampion").OnServerEvent:Connect(function(player, championKey)
	local entry = combatService:getEntry(player)
	if not entry or not entry.selectingChampion then
		return
	end
	if typeof(championKey) ~= "string" or not Champions.Roster[championKey] then
		return
	end
	-- Uniqueness within team. If a teammate already locked this champion,
	-- silently reject — client UI also blocks the card, this is the
	-- belt-and-suspenders server check.
	local team = matchController:teamOf(player)
	if team and championPicks[team] then
		local owner = championPicks[team][championKey]
		if owner and owner ~= player.UserId then
			-- Re-sync the client's locked-list in case it was stale.
			broadcastTeamPicksTo(player)
			return
		end
		championPicks[team][championKey] = player.UserId
	end
	local champ = Champions.Roster[championKey]
	local bonuses = entry.bonuses or { MoveSpeedPct = 0 }
	local maxHP = champ.MaxHP
	local walkSpeed = champ.WalkSpeed * (1 + bonuses.MoveSpeedPct / 100)
	entry.championKey = championKey
	entry.maxHP = maxHP
	entry.hp = maxHP
	entry.baseSpeed = walkSpeed
	entry.selectingChampion = false
	combatService:replicateHP(player)
	Remotes.get("ChampionSelected"):FireClient(player, championKey)
	-- Tell teammates the picks list grew.
	if team then
		broadcastTeamPicksToTeam(team)
	end
end)

-- =====================================================================
-- Match lifecycle (callbacks from MatchmakingService)
-- =====================================================================

matchmaking.callbacks.onMatchStart = function(blueIds, redIds)
	-- Clean any leftover minions from a previous match.
	minionService:clearAll()
	-- Assign teams explicitly (override auto-balance from MatchController).
	matchController.teams = {}
	for _, uid in ipairs(blueIds) do
		matchController.teams[uid] = "Blue"
		matchController.gold[uid] = matchController.gold[uid] or 0
	end
	for _, uid in ipairs(redIds) do
		matchController.teams[uid] = "Red"
		matchController.gold[uid] = matchController.gold[uid] or 0
	end
	for _, uid in ipairs(blueIds) do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			spawnInMatch(p, "Blue")
		end
	end
	for _, uid in ipairs(redIds) do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			spawnInMatch(p, "Red")
		end
	end
	towerService:initTowers()
	minionService:startWaves()
end

matchmaking.callbacks.onMatchEnd = function()
	minionService:stopWaves()
	minionService:clearAll()
	towerService:reset()
	-- Wipe per-team champion picks so the next match's select screen is clean.
	championPicks = { Blue = {}, Red = {} }
	-- Only players whose state just got reset to "lobby" by endMatch are returning
	-- from this match. Anyone still in_zone is a leftover waiting for the next
	-- pairing and must not be teleported.
	for _, player in ipairs(Players:GetPlayers()) do
		if matchmaking:getState(player) == "lobby" then
			combatService:unregister(player)
			matchController:removePlayer(player)
			spawnInLobby(player)
		end
	end
end

-- =====================================================================
-- ClickDetectors (zone pads, shop kiosk)
-- =====================================================================

matchmaking:wireClickDetectors(function(_player, _zoneId)
	-- Zone clicks no longer auto-join; players walk onto the pad and pick
	-- Open or Private from the in-world prompt.
end, function(_player)
	-- Shop click is handled client-side by toggling the shop UI; nothing to do server-side.
end)

-- =====================================================================
-- Lobby remotes
-- =====================================================================

-- Teleport a player onto the center of a zone pad (used after joining a zone
-- so they don't have to clip through the walls themselves).
local function teleportToZone(player, zoneId)
	local rec = lobby.zones and lobby.zones[zoneId]
	if not rec or not rec.pad then
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(rec.pad.Position + Vector3.new(0, 4, 0))
	end
end

Remotes.get("JoinZone").OnServerEvent:Connect(function(player, zoneId, accessMode)
	if typeof(zoneId) ~= "number" then
		return
	end
	if accessMode ~= "anyone" and accessMode ~= "friends" and accessMode ~= "solo" then
		accessMode = "anyone"
	end
	if matchmaking:joinZone(player, zoneId, accessMode) then
		teleportToZone(player, zoneId)
	end
end)

Remotes.get("LeaveZone").OnServerEvent:Connect(function(player)
	-- Capture who's in the zone BEFORE the kick (leaveZone clears it) so we
	-- can teleport everyone back to the lobby spawn.
	local s = matchmaking.playerStates[player.UserId]
	local kicked = {}
	if s and s.state == "in_zone" then
		local zone = matchmaking.zones[s.zoneId]
		if zone then
			for _, uid in ipairs(zone.players) do
				table.insert(kicked, uid)
			end
		end
	end
	if matchmaking:leaveZone(player) then
		for _, uid in ipairs(kicked) do
			local p = Players:GetPlayerByUserId(uid)
			if p then
				spawnInLobby(p)
			end
		end
	end
end)

Remotes.get("StartNow").OnServerEvent:Connect(function(player)
	matchmaking:startNow(player)
end)

Remotes.get("LeaveMatch").OnServerEvent:Connect(function(player)
	if matchmaking:getState(player) == "in_match" then
		matchmaking:leaveMatch(player)
		clearPickForPlayer(player)
		combatService:unregister(player)
		matchController:removePlayer(player)
		spawnInLobby(player)
	end
end)

Remotes.get("BuyRune").OnServerEvent:Connect(function(player, runeKey, tier)
	local ok, reason = playerData:tryBuyRune(player, runeKey, tier)
	Remotes.get("BuyRuneResult"):FireClient(player, ok, reason)
end)

Remotes.get("SetSummonerSpell").OnServerEvent:Connect(function(player, spellKey)
	playerData:setSummonerSpell(player, spellKey)
end)

-- =====================================================================
-- Gameplay remotes — only valid while in_match
-- =====================================================================

Remotes.get("SetTarget").OnServerEvent:Connect(function(player, targetType, targetId)
	if matchmaking:getState(player) ~= "in_match" then
		return
	end
	if targetType == nil then
		combatService:setTarget(player, nil, nil)
		return
	end
	if typeof(targetType) ~= "string" or typeof(targetId) ~= "number" then
		return
	end
	local attackerTeam = matchController:teamOf(player)
	if targetType == "minion" then
		local m = minionService:getMinion(targetId)
		if not m or not m.alive or m.team == attackerTeam then
			return
		end
	elseif targetType == "player" then
		local other = Players:GetPlayerByUserId(targetId)
		if not other or other == player then
			return
		end
		if matchController:teamOf(other) == attackerTeam then
			return
		end
	elseif targetType == "tower" then
		local t = towerService:getTower(targetId)
		if not t or not t.alive or t.team == attackerTeam then
			return
		end
	else
		return
	end
	combatService:setTarget(player, targetType, targetId)
end)

-- AbilityHandler's own listener checks `abilityHandler.isInMatch(player)` before processing.

-- =====================================================================
-- Player lifecycle
-- =====================================================================

-- Dedupe: in Studio's multi-player test mode, players that join during script
-- load can be picked up by BOTH the PlayerAdded connect and the GetPlayers()
-- backfill loop. Without this guard, onPlayerAdded fires twice for the same
-- player — the second call kicks off another LoadCharacter that races the
-- first lobby teleport, leaving the character at origin (which sits inside
-- the arena, not the lobby up at y=600).
local handledJoin = {}
local function onPlayerAdded(player)
	if handledJoin[player.UserId] then
		return
	end
	handledJoin[player.UserId] = true
	playerData:register(player)
	matchmaking:onPlayerJoined(player)
	spawnInLobby(player)
	task.wait(0.2)
	playerData:replicate(player)
	matchmaking:sendLobbyTimerTo(player)
end

-- Kick off the global lobby-timer tick loop.
matchmaking:startTimerLoop()

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	-- If they were in a match, end it cleanly.
	if matchmaking:getState(player) == "in_match" then
		matchmaking:leaveMatch(player)
	end
	-- Free up this player's champion pick BEFORE removing their team mapping,
	-- so teammates see the slot reopen.
	clearPickForPlayer(player)
	matchmaking:onPlayerLeft(player)
	playerData:unregister(player)
	combatService:unregister(player)
	matchController:removePlayer(player)
	handledJoin[player.UserId] = nil
end)

-- Tell AbilityHandler how to look up matchmaking state so it can gate casts.
abilityHandler.isInMatch = function(player)
	return matchmaking:getState(player) == "in_match"
end

print("[Server] BloxLegends ready — lobby + matchmaking online.")
