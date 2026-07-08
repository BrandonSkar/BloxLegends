local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Champions = require(Shared:WaitForChild("Champions"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local ServerRole = require(Shared:WaitForChild("ServerRole"))

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
local ShopService = require(script:WaitForChild("ShopService"))
local ScoreService = require(script:WaitForChild("ScoreService"))
local JungleService = require(script:WaitForChild("JungleService"))
local MatchTeleport = require(script:WaitForChild("MatchTeleport"))

-- =====================================================================
-- Server role (see ServerRole.luau). One place runs as the lobby, as a
-- reserved match instance, or — in Studio — as an all-in-one local server.
-- =====================================================================
local ROLE = ServerRole.get()
local IS_LOCAL = ROLE == "local"
local IS_LOBBY = ROLE == "lobby"
local IS_MATCH = ROLE == "match"
local RUN_COMBAT = IS_LOCAL or IS_MATCH -- build the arena + tick combat loops
local RUN_LOBBY = IS_LOCAL or IS_LOBBY -- build the lobby + run matchmaking zones

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

-- Only servers that actually run a match build the arena. The lobby server
-- skips it; a reserved match server skips the lobby. Studio builds everything.
if RUN_COMBAT then
	ArenaBuilder.build()
end
local lobby = RUN_LOBBY and LobbyBuilder.build() or { zones = {} }
-- The practice room exists wherever there's a lobby (Studio + production
-- lobby servers) so queueing players always have something to do.
if RUN_LOBBY then
	PracticeBuilder.build()
end

local matchController = MatchController.new()
local playerData = PlayerDataService.new()
local combatService = CombatService.new(matchController)
local minionService = MinionService.new(matchController, combatService)
combatService:setMinionService(minionService)
local towerService = TowerService.new(matchController, combatService, minionService)
combatService:setTowerService(towerService)
minionService:setTowerService(towerService)
-- Score: kills/assists/gold/XP payouts, kill feed, match clock, scoreboard.
local scoreService = ScoreService.new(matchController, combatService)
combatService:setScoreService(scoreService)
minionService:setScoreService(scoreService)
towerService:setScoreService(scoreService)
matchController.scoreService = scoreService
-- Jungle: neutral buff camps + the Overlord boss (arena servers only).
local jungleService = JungleService.new(minionService, combatService, matchController, scoreService)
minionService:setJungleService(jungleService)
local practiceService = PracticeService.new(minionService, combatService, matchController)
minionService:setPracticeService(practiceService)
combatService:setPracticeService(practiceService)
local abilityHandler = AbilityHandler.new(combatService, minionService, matchController)
abilityHandler:setTowerService(towerService)
abilityHandler.playerData = playerData
local matchmaking = MatchmakingService.new(lobby, { delegated = IS_LOBBY })
towerService.onNexusDestroyed = function(winningTeam)
	matchmaking:endMatch(winningTeam .. " wins — Nexus destroyed!")
end

local recallService = RecallService.new(matchController, combatService, matchmaking)
combatService:setRecallService(recallService)
abilityHandler:setRecallService(recallService)

-- In-match item shop (spends match gold, gated to the base regen zone).
local shopService = ShopService.new(combatService, matchController, recallService)

-- Combat / minion / recall loops tick everywhere (cheap when nothing is
-- registered) so the practice room works on lobby servers too. Towers and
-- jungle only exist where the arena does.
combatService:start()
minionService:start()
recallService:start()
if RUN_COMBAT then
	towerService:start()
	jungleService:start()
end
-- Pit bot AI only where the Pit exists (Studio + production lobby servers).
if RUN_LOBBY then
	practiceService:start()
end

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
	-- Fresh item loadout + re-sync the shop's in-base gate for the new match.
	shopService:resetPlayer(player)
	recallService:clearInBaseState(player)

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

		-- Nameplate (shows current champion level; CombatService updates the
		-- text on level-up).
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
			local curEntry = combatService:getEntry(player)
			label.Text = ("[%d] %s"):format((curEntry and curEntry.level) or 1, player.DisplayName)
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
			-- Death timers scale with match time; CombatService stamps the
			-- entry at the moment of death.
			local eAtDeath = combatService:getEntry(player)
			task.wait((eAtDeath and eAtDeath.respawnDelay) or Config.RespawnDelay)
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

-- The Pit: bypass matchmaking and drop the player into the shared free-for-all
-- warm-up arena (sparring bots + a target dummy + any other waiting players).
-- Treated as "in_match" state so the in-match HUD shows; the player picks a
-- champion via the normal Champion Select UI. Each Pit player gets a UNIQUE
-- one-man team ("FFA<userId>") — that single fact is what turns every existing
-- "enemy = different team" check (targeting, abilities, kill credit) into
-- free-for-all PvP without special cases.
local PIT_TAG_COLOR = Color3.fromRGB(255, 140, 70)

local function spawnInPractice(player)
	local ffaTeam = "FFA" .. player.UserId
	matchController.teams[player.UserId] = ffaTeam
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
		-- Changes the recall destination + keeps the shop always available.
		entry.practiceMode = true
	end
	shopService:resetPlayer(player)
	recallService:clearInBaseState(player)
	-- Practice gold so builds can be tested; kills top it up from there.
	matchController:addGold(player, Config.Pit.StartingGold)

	local function spawnBody()
		-- Scattered spawn plates so respawns don't stack players on one spot.
		local char, humanoid = spawnAt(player, PracticeBuilder.getSpawnPos(), Vector3.new(1, 0, 0))
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.UseJumpPower = true
		humanoid.AutoRotate = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

		char:SetAttribute("PlayerId", player.UserId)
		char:SetAttribute("Team", ffaTeam)
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") then
				part:SetAttribute("PlayerId", player.UserId)
				part:SetAttribute("Team", ffaTeam)
			end
		end

		-- Ember FFA nameplate so Pit brawlers can read each other's level/name.
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
			label.BackgroundColor3 = Color3.fromRGB(40, 30, 25)
			label.BackgroundTransparency = 0.3
			label.BorderSizePixel = 0
			local curEntry = combatService:getEntry(player)
			label.Text = ("[%d] %s"):format((curEntry and curEntry.level) or 1, player.DisplayName)
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.TextStrokeTransparency = 0.3
			label.Parent = gui
			local nameCorner = Instance.new("UICorner")
			nameCorner.CornerRadius = UDim.new(0, 3)
			nameCorner.Parent = label
			local nameStroke = Instance.new("UIStroke")
			nameStroke.Color = PIT_TAG_COLOR
			nameStroke.Thickness = 2
			nameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			nameStroke.Parent = label
		end

		-- Brief spawn protection so a fresh body can't be farmed on its plate.
		combatService:applyDamageReduction(player, 0, Config.Pit.SpawnProtection)

		humanoid.Died:Connect(function()
			local eAtDeath = combatService:getEntry(player)
			task.wait((eAtDeath and eAtDeath.respawnDelay) or Config.RespawnDelay)
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
	practiceService:onPlayerEnteredPit(player)
	combatService:replicateHP(player)
	matchController:sendStateTo(player)
	Remotes.get("PracticeStarted"):FireClient(player)
	Remotes.get("ChampionSelectStart"):FireClient(player, Champions.RosterOrder)
	broadcastTeamPicksTo(player)
end

-- Practice runs wherever the lobby does (Studio + production lobby servers) —
-- the room lives far above the world and the combat loops tick everywhere.
if RUN_LOBBY then
	Remotes.get("StartPractice").OnServerEvent:Connect(function(player)
		-- Only allow from the lobby — anyone in a zone or already in a match is ignored.
		if matchmaking:getState(player) ~= "lobby" then
			return
		end
		spawnInPractice(player)
	end)
end

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
	-- Pit players carry FFA teams with no pick table — everything's available.
	if not team or not championPicks[team] then
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
	if not team or not championPicks[team] then
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
	entry.championKey = championKey
	entry.selectingChampion = false
	-- One formula for max HP / walk speed (champion × level × items × runes),
	-- then start the match at full health.
	combatService:recomputeDerived(player)
	entry.hp = entry.maxHP
	combatService:replicateHP(player)
	scoreService:setChampion(player, championKey)
	-- Prime the client's XP bar (level 1, 0 XP).
	Remotes.get("XPChanged"):FireClient(player, entry.level, entry.xp, Config.xpToNext(entry.level))
	Remotes.get("ChampionSelected"):FireClient(player, championKey)
	-- Tell teammates the picks list grew.
	if team then
		broadcastTeamPicksToTeam(team)
	end
end)

-- =====================================================================
-- Reserved match server: arrivals + match kickoff.
-- Players are teleported in from a lobby server carrying { teams, loadouts }
-- in their join data. We spawn each into champion-select as they arrive, and
-- start towers/minion waves once the whole expected roster is present (or a
-- short grace timeout elapses, so one missing player can't stall the match).
-- =====================================================================
local MATCH_FILL_TIMEOUT = 12 -- seconds to wait for stragglers before kicking off
local MATCH_END_RETURN_DELAY = 5 -- seconds to show the end screen before teleporting home
local matchExpected -- { [userId] = "Blue"/"Red" } captured from the first arrival
local matchArrived = {} -- [userId] = true
local matchBegun = false

local function beginMatch()
	if matchBegun or not matchExpected then
		return
	end
	matchBegun = true
	local blue, red = {}, {}
	for uid, team in pairs(matchExpected) do
		if team == "Red" then
			table.insert(red, uid)
		else
			table.insert(blue, uid)
		end
	end
	-- Hand the roster to MatchmakingService so its abandon check (_checkMatchEnd)
	-- and endMatch broadcast work just like a locally-run match.
	matchmaking.matchInProgress = true
	matchmaking.matchTeams = { Blue = blue, Red = red }
	minionService:clearAll()
	towerService:initTowers()
	minionService:startWaves()
	jungleService:startSpawns()
	-- Start the match clock + push initial score/stats to everyone.
	scoreService:onMatchBegin()
end

local function handleMatchArrival(player)
	local jd = player:GetJoinData()
	local td = jd and jd.TeleportData
	local teams = td and td.teams
	local team = teams and teams[tostring(player.UserId)]
	if not team then
		-- Stray joiner on a reserved server with no match assignment — send home.
		matchmaking:_setPlayerState(player, "lobby", nil)
		MatchTeleport.sendToLobby({ player })
		return
	end
	if not matchExpected then
		matchExpected = {}
		for k, v in pairs(teams) do
			matchExpected[tonumber(k)] = v
		end
		-- Kick off even if someone never arrives.
		task.delay(MATCH_FILL_TIMEOUT, beginMatch)
	end
	-- Restore the loadout carried from the lobby. With no DataStore, this is the
	-- only source of this player's runes / summoner spell on this server.
	local lo = td.loadouts and td.loadouts[tostring(player.UserId)]
	if lo then
		local d = playerData:get(player)
		if d then
			d.runes = lo.runes or {}
			d.summonerSpell = lo.summonerSpell or d.summonerSpell
		end
	end
	matchController.teams[player.UserId] = team
	matchController.gold[player.UserId] = matchController.gold[player.UserId] or 0
	matchmaking:_setPlayerState(player, "in_match", nil)
	Remotes.get("MatchStarted"):FireClient(player, team)
	matchArrived[player.UserId] = true
	playerData:replicate(player)
	spawnInMatch(player, team)
	-- Late arrivals still need the match clock + current score/stats.
	scoreService:sendSnapshotTo(player)
	-- All expected players here → start the match now rather than waiting out the timeout.
	local allHere = true
	for uid in pairs(matchExpected) do
		if not matchArrived[uid] then
			allHere = false
			break
		end
	end
	if allHere then
		beginMatch()
	end
end

-- =====================================================================
-- Match lifecycle (callbacks from MatchmakingService)
-- =====================================================================

matchmaking.callbacks.onMatchStart = function(blueIds, redIds)
	-- Lobby server: don't run the match here — reserve a private server and
	-- teleport the paired group into it, carrying their loadouts.
	if IS_LOBBY then
		local players = {}
		for _, uid in ipairs(blueIds) do
			local p = Players:GetPlayerByUserId(uid)
			if p then
				table.insert(players, p)
			end
		end
		for _, uid in ipairs(redIds) do
			local p = Players:GetPlayerByUserId(uid)
			if p then
				table.insert(players, p)
			end
		end
		if #players == 0 then
			return
		end
		local loadouts = MatchTeleport.encodeLoadouts(players, playerData)
		local ok, err = MatchTeleport.sendGroupToMatch(blueIds, redIds, players, loadouts)
		if not ok then
			warn("[Lobby] match teleport failed, returning group to lobby:", err)
			for _, p in ipairs(players) do
				matchmaking:_setPlayerState(p, "lobby", nil)
				spawnInLobby(p)
			end
		end
		return
	end

	-- Studio (local) server: run the match in this server (original behavior).
	-- Clean any leftover minions from a previous match + fresh score sheet.
	minionService:clearAll()
	scoreService:resetMatch()
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
	jungleService:startSpawns()
	scoreService:onMatchBegin()
end

matchmaking.callbacks.onMatchEnd = function()
	minionService:stopWaves()
	minionService:clearAll()
	jungleService:stopAndClear()
	towerService:reset()
	-- Wipe per-team champion picks so the next match's select screen is clean.
	championPicks = { Blue = {}, Red = {} }

	-- Reserved match server: this instance is done. Carry everyone's loadout
	-- back and teleport them to a public lobby server, then let Roblox shut this
	-- empty reserved server down. (matchmaking:endMatch already fired MatchEnded
	-- to the clients so they can show the result first.)
	if IS_MATCH then
		local players = Players:GetPlayers()
		local loadouts = MatchTeleport.encodeLoadouts(players, playerData)
		task.delay(MATCH_END_RETURN_DELAY, function()
			MatchTeleport.sendToLobby(players, loadouts)
		end)
		return
	end
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
	if matchmaking:getState(player) ~= "in_match" then
		return
	end
	if IS_MATCH then
		-- On a reserved match server, leaving the match = leave this server.
		-- leaveMatch updates state + runs the abandon check for the team left behind.
		matchmaking:leaveMatch(player)
		clearPickForPlayer(player)
		local loadouts = MatchTeleport.encodeLoadouts({ player }, playerData)
		MatchTeleport.sendToLobby({ player }, loadouts)
		return
	end
	matchmaking:leaveMatch(player)
	clearPickForPlayer(player)
	practiceService:onPlayerLeftPit(player) -- no-op unless they were in the Pit
	combatService:unregister(player)
	matchController:removePlayer(player)
	spawnInLobby(player)
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

	-- Reserved match server: this player was teleported in for a match. Read
	-- their team + loadout from join data and drop them straight into it.
	if IS_MATCH then
		handleMatchArrival(player)
		return
	end

	matchmaking:onPlayerJoined(player)
	-- Restore a loadout carried back from a finished match, if present, so runes
	-- bought before the match aren't lost on the round trip (no DataStore yet).
	local jd = player:GetJoinData()
	local td = jd and jd.TeleportData
	if td and td.returning and td.loadouts then
		local lo = td.loadouts[tostring(player.UserId)]
		local d = lo and playerData:get(player)
		if d then
			d.runes = lo.runes or {}
			d.summonerSpell = lo.summonerSpell or d.summonerSpell
			if lo.gold then
				d.gold = lo.gold
			end
		end
	end
	spawnInLobby(player)
	task.wait(0.2)
	playerData:replicate(player)
	matchmaking:sendLobbyTimerTo(player)
end

-- A failed teleport (caught asynchronously) leaves the player on THIS lobby
-- server — put them back in a clean lobby state instead of a limbo.
if IS_LOBBY then
	TeleportService.TeleportInitFailed:Connect(function(player, _result, errorMessage)
		warn("[Lobby] TeleportInitFailed for", player.Name, "-", errorMessage)
		matchmaking:_setPlayerState(player, "lobby", nil)
		spawnInLobby(player)
	end)
end

-- The lobby-timer tick loop only runs where matchmaking zones exist.
if RUN_LOBBY then
	matchmaking:startTimerLoop()
end

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
	practiceService:onPlayerLeftPit(player)
	matchmaking:onPlayerLeft(player)
	playerData:unregister(player)
	combatService:unregister(player)
	matchController:removePlayer(player)
	shopService:removePlayer(player)
	handledJoin[player.UserId] = nil
end)

-- Tell AbilityHandler how to look up matchmaking state so it can gate casts.
abilityHandler.isInMatch = function(player)
	return matchmaking:getState(player) == "in_match"
end

print(("[Server] BloxLegends ready — role: %s."):format(ROLE))
