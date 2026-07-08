local RunService = game:GetService("RunService")

-- =====================================================================
-- Server role — single source of truth for "what is this server for".
--
-- One PLACE runs in three roles depending on how the server was spun up:
--
--   "local" — Studio. TeleportService can't run here, so we keep the old
--             all-in-one behavior: lobby + matchmaking + a locally-run match
--             in the same server. This is what the two-player Studio test uses.
--
--   "lobby" — a normal published public server. Hosts the lobby + matchmaking
--             and, when a group is paired, RESERVES a private server and
--             teleports the group into it (see MatchTeleport). Runs no combat.
--
--   "match" — a reserved (private, owner-less) server. Builds the arena, runs
--             exactly one match, then teleports everyone back to the lobby.
--
-- A reserved server has a non-empty PrivateServerId AND PrivateServerOwnerId
-- of 0 (a player-owned VIP server has a non-zero owner id, so it falls through
-- to "lobby" and behaves like a normal public server).
-- =====================================================================

local ServerRole = {}

function ServerRole.get()
	if RunService:IsStudio() then
		return "local"
	end
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
		return "match"
	end
	return "lobby"
end

return ServerRole
