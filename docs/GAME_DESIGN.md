# Doodle Disaster: Game Design (MVP)

Doodle Disaster is a 3–8 player drawing-and-guessing party game set in a chaotic 2.5D
classroom. Every player starts a sketchbook from a funny prompt; sketchbooks rotate,
alternating drawing and guessing, until everyone has touched every book. Then the whole
class watches a synchronized reveal and votes on anonymous awards.

This document describes the game **as implemented** in this repository.

## Core loop

```
WaitingForPlayers → Countdown → StartingMatch
  → Drawing → CollectingSubmissions → Guessing → CollectingSubmissions → … (N steps)
  → Reveal → AwardVoting → Results → ReturningToLobby → WaitingForPlayers
```

Phases live in `src/shared/Phases.luau` with an explicit transition table. The server
(`GameState.setPhase`) refuses illegal transitions; every in-match phase can abort to
`ReturningToLobby`. Clients never change phases; they only send requests.

| Phase | Duration (default) | What happens |
|---|---|---|
| WaitingForPlayers | until enough ready players | free roam, interactions on |
| Countdown | 15 s (public) / 5 s after host start | cancels if ready players drop below the minimum |
| StartingMatch | 4 s | desks assigned, players seated and frozen |
| Drawing | 60 s | draw the prompt or the previous guess |
| Guessing | 30 s | guess the previous drawing |
| CollectingSubmissions | 2 s | placeholders inserted, books pass to the next desk |
| Reveal | server-paced | each book: prompt → entries → "started as / ended as" |
| AwardVoting | 30 s (ends early if everyone voted) | anonymous ballot |
| Results | 12 s | winners and names revealed, Doodle Points granted |
| ReturningToLobby | 3 s | everyone released, next match can start |

All timers live in `src/shared/GameConfig.luau`. Each phase broadcasts an absolute
`endsAt` server timestamp (`workspace:GetServerTimeNow()`), so every client shows the same
countdown regardless of latency.

## Players, lobby and hosts

* 3–8 players per match (`GameConfig.MinPlayers` / `MaxPlayers`). Extra players and late
  joiners spectate until the next match.
* **Public servers:** a 15 s countdown starts automatically when at least 3 ready players
  are present. Players can toggle *Ready / Sitting out*. The longest-present player is the
  "class captain" and can change difficulty.
* **Private servers** (`game.PrivateServerId ~= ""` and an owner): the owner (or the
  longest-present player if the owner is absent) is host. Nothing starts automatically; the
  host presses **Start class** (≥3 ready players) and chooses difficulty.
* **Studio dev mode:** `GameConfig.DevMode` lowers the minimum to 1 *only* when
  `RunService:IsStudio()` is true, so it can't affect live servers. The HUD shows "DEV".

## Prompts and difficulty

Prompts (`src/shared/PromptPacks.luau`) have `Id, Phrase, Category, Difficulty, Pack,
Enabled`. Categories map to difficulty: Scenario → Easy, Idiom → Medium, Metaphor → Hard.
The free **Starter Chaos** pack already contains all three (20 / 16 / 12 prompts), so idioms
and metaphors are never locked behind progression.

| Difficulty | Easy | Medium | Hard |
|---|---|---|---|
| Casual Chaos | 70 | 25 | 5 |
| **Mixed Madness** (default) | 40 | 40 | 20 |
| Brain Meltdown | 10 | 40 | 50 |

`PromptSelector` rolls a difficulty per prompt by weight, never repeats a prompt within a
match, avoids the last 40 prompts used on the server while alternatives exist, and
redistributes weight if a difficulty runs dry.

### Unlockable packs

| Pack | Cost | Free after |
|---|---|---|
| Starter Chaos | free, always on | – |
| Brainrot | 60 pts | 8 matches |
| Everyday Disasters | 80 pts | 10 matches |
| Impossible Situations | 120 pts | 15 matches |

Each pack mixes difficulties. The match pool is Starter Chaos + every pack *enabled* by at
least one participant, so one player's unlocks add variety for everyone and nobody is
excluded from normal play.

## Sketchbook rotation

`src/shared/Rotation.luau`: with players indexed 1..N, at step `s` (0-based) player `p`
holds book `((p − 1 − s) mod N) + 1`. Book `b` starts with its owner (step 0) and moves one
desk each step. Over N steps each player touches each book exactly once and every book gets
N entries. Entries alternate Draw, Guess, Draw…, so the last entry is a drawing for odd N
and a guess for even N. `Rotation.validateSchedule` checks these rules and the tests run it
for N = 1..8.

Players see only the immediately preceding entry: the drawer gets the prompt (step 0) or
the previous guess; the guesser gets the previous drawing. If the previous guess was a
timeout placeholder, the drawer gets the most recent real text in that chain (falling back
to the original prompt) so a book never dies.

`src/server/Logic/MatchCore.luau` holds the authoritative per-match state and enforces
ownership, phase/step/kind, duplicate rejection and placeholder filling. It is pure Luau
with injected dependencies, so it is unit-tested without Roblox networking.

## Drawing

* Normalized integer coordinates 0–1000 on a 4:3 canvas; strokes are
  `{ c = colorIndex, w = brushIndex, p = { x1, y1, x2, y2, … } }`.
* 12 colours, 5 brush sizes, eraser (paper colour), undo, clear, submit, 60 s timer,
  auto-submit at 0. Mouse and touch input.
* Rendered with rotated, rounded `Frame`s (`DrawingRenderer`), so no physical parts are
  created and the same data renders on screen, on the projector and in voting thumbnails.
