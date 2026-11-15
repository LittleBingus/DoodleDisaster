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
	-- Testing baseline after the first alpha (15 felt rushed). Compare 20, 25, 30 and 35 by
	-- changing this one number; the server deadline and every client timer follow it.
	Guessing = 25,
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
	CasualChaos = { DisplayName = "Casual Chaos", ShortName = "Casual", Emoji = "😌",
		Subtitle = "Class dismissed! Common sense is optional.",
		Weights = { Easy = 70, Medium = 25, Hard = 5 } },
	MixedMadness = { DisplayName = "Mixed Madness", ShortName = "Mixed", Emoji = "🎲",
		Subtitle = "A little bit of everything. What could go wrong?",
		Weights = { Easy = 40, Medium = 40, Hard = 20 } },
	BrainMeltdown = { DisplayName = "Brain Meltdown", ShortName = "Meltdown", Emoji = "🤯",
		Subtitle = "The class has chosen suffering!",
		Weights = { Easy = 10, Medium = 40, Hard = 50 } },
}
GameConfig.DifficultyOrder = { "CasualChaos", "MixedMadness", "BrainMeltdown" }
-- The mode is chosen by a lobby vote (see ModeVote). This one is used when nobody votes and
-- wins any tie it is part of.
GameConfig.DefaultDifficulty = "MixedMadness"

-- How many of the previous match's prompts to avoid repeating.
GameConfig.PromptHistorySize = 40

GameConfig.Guess = {
	MaxLength = 60,
	TimeoutPlaceholder = "(ran out of time and shrugged)",
	LeftPlaceholder = "(the guesser fled the classroom)",
	-- Used when Roblox's text filter censors a guess completely (or nearly), or filtering
	-- fails. One is picked at random and becomes the next player's drawing prompt. These are
	-- developer-written and never derived from what the player typed.
	FallbackPhrases = {
		"a potato with a law degree",
		"the homework that ate the dog",
		"a very polite tornado",
		"grandma's secret wrestling career",
		"a pigeon running for class president",
		"spaghetti in a business suit",
		"the moon wearing sunglasses",
		"a goldfish learning to drive",
		"a sandwich with trust issues",
		"the world's slowest rocket",
		"a cactus giving free hugs",
		"a ghost who is scared of people",
		"a dinosaur at the dentist",
		"an octopus knitting eight scarves",
		"a snowman on a beach holiday",
		"the substitute teacher is a duck",
		"a robot afraid of toasters",
		"a cloud that forgot how to rain",
		"a penguin delivering pizza",
		"a wizard stuck in an elevator",
		"a cow jumping over the wrong moon",
		"a superhero whose power is napping",
		"a shark at a pool party",
		"a pirate who gets seasick",
	},
}

-- Hide / report controls for drawings (see ModerationManager).
GameConfig.Moderation = {
	ReportsPerMatch = 4, -- per player
	ReportsPerSession = 12, -- per player, per server
	-- Reports are saved (with the drawing) so the owner can review them. Studio uses its own
	-- store; nothing here ever touches player progression.
	ReportStoreName = "DoodleDisaster_Reports_Alpha_v1",
	StudioReportStoreName = "DoodleDisaster_Reports_Dev_v1",
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
	Report = { Count = 3, Window = 10 },
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
-- Published servers use DataStoreName. It points at the ALPHA store while the game is in
-- friends-only testing so alpha play can never touch ProductionDataStoreName. Switching to
-- ProductionDataStoreName is the one-line change for a real launch.
GameConfig.ProductionDataStoreName = "DoodleDisaster_PlayerData_v1"
GameConfig.AlphaDataStoreName = "DoodleDisaster_PlayerData_Alpha_v1"
GameConfig.DataStoreName = GameConfig.AlphaDataStoreName
GameConfig.StudioDataStoreName = "DoodleDisaster_PlayerData_Dev_v1"
GameConfig.AutosaveInterval = 120

return GameConfig
