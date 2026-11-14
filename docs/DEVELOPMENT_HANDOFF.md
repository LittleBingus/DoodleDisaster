# Doodle Disaster: Development Handoff

Written 2026-11-13 from the repository and Studio state, not from memory of earlier chats.

## Repository state

* Branch `feature/full-game-mvp`; `main` untouched at `e351c1f`.
* HEAD `842c593` ("Faster pacing, majority reveal skip, responsive drawing UI, safer saves") is **already on `origin/feature/full-game-mvp`** (0 ahead, 0 behind; the owner pushed it).
* **Uncommitted, not pushed:** `src/server/Logic/ProfileSaver.luau` and `tests/specs/ProfileSaver.spec.luau` (write-id double-apply protection, pack-toggle rebasing, 4 new tests). They are synced to Studio and the 84-test suite passes with them. Review and commit them first.
* This handoff, the `IMPLEMENTATION_STATUS.md` update and the stale `GAME_DESIGN.md` are also uncommitted or pending.

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

1. Suspicious button off-screen during reveal on narrow windows.
2. Toolbar buttons 41-42 px at 705x338.
3. 15 s guess expiry unverified; reveal skip buttons never viewed.
4. `GAME_DESIGN.md` out of date (see below).

## Cleanup before any publish

* Delete `ReplicatedStorage.__McpTestDriver` (Studio edit place, not in Git).
* End the leftover 6-client test session (call `StudioTestService:EndTest(...)` from the test server, or close the extra Studio windows).
* Dev DataStore test records (`DoodleDisaster_PlayerData_Dev_v1`, `DoodleDisaster_DevTest_v1`) are harmless but can be cleared from a playtest server.
* Production store was never written.

## Resume here

1. `git status`; review and commit the two ProfileSaver files locally.
2. Update `docs/GAME_DESIGN.md`: Guessing 15 s, Voting 20 s, reveal timings, reveal-skip section, test args, and the future idea below.
3. Finish testing: 6-player and 8-player matches with the new timers and skip; guess-timer expiry; late joiner (needs a manual second Studio client); simulate a failing `UpdateAsync` to watch the leave-save retry.
4. Look at the reveal screen with skip buttons at phone and desktop sizes.
5. Fix the off-screen suspicious button; nudge the toolbar at 705x338.
6. Only then begin the visual polish pass (list in the owner's brief: furniture, palette, lighting, projector, sounds, ambient animation, reveal camera). Blender needs go in a doc, not procedural approximations.

## Future idea (record in GAME_DESIGN.md, do not build yet)

"The Doodle Disaster Incident": a harmless, absurd Easter egg at 0.00001% per match. Server-authoritative roll; reduced-scares accessibility option; no strobing or intense flashes; moderate volume; must not interrupt active drawing; no gameplay advantage or exclusive reward.

## Rules in force

No push, merge to `main` or publish without the owner's approval. The owner may commit from VS Code, so check `git status` and `git log` before editing. Lua scripts are edited only in local files (Rojo owns the script folders). Test with `StudioTestService:ExecuteMultiplayerTestAsync(n, args)`; do not `require` server services from MCP `execute_luau` (it duplicates the `Remotes` folder); test clients have no `loadstring`, so attach drivers by `require`ing a ModuleScript. Use only the dev DataStore.
