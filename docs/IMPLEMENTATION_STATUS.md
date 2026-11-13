# Doodle Disaster: Implementation Status

Last verified: 2026-11-12, on `feature/full-game-mvp`.

Design reference: [GAME_DESIGN.md](GAME_DESIGN.md), updated to the finalized specification.

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

Ready for gameplay testing; earning, saving and reloading are verified (see multiplayer results).

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

Store separation (done): Studio sessions use `DoodleDisaster_PlayerData_Dev_v1`, production
uses `DoodleDisaster_PlayerData_v1`. `PlayerDataManager` is the only module that opens a
progression store and picks the name with `RunService:IsStudio()`. No records were migrated,
deleted or overwritten; the production store still holds the single record it had before.

Smaller limitations, acceptable for testing:

* No session locking. If two servers hold the same player at once, the later save is dropped
  by the guard, and `save` still reports success because `UpdateAsync` does not error.
* A failed load is not retried later in the session.
* No request-budget checks; fine at 8 players per server.
* Not yet exercised: buying or toggling a pack, and milestone unlocks.

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

## Multiplayer verification

Run with `StudioTestService:ExecuteMultiplayerTestAsync` (one local server plus N clients, all
driven through MCP). A test driver attached to each client submits distinct drawings and
guesses, casts votes including deliberate self-votes and duplicates, and logs every server
event. One client was driven by real mouse and keyboard input instead.

| Check | Result |
|---|---|
| Three players join the classroom, locked Scriptable camera, free movement in lobby | Pass |
| Countdown needs 3 ready players (dev mode off): cancels when one sits out, restarts when ready, never starts with 2 | Pass |
| Each player gets a different prompt | Pass |
| Rotation: every player contributes once to every sketchbook; guesser sees only the previous drawing, drawer only the previous guess | Pass (cross-checked from stroke colours and guess text per author) |
| Phases end early when everyone has submitted; timeouts insert placeholders and the book continues from the last real text | Pass |
| Shared reveal reaches all clients in order and completes | Pass |
| Anonymous ballot carries no author data; self-vote and duplicate vote rejected by the server | Pass |
| Results name the winners; ties share an award | Pass |
| Rewards: +20 for completing, +5 per award, none for a mostly idle player | Pass |
| Saved to the dev DataStore and reloaded after leaving and rejoining in a new session | Pass |
| Everyone returns to the lobby and a second match starts on the same server | Pass |
| Player leaves mid-match: announced, match continues, leaver gets no reward | Pass |
| Drawing UI with real mouse input: strokes land under the pointer, colour, brush size, Undo, Done | Pass |
| Guess UI with real keyboard input, Enter to submit | Pass |
| Ballot UI: own entry not clickable, valid vote accepted, moves to next category | Pass |
| Unit tests in a fresh server context | 65 passed, 0 failed |

Bugs found and fixed during these runs:

* The drawing and guess screens identified a task by step number only, so in a second
  match the guess screen kept the previous drawing and stayed locked as submitted. Tasks
  now carry `matchId`.
* When a match produced nothing to vote on, clients were never told and the results screen
  showed the previous match. The server now sends empty results.

Testing notes:

* Do not `require` server service modules from MCP `execute_luau`: it runs in a separate
  module cache, so `Net` is executed again and creates a second `Remotes` folder.
* For the same reason, unit tests run from edit mode can use stale cached modules. Run them
  from a playtest or test-session server.
* `{ devMode = false }` test args give the real three-player minimum in Studio.

## Open issues

1. A winner who left before results is shown as "A mysterious artist".
2. On a narrow window (about 800 px wide) the drawing tool buttons are only about 22 px tall.
3. Pack purchase, pack toggling and milestone unlocks have not been exercised.
4. Classroom interactions, touch input, gamepad and private-server host flow have not been exercised.
5. `rojo serve` and Studio must both be running; nothing checks this automatically.

## Feature status

| Area | Status |
|---|---|
| Lobby, countdown, minimum players, sit out | Verified in 3-player tests |
| Station assignment, seat lock, movement restore | Verified |
| Prompts, difficulty weights, no repeats | Verified by unit tests; prompts differ per player in play |
| Drawing (server validation, UI with mouse) | Verified |
| Guessing (limits, filtering call, UI with keyboard) | Verified; filter output cannot be meaningfully tested in Studio |
| Sketchbook rotation and placeholders | Verified (unit tests and play) |
| Shared reveal | Verified (events and overlay); projector screen not visually reviewed |
| Anonymous voting and results | Verified |
| Rewards and persistence | Verified against the dev DataStore |
| Second match on the same server | Verified |
| Mid-match disconnect | Verified |
| Late joiner spectating | Not exercised (a test session cannot add a client mid-run) |
| Pack unlock, toggle, milestones | Present, not exercised |
| Classroom interactions | Present, not exercised |
| Touch and gamepad input, private-server host flow | Present, not exercised |
| 4, 6 and 8 players | See multiplayer verification; rotation is unit-tested for 1 to 8 |
| Custom prompts, purchases | Disabled by design |
