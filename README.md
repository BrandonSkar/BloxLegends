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

## Layout

- `src/shared/` — data + remotes shared between server and client.
  - `Config.luau` — match constants (team count, kills-to-win, respawn time).
  - `Champions.luau` — champion roster and ability definitions.
  - `Remotes.luau` — RemoteEvents.
- `src/server/` — server-authoritative logic.
  - `init.server.luau` — entry point, wires services.
  - `ArenaBuilder.luau` — builds the lane + jungle + bases.
  - `MatchController.luau` — team assignment, score, win condition.
  - `ChampionService.luau` — champion stats per player (HP, level, cooldowns).
  - `AbilityService.luau` — validates and executes Q/W/E/D casts.
  - `ProjectileService.luau` — simulates skillshot projectiles + hit detection.
- `src/client/` — local player input + UI.
  - `init.client.luau` — entry point.
  - `CameraController.luau` — 3rd-person over-shoulder camera with mouse look.
  - `MovementController.luau` — WASD relative to camera, no jump.
  - `AbilityCaster.luau` — Q/W/E/D key handling, fires cast remotes.
  - `HUD.luau` — HP, ability cooldowns, score, crosshair.

## Controls

- `W` `A` `S` `D` — move (relative to camera direction)
- Mouse — look / aim
- `Q` — Fireball (skillshot projectile)
- `W` — Sprint (self speed buff)
- `E` — Meteor (ground-targeted AoE at crosshair)
- `D` — Heal (instant self heal, long cooldown)

## MVP status

Currently one champion (Pyromancer) with four abilities. Map is a placeholder
rectangle with two bases. No minions, no turrets, no jungle camps, no leveling
beyond stats yet — those are the next layers.
