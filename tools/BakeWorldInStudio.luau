--!nocheck
-- ===========================================================================
-- BakeWorldInStudio.luau
-- Paste into Studio's Command Bar (View → Command Bar) in EDIT mode while the
-- Rojo plugin is CONNECTED (so ReplicatedStorage.Shared + ServerScriptService
-- .Server exist). Generates the Arena, Lobby, and PracticeRoom as real,
-- editable Instances in the Workspace hierarchy, then prints a reminder to
-- save. After saving/publishing, the runtime builders find these folders and
-- use them verbatim instead of generating geometry from script — so you can
-- reshape the world by hand in Studio from then on.
--
-- To re-bake from scratch, delete the folder(s) you want regenerated
-- (Workspace.Arena / Workspace.Lobby / Workspace.PracticeRoom) and run again.
--
-- If you'd rather not depend on Rojo being connected, the older standalone
-- tools/BuildArenaInStudio.luau still works for the arena alone.
-- ===========================================================================

local server = game:GetService("ServerScriptService"):FindFirstChild("Server")
assert(server, "ServerScriptService.Server not found — connect the Rojo plugin first, then re-run.")

local built = {}
for _, name in ipairs({ "ArenaBuilder", "LobbyBuilder", "PracticeBuilder" }) do
	local module = server:FindFirstChild(name)
	assert(module, name .. " not found under ServerScriptService.Server — is Rojo synced?")
	require(module).build()
	table.insert(built, name)
end

print("[BakeWorldInStudio] Built via: " .. table.concat(built, ", "))
print("[BakeWorldInStudio] Workspace now has Arena / Lobby / PracticeRoom as editable objects.")
print("[BakeWorldInStudio] SAVE (and publish) the place to bake them in — the runtime will use them as-is.")
