# Doodle Disaster: Implementation Status

Last verified: 2026-11-12, at commit `e351c1f` (`main` and `feature/full-game-mvp` both point here).

Design reference: [GAME_DESIGN.md](GAME_DESIGN.md). That document predates the finalized
design; it has not yet been reconciled against it.

## Development environment

| Item | State |
|---|---|
| Git | `main` tracks `origin/main` (github.com/LittleBingus/DoodleDisaster) and is in sync; push auth works (dry run). Work branch `feature/full-game-mvp` is local only |
| Rojo | 7.7.0 via Rokit, `rojo serve` from the repo root, plugin 7.7.0 connected on `localhost:34872` |
| Rojo sync direction | One-way, disk to Studio (`twoWaySync` off) |
| Studio place | DoodleDisaster, placeId `136452236954845`, universe `10776256954`, Team Create on |
| Disk vs Studio | All 46 scripts byte-identical |
| Live sync | A temporary file added under `tests/` appeared in Studio within 2 s and disappeared when deleted |
| MCP: inspect | Game tree, instance properties and script sources readable |
| MCP: run Luau | Works in Edit, Server and Client data models |
| MCP: scene edits | Temporary Part created in and removed from `Workspace`; nothing left behind |
| MCP: Output | Readable in edit mode and during playtests |
| Logic tests | 64 passed, 0 failed (`require(game.ServerStorage.Tests.TestRunner)()`) |
| Playtest | Server boots, classroom builds, solo dev-mode match reaches Drawing |

The edit-mode place contains only `Baseplate`, `SpawnLocation`, `Terrain` and default
lighting objects in addition to the Rojo-managed scripts. The classroom is built at runtime by
`ClassroomBuilder`, so there is currently no hand-placed scene content to protect.

### Workflow rules

* Scripts are edited **only** in local files. Rojo owns these Studio paths, and anything
  changed or created there through Studio or MCP is overwritten or deleted on the next sync:
  * `ReplicatedStorage.Shared` (`src/shared`)
  * `ServerScriptService.Server` (`src/server`)
  * `ServerStorage.Tests` (`tests`)
  * `StarterPlayer.StarterPlayerScripts.Client` (`src/client`)
* Rojo also owns the `Workspace`, `Lighting` and `StarterPlayer` properties listed in
  `default.project.json`.
* MCP is used for everything else: scene construction (models, parts, lighting objects,
  `StarterGui` content and anything in `Workspace`, `ReplicatedStorage` or `ServerStorage`
  outside the folders above), object inspection, running Luau, running the test suite,
  reading Output, and playtests.
* MCP-built scene content lives only in the Studio place, not in Git. It is saved with the
  place (Team Create), so it is not covered by commits or code review.
* `servePlaceIds` pins Rojo to this place so it cannot sync into another open place.
  It is read when `rojo serve` starts, so the server must be restarted after changing it.
* No pushing to GitHub and no publishing the experience without explicit approval.

## Open issues

1. **DataStore blocked in Studio.** "Enable Studio Access to API Services" is off, so
   `PlayerDataManager` fails to load and falls back to a temporary, never-saved profile.
   Points, unlocks and persistence cannot be tested in Studio until it is enabled
   (Game Settings, Security).
2. **`MovementController` cannot find `PlayerModule`.** `PlayerScripts:WaitForChild("PlayerModule")`
   yields forever in playtests (`src/client/Controllers/MovementController.luau:20`), so the
   client-side control lock never engages. The server-side seat lock (WalkSpeed 0, seated)
   still works.
3. **Asset `rbxassetid://203785492`** fails to load ("Asset type does not match requested
   type"). It is logged before any game script runs; source not yet traced.

## Feature status

"Present" means the code exists and loads without errors. Only rows marked "Verified" have
been exercised.

| Area | Code | Status |
|---|---|---|
| Phase state machine, rotation, match logic, voting logic, prompt selection | `src/shared`, `src/server/Logic` | Verified by unit tests |
| Drawing validation | `DrawingTypes` | Verified by unit tests |
| Server boot, remotes | `GameManager`, `Net` | Verified in playtest (20 remotes created) |
| Procedural classroom | `ClassroomBuilder` | Verified in playtest (builds; not visually reviewed) |
| Lobby, dev-mode solo start | `LobbyManager` | Verified in playtest (solo match starts) |
| Desk assignment and seat lock | `StationManager` | Verified in playtest (server side) |
| Drawing phase and UI | `RoundManager`, `DrawingController` | Present; phase reached and prompt shown, drawing not exercised |
| Fixed camera | `CameraController` | Present; Scriptable camera active |
| Guessing, text filtering | `GuessController`, `TextFilter` | Present, not exercised |
| Reveal | `RevealController` | Present, not exercised |
| Award voting, results | `VotingManager`, `VotingController` | Present, not exercised |
| Rewards, persistence, pack unlocks | `RewardManager`, `PlayerDataManager` | Present, blocked by issue 1 |
| Classroom interactions | `ClassroomInteractionManager` | Present, not exercised |
| Multiplayer (3 to 8), private-server host flow, late join | | Not exercised |
| Touch and gamepad input | | Not exercised |
| Custom prompts, monetisation | `CustomPromptService` | Disabled by design |