* Server validation (`DrawingTypes.validate`): types, integer ranges, NaN/inf, array shape,
  ≤250 strokes, ≤400 points/stroke, ≤3000 points total, payload budget, plus phase, step,
  ownership and duplicate checks in MatchCore. Blank pages are allowed but don't count as
  active participation.
* **Chaos Events (future):** `DrawingController.inputTransforms` lets a later update mirror,
  rotate or shake input without changing the stored format or validation.

## Guessing and text safety

Guesses are trimmed, whitespace-collapsed, UTF-8 checked and capped at 60 characters
(`TextRules`), rate-limited, then filtered with `TextService:FilterStringAsync` +
`GetNonChatStringForBroadcastAsync` before anyone else can see them. If filtering fails, the
original text is discarded and a safe placeholder is stored instead. Timeouts insert a
placeholder.

## Shared reveal

The server walks every book and fires `RevealEvent`s (`Book`, `Entry`, `BookEnd`,
`Finished`) on a fixed schedule; clients only render. The overlay and the classroom
projector show the same step. No author names are shown during the reveal (that would
de-anonymise voting). Movement is restored during the reveal, players can react with six
preset emoji reactions (shown above their heads and floating over the reveal), and can hide
the overlay to watch the projector. Late joiners are re-synced to the current book.

## Anonymous awards

Categories: Funniest Drawing, Biggest Disaster, Most Confusing Guess, Unexpected
Masterpiece. `VotingCore.buildBallot` samples up to 8 real (non-placeholder, non-blank)
entries per kind in random order and labels them "Doodle 3" / "Guess 5" with opaque ids.
Book index, author and order metadata stay on the server. Each voter is told only which
candidates are *their own* so the UI can disable them. The server rejects self-votes,
duplicate votes, unknown categories/candidates, non-voters and votes outside the phase.
Ties share the award; categories with fewer than two candidates are skipped; a category
with no votes has no winner. Names are revealed only after voting closes.

## Progression and persistence

* Legitimate completion = still in the server at Results **and** actively submitted at
  least 50% of their tasks (blank pages and timeouts don't count): **+20 Doodle Points**.
* Each award won: **+5** (only for legitimate completers).
* `RewardManager` grants once per `matchId:userId`; clients never send reward values.
* `PlayerDataManager` stores `points, matchesCompleted, awardsEarned, unlockedPacks,
  enabledPacks` in DataStore `DoodleDisaster_PlayerData_v1`. Loads retry 3×; if loading
  fails the session uses a temporary profile that is **never saved**, so existing data
  can't be overwritten with defaults. Saves use `UpdateAsync` with a `saveCount` guard,
  autosave every 120 s, on leave, and on `BindToClose`.

## Classroom and camera

`ClassroomBuilder` builds the room procedurally: checkerboard wooden floor, coloured walls,
low front wall, invisible barriers and ceiling, eight colour-coded desks with seats and
name labels in two rows facing a giant projector screen, central craft table, chalkboard,
posters, windows, bookshelf, giant crayons, paint splats, teacher's desk, projector cart
with a light beam.

The camera (`CameraController`) is a Scriptable camera re-applied every frame: fixed angle,
no rotation or zoom, FOV widened on narrow screens, gentle ease toward the projector during
the reveal. Movement uses default Roblox controls (WASD, gamepad, mobile thumbstick);
emotes work through the default `/e` chat commands and emote menu.

During seated phases the **server** assigns desks, seats players and zeroes WalkSpeed /
JumpHeight (authoritative); the client also disables its control module. Respawning
players are re-seated; everyone is released (and placed beside their desk) afterwards.

### Interactions (cosmetic, disabled while seated)

* **Chalkboard** – rotating messages and lobby info; *Read* shows a joke.
* **Trash can** – *Throw paper ball*: a server-simulated paper ball arcs into the bin
  (per-player cooldown, global cap).
* **Suspicious button** – random harmless effect (confetti, disco lights, rubber-duck rain,
  a bounce) with an 8 s global cooldown.
* **Golden pencil** – shows the latest award winner.

## Security model

All client → server remotes go through `Net.on`, which applies a per-player rate limit and
isolates errors. Every handler validates types and phase. Server state (phase, books,
prompts, votes, points) is never accepted from clients.

## Future work hooks

* **Custom prompts / monetisation:** `CustomPromptService` contains validation, filtering
  (anything altered by the filter is rejected), a pending/approved/rejected queue and an
  idempotent `processReceipt` skeleton. It is disabled, not wired to any remote, no
  `ProcessReceipt` is assigned and **no product ID exists**. Its header lists the steps to
  enable it.
* **Chaos Events:** drawing input transforms (see Drawing).

## Code map

```
src/shared        GameConfig, PromptPacks, Phases, Rotation, DrawingTypes, DrawingRenderer,
                  TextRules, RemoteDefinitions
src/server/Logic  MatchCore, VotingCore, PromptSelector, Rewards, RateLimiter   (pure, tested)
src/server/Services
                  GameManager (boot + loop), GameState, Net, LobbyManager, RoundManager,
                  VotingManager, RewardManager, PlayerDataManager, PromptManager,
                  StationManager, ClassroomBuilder, ClassroomInteractionManager,
                  TextFilter, CustomPromptService
src/client        Main + Controllers: ClientState, Ui, CameraController, MovementController,
                  UIController, DrawingController, GuessController, RevealController,
                  VotingController
tests             TestRunner + specs (Rotation, MatchCore, DrawingTypes, PromptSelector,
                  VotingCore, Rules)
```
