# Blox Legends

3v3 third-person MOBA in Roblox. Single lane + jungle, skillshot-heavy combat,
WASD movement relative to camera (Smite-style), no jumping.

## Quickstart

1. Install [Aftman](https://github.com/LPGhatguy/aftman) and the
   [Rojo VS Code plugin](https://rojo.space/docs/v7/getting-started/installation/).
2. From this folder:
   ```
   aftman install
   rojo serve
   ```
3. Open Roblox Studio, install the Rojo plugin, and connect to the local server.
4. Hit Play. The arena builds itself on first run.

## Server roles (concurrent matches)

One place runs in three roles (`src/shared/ServerRole.luau`):

- **local** — Studio. All-in-one: lobby + matchmaking + the match in one
  server. This is what Studio multi-client testing uses.
- **lobby** — a published public server. Hosts the lobby, matchmaking zones,
  and the practice room. When a group is paired it **reserves a private
  server** and teleports the group into it — so any number of matches run
  concurrently, each on its own server.
- **match** — a reserved server. Runs exactly one match, then teleports
  everyone back to a public lobby server.

Player loadouts (runes, summoner spell, lobby gold) ride along in teleport
data (`MatchTeleport.luau`) — there's no DataStore yet, so they survive the
round trip but not a rejoin. Reserved-server flow can only be tested on a
**published** place; Studio always uses the local role.

## Game systems

- **Champions** — 6 champions across 3 classes (Attack / Support / Tank),
  each with Q/E/R abilities, an F utility, Shift dash, and a summoner heal.
  Class drives auto-attack feel (ranged vs melee, wind-up, interval).
  Champion select enforces per-team uniqueness. *(Kits are placeholder —
  per-champion redesign is planned.)*
- **Leveling** — champions earn XP from nearby minion deaths, takedowns,
  towers, and jungle camps. Levels scale max HP and damage
  (`Config.Leveling`). Level shows on the HUD badge and nameplates.
- **Kill rewards** — kill + assist gold, first blood, shutdown bounties on
  killing sprees, multikill announcements (Double → Penta), kill feed, and a
  team-kill score bar with the match clock.
- **Economy** — passive team gold + last-hit bonuses from minions, tower
  team gold, and an in-base item shop (`Items.luau`): class-gated components
  that combine into completed items, League-style recipe discounts.
- **Minions** — 3 waves types (melee/ranged/cannon) with lock-on aggro,
  lane clamping, and separation. Waves scale HP/damage over the match.
- **Towers** — tier-cascade invulnerability (T2 immune until T1 falls),
  backdoor protection, champion aggro on ally harassment, nexus win.
- **Jungle** — 4 buff camps (STORM: move+attack speed north, MIGHT:
  AD+AP south) and **the Overlord** boss in the pit: team-wide gold, XP,
  and a 90s buff. Camps leash, reset, and respawn.
- **Death timers** — scale with match time (6s early → 24s late) with a
  death screen countdown.
- **Recall** — 8s channel back to base; cancelled by damage/movement/casts.
  Base zone regenerates HP and gates the shop.
- **Practice room** — available from the lobby (also on published lobby
  servers): respawning target dummy, 10k gold to test item builds, recall
  returns you to the practice spawn.
- **HUD** — HP/shield/XP bars, ability cooldowns, kill feed, center
  announcements, team score + match timer, minimap (champions, minions,
  towers, jungle), Tab scoreboard (K/D/A, CS, gold), death overlay, and a
  built-in sound layer (rbxasset sounds only — nothing to upload).

## Controls

- `W` `A` `S` `D` — move (relative to camera) · mouse / touch-drag — look
- Click / tap — target (smart-target fallback in AA range)
- `Q` `E` `R` `F` — abilities (drag the HUD slot to aim skillshots)
- `Shift` — dash · `Space` — summoner heal
- `B` — recall · `P` — shop (in base) · `Tab` — scoreboard (tap the score
  bar on touch)

## Publishing checklist

1. Publish the place to Roblox (File → Publish). Reserved-server teleports
   only work on published places.
2. In Game Settings → Security, enable **"Allow Third Party Teleports"** is
   NOT required (same-place teleports), but **API Services** should be on if
   you later add DataStores.
3. `Config.Matchmaking` — zone pairing already supports 1v1 up to 3v3 via
   `MATCH_PATTERNS`; the 2-minute lobby timer auto-pairs zone groups FIFO.
   "Start Match Now" starts a match early only when a legal pairing exists.
4. Test with 2+ clients: lobby server should print `role: lobby`, and paired
   groups should teleport to a fresh server printing `role: match`.

## Layout

- `src/shared/` — data + remotes shared between server and client
  (`Config`, `Champions`, `Items`, `Runes`, `Remotes`, `ServerRole`).
- `src/server/` — server-authoritative logic. Entry: `init.server.luau`.
  Combat (`CombatService`), abilities (`AbilityHandler`), minions + waves
  (`MinionService`), towers (`TowerService`), jungle + boss
  (`JungleService`), score/kills/XP (`ScoreService`), shop (`ShopService`),
  recall (`RecallService`), matchmaking (`MatchmakingService`), reserved
  server teleports (`MatchTeleport`), builders (`ArenaBuilder`,
  `LobbyBuilder`, `PracticeBuilder`).
- `src/client/` — input + UI. Entry: `init.client.luau`. Camera, movement,
  ability casting with drag-aim, targeting, HUD, scoreboard, minimap,
  kill-feed/announcements, shop UI, champion select, lobby UI, sounds.

## Dev verification

```sh
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap sourcemap.json --definitions globalTypes.d.luau src
rojo build default.project.json -o /tmp/build-check.rbxlx
```

(`luau-lsp` from GitHub releases; `globalTypes.d.luau` from the luau-lsp
repo's `scripts/` folder.)
