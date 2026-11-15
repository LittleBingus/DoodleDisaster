# Doodle Disaster: Development Handoff

Written 2026-11-13 from the repository and Studio state, not from memory of earlier chats.

## Status at end of session (2026-11-14): ready for a private friends-only alpha, not yet published

* Branch `feature/full-game-mvp`, latest commit `66bcfe7` ("Use a separate alpha DataStore for published servers"). It is on GitHub (`origin/feature/full-game-mvp`), local tree clean. `main` untouched.
* Place saved to Roblox (Team Create version 26). **Not published.** Experience visibility is `PRIVATE`.
* The owner sometimes commits from VS Code: run `git status` and `git log` before editing.

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

## Alpha preparation

**DataStores (no records modified).** Published servers use `DoodleDisaster_PlayerData_Alpha_v1` (`GameConfig.DataStoreName` = `AlphaDataStoreName`). Studio uses `..._Dev_v1`. The production store `DoodleDisaster_PlayerData_v1` (holds one record, `player_77159458`, the owner's) is untouched and unused. For a real launch, set `GameConfig.DataStoreName = GameConfig.ProductionDataStoreName`.

**Verified (final run, d2bf525 + alpha store change).** Git, Rojo and Studio in sync (50 scripts, matching checksums); 86 unit tests pass in a fresh test server; Output clean except the Rojo plugin's own asset warning; no temporary MCP objects in the place; no monetization code is active (no `ProcessReceipt`, no product ID); reveal skip buttons seen on screen and a real click registers a vote without advancing alone; 3, 4, 6 and 8 player matches, timeouts, disconnects, host controls, sit-out, packs and persistence verified earlier (see `IMPLEMENTATION_STATUS.md`).

**Experience settings read from Roblox (read-only):** visibility `PRIVATE`; age rating 13+; desktop, mobile and tablet on; console off; voice chat **on**; VR **on**; place server size **50**. MCP has no Open Cloud write scopes and `Players.MaxPlayers` is read-only from scripts, so these must be changed by the owner.

**Needs real-world testing (cannot be done in Studio):** Roblox text filtering of guesses on a published server (profanity becomes `####`, normal text passes); late joiner; touch on a real phone; gamepad; a failing DataStore save in a live server. Drawings are not filtered (normal for drawing games, a moderation question before any public release).

## Next session: do these in order

1. Confirm Git and Rojo are synchronized (`git status`, `git log origin/feature/full-game-mvp..HEAD`, Rojo plugin connected, script checksums match Studio).
2. Set maximum server capacity to 8 (Studio Game Settings, or Creator Hub; or grant the MCP `universe.place:write` scope and have it set `serverSize`).
3. Disable voice chat and VR (Game Settings, or grant `universe:write`).
4. Verify the private experience settings by reading them back (visibility must be `PRIVATE`; voice chat, VR off; server size 8).
5. Publish the latest build privately, **only with the owner's explicit approval** (Studio: File > Publish to Roblox).
6. Invite 3 to 6 friends with the lowest permission that lets them play, preferably an early-testing or invite mechanism, never edit access. Do not make the experience public. Then run the playtest checklist below.

## Playtest checklist

1. Everyone joins; the lobby lists all players.
2. Players ready up (3 needed); the 15 s countdown runs.
3. Draw (60 s) and guess (15 s); books rotate; a timeout gives a placeholder.
4. Use reveal skip; check the vote counter.
5. Vote; check results and points.
6. Try a profanity guess (expect `####`) and one late join; include a phone player if possible.
7. Leave and rejoin; points and packs persist.
8. Play a second match without restarting the server.

## Cleanup

* Studio place is clean. Test drivers are temporary ModuleScripts MCP creates in `ReplicatedStorage` per run; delete after each run.
* Dev DataStore records (`DoodleDisaster_PlayerData_Dev_v1`, `DoodleDisaster_DevTest_v1`) are harmless test data.

## Future idea (recorded in GAME_DESIGN.md, do not build yet)

"The Doodle Disaster Incident": a harmless, absurd Easter egg at 0.00001% per match. Server-authoritative roll; reduced-scares accessibility option; no strobing or intense flashes; moderate volume; must not interrupt active drawing; no gameplay advantage or exclusive reward.

## Rules in force

No push, merge to `main` or publish without the owner's approval. The owner may commit from VS Code, so check `git status` and `git log` before editing. Lua scripts are edited only in local files (Rojo owns the script folders). Test with `StudioTestService:ExecuteMultiplayerTestAsync(n, args)`; do not `require` server services from MCP `execute_luau` (it duplicates the `Remotes` folder); test clients have no `loadstring`, so attach drivers by `require`ing a ModuleScript. Use only the dev DataStore.
