--!strict
-- GameConfig: every tunable number in Doodle Disaster lives here.
-- Pure data: safe to require from server, client and the standalone test runner.

local GameConfig = {}

GameConfig.MinPlayers = 3
GameConfig.MaxPlayers = 8

-- Development mode lets a single tester run full matches in Roblox Studio.
-- The server only honours it when RunService:IsStudio() is true, so it can never
-- lower the player requirement on a live server (see GameManager.getMinPlayers).
GameConfig.DevMode = {
	Enabled = true,
	MinPlayers = 1,
}

GameConfig.Timers = {
	LobbyCountdown = 15,
	StartingMatch = 4,
	Drawing = 60,
	Guessing = 15,
	-- Extra time after a deadline for in-flight submissions (client auto-submits at 0).
	SubmissionGrace = 2,
	CollectingSubmissions = 2,
	RevealIntro = 2, -- title card for each sketchbook
	RevealEntry = 3, -- each prompt / drawing / guess on screen
	RevealBookOutro = 1.5,
	-- A majority skip vote can't cut a reveal step shorter than this, so it can still be read.
	RevealMinRead = 1.2,
	AwardVoting = 20,
	Results = 12,
	ReturningToLobby = 3,
}

GameConfig.Difficulties = {
	CasualChaos = { DisplayName = "Casual Chaos", Weights = { Easy = 70, Medium = 25, Hard = 5 } },
	MixedMadness = { DisplayName = "Mixed Madness", Weights = { Easy = 40, Medium = 40, Hard = 20 } },
	BrainMeltdown = { DisplayName = "Brain Meltdown", Weights = { Easy = 10, Medium = 40, Hard = 50 } },
}
GameConfig.DifficultyOrder = { "CasualChaos", "MixedMadness", "BrainMeltdown" }
GameConfig.DefaultDifficulty = "MixedMadness"

-- How many of the previous match's prompts to avoid repeating.
GameConfig.PromptHistorySize = 40

GameConfig.Guess = {
	MaxLength = 60,
	TimeoutPlaceholder = "(ran out of time and shrugged)",
	FilterFailedPlaceholder = "(this guess got lost in the mail)",
	LeftPlaceholder = "(the guesser fled the classroom)",
}

GameConfig.Rewards = {
	MatchCompletion = 20,
	AwardBonus = 5,
	-- A player must actively submit at least this share of their tasks to count as
	-- having legitimately completed a match (prevents AFK farming).
	MinActiveSubmissionRatio = 0.5,
}

GameConfig.Voting = {
	MaxCandidatesPerCategory = 8,
	Categories = {
		{ Id = "Funniest", DisplayName = "Funniest Drawing", Kind = "Draw" },
		{ Id = "Disaster", DisplayName = "Biggest Disaster", Kind = "Draw" },
		{ Id = "Confusing", DisplayName = "Most Confusing Guess", Kind = "Guess" },
		{ Id = "Masterpiece", DisplayName = "Unexpected Masterpiece", Kind = "Draw" },
	},
}

GameConfig.RateLimits = {
	-- tokens per window (seconds)
	Submit = { Count = 4, Window = 5 },
	Vote = { Count = 12, Window = 5 },
	Reaction = { Count = 6, Window = 4 },
	RevealSkip = { Count = 8, Window = 4 },
	Lobby = { Count = 6, Window = 3 },
	Packs = { Count = 5, Window = 3 },
}

GameConfig.Reactions = { "😂", "😱", "🔥", "🤔", "💀", "👏" }

GameConfig.Interactions = {
	SuspiciousButtonCooldown = 8,
	PaperBallCooldown = 1.5,
	MaxPaperBalls = 25,
}

-- Future monetisation. Everything is disabled; no product IDs are defined on purpose.
GameConfig.CustomPrompts = {
	Enabled = false,
	MinLength = 4,
	MaxLength = 60,
	-- Fill in only with a real Developer Product ID created on the Creator Dashboard.
	DeveloperProductId = nil :: number?,
}

-- Player progression stores. The server picks one in PlayerDataManager using
-- RunService:IsStudio(), so Studio playtests never read or write live progression.
GameConfig.DataStoreName = "DoodleDisaster_PlayerData_v1"
GameConfig.StudioDataStoreName = "DoodleDisaster_PlayerData_Dev_v1"
GameConfig.AutosaveInterval = 120

return GameConfig
