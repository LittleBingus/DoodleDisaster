# Doodle Disaster: Implementation Status

Last reviewed: 2026-11-13, on `feature/full-game-mvp` (see [DEVELOPMENT_HANDOFF.md](DEVELOPMENT_HANDOFF.md)). Sections below dated earlier than the "Session 3" section may describe
older behaviour (30 s guessing, 30 s voting, no reveal skip, `PlayerDataManager.save` as it was).

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

* (Superseded by `ProfileSaver`, see Session 3.) Earlier versions dropped a stale save while
  reporting success.
* A failed load is not retried later in the session.
* No request-budget checks; fine at 8 players per server.

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
| 4 players: 4 steps, every sketchbook ends on a guess, rewards paid | Pass |
| 8 players: 8 sketchbooks of 8 entries, every book ends on a guess, ballot capped at 8 candidates per category, rewards paid | Pass |
| Classroom interactions (chalkboard, paper toss, suspicious button, golden pencil) | Pass |
| Unit tests in a fresh server context | 65 passed, 0 failed |

Bugs found and fixed during these runs:

* The drawing and guess screens identified a task by step number only, so in a second
  match the guess screen kept the previous drawing and stayed locked as submitted. Tasks
  now carry `matchId`.
* When a match produced nothing to vote on, clients were never told and the results screen
  showed the previous match. The server now sends empty results.
* A winner who left before results was shown as "A mysterious artist"; names are now
  remembered for the session (fix not yet re-tested with a leaver).

Testing notes:

* Do not `require` server service modules from MCP `execute_luau`: it runs in a separate
  module cache, so `Net` is executed again and creates a second `Remotes` folder.
* For the same reason, unit tests run from edit mode can use stale cached modules. Run them
  from a playtest or test-session server.
* `{ devMode = false }` test args give the real three-player minimum in Studio.

## Session 3: pacing, reveal skip, responsive UI, safer saves

Timers now: Drawing 60 s, Guessing 15 s, Voting 20 s, reveal intro 2 s / entry 3 s / outro 1.5 s
(`GameConfig.Timers`, minimum read time for skips `RevealMinRead` 1.2 s).

| Area | Status |
|---|---|
| Timers as above, early advance when all submit (phases end about 3 s after the last submission) | Verified in 3, 4 and private 4-player runs |
| Expiry of the 15 s guess timer with no submission | Verified in Session 4 |
| Reveal skip: one vote does not advance, duplicate votes ignored, spectator votes ignored, strict majority advances, threshold shrinks when a player leaves (needed 3 -> 2), skip status reaches all clients | Verified (4 players). Whole-book skip verified with 3 players |
| Reveal skip buttons on screen | Built; never looked at in a screenshot |
| Drawing toolbar: side / landscape-phone / portrait layouts | Verified by measurement at 1365x768, 750x381 and 401x778 (all buttons 44 px+, no overlap, no off-screen). At 705x338 (Galaxy A06) 8 buttons were 41-42 px; fixed in Session 4 |
| Touch drawing and Undo | Verified only through Studio touch emulation, not on a device |
| Private-server host flow (via test arg `{ privateServer = true }`): non-host start and difficulty rejected, host start gives a 5 s countdown, difficulty change broadcast | Verified |
| Sit-out player: no task, no reward, spectator banner, ballot with `canVote=false`, joins next match when ready again | Verified |
| Packs: buy (60 deducted from 110), repeat, insufficient points, free pack and unknown id all rejected with a message; toggle works; non-owned and free-pack toggles ignored; enabled pack appears in the match pool list | Verified. Prompts actually drawn from a non-free pack were not inspected |
| Milestone unlock at 8 matches | Seen once (notice fired at matches=8) |
| Unlocks and points persist across test sessions | Verified |
| Departed award winner credited by name; vote for a leaver's entries counted | Verified |
| Three consecutive matches on one server | Verified |
| Concurrent external write (+1000 points and a pack added to a stored record mid-session) | Merged, nothing lost (see note) |
| Unit tests | 84 passed, 0 failed (includes uncommitted ProfileSaver tests) |

`ProfileSaver` (`src/server/Logic/ProfileSaver.luau`): one write per player at a time; profile stays
dirty until a write containing its latest revision succeeds; a newer stored record is rebased onto
inside `UpdateAsync` (deltas for points, matches, awards; unlock union; pack toggles only where this
session changed them); each write carries a `writeId` so a write that landed but reported an error is
not applied twice on retry. Failed or untracked (failed-load) profiles are never written.
Verified by unit tests with a fake store, and live only for the external-write case above. Real
DataStore outages, throttling and a failing save on leave or shutdown have **not** been exercised live.

## Session 4: verification and fixes

| Area | Result |
|---|---|
| ProfileSaver review | Duplicate-write protection (writeId) and numeric/unlock merging correct. **Bug found and fixed:** after a merged save the live profile kept stale pack toggles, so the next rebase could switch a pack back on; the profile now adopts stored toggles unless changed mid-write. 6 new tests |
| Unit tests (fresh playtest server) | 86 passed, 0 failed |
| 6-player match (public, `devMode=false`) | Pass: 6 books x 6 entries, each book has every author exactly once, alternating draw/guess, ends on a guess, 5 of 6 votes where the winner cannot vote for self, rewards paid |
| Guess timeout with the 15 s timer | Pass: a player who never guessed got a placeholder; the step ended at about 17 s (15 s + 2 s `SubmissionGrace`) |
| Early advance when all submit | Pass (drawing steps ended 4-6 s after start) |
| Reveal camera | Fixed. The old reveal shot hid the suspicious button and trash can at **every** window size, and portrait hid them even outside the reveal. New framing plus a distance scale for narrow aspect ratios; verified by projection maths for 6 viewports and on a live client (all five props on screen during a reveal at 800x751) |
| Toolbar at 705x338 | Fixed: all 21 buttons 44 px or more, no overlap, canvas 273x204 |
| Production DataStore | Never written (1 key before and after) |
| Temp objects | `__McpTestDriver` removed (twice, after each run), no `__Mcp*`/`__ddlog` instances, no workspace attributes, device simulator reset, no test clients running |

Residual ProfileSaver limit: if a write lands but its call errors, and *another* server writes the same
record before our retry, our retry can add this session's delta on top of data that already contains it.
It needs a store timeout plus a cross-server write in the same few seconds; the common single-server
timeout case is handled and tested.

## Cleanup status

* Studio place: clean.
* Dev store `DoodleDisaster_PlayerData_Dev_v1` still holds `player_-1` to `player_-6` (test profiles, points inflated by tests). `DoodleDisaster_DevTest_v1` holds `xsession_e43234e8-bdc4-4746`. Dev only; delete or ignore.

## Open issues

1. Not tested: late joiner (a test session cannot add a client mid-run), real-device touch, gamepad, a real DataStore outage, 8-player run with the new timers.
2. Reveal skip buttons never viewed in a screenshot.
3. Visual polish not started (furniture, palette, lighting, projector, sounds, ambient animation).
4. A 4-client test session once started with 3; relaunching worked. `rojo serve` and Studio must both be running.

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
| Late joiner spectating | Not exercised (sit-out spectating verified instead) |
| 6 players | Verified (Session 4) |
| Pack unlock, toggle, milestones | Verified (see Session 3) |
| Classroom interactions | Verified |
| Touch (emulated), private-server host flow | Verified in Studio; real devices and gamepad untested |
| 3, 4, 6 and 8 players | Verified in play (8 with the old timers); rotation unit-tested for 1 to 8 |
| Custom prompts, purchases | Disabled by design |
