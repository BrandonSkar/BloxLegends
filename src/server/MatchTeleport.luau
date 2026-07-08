local TeleportService = game:GetService("TeleportService")

-- =====================================================================
-- MatchTeleport — all TeleportService usage + the teleport-data wire format
-- live here, so the lobby and match servers agree on the payload shape.
--
-- Lobby → match:  reserve a private server, teleport the paired group into it
--                 carrying { teams, loadouts }.
-- Match → lobby:  teleport everyone to a public server of the same place (no
--                 reserved code) carrying { returning, loadouts } so the lobby
--                 can restore the player's runes / gold (there's no DataStore).
--
-- Teleport data is serialized as JSON, so table keys must be strings — we key
-- everything by tostring(UserId) and the receiver converts back with tonumber.
-- =====================================================================

local MatchTeleport = {}

local MAX_ATTEMPTS = 3
local RETRY_DELAY = 1.5

-- Snapshot each player's loadout into a string-keyed table for teleport data.
function MatchTeleport.encodeLoadouts(players, playerData)
	local out = {}
	for _, player in ipairs(players) do
		local d = playerData and playerData:get(player)
		if d then
			out[tostring(player.UserId)] = {
				runes = d.runes,
				summonerSpell = d.summonerSpell,
				gold = d.gold,
			}
		end
	end
	return out
end

-- pcall + retry around an async teleport. Returns ok, err.
local function attemptTeleport(placeId, players, options)
	local lastErr
	for attempt = 1, MAX_ATTEMPTS do
		local ok, err = pcall(function()
			TeleportService:TeleportAsync(placeId, players, options)
		end)
		if ok then
			return true
		end
		lastErr = err
		if attempt < MAX_ATTEMPTS then
			task.wait(RETRY_DELAY)
		end
	end
	return false, lastErr
end

-- Reserve a fresh private server and send the paired group there.
-- blueIds / redIds drive team assignment; players is the list of live Player
-- objects to actually teleport. Returns ok, err.
function MatchTeleport.sendGroupToMatch(blueIds, redIds, players, loadouts)
	local teams = {}
	for _, uid in ipairs(blueIds) do
		teams[tostring(uid)] = "Blue"
	end
	for _, uid in ipairs(redIds) do
		teams[tostring(uid)] = "Red"
	end

	local accessCode
	local ok, err = pcall(function()
		-- ReserveServer returns (accessCode, privateServerId); we only need the code.
		accessCode = TeleportService:ReserveServer(game.PlaceId)
	end)
	if not ok then
		return false, "ReserveServer failed: " .. tostring(err)
	end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = accessCode
	options:SetTeleportData({ teams = teams, loadouts = loadouts })
	return attemptTeleport(game.PlaceId, players, options)
end

-- Send players to a public server of the same place (the lobby). No reserved
-- access code → a normal matchmade public server. Returns ok, err.
function MatchTeleport.sendToLobby(players, loadouts)
	local options = Instance.new("TeleportOptions")
	options:SetTeleportData({ returning = true, loadouts = loadouts })
	return attemptTeleport(game.PlaceId, players, options)
end

return MatchTeleport
