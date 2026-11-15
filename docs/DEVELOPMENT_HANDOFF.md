# Doodle Disaster: Development Handoff

Updated 2026-11-15 from the repository and Studio state.

## Status: private alpha played; alpha-feedback build implemented, not yet republished

* Branch `feature/full-game-mvp`. The owner committed and pushed the feedback work as `0edc7c5`; later local commits may follow (check `git log origin/feature/full-game-mvp..HEAD`). `main` untouched.
* The experience is published and `PRIVATE` (8 players per server, voice and VR off). **The published build predates this session**: mode voting, the 25 s guess timer, the guess fallback, Hide / Report and rejoin are only in Studio and Git until the owner republishes.
* The owner sometimes commits from VS Code and restarts Studio: run `git status`, `git log` and re-list Studio instances before editing.

## What changed this session (details in `IMPLEMENTATION_STATUS.md`, Session 5)

1. **Mode vote** replaces the host's difficulty button (`ModeVote`, `LobbyManager`, `VoteDifficulty`).
2. **Announcement** on the projector during StartingMatch, with sound and tint (`RevealController`).
3. **Guess timer 25 s** (`GameConfig.Timers.Guessing`).
4. **Censored-guess fallback** (`GuessFallback`, `GameConfig.Guess.FallbackPhrases`, `RoundManager`).
5. **Hide / Report drawings** (`DrawingGuard` client, `ModerationManager` + `ReportLog` server, report DataStore).
6. **Rejoin**: a participant returning to the same server resumes at the current page (`MatchCore.markReturned`, `StationManager.restore`).
7. Lobby panel no longer overlaps the reaction bar on narrow screens.

Tests: 110 unit tests pass; 3-player (3 matches, including a mid-match kick) and 5-player sessions pass.

## Public-beta blockers

1. **Republish and re-test on a live server.** None of the new features has run outside Studio. In particular the real text filter (expect a replacement phrase for a fully censored guess), a real rejoin, a late joiner and a real phone.
2. **Roblox questionnaire: free-form user creation.** Drawings that other players see must be declared in the Content Maturity questionnaire (Creator Hub > experience > Audience). Roblox's Creator docs currently say such experiences are only available to players aged 16 and over (the 2024 announcement said 13). Confirm the current wording before going public; this limits the audience and is not something code can change.
3. **Report review is manual.** Reports are saved to `DoodleDisaster_Reports_Alpha_v1` but there is no tool or routine for reading them, and nothing acts on repeat offenders. Before a broad launch someone has to look at them (Studio command bar, or Open Cloud DataStore API). The store contains user ids, so it falls under Roblox's data-deletion requests.
4. **DataStore choice.** Published servers still write to the alpha store. Decide whether beta players keep alpha progress (stay on it) or start on `ProductionDataStoreName` (one line in `GameConfig`).

Known limits that do not block a limited beta: Hide is per drawing and per session; a reported artist is only hidden from the reporter; a drawing is seen once before it can be hidden; rejoining only works if Roblox puts the player back on the same server; leavers' pages are placeholders (no Substitute Doodler); no quitting penalties; ProfileSaver's rare cross-server double-apply; visual polish not started; gamepad untested.

## Next session: in order

1. Sync check (Git, Rojo, Studio scripts, experience settings).
2. With the owner's approval, publish privately and run the live checklist below with 3 or more friends.
3. Fill in the questionnaire item for free-form user creation and read the resulting age restriction.
4. Decide the DataStore for the beta.
5. Only then consider a limited public beta.

## Live checklist (private server, 3+ players, one on a phone)

1. Everyone votes for a mode; change a vote; one player sits out and tries to vote.
2. The projector announces the winning mode; the sound is audible but not loud.
3. A guess of plain profanity becomes a random phrase and the next player draws it; a normal guess passes.
4. Hide a drawing on the guess screen, in the reveal and in voting; it stays hidden in results.
5. Report a drawing (two taps); that artist's later drawings show as hidden for the reporter only.
6. One player leaves mid-match and rejoins through a friend; they get their desk and page back. Leave again and stay away; the match finishes with two.
7. A late joiner spectates and plays the next match.
8. 25 s guessing: too long, too short?
9. Play three matches in a row; points and packs persist after rejoining.

## Rules in force

No push, merge to `main`, publish, visibility or permission change without the owner's approval. No monetization. Lua scripts are edited only in local files (Rojo owns the script folders). Studio uses only dev DataStores (`..._PlayerData_Dev_v1`, `..._Reports_Dev_v1`); the production store is never written. Test with `StudioTestService:ExecuteMultiplayerTestAsync(n, args)`; Studio-only test args: `devMode = false`, `privateServer = true`, `simulateFilter = true` (the word "censorme" is censored). Do not `require` server services from MCP `execute_luau`. Test drivers are temporary ModuleScripts in `ReplicatedStorage`; delete every `__Mcp*` object after each run.

## Cleanup

Studio place is clean (no `__Mcp*` objects). Dev stores hold harmless test data, including three test reports in `DoodleDisaster_Reports_Dev_v1`.

## Postponed (see GAME_DESIGN.md)

Substitute Doodler bot, repeated-quitting cooldowns, moderation review tooling, "The Doodle Disaster Incident" Easter egg, visual polish, custom prompts and all monetization.
