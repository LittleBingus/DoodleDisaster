# Doodle Disaster: Development Handoff

Written 2026-11-13 from the repository and Studio state, not from memory of earlier chats.

## Repository state

* Branch `feature/full-game-mvp`. `main` untouched at `e351c1f`. `842c593` and earlier are on GitHub; later local commits (ProfileSaver fixes, docs, camera/toolbar fixes) are **not pushed**. Run `git status` and `git log origin/feature/full-game-mvp..HEAD` to see exactly what is unpushed.
* The owner sometimes commits from VS Code: check before editing.

## What exists (50 Luau files, ~7k lines)

Complete core loop for 3 to 8 players: lobby, ready/sit-out, 15 s public countdown or host start (private), station seating, alternating draw/guess with sketchbook rotation, shared reveal with majority skip vote, anonymous awards, rewards (+20 / +5 per award), saved progression (points, matches, awards, packs), three difficulties, four prompt packs (141 prompts), classroom interactions, locked camera.

Structure: `src/shared` (config, phases, rotation, drawing format, prompts, remotes), `src/server/Logic` (pure, unit-tested: MatchCore, VotingCore, PromptSelector, Rewards, RateLimiter, SkipVote, ProfileSaver), `src/server/Services` (RoundManager, GameState, LobbyManager, PlayerDataManager, ...), `src/client/Controllers`, `tests/`.

## Latest session (all in `842c593` except ProfileSaver follow-up)

* Timers: guess 15 s, vote 20 s, reveal 2 / 3 / 1.5 s; all in `GameConfig.Timers`.
* Reveal skip: `RevealSkipVote` remote, strict majority of connected participants, 1.2 s minimum read time, status broadcast `RevealSkipStatus`, two buttons in `RevealController`.
* Drawing UI: pixel-based three-layout toolbar in `DrawingController.pickLayout`.
* DataStore: `ProfileSaver` integrated into `PlayerDataManager` (retry-on-leave, dirty tracking, atomic rebase).
* Studio-only test args: `{ devMode = false }` (real 3-player minimum) and `{ privateServer = true }`. Both are gated by `RunService:IsStudio()`.

Verified vs not: see `IMPLEMENTATION_STATUS.md`, "Session 3". Short version: pacing, skip voting, host flow, sit-out, pack economy, persistence, disconnects, three consecutive matches and responsive layouts (by measurement) are verified; real-device touch, gamepad, late join, 6- and 8-player runs with new timers, live DataStore failure and all visual polish are not.

## Known bugs / gaps

1. Late joiner, real-device touch, gamepad, live DataStore outage, 8-player run with new timers: untested (manual).
2. Reveal skip buttons never viewed on screen.
3. Visual polish not started.
4. ProfileSaver residual: a landed-but-failed write plus a cross-server write in the same moments can double-apply one delta (rare).

## Cleanup before any publish

* Studio place is clean (verified). Dev DataStore test records are harmless (`DoodleDisaster_PlayerData_Dev_v1`, `DoodleDisaster_DevTest_v1`).
* Production store never written.
* Test drivers are temporary ModuleScripts created in `ReplicatedStorage` by MCP; recreate and delete per run.

## Resume here

1. Look at the reveal screen with skip buttons at phone and desktop sizes.
2. Manual tests the owner can do: late join (second Studio client), real phone, gamepad.
3. Optional: 8-player run with the 15 s / 20 s timers.
4. Then the visual polish pass (furniture, palette, lighting, projector, sounds, ambient animation, reveal camera framing). Blender needs go in a doc.

## Future idea (recorded in GAME_DESIGN.md, do not build yet)

"The Doodle Disaster Incident": a harmless, absurd Easter egg at 0.00001% per match. Server-authoritative roll; reduced-scares accessibility option; no strobing or intense flashes; moderate volume; must not interrupt active drawing; no gameplay advantage or exclusive reward.

## Rules in force

No push, merge to `main` or publish without the owner's approval. The owner may commit from VS Code, so check `git status` and `git log` before editing. Lua scripts are edited only in local files (Rojo owns the script folders). Test with `StudioTestService:ExecuteMultiplayerTestAsync(n, args)`; do not `require` server services from MCP `execute_luau` (it duplicates the `Remotes` folder); test clients have no `loadstring`, so attach drivers by `require`ing a ModuleScript. Use only the dev DataStore.

## Friends-only alpha configuration (2026-11-14)

* Published servers use `DoodleDisaster_PlayerData_Alpha_v1` (`GameConfig.DataStoreName`); Studio uses `..._Dev_v1`; `DoodleDisaster_PlayerData_v1` (production) is untouched and unused. For a real launch, set `GameConfig.DataStoreName = GameConfig.ProductionDataStoreName`.
* Experience visibility must stay `PRIVATE`. Voice chat, VR and server size 8 are set in Creator Hub / Game Settings by the owner (Open Cloud write scopes are not granted to MCP, and `Players.MaxPlayers` is read-only from scripts).
