--!strict
-- RemoteDefinitions: names of every RemoteEvent. The server creates them in
-- ReplicatedStorage.Remotes at boot; clients wait for them. All client -> server
-- events are treated as untrusted requests and validated by the server.

local RemoteDefinitions = {}

RemoteDefinitions.FolderName = "Remotes"

RemoteDefinitions.Events = {
	-- server -> client
	"StateChanged", -- (snapshot) phase, timer, roster, settings
	"TaskAssigned", -- (task) the player's personal draw/guess task for this step
	"TaskCleared", -- () hide task UI (step ended / submission accepted)
	"RevealEvent", -- (event) shared reveal presentation step
	"VotingOpened", -- (ballot) anonymous candidates
	"VotingClosed", -- (results) winners with names revealed
	"ProfileUpdated", -- (profile) points, packs
	"Notify", -- (text, kind?) toast message
	"ReactionShown", -- (userId, reactionIndex)
	"VoteResult", -- (categoryId, candidateId, ok, reason)
	"RevealSkipStatus", -- ({ entry, book, needed, entrySeq, bookSeq }) fast-forward vote tallies

	-- client -> server
	"RequestSync", -- () ask for the current snapshot + task + profile
	"SubmitDrawing", -- (step, drawing)
	"SubmitGuess", -- (step, text)
	"CastVote", -- (categoryId, candidateId)
	"SendReaction", -- (reactionIndex)
	"RevealSkipVote", -- (scope: "Entry" | "Book") vote to fast-forward the reveal
	"SetReady", -- (bool)
	"HostStart", -- ()
	"SetDifficulty", -- (difficultyId) host only
	"UnlockPack", -- (packId)
	"TogglePack", -- (packId, enabled)
}

return RemoteDefinitions
