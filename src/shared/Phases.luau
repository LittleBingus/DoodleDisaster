--!strict
-- Phases: the match state machine definition. Pure logic.

local Phases = {}

Phases.WaitingForPlayers = "WaitingForPlayers"
Phases.Countdown = "Countdown"
Phases.StartingMatch = "StartingMatch"
Phases.Drawing = "Drawing"
Phases.Guessing = "Guessing"
Phases.CollectingSubmissions = "CollectingSubmissions"
Phases.Reveal = "Reveal"
Phases.AwardVoting = "AwardVoting"
Phases.Results = "Results"
Phases.ReturningToLobby = "ReturningToLobby"

-- Allowed transitions. ReturningToLobby is reachable from every in-match phase so a
-- match can always abort safely (e.g. too many players left).
Phases.Transitions = {
	WaitingForPlayers = { Countdown = true, StartingMatch = true },
	Countdown = { WaitingForPlayers = true, StartingMatch = true },
	StartingMatch = { Drawing = true, ReturningToLobby = true },
	Drawing = { CollectingSubmissions = true, ReturningToLobby = true },
	Guessing = { CollectingSubmissions = true, ReturningToLobby = true },
	CollectingSubmissions = { Drawing = true, Guessing = true, Reveal = true, ReturningToLobby = true },
	Reveal = { AwardVoting = true, Results = true, ReturningToLobby = true },
	AwardVoting = { Results = true, ReturningToLobby = true },
	Results = { ReturningToLobby = true },
	ReturningToLobby = { WaitingForPlayers = true },
} :: { [string]: { [string]: boolean } }

function Phases.canTransition(from: string, to: string): boolean
	local allowed = Phases.Transitions[from]
	return allowed ~= nil and allowed[to] == true
end

-- Phases where players are seated at stations and free movement is disabled.
Phases.Seated = {
	StartingMatch = true,
	Drawing = true,
	Guessing = true,
	CollectingSubmissions = true,
} :: { [string]: boolean }

-- Phases in which a match is in progress (late joiners spectate).
Phases.InMatch = {
	StartingMatch = true,
	Drawing = true,
	Guessing = true,
	CollectingSubmissions = true,
	Reveal = true,
	AwardVoting = true,
	Results = true,
} :: { [string]: boolean }

Phases.DisplayNames = {
	WaitingForPlayers = "Waiting for players",
	Countdown = "Class starts soon!",
	StartingMatch = "Handing out sketchbooks",
	Drawing = "DRAW!",
	Guessing = "GUESS!",
	CollectingSubmissions = "Passing sketchbooks",
	Reveal = "The Big Reveal",
	AwardVoting = "Award voting",
	Results = "Results",
	ReturningToLobby = "Back to recess",
} :: { [string]: string }

return Phases
