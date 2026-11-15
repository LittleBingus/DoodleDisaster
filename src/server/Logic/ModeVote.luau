--!strict
-- ModeVote: democratic game-mode voting in the lobby. Pure logic (rng injected).
--
-- Every eligible player has one vote and may change it until the match starts. Only the
-- votes of the players who actually start the match are counted, so sitting-out players,
-- spectators and leavers never influence the result. The host has no extra say.
--
-- Winner: most votes. If the default mode is among the tied leaders it wins the tie,
-- otherwise the tie is broken at random. No votes at all = the default mode.

local ModeVote = {}
ModeVote.__index = ModeVote

function ModeVote.new(modes: { string }, defaultMode: string)
	local self = setmetatable({}, ModeVote)
	self.modes = table.clone(modes)
	self.valid = {} :: { [string]: boolean }
	for _, id in modes do
		self.valid[id] = true
	end
	assert(self.valid[defaultMode], "default mode must be one of the modes")
	self.defaultMode = defaultMode
	self.votes = {} :: { [number]: string }
	return self
end

-- Records or changes a vote. Returns false for anything that is not a known mode id.
function ModeVote.cast(self, userId: number, modeId: any): boolean
	if type(modeId) ~= "string" or not self.valid[modeId] then
		return false
	end
	self.votes[userId] = modeId
	return true
end

function ModeVote.remove(self, userId: number)
	self.votes[userId] = nil
end

function ModeVote.clear(self)
	self.votes = {}
end

function ModeVote.voteOf(self, userId: number): string?
	return self.votes[userId]
end

-- Vote counts per mode, counting only `eligible` voters.
function ModeVote.tally(self, eligible: { number }): { [string]: number }
	local counts = {}
	for _, id in self.modes do
		counts[id] = 0
	end
	local seen = {}
	for _, userId in eligible do
		local vote = self.votes[userId]
		if vote and not seen[userId] then
			seen[userId] = true
			counts[vote] += 1
		end
	end
	return counts
end

-- Returns (winningMode, info) where info = { counts, tied = { modeIds }, votes = total }.
function ModeVote.pick(self, eligible: { number }, rng: () -> number)
	local counts = self:tally(eligible)
	local best, total = 0, 0
	for _, id in self.modes do
		best = math.max(best, counts[id])
		total += counts[id]
	end
	if total == 0 then
		return self.defaultMode, { counts = counts, tied = {}, votes = 0 }
	end
	local tied = {}
	for _, id in self.modes do
		if counts[id] == best then
			table.insert(tied, id)
		end
	end
	local winner = tied[1]
	if #tied > 1 then
		if table.find(tied, self.defaultMode) then
			winner = self.defaultMode
		else
			winner = tied[math.clamp(math.floor(rng() * #tied) + 1, 1, #tied)]
		end
	end
	return winner, { counts = counts, tied = if #tied > 1 then tied else {}, votes = total }
end

return ModeVote
