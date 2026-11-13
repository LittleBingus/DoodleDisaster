# Doodle Disaster: Implementation Status

Last verified: 2026-11-12, on `feature/full-game-mvp` at commit `a8911f4` plus the
`MovementController` fix described below.

Design reference: [GAME_DESIGN.md](GAME_DESIGN.md). That document predates the finalized
design; it has not yet been reconciled against it.

## Development environment

| Item | State |
|---|---|
| Git | `main` tracks `origin/main` (github.com/LittleBingus/DoodleDisaster) and is in sync; push auth works (dry run). Work branch `feature/full-game-mvp` is local only |
| Rojo | 7.7.0 via Rokit, `rojo serve` from the repo root, plugin 7.7.0 connected on `localhost:34872` |
| Rojo place pin | Active: server restarted and reports `expectedPlaceIds = [136452236954845]`; an edit made after the restart synced and all 46 scripts match |
| Rojo sync direction | One-way, disk to Studio (`twoWaySync` off) |
| Studio place | DoodleDisaster, placeId `136452236954845`, universe `10776256954`, Team Create on |
| Disk vs Studio | All 46 scripts byte-identical |
| Live sync | A temporary file added under `tests/` appeared in Studio within 2 s and disappeared when deleted |
| MCP: inspect | Game tree, instance properties and script sources readable |
| MCP: run Luau | Works in Edit, Server and Client data models |
| MCP: scene edits | Temporary Part created in and removed from `Workspace`; nothing left behind |
| MCP: Output | Readable in edit mode and during playtests |
| Logic tests | 64 passed, 0 failed (`require(game.ServerStorage.Tests.TestRunner)()`) |
| Playtest | Server boots, classroom builds, solo dev-mode match reaches Drawing, Output clean |
| DataStore | Studio API access enabled; write, read and update verified (see below) |

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

## DataStore verification

Run from a playtest server through MCP against the development-only store
`DoodleDisaster_DevTest_v1`, using unique throwaway keys. `DoodleDisaster_PlayerData_v1` was
never written to.

| Step | Result |
|---|---|
| Read of a new key returns nil | Pass |
| Write (`SetAsync`) of a profile-shaped record | Pass |
| Read back, cache bypassed | Pass |
| Read from a different session (edit mode) of a record written by the playtest server | Pass |
| Update (`UpdateAsync`) with the same `saveCount` guard `PlayerDataManager` uses | Pass |
| Stale update (equal `saveCount`) rejected by the guard | Pass |
| Cleanup (`RemoveAsync`), uncached read returns nil | Pass |

Notes:

* Edit-mode code can read DataStores but writes are refused ("Access forbidden"), so
  DataStore write tests must run in a playtest server.
* `ListKeysAsync` still listed the removed key immediately after deletion, with a nil value.
  The dev store holds no data.
* Key names are limited to 50 characters.

## PlayerDataManager assessment

Ready for gameplay testing, with one caveat that should be settled first.

What is sound:

* Load uses `GetAsync` with 3 retries. On failure the session gets a temporary profile that
  is never saved, so stored data cannot be overwritten with defaults.
* Saves use `UpdateAsync` with a `saveCount` guard; the same guard passed the stale-write
  test above.
* Nothing is written unless the profile is dirty (a reward grant, a pack unlock or a pack
  toggle). Joining and leaving without those only reads.
* Saves happen on grant and unlock, on leave, every 120 s and in `BindToClose`.
* Rewards are computed server-side and granted once per `matchId:userId`.
* With Studio API access on, the load now succeeds: no `[PlayerData]` warnings in Output.

Caveat:

* **Studio and live servers share `DoodleDisaster_PlayerData_v1`**, which already contains
  one record. A dev-mode solo match that is actually played to Results grants +20 points to
  the tester's real record, and pack unlocks or toggles in Studio are saved too. Using a
  separate store name when `RunService:IsStudio()` is true would keep test runs out of real
  progression. Not changed yet; needs a decision.

Smaller limitations, acceptable for testing:

* No session locking. If two servers hold the same player at once, the later save is dropped
  by the guard, and `save` still reports success because `UpdateAsync` does not error.
* A failed load is not retried later in the session.
* No request-budget checks; fine at 8 players per server.
* Not yet exercised end to end: a real grant, unlock and reload cycle (blocked on the caveat).

## Resolved issues

1. **DataStore blocked in Studio.** Studio API access is now enabled and verified.
2. **`MovementController` could not find `PlayerModule`.** Roblox now ships the default
   control scripts at `StarterPlayer.PlayerModule` instead of cloning them into
   `PlayerScripts`, and replaced `GetControls():Enable()/Disable()` with a
   `ControlModule.Enabled` flag. `MovementController` waited forever on the old location.
   It now looks in both places without yielding and supports both APIs. Verified in a
   playtest: holding W moves the character in the lobby (21 studs), produces zero move
   input once seated, and the "Infinite yield possible" warnings are gone.
3. **Asset `rbxassetid://203785492` fails to load.** Not a game issue. It is the Rojo
   plugin's own notification sound (`Sounds.Notification` in `RojoManagedPlugin.rbxm`, an
   audio asset named "Pop Close Sound"). Nothing in the place or repo references it. The
   message is harmless and will keep appearing while the plugin is installed.

## Open issues

1. **Finalized design not yet received.** `GAME_DESIGN.md` still describes the game as
   implemented; the feature table below cannot be measured against the final design.
2. **Shared DataStore between Studio and live** (see the assessment above).

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
| Desk assignment and seat lock | `StationManager`, `MovementController` | Verified in playtest (server lock and client control lock) |
| Drawing phase and UI | `RoundManager`, `DrawingController` | Present; phase reached and prompt shown, drawing not exercised |
| Fixed camera | `CameraController` | Present; Scriptable camera active |
| Guessing, text filtering | `GuessController`, `TextFilter` | Present, not exercised |
| Reveal | `RevealController` | Present, not exercised |
| Award voting, results | `VotingManager`, `VotingController` | Present, not exercised |
| Rewards, persistence, pack unlocks | `RewardManager`, `PlayerDataManager` | Profile load verified; grant, unlock and save not exercised (see assessment) |
| Classroom interactions | `ClassroomInteractionManager` | Present, not exercised |
| Multiplayer (3 to 8), private-server host flow, late join | | Not exercised |
| Touch and gamepad input | | Not exercised |
| Custom prompts, monetisation | `CustomPromptService` | Disabled by design |
