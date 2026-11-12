--!strict
-- VotingCore: anonymous award voting. Pure logic (rng injected).
--
-- buildBallot() turns authored entries into anonymous candidates. The public ballot
-- contains only opaque ids, generic labels ("Doodle 3") and the content itself, in a
-- shuffled order. Authorship stays in the private `authorOf` map on the server until
-- voting closes.
--
-- Tie rule: every candidate tied for the most votes wins (awards are shared). A category
-- with zero votes has no winner. Categories with fewer than 2 candidates are skipped.

local VotingCore = {}
VotingCore.__index = VotingCore

local function shuffle<T>(list: { T }, rng: () -> number): { T }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = math.clamp(math.floor(rng() * i) + 1, 1, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

-- entriesByKind: { Draw = { {author, content, ...} }, Guess = {...} }
-- categories: GameConfig.Voting.Categories
function VotingCore.buildBallot(entriesByKind: { [string]: { any } }, categories: { any }, maxPerCategory: number, rng: () -> number)
	local authorOf: { [string]: number } = {}
	local sourceOf: { [string]: any } = {}
	local poolByKind: { [string]: { any } } = {}

	-- One shared, shuffled candidate pool per kind so the same drawing keeps the same
	-- anonymous label across the drawing categories.
	for kind, entries in entriesByKind do
		local sample = shuffle(entries, rng)
		local pool = {}
		for i = 1, math.min(#sample, maxPerCategory) do
			local e = sample[i]
			local id = string.format("%s%d", if kind == "Draw" then "D" else "G", i)
			authorOf[id] = e.author
			sourceOf[id] = { bookIndex = e.bookIndex, entryIndex = e.entryIndex }
			table.insert(pool, {
				id = id,
				label = string.format("%s %d", if kind == "Draw" then "Doodle" else "Guess", i),
				kind = kind,
				content = e.content,
			})
		end
		poolByKind[kind] = pool
	end

	local ballotCategories = {}
	for _, cat in categories do
		local pool = poolByKind[cat.Kind] or {}
		if #pool >= 2 then
			table.insert(ballotCategories, {
				id = cat.Id,
				displayName = cat.DisplayName,
				kind = cat.Kind,
				candidateIds = (function()
					local ids = {}
					for _, c in pool do
						table.insert(ids, c.id)
					end
					return ids
				end)(),
			})
		end
	end

	local candidates = {}
	for _, pool in poolByKind do
		for _, c in pool do
			candidates[c.id] = c
		end
	end

	return {
		categories = ballotCategories,
		candidates = candidates,
	}, authorOf, sourceOf
end

function VotingCore.new(ballot: any, authorOf: { [string]: number }, voterIds: { number })
	local self = setmetatable({}, VotingCore)
	self.ballot = ballot
	self.authorOf = authorOf
	self.voters = {} :: { [number]: boolean }
	for _, id in voterIds do
		self.voters[id] = true
	end
	self.categoryById = {} :: { [string]: any }
	for _, cat in ballot.categories do
		local set = {}
		for _, cid in cat.candidateIds do
			set[cid] = true
		end
		self.categoryById[cat.id] = { cat = cat, set = set }
	end
	self.votes = {} :: { [string]: { [number]: string } } -- categoryId -> voter -> candidateId
	self.open = true
	return self
end

function VotingCore.cast(self, voterId: number, categoryId: any, candidateId: any): (boolean, string?)
	if not self.open then
		return false, "voting closed"
	end
	if not self.voters[voterId] then
		return false, "not an eligible voter"
	end
	if type(categoryId) ~= "string" or type(candidateId) ~= "string" then
		return false, "bad vote"
	end
	local entry = self.categoryById[categoryId]
	if not entry then
		return false, "unknown category"
	end
	if not entry.set[candidateId] then
		return false, "unknown candidate"
	end
	if self.authorOf[candidateId] == voterId then
		return false, "you can't vote for yourself"
	end
	local catVotes = self.votes[categoryId]
	if not catVotes then
		catVotes = {}
		self.votes[categoryId] = catVotes
	end
	if catVotes[voterId] then
		return false, "already voted in this category"
	end
	catVotes[voterId] = candidateId
	return true, nil
end

function VotingCore.removeVoter(self, voterId: number)
	self.voters[voterId] = nil
	for _, catVotes in self.votes do
		catVotes[voterId] = nil
	end
end

function VotingCore.hasVotedEverywhere(self, voterId: number): boolean
	for _, cat in self.ballot.categories do
		-- a category where every candidate is the voter's own can't be voted in
		local canVote = false
		for _, cid in cat.candidateIds do
			if self.authorOf[cid] ~= voterId then
				canVote = true
				break
			end
		end
		if canVote then
			local catVotes = self.votes[cat.id]
			if not catVotes or not catVotes[voterId] then
				return false
			end
		end
	end
	return true
end

function VotingCore.allVoted(self): boolean
	for voterId in self.voters do
		if not self:hasVotedEverywhere(voterId) then
			return false
		end
	end
	return true
end

-- Closes voting and returns winners: { { categoryId, displayName, candidateIds, authorIds, votes } }
-- plus awardCounts { [userId]: number }.
function VotingCore.close(self)
	self.open = false
	local results = {}
	local awardCounts: { [number]: number } = {}
	for _, cat in self.ballot.categories do
		local tally: { [string]: number } = {}
		for voterId, cid in self.votes[cat.id] or {} do
			if self.voters[voterId] then
				tally[cid] = (tally[cid] or 0) + 1
			end
		end
		local best = 0
		for _, count in tally do
			best = math.max(best, count)
		end
		local winners, authors = {}, {}
		if best > 0 then
			-- iterate in ballot order for deterministic output
			for _, cid in cat.candidateIds do
				if tally[cid] == best then
					table.insert(winners, cid)
					local author = self.authorOf[cid]
					if author and not table.find(authors, author) then
						table.insert(authors, author)
					end
				end
			end
		end
		for _, author in authors do
			awardCounts[author] = (awardCounts[author] or 0) + 1
		end
		table.insert(results, {
			categoryId = cat.id,
			displayName = cat.displayName,
			candidateIds = winners,
			authorIds = authors,
			votes = best,
		})
	end
	return results, awardCounts
end

return VotingCore
