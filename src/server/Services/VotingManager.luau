--!strict
-- VotingManager: runs the anonymous award voting phase.
-- Clients only ever see opaque candidate ids ("D3"), generic labels ("Doodle 3") and the
-- content. Each voter is additionally told which candidates are their own (so the UI can
-- disable them); nobody learns anyone else's authorship until voting closes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.GameConfig)
local Phases = require(Shared.Phases)
local VotingCore = require(script.Parent.Parent.Logic.VotingCore)
local GameState = require(script.Parent.GameState)
local Net = require(script.Parent.Net)

local VotingManager = {}

local session: any = nil
local publicBallot: any = nil
local authorOfCurrent: { [string]: number } = {}

local function ballotFor(player: Player)
	local mine = {}
	for cid, author in authorOfCurrent do
		if author == player.UserId then
			table.insert(mine, cid)
		end
	end
	return {
		categories = publicBallot.categories,
		candidates = publicBallot.candidates,
		mine = mine,
		canVote = session ~= nil and session.voters[player.UserId] == true,
		endsAt = GameState.endsAt,
	}
end

function VotingManager.sendBallot(player: Player)
	if session and publicBallot and GameState.phase == Phases.AwardVoting then
		Net.fire(player, "VotingOpened", ballotFor(player))
	end
end

-- Runs the whole voting phase. Returns (displayResults, awardCounts).
function VotingManager.run(core: any, voters: { Player })
	local rng = Random.new()
	local entriesByKind = {
		Draw = core:getEntries("Draw"),
		Guess = core:getEntries("Guess"),
	}
	local ballot, authorOf = VotingCore.buildBallot(entriesByKind, GameConfig.Voting.Categories,
		GameConfig.Voting.MaxCandidatesPerCategory, function()
			return rng:NextNumber()
		end)
	if #ballot.categories == 0 then
		return {}, {}
	end
	local voterIds = {}
	for _, p in voters do
		if p.Parent == Players then
			table.insert(voterIds, p.UserId)
		end
	end
	session = VotingCore.new(ballot, authorOf, voterIds)
	publicBallot = ballot
	authorOfCurrent = authorOf

	GameState.setPhase(Phases.AwardVoting, GameConfig.Timers.AwardVoting)
	for _, p in Players:GetPlayers() do
		VotingManager.sendBallot(p)
	end

	local deadline = os.clock() + GameConfig.Timers.AwardVoting
	while os.clock() < deadline do
		if session:allVoted() then
			break
		end
		task.wait(0.25)
	end

	local results, awardCounts = session:close()
	-- Build display results with names revealed now that voting is over.
	local display = {}
	for _, r in results do
		local winners = {}
		for _, cid in r.candidateIds do
			local c = ballot.candidates[cid]
			local author = authorOf[cid]
			local authorPlayer = if author then Players:GetPlayerByUserId(author) else nil
			table.insert(winners, {
				label = c.label,
				kind = c.kind,
				content = c.content,
				authorName = if authorPlayer then authorPlayer.DisplayName else "A mysterious artist",
			})
		end
		table.insert(display, { displayName = r.displayName, votes = r.votes, winners = winners })
	end
	session = nil
	publicBallot = nil
	authorOfCurrent = {}
	Net.fireAll("VotingClosed", display)
	return display, awardCounts
end

function VotingManager.init()
	Net.on("CastVote", GameConfig.RateLimits.Vote, function(player, categoryId, candidateId)
		if not session or GameState.phase ~= Phases.AwardVoting then
			Net.fire(player, "VoteResult", categoryId, candidateId, false, "Voting is closed.")
			return
		end
		local ok, reason = session:cast(player.UserId, categoryId, candidateId)
		Net.fire(player, "VoteResult", categoryId, candidateId, ok, reason)
	end)
	Players.PlayerRemoving:Connect(function(player)
		if session then
			session:removeVoter(player.UserId)
		end
	end)
end

return VotingManager
