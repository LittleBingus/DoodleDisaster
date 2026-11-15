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
local ModerationManager = require(script.Parent.ModerationManager)

local VotingManager = {}

local session: any = nil
local publicBallot: any = nil
local authorOfCurrent: { [string]: number } = {}
-- Display names of everyone seen this session, so a winner who left is still credited.
local knownNames: { [number]: string } = {}

local function ballotFor(player: Player)
	local mine = {}
	for cid, author in authorOfCurrent do
		if author == player.UserId then
			table.insert(mine, cid)
		end
	end
	-- Drawings by an artist this player reported are sent without their strokes.
	local candidates = {}
	for cid, c in publicBallot.candidates do
		if c.kind == "Draw" and ModerationManager.isBlocked(player.UserId, authorOfCurrent[cid]) then
			local copy = table.clone(c)
			copy.content = nil
			copy.hidden = true
			candidates[cid] = copy
		else
			candidates[cid] = c
		end
	end
	return {
		categories = publicBallot.categories,
		candidates = candidates,
		mine = mine,
		canVote = session ~= nil and session.voters[player.UserId] == true,
		endsAt = GameState.endsAt,
	}
end

-- The results as this player should see them: winning drawings by an artist they reported
-- are replaced by a placeholder.
function VotingManager.resultsFor(player: Player, display: { any }): { any }
	local out = {}
	for i, r in display do
		local winners = {}
		for j, w in r.winners do
			if w.kind == "Draw" and ModerationManager.hiddenFor(player.UserId, w.drawId) then
				local copy = table.clone(w)
				copy.content = nil
				copy.hidden = true
				winners[j] = copy
			else
				winners[j] = w
			end
		end
		out[i] = { displayName = r.displayName, votes = r.votes, winners = winners }
	end
	return out
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
		-- Nothing to vote on: still tell clients, so the results screen doesn't show a previous match.
		Net.fireAll("VotingClosed", {})
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
			table.insert(winners, {
				label = c.label,
				kind = c.kind,
				content = c.content,
				drawId = c.drawId,
				authorName = (author and knownNames[author]) or "A mysterious artist",
			})
		end
		table.insert(display, { displayName = r.displayName, votes = r.votes, winners = winners })
	end
	session = nil
	publicBallot = nil
	authorOfCurrent = {}
	for _, p in Players:GetPlayers() do
		Net.fire(p, "VotingClosed", VotingManager.resultsFor(p, display))
	end
	return display, awardCounts
end

function VotingManager.init()
	local function remember(player: Player)
		knownNames[player.UserId] = player.DisplayName
	end
	Players.PlayerAdded:Connect(remember)
	for _, p in Players:GetPlayers() do
		remember(p)
	end
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
